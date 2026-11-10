import LabiaCore
import SwiftUI

// MARK: Resumen

struct SummaryPane: View {
	let model: AppModel
	@Environment(\.openWindow) private var openWindow

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				status
				HStack(spacing: 10) {
					Tile(value: "\(today.count)", label: "dictados hoy")
					Tile(value: today.words.formatted(.number.locale(.labia)), label: "palabras hoy")
					Tile(value: modelLabel, label: "modelo")
				}
				Text("Últimos dictados").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
				if model.history.entries.isEmpty {
					Text("Todavía no hay dictados. Mantén \(model.settings.hotkey.label) en cualquier app y habla.")
						.foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Card())
				} else {
					VStack(spacing: 0) {
						ForEach(Array(model.history.entries.prefix(3).enumerated()), id: \.element.id) { index, entry in
							if index > 0 { Divider().padding(.leading, 54) }
							HistoryRow(entry: entry) { model.copy(entry) }
						}
					}
					.background(Card())
				}
			}
			.padding(24)
		}
	}

	private var status: some View {
		HStack(spacing: 18) {
			TalkingBars(count: 4, width: 4, height: 26, animated: !model.needsSetup && !model.paused)
				.frame(width: 54, height: 54)
				.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.lime))
			VStack(alignment: .leading, spacing: 4) {
				Text(headline).font(.system(size: 18, weight: .bold))
				if model.needsSetup {
					Text("Falta un permiso o el modelo para poder dictar.").foregroundStyle(.white.opacity(0.85))
				} else {
					HStack(spacing: 6) {
						Text("Mantén")
						Keycap(text: model.settings.hotkey.label, onBrand: true)
						Text("en cualquier app y habla.")
					}
					.foregroundStyle(.white.opacity(0.85))
				}
			}
			Spacer()
			if model.needsSetup {
				Button("Terminar configuración") { openWindow(id: OnboardingView.windowID) }
					.buttonStyle(.plain)
					.font(.system(size: 13, weight: .semibold))
					.foregroundStyle(Brand.indigo)
					.padding(.horizontal, 12).padding(.vertical, 6)
					.background(Capsule().fill(Brand.lime))
			}
		}
		.foregroundStyle(.white)
		.padding(20)
		.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.gradient))
	}

	private var headline: String {
		if model.paused { return "Labia está en pausa" }
		if model.needsSetup { return "Falta terminar la configuración" }
		return "Labia está lista"
	}

	private var modelLabel: String {
		switch model.modelStatus {
		case .ready: "En memoria"
		case .loading: "Cargando…"
		case .unloaded: "En reposo"
		case .downloading: "Bajando…"
		case .missing: "Sin bajar"
		case .failed: "Con error"
		}
	}

	private var today: (count: Int, words: Int) {
		let entries = model.history.entries.filter { Calendar.current.isDateInToday($0.date) }
		return (entries.count, entries.reduce(0) { $0 + $1.words })
	}
}

private struct Tile: View {
	let value: String
	let label: String

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(value).font(.system(size: 20, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
			Text(label).font(.caption).foregroundStyle(.secondary)
		}
		.padding(.horizontal, 14).padding(.vertical, 12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Card())
	}
}

struct HistoryRow: View {
	let entry: HistoryEntry
	var showTime = false
	let copy: () -> Void
	@State private var copied = false

	var body: some View {
		HStack(alignment: .top, spacing: 12) {
			AppBadge(name: entry.app)
			VStack(alignment: .leading, spacing: 3) {
				Text(entry.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
				Text(caption).font(.caption).foregroundStyle(.secondary)
			}
			Spacer(minLength: 8)
			Button(copied ? "Copiado" : "Copiar") {
				copy()
				copied = true
				Task {
					try? await Task.sleep(for: .seconds(1.5))
					copied = false
				}
			}
			.controlSize(.small)
		}
		.padding(.horizontal, 14).padding(.vertical, 10)
	}

	private var caption: String {
		var parts: [String] = []
		if let app = entry.app { parts.append(app) }
		parts.append(showTime ? entry.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.labia)) : entry.date.formatted(.relative(presentation: .named).locale(.labia)))
		parts.append("\(entry.words) palabras")
		parts.append(String(format: "%.0f s", entry.seconds))
		return parts.joined(separator: " · ")
	}
}

