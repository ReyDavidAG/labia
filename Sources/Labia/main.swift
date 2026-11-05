import Foundation
import ServiceManagement
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

if let i = arguments.firstIndex(of: "--screenshots"), arguments.count > i + 1 {
	MainActor.assumeIsolated { Screenshots.render(to: URL(fileURLWithPath: arguments[i + 1])) }
	exit(0)
}

if let i = arguments.firstIndex(of: "--login-item"), arguments.count > i + 1 {
	do {
		if arguments[i + 1] == "on" { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
	} catch {
		FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
	}
	print(SMAppService.mainApp.status == .enabled ? "abrir al iniciar sesión: activado" : "abrir al iniciar sesión: desactivado")
	exit(0)
}

LabiaApp.main()
