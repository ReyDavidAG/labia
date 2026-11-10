import Testing
@testable import LabiaCore

/// Las mismas pruebas que `linux/tests/test_stream.py`.
@Suite struct LiveSessionTests {
	func words(_ items: String...) -> [Word] {
		items.enumerated().map { i, w in Word(Double(i) * 0.5, Double(i) * 0.5 + 0.4, w) }
	}

	func preferences(send: Bool = true) -> Preferences {
		var p = Preferences()
		p.vocabulary = []
		p.sendOnKeyword = send
		return p
	}

	/// Una pasada con la hipótesis dada, como `Session.step` de Python con el modelo de mentira.
	@discardableResult
	func step(_ s: LiveSession, _ hypothesis: [Word], screen: inout String) -> PassKind {
		guard let kind = s.nextPass()?.kind else { return .draft }
		let (back, add) = s.absorb(hypothesis, kind: kind)
		screen = String(screen.dropLast(back)) + add
		return kind
	}

	let second = [Float](repeating: 0, count: LiveSession.sampleRate)

	@Test func agreementCommitsOnlyWhatTwoPassesShare() {
		var a = LocalAgreement()
		#expect(a.update(words(" Hola", " mun")).isEmpty)
		#expect(a.update(words(" Hola", " mundo", " cómo")).map(\.text) == [" Hola"])
		#expect(a.update(words(" Hola", " mundo", " cómo", " estás")).map(\.text) == [" mundo", " cómo"])
		#expect(a.text == " Hola mundo cómo")
	}

	@Test func agreementSurvivesOneGarbagePass() {
		var a = LocalAgreement()
		a.update(words(" familia", " Parra."))
		a.update([Word(0, 0.9, " Parlo")])
		a.update(words(" familia", " Parra", " Su"))
		#expect(a.text == " familia Parra")
	}

	@Test func agreementDropsRepeatedOverlapAfterTrim() {
		var a = LocalAgreement()
		a.update(words(" uno", " dos"))
		a.update(words(" uno", " dos"))
		let again = [Word(0.45, 0.9, " dos"), Word(1.0, 1.4, " tres")]
		a.update(again)
		a.update(again)
		#expect(a.text == " uno dos tres")
	}

	@Test func diffAndHold() {
		#expect(LiveText.diff("Hola mundo", "Hola mundo, cómo") == (0, ", cómo"))
		#expect(LiveText.diff("Hola de velo", "Hola develop") == (5, "velop"))
		#expect(LiveText.diff("año", "ano") == (2, "no"))
		#expect(LiveText.holdLastWord("Hola mundo cómo") == "Hola mundo")
		#expect(LiveText.holdLastWord("Hola") == "")
	}

	@Test func typesProgressivelyAndSendsOnKeyword() {
		let s = LiveSession(preferences: preferences())
		s.feed(second)
		var screen = ""
		step(s, words(" Revisa", " el"), screen: &screen)
		#expect(screen == "")
		step(s, words(" Revisa", " el", " build,"), screen: &screen)
		#expect(screen == "Revisa")
		step(s, words(" Revisa", " el", " build,", " Claude."), screen: &screen)
		#expect(screen == "Revisa el")
		let (back, add, send) = s.finish(raw: " Revisa el build, Claude.")
		screen = String(screen.dropLast(back)) + add
		#expect(screen == "Revisa el build")
		#expect(send)
	}

	@Test func cleaningCanRetract() {
		let s = LiveSession(preferences: preferences(send: false))
		s.feed(second)
		var screen = ""
		step(s, words(" a", " de", " velo", " ya"), screen: &screen)
		step(s, words(" a", " de", " velo", " ya"), screen: &screen)
		#expect(screen == "a develop")
		_ = s.finish(raw: " a de velo ya")
		#expect(s.typed == "a develop ya ")
	}

