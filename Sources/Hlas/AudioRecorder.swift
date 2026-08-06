import AVFoundation
import CoreMedia

/// Captures microphone audio and delivers 16 kHz mono Float32 samples,
/// the native input format of every Whisper-family model.
final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let captureQueue = DispatchQueue(label: "hlas.audio-capture", qos: .userInitiated)
    private var session: AVCaptureSession?
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private var isCapturing = false
    private var captureDeviceID: String?
    private var warmShutdownTimer: Timer?
    private var needsReconfiguration = false
    private var sessionObservers: [NSObjectProtocol] = []

    /// Keep the microphone session warm briefly so consecutive dictations
    /// do not pay device startup latency again.
    private let keepWarmSeconds: TimeInterval = 45

    /// 0...1 smoothed input level, for the overlay waveform.
    var onLevel: ((Float) -> Void)?

    static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    /// The device audio was actually captured from in the current session.
    private(set) var activeDevice: AudioInputDevice?

    @MainActor
    private static func preferredDevice() -> AudioInputDevice? {
        switch Settings.shared.inputDeviceUID {
        case "": return nil
        case "builtin": return AudioDevices.builtIn()
        case let uid: return AudioDevices.device(uid: uid)
        }
    }

    @MainActor
    func start() throws {
        let startupBegan = ContinuousClock.now
        warmShutdownTimer?.invalidate()
        warmShutdownTimer = nil

        let preferred = Self.preferredDevice()
        let captureDevice = Self.captureDevice(matching: preferred)
            ?? AVCaptureDevice.default(for: .audio)
        guard let captureDevice else {
            throw Self.error("No microphone input available")
        }

        var configureMs: Int64 = 0
        if needsReconfiguration || session == nil || captureDeviceID != captureDevice.uniqueID {
            let configureBegan = ContinuousClock.now
            tearDownSession()
            try configureSession(device: captureDevice)
            needsReconfiguration = false
            configureMs = Self.elapsedMs(since: configureBegan)
        }

        captureQueue.sync {
            samples.removeAll(keepingCapacity: true)
            converter = nil
            isCapturing = true
        }

        guard let session else {
            throw Self.error("Microphone session is unavailable")
        }
        let runBegan = ContinuousClock.now
        if !session.isRunning {
            session.startRunning()
        }
        let runMs = Self.elapsedMs(since: runBegan)
        if configureMs + runMs > 100 {
            Log.write("capture startup breakdown: configure \(configureMs) ms, startRunning \(runMs) ms")
        }
        guard session.isRunning else {
            captureQueue.sync { isCapturing = false }
            throw Self.error("Could not start the microphone")
        }

        captureDeviceID = captureDevice.uniqueID
        activeDevice = AudioDevices.list().first {
            $0.uid == captureDevice.uniqueID || $0.name == captureDevice.localizedName
        } ?? AudioDevices.defaultInputID().flatMap { AudioDevices.device(id: $0) }
        let startup = startupBegan.duration(to: .now)
        let milliseconds = startup.components.seconds * 1_000
            + Int64(startup.components.attoseconds / 1_000_000_000_000_000)
        Log.write("recording source: \(captureDevice.localizedName), startup \(milliseconds) ms")
    }

    /// Drop a warm session after the selected or system input changes.
    /// If capture is active, finish it and rebuild before the next dictation.
    @MainActor
    func deviceSelectionDidChange() {
        warmShutdownTimer?.invalidate()
        warmShutdownTimer = nil
        needsReconfiguration = true
        let capturing = captureQueue.sync { isCapturing }
        if !capturing {
            tearDownSession()
        }
        Log.write("microphone changed: capture session invalidated")
    }

    func stop() -> [Float] {
        let result = captureQueue.sync {
            isCapturing = false
            let result = samples
            samples.removeAll(keepingCapacity: false)
            return result
        }

        warmShutdownTimer?.invalidate()
        warmShutdownTimer = Timer.scheduledTimer(withTimeInterval: keepWarmSeconds, repeats: false) { [weak self] _ in
            self?.suspendSession()
        }
        return result
    }

    /// Cooldown: release the microphone (indicator turns off) but KEEP the
    /// configured session, so the next start pays only startRunning — not the
    /// full ~1.7 s configure+open that caused lost speech on cold dictations.
    private func suspendSession() {
        guard let session, session.isRunning else { return }
        DispatchQueue.global(qos: .utility).async {
            session.stopRunning()
            Log.write("capture session suspended (kept configured)")
        }
    }

    /// Warm the capture pipeline before the first dictation: configure and
    /// briefly run the session, then release the mic. Called at app launch
    /// and on wake from sleep.
    @MainActor
    func prewarm() {
        let capturing = captureQueue.sync { isCapturing }
        guard !capturing else { return }
        let preferred = Self.preferredDevice()
        guard let device = Self.captureDevice(matching: preferred)
            ?? AVCaptureDevice.default(for: .audio) else { return }

        if needsReconfiguration || session == nil || captureDeviceID != device.uniqueID {
            tearDownSession()
            guard (try? configureSession(device: device)) != nil else { return }
            needsReconfiguration = false
            captureDeviceID = device.uniqueID
        }
        guard let session, !session.isRunning else { return }

        let began = ContinuousClock.now
        DispatchQueue.global(qos: .utility).async { [weak self] in
            session.startRunning()
            Log.write("prewarm: startRunning \(Self.elapsedMs(since: began)) ms")
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                guard let self else { return }
                // Leave it running if a real dictation began meanwhile.
                let capturing = self.captureQueue.sync { self.isCapturing }
                if !capturing {
                    self.suspendSession()
                }
            }
        }
    }

    private static func elapsedMs(since start: ContinuousClock.Instant) -> Int64 {
        let d = start.duration(to: .now)
        return d.components.seconds * 1_000 + Int64(d.components.attoseconds / 1_000_000_000_000_000)
    }

    func shutdown() {
        warmShutdownTimer?.invalidate()
        warmShutdownTimer = nil
        captureQueue.sync {
            isCapturing = false
            samples.removeAll(keepingCapacity: false)
            converter = nil
        }
        tearDownSession()
    }

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    private func configureSession(device: AVCaptureDevice) throws {
        let session = AVCaptureSession()
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw Self.error("Could not use the selected microphone")
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(output) else {
            throw Self.error("Could not capture microphone audio")
        }
        session.addOutput(output)
        self.session = session
        observeSession(session)
    }

    private func tearDownSession() {
        for observer in sessionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        sessionObservers.removeAll()
        if session?.isRunning == true {
            session?.stopRunning()
        }
        session = nil
        captureDeviceID = nil
        captureQueue.sync { converter = nil }
    }

    private func observeSession(_ session: AVCaptureSession) {
        let center = NotificationCenter.default
        let runtime = center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
                ?? "unknown error"
            Log.write("capture session error: \(message)")
            self?.needsReconfiguration = true
        }
        let interrupted = center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Log.write("capture session interrupted")
            self?.needsReconfiguration = true
        }
        sessionObservers = [runtime, interrupted]
    }

    private static func captureDevice(matching preferred: AudioInputDevice?) -> AVCaptureDevice? {
        guard let preferred else { return nil }
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone], mediaType: .audio, position: .unspecified
        ).devices
        return devices.first {
            $0.uniqueID == preferred.uid || $0.localizedName == preferred.name
        }
    }

    private static func error(_ description: String) -> NSError {
        NSError(domain: "Hlas", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isCapturing,
              let inputBuffer = sampleBuffer.audioPCMBuffer else { return }

        if converter == nil {
            converter = AVAudioConverter(from: inputBuffer.format, to: Self.targetFormat)
        }
        guard let converter,
              let outputBuffer = Self.convert(inputBuffer, using: converter),
              outputBuffer.frameLength > 0,
              let channel = outputBuffer.floatChannelData?[0] else { return }

        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength)))
        samples.append(contentsOf: chunk)

        var peak: Float = 0
        for sample in chunk { peak = max(peak, abs(sample)) }
        let level = min(1, peak * 3)
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }

    private static func convert(
        _ input: AVAudioPCMBuffer,
        using converter: AVAudioConverter
    ) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        guard conversionError == nil else { return nil }
        return output
    }
}

private extension CMSampleBuffer {
    var audioPCMBuffer: AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(self),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: streamDescription) else { return nil }

        let frameCount = CMSampleBufferGetNumSamples(self)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }
}
