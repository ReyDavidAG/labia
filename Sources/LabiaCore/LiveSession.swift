import Foundation

public struct Word: Equatable, Sendable {
	public var start: Double
	public var end: Double
	public var text: String

	public init(_ start: Double, _ end: Double, _ text: String) {
		self.start = start
		self.end = end
		self.text = text
	}
}

public enum PassKind: Equatable, Sendable {
	/// Rápida, sin fallback de temperatura: da el borrador.
	case draft
	/// Con fallback de temperatura: reescribe lo ya confirmado de la ventana.
	case careful
}

/// LocalAgreement-2 (whisper_streaming, Macháček et al., 2023), igual que `linux/labia/stream.py`.
/// Confirma el prefijo más largo que una pasada comparte con alguna de las dos anteriores: Whisper suelta
/// pasadas basura de vez en cuando, y contra una sola se perdían palabras.
public struct LocalAgreement: Sendable {
	public internal(set) var committed: [Word] = []
	var recent: [[Word]] = []
	/// Palabras de la última pasada que todavía no se confirman.
	public private(set) var pending = 0

	public init() {}

	var lastEnd: Double { committed.last?.end ?? 0 }

	public var text: String { committed.map(\.text).joined() }

	func fresh(_ words: [Word]) -> [Word] {
		guard let last = committed.last else { return words }
		// Por el inicio de la última palabra: Whisper estira el final de la última palabra del búfer.
		let new = words.filter { $0.start > last.start + 0.05 }
		// Las mismas palabras pueden regresar al principio de la pasada siguiente: se quita ese traslape.
		for n in stride(from: min(5, new.count, committed.count), to: 0, by: -1) {
			if committed.suffix(n).map(\.text).map(fold) == new.prefix(n).map(\.text).map(fold) {
				return Array(new.dropFirst(n))
			}
		}
		return new
	}

	/// Recibe una hipótesis y regresa las palabras recién confirmadas.
	@discardableResult
	public mutating func update(_ words: [Word]) -> [Word] {
		let new = fresh(words)
		var best: [Word] = []
		for old in recent {
			var agreed: [Word] = []
			for (a, b) in zip(new, fresh(old)) {
				guard fold(a.text) == fold(b.text) else { break }
				agreed.append(a)
			}
			if agreed.count > best.count { best = agreed }
		}
		committed += best
		pending = new.count - best.count
		recent = Array((recent + [words]).suffix(2))
		return best
	}
}

/// «Parra.» y «parra» son la misma palabra.
func fold(_ word: String) -> String {
	SendKeyword.key(word)
}

public enum LiveText {
	/// Retrocesos y texto a escribir para que lo que está en pantalla (`typed`) quede como `target`.
	public static func diff(_ typed: String, _ target: String) -> (back: Int, text: String) {
		var k = 0
		for (a, b) in zip(typed, target) {
			guard a == b else { break }
			k += 1
		}
		return (typed.count - k, String(target.dropFirst(k)))
	}

	/// Mientras se sigue hablando, la última palabra se retiene: la limpieza o la palabra de envío pueden cambiarla.
	public static func holdLastWord(_ text: String) -> String {
		let trimmed = text.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
		guard let cut = trimmed.range(of: " ", options: .backwards), cut.lowerBound > trimmed.startIndex else { return "" }
		return String(trimmed[..<cut.lowerBound])
	}
}

/// Un dictado en tiempo real, como el `Session` de Linux y Windows: las pasadas rápidas escriben un borrador,
/// las cuidadosas lo reemplazan para el mismo audio, y el audio que sale de la ventana ya es final.
/// Al soltar, la pasada final sobre toda la grabación decide el texto.
///
/// Lógica pura: quien la usa pide `nextPass()`, transcribe ese audio y entrega las palabras con `absorb`.
public final class LiveSession {
	public static let sampleRate = 16_000
	/// Recorta la ventana de Whisper cuando pasa de esto: la pasada cuesta lo mismo, pero el peor caso baja.
	public static let trimSeconds = 10.0
	/// Cada tanto audio nuevo, una pasada cuidadosa reescribe lo ya escrito (la microcorrección).
	public static let refineSeconds = 3.0
	/// Una pasada cuidadosa con menos de esta parte de las palabras que reemplaza es basura y se ignora.
	public static let garbageRatio = 0.6
	/// Una pasada final con menos de `garbageRatio` de las palabras ya confirmadas se descarta y se quedan esas:
	/// en audio largo Whisper a veces regresa vacío y se borraba todo el dictado. Con menos palabras en pantalla
	/// (una alucinación sobre silencio, «Gracias.») sí se borra.
	public static let keepMinWords = 4
	/// Por debajo de este volumen (RMS) el audio nuevo es silencio.
	public static let silenceRMS: Float = 0.004

	public let preferences: Preferences
	public private(set) var agreement = LocalAgreement()
	public private(set) var samples = 0
	public private(set) var typed = ""
	private var window: [Float] = []
	private var offset = 0
	private var refinedAt = 0
	private var passedAt = 0
	private var settled = false

