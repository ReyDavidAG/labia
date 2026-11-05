import Testing
@testable import LabiaCore

@Suite struct SendKeywordTests {
	let keys = SendKeyword.defaults

	@Test func stripsTheFinalKeywordAndAsksToSend() {
		#expect(SendKeyword.split("Revisa el build. Claude.", keywords: keys) == ("Revisa el build.", true))
		#expect(SendKeyword.split("Revisa el build, cloud", keywords: keys) == ("Revisa el build", true))
		#expect(SendKeyword.split("Sube el PR ¡Clod!", keywords: keys) == ("Sube el PR", true))
	}

	@Test func keywordAloneSendsWithoutText() {
		#expect(SendKeyword.split("Claude.", keywords: keys) == ("", true))
	}

	@Test func keywordElsewhereIsJustText() {
		#expect(SendKeyword.split("Pregúntale a Claude por el build.", keywords: keys) == ("Pregúntale a Claude por el build.", false))
		#expect(SendKeyword.split("Usa Cloudflare", keywords: keys) == ("Usa Cloudflare", false))
	}

	@Test func emptyListNeverSends() {
		#expect(SendKeyword.split("Hola Claude", keywords: []) == ("Hola Claude", false))
		#expect(SendKeyword.split("Hola Claude", keywords: [" "]) == ("Hola Claude", false))
	}
}
