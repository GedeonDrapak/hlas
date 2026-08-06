import AppKit
import AVFoundation
import Combine
import HlasCore
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
    private var activeSessionID = UUID()
    private var transcriptionTask: Task<Void, Never>?
    private weak var statusSummaryItem: NSMenuItem?
    private var inputDeviceCancellable: AnyCancellable?
    private var audioEnvironmentCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistrar.register()
        setupMainMenu()
        setupStatusItem()
        _ = History.shared
        if OnboardingWindow.shouldShow || ProcessInfo.processInfo.environment["HLAS_STEP"] != nil {
            OnboardingWindow.shared.show()
        } else {
            Task { await requestPermissions() }
        }

        recorder.onLevel = { [weak self] level in
            Task { @MainActor in self?.overlay.model.push(level: level) }
        }
        hotkey.onPress = { [weak self] in self?.hotkeyPressed() }
        hotkey.onRelease = { [weak self] in self?.hotkeyReleased() }
        hotkey.onEscape = { [weak self] in self?.cancelDictation() }

        inputDeviceCancellable = Settings.shared.$inputDeviceUID
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.recorder.deviceSelectionDidChange() }
        audioEnvironmentCancellable = AudioDeviceMonitor.shared.$revision
            .dropFirst()
            .sink { [weak self] _ in self?.recorder.deviceSelectionDidChange() }

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
            stopDictation() // latched session - this tap ends it
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
        activeSessionID = UUID()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        do {
            try recorder.start()
            isRecording = true
            // Source badge in the pill when not the built-in mic
            if let device = recorder.activeDevice, !device.isBuiltIn {
                overlay.model.sourceIcon = device.icon
                overlay.model.sourceName = device.name
            } else {
                overlay.model.sourceIcon = nil
                overlay.model.sourceName = nil
            }
            overlay.show(.recording)
            setIcon(recording: true)
        } catch {
            Log.write("recording failed: \(error.localizedDescription)")
            overlay.show(.error(error.localizedDescription))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.overlay.hide() }
        }
    }

    private func stopDictation() {
        guard isRecording else { return }
        let sessionID = activeSessionID
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

        let engine = TranscriberFactory.make()
        let language = Settings.shared.language == "auto" ? nil : Settings.shared.language
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await engine.transcribe(samples: padded, language: language)
                guard !Task.isCancelled else { return }
                Log.write("transcription completed: \(text.count) characters")
                await MainActor.run {
                    guard self.activeSessionID == sessionID else { return }
                    self.overlay.hide()
                    let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmed = Hallucinations.filter(raw)
                    if !trimmed.isEmpty {
                        TextInjector.insert(trimmed)
                        History.shared.add(trimmed)
                        Log.write("text injection posted")
                    } else if !raw.isEmpty {
                        Log.write("dropped hallucination output")
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.activeSessionID == sessionID else { return }
                    self.overlay.show(.error(error.localizedDescription))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.overlay.hide() }
                }
            }
        }
    }

    private func cancelDictation() {
        guard isRecording else { return }
        isRecording = false
        pressStartedAt = nil
        activeSessionID = UUID()
        _ = recorder.stop()
        setIcon(recording: false)
        Log.write("recording cancelled")
        overlay.show(.cancelled)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard self?.isRecording == false else { return }
            self?.overlay.hide()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { SettingsWindow.shared.show(appDelegate: self) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        transcriptionTask?.cancel()
        if isRecording { _ = recorder.stop() }
        recorder.shutdown()
        transcriber.unload()
    }

    /// LSUIElement apps have no menu bar, but Cmd-C/V/X/A key equivalents
    /// route through the main menu - without one, paste doesn't work in our
    /// own windows (the "transcribes but never lands in the Try It field" bug).
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Hlas", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Hlas", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.items.forEach { $0.target = self }
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIcon(recording: false)
        let menu = NSMenu()
        let summary = menu.addItem(withTitle: "Hlas", action: nil, keyEquivalent: "")
        statusSummaryItem = summary
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "History…", action: #selector(openHistory), keyEquivalent: "")
        menu.addItem(withTitle: "Welcome Tour…", action: #selector(openOnboarding), keyEquivalent: "")
        menu.addItem(withTitle: "Privacy", action: #selector(openPrivacy), keyEquivalent: "")
        menu.addItem(withTitle: "Third-party notices", action: #selector(openThirdPartyNotices), keyEquivalent: "")
        menu.addItem(withTitle: "Export Diagnostics…", action: #selector(exportDiagnostics), keyEquivalent: "")
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Hlas", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        // terminate(_:) lives on NSApplication, not the delegate — with
        // target = self the item fails validation and shows up disabled.
        quit.target = NSApp
        menu.delegate = self
        statusItem.menu = menu
    }

    private func setIcon(recording: Bool) {
        statusItem.button?.image = HlasMarkImage.menuBar
        statusItem.button?.contentTintColor = recording
            ? NSColor(red: 0, green: 0.9, blue: 0.5, alpha: 1)
            : nil
        statusItem.button?.toolTip = recording ? "Hlas is recording" : "Hlas is ready"
        statusItem.button?.setAccessibilityLabel("Hlas")
        statusItem.button?.setAccessibilityValue(recording ? "Recording" : "Ready")
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show(appDelegate: self)
    }

    @objc private func openOnboarding() {
        OnboardingWindow.shared.show()
    }

    @objc private func openHistory() {
        HistoryWindow.shared.show()
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Hlas",
            .applicationVersion: version,
            .credits: NSAttributedString(string: "Private dictation for Apple Silicon Macs.")
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openPrivacy() {
        LegalDocuments.open("Privacy")
    }

    @objc private func openThirdPartyNotices() {
        LegalDocuments.open("ThirdPartyNotices")
    }

    @objc private func exportDiagnostics() {
        DiagnosticsExporter.present()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let accessibility = Hotkey.hasAccessibilityPermission(prompt: false)
        if !mic || !accessibility {
            statusSummaryItem?.title = "Hlas · Permission needed"
            return
        }
        let engine = Settings.shared.engine.displayName
        let language = Languages.name(for: Settings.shared.language)
        statusSummaryItem?.title = "Hlas · \(engine) · \(language)"
    }
}
