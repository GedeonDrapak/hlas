import AppKit
import HlasCore

@MainActor final class DictationCoordinator {
    enum State { case idle, starting, recording, transcribing, formatting }
    private(set) var state: State = .idle
    private let recorder: AudioRecorder
    private let overlay: OverlayPanel
    private let onRecording: (Bool) -> Void
    private var task: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var sessionID = UUID()
    private var pressedAt: Date?
    private var stopWhenReady = false
    private var localPrefetched = false
    private var snapshot: Snapshot?
    private(set) var lastResult: (text: String, raw: String)?

    private struct Snapshot {
        let id: UUID
        let transcriber: Transcriber
        let engine: String
        let language: String?
        let prompt: String?
        let keepAlive: Double
        let mode: OutputMode
        let processor: SmartTextProcessor?
        let replacements: [TextReplacement]
        let target: TextInjector.Target?
        let saveHistory: Bool
        let isImport: Bool
    }

    init(recorder: AudioRecorder, overlay: OverlayPanel, onRecording: @escaping (Bool) -> Void) {
        self.recorder = recorder; self.overlay = overlay; self.onRecording = onRecording
        recorder.onLevel = { [weak self] level, seconds in
            guard let self, self.state == .recording else { return }
            if level > 0.03, !self.localPrefetched, self.snapshot?.engine == "local" {
                self.localPrefetched = true
                LocalTranscriberHolder.shared.prepare(keepAlive: 600)
            }
            self.overlay.model.push(level: level)
            self.overlay.model.elapsed = seconds
        }
        recorder.onLimit = { [weak self] in self?.stop() }
    }

    func press() {
        if state == .recording || state == .starting { pressedAt = nil; stop(); return }
        pressedAt = Date()
        start()
    }
    func release() {
        guard let pressedAt, Date().timeIntervalSince(pressedAt) >= 0.35 else { return }
        self.pressedAt = nil
        stop()
    }

    private func start() {
        task?.cancel()
        hideTask?.cancel()
        let settings = Settings.shared
        sessionID = UUID()
        // With Right Option as the hotkey, only Left Option (NX_DEVICELALTKEYMASK) means "Transcript once".
        let optionHeld = settings.hotkey == .rightOption
            ? CGEventSource.flagsState(.combinedSessionState).rawValue & 0x20 != 0
            : NSEvent.modifierFlags.contains(.option)
        let mode: OutputMode = optionHeld ? .transcript : settings.outputMode
        let snap = Snapshot(id: sessionID, transcriber: TranscriberFactory.make(), engine: settings.engine.rawValue,
            language: settings.language == "auto" ? nil : settings.language, prompt: settings.vocabularyPrompt,
            keepAlive: settings.modelKeepAliveSeconds, mode: mode, processor: SmartTextProcessor.configured(),
            replacements: settings.replacements, target: TextInjector.Target.capture(), saveHistory: settings.historyEnabled, isImport: false)
        snapshot = snap
        localPrefetched = false
        stopWhenReady = false
        state = .starting
        overlay.model.elapsed = 0
        overlay.model.mode = mode.title
        overlay.model.sourceIcon = nil; overlay.model.sourceName = nil
        overlay.show(.starting)
        onRecording(true)
        Log.write("session=\(snap.id) engine=\(snap.engine) mode=\(mode.rawValue) phase=starting")
        task = Task {
            do {
                let device = try await recorder.start(id: snap.id)
                guard sessionID == snap.id, !Task.isCancelled else { return }
                if let device, !device.isBuiltIn {
                    overlay.model.sourceIcon = device.icon; overlay.model.sourceName = device.name
                }
                state = .recording
                overlay.show(.recording)
                if stopWhenReady { stop() }
            } catch {
                guard sessionID == snap.id, !Task.isCancelled else { return }
                finish(.error(error.localizedDescription), after: 3)
            }
        }
    }

    private func stop() {
        if state == .starting { stopWhenReady = true; return }
        guard state == .recording, let snap = snapshot else { return }
        state = .transcribing
        onRecording(false)
        overlay.show(.transcribing)
        task = Task {
            let samples = await recorder.stop(id: snap.id)
            guard sessionID == snap.id, !Task.isCancelled else { return }
            await process(samples: samples, snap: snap)
        }
    }

