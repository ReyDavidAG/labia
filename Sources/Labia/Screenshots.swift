import AppKit
import LabiaCore
import SwiftUI

@MainActor
enum Screenshots {
	static let sentence = "Revisa el pull request y si pasa el lint, haz el merge a develop y sube el release a Vercel."

	static func render(to folder: URL) {
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let model = AppModel(sample: true)
		model.levels = (0..<AppModel.waveformBars).map(sampleLevel)
		model.recordingStart = .now.addingTimeInterval(-4)
		for (text, minutes, app) in [
			(sentence, 3.0, "Terminal"),
			("Usa el hook useApiQuery con enabled y un staleTime de 5 minutos.", 18.0, "Visual Studio Code"),
			("Agenda la revisión del deploy para el jueves a las 10.", 64.0, "Slack"),
		] {
			model.history.add(HistoryEntry(text: text, date: .now.addingTimeInterval(-minutes * 60), seconds: Double(text.count) / 14, app: app))
		}

		save(Hero(model: model), size: CGSize(width: 1280, height: 720), dark: true, to: folder.appending(path: "hero.png"))
		save(States(model: model), size: CGSize(width: 1280, height: 560), dark: true, to: folder.appending(path: "states.png"))
		for tab in SettingsTab.allCases {
			model.settingsTab = tab
			for dark in [false, true] {
				let name = "settings-\(tab.rawValue)\(dark ? "-dark" : "").png"
				save(SettingsView(model: model), size: CGSize(width: 880, height: 620), dark: dark, to: folder.appending(path: name))
			}
		}
		save(MenuPanel(model: model), size: CGSize(width: 300, height: 330), dark: false, to: folder.appending(path: "menu.png"))
		save(MenuPanel(model: model), size: CGSize(width: 300, height: 330), dark: true, to: folder.appending(path: "menu-dark.png"))
		for step in OnboardingView.Step.allCases {
			for dark in [false, true] {
				let name = "welcome-\(step.rawValue + 1)\(dark ? "-dark" : "").png"
				save(OnboardingView(model: model, initialStep: step), size: CGSize(width: 760, height: 500), dark: dark, to: folder.appending(path: name))
			}
		}
	}

	private static func sampleLevel(_ i: Int) -> Float {
		let x = Double(i)
		let wave: Double = abs(sin(x * 0.55)) * (0.5 + 0.5 * cos(x * 0.21))
		return Float(0.25 + 0.6 * wave)
	}

	private static func save(_ view: some View, size: CGSize, dark: Bool, to url: URL) {
		let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
		window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
		window.backgroundColor = dark ? .black : .windowBackgroundColor
		let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .top).background(Color(nsColor: .windowBackgroundColor)))
		host.frame = NSRect(origin: .zero, size: size)
		window.contentView = host
		window.orderFrontRegardless()
		RunLoop.main.run(until: .now.addingTimeInterval(0.6))
		host.layoutSubtreeIfNeeded()
		host.display()
		guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
		host.cacheDisplay(in: host.bounds, to: rep)
		try? rep.representation(using: .png, properties: [:])?.write(to: url)
		window.orderOut(nil)
		print(url.path)
	}
}

private struct Desk: View {
	var body: some View {
		LinearGradient(colors: [Color(red: 0.11, green: 0.13, blue: 0.2), Color(red: 0.05, green: 0.06, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing)
	}
}

private struct Hero: View {
	let model: AppModel

	var body: some View {
		ZStack(alignment: .bottom) {
			Desk()
			VStack(alignment: .leading, spacing: 0) {
				HStack(spacing: 8) {
					ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 12, height: 12) }
					Spacer()
					Text("claude — ~/proyectos/tienda").font(.system(size: 12)).foregroundStyle(.secondary)
					Spacer()
				}
				.padding(.horizontal, 14).frame(height: 34).background(Color(white: 0.14))
				VStack(alignment: .leading, spacing: 14) {
					Text("✻ Claude Code").foregroundStyle(.secondary)
					(Text("⏺ ").foregroundColor(.orange) + Text("Listo, las pruebas pasan. ¿Qué sigue?"))
					HStack(alignment: .top, spacing: 10) {
						Text(">").foregroundStyle(.secondary)
						Text(Screenshots.sentence + " ").background(Color(red: 0.5, green: 0.59, blue: 1).opacity(0.28))
						Rectangle().fill(.white).frame(width: 9, height: 18)
					}
					.padding(12)
					.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.25)))
				}
				.font(.system(size: 15, design: .monospaced))
				.padding(22)
				Spacer()
			}
			.frame(width: 1000, height: 300)
			.background(Color(red: 0.06, green: 0.07, blue: 0.09))
			.clipShape(RoundedRectangle(cornerRadius: 14))
			.shadow(color: .black.opacity(0.5), radius: 30, y: 20)
			.frame(maxHeight: .infinity, alignment: .center)
			.padding(.bottom, 60)
			PillBody(pill: .done(words: Screenshots.sentence.split(separator: " ").count, pasted: true), model: model)
				.scaleEffect(1.25)
				.padding(.bottom, 48)
		}
		.environment(\.colorScheme, .dark)
	}
}

private struct States: View {
	let model: AppModel

	var body: some View {
		ZStack {
			Desk()
			Grid(horizontalSpacing: 40, verticalSpacing: 34) {
				GridRow {
					state(.listening, "Escuchando")
					state(.locked, "Manos libres")
				}
				GridRow {
					state(.transcribing, "Transcribiendo")
					state(.done(words: 14, pasted: true), "Pegado")
				}
				GridRow {
					state(.silent, "Sin voz")
					state(.cancelled, "Cancelado")
				}
			}
			.scaleEffect(1.2)
		}
		.environment(\.colorScheme, .dark)
	}

	private func state(_ pill: Pill, _ title: String) -> some View {
		VStack(spacing: 10) {
			PillBody(pill: pill, model: model)
			Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
		}
		.frame(width: 420)
	}
}
