import AppKit
import Carbon.HIToolbox

enum Paster {
	// Los gestores de portapapeles ignoran lo marcado así (nspasteboard.org).
	static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
	/// Si la app nunca lee el pegado (no hay campo de texto), se restaura de todos modos pasado este tiempo.
	static let readTimeout: Duration = .seconds(3)

	/// El texto del último pegado; vive aquí porque el portapapeles no retiene al proveedor.
	@MainActor private static var pending: LazyText?

	static func copy(_ text: String) {
		let board = NSPasteboard.general
		board.clearContents()
		board.setString(text, forType: .string)
	}

	@MainActor
	static func paste(_ text: String, restore: Bool, thenReturn: Bool = false) {
		guard !text.isEmpty else { return pressReturn() }
		let board = NSPasteboard.general
		let saved = restore ? snapshot(board) : nil
		// Datos diferidos: el texto se entrega cuando la app lo pide, y ese es el aviso de que ya pegó.
		// La app puede llegar tarde al ⌘V; restaurar antes pegaría el portapapeles viejo.
		let lazy = LazyText(text)
		pending = lazy
		let item = NSPasteboardItem()
		item.setDataProvider(lazy, forTypes: [.string])
		item.setData(Data(), forType: transient)
		board.clearContents()
		board.writeObjects([item])
		let mark = board.changeCount
		press(kVK_ANSI_V, flags: .maskCommand)
		Task { @MainActor in
			let deadline = ContinuousClock.now + readTimeout
			while !lazy.read, ContinuousClock.now < deadline {
				try? await Task.sleep(for: .milliseconds(20))
			}
			// La terminal descarta el Enter si llega mientras todavía procesa el pegado.
			if thenReturn {
				try? await Task.sleep(for: .milliseconds(150))
				pressReturn()
			}
			guard let saved else {
				// Sin restaurar, el texto se queda: que no dependa de que Labia siga abierta para entregarlo.
				if !lazy.read, board.changeCount == mark { copy(text) }
				return
			}
			try? await Task.sleep(for: .milliseconds(100))
			guard board.changeCount == mark else { return }
			board.clearContents()
			if !saved.isEmpty { board.writeObjects(saved) }
		}
	}

	private static func snapshot(_ board: NSPasteboard) -> [NSPasteboardItem] {
		(board.pasteboardItems ?? []).map { item in
			let copy = NSPasteboardItem()
			for type in item.types {
				if let data = item.data(forType: type) { copy.setData(data, forType: type) }
			}
			return copy
		}
	}

	static func pressReturn() {
		press(kVK_Return, flags: [])
	}

	private static func press(_ code: Int, flags: CGEventFlags) {
		let source = CGEventSource(stateID: .combinedSessionState)
		for down in [true, false] {
			let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)
			event?.flags = flags
			event?.post(tap: .cghidEventTap)
		}
	}
}

/// Entrega el texto cuando una app lo lee del portapapeles y anota que ya lo leyó.
private final class LazyText: NSObject, NSPasteboardItemDataProvider {
	let text: String
	private(set) var read = false

	init(_ text: String) {
		self.text = text
	}

	func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
		item.setString(text, forType: type)
		read = true
	}

	func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {}
}