    private func process(samples: [Float], snap: Snapshot) async {
            let duration = Double(samples.count) / 16_000
            let stoppedAt = ContinuousClock.now
            Log.write("session=\(snap.id) phase=stopped audio_s=\(duration)")
            do {
                let prepared = await Task.detached(priority: .userInitiated) { AudioPreparation.padded(samples) }.value
                try Task.checkCancellation()
                guard let prepared else { finish(.hidden); return }
                let raw = try await snap.transcriber.transcribe(samples: prepared, language: snap.language,
                    prompt: snap.prompt, keepAlive: snap.keepAlive).trimmingCharacters(in: .whitespacesAndNewlines)
                try Task.checkCancellation()
                guard sessionID == snap.id else { return }
                Log.write("session=\(snap.id) phase=stt_done elapsed=\(stoppedAt.duration(to: .now)) chars=\(raw.count)")
                guard !raw.isEmpty else { finish(.hidden); return }
                lastResult = (raw, raw)
                guard !Hallucinations.filter(raw).isEmpty else {
                    if snap.saveHistory { History.shared.add(raw, raw: raw, mode: .transcript, engine: snap.engine, duration: duration) }
                    finish(.hidden)
                    ResultWindow.shared.show(text: raw, original: raw, message: "This may be background audio. Review before copying.")
                    return
                }
                var text = TextReplacement.apply(snap.replacements, to: raw)
                var recoveryMessage: String?
                if snap.mode == .smart {
                    state = .formatting
                    overlay.show(.formatting)
                    do {
                        guard let processor = snap.processor else { throw SmartTextError.missingKey }
                        let began = ContinuousClock.now
                        text = TextReplacement.apply(snap.replacements, to: try await processor.process(text))
                        Log.write("session=\(snap.id) phase=smart_done provider=\(processor.provider) elapsed=\(began.duration(to: .now))")
                    } catch {
                        if Task.isCancelled || error is CancellationError { return }
                        recoveryMessage = error.localizedDescription
                    }
                }
                try Task.checkCancellation()
                guard sessionID == snap.id else { return }
                lastResult = (text, raw)
                if snap.saveHistory {
                    History.shared.add(text, raw: raw, mode: recoveryMessage == nil ? snap.mode : .transcript,
                                       engine: snap.engine, duration: duration)
                }
                finish(.hidden)
                if let recoveryMessage {
                    ResultWindow.shared.show(text: text, original: raw, message: recoveryMessage)
                } else if let target = snap.target, TextInjector.insert(text, target: target) {
                    Log.write("session=\(snap.id) phase=paste_posted elapsed=\(stoppedAt.duration(to: .now))")
                } else {
                    ResultWindow.shared.show(text: text, original: raw,
                        message: snap.isImport ? "Audio file transcribed. Copy your text below."
                            : "You switched applications. Your text is ready to copy.")
                    Log.write("session=\(snap.id) phase=delivery_review")
                }
            } catch {
                guard sessionID == snap.id, !Task.isCancelled else { return }
                Log.write("session=\(snap.id) phase=failed")
                finish(.error(error.localizedDescription), after: 4)
            }
    }

    func importAudio(_ url: URL) {
        guard state == .idle else { return }
        hideTask?.cancel()
        let settings = Settings.shared
        sessionID = UUID()
        let snap = Snapshot(id: sessionID, transcriber: TranscriberFactory.make(), engine: settings.engine.rawValue,
            language: settings.language == "auto" ? nil : settings.language, prompt: settings.vocabularyPrompt,
            keepAlive: settings.modelKeepAliveSeconds, mode: settings.outputMode, processor: SmartTextProcessor.configured(),
            replacements: settings.replacements, target: nil, saveHistory: settings.historyEnabled, isImport: true)
        snapshot = snap
        state = .transcribing
        overlay.show(.transcribing)
        task = Task {
            do {
                let token = CancellationToken()
                let samples = try await withTaskCancellationHandler {
                    try await Task.detached(priority: .userInitiated) { try AudioFileImporter.read(url, token: token) }.value
                } onCancel: { token.cancel() }
                try Task.checkCancellation()
                guard sessionID == snap.id else { return }
                await process(samples: samples, snap: snap)
            } catch {
                guard sessionID == snap.id, !Task.isCancelled else { return }
                finish(.error(error.localizedDescription), after: 4)
            }
        }
    }

    func cancel() {
        guard state != .idle else { return }
        task?.cancel(); task = nil
        let cancelledID = sessionID
        sessionID = UUID()
        pressedAt = nil
        recorder.cancel(id: cancelledID)
        Log.write("dictation cancelled")
        finish(.cancelled, after: 0.8)
    }

    private func finish(_ state: OverlayState, after seconds: Double = 0) {
        self.state = .idle
        if let snapshot, snapshot.engine == "local" { LocalTranscriberHolder.shared.releaseAfter(snapshot.keepAlive) }
        snapshot = nil
        onRecording(false)
        hideTask?.cancel()
        if state == .hidden { overlay.hide(); return }
        overlay.show(state)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, self?.state == .idle else { return }
            self?.overlay.hide()
        }
    }
    func showLast() {
        guard let lastResult else { return }
        ResultWindow.shared.show(text: lastResult.text, original: lastResult.raw, message: "Your last dictation")
    }
    func makeLastSmart() {
        guard state == .idle, let lastResult else { return }
        guard let processor = SmartTextProcessor.configured() else {
            ResultWindow.shared.show(text: lastResult.raw, original: lastResult.raw, message: SmartTextError.missingKey.localizedDescription)
            return
        }
        hideTask?.cancel()
        let id = UUID(); sessionID = id
        state = .formatting
        overlay.show(.formatting)
        task = Task {
            do {
                let text = try await processor.process(lastResult.raw)
                guard sessionID == id, !Task.isCancelled else { return }
                self.lastResult = (text, lastResult.raw)
                History.shared.add(text, raw: lastResult.raw, mode: .smart)
                finish(.hidden)
                ResultWindow.shared.show(text: text, original: lastResult.raw, message: "Smart text is ready")
            } catch {
                guard sessionID == id, !Task.isCancelled else { return }
                finish(.hidden)
                ResultWindow.shared.show(text: lastResult.raw, original: lastResult.raw, message: error.localizedDescription)
            }
        }
    }
    func shutdown() { task?.cancel(); hideTask?.cancel(); recorder.shutdown(); LocalTranscriberHolder.shared.unload() }
}
