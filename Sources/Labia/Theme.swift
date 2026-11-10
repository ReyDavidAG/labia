import SwiftUI

/// Los colores del ícono «Dicho y escrito».
enum Brand {
	static let violetLight = Color(red: 0.459, green: 0.376, blue: 0.953)
	static let violet = Color(red: 0.353, green: 0.263, blue: 0.886)
	static let violetDeep = Color(red: 0.243, green: 0.173, blue: 0.800)
	static let lime = Color(red: 0.863, green: 1, blue: 0.373)
	static let indigo = Color(red: 0.129, green: 0.063, blue: 0.416)

	static let gradient = LinearGradient(colors: [violetLight, violetDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Mosaico de color con un símbolo, como los de Ajustes del Sistema.
struct IconTile: View {
	let symbol: String
	let color: Color
	var size: CGFloat = 22

	var body: some View {
		Image(systemName: symbol)
			.font(.system(size: size * 0.55, weight: .semibold))
			.foregroundStyle(.white)
			.frame(width: size, height: size)
			.background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(color.gradient))
	}
}

/// La onda que habla: barras índigo que suben y bajan, como en el ícono.
struct TalkingBars: View {
	var count = 4
	var width: CGFloat = 7
	var height: CGFloat = 44
	var color: Color = Brand.indigo
	var animated = true
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private static let shape: [CGFloat] = [0.4, 0.9, 0.6, 0.75, 0.5]

	var body: some View {
		TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated || reduceMotion)) { context in
			let t = context.date.timeIntervalSinceReferenceDate
			HStack(spacing: width * 0.7) {
				ForEach(0..<count, id: \.self) { i in
					let base = Self.shape[i % Self.shape.count]
					let wave = animated && !reduceMotion ? 0.72 + 0.28 * sin(t * 5.5 + Double(i) * 1.3) : 1
					Capsule().fill(color).frame(width: width, height: height * base * wave)
				}
			}
			.frame(height: height)
		}
	}
}

/// La burbuja lima con la onda y el cursor: la marca en grande.
struct BrandBubble: View {
	var scale: CGFloat = 1

	var body: some View {
		HStack(spacing: 14 * scale) {
			TalkingBars(width: 7 * scale, height: 44 * scale)
			Capsule().fill(Brand.indigo).frame(width: 4 * scale, height: 40 * scale)
		}
		.padding(.horizontal, 26 * scale)
		.padding(.vertical, 22 * scale)
		.background(RoundedRectangle(cornerRadius: 28 * scale, style: .continuous).fill(Brand.lime))
		.shadow(color: Brand.indigo.opacity(0.35), radius: 24 * scale, y: 14 * scale)
	}
}

/// Una tecla dibujada: ⌥ derecho, esc.
struct Keycap: View {
	let text: String
	var onBrand = false

	var body: some View {
		Text(text)
			.font(.system(size: 12, weight: .semibold))
			.padding(.horizontal, 8)
			.padding(.vertical, 2)
			.background(
				RoundedRectangle(cornerRadius: 6, style: .continuous)
					.fill(onBrand ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(.background))
					.shadow(color: .black.opacity(onBrand ? 0 : 0.18), radius: 0, y: 1)
			)
			.overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(onBrand ? 0 : 0.1)))
	}
}

/// Estado con punto de color: «Concedido», «Falta».
struct StatusBadge: View {
	let text: String
	let color: Color

	var body: some View {
		HStack(spacing: 6) {
			Circle().fill(color).frame(width: 7, height: 7)
			Text(text).font(.system(size: 12, weight: .semibold))
		}
		.foregroundStyle(color)
		.padding(.horizontal, 9)
		.padding(.vertical, 3)
		.background(Capsule().fill(color.opacity(0.13)))
	}
}
