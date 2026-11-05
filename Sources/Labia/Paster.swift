import AppKit
import Carbon.HIToolbox

enum Paster {
	// Los gestores de portapapeles ignoran lo marcado así (nspasteboard.org).
	static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

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
		board.clearContents()
		board.setString(text, forType: .string)
		board.setData(Data(), forType: transient)
		let mark = board.changeCount
		press(kVK_ANSI_V, flags: .maskCommand)
		Task { @MainActor in
			// La terminal descarta el Enter si llega mientras todavía procesa el pegado.
			if thenReturn {
				try? await Task.sleep(for: .milliseconds(150))
				pressReturn()
			}
			guard let saved else { return }
			try? await Task.sleep(for: .milliseconds(600))
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
