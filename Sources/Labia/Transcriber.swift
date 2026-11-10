import Foundation
import LabiaCore
import WhisperKit

actor Transcriber {
	static let variant = "large-v3-v20240930_turbo"
	static let repo = "argmaxinc/whisperkit-coreml"

	static var base: URL {
		FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Labia")
	}

	static var modelFolder: URL {
		base.appending(path: "models/\(repo)/openai_whisper-\(variant)")
	}

	static var isDownloaded: Bool {
		["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"].allSatisfy {
			FileManager.default.fileExists(atPath: modelFolder.appending(path: $0).path)
		}
	}

	private var kit: WhisperKit?
	private var loading: Task<Void, Error>?

	var isLoaded: Bool { kit != nil }

	func download(progress: @escaping @Sendable (Double) -> Void) async throws {
		_ = try await WhisperKit.download(variant: Self.variant, downloadBase: Self.base, from: Self.repo) {
			progress($0.fractionCompleted)
		}
	}

	func load() async throws {
		if kit != nil { return }
		if let loading { return try await loading.value }
		let task = Task { try await self.makeKit() }
		loading = task
		defer { loading = nil }
		try await task.value
	}

	func unload() async {
		await kit?.unloadModels()
		kit = nil
	}

	func promptTokenCount(_ prompt: String?) -> Int? {
		guard let tokenizer = kit?.tokenizer else { return nil }
		guard let prompt else { return 0 }
		return tokenizer.encode(text: " " + prompt).count
	}

	/// Más de 30 s se corta en las pausas y cada tramo se transcribe por separado. Sin esto WhisperKit avanza
	/// ventana por ventana guiado por los timestamps, y una ventana mala se salta el resto.
	/// El vocabulario va como prompt, pero con él Whisper a veces deja un tramo corto vacío (casi siempre el último):
	/// ese tramo se repite sin prompt y se queda la versión con más palabras.
	func transcribe(_ samples: [Float], prompt: String?, language: String) async throws -> String {
		try await pass(samples, prompt: prompt, language: language, timestamps: false).map(\.text).joined(separator: " ")
	}

	/// Como `transcribe`, con el tiempo de cada palabra en segundos desde el inicio de `samples`.
	func transcribeWords(_ samples: [Float], prompt: String?, language: String) async throws -> [Word] {
		try await pass(samples, prompt: prompt, language: language, timestamps: true).flatMap { piece in
			piece.results.flatMap(\.segments).flatMap { $0.words ?? [] }.map {
				Word(piece.offset + Double($0.start), piece.offset + Double($0.end), $0.word)
			}
		}
	}

	private struct Piece {
		let offset: Double
		var results: [TranscriptionResult]
		var text: String { results.map(\.text).joined(separator: " ") }
	}

	private func pass(_ samples: [Float], prompt: String?, language: String, timestamps: Bool) async throws -> [Piece] {
		try await load()
		guard let kit else { return [] }
		var options = DecodingOptions(
			task: .transcribe,
			language: language,
			temperature: 0,
			usePrefillPrompt: true,
			skipSpecialTokens: true,
			wordTimestamps: timestamps
		)
		let window = Self.windowSeconds * LiveSession.sampleRate
		let chunks = samples.count > window
			? try await VADAudioChunker().chunkAll(audioArray: samples, maxChunkLength: window, decodeOptions: options)
			: [AudioChunk(seekOffsetIndex: 0, audioSamples: samples)]
		if let prompt, let tokenizer = kit.tokenizer {
			options.promptTokens = tokenizer.encode(text: " " + prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
		}
		let results = await kit.transcribe(audioArrays: chunks.map(\.audioSamples), decodeOptions: options)
		var pieces: [Piece] = []
		for (chunk, result) in zip(chunks, results) {
			let rate = Double(LiveSession.sampleRate)
			var piece = Piece(offset: Double(chunk.seekOffsetIndex) / rate, results: result ?? [])
			if options.promptTokens != nil,
				Double(Self.wordCount(piece.text)) < Self.minWordsPerSecond * Double(chunk.audioSamples.count) / rate
			{
				var plain = options
				plain.promptTokens = nil
				let retry = Piece(offset: piece.offset, results: try await kit.transcribe(audioArray: chunk.audioSamples, decodeOptions: plain))
				if Self.wordCount(retry.text) > Self.wordCount(piece.text) { piece = retry }
			}
			pieces.append(piece)
		}
		return pieces
	}

	/// La ventana de Whisper.
	static let windowSeconds = 30
	/// Un tramo con menos palabras por segundo que esto probablemente perdió frases (se habla a ~2.5 por segundo).
	static let minWordsPerSecond = 0.5

	static func wordCount(_ text: String) -> Int {
		text.split(whereSeparator: \.isWhitespace).count
	}

	/// Una pasada del dictado en tiempo real, con el tiempo de cada palabra.
	/// Sin vocabulario como prompt: en audio corto hace que Whisper entre en bucle (medido en Linux, ver `linux/state.md`).
	func words(_ samples: [Float], kind: PassKind, language: String) async throws -> [Word] {
		try await load()
		guard let kit else { return [] }
		var options = DecodingOptions(
			task: .transcribe,
			language: language,
			temperature: 0,
			temperatureFallbackCount: kind == .careful ? 5 : 0,
			usePrefillPrompt: true,
			skipSpecialTokens: true,
			wordTimestamps: true
		)
		if samples.count > 28 * LiveSession.sampleRate { options.chunkingStrategy = .vad }
		let results: [TranscriptionResult] = try await kit.transcribe(audioArray: samples, decodeOptions: options)
		return results.flatMap(\.segments).flatMap { $0.words ?? [] }.map { Word(Double($0.start), Double($0.end), $0.word) }
	}

	private func makeKit() async throws {
		kit = try await WhisperKit(WhisperKitConfig(
			downloadBase: Self.base,
			modelFolder: Self.modelFolder.path,
			verbose: false,
			logLevel: .error,
			prewarm: true,
			load: true,
			download: false
		))
	}

	static func samples(fromFile path: String) throws -> [Float] {
		try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
	}
}
