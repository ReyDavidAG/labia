import AVFoundation

enum RecorderError: LocalizedError {
	case noInput

	var errorDescription: String? { "No hay micrófono disponible" }
}

final class Recorder {
	static let sampleRate = 16_000.0

	var onLevel: ((Float) -> Void)?

	private var engine: AVAudioEngine?
	private var converter: AVAudioConverter?
	private let lock = NSLock()
	private var samples: [Float] = []
	private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Recorder.sampleRate, channels: 1, interleaved: false)!

	func start() throws {
		lock.withLock { samples.removeAll(keepingCapacity: true) }
		let engine = AVAudioEngine()
		let input = engine.inputNode
		let inputFormat = input.outputFormat(forBus: 0)
		guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0, let converter = AVAudioConverter(from: inputFormat, to: format) else {
			throw RecorderError.noInput
		}
		self.converter = converter
		input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
			self?.consume(buffer)
		}
		engine.prepare()
		try engine.start()
		self.engine = engine
	}

	func stop() -> [Float] {
		guard let engine else { return [] }
		engine.inputNode.removeTap(onBus: 0)
		engine.stop()
		self.engine = nil
		return lock.withLock { samples }
	}

	/// Lo grabado desde `index`, sin detener la grabación.
	func samples(from index: Int) -> [Float] {
		lock.withLock { index < samples.count ? Array(samples[index...]) : [] }
	}

	private func consume(_ input: AVAudioPCMBuffer) {
		guard let converter else { return }
		let capacity = AVAudioFrameCount(Double(input.frameLength) * format.sampleRate / input.format.sampleRate) + 64
		guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
		var consumed = false
		var error: NSError?
		converter.convert(to: output, error: &error) { _, status in
			if consumed {
				status.pointee = .noDataNow
				return nil
			}
			consumed = true
			status.pointee = .haveData
			return input
		}
		guard error == nil, let channel = output.floatChannelData?[0] else { return }
		let chunk = UnsafeBufferPointer(start: channel, count: Int(output.frameLength))
		lock.withLock { samples.append(contentsOf: chunk) }
		onLevel?(Self.level(Self.rms(chunk)))
	}

	static func rms<C: Collection>(_ values: C) -> Float where C.Element == Float {
		guard !values.isEmpty else { return 0 }
		return (values.reduce(0) { $0 + $1 * $1 } / Float(values.count)).squareRoot()
	}

	static func level(_ rms: Float) -> Float {
		guard rms > 0 else { return 0 }
		return min(1, max(0, (20 * log10(rms) + 52) / 38))
	}
}
