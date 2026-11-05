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
	static func paste(_ text: String, restore: Bool) {
		let board = NSPasteboard.general
		let saved = restore ? snapshot(board) : nil
		board.clearContents()
		board.setString(text, forType: .string)
		board.setData(Data(), forType: transient)
		let mark = board.changeCount
		pressCommandV()
		guard let saved else { return }
		Task { @MainActor in
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

	private static func pressCommandV() {
		let source = CGEventSource(stateID: .combinedSessionState)
		let key = CGKeyCode(kVK_ANSI_V)
		for down in [true, false] {
			let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
			event?.flags = .maskCommand
			event?.post(tap: .cghidEventTap)
		}
	}
}
