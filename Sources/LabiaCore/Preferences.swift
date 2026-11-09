import Foundation

public enum Hotkey: String, Codable, CaseIterable, Sendable, Identifiable {
	case rightOption, rightCommand, fn

	public var id: String { rawValue }

	public var keyCode: Int64 {
		switch self {
		case .rightOption: 61
		case .rightCommand: 54
		case .fn: 63
		}
	}

	public var deviceMask: UInt64 {
		switch self {
		case .rightOption: 0x40
		case .rightCommand: 0x10
		case .fn: 0x80_0000
		}
	}

	public var symbol: String {
		switch self {
		case .rightOption: "⌥"
		case .rightCommand: "⌘"
		case .fn: "fn"
		}
	}

	public var label: String {
		switch self {
		case .rightOption: "⌥ derecho"
		case .rightCommand: "⌘ derecho"
		case .fn: "fn"
		}
	}
}

public struct Preferences: Codable, Equatable, Sendable {
	public static let defaultVocabulary = [
		"develop", "pull request", "deploy", "endpoint", "lint", "cron", "GitHub", "Vercel", "Supabase",
	]
	public static let defaultReplacements = [
		Replacement(from: "nueva línea", to: "\\n"),
		Replacement(from: "punto y coma", to: ";"),
		Replacement(from: "de velo", to: "develop"),
	]
	public static let maxPromptCharacters = 600

	public var hotkey: Hotkey = .rightOption
	public var autoPaste = true
	public var liveTyping = true
	public var restoreClipboard = true
	public var trailingSpace = true
	public var sendOnKeyword = true
	public var sendKeywords = SendKeyword.defaults
	public var sounds = true
	public var showPill = true
	public var language = "es"
	public var vocabulary = Preferences.defaultVocabulary
	public var replacements = Preferences.defaultReplacements
	public var unloadAfterMinutes = 30
	public var maxRecordingSeconds = 300

	public init() {}

	public init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		let d = Preferences()
		hotkey = (try? c.decode(Hotkey.self, forKey: .hotkey)) ?? d.hotkey
		autoPaste = (try? c.decode(Bool.self, forKey: .autoPaste)) ?? d.autoPaste
		liveTyping = (try? c.decode(Bool.self, forKey: .liveTyping)) ?? d.liveTyping
		restoreClipboard = (try? c.decode(Bool.self, forKey: .restoreClipboard)) ?? d.restoreClipboard
		trailingSpace = (try? c.decode(Bool.self, forKey: .trailingSpace)) ?? d.trailingSpace
		sendOnKeyword = (try? c.decode(Bool.self, forKey: .sendOnKeyword)) ?? d.sendOnKeyword
		sendKeywords = (try? c.decode([String].self, forKey: .sendKeywords)) ?? d.sendKeywords
		sounds = (try? c.decode(Bool.self, forKey: .sounds)) ?? d.sounds
		showPill = (try? c.decode(Bool.self, forKey: .showPill)) ?? d.showPill
		language = (try? c.decode(String.self, forKey: .language)) ?? d.language
		vocabulary = (try? c.decode([String].self, forKey: .vocabulary)) ?? d.vocabulary
		replacements = (try? c.decode([Replacement].self, forKey: .replacements)) ?? d.replacements
		unloadAfterMinutes = (try? c.decode(Int.self, forKey: .unloadAfterMinutes)) ?? d.unloadAfterMinutes
		maxRecordingSeconds = (try? c.decode(Int.self, forKey: .maxRecordingSeconds)) ?? d.maxRecordingSeconds
	}

	public var prompt: String? {
		let words = vocabulary.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
		guard !words.isEmpty else { return nil }
		var out = "Vocabulario:"
		for w in words {
			let next = out + (out.hasSuffix(":") ? " " : ", ") + w
			if next.count > Preferences.maxPromptCharacters { break }
			out = next
		}
		return out + "."
	}

	public static func load(_ defaults: UserDefaults = .standard, key: String = "settings") -> Preferences {
		guard let data = defaults.data(forKey: key), let s = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
		return s
	}

	public func save(_ defaults: UserDefaults = .standard, key: String = "settings") {
		if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: key) }
	}
}
