import LabiaCore
import SwiftUI

struct SettingsView: View {
	@Bindable var model: AppModel

	var body: some View {
		TabView(selection: $model.settingsTab) {
			GeneralTab(model: model)
				.tabItem { Label("General", systemImage: "gearshape") }
				.tag(SettingsTab.general)
			VocabularyTab(model: model)
				.tabItem { Label("Vocabulario", systemImage: "text.book.closed") }
				.tag(SettingsTab.vocabulary)
			ReplacementsTab(model: model)
				.tabItem { Label("Reemplazos", systemImage: "arrow.left.arrow.right") }
				.tag(SettingsTab.replacements)
			HistoryTab(model: model)
				.tabItem { Label("Historial", systemImage: "clock") }
				.tag(SettingsTab.history)
			ModelTab(model: model)
				.tabItem { Label("Modelo", systemImage: "cpu") }
				.tag(SettingsTab.model)
		}
		.frame(width: 580, height: 480)
	}
}

private struct GeneralTab: View {
	@Bindable var model: AppModel

	var body: some View {
		Form {
			Section {
				Picker("Atajo", selection: $model.settings.hotkey) {
					ForEach(Hotkey.allCases) { Text($0.label).tag($0) }
				}
				Text("Mantén para hablar · doble toque para manos libres · esc cancela.")
					.font(.callout).foregroundStyle(.secondary)
			}
			Section {
				Toggle("Pegar automáticamente", isOn: $model.settings.autoPaste)
				Toggle("Escribir mientras hablas", isOn: $model.settings.liveTyping)
					.disabled(!model.settings.autoPaste)
				Toggle("Restaurar el portapapeles después de pegar", isOn: $model.settings.restoreClipboard)
				Toggle("Agregar un espacio al final", isOn: $model.settings.trailingSpace)
			}
			Section {
				Toggle("Enviar al terminar con una palabra", isOn: $model.settings.sendOnKeyword)
				TextField("Palabras", text: Binding(
					get: { model.settings.sendKeywords.joined(separator: ", ") },
					set: { model.settings.sendKeywords = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
				))
				.disabled(!model.settings.sendOnKeyword)
			} footer: {
				Text(model.settings.sendOnKeyword
					? "Si la última palabra que dices es una de éstas, Labia la quita, pega el texto y presiona Enter. Dila sola para enviar lo que ya escribiste."
					: "Labia nunca presiona Enter por ti: revisas y envías tú.")
			}
			Section {
				Toggle("Mostrar la cápsula mientras dictas", isOn: $model.settings.showPill)
				Toggle("Sonido al empezar y terminar", isOn: $model.settings.sounds)
				Toggle("Abrir al iniciar sesión", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
			}
			Section("Permisos") {
				PermissionRow(title: "Micrófono", granted: model.micGranted, action: model.requestMicrophone)
				PermissionRow(title: "Accesibilidad", granted: model.accessibilityGranted, action: model.requestAccessibility)
			}
		}
		.formStyle(.grouped)
		.onAppear { model.refreshPermissions() }
	}
}

struct PermissionRow: View {
	let title: String
	let granted: Bool
	let action: () -> Void

	var body: some View {
		LabeledContent(title) {
			if granted {
				Label("Concedido", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
			} else {
				Button("Conceder…", action: action)
			}
		}
	}
}

private struct VocabularyTab: View {
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
					TextField("Agregar palabra", text: $draft, prompt: Text("p. ej. useApiQuery"))
						.onSubmit(add)
					Button("Agregar", action: add).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
				}
			} header: {
				Text("Palabras que dices en inglés o con mayúsculas especiales")
			} footer: {
				HStack {
					Text("\(model.settings.vocabulary.count) palabras · \(model.promptCostLabel ?? "carga el modelo para medir el costo")")
					Spacer()
					Button("Restaurar lista inicial") { model.settings.vocabulary = Preferences.defaultVocabulary }
						.buttonStyle(.link)
				}
			}
			Section {
				Text("Whisper usa esta lista como contexto: escribe bien esas palabras y respeta sus mayúsculas. Cada palabra agrega unos milisegundos, así que pon sólo las que te fallan.")
					.font(.callout).foregroundStyle(.secondary)
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

private struct Chip: View {
	let text: String
	let remove: () -> Void

	var body: some View {
		HStack(spacing: 4) {
			Text(text).font(.system(.callout, design: .monospaced))
			Button(action: remove) {
				Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
			}
			.buttonStyle(.plain)
			.foregroundStyle(.secondary)
			.accessibilityLabel("Quitar \(text)")
		}
		.padding(.leading, 10).padding(.trailing, 7).padding(.vertical, 4)
		.background(Capsule().fill(Color.accentColor.opacity(0.14)))
		.transition(.scale(scale: 0.8).combined(with: .opacity))
	}
}

private struct ReplacementsTab: View {
	@Bindable var model: AppModel

	var body: some View {
		Form {
			Section {
				ForEach($model.settings.replacements) { $rule in
					HStack {
						TextField("Cuando escuche", text: $rule.from).labelsHidden()
						Image(systemName: "arrow.right").foregroundStyle(.secondary)
						TextField("Escribe", text: $rule.to).labelsHidden()
						Button {
							model.settings.replacements.removeAll { $0.id == rule.id }
						} label: {
							Image(systemName: "minus.circle.fill")
						}
						.buttonStyle(.plain).foregroundStyle(.secondary)
						.accessibilityLabel("Quitar reemplazo")
					}
				}
				Button("Agregar reemplazo") { model.settings.replacements.append(Replacement(from: "", to: "")) }
			} header: {
				Text("Se aplican después de transcribir, en orden y sin distinguir mayúsculas")
			} footer: {
				Text("Escribe \\n para un salto de línea. Sirven para comandos dictados como \"nueva línea\" o para lo que el vocabulario no alcance.")
			}
		}
		.formStyle(.grouped)
	}
}

private struct HistoryTab: View {
	let model: AppModel

	var body: some View {
		VStack(spacing: 0) {
			if model.history.entries.isEmpty {
				ContentUnavailableView("Sin dictados todavía", systemImage: "waveform", description: Text("Mantén \(model.settings.hotkey.label) en cualquier app y habla."))
			} else {
				List(model.history.entries) { entry in
					VStack(alignment: .leading, spacing: 4) {
						Text(entry.text).textSelection(.enabled)
						Text(caption(entry)).font(.caption).foregroundStyle(.secondary)
					}
					.padding(.vertical, 2)
					.contextMenu { Button("Copiar") { model.copy(entry) } }
				}
			}
			Divider()
			HStack {
				Text("Últimos \(History.limit), sólo el texto y sólo en esta Mac.").font(.caption).foregroundStyle(.secondary)
				Spacer()
				Button("Borrar historial", role: .destructive) { model.clearHistory() }
					.disabled(model.history.entries.isEmpty)
			}
			.padding(12)
		}
	}

	private func caption(_ entry: HistoryEntry) -> String {
		var parts = [entry.date.formatted(.relative(presentation: .named))]
		if let app = entry.app { parts.append(app) }
		parts.append("\(entry.words) palabras")
		parts.append(String(format: "%.0f s de audio", entry.seconds))
		return parts.joined(separator: " · ")
	}
}

private struct ModelTab: View {
	@Bindable var model: AppModel

	var body: some View {
		Form {
			Section {
				LabeledContent("Whisper large-v3-turbo") { ModelStatusLabel(status: model.modelStatus) }
				Text("1.5 GB en disco y cerca de 1.6 GB de memoria mientras está cargado. Todo se procesa en esta Mac.")
					.font(.callout).foregroundStyle(.secondary)
				HStack {
					if model.modelStatus == .missing || model.modelStatus.isFailure {
						Button("Descargar modelo", action: model.download)
					}
					if model.modelStatus == .ready {
						Button("Liberar memoria ahora", action: model.unloadNow)
					}
					if model.modelStatus == .unloaded {
						Button("Cargar ahora", action: model.preload)
					}
					Spacer()
					Button("Mostrar en Finder", action: model.revealModel).disabled(model.modelStatus == .missing)
				}
			}
			Section {
				Picker("Liberar memoria", selection: $model.settings.unloadAfterMinutes) {
					Text("Nunca").tag(0)
					Text("Después de 5 min sin dictar").tag(5)
					Text("Después de 30 min sin dictar").tag(30)
					Text("Después de 2 h sin dictar").tag(120)
				}
				Picker("Idioma", selection: $model.settings.language) {
					Text("Español").tag("es")
					Text("English").tag("en")
				}
			} footer: {
				Text("Cuando el modelo está liberado, el primer dictado tarda unos segundos más mientras vuelve a cargar.")
			}
		}
		.formStyle(.grouped)
	}
}

struct ModelStatusLabel: View {
	let status: ModelStatus

	var body: some View {
		switch status {
		case .missing: Label("Sin descargar", systemImage: "arrow.down.circle").foregroundStyle(.secondary)
		case let .downloading(p): ProgressView(value: p) { Text("Descargando \(Int(p * 100)) %") }.frame(width: 180)
		case .unloaded: Label("Descargado, en reposo", systemImage: "moon.zzz").foregroundStyle(.secondary)
		case .loading: HStack { ProgressView().controlSize(.small); Text("Cargando…") }
		case .ready: Label("Listo en memoria", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
		case let .failed(message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
		}
	}
}

struct FlowLayout: Layout {
	var spacing: CGFloat = 8

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let rows = arrange(subviews, width: proposal.width ?? .infinity)
		return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		for row in arrange(subviews, width: bounds.width) {
			var x = bounds.minX
			for index in row.items {
				let size = subviews[index].sizeThatFits(.unspecified)
				subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
				x += size.width + spacing
			}
		}
	}

	private struct Row {
		var items: [Int] = []
		var y: CGFloat = 0
		var width: CGFloat = 0
		var height: CGFloat = 0
	}

	private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
		var rows = [Row()]
		for index in subviews.indices {
			let size = subviews[index].sizeThatFits(.unspecified)
			if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
				let last = rows[rows.count - 1]
				rows.append(Row(y: last.y + last.height + spacing))
			}
			var row = rows[rows.count - 1]
			row.width += (row.items.isEmpty ? 0 : spacing) + size.width
			row.height = max(row.height, size.height)
			row.items.append(index)
			rows[rows.count - 1] = row
		}
		return rows
	}
}