	@Test func carefulPassCorrectsTypedWords() {
		let s = LiveSession(preferences: preferences(send: false))
		s.feed(second)
		var screen = ""
		let draft = words(" Abre", " el", " pul", " request", " ya")
		step(s, draft, screen: &screen)
		step(s, draft, screen: &screen)
		#expect(s.typed == "Abre el pul request")
		s.feed(second + second + second)
		#expect(step(s, words(" Abre", " el", " pull", " request", " ya"), screen: &screen) == .careful)
		#expect(s.typed == "Abre el pull request")
		#expect(screen == s.typed)
		_ = s.finish(raw: " Abre el pull request ya.")
		#expect(s.typed == "Abre el pull request ya. ")
	}

	@Test func carefulPassIgnoresGarbageAndSilentFinalErasesDraft() {
		let s = LiveSession(preferences: preferences(send: false))
		s.feed(second)
		var screen = ""
		let draft = words(" Uno", " dos", " tres", " cuatro")
		step(s, draft, screen: &screen)
		step(s, draft, screen: &screen)
		s.feed(second + second + second)
		step(s, words(" Gracias."), screen: &screen)
		#expect(s.typed == "Uno dos tres")
		let (back, _, _) = s.finish(raw: "")
		#expect(s.typed == "")
		#expect(back == "Uno dos tres".count)
	}

	@Test func emptyFinalPassKeepsALongDraft() {
		let s = LiveSession(preferences: preferences(send: false))
		s.feed(second)
		var screen = ""
		let draft = words(" Revisa", " que", " el", " build", " pase", " ya")
		step(s, draft, screen: &screen)
		step(s, draft, screen: &screen)
		#expect(screen == "Revisa que el build pase")
		let (back, add, _) = s.finish(raw: "")
		screen = String(screen.dropLast(back)) + add
		#expect(screen == "Revisa que el build pase ya ")
	}

	@Test func voiceAmongLongPausesIsNotSilence() {
		var audio = [Float](repeating: 0, count: 60 * LiveSession.sampleRate)
		#expect(!LiveSession.hasVoice(audio))
		for i in 0..<LiveSession.sampleRate { audio[i] = 0.02 }
		#expect(LiveSession.rms(audio) < LiveSession.silenceRMS)
		#expect(LiveSession.hasVoice(audio))
	}

	@Test func windowIsTrimmedPastTenSecondsKeepingCommittedText() {
		let s = LiveSession(preferences: preferences(send: false))
		var screen = ""
		for _ in 0..<11 { s.feed(second) }
		let hypothesis = words(" uno", " dos", " tres")
		step(s, hypothesis, screen: &screen)
		step(s, hypothesis, screen: &screen)
		#expect(s.nextPass()!.audio.count < 11 * LiveSession.sampleRate)
		#expect(screen == "uno dos")
	}

	@Test func longFinalPassKeepsTextBeforeTheWindow() {
		let s = LiveSession(preferences: preferences(send: false))
		var screen = ""
		for _ in 0..<11 { s.feed(second) }
		let hypothesis = words(" uno", " dos", " tres")
		step(s, hypothesis, screen: &screen)
		step(s, hypothesis, screen: &screen)
		for _ in 0..<20 { s.feed(second) }
		#expect(s.finalStart == 0)
		let final = [Word(0.5, 0.9, " dos"), Word(1.0, 1.4, " tres,"), Word(1.6, 1.9, " cuatro"), Word(2.0, 2.4, " cinco.")]
		let (back, add, _) = s.finish(words: final, from: 0)
		screen = String(screen.dropLast(back)) + add
		#expect(back == 0)
		#expect(screen == "uno dos tres cuatro cinco. ")
	}

	@Test func longFinalPassDropsAPhraseItPlacesLater() {
		let s = LiveSession(preferences: preferences(send: false))
		var screen = ""
		for _ in 0..<11 { s.feed(second) }
		let phrase = " que ya quede todo más sencillo y más fácil para ellos".split(separator: " ").map { " " + $0 }
		let said = phrase.enumerated().map { i, w in Word(Double(i) * 0.3, Double(i) * 0.3 + 0.25, w) }
		step(s, said + [Word(4, 4.3, " implementar")], screen: &screen)
		step(s, said + [Word(4, 4.3, " implementar")], screen: &screen)
		for _ in 0..<20 { s.feed(second) }
		let late = phrase.enumerated().map { i, w in Word(Double(i) * 0.3 + 3.2, Double(i) * 0.3 + 3.45, w) }
		let (back, add, _) = s.finish(words: late + [Word(7, 7.3, " implementar"), Word(7.4, 7.6, " ya.")], from: s.finalStart!)
		screen = String(screen.dropLast(back)) + add
		#expect(screen == "que ya quede todo más sencillo y más fácil para ellos implementar ya. ")
	}

