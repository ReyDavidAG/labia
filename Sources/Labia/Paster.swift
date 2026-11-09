import AppKit
import Carbon.HIToolbox

enum Paster {
	// Los gestores de portapapeles ignoran lo marcado así (nspasteboard.org).
	static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
	/// Si la app nunca lee el pegado (no hay campo de texto), se restaura de todos modos pasado este tiempo.
	static let readTimeout: Duration = .seconds(3)
	/// Marca de las teclas que manda Labia, para que el atajo no las confunda con una combinación y corte el dictado.
	static let syntheticMark: Int64 = 0x4C61_6269

	/// El texto del último pegado; vive aquí porque el portapapeles no retiene al proveedor.
	@MainActor private static var pending: LazyText?

	/// El `changeCount` del último pegado de Labia: si cambió, alguien más copió algo y no se toca.
	@MainActor private(set) static var pastedCount = -1

	static func copy(_ text: String) {
		let board = NSPasteboard.general
		board.clearContents()
		board.setString(text, forType: .string)
	}

	@MainActor
	static func paste(_ text: String, restore: Bool, thenReturn: Bool = false) {
		guard !text.isEmpty else { return pressReturn() }
		let saved = restore ? snapshot() : nil
		Task { @MainActor in
			let read = await pasteAndWait(text)
			// La terminal descarta el Enter si llega mientras todavía procesa el pegado.
			if thenReturn {
				try? await Task.sleep(for: .milliseconds(150))
				pressReturn()
			}
			guard let saved else {
				// Sin restaurar, el texto se queda: que no dependa de que Labia siga abierta para entregarlo.
				if !read, NSPasteboard.general.changeCount == pastedCount { copy(text) }
				return
			}
			try? await Task.sleep(for: .milliseconds(100))
			restoreIfUntouched(saved)
		}
	}

	/// Pega con ⌘V y espera a que la app lea el texto (o a `readTimeout`). Regresa si lo leyó.
	/// Datos diferidos: el texto se entrega cuando la app lo pide, y ese es el aviso de que ya pegó.
	/// La app puede llegar tarde al ⌘V (todavía procesando retrocesos); cambiar el portapapeles antes pegaría otra cosa.
	@MainActor
	@discardableResult
	static func pasteAndWait(_ text: String) async -> Bool {
		let board = NSPasteboard.general
		let lazy = LazyText(text)
		pending = lazy
		let item = NSPasteboardItem()
		item.setDataProvider(lazy, forTypes: [.string])
		item.setData(Data(), forType: transient)
		board.clearContents()
		board.writeObjects([item])
		pastedCount = board.changeCount
		press(kVK_ANSI_V, flags: .maskCommand)
		let deadline = ContinuousClock.now + readTimeout
		while !lazy.read, ContinuousClock.now < deadline {
			try? await Task.sleep(for: .milliseconds(15))
		}
		return lazy.read
	}

	@MainActor
	static func snapshot() -> [NSPasteboardItem] {
		(NSPasteboard.general.pasteboardItems ?? []).map { item in
			let copy = NSPasteboardItem()
			for type in item.types {
				if let data = item.data(forType: type) { copy.setData(data, forType: type) }
			}
			return copy
		}
	}

	@MainActor
	static func restoreIfUntouched(_ saved: [NSPasteboardItem]) {
		let board = NSPasteboard.general
		guard board.changeCount == pastedCount else { return }
		board.clearContents()
		if !saved.isEmpty { board.writeObjects(saved) }
	}

	static func pressReturn() {
		press(kVK_Return, flags: [])
	}

	static func deleteBackward(_ count: Int) {
		for _ in 0..<count { press(kVK_Delete, flags: []) }
	}

	static func typeSpaces(_ count: Int) {
		for _ in 0..<count { press(kVK_Space, flags: []) }
	}

	private static func press(_ code: Int, flags: CGEventFlags) {
		// Estado privado: que no se le sume el ⌥ que el usuario mantiene para dictar (⌥⌫ borraría palabras enteras).
		let source = CGEventSource(stateID: .privateState)
		for down in [true, false] {
			let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)
			event?.flags = flags
			event?.setIntegerValueField(.eventSourceUserData, value: syntheticMark)
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