// MARK: Atajo y escritura

struct GeneralPane: View {
	@Bindable var model: AppModel
	@State private var keyword = ""

	var body: some View {
		Form {
			Section("Atajo") {
				Picker(selection: $model.settings.hotkey) {
					ForEach(Hotkey.allCases) { Text($0.label).tag($0) }
				} label: {
					Text("Tecla para dictar")
					Text("Mantén para hablar · doble toque para manos libres · esc cancela")
				}
			}
			Section("Escritura") {
				DetailToggle(title: "Pegar automáticamente", detail: "Si lo apagas, el dictado sólo se copia", isOn: $model.settings.autoPaste)
				DetailToggle(title: "Escribir mientras hablas", detail: "El texto aparece en vivo y se corrige al soltar", isOn: $model.settings.liveTyping)
					.disabled(!model.settings.autoPaste)
				DetailToggle(title: "Restaurar el portapapeles", detail: "Lo que tenías copiado vuelve al terminar", isOn: $model.settings.restoreClipboard)
				DetailToggle(title: "Agregar un espacio al final", isOn: $model.settings.trailingSpace)
			}
			Section {
				DetailToggle(title: "Presionar Enter si terminas con…", detail: "Labia quita la palabra, pega y envía. Dila sola para enviar lo que ya escribiste", isOn: $model.settings.sendOnKeyword)
				if model.settings.sendOnKeyword {
					FlowLayout(spacing: 6) {
						ForEach(model.settings.sendKeywords, id: \.self) { word in
							Chip(text: word) { model.settings.sendKeywords.removeAll { $0 == word } }
						}
					}
					HStack {
						TextField("Otra palabra", text: $keyword, prompt: Text("p. ej. envía")).labelsHidden().onSubmit(addKeyword)
						Button("Agregar", action: addKeyword).buttonStyle(.brand).disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
					}
				}
			} header: {
				Text("Enviar con una palabra")
			}
			Section("Aviso y sonido") {
				DetailToggle(title: "Mostrar la cápsula mientras dictas", isOn: $model.settings.showPill)
				DetailToggle(title: "Sonido al empezar y terminar", isOn: $model.settings.sounds)
				DetailToggle(title: "Abrir al iniciar sesión", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
			}
		}
		.formStyle(.grouped)
		.animation(.default, value: model.settings.sendOnKeyword)
	}

	private func addKeyword() {
		let word = keyword.trimmingCharacters(in: .whitespaces)
		if !word.isEmpty, !model.settings.sendKeywords.contains(word) { model.settings.sendKeywords.append(word) }
		keyword = ""
	}
}

struct Chip: View {
	let text: String
	let remove: () -> Void

	var body: some View {
		HStack(spacing: 5) {
			Text(text).font(.system(size: 12, design: .monospaced))
			Button(action: remove) {
				Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
			}
			.buttonStyle(.plain)
			.foregroundStyle(.secondary)
			.accessibilityLabel("Quitar \(text)")
		}
		.padding(.leading, 10).padding(.trailing, 7).padding(.vertical, 4)
		.background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.background))
		.overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.primary.opacity(0.1)))
		.transition(.scale(scale: 0.8).combined(with: .opacity))
	}
}

// MARK: Vocabulario

struct VocabularyPane: View {
	@Bindable var model: AppModel
	@State private var draft = ""

