import AVFoundation
import CoreMedia
import HlasCore

// All session lifecycle state belongs to sessionQueue; audio state to captureQueue.
final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let sessionQueue = DispatchQueue(label: "hlas.audio-session", qos: .userInitiated)
    private let captureQueue = DispatchQueue(label: "hlas.audio-capture", qos: .userInitiated)
    private var session: AVCaptureSession?
    private var captureDeviceID: String?
    private var sessionObservers: [NSObjectProtocol] = []
    private var needsReconfiguration = false
    private var lifecycleGeneration = 0
    private var lastStop: Date?
    private var activeSessionID: UUID?
    private var activeToken: CancellationToken?

    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private var isCapturing = false
    private var meteredAt = ContinuousClock.now
    private var captureToken: CancellationToken?
    private var limitReported = false
    private var captureStartedAt = ContinuousClock.now
    @MainActor var onLevel: (@MainActor (Float, Double) -> Void)?
    @MainActor var onLimit: (@MainActor () -> Void)?

    static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000, channels: 1, interleaved: false)!

    @MainActor private static func preferredDevice() -> AudioInputDevice? {
        switch Settings.shared.inputDeviceUID {
        case "": return nil
        case "builtin": return AudioDevices.builtIn()
        case let uid: return AudioDevices.device(uid: uid)
        }
    }

    @MainActor func start(id: UUID) async throws -> AudioInputDevice? {
        let preferred = Self.preferredDevice()
        let token = CancellationToken()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sessionQueue.async {
                    do {
                        try token.check()
                        self.lifecycleGeneration += 1
                        let began = ContinuousClock.now
                        let device = Self.captureDevice(matching: preferred) ?? AVCaptureDevice.default(for: .audio)
                        guard let device else { throw Self.error("No microphone input available") }
                        if self.needsReconfiguration || self.session == nil || self.captureDeviceID != device.uniqueID {
                            self.tearDownSession()
                            try self.configureSession(device: device)
                            self.needsReconfiguration = false
                        }
                        self.activeSessionID = id
                        self.activeToken = token
                        self.captureQueue.sync {
                            self.samples.removeAll(keepingCapacity: false)
                            self.samples.reserveCapacity(16_000 * 30)
                            self.converter = nil
                            self.captureToken = token
                            self.limitReported = false
                            self.isCapturing = true
                            self.captureStartedAt = .now
                        }
                        guard let session = self.session else { throw Self.error("Microphone session is unavailable") }
                        if !session.isRunning { session.startRunning() }
                        try token.check()
                        guard session.isRunning else { throw Self.error("Could not start the microphone") }
                        let actual = AudioDevices.list().first { $0.uid == device.uniqueID || $0.name == device.localizedName }
                        Log.write("capture ready: startup_ms=\(Self.elapsedMs(since: began))")
                        continuation.resume(returning: actual)
                    } catch {
                        self.captureQueue.sync {
                            self.isCapturing = false
                            self.samples.removeAll(keepingCapacity: false)
                        }
                        self.activeToken = nil
                        self.scheduleSuspend(after: 0)
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: { token.cancel() }
    }

    func stop(id: UUID) async -> [Float] {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                guard self.activeSessionID == id else { continuation.resume(returning: []); return }
                let result = self.captureQueue.sync {
                    self.isCapturing = false
                    let result = self.samples
                    self.samples = []
                    self.captureToken = nil
                    return result
                }
                self.activeToken?.cancel()
                self.activeToken = nil
                self.activeSessionID = nil
                let repeated = self.lastStop.map { Date().timeIntervalSince($0) < 60 } ?? false
                self.lastStop = Date()
                self.scheduleSuspend(after: repeated ? 30 : 8)
                continuation.resume(returning: result)
            }
        }
    }

    func cancel(id: UUID) {
        sessionQueue.async {
            guard self.activeSessionID == id else { return }
            self.activeToken?.cancel()
            self.activeToken = nil
            self.activeSessionID = nil
            self.captureQueue.sync {
                self.isCapturing = false
                self.samples = []
                self.captureToken = nil
            }
            self.scheduleSuspend(after: 0)
        }
    }

    func deviceSelectionDidChange() {
        sessionQueue.async {
            self.needsReconfiguration = true
            if self.activeToken == nil { self.tearDownSession() }
            Log.write("microphone changed: capture session invalidated")
        }
    }

    private func scheduleSuspend(after seconds: Double) {
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        sessionQueue.asyncAfter(deadline: .now() + seconds) {
            guard self.lifecycleGeneration == generation, self.activeToken == nil else { return }
            if self.session?.isRunning == true { self.session?.stopRunning() }
            Log.write("capture suspended: cooldown_s=\(seconds)")
        }
    }

    @MainActor func prewarm() {
        let preferred = Self.preferredDevice()
        sessionQueue.async {
            guard self.activeToken == nil else { return }
            guard let device = Self.captureDevice(matching: preferred) ?? AVCaptureDevice.default(for: .audio) else { return }
            do {
                if self.needsReconfiguration || self.session == nil || self.captureDeviceID != device.uniqueID {
                    self.tearDownSession()
                    try self.configureSession(device: device)
                    self.needsReconfiguration = false
                }
                let began = ContinuousClock.now
                if self.session?.isRunning == false { self.session?.startRunning() }
                Log.write("prewarm: startup_ms=\(Self.elapsedMs(since: began))")
                self.scheduleSuspend(after: 0.5)
            } catch { Log.write("prewarm failed") }
        }
    }

    func shutdown() {
        sessionQueue.async {
            self.activeToken?.cancel()
            self.activeToken = nil
            self.activeSessionID = nil
            self.captureQueue.sync { self.isCapturing = false; self.samples = []; self.converter = nil }
            self.tearDownSession()
        }
    }

    static func requestPermission() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }
    private static func elapsedMs(since start: ContinuousClock.Instant) -> Int64 {
        let d = start.duration(to: .now)
        return d.components.seconds * 1000 + Int64(d.components.attoseconds / 1_000_000_000_000_000)
    }

    private func configureSession(device: AVCaptureDevice) throws {
        let session = AVCaptureSession()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw Self.error("Could not use the selected microphone") }
        session.addInput(input)
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(output) else { throw Self.error("Could not capture microphone audio") }
        session.addOutput(output)
        self.session = session
        captureDeviceID = device.uniqueID
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.sessionQueue.async {
                    guard self.session === session else { return }
                    self.needsReconfiguration = true; Log.write("capture session interrupted")
                }
            }
            sessionObservers.append(observer)
        }
    }

    private func tearDownSession() {
        lifecycleGeneration += 1
        sessionObservers.forEach { NotificationCenter.default.removeObserver($0) }
        sessionObservers = []
        if session?.isRunning == true { session?.stopRunning() }
        session = nil
        captureDeviceID = nil
        captureQueue.sync { converter = nil }
    }

    private static func captureDevice(matching preferred: AudioInputDevice?) -> AVCaptureDevice? {
        guard let preferred else { return nil }
        return AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
            .devices.first { $0.uniqueID == preferred.uid }
    }
    private static func error(_ message: String) -> NSError {
        NSError(domain: "Hlas", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard isCapturing, captureToken?.isCancelled == false, let input = sampleBuffer.audioPCMBuffer else { return }
        if converter == nil { converter = AVAudioConverter(from: input.format, to: Self.targetFormat) }
        guard let converter, let buffer = Self.convert(input, using: converter),
              let channel = buffer.floatChannelData?[0] else { return }
        let remaining = max(0, AudioPreparation.maxSamples - samples.count)
        let count = min(Int(buffer.frameLength), remaining)
        if samples.isEmpty, count > 0 { Log.write("capture first_buffer_ms=\(Self.elapsedMs(since: captureStartedAt))") }
        let chunk = UnsafeBufferPointer(start: channel, count: count)
        samples.append(contentsOf: chunk)
        if Self.elapsedMs(since: meteredAt) >= 50 {
            meteredAt = .now
            let peak = chunk.reduce(Float(0)) { max($0, abs($1)) }
            let seconds = Double(samples.count) / 16_000
            let token = captureToken
            DispatchQueue.main.async { [weak self] in
                guard token?.isCancelled == false else { return }
                self?.onLevel?(min(1, peak * 3), seconds)
            }
        }
        if samples.count >= AudioPreparation.maxSamples, !limitReported {
            limitReported = true
            let token = captureToken
            DispatchQueue.main.async { [weak self] in
                guard token?.isCancelled == false else { return }
                self?.onLimit?()
            }
        }
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
