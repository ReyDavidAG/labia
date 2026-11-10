import SwiftUI

/// Bienvenida en cinco pasos: la marca a la izquierda y un solo paso a la derecha (`propuesta/v2`).
struct OnboardingView: View {
	static let windowID = "welcome"

	let model: AppModel
	var initialStep: Step?
	@State private var step: Step = .intro
	@State private var trial = ""
	@Environment(\.dismissWindow) private var dismissWindow

	enum Step: Int, CaseIterable {
		case intro, microphone, accessibility, model, tryout
	}

	var body: some View {
		HStack(spacing: 0) {
			art
			VStack(alignment: .leading, spacing: 0) {
				Text("Paso \(step.rawValue + 1) de \(Step.allCases.count)")
					.font(.system(size: 12, weight: .semibold))
					.foregroundStyle(Brand.accent)
				Group {
					switch step {
					case .intro: intro
					case .microphone: microphone
					case .accessibility: accessibility
					case .model: modelStep
					case .tryout: tryout
					}
				}
				.id(step)
				.transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
				Spacer(minLength: 16)
				footer
			}
			.padding(.horizontal, 36)
			.padding(.top, 40)
			.padding(.bottom, 24)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.frame(width: 760, height: 500)
		.tint(Brand.violet)
		.environment(\.locale, .labia)
		.animation(.spring(response: 0.35, dampingFraction: 0.85), value: step)
		.onAppear {
			step = initialStep ?? firstPending
			model.refreshPermissions()
			model.startPermissionPolling()
		}
	}

	// MARK: Marca

	private var art: some View {
		VStack(spacing: 0) {
			Spacer()
			BrandBubble()
			Spacer()
			HStack(spacing: 6) {
				ForEach(Step.allCases, id: \.self) { item in
					Capsule()
						.fill(item.rawValue <= step.rawValue ? Brand.lime : .white.opacity(0.25))
						.frame(height: 4)
				}
			}
		}
		.padding(.horizontal, 24)
		.padding(.top, 48)
		.padding(.bottom, 26)
		.frame(width: 280)
		.frame(maxHeight: .infinity)
		.background(Brand.gradient)
	}

	// MARK: Pasos

	private var intro: some View {
		VStack(alignment: .leading, spacing: 0) {
			Title("Habla y Labia escribe")
			Lead("Donde esté el cursor: Slack, VS Code, la terminal, el correo. Todo se transcribe en esta Mac.")
			VStack(spacing: 8) {
				Gesture(key: "mantén \(model.settings.hotkey.symbol)", text: "Habla mientras lo sostienes y suelta para pegar.")
				Gesture(key: "\(model.settings.hotkey.symbol) \(model.settings.hotkey.symbol)", text: "Doble toque: manos libres hasta que lo toques otra vez.")
				Gesture(key: "esc", text: "Cancela sin escribir nada.")
			}
		}
	}

	private var microphone: some View {
		VStack(alignment: .leading, spacing: 0) {
			Title("Deja que Labia te oiga")
			Lead("El audio se procesa en memoria y se descarta al terminar. Nunca sale de esta Mac.")
			PermissionCard(symbol: "mic.fill", title: "Micrófono", pending: "macOS te mostrará su propio aviso", granted: model.micGranted, button: "Permitir", action: model.requestMicrophone)
		}
	}

	private var accessibility: some View {
		VStack(alignment: .leading, spacing: 0) {
			Title("Deja que Labia escriba por ti")
			Lead("Accesibilidad le permite oír el atajo en cualquier app y pegar con ⌘V.")
			PermissionCard(symbol: "hand.raised.fill", title: "Accesibilidad", pending: "Esperando el permiso…", granted: model.accessibilityGranted, button: "Abrir Ajustes", action: model.requestAccessibility)
			if !model.accessibilityGranted {
				VStack(alignment: .leading, spacing: 6) {
					HowTo(number: 1, text: "Se abre Privacidad y seguridad › Accesibilidad.")
					HowTo(number: 2, text: "Activa Labia en la lista.")
					HowTo(number: 3, text: "Vuelve aquí: el paso se marca solo.")
				}
				.padding(.top, 14)
			}
		}
	}

	private var modelStep: some View {
		VStack(alignment: .leading, spacing: 0) {
			Title("Descarga el modelo de voz")
			Lead("Whisper large-v3-turbo, una sola vez. La primera carga tarda cerca de un minuto mientras se prepara para tu chip.")
			VStack(alignment: .leading, spacing: 10) {
				HStack {
					Text("Whisper large-v3-turbo").font(.system(size: 14, weight: .semibold))
					Spacer()
					switch model.modelStatus {
					case .missing, .failed: Button("Descargar", action: model.download).buttonStyle(.brand)
					case .downloading: EmptyView()
					default: StatusBadge(text: modelDone ? "Listo" : "Cargando…", color: .green)
					}
				}
				if case let .downloading(fraction) = model.modelStatus {
					ProgressView(value: fraction).tint(Brand.violet)
					Text("\(String(format: "%.2f", fraction * 1.5)) de 1.5 GB").font(.caption).foregroundStyle(.secondary)
				} else if case let .failed(message) = model.modelStatus {
					Text(message).font(.caption).foregroundStyle(.orange)
				} else {
					Text("1.5 GB en disco · cerca de 1.6 GB de memoria mientras está cargado").font(.caption).foregroundStyle(.secondary)
				}
			}
			.padding(14)
			.background(Card())
		}
	}

	private var tryout: some View {
		VStack(alignment: .leading, spacing: 0) {
			Title(model.needsSetup ? "Casi listo" : "Pruébalo aquí")
			if model.needsSetup {
				Lead("Falta algún paso. Vuelve con «Atrás» o termina después desde el menú de Labia.")
			} else {
				(Text("Haz clic en el cuadro, mantén ") + Text(model.settings.hotkey.label).bold().foregroundColor(.primary) + Text(", di una frase y suelta."))
					.font(.system(size: 14))
					.foregroundStyle(.secondary)
					.padding(.bottom, 18)
				TextEditor(text: $trial)
					.font(.system(size: 14))
					.scrollContentBackground(.hidden)
					.padding(10)
					.frame(height: 110)
					.background(Card())
			}
		}
	}

	private var footer: some View {
		HStack {
			if step != .intro {
				Button("Atrás") { move(-1) }.controlSize(.large)
			}
			Spacer()
			if step == .tryout {
				Button(model.needsSetup ? "Después" : "Empezar a dictar") { dismissWindow(id: Self.windowID) }
					.buttonStyle(.brandLarge)
					.keyboardShortcut(.defaultAction)
			} else {
				Button("Continuar") { move(1) }
					.buttonStyle(.brandLarge)
					.keyboardShortcut(.defaultAction)
			}
		}
	}

	// MARK: Estado

	private func move(_ delta: Int) {
		step = Step(rawValue: step.rawValue + delta) ?? step
	}

	/// La primera vez empieza por el principio; si sólo falta algo (un permiso perdido), va directo a ese paso.
	private var firstPending: Step {
		let fresh = !model.micGranted && !model.accessibilityGranted && model.modelStatus == .missing
		if fresh || !model.needsSetup { return .intro }
		if !model.micGranted { return .microphone }
		if !model.accessibilityGranted { return .accessibility }
		return .model
	}

	private var modelDone: Bool {
		switch model.modelStatus {
		case .unloaded, .ready, .loading: true
		default: false
		}
	}
}

private struct Title: View {
	let text: String
	init(_ text: String) { self.text = text }

