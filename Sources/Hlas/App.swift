import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkey = Hotkey()
    private let recorder = AudioRecorder()
    private let overlay = OverlayPanel()
    private var isRecording = false
    private var transcriber: Transcriber = EchoTranscriber()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        if OnboardingWindow.shouldShow {
            OnboardingWindow.shared.show()
        } else {
            Task { await requestPermissions() }
        }

        recorder.onLevel = { [weak self] level in
            Task { @MainActor in self?.overlay.model.push(level: level) }
        }
        hotkey.onPress = { [weak self] in self?.hotkeyPressed() }
        hotkey.onRelease = { [weak self] in self?.hotkeyReleased() }

        startHotkeyWithRetry()
        rebuildTranscriber()
    }

    /// The event tap can only be created once Accessibility is granted.
    /// If the user grants it after launch, keep retrying until it works.
    private func startHotkeyWithRetry(attempt: Int = 0) {
        if hotkey.start() {
            Log.write("event tap STARTED (attempt \(attempt), AXTrusted=\(Hotkey.hasAccessibilityPermission(prompt: false)))")
            return
        }
        Log.write("event tap FAILED (attempt \(attempt), AXTrusted=\(Hotkey.hasAccessibilityPermission(prompt: false)))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.startHotkeyWithRetry(attempt: attempt + 1)
        }
    }

    private func requestPermissions() async {
        _ = await AudioRecorder.requestPermission()
        _ = Hotkey.hasAccessibilityPermission(prompt: true)
    }

    func rebuildTranscriber() {
        transcriber.unload()
        transcriber = TranscriberFactory.make()
    }

    // MARK: dictation loop
    // Hybrid mode (VoiceInk-style): hold = push-to-talk, quick tap = latch
    // hands-free until the next tap.

    private var pressStartedAt: Date?

    private func hotkeyPressed() {
        Log.write("fn PRESS (recording=\(isRecording))")
        if isRecording {
            stopDictation() // latched session — this tap ends it
        } else {
            pressStartedAt = Date()
            startDictation()
        }
    }

    private func hotkeyReleased() {
        guard isRecording, let start = pressStartedAt else { return }
        if Date().timeIntervalSince(start) >= 0.35 {
            stopDictation()
        }
        // else: quick tap → stay latched, keep recording
    }

    private func startDictation() {
        guard !isRecording else { return }
        do {
            try recorder.start()
            isRecording = true
            overlay.show(.recording)
            setIcon(recording: true)
        } catch {
            overlay.show(.error(error.localizedDescription))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.overlay.hide() }
        }
    }

    private func stopDictation() {
        guard isRecording else { return }
        isRecording = false
        let samples = recorder.stop()
        setIcon(recording: false)
        Log.write("recording stopped: \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / 16000))s)")

        // Ignore accidental taps shorter than 0.3 s.
        guard samples.count > 4800 else {
            overlay.hide()
            return
        }
        // Silence guard: whisper hallucinates on silence ("Konec.", "Titulky…").
        var peak: Float = 0
        for s in samples { peak = max(peak, abs(s)) }
        guard peak > 0.01 else {
            Log.write("dropped: silence (peak \(peak))")
            overlay.hide()
            return
        }
        // Leading pad: whisper drops the first word when speech starts at t=0
        // (the "Ahoj"→"Hoj" bug). Trailing pad: sub-second input misbehaves.
        var padded = [Float](repeating: 0, count: 4_000) // 0.25 s lead-in
        padded.append(contentsOf: samples)
        if padded.count < 19_200 {
            padded.append(contentsOf: [Float](repeating: 0, count: 19_200 - padded.count))
        }
        overlay.show(.transcribing)

        let engine = transcriber
        let language = Settings.shared.language == "auto" ? nil : Settings.shared.language
        Task {
            do {
                let text = try await engine.transcribe(samples: padded, language: language)
                Log.write("transcribed: \"\(text.prefix(80))\"")
                await MainActor.run {
                    self.overlay.hide()
                    let trimmed = Hallucinations.filter(
                        text.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    if !trimmed.isEmpty {
                        TextInjector.insert(trimmed)
                        History.shared.add(trimmed)
                    }
                }
            } catch {
                await MainActor.run {
                    self.overlay.show(.error(error.localizedDescription))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.overlay.hide() }
                }
            }
        }
    }

    // MARK: status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIcon(recording: false)
        let menu = NSMenu()
        menu.addItem(withTitle: "Hlas — hold Fn to dictate", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Welcome Tour…", action: #selector(openOnboarding), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Hlas", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func setIcon(recording: Bool) {
        let name = recording ? "waveform.circle.fill" : "waveform"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Hlas")
        image?.isTemplate = !recording
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = recording
            ? NSColor(red: 0, green: 0.9, blue: 0.5, alpha: 1)
            : nil
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show(appDelegate: self)
    }

    @objc private func openOnboarding() {
        OnboardingWindow.shared.show()
    }
}