	var body: some View {
		Form {
			Section {
				FlowLayout(spacing: 6) {
					ForEach(model.settings.vocabulary, id: \.self) { word in
						Chip(text: word) { model.settings.vocabulary.removeAll { $0 == word } }
					}
				}
				.animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.settings.vocabulary)
				HStack {
					TextField("Palabra nueva", text: $draft, prompt: Text("p. ej. useApiQuery")).labelsHidden().onSubmit(add)
					Button("Agregar", action: add).buttonStyle(.brand).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
				}
				CostMeter(tokens: model.promptTokens)
			} header: {
				Text("Palabras que dices en inglés o con mayúsculas especiales")
			} footer: {
				HStack(alignment: .top) {
					Text("Whisper usa esta lista como contexto: escribe bien esas palabras y respeta sus mayúsculas. Pon sólo las que te fallan.")
					Spacer()
					Button("Restaurar lista inicial") { model.settings.vocabulary = Preferences.defaultVocabulary }.buttonStyle(.link)
				}
			}
		}
		.formStyle(.grouped)
	}

	private func add() {
		let words = draft.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
		for word in words where !model.settings.vocabulary.contains(word) {
			model.settings.vocabulary.append(word)
		}
		draft = ""
	}
}

/// Lo que el vocabulario agrega a cada dictado: verde rápido, ámbar se nota, rojo demasiado.
private struct CostMeter: View {
	let tokens: Int?

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text("Costo por dictado")
				Spacer()
				Text(label).fontWeight(.semibold).monospacedDigit()
			}
			GeometryReader { geo in
				ZStack(alignment: .leading) {
					Capsule().fill(.quaternary)
					Capsule().fill(color.gradient).frame(width: geo.size.width * fraction)
				}
			}
			.frame(height: 6)
		}
		.animation(.easeOut, value: tokens)
	}

	private var ms: Int? { tokens.map { Int((Double($0) * 25 / 10).rounded()) * 10 } }
	private var fraction: Double { min(Double(ms ?? 0) / 1200, 1) }
	private var label: String {
		guard let ms else { return "carga el modelo para medirlo" }
		return ms == 0 ? "sin costo extra" : "≈ +\(ms) ms"
	}
	private var color: Color {
		switch ms ?? 0 {
		case ..<400: .green
		case ..<800: .orange
		default: .red
		}
	}
}

// MARK: Reemplazos

struct ReplacementsPane: View {
	@Bindable var model: AppModel

	var body: some View {
		Form {
			Section {
				HStack {
					Text("Si dices").frame(maxWidth: .infinity, alignment: .leading)
					Spacer().frame(width: 20)
					Text("Escribe").frame(maxWidth: .infinity, alignment: .leading)
					Spacer().frame(width: 22)
				}
				.font(.system(size: 11, weight: .semibold))
				.foregroundStyle(.secondary)
				ForEach($model.settings.replacements) { $rule in
					HStack {
						TextField("Si dices", text: $rule.from).labelsHidden()
						Image(systemName: "arrow.right").foregroundStyle(.secondary).frame(width: 20)
						TextField("Escribe", text: $rule.to).labelsHidden()
						Button {
							model.settings.replacements.removeAll { $0.id == rule.id }
						} label: {
							Image(systemName: "minus.circle.fill")
						}
						.buttonStyle(.plain).foregroundStyle(.secondary)
						.accessibilityLabel("Quitar reemplazo")
					}
					.font(.system(size: 12, design: .monospaced))
				}
				Button("Agregar reemplazo") { model.settings.replacements.append(Replacement(from: "", to: "")) }
			} header: {
				Text("Se aplican después de transcribir, en orden y sin distinguir mayúsculas")
			} footer: {
				Text("Escribe \\n para un salto de línea. Sirven para comandos dictados como «nueva línea» o para lo que el vocabulario no alcance.")
			}
		}
		.formStyle(.grouped)
	}
}

// MARK: Historial

