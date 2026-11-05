import Foundation

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
	public var id = UUID()
	public var text: String
	public var date: Date
	public var seconds: Double
	public var app: String?

	public init(text: String, date: Date = .now, seconds: Double, app: String? = nil) {
		self.text = text
		self.date = date
		self.seconds = seconds
		self.app = app
	}

	public var words: Int { text.split(whereSeparator: \.isWhitespace).count }
}

public struct History: Codable, Equatable, Sendable {
	public static let limit = 50
	public private(set) var entries: [HistoryEntry] = []

	public init(entries: [HistoryEntry] = []) {
		self.entries = Array(entries.prefix(History.limit))
	}

	public mutating func add(_ entry: HistoryEntry) {
		entries.insert(entry, at: 0)
		if entries.count > History.limit { entries.removeLast(entries.count - History.limit) }
	}

	public mutating func clear() { entries.removeAll() }

	public static func load(from url: URL) -> History {
		guard let data = try? Data(contentsOf: url) else { return History() }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return (try? decoder.decode(History.self, from: data)) ?? History()
	}

	public func save(to url: URL) throws {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		try encoder.encode(self).write(to: url, options: [.atomic])
	}
}