	@Test func emptyLongFinalPassKeepsTheWordsHeardLive() {
		let s = LiveSession(preferences: preferences(send: false))
		var screen = ""
		for _ in 0..<11 { s.feed(second) }
		step(s, words(" uno", " dos", " tres"), screen: &screen)
		step(s, words(" uno", " dos", " tres"), screen: &screen)
		let late = [Word(1.6, 1.9, " cuatro"), Word(2.0, 2.4, " cinco"), Word(2.5, 2.9, " seis")]
		let voice = [Float](repeating: 0.1, count: LiveSession.sampleRate)
		for _ in 0..<3 {
			s.feed(voice)
			step(s, late, screen: &screen)
		}
		#expect(screen == "uno dos tres cuatro cinco")
		for _ in 0..<20 { s.feed(second) }
		let (back, add, _) = s.finish(words: [], from: s.finalStart!)
		screen = String(screen.dropLast(back)) + add
		#expect(screen == "uno dos tres cuatro cinco seis ")
	}

	@Test func shortRecordingsGetAFullFinalPass() {
		let s = LiveSession(preferences: preferences(send: false))
		for _ in 0..<11 { s.feed(second) }
		var screen = ""
		step(s, words(" uno", " dos", " tres"), screen: &screen)
		step(s, words(" uno", " dos", " tres"), screen: &screen)
		#expect(s.finalStart == nil)
	}

	@Test func aWindowWithNothingConfirmedStopsLivePasses() {
		let s = LiveSession(preferences: preferences(send: false))
		for _ in 0..<26 { s.feed(second) }
		#expect(s.nextPass() == nil)
		for _ in 0..<5 { s.feed(second) }
		#expect(s.finalStart == nil)
	}

	@Test func discardErasesEverything() {
		let s = LiveSession(preferences: preferences())
		s.feed(second)
		var screen = ""
		step(s, words(" hola", " mundo", " ya"), screen: &screen)
		step(s, words(" hola", " mundo", " ya"), screen: &screen)
		#expect(s.discard() == screen.count)
		#expect(s.typed == "")
	}

	@Test func carefulPassKeepsCaseOnlyDifferences() {
		let s = LiveSession(preferences: preferences(send: false))
		s.feed(second)
		var screen = ""
		let draft = words(" Revisa", " el", " bild", " ya")
		step(s, draft, screen: &screen)
		step(s, draft, screen: &screen)
		s.feed(second + second + second)
		step(s, words(" revisa", " el", " build", " ya"), screen: &screen)
		#expect(screen == "Revisa el build")
	}

	@Test func silenceAfterAnUnchangedPassSkipsThePass() {
		let s = LiveSession(preferences: preferences())
		let voice = [Float](repeating: 0.1, count: LiveSession.sampleRate)
		s.feed(voice)
		var screen = ""
		step(s, words(" hola", " mundo", " ya"), screen: &screen)
		step(s, words(" hola", " mundo", " ya"), screen: &screen)
		#expect(screen == "hola mundo")
		s.feed(second)
		#expect(s.nextPass() != nil)
		_ = s.absorb(words(" hola", " mundo", " ya", " va"), kind: .draft)
		s.feed(second)
		#expect(s.nextPass() != nil, "«va» falta por confirmar")
		_ = s.absorb(words(" hola", " mundo", " ya", " va"), kind: .draft)
		_ = s.absorb(words(" hola", " mundo", " ya", " va"), kind: .draft)
		s.feed(second)
		#expect(s.nextPass() == nil)
		s.feed(voice)
		#expect(s.nextPass() != nil)
	}
}
