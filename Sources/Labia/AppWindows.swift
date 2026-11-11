import AppKit
import SwiftUI

/// Labia vive en la barra de menú (`LSUIElement`): no sale en el Dock ni en ⌘⇥ y sus ventanas se pierden detrás de
/// las demás. Mientras haya una ventana abierta se vuelve app normal, y al cerrar la última regresa.
@MainActor
enum AppWindows {
	private static var open: Set<String> = []

	static func opened(_ id: String) {
		open.insert(id)
		if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
		bringForward()
	}

	static func closed(_ id: String) {
		open.remove(id)
		guard open.isEmpty else { return }
		NSApp.setActivationPolicy(.accessory)
	}

	/// El cambio de política tarda un ciclo en surtir efecto: se activa y se ordena al frente después.
	static func bringForward() {
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(80))
			NSApp.activate()
			for window in NSApp.windows where window.isVisible && window.canBecomeMain {
				window.orderFrontRegardless()
			}
			NSApp.windows.last { $0.isVisible && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
		}
	}
}

private struct TrackedWindow: ViewModifier {
	let id: String

	func body(content: Content) -> some View {
		content
			.onAppear { AppWindows.opened(id) }
			.onDisappear { AppWindows.closed(id) }
	}
}

extension View {
	func labiaWindow(_ id: String) -> some View {
		modifier(TrackedWindow(id: id))
	}
}
