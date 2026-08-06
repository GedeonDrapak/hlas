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
        Task { await requestPermissions() }

        recorder.onLevel = { [weak self] level in
            Task { @MainActor in self?.overlay.model.push(level: level) }
        }
        hotkey.onPress = { [weak self] in self?.hotkeyPressed() }
        hotkey.onRelease = { [weak self] in self?.hotkeyReleased() }

        if !hotkey.start() {
            NSLog("Hlas: event tap failed — accessibility permission missing?")
        }
        rebuildTranscriber()
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

        // Ignore accidental taps shorter than 0.3 s.
        guard samples.count > 4800 else {
            overlay.hide()
            return
        }
        // whisper.cpp misbehaves on sub-second input — pad with silence.
        var padded = samples
        if padded.count < 19_200 {
            padded.append(contentsOf: [Float](repeating: 0, count: 19_200 - padded.count))
        }
        overlay.show(.transcribing)

        let engine = transcriber
        let language = Settings.shared.language == "auto" ? nil : Settings.shared.language
        Task {
            do {
                let text = try await engine.transcribe(samples: padded, language: language)
                await MainActor.run {
                    self.overlay.hide()
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
