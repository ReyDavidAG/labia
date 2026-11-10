import AppKit
import LabiaCore

/// Un dictado que escribe mientras se habla, como `Dictation` en `linux/labia/app.py`.
/// Graba desde que se presiona el atajo; si el dictado anterior todavía está escribiendo su pasada final,
/// espera a que termine antes de escribir.
@MainActor
final class LiveDictation {
	/// Segundos entre pasadas. Si una pasada tarda más, la siguiente empieza en cuanto termina.
	nonisolated static let step = 0.5
	/// Claude Code dobla un pegado largo en «[Pasted text #1]»: el texto largo se pega por pedazos.
	nonisolated static let chunk = 400

	/// Por qué el texto final no quedó escrito y se dejó en el portapapeles.
	enum Miss: Equatable {
		/// La app no leyó el pegado (no hay campo de texto, o se tardó demasiado).
		case unread
		/// Cambiaste de app, hiciste clic o tecleaste: corregir ahí borraría otra cosa.
		case moved
	}

	/// Clics y teclas del usuario; si cambia entre dos escrituras, el cursor pudo moverse.
	static var userInput = 0

	private struct Place: Equatable {
		let app: pid_t?
		let input: Int

		@MainActor static var now: Place {
			Place(app: NSWorkspace.shared.frontmostApplication?.processIdentifier, input: LiveDictation.userInput)
		}
	}

	let session: LiveSession
	private let transcriber: Transcriber
	private let recorder: Recorder
	private let settings: Preferences
	private var listening = true
	private var stalled = false
	private var moved = false
	/// Hubo un cambio que ya no se pudo escribir.
	private var missed = false
	/// Dónde se escribió la primera vez; si después el cursor está en otro lado, se deja de corregir.
	private var place: Place?
	private var pulled = 0
	private var loop: Task<Void, Never>?
	private var saved: [NSPasteboardItem]?

	init(settings: Preferences, transcriber: Transcriber, recorder: Recorder) {
		self.settings = settings
		self.transcriber = transcriber
		self.recorder = recorder
		session = LiveSession(preferences: settings)
	}

	func start(after previous: Task<Void, Never>?) {
		loop = Task {
			await previous?.value
			saved = settings.restoreClipboard ? Paster.snapshot() : nil
			while listening {
				let started = ContinuousClock.now
				if pull() > 0, let (audio, kind) = session.nextPass() {
					if let words = try? await transcriber.words(audio, kind: kind, language: settings.language) {
						let (back, text) = session.absorb(words, kind: kind)
						await type(back, text)
					}
				}
				let wait = Duration.seconds(Self.step) - (ContinuousClock.now - started)
				if wait > .zero { try? await Task.sleep(for: wait) }
			}
		}
	}

	/// Deja de leer el micrófono. Va antes de `recorder.stop()`: el siguiente dictado reutiliza la grabadora.
	func stopListening() {
		listening = false
	}

	/// Pasada final sobre toda la grabación (con vocabulario y cortes en pausas) y corrección de lo escrito.
	/// Si no se pudo escribir todo, el texto completo queda en el portapapeles y regresa por qué.
	func finish(_ samples: [Float]) async throws -> (text: String, miss: Miss?) {
		stopListening()
		await loop?.value
		if samples.count > pulled { session.feed(Array(samples[pulled...])) }
		do {
			let raw = try await transcriber.transcribe(samples, prompt: settings.prompt, language: settings.language)
			let (back, text, send) = session.finish(raw: raw)
			await type(back, text)
			let final = session.typed.trimmingCharacters(in: .whitespacesAndNewlines)
			if missed {
				saved = nil
				Paster.copy(final)
				return (final, stalled ? .unread : .moved)
			}
			if send, !moved {
				try? await Task.sleep(for: .milliseconds(150))
				Paster.pressReturn()
			}
			await end()
			return (final, nil)
		} catch {
			await end()
			throw error
		}
	}

	/// Cancelado: borra lo que ya se escribió.
	func cancel() async {
		stopListening()
		await loop?.value
		await type(session.discard(), "")
		await end()
	}

	private func pull() -> Int {
		let new = recorder.samples(from: pulled)
		pulled += new.count
		session.feed(new)
		return new.count
	}

	private func type(_ back: Int, _ text: String) async {
		guard back > 0 || !text.isEmpty else { return }
		if let place, place != .now { moved = true }
		// Si la app no leyó un pegado o el cursor se movió, no se sigue mandando nada a ciegas.
		guard !stalled, !moved else {
			if back > 0 || !text.trimmingCharacters(in: .whitespaces).isEmpty { missed = true }
			return
		}
		Paster.deleteBackward(back)
		// La app procesa los retrocesos antes de leer el pegado.
		var timeout = Paster.readTimeout + .milliseconds(5 * back)
		var rest = Substring(text)
		while !rest.isEmpty {
			let piece = rest.prefix(Self.chunk)
			rest = rest.dropFirst(piece.count)
			let body = piece.replacingOccurrences(of: #" +$"#, with: "", options: .regularExpression)
			if !body.isEmpty, !(await Paster.pasteAndWait(body, timeout: timeout)) {
				stalled = true
				missed = true
				return
			}
			timeout = Paster.readTimeout
			// Algunas terminales recortan los espacios del final de un pegado: esos van como teclas.
			Paster.typeSpaces(piece.count - body.count)
		}
		place = place ?? .now
	}

	private func end() async {
		if let saved {
			try? await Task.sleep(for: .milliseconds(100))
			Paster.restoreIfUntouched(saved)
		} else if !session.typed.isEmpty, NSPasteboard.general.changeCount == Paster.pastedCount {
			// Sin restaurar, el dictado completo se queda en el portapapeles, no sólo el último pedazo.
			Paster.copy(session.typed)
		}
		saved = nil
	}
}
