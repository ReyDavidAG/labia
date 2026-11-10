import Foundation

public enum GestureEvent: Equatable, Sendable {
	case keyDown(TimeInterval)
	case keyUp(TimeInterval)
	case escape
	case otherKey(TimeInterval)
	case tick(TimeInterval)
}

public enum GestureAction: Equatable, Sendable {
	case start
	case stop
	case lock
	case cancel
	case tooShort
	case chord
}

public struct GestureMachine: Sendable {
	public enum Phase: Equatable, Sendable {
		case idle
		case holding(since: TimeInterval)
		case tapPending(deadline: TimeInterval)
		case locked
	}

	public var minHold: TimeInterval
	public var doubleTapWindow: TimeInterval
	/// Otra tecla antes de esto es una combinación (⌥ + tecla) y no un dictado. Después se ignora:
	/// rozar una tecla a media frase borraba todo lo dictado.
	public var chordWindow: TimeInterval
	public private(set) var phase: Phase = .idle

	public init(minHold: TimeInterval = 0.3, doubleTapWindow: TimeInterval = 0.35, chordWindow: TimeInterval = 1) {
		self.minHold = minHold
		self.doubleTapWindow = doubleTapWindow
		self.chordWindow = chordWindow
	}

	public var isRecording: Bool { phase != .idle }
	public var swallowsEscape: Bool { isRecording }

	public mutating func handle(_ event: GestureEvent) -> GestureAction? {
		switch (phase, event) {
		case let (.idle, .keyDown(t)):
			phase = .holding(since: t)
			return .start
		case let (.holding(since), .keyUp(t)):
			if t - since < minHold {
				phase = .tapPending(deadline: t + doubleTapWindow)
				return nil
			}
			phase = .idle
			return .stop
		case let (.tapPending(deadline), .keyDown(t)) where t <= deadline:
			phase = .locked
			return .lock
		case let (.tapPending(deadline), .keyDown(t)) where t > deadline:
			phase = .holding(since: t)
			return .start
		case let (.tapPending(deadline), .tick(t)) where t > deadline:
			phase = .idle
			return .tooShort
		case (.locked, .keyDown):
			phase = .idle
			return .stop
		case (.holding, .escape), (.tapPending, .escape), (.locked, .escape):
			phase = .idle
			return .cancel
		case let (.holding(since), .otherKey(t)) where t - since < chordWindow:
			phase = .idle
			return .chord
		case (.tapPending, .otherKey):
			phase = .idle
			return .chord
		default:
			return nil
		}
	}

	public mutating func reset() { phase = .idle }
}
