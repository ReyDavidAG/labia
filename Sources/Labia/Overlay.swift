import AppKit
import SwiftUI

@MainActor
final class Overlay {
	static let size = NSSize(width: 440, height: 96)

	private var panel: NSPanel?

	func show(_ model: AppModel) {
		let panel = panel ?? make(model)
		self.panel = panel
		place(panel)
		panel.orderFrontRegardless()
	}

	func hide() {
		panel?.orderOut(nil)
	}

	private func make(_ model: AppModel) -> NSPanel {
		let panel = NSPanel(
			contentRect: NSRect(origin: .zero, size: Self.size),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: true
		)
		panel.level = .statusBar
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = false
		panel.ignoresMouseEvents = true
		panel.hidesOnDeactivate = false
		panel.isMovable = false
		panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
		let host = NSHostingView(rootView: PillView(model: model))
		host.frame = NSRect(origin: .zero, size: Self.size)
		panel.contentView = host
		return panel
	}

	private func place(_ panel: NSPanel) {
		let mouse = NSEvent.mouseLocation
		let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
		guard let frame = screen?.visibleFrame else { return }
		panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 12))
	}
}
