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

	func transcribe(_ samples: [Float], prompt: String?, language: String) async throws -> String {
		try await load()
		guard let kit else { return "" }
		var options = DecodingOptions(task: .transcribe, language: language, temperature: 0, usePrefillPrompt: true, skipSpecialTokens: true)
		// Más de 30 s: cortar en las pausas y transcribir cada tramo por separado. Sin esto WhisperKit avanza
		// ventana por ventana guiado por los timestamps, y una ventana mala (el prompt la hace repetir o cortar)
		// se salta el resto: en dictados de más de un minuto sólo llegaban las primeras frases.
		options.chunkingStrategy = .vad
		if let prompt, let tokenizer = kit.tokenizer {
			options.promptTokens = tokenizer.encode(text: " " + prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
		}
		let results: [TranscriptionResult] = try await kit.transcribe(audioArray: samples, decodeOptions: options)
		return results.map(\.text).joined(separator: " ")
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