	var body: some View {
		Text(text).font(.system(size: 24, weight: .bold)).padding(.top, 6).padding(.bottom, 8)
	}
}

private struct Lead: View {
	let text: String
	init(_ text: String) { self.text = text }

	var body: some View {
		Text(text).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.bottom, 18)
	}
}

struct Card: View {
	var body: some View {
		RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.6))
	}
}

private struct Gesture: View {
	let key: String
	let text: String

	var body: some View {
		HStack(spacing: 12) {
			Keycap(text: key).frame(minWidth: 84)
			Text(text).font(.system(size: 13))
			Spacer(minLength: 0)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(Card())
	}
}

private struct PermissionCard: View {
	let symbol: String
	let title: String
	let pending: String
	let granted: Bool
	let button: String
	let action: () -> Void

	var body: some View {
		HStack(spacing: 14) {
			IconTile(symbol: symbol, color: Brand.violet, size: 40)
			VStack(alignment: .leading, spacing: 2) {
				Text(title).font(.system(size: 14, weight: .semibold))
				Text(granted ? "Listo" : pending).font(.caption).foregroundStyle(.secondary)
			}
			Spacer()
			if granted {
				StatusBadge(text: "Concedido", color: .green).transition(.scale.combined(with: .opacity))
			} else {
				Button(button, action: action).buttonStyle(.brand)
			}
		}
		.padding(14)
		.background(Card())
		.animation(.spring(response: 0.35, dampingFraction: 0.7), value: granted)
	}
}

private struct HowTo: View {
	let number: Int
	let text: String

	var body: some View {
		HStack(spacing: 8) {
			Text("\(number)")
				.font(.system(size: 11, weight: .bold))
				.foregroundStyle(Brand.accent)
				.frame(width: 18, height: 18)
				.background(Circle().fill(Brand.violet.opacity(0.12)))
			Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
		}
	}
}
