import SwiftUI

struct PillView: View {
	let model: AppModel
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		ZStack(alignment: .bottom) {
			if model.pillVisible, let pill = model.pill {
				PillBody(pill: pill, model: model)
					.transition(reduceMotion ? .opacity : .asymmetric(
						insertion: .scale(scale: 0.92, anchor: .bottom).combined(with: .offset(y: 14)).combined(with: .opacity),
						removal: .offset(y: 10).combined(with: .opacity)
					))
			}
		}
		.frame(width: Overlay.size.width, height: Overlay.size.height, alignment: .bottom)
		.padding(.bottom, 12)
		.environment(\.colorScheme, .dark)
	}
}

struct PillBody: View {
	let pill: Pill
	let model: AppModel
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		HStack(spacing: 10) { content }
			.font(.system(size: 13, weight: .medium))
			.foregroundStyle(.white)
			.padding(.horizontal, 16)
			.frame(height: 44)
			.background {
				Capsule().fill(Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.92))
					.shadow(color: .black.opacity(0.35), radius: 14, y: 8)
				Capsule().strokeBorder(.white.opacity(0.08))
			}
			.keyframeAnimator(initialValue: 0.0, trigger: pill) { view, x in
				view.offset(x: x)
			} keyframes: { _ in
				KeyframeTrack {
					if pill.isWarning && !reduceMotion {
						LinearKeyframe(-4, duration: 0.08)
						LinearKeyframe(4, duration: 0.08)
						LinearKeyframe(-2, duration: 0.08)
						LinearKeyframe(0, duration: 0.08)
					} else {
						LinearKeyframe(0, duration: 0.01)
					}
				}
			}
			.animation(.smooth(duration: 0.24), value: pill)
			.accessibilityElement(children: .combine)
	}

	@ViewBuilder private var content: some View {
		switch pill {
		case .listening:
			RecordingDot()
			Waveform(levels: model.levels, bars: AppModel.waveformBars)
			ElapsedTime(start: model.recordingStart)
		case .locked:
			Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold))
			Waveform(levels: model.levels, bars: 18)
			ElapsedTime(start: model.recordingStart)
			Text("toca \(model.settings.hotkey.symbol)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
		case .transcribing:
			ProgressView().controlSize(.small).tint(.white)
			ShimmerText(text: "Transcribiendo…")
		case let .done(words, pasted):
			Checkmark()
			Text(pasted ? "Pegado" : "Copiado")
			Text("· \(words) \(words == 1 ? "palabra" : "palabras")").foregroundStyle(.white.opacity(0.6))
		case let .unpasted(miss):
			Warning(text: miss == .moved ? "Cambiaste de lugar · quedó copiado, ⌘V" : "No se pudo pegar · quedó copiado, ⌘V")
		case .short:
			Label("Muy corto", systemImage: "xmark").foregroundStyle(.white.opacity(0.75))
		case .cancelled:
			Label("Cancelado", systemImage: "xmark").foregroundStyle(.white.opacity(0.75))
		case .silent:
			Label("No te oí", systemImage: "mic.slash").foregroundStyle(.white.opacity(0.75))
		case .permission:
			Warning(text: "Falta permiso de Accesibilidad")
		case .noModel:
			Label("Falta descargar el modelo", systemImage: "arrow.down.circle")
		case let .failed(message):
			Warning(text: message)
		case let .updated(version):
			Label("Labia se actualizó a \(version)", systemImage: "arrow.down.circle.fill")
		}
	}
}

private struct RecordingDot: View {
	@State private var pulse = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		Circle()
			.fill(Color(red: 0.9, green: 0.28, blue: 0.3))
			.frame(width: 10, height: 10)
			.background {
				Circle()
					.stroke(Color(red: 0.9, green: 0.28, blue: 0.3).opacity(0.6), lineWidth: 2)
					.scaleEffect(pulse ? 2.1 : 1)
					.opacity(pulse ? 0 : 1)
			}
			.onAppear {
				guard !reduceMotion else { return }
				withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
			}
			.accessibilityLabel("Grabando")
	}
}

private struct Waveform: View {
	let levels: [Float]
	let bars: Int

	var body: some View {
		HStack(spacing: 2) {
			ForEach(0..<bars, id: \.self) { i in
				let value = CGFloat(levels[levels.count - bars + i])
				Capsule()
					.fill(.white.opacity(0.55 + value * 0.45))
					.frame(width: 3, height: max(3, value * 24))
			}
		}
		.frame(height: 24)
		.animation(.linear(duration: 0.07), value: levels)
		.accessibilityHidden(true)
	}
}

private struct ElapsedTime: View {
	let start: Date?

	var body: some View {
		TimelineView(.periodic(from: .now, by: 0.25)) { context in
			let seconds = Int(context.date.timeIntervalSince(start ?? context.date))
			Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
				.font(.system(size: 12, weight: .medium, design: .monospaced))
				.monospacedDigit()
				.foregroundStyle(.white.opacity(0.6))
		}
	}
}

private struct ShimmerText: View {
	let text: String
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		TimelineView(.animation(paused: reduceMotion)) { context in
			let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1
			Text(text)
				.foregroundStyle(.white.opacity(0.55))
				.overlay {
					LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
						.frame(width: 60)
						.offset(x: CGFloat(phase) * 220 - 110)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.mask(Text(text))
						.opacity(reduceMotion ? 0 : 1)
				}
		}
	}
}

private struct Checkmark: View {
	@State private var drawn = false

	var body: some View {
		Path { p in
			p.move(to: CGPoint(x: 3, y: 9.5))
			p.addLine(to: CGPoint(x: 7, y: 13.5))
			p.addLine(to: CGPoint(x: 15, y: 4.5))
		}
		.trim(from: 0, to: drawn ? 1 : 0)
		.stroke(Color(red: 0.3, green: 0.76, blue: 0.54), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
		.frame(width: 18, height: 18)
		.onAppear { withAnimation(.easeOut(duration: 0.32).delay(0.05)) { drawn = true } }
	}
}

private struct Warning: View {
	let text: String

	var body: some View {
		Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(red: 0.94, green: 0.72, blue: 0.28))
		Text(text)
	}
}
