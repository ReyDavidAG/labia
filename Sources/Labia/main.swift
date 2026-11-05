import Foundation
import LabiaCore

let arguments = CommandLine.arguments

if let i = arguments.firstIndex(of: "--transcribe") {
	let files = Array(arguments.dropFirst(i + 1))
	let settings = Preferences.load()
	let semaphore = DispatchSemaphore(value: 0)
	Task {
		let transcriber = Transcriber()
		do {
			let loadStart = Date()
			try await transcriber.load()
			print(String(format: "modelo cargado en %.2f s", Date().timeIntervalSince(loadStart)))
			for file in files {
				let samples = try Transcriber.samples(fromFile: file)
				let start = Date()
				let raw = try await transcriber.transcribe(samples, prompt: settings.prompt, language: settings.language)
				let text = TextCleaner.clean(raw, replacements: settings.replacements, vocabulary: settings.vocabulary)
				print(String(format: "%@\t%.2f s\t%@", (file as NSString).lastPathComponent, Date().timeIntervalSince(start), text))
			}
		} catch {
			FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
			exit(1)
		}
		semaphore.signal()
	}
	semaphore.wait()
	exit(0)
}

LabiaApp.main()
