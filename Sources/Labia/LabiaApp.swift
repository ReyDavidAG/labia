import SwiftUI

struct LabiaApp: App {
	@State private var model = AppModel()

	var body: some Scene {
		MenuBarExtra {
			MenuContent(model: model)
		} label: {
			MenuLabel(model: model)
		}

		Settings {
			SettingsView(model: model)
		}

		Window("Bienvenida", id: OnboardingView.windowID) {
			OnboardingView(model: model)
		}
		.windowResizability(.contentSize)
		.windowStyle(.hiddenTitleBar)
	}
}

private struct MenuLabel: View {
	let model: AppModel
	@Environment(\.openWindow) private var openWindow

	var body: some View {
		Image(systemName: model.menuSymbol)
			.task { if model.needsSetup { openSetup() } }
			.onChange(of: model.accessibilityGranted) { _, granted in if !granted { openSetup() } }
	}

	private func openSetup() {
		NSApp.activate()
		openWindow(id: OnboardingView.windowID)
	}
}

private struct MenuContent: View {
	@Bindable var model: AppModel
	@Environment(\.openWindow) private var openWindow
	@Environment(\.openSettings) private var openSettings

	var body: some View {
		Text(model.statusLine)
		if let last = model.lastText {
			Text("Último: \(last.count > 48 ? String(last.prefix(48)) + "…" : last)")
		}
		Divider()
		Button("Copiar último dictado") { model.copyLast() }
			.disabled(model.lastText == nil)
		Button("Historial…") { showSettings(.history) }
		if model.needsSetup {
			Button("Terminar configuración…") {
				NSApp.activate()
				openWindow(id: OnboardingView.windowID)
			}
		}
		Divider()
		Toggle("Pausar Labia", isOn: $model.paused)
		Button("Ajustes…") { showSettings(.general) }
			.keyboardShortcut(",")
		if model.updater.isRunning {
			Button("Buscar actualizaciones…") { model.updater.checkNow() }
		}
		Divider()
		Button("Salir de Labia") { NSApp.terminate(nil) }
			.keyboardShortcut("q")
	}

	private func showSettings(_ tab: SettingsTab) {
		model.settingsTab = tab
		NSApp.activate()
		openSettings()
	}
}
