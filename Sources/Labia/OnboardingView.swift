import SwiftUI

struct OnboardingView: View {
	static let windowID = "welcome"

	let model: AppModel
	@State private var trial = ""
	@Environment(\.dismissWindow) private var dismissWindow

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			VStack(alignment: .leading, spacing: 6) {
				Text("Te doy la bienvenida a Labia").font(.system(size: 26, weight: .bold, design: .rounded))
				Text("Mantén \(model.settings.hotkey.label), habla y suelta: el texto se pega donde está el cursor. Antes, tres cosas:")
					.foregroundStyle(.secondary)
			}
			VStack(spacing: 10) {
				Step(number: 1, title: "Micrófono", detail: "Para oírte. El audio nunca sale de esta Mac ni se guarda.", done: model.micGranted) {
					Button("Permitir", action: model.requestMicrophone)
				}
				Step(number: 2, title: "Accesibilidad", detail: "Para detectar el atajo en cualquier app y pegar con ⌘V. Actívalo en la lista y vuelve aquí.", done: model.accessibilityGranted) {
					Button("Abrir Ajustes", action: model.requestAccessibility)
				}
				Step(number: 3, title: "Modelo Whisper", detail: "1.5 GB, una sola vez. La primera carga tarda cerca de un minuto mientras se prepara para tu chip.", done: modelDone) {
					switch model.modelStatus {
					case let .downloading(p): ProgressView(value: p).frame(width: 110)
					case .loading: ProgressView().controlSize(.small)
					default: Button("Descargar", action: model.download)
					}
				}
			}
			if !model.needsSetup {
				VStack(alignment: .leading, spacing: 8) {
					Text("Pruébalo aquí: haz clic en el cuadro, mantén \(model.settings.hotkey.label) y di algo.").font(.callout)
					TextEditor(text: $trial)
						.font(.body)
						.frame(height: 64)
						.scrollContentBackground(.hidden)
						.padding(8)
						.background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
				}
				.transition(.move(edge: .bottom).combined(with: .opacity))
			}
			HStack {
				Spacer()
				Button(model.needsSetup ? "Después" : "Listo") { dismissWindow(id: Self.windowID) }
					.keyboardShortcut(.defaultAction)
			}
		}
		.padding(28)
		.frame(width: 520)
		.animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.needsSetup)
		.onAppear {
			model.refreshPermissions()
			model.startPermissionPolling()
		}
	}

	private var modelDone: Bool {
		switch model.modelStatus {
		case .unloaded, .ready, .loading: true
		default: false
		}
	}
}

private struct Step<Action: View>: View {
	let number: Int
	let title: String
	let detail: String
	let done: Bool
	@ViewBuilder let action: Action

	var body: some View {
		HStack(alignment: .top, spacing: 14) {
			ZStack {
				Circle().fill(done ? Color.green : Color.secondary.opacity(0.18)).frame(width: 28, height: 28)
				if done {
					Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
						.transition(.scale.combined(with: .opacity))
				} else {
					Text("\(number)").font(.system(size: 13, weight: .semibold))
				}
			}
			.animation(.spring(response: 0.35, dampingFraction: 0.6), value: done)
			VStack(alignment: .leading, spacing: 2) {
				Text(title).font(.headline)
				Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
			}
			Spacer(minLength: 12)
			if !done { action }
		}
		.padding(14)
		.background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(done ? 0.25 : 0.5)))
	}
}
