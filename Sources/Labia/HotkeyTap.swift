import CoreGraphics
import Foundation
import LabiaCore

final class HotkeyTap {
	static let escapeKeyCode: Int64 = 53

	var hotkey: Hotkey = .rightOption {
		didSet { isDown = false }
	}
	var isEnabled = true
	var onEvent: ((GestureEvent) -> Bool)?

	private var tap: CFMachPort?
	private var isDown = false

	var isRunning: Bool { tap != nil }

	@discardableResult
	func start() -> Bool {
		if tap != nil { return true }
		let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue)
		guard let tap = CGEvent.tapCreate(
			tap: .cgSessionEventTap,
			place: .headInsertEventTap,
			options: .defaultTap,
			eventsOfInterest: mask,
			callback: { _, type, event, refcon in
				guard let refcon else { return Unmanaged.passUnretained(event) }
				return Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue().process(type, event)
			},
			userInfo: Unmanaged.passUnretained(self).toOpaque()
		) else { return false }
		let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
		CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
		CGEvent.tapEnable(tap: tap, enable: true)
		self.tap = tap
		return true
	}

	private func process(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
		let pass = Unmanaged.passUnretained(event)
		if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
			if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
			return pass
		}
		guard isEnabled, let onEvent else { return pass }
		guard event.getIntegerValueField(.eventSourceUserData) != Paster.syntheticMark else { return pass }
		let code = event.getIntegerValueField(.keyboardEventKeycode)
		let now = ProcessInfo.processInfo.systemUptime
		switch type {
		case .flagsChanged:
			guard code == hotkey.keyCode else {
				_ = onEvent(.otherKey)
				return pass
			}
			let down = event.flags.rawValue & hotkey.deviceMask != 0
			guard down != isDown else { return pass }
			isDown = down
			_ = onEvent(down ? .keyDown(now) : .keyUp(now))
		case .keyDown:
			if code == Self.escapeKeyCode {
				return onEvent(.escape) ? nil : pass
			}
			_ = onEvent(.otherKey)
		default:
			break
		}
		return pass
	}
}
