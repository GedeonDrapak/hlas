import AVFoundation

/// Captures microphone audio and delivers 16 kHz mono Float32 samples —
/// the native input format of every Whisper-family model.
/// The engine is started only while recording, so idle cost is zero.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private(set) var samples: [Float] = []
    private var warmShutdownTimer: Timer?

    /// Keep the engine running briefly after a dictation so consecutive
    /// dictations start with zero mic-spinup loss (Handy's technique).
    private let keepWarmSeconds: TimeInterval = 12

    /// 0…1 smoothed input level, for the overlay waveform.
    var onLevel: ((Float) -> Void)?

    static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    func start() throws {
        warmShutdownTimer?.invalidate()
        warmShutdownTimer = nil
        samples.removeAll(keepingCapacity: true)
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "Hlas", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No microphone input available"
            ])
        }
        let converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat)!
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let ratio = Self.targetFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else { return }
            var consumed = false
            converter.convert(to: out, error: nil) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            if out.frameLength > 0, let ch = out.floatChannelData?[0] {
                let chunk = Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
                DispatchQueue.main.async {
                    self.samples.append(contentsOf: chunk)
                }
                var peak: Float = 0
                for s in chunk { peak = max(peak, abs(s)) }
                let level = min(1, peak * 3)
                DispatchQueue.main.async { self.onLevel?(level) }
            }
        }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    /// Stops capture and returns the recorded 16 kHz mono samples.
    /// The engine keeps running for `keepWarmSeconds` so an immediate next
    /// dictation loses zero audio to mic spin-up.
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        converter = nil
        let result = samples
        samples.removeAll(keepingCapacity: false)

        warmShutdownTimer?.invalidate()
        warmShutdownTimer = Timer.scheduledTimer(withTimeInterval: keepWarmSeconds, repeats: false) { [weak self] _ in
            self?.engine.stop()
        }
        return result
    }

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
