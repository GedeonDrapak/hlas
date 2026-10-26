import AppKit
import AVFoundation
import Combine
import HlasCore
import SwiftUI
import UniformTypeIdentifiers

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
    private lazy var coordinator = DictationCoordinator(recorder: recorder, overlay: overlay) { [weak self] recording in
        self?.setIcon(recording: recording)
    }
    private weak var statusSummaryItem: NSMenuItem?
    private var hotkeyCancellable: AnyCancellable?
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

        _ = coordinator
        hotkey.onPress = { [weak self] in self?.coordinator.press() }
        hotkey.onRelease = { [weak self] in self?.coordinator.release() }
        hotkey.onEscape = { [weak self] in self?.coordinator.cancel() }
        hotkey.onChord = { [weak self] in self?.coordinator.cancel() }
        hotkey.trigger = Settings.shared.hotkey.trigger
        hotkeyCancellable = Settings.shared.$hotkey
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] choice in
                self?.hotkey.trigger = choice.trigger
                Log.write("hotkey set to \(choice.rawValue)")
            }

        inputDeviceCancellable = Settings.shared.$inputDeviceUID
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.recorder.deviceSelectionDidChange() }
        audioEnvironmentCancellable = AudioDeviceMonitor.shared.$revision
            .dropFirst()
            .sink { [weak self] _ in self?.recorder.deviceSelectionDidChange() }

        startHotkeyWithRetry()
        rebuildTranscriber()

        // First-dictation latency: warm the capture pipeline now and after
        // every wake, so holding Fn never races a ~1.7 s cold mic start.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            recorder.prewarm()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recorder.prewarm() }
        }
    }

    private var wakeObserver: NSObjectProtocol?

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
        if Settings.shared.engine != .local { LocalTranscriberHolder.shared.unload() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { SettingsWindow.shared.show(appDelegate: self) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { coordinator.shutdown() }

    /// LSUIElement apps have no menu bar, but Cmd-C/V/X/A key equivalents
    /// route through the main menu - without one, paste doesn't work in our
    /// own windows (the "transcribes but never lands in the Try It field" bug).
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Hlas", action: #selector(showAbout), keyEquivalent: "")
        let cancelItem = appMenu.addItem(withTitle: "Cancel dictation", action: #selector(cancelActiveDictation), keyEquivalent: "\u{1b}")
        cancelItem.keyEquivalentModifierMask = []
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Hlas", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.items.forEach { $0.target = self }
        appMenu.items.last?.target = NSApp
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let file = NSMenu(title: "File")
        let openAudio = file.addItem(withTitle: "Transcribe audio file…", action: #selector(importAudio), keyEquivalent: "o")
        openAudio.target = self
        fileItem.submenu = file

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
        for mode in OutputMode.allCases {
            let item = menu.addItem(withTitle: mode.title, action: #selector(selectOutputMode(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue
        }
        menu.addItem(withTitle: "Transcribe audio file…", action: #selector(importAudio), keyEquivalent: "")
        menu.addItem(withTitle: "Show last text…", action: #selector(showLastText), keyEquivalent: "")
        menu.addItem(withTitle: "Make last text smart…", action: #selector(makeLastSmart), keyEquivalent: "")
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

    @objc private func selectOutputMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = OutputMode(rawValue: raw) { Settings.shared.outputMode = mode }
    }
    @objc private func importAudio() {
        guard coordinator.state == .idle else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Transcribe up to 10 minutes of audio using your current engine and output mode."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.coordinator.importAudio(url)
        }
    }
    @objc private func cancelActiveDictation() { coordinator.cancel() }
    @objc private func showLastText() { coordinator.showLast() }
    @objc private func makeLastSmart() { coordinator.makeLastSmart() }

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
        for item in menu.items {
            if let mode = item.representedObject as? String {
                item.state = mode == Settings.shared.outputMode.rawValue ? .on : .off
            }
        }
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


extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(cancelActiveDictation) { return coordinator.state != .idle }
        if menuItem.action == #selector(showLastText) { return coordinator.lastResult != nil }
        if menuItem.action == #selector(makeLastSmart) { return coordinator.lastResult != nil && coordinator.state == .idle }
        if menuItem.action == #selector(importAudio) { return coordinator.state == .idle }
        return true
    }
}
