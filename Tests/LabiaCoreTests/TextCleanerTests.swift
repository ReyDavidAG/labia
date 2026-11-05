import Foundation
import Testing
@testable import LabiaCore

@Suite struct TextCleanerTests {
	@Test func trimsAndCollapsesSpaces() {
		#expect(TextCleaner.clean("  Corre  el build ,  y  sube el release . ") == "Corre el build, y sube el release.")
	}

	@Test func dropsSilenceHallucinations() {
		#expect(TextCleaner.clean(" Subtítulos realizados por la comunidad de Amara.org") == "")
		#expect(TextCleaner.clean("¡Gracias por ver!") == "")
		#expect(TextCleaner.clean("Haz el commit. Gracias por ver.") == "Haz el commit.")
	}

	@Test func removesSpecialTokens() {
		#expect(TextCleaner.clean("<|startoftranscript|><|es|> Hola<|endoftext|>") == "Hola")
	}

	@Test func appliesReplacementsOnWholeWords() {
		let reps = [Replacement(from: "de velo", to: "develop"), Replacement(from: "lint", to: "lint")]
		#expect(TextCleaner.clean("Hago el push a De Velo.", replacements: reps) == "Hago el push a develop.")
		#expect(TextCleaner.clean("Un vestido develop", replacements: [Replacement(from: "velo", to: "X")]) == "Un vestido develop")
	}

	@Test func spokenNewLineAndPunctuation() {
		let reps = Settings.defaultReplacements
		#expect(TextCleaner.clean("primera nueva línea segunda punto y coma", replacements: reps) == "primera\nsegunda;")
	}

	@Test func replacementTargetIsLiteral() {
		let reps = [Replacement(from: "precio", to: "$1 USD")]
		#expect(TextCleaner.clean("el precio", replacements: reps) == "el $1 USD")
	}

	@Test func vocabularyJoinsSplitTermsAndFixesBrandCase() {
		let vocab = ["useApiQuery", "staleTime", "Vercel", "pull request", "front"]
		#expect(TextCleaner.clean("Usa el hook Use API Query con el stale time.", vocabulary: vocab) == "Usa el hook useApiQuery con el staleTime.")
		#expect(TextCleaner.clean("sube el release a vercel", vocabulary: vocab) == "sube el release a Vercel")
		#expect(TextCleaner.clean("Revisa el Pull Request", vocabulary: vocab) == "Revisa el pull request")
	}

	@Test func vocabularyNeverTouchesLowercaseWordsOrPunctuatedSpans() {
		let vocab = ["front", "staleTime"]
		#expect(TextCleaner.clean("Front primero.", vocabulary: vocab) == "Front primero.")
		#expect(TextCleaner.clean("stale. Time", vocabulary: vocab) == "stale. Time")
	}

	@Test func emptyReplacementIsIgnored() {
		#expect(TextCleaner.clean("hola", replacements: [Replacement(from: " ", to: "x")]) == "hola")
	}
}

@Suite struct SettingsTests {
	@Test func promptListsVocabularyWithinLimit() {
		var s = Settings()
		s.vocabulary = ["commit", " ", "useApiQuery"]
		#expect(s.prompt == "Vocabulario: commit, useApiQuery.")
		s.vocabulary = Array(repeating: "palabralarga", count: 200)
		#expect((s.prompt?.count ?? 0) <= Settings.maxPromptCharacters + 1)
		s.vocabulary = []
		#expect(s.prompt == nil)
	}

	@Test func decodingKeepsDefaultsForMissingKeys() throws {
		let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"hotkey":"fn","sounds":false}"#.utf8))
		#expect(s.hotkey == .fn)
		#expect(!s.sounds)
		#expect(s.unloadAfterMinutes == 30)
		#expect(s.vocabulary == Settings.defaultVocabulary)
	}

	@Test func roundTripsThroughDefaults() throws {
		let defaults = try #require(UserDefaults(suiteName: "labia.tests.\(UUID())"))
		var s = Settings()
		s.hotkey = .rightCommand
		s.unloadAfterMinutes = 0
		s.save(defaults)
		let back = Settings.load(defaults)
		#expect(back.hotkey == .rightCommand)
		#expect(back.unloadAfterMinutes == 0)
	}
}

@Suite struct HistoryTests {
	@Test func keepsNewestFirstAndCapsAtLimit() {
		var h = History()
		for i in 0..<60 { h.add(HistoryEntry(text: "frase \(i)", seconds: 1)) }
		#expect(h.entries.count == History.limit)
		#expect(h.entries.first?.text == "frase 59")
	}

	@Test func savesAndLoads() throws {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("labia-\(UUID())/history.json")
		var h = History()
		h.add(HistoryEntry(text: "Haz el commit", seconds: 2.5, app: "Terminal"))
		try h.save(to: url)
		let back = History.load(from: url)
		#expect(back.entries.first?.text == "Haz el commit")
		#expect(back.entries.first?.app == "Terminal")
		#expect(back.entries.first?.words == 3)
	}
}
