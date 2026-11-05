import Foundation

public enum SendKeyword {
	public static let defaults = ["Claude", "cloud", "clod"]

	public static func split(_ text: String, keywords: [String]) -> (text: String, send: Bool) {
		let keys = Set(keywords.map(key).filter { !$0.isEmpty })
		guard !keys.isEmpty,
			let match = text.range(of: #"[\p{L}\p{N}]+[^\p{L}\p{N}]*$"#, options: .regularExpression),
			keys.contains(key(String(text[match])))
		else { return (text, false) }
		let rest = text[..<match.lowerBound].replacingOccurrences(of: #"[\s,;:¡¿«“"(-]+$"#, with: "", options: .regularExpression)
		return (rest.trimmingCharacters(in: .whitespacesAndNewlines), true)
	}

	static func key(_ word: String) -> String {
		String(word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
			.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
	}
}