	public init(preferences: Preferences) {
		self.preferences = preferences
	}

	public func feed(_ chunk: [Float]) {
		window += chunk
		samples += chunk.count
	}

	private var windowStart: Double { Double(offset) / Double(Self.sampleRate) }

	/// La pasada que toca y el audio de la ventana para hacerla, o `nil` si no hace falta:
	/// si sólo llegó silencio, la pasada anterior no cambió nada y no quedan palabras por confirmar,
	/// otra pasada tampoco cambiaría nada.
	/// En manos libres, con pausas largas, eso ahorra el Neural Engine sin escribir más tarde.
	public func nextPass() -> (audio: [Float], kind: PassKind)? {
		let fresh = window.suffix(samples - passedAt)
		passedAt = samples
		if settled, !fresh.isEmpty, Self.rms(fresh) < Self.silenceRMS { return nil }
		if samples - refinedAt >= Int(Self.refineSeconds * Double(Self.sampleRate)), !agreement.committed.isEmpty {
			refinedAt = samples
			return (window, .careful)
		}
		return (window, .draft)
	}

	/// Palabras de la pasada (tiempos relativos al audio que dio `nextPass`). Regresa lo que hay que cambiar en pantalla.
	public func absorb(_ words: [Word], kind: PassKind) -> (back: Int, text: String) {
		let start = windowStart
		let shifted = words.map { Word($0.start + start, $0.end + start, $0.text) }
		switch kind {
		case .draft: agreement.update(shifted)
		case .careful: refine(shifted)
		}
		trim()
		let change = apply(LiveText.holdLastWord(clean(agreement.text)))
		settled = change.back == 0 && change.text.isEmpty && agreement.pending == 0
		return change
	}

	public static func rms<C: Collection>(_ values: C) -> Float where C.Element == Float {
		guard !values.isEmpty else { return 0 }
		return (values.reduce(0) { $0 + $1 * $1 } / Float(values.count)).squareRoot()
	}

	/// Si algún tramo de 0.1 s pasa de `silenceRMS`. El promedio de toda la grabación no sirve:
	/// las pausas de un dictado largo lo bajan y se tomaba como silencio.
	public static func hasVoice(_ samples: [Float]) -> Bool {
		let frame = sampleRate / 10
		return stride(from: 0, to: samples.count, by: frame).contains { start in
			rms(samples[start..<min(start + frame, samples.count)]) > silenceRMS
		}
	}

	/// El texto de la pasada final sobre toda la grabación. Regresa lo que hay que cambiar en pantalla y si se envía.
	public func finish(raw: String) -> (back: Int, text: String, send: Bool) {
		var text = clean(raw)
		let kept = clean(agreement.text)
		if Self.wordCount(typed) >= Self.keepMinWords, Double(Self.wordCount(text)) < Self.garbageRatio * Double(Self.wordCount(kept)) {
			text = kept
		}
		var send = false
		if preferences.sendOnKeyword {
			(text, send) = SendKeyword.split(text, keywords: preferences.sendKeywords)
		}
		if !text.isEmpty, preferences.trailingSpace, !send, !text.hasSuffix("\n") {
			text += " "
		}
		let (back, add) = apply(text)
		return (back, add, send)
	}

	static func wordCount(_ text: String) -> Int {
		text.split(whereSeparator: \.isWhitespace).count
	}

	/// Borra todo lo escrito (dictado cancelado).
	public func discard() -> Int {
		apply("").back
	}

	private func refine(_ words: [Word]) {
		let old = agreement.committed
		let frozen = old.filter { $0.start < windowStart }
		let inWindow = old.dropFirst(frozen.count)
		guard let last = inWindow.last else { return }
		// Hasta la última palabra confirmada; lo que sigue todavía es borrador.
		var new = words.filter { $0.start <= last.start + 0.15 }
		// Sólo cambiar mayúsculas («Revisa» → «revisa») borraría y reescribiría todo lo que sigue sin corregir nada.
		for (i, old) in zip(new.indices, inWindow) where new[i].text.lowercased() == old.text.lowercased() {
			new[i].text = old.text
		}
		if Double(new.count) >= Self.garbageRatio * Double(inWindow.count) {
			agreement.committed = frozen + new
		}
	}

	private func trim() {
		guard Double(window.count) / Double(Self.sampleRate) >= Self.trimSeconds, !agreement.committed.isEmpty else { return }
		let cut = Int(agreement.lastEnd * Double(Self.sampleRate)) - offset
		guard cut > 0 else { return }
		window.removeFirst(min(cut, window.count))
		offset += cut
	}

	private func clean(_ raw: String) -> String {
		TextCleaner.clean(raw, replacements: preferences.replacements, vocabulary: preferences.vocabulary)
	}

	private func apply(_ target: String) -> (back: Int, text: String) {
		let change = LiveText.diff(typed, target)
		typed = target
		return change
	}
}
