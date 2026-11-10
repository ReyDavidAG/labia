import AVFoundation

enum RecorderError: LocalizedError {
	case noInput

	var errorDescription: String? { "No hay micrófono disponible" }
}

final class Recorder {
	static let sampleRate = 16_000.0

	private var engine: AVAudioEngine?
	private var converter: AVAudioConverter?
	private let lock = NSLock()
	private var samples: [Float] = []
	private var peak: Float = 0
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
		let level = Self.level(Self.rms(chunk))
		lock.withLock {
			samples.append(contentsOf: chunk)
			peak = max(peak, level)
		}
	}

	/// El nivel más alto desde la última vez que se pidió: la onda lo lee a su ritmo, sin una tarea por bloque de audio.
	func takeLevel() -> Float {
		lock.withLock {
			defer { peak = 0 }
			return peak
		}
	}

	/// WAV de 16 kHz para revisar un dictado con `Labia --simulate` o `--transcribe`.
	static func write(_ samples: [Float], to url: URL) throws {
		let settings: [String: Any] = [
			AVFormatIDKey: kAudioFormatLinearPCM,
			AVSampleRateKey: sampleRate,
			AVNumberOfChannelsKey: 1,
			AVLinearPCMBitDepthKey: 16,
			AVLinearPCMIsFloatKey: false,
		]
		let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
		guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)),
			let channel = buffer.floatChannelData?[0]
		else { return }
		buffer.frameLength = AVAudioFrameCount(samples.count)
		samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
		try file.write(from: buffer)
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