struct HistoryPane: View {
	let model: AppModel
	@State private var query = ""

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				HStack(spacing: 6) {
					Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
					TextField("Buscar en el historial", text: $query).textFieldStyle(.plain)
				}
				.padding(.horizontal, 8).padding(.vertical, 5)
				.background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quaternary.opacity(0.7)))
				Button("Borrar todo", role: .destructive) { model.clearHistory() }
					.disabled(model.history.entries.isEmpty)
			}
			.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)
			if model.history.entries.isEmpty {
				ContentUnavailableView("Sin dictados todavía", systemImage: "waveform", description: Text("Mantén \(model.settings.hotkey.label) en cualquier app y habla."))
			} else if groups.isEmpty {
				ContentUnavailableView.search(text: query)
			} else {
				ScrollView {
					VStack(alignment: .leading, spacing: 18) {
						ForEach(groups, id: \.title) { group in
							VStack(alignment: .leading, spacing: 6) {
								Text(group.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
								VStack(spacing: 0) {
									ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
										if index > 0 { Divider().padding(.leading, 54) }
										HistoryRow(entry: entry, showTime: true) { model.copy(entry) }
									}
								}
								.background(Card())
							}
						}
						Text("Últimos \(History.limit), sólo el texto y sólo en esta Mac.").font(.caption).foregroundStyle(.secondary)
					}
					.padding(.horizontal, 24).padding(.bottom, 24)
				}
			}
		}
	}

	private var groups: [(title: String, entries: [HistoryEntry])] {
		let words = query.split(separator: " ").map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
		let matches = model.history.entries.filter { entry in
			let text = entry.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
			return words.allSatisfy { text.contains($0) }
		}
		var result: [(title: String, entries: [HistoryEntry])] = []
		for entry in matches {
			let title = Self.dayTitle(entry.date)
			if result.last?.title == title { result[result.count - 1].entries.append(entry) } else { result.append((title, [entry])) }
		}
		return result
	}

	private static func dayTitle(_ date: Date) -> String {
		let calendar = Calendar.current
		if calendar.isDateInToday(date) { return "Hoy" }
		if calendar.isDateInYesterday(date) { return "Ayer" }
		return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.labia)).capitalized(with: .labia)
	}
}

// MARK: Modelo

struct ModelPane: View {
	@Bindable var model: AppModel

	var body: some View {
		Form {
			Section {
				HStack(spacing: 16) {
					ModelRing(status: model.modelStatus)
					VStack(alignment: .leading, spacing: 4) {
						Text("Whisper large-v3-turbo").font(.system(size: 14, weight: .semibold))
						ModelStatusLabel(status: model.modelStatus)
						Text("1.5 GB en disco · ~1.6 GB de memoria cargado").font(.caption).foregroundStyle(.secondary)
					}
					Spacer()
					switch model.modelStatus {
					case .missing, .failed: Button("Descargar", action: model.download).buttonStyle(.brand)
					case .ready: Button("Liberar memoria", action: model.unloadNow)
					case .unloaded: Button("Cargar ahora", action: model.preload)
					default: EmptyView()
					}
				}
				.padding(.vertical, 4)
			}
			Section {
				Picker("Idioma", selection: $model.settings.language) {
					Text("Español").tag("es")
					Text("English").tag("en")
				}
				.pickerStyle(.segmented)
				Picker(selection: $model.settings.unloadAfterMinutes) {
					Text("5 min").tag(5)
					Text("30 min").tag(30)
					Text("2 h").tag(120)
					Text("Nunca").tag(0)
				} label: {
					Text("Liberar memoria sin dictar")
					Text("El primer dictado después tarda unos segundos más")
				}
				.pickerStyle(.segmented)
				LabeledContent("Carpeta del modelo") {
					Button("Mostrar en Finder", action: model.revealModel).disabled(model.modelStatus == .missing)
				}
			} footer: {
				Text("Todo se procesa en esta Mac. El audio no sale de aquí.")
			}
		}
		.formStyle(.grouped)
	}
}

private struct ModelRing: View {
	let status: ModelStatus

	var body: some View {
		ZStack {
			Circle().stroke(.quaternary, lineWidth: 5)
			Circle().trim(from: 0, to: progress).stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
			Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(color)
		}
		.frame(width: 50, height: 50)
		.animation(.easeOut, value: progress)
	}

	private var progress: Double {
		switch status {
		case let .downloading(p): p
		case .missing, .failed: 0
		default: 1
		}
	}

