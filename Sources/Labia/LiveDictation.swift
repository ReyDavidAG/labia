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

	let session: LiveSession
	private let transcriber: Transcriber
	private let recorder: Recorder
	private let settings: Preferences
	private var listening = true
	private var stalled = false
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
	func finish(_ samples: [Float]) async throws -> (text: String, send: Bool) {
		stopListening()
		await loop?.value
		if samples.count > pulled { session.feed(Array(samples[pulled...])) }
		do {
			let raw = try await transcriber.transcribe(samples, prompt: settings.prompt, language: settings.language)
			let (back, text, send) = session.finish(raw: raw)
			await type(back, text)
			if send, !stalled {
				try? await Task.sleep(for: .milliseconds(150))
				Paster.pressReturn()
			}
			await end()
			return (session.typed.trimmingCharacters(in: .whitespacesAndNewlines), send)
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
		// Si la app no leyó un pegado (no hay campo de texto), no se sigue mandando nada a ciegas.
		guard !stalled else { return }
		Paster.deleteBackward(back)
		var rest = Substring(text)
		while !rest.isEmpty {
			let piece = rest.prefix(Self.chunk)
			rest = rest.dropFirst(piece.count)
			let body = piece.replacingOccurrences(of: #" +$"#, with: "", options: .regularExpression)
			if !body.isEmpty, !(await Paster.pasteAndWait(body)) {
				stalled = true
				return
			}
			// Algunas terminales recortan los espacios del final de un pegado: esos van como teclas.
			Paster.typeSpaces(piece.count - body.count)
		}
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
