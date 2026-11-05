import Foundation

public struct Replacement: Codable, Equatable, Hashable, Sendable, Identifiable {
	public var id = UUID()
	public var from: String
	public var to: String

	public init(from: String, to: String) {
		self.from = from
		self.to = to
	}

	enum CodingKeys: String, CodingKey { case from, to }
}

public enum TextCleaner {
	// Whisper inventa estas frases cuando el audio es silencio o ruido.
	static let hallucinations = [
		"subtítulos realizados por la comunidad de amara.org",
		"subtítulos por la comunidad de amara.org",
		"subtitulado por la comunidad de amara.org",
		"gracias por ver el video",
		"gracias por ver",
		"¡gracias por ver!",
		"suscríbete al canal",
		"no olvides suscribirte",
		"[música]",
		"(música)",
		"[blank_audio]",
		"[ruido]",
		"...",
	]

	public static func clean(_ raw: String, replacements: [Replacement] = [], vocabulary: [String] = []) -> String {
		var text = raw.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
		text = stripHallucinations(text)
		text = applyVocabulary(text, vocabulary)
		for r in replacements where !r.from.trimmingCharacters(in: .whitespaces).isEmpty {
			text = replace(r, in: text)
		}
		return tidy(text)
	}

	static func key(_ s: String) -> String {
		String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
	}

	static func applyVocabulary(_ text: String, _ vocabulary: [String]) -> String {
		let terms = vocabulary.map { $0.trimmingCharacters(in: .whitespaces) }.filter { key($0).count >= 3 }
		guard !terms.isEmpty, let wordRegex = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#) else { return text }
		let byKey = Dictionary(terms.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
		let ns = text as NSString
		let words = wordRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
		var edits: [(NSRange, String)] = []
		var i = 0
		while i < words.count {
			var matched = false
			for n in stride(from: min(4, words.count - i), through: 1, by: -1) {
				let span = NSRange(location: words[i].location, length: NSMaxRange(words[i + n - 1]) - words[i].location)
				let original = ns.substring(with: span)
				if n > 1, original.range(of: #"[^\p{L}\p{N} \-]"#, options: .regularExpression) != nil { continue }
				guard let term = byKey[key(original)], term != original else { continue }
				if n == 1, term == term.lowercased() { continue }
				edits.append((span, term))
				i += n
				matched = true
				break
			}
			if !matched { i += 1 }
		}
		let out = NSMutableString(string: text)
		for (range, term) in edits.reversed() { out.replaceCharacters(in: range, with: term) }
		return out as String
	}

	static func stripHallucinations(_ text: String) -> String {
		var out = text.trimmingCharacters(in: .whitespacesAndNewlines)
		var changed = true
		while changed, !out.isEmpty {
			changed = false
			let lower = out.lowercased()
			for h in hallucinations {
				if lower == h || lower == h + "." {
					return ""
				}
				for candidate in [h + ".", h] where lower.hasSuffix(" " + candidate) {
					out = String(out.dropLast(candidate.count)).trimmingCharacters(in: .whitespaces)
					changed = true
					break
				}
				if changed { break }
			}
		}
		return out
	}

	static func replace(_ r: Replacement, in text: String) -> String {
		let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: r.from.trimmingCharacters(in: .whitespaces)) + "(?![\\p{L}\\p{N}])"
		guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
		let to = NSRegularExpression.escapedTemplate(for: r.to.replacingOccurrences(of: "\\n", with: "\n"))
		return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: to)
	}

	static func tidy(_ text: String) -> String {
		var out = text
		let rules: [(String, String)] = [
			(#"[ \t]+"#, " "),
			(#" *\n *"#, "\n"),
			(#" +([,.;:!?)\]])"#, "$1"),
			(#"([(\[¿¡]) +"#, "$1"),
		]
		for (pattern, template) in rules {
			out = out.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
		}
		return out.trimmingCharacters(in: .whitespaces)
	}
}