	private var color: Color {
		switch status {
		case .ready: .green
		case .failed: .orange
		case .unloaded: .secondary
		default: Brand.violet
		}
	}

	private var symbol: String {
		switch status {
		case .ready: "checkmark"
		case .unloaded: "moon.zzz.fill"
		case .failed: "exclamationmark"
		case .missing: "arrow.down"
		default: "ellipsis"
		}
	}
}

struct ModelStatusLabel: View {
	let status: ModelStatus

	var body: some View {
		switch status {
		case .missing: StatusBadge(text: "Sin descargar", color: .secondary)
		case let .downloading(p): StatusBadge(text: "Descargando \(Int(p * 100)) %", color: Brand.violet)
		case .unloaded: StatusBadge(text: "En reposo", color: .secondary)
		case .loading: StatusBadge(text: "Cargando…", color: Brand.violet)
		case .ready: StatusBadge(text: "Listo en memoria", color: .green)
		case let .failed(message): StatusBadge(text: message, color: .orange)
		}
	}
}

// MARK: Permisos

struct PermissionsPane: View {
	let model: AppModel

	var body: some View {
		Form {
			Section {
				PermissionRow(symbol: "mic.fill", color: SettingsTab.general.color, title: "Micrófono", detail: "Para oírte", granted: model.micGranted, button: "Permitir", action: model.requestMicrophone)
				PermissionRow(symbol: "hand.raised.fill", color: SettingsTab.permissions.color, title: "Accesibilidad", detail: "Para oír el atajo y pegar", granted: model.accessibilityGranted, button: "Abrir Ajustes", action: model.requestAccessibility)
			} footer: {
				Text("Si un permiso se pierde (por ejemplo, tras una actualización), Labia te lo dice en segundos y abre la bienvenida en ese paso.")
			}
		}
		.formStyle(.grouped)
		.onAppear { model.refreshPermissions() }
	}
}

private struct PermissionRow: View {
	let symbol: String
	let color: Color
	let title: String
	let detail: String
	let granted: Bool
	let button: String
	let action: () -> Void

	var body: some View {
		HStack(spacing: 12) {
			IconTile(symbol: symbol, color: color, size: 28)
			VStack(alignment: .leading, spacing: 1) {
				Text(title)
				Text(detail).font(.caption).foregroundStyle(.secondary)
			}
			Spacer()
			if granted {
				StatusBadge(text: "Concedido", color: .green)
			} else {
				StatusBadge(text: "Falta", color: .orange)
				Button(button, action: action).buttonStyle(.brand)
			}
		}
	}
}

// MARK: Actualizaciones

struct UpdatesPane: View {
	@Bindable var model: AppModel

	var body: some View {
		Form {
			Section {
				HStack(spacing: 14) {
					Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
					VStack(alignment: .leading, spacing: 2) {
						Text("Labia \(Updater.version)").font(.system(size: 14, weight: .semibold))
						if let commit = Updater.commit { Text(commit).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
						if let last = model.updater.lastCheck {
							Text("Revisado \(last.formatted(.relative(presentation: .named).locale(.labia)))").font(.caption).foregroundStyle(.secondary)
						}
					}
					Spacer()
					Button("Buscar ahora", action: model.updater.checkNow).disabled(!model.updater.isRunning)
				}
			}
			Section {
				DetailToggle(title: "Actualizar automáticamente", detail: "Se instalan sólo cuando no estás dictando", isOn: $model.settings.autoUpdate)
				Picker("Canal", selection: $model.settings.updateChannel) {
					Text("Estable").tag(UpdateChannel.stable)
					Text("Desarrollo").tag(UpdateChannel.development)
				}
				.pickerStyle(.segmented)
			} footer: {
				Text(model.updater.isRunning
					? "Las actualizaciones vienen de github.com/ReyDavidAG/labia. No se envía nada de esta Mac."
					: "Esta compilación no se actualiza sola. Instala Labia desde los releases de GitHub.")
			}
		}
		.formStyle(.grouped)
	}
}
