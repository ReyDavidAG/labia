import Foundation

/// Los últimos dictados en WAV, para revisar una falla con `Labia --simulate`. Sólo se guardan si se activa
/// `saveRecordings`. El nombre lleva la fecha, así que el orden alfabético es el cronológico.
public enum RecordingArchive {
	public static let kept = 20

	public static func name(for date: Date) -> String {
		let format = DateFormatter()
		format.locale = Locale(identifier: "en_US_POSIX")
		format.dateFormat = "yyyy-MM-dd HH.mm.ss"
		return format.string(from: date) + ".wav"
	}

	/// Las que sobran, de la más vieja a la más nueva.
	public static func stale(_ names: [String], keeping count: Int = kept) -> [String] {
		Array(names.filter { $0.hasSuffix(".wav") }.sorted().dropLast(count))
	}
}
