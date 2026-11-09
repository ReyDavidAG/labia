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

if let i = arguments.firstIndex(of: "--simulate"), arguments.count > i + 1 {
	let file = arguments[i + 1]
	let settings = Preferences.load()
	let semaphore = DispatchSemaphore(value: 0)
	Task {
		do {
			let transcriber = Transcriber()
			try await transcriber.load()
			let audio = try Transcriber.samples(fromFile: file)
			let session = LiveSession(preferences: settings)
			let rate = Double(LiveSession.sampleRate)
			var fed = 0
			var screen = ""
			var costs: [Double] = []
			// Como en vivo: mientras corre una pasada sigue llegando audio, así que la siguiente ve todo lo nuevo.
			while fed < audio.count {
				let advance = Int(max(LiveDictation.step, costs.last ?? 0) * rate)
				let next = min(audio.count, fed + advance)
				session.feed(Array(audio[fed..<next]))
				fed = next
				let (window, kind) = session.nextPass()
				let start = Date()
				let words = try await transcriber.words(window, kind: kind, language: settings.language)
				costs.append(Date().timeIntervalSince(start))
				let (back, add) = session.absorb(words, kind: kind)
				screen = String(screen.dropLast(back)) + add
				print(String(format: "%6.1fs  %@ %.2fs  -%-3d +%@", Double(fed) / rate, kind == .careful ? "cuidadosa" : "rápida   ", costs.last!, back, add.debugDescription))
			}
			let start = Date()
			let raw = try await transcriber.transcribe(audio, prompt: settings.prompt, language: settings.language)
			let (back, add, send) = session.finish(raw: raw)
			screen = String(screen.dropLast(back)) + add
			print(String(format: "final  %.2fs  -%d +%@ enviar=%@", Date().timeIntervalSince(start), back, add.debugDescription, send ? "sí" : "no"))
			let sorted = costs.sorted()
			print(String(format: "\npasadas: %d, mediana %.2fs, máx %.2fs", costs.count, sorted[sorted.count / 2], sorted.last ?? 0))
			print("\n\(screen)")
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
