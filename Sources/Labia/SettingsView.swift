import AppKit
import LabiaCore
import SwiftUI

/// Ajustes con barra lateral, como los de macOS (`propuesta/v2`). La barra es propia: la de `NavigationSplitView`
/// no se dibuja en las capturas de `--screenshots`.
struct SettingsView: View {
	static let windowID = "settings"

	@Bindable var model: AppModel

	var body: some View {
		HStack(spacing: 0) {
			sidebar
			Divider()
			detail
				.id(model.settingsTab)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.navigationTitle(model.settingsTab.title)
		.frame(minWidth: 820, minHeight: 560)
		.tint(Brand.violet)
		.environment(\.locale, .labia)
		.onAppear { model.refreshPermissions() }
	}

	private var sidebar: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 2) {
				SidebarRow(tab: .summary, selection: $model.settingsTab)
				SidebarTitle("Dictado")
				SidebarRow(tab: .general, selection: $model.settingsTab)
				SidebarRow(tab: .vocabulary, selection: $model.settingsTab, count: model.settings.vocabulary.count)
				SidebarRow(tab: .replacements, selection: $model.settingsTab, count: model.settings.replacements.count)
				SidebarRow(tab: .history, selection: $model.settingsTab)
				SidebarTitle("Sistema")
				SidebarRow(tab: .model, selection: $model.settingsTab)
				SidebarRow(tab: .permissions, selection: $model.settingsTab, warning: !model.micGranted || !model.accessibilityGranted)
				SidebarRow(tab: .updates, selection: $model.settingsTab)
			}
			.padding(10)
		}
		.frame(width: 216)
		.background(Color.primary.opacity(0.035))
	}

	@ViewBuilder private var detail: some View {
		switch model.settingsTab {
		case .summary: SummaryPane(model: model)
		case .general: GeneralPane(model: model)
		case .vocabulary: VocabularyPane(model: model)
		case .replacements: ReplacementsPane(model: model)
		case .history: HistoryPane(model: model)
		case .model: ModelPane(model: model)
		case .permissions: PermissionsPane(model: model)
		case .updates: UpdatesPane(model: model)
		}
	}
}

private struct SidebarTitle: View {
	let text: String
	init(_ text: String) { self.text = text }

	var body: some View {
		Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 2)
	}
}

private struct SidebarRow: View {
	let tab: SettingsTab
	@Binding var selection: SettingsTab
	var count: Int?
	var warning = false
	@State private var hovering = false

	var body: some View {
		Button { selection = tab } label: {
			HStack(spacing: 9) {
				IconTile(symbol: tab.symbol, color: tab.color)
				Text(tab.title).font(.system(size: 13))
				Spacer(minLength: 4)
				if warning {
					Image(systemName: "exclamationmark.circle.fill").foregroundStyle(selected ? .white : .orange)
				} else if let count {
					Text("\(count)").font(.system(size: 11)).monospacedDigit().opacity(0.65)
				}
			}
			.foregroundStyle(selected ? .white : .primary)
			.padding(.horizontal, 8).padding(.vertical, 5)
			.background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? AnyShapeStyle(Brand.violet.gradient) : AnyShapeStyle(Color.primary.opacity(hovering ? 0.06 : 0))))
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
		.accessibilityAddTraits(selected ? .isSelected : [])
	}

	private var selected: Bool { selection == tab }
}

extension SettingsTab {
	var color: Color {
		switch self {
		case .summary: Brand.violet
		case .general: Color(red: 1, green: 0.48, blue: 0.27)
		case .vocabulary: Color(red: 0.18, green: 0.61, blue: 1)
		case .replacements: Color(red: 0.08, green: 0.72, blue: 0.65)
		case .history: Color(red: 0.55, green: 0.36, blue: 0.96)
		case .model: Color(red: 0.39, green: 0.45, blue: 0.55)
		case .permissions: Color(red: 0.13, green: 0.66, blue: 0.38)
		case .updates: Color(red: 0.88, green: 0.27, blue: 0.48)
		}
	}
}

/// Interruptor con una línea de explicación abajo.
struct DetailToggle: View {
	let title: String
	var detail: String?
	@Binding var isOn: Bool

	var body: some View {
		Toggle(isOn: $isOn) {
			Text(title)
			if let detail { Text(detail) }
		}
	}
}

/// El icono real de la app si está abierta; si no, su inicial en un mosaico.
struct AppBadge: View {
	let name: String?

	var body: some View {
		if let icon {
			Image(nsImage: icon).resizable().frame(width: 28, height: 28)
		} else {
			Text(String((name ?? "?").prefix(1)).uppercased())
				.font(.system(size: 12, weight: .bold))
				.foregroundStyle(.white)
				.frame(width: 28, height: 28)
				.background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.secondary.gradient))
		}
	}

	private var icon: NSImage? {
		guard let name else { return nil }
		return NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.icon
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
