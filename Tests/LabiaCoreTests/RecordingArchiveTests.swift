import Foundation
import Testing
@testable import LabiaCore

@Suite struct RecordingArchiveTests {
	@Test func namesSortByDate() {
		let early = RecordingArchive.name(for: Date(timeIntervalSince1970: 1_000))
		let late = RecordingArchive.name(for: Date(timeIntervalSince1970: 100_000))
		#expect(early < late)
		#expect(late.hasSuffix(".wav"))
	}

	@Test func dropsOnlyTheOldestBeyondTheLimit() {
		let names = ["2026-11-10 15.52.45.wav", "2026-11-09 08.00.00.wav", "notes.txt", "2026-11-10 15.53.13.wav"]
		#expect(RecordingArchive.stale(names, keeping: 2) == ["2026-11-09 08.00.00.wav"])
		#expect(RecordingArchive.stale(names, keeping: 5).isEmpty)
	}
}
