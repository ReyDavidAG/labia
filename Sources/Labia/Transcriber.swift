import Foundation
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
		if let prompt, let tokenizer = kit.tokenizer {
			options.promptTokens = tokenizer.encode(text: " " + prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
		}
		let results: [TranscriptionResult] = try await kit.transcribe(audioArray: samples, decodeOptions: options)
		return results.map(\.text).joined(separator: " ")
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
