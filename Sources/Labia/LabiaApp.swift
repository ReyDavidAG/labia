import SwiftUI

struct LabiaApp: App {
	@State private var model = AppModel()

	var body: some Scene {
		MenuBarExtra {
			MenuPanel(model: model)
		} label: {
			MenuLabel(model: model)
		}
		.menuBarExtraStyle(.window)

		Window("Ajustes de Labia", id: SettingsView.windowID) {
			SettingsView(model: model)
				.labiaWindow(SettingsView.windowID)
		}
		.defaultSize(width: 880, height: 620)
		.commands { SettingsCommand(model: model) }

		Window("Bienvenida", id: OnboardingView.windowID) {
			OnboardingView(model: model)
				.labiaWindow(OnboardingView.windowID)
		}
		.windowResizability(.contentSize)
		.windowStyle(.hiddenTitleBar)
	}
}

/// ⌘, abre los Ajustes nuevos en lugar de la ventana de Ajustes de SwiftUI.
private struct SettingsCommand: Commands {
	let model: AppModel
	@Environment(\.openWindow) private var openWindow

	var body: some Commands {
		CommandGroup(replacing: .appSettings) {
			Button("Ajustes…") {
				openWindow(id: SettingsView.windowID)
				AppWindows.bringForward()
			}
			.keyboardShortcut(",")
		}
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
		openWindow(id: OnboardingView.windowID)
		AppWindows.bringForward()
	}
}
