import Testing
@testable import LabiaCore

@Suite struct GestureMachineTests {
	@Test func holdAndRelease() {
		var m = GestureMachine()
		#expect(m.handle(.keyDown(0)) == .start)
		#expect(m.isRecording)
		#expect(m.handle(.keyUp(1.2)) == .stop)
		#expect(m.phase == .idle)
	}

	@Test func shortTapCancelsAfterWindow() {
		var m = GestureMachine()
		_ = m.handle(.keyDown(0))
		#expect(m.handle(.keyUp(0.1)) == nil)
		#expect(m.handle(.tick(0.3)) == nil)
		#expect(m.handle(.tick(0.5)) == .tooShort)
		#expect(!m.isRecording)
	}

	@Test func doubleTapLocksAndNextPressStops() {
		var m = GestureMachine()
		_ = m.handle(.keyDown(0))
		_ = m.handle(.keyUp(0.1))
		#expect(m.handle(.keyDown(0.3)) == .lock)
		#expect(m.handle(.keyUp(0.35)) == nil)
		#expect(m.handle(.tick(10)) == nil)
		#expect(m.handle(.keyDown(12)) == .stop)
		#expect(m.handle(.keyUp(12.1)) == nil)
		#expect(m.phase == .idle)
	}

	@Test func lateSecondPressStartsAgain() {
		var m = GestureMachine()
		_ = m.handle(.keyDown(0))
		_ = m.handle(.keyUp(0.1))
		#expect(m.handle(.keyDown(1)) == .start)
	}

	@Test func escapeCancelsInEveryRecordingPhase() {
		var a = GestureMachine()
		_ = a.handle(.keyDown(0))
		#expect(a.swallowsEscape)
		#expect(a.handle(.escape) == .cancel)

		var b = GestureMachine()
		_ = b.handle(.keyDown(0)); _ = b.handle(.keyUp(0.1)); _ = b.handle(.keyDown(0.2))
		#expect(b.handle(.escape) == .cancel)

		var c = GestureMachine()
		#expect(!c.swallowsEscape)
		#expect(c.handle(.escape) == nil)
	}

	@Test func chordWithAnotherKeyIsNotDictation() {
		var m = GestureMachine()
		_ = m.handle(.keyDown(0))
		#expect(m.handle(.otherKey(0.2)) == .chord)
		#expect(m.handle(.keyUp(0.5)) == nil)
	}

	@Test func anotherKeyLateInADictationKeepsRecording() {
		var m = GestureMachine()
		_ = m.handle(.keyDown(0))
		#expect(m.handle(.otherKey(5)) == nil)
		#expect(m.handle(.keyUp(8)) == .stop)
	}

	@Test func typingWhileLockedKeepsRecording() {
		var m = GestureMachine()
		_ = m.handle(.keyDown(0)); _ = m.handle(.keyUp(0.1)); _ = m.handle(.keyDown(0.2))
		#expect(m.handle(.otherKey(0.5)) == nil)
		#expect(m.phase == .locked)
	}
}
