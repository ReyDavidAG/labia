import AppKit
import SwiftUI

/// El menú de la barra: estado con la marca, el último dictado y los atajos de siempre (`propuesta/v2`).
struct MenuPanel: View {
	@Bindable var model: AppModel
	@Environment(\.openWindow) private var openWindow

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			HStack(spacing: 10) {
				Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 32, height: 32)
				VStack(alignment: .leading, spacing: 1) {
					Text(headline).font(.system(size: 13, weight: .semibold))
					Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
				}
			}
			.padding(8)

			if let last = model.history.entries.first {
				VStack(alignment: .leading, spacing: 3) {
					Text("Último dictado" + (last.app.map { " · \($0)" } ?? "")).font(.system(size: 11)).foregroundStyle(.secondary)
					Text(last.text).font(.system(size: 12)).lineLimit(2)
				}
				.padding(10)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.6)))
				.padding(.horizontal, 4).padding(.bottom, 4)
			}

			if model.needsSetup {
				MenuRow(title: "Terminar configuración…", symbol: "exclamationmark.circle.fill") { show(OnboardingView.windowID) }
			}
			MenuRow(title: "Copiar último dictado", shortcut: "⌘C", disabled: model.lastText == nil) {
				model.copyLast()
				dismiss()
			}
			.keyboardShortcut("c")
			MenuRow(title: "Historial…") { showSettings(.history) }
			Divider().padding(.vertical, 4).padding(.horizontal, 6)
			HStack {
				Text("Pausar Labia").font(.system(size: 13))
				Spacer()
				Toggle("Pausar Labia", isOn: $model.paused).labelsHidden().toggleStyle(.switch).controlSize(.mini)
			}
			.padding(.horizontal, 8).padding(.vertical, 3)
			MenuRow(title: "Ajustes…", shortcut: "⌘,") { showSettings(.summary) }
				.keyboardShortcut(",")
			if model.updater.isRunning {
				MenuRow(title: "Buscar actualizaciones…") {
					dismiss()
					model.updater.checkNow()
				}
			}
			Divider().padding(.vertical, 4).padding(.horizontal, 6)
			MenuRow(title: "Salir de Labia", shortcut: "⌘Q") { NSApp.terminate(nil) }
				.keyboardShortcut("q")
		}
		.padding(6)
		.frame(width: 300)
	}

	private var headline: String {
		if model.paused { return "Labia está en pausa" }
		if model.needsSetup { return "Falta terminar la configuración" }
		switch model.modelStatus {
		case .loading: return "Cargando el modelo…"
		case .failed: return "El modelo no cargó"
		default: return "Labia está lista"
		}
	}

	private var detail: String {
		model.needsSetup ? "Falta un permiso o el modelo" : "Mantén \(model.settings.hotkey.label) para dictar"
	}

	private func showSettings(_ tab: SettingsTab) {
		model.settingsTab = tab
		show(SettingsView.windowID)
	}

	private func show(_ id: String) {
		dismiss()
		openWindow(id: id)
		AppWindows.bringForward()
	}

	/// El panel de `MenuBarExtra` no se cierra solo al elegir una opción.
	private func dismiss() {
		for window in NSApp.windows where window.className.contains("MenuBarExtra") {
			window.orderOut(nil)
		}
	}
}

private struct MenuRow: View {
	let title: String
	var symbol: String?
	var shortcut: String?
	var disabled = false
	let action: () -> Void
	@State private var hovering = false

	var body: some View {
		Button(action: action) {
			HStack(spacing: 8) {
				if let symbol { Image(systemName: symbol).foregroundStyle(hovering ? .white : .orange) }
				Text(title)
				Spacer()
				if let shortcut { Text(shortcut).opacity(0.55) }
			}
			.font(.system(size: 13))
			.foregroundStyle(hovering && !disabled ? .white : .primary)
			.padding(.horizontal, 8).padding(.vertical, 4)
			.background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(hovering && !disabled ? Brand.violet : .clear))
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.disabled(disabled)
		.opacity(disabled ? 0.45 : 1)
		.onHover { hovering = $0 }
	}
}
