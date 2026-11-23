import AppKit
import SwiftUI
import AVFoundation
import ServiceManagement
import HlasCore

/// First-run onboarding: split layout - Unsplash gradient + brand + step list
/// on the left, setup content on the right. Frosted-glass window.
@MainActor
final class OnboardingWindow {
    static let shared = OnboardingWindow()
    private var window: NSWindow?

    static var shouldShow: Bool {
        let done = UserDefaults.standard.bool(forKey: "hasOnboarded")
        return !done
            || !Hotkey.hasAccessibilityPermission(prompt: false)
            || AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView(close: { [weak self] in
                UserDefaults.standard.set(true, forKey: "hasOnboarded")
                self?.window?.orderOut(nil)
            }))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Live permission state

@MainActor
final class PermissionModel: ObservableObject {
    @Published var mic = false
    @Published var accessibility = false
    /// Grant was clicked a while ago and macOS still says no. Usually a stale
    /// TCC entry from an older build: the switch shows on, the csreq no longer matches.
    @Published var accessibilityStuck = false
    private var accessibilityRequestedAt: Date?
    private var timer: Timer?

    var allGranted: Bool { mic && accessibility }

    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibility = Hotkey.hasAccessibilityPermission(prompt: false)
        if accessibility {
            accessibilityRequestedAt = nil
            accessibilityStuck = false
        } else if let requested = accessibilityRequestedAt, Date().timeIntervalSince(requested) > 8 {
            accessibilityStuck = true
        }
    }

    func requestMic() {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run { self.refresh() }
        }
    }

    func requestAccessibility() {
        if accessibilityRequestedAt == nil { accessibilityRequestedAt = Date() }
        _ = Hotkey.hasAccessibilityPermission(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Toggling a stale entry does nothing; removing it and granting fresh does.
    func resetAccessibility() {
        let tccutil = Process()
        tccutil.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        tccutil.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.gedeon.hlas"]
        do {
            try tccutil.run()
            tccutil.waitUntilExit()
            Log.write("tccutil reset Accessibility exit=\(tccutil.terminationStatus)")
        } catch {
            Log.write("tccutil reset Accessibility failed: \(error.localizedDescription)")
        }
        accessibilityStuck = false
        accessibilityRequestedAt = Date()
        requestAccessibility()
    }
}

// MARK: - View

struct OnboardingView: View {
    var close: () -> Void

    // HLAS_STEP env var jumps straight to a step - used for visual QA.
    @State private var step = ProcessInfo.processInfo.environment["HLAS_STEP"].flatMap(Int.init) ?? 0
    @StateObject private var permissions = PermissionModel()
    @StateObject private var downloader = ModelDownloader()
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var history = History.shared
    @State private var launchAtLogin = false
    /// +1 forward, -1 back: content slides in from the side it is coming from.
    @State private var direction = 1
    @Namespace private var chipHighlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let stepTitles = ["Welcome", "Permissions", "Engine & language", "Your text", "Try it"]
    private static var lastStep: Int { stepTitles.count - 1 }
    /// One Unsplash gradient per step, crossfaded.
    private static let gradients = ["gradient-dark", "gradient-purple", "gradient-blue", "gradient-purple", "gradient-dark"]

    private func go(to target: Int) {
        guard target != step, (0...Self.lastStep).contains(target) else { return }
        direction = target > step ? 1 : -1
        if reduceMotion { step = target; return }
        withAnimation(.smooth(duration: 0.42)) { step = target }
    }

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
                .padding(14)
            rightPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 860, height: 600)
        .background(
            ZStack {
                VisualEffectBlur(material: .underWindowBackground)
                DS.bg.opacity(0.45) // slightly transparent - desktop shows through
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.25), value: permissions.mic)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.25), value: permissions.accessibility)
    }

    // MARK: left - gradient, brand, step list

    private var leftPanel: some View {
        ZStack {
            // Base fill + gradient image as overlay: the overlay pattern keeps
            // scaledToFill from blowing the layout past the panel bounds.
            Color(hex: 0x0F0F0F)
                .overlay(
                    ZStack {
                        // All layers stay mounted; only opacity and a slow
                        // settle-in scale animate, which Core Animation does on the GPU.
                        ForEach(Array(Self.gradients.enumerated()), id: \.offset) { i, name in
                            if let img = Self.loadedImages[name] {
                                // Color.clear takes exactly the panel size, so photos
                                // with different aspect ratios all cover it.
                                Color.clear
                                    .overlay(Image(nsImage: img).resizable().scaledToFill())
                                    .clipped()
                                    .scaleEffect(i == step || reduceMotion ? 1 : 1.06)
                                    .opacity(i == step ? 1 : 0)
                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: step)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                )
            // Legibility scrim: uniform darkening + heavier bottom, so white
            // text and chips hold contrast on ANY gradient photo.
            Color(hex: 0x0F0F0F).opacity(0.38)
            LinearGradient(
                colors: [Color(hex: 0x0F0F0F).opacity(0.85), .clear],
                startPoint: .bottom, endPoint: .center
            )

            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                HStack(spacing: 12) {
                    HlasMark()
                        .fill(DS.brand)
                        .frame(width: 28, height: 28)
                    Text("HLAS")
                        .font(DS.display(36))
                        .tracking(10)
                        .foregroundStyle(DS.fg)
                }
                Text("DICTATION. NOT TYPING.")
                    .font(DS.label(10))
                    .tracking(4)
                    .foregroundStyle(DS.brand)
                    .padding(.top, 6)
                Text("Hold a key, speak, release.\nYour words land wherever your cursor is.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 14)

                VStack(spacing: 8) {
                    ForEach(0..<Self.stepTitles.count, id: \.self) { i in
                        stepChip(i)
                    }
                }
                .padding(.top, 26)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(width: 330)
        .frame(maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    /// Images decoded once, not on every render.
    private static let loadedImages: [String: NSImage] = {
        var dict: [String: NSImage] = [:]
        for name in Set(gradients) {
            if let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
               let img = NSImage(contentsOf: url) {
                dict[name] = img
            }
        }
        return dict
    }()

    private func stepChip(_ i: Int) -> some View {
        Button { if i < step { go(to: i) } } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(i == step ? Color(hex: 0x0F0F0F) : Color.white.opacity(0.18))
                        .frame(width: 20, height: 20)
                    if i < step {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(i == step ? DS.brand : .white.opacity(0.9))
                    } else {
                        Text("\(i + 1)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(i == step ? .white : .white.opacity(0.8))
                    }
                }
                Text(Self.stepTitles[i])
                    .font(.system(size: 12, weight: i == step ? .semibold : .regular))
                    .foregroundStyle(i == step ? Color(hex: 0x0F0F0F) : .white.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x0F0F0F).opacity(0.35))
                    if i == step {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.92))
                            .matchedGeometryEffect(id: "current", in: chipHighlight)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(i >= step)
        .accessibilityLabel("Step \(i + 1): \(Self.stepTitles[i])")
        .accessibilityValue(i == step ? "Current" : (i < step ? "Completed" : "Upcoming"))
        .accessibilityHint(i < step ? "Returns to this step" : "")
    }

    // MARK: right - step content

    private var rightPanel: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: permissionsStep
                    case 2: engineStep
                    case 3: textStep
                    default: tryItStep
                    }
                }
                .id(step)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 28 * CGFloat(direction))),
                    removal: .opacity.combined(with: .offset(x: -28 * CGFloat(direction)))))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 34)
            .padding(.top, 40)
            .clipped()
            footer
        }
    }

    // MARK: step 0 - welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("Welcome to Hlas", "Your own dictation app. No subscription, no account, no cloud unless you ask for it.")
            featureRow("waveform", "**Hold \(settings.hotkey.shortName)** and speak Czech or English. Release - the text pastes at your cursor, in any app.")
            if settings.quickTapEnabled {
                featureRow("hand.tap", "**Quick-tap \(settings.hotkey.shortName)** to latch hands-free mode. Tap again to stop.")
            }
            featureRow("lock", "Local by default - audio never leaves this Mac. Cloud engines are opt-in.")
            featureRow("bolt", "A small app that idles at ~60 MB RAM. The model loads on demand and unloads after inactivity.")
        }
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.brand)
                .frame(width: 24)
            Text(.init(text))
                .font(.system(size: 13))
                .foregroundStyle(DS.fg2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: DS.radiusSm).fill(Color.white.opacity(0.05)))
    }

    // MARK: step 1 - permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("Two permissions", "Both are checked live - the card turns green the moment macOS registers it.")
            permissionCard(
                granted: permissions.mic,
                icon: "mic",
                title: "Microphone",
                detail: "To hear what you dictate.",
                action: permissions.requestMic
            )
            permissionCard(
                granted: permissions.accessibility,
                icon: "keyboard",
                title: "Accessibility",
                detail: "To catch the \(settings.hotkey.shortName) key globally and paste text at your cursor.",
                action: permissions.requestAccessibility
            )
            if permissions.accessibilityStuck {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hlas is already switched on but this card stays grey? macOS kept an entry from an older Hlas build. Reset it, then switch Hlas on again in the list.")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Reset Accessibility entry", action: permissions.resetAccessibility)
                        .buttonStyle(.bordered)
                }
            } else if !permissions.accessibility {
                Text("System Settings opens on the right page - find Hlas in the list and switch it on.")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.fg3)
            }
        }
    }

    private func permissionCard(granted: Bool, icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : icon)
                .font(.system(size: 20))
                .foregroundStyle(granted ? DS.brand : DS.fg2)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: granted)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.fg)
                Text(detail).font(.system(size: 11)).foregroundStyle(DS.fg3)
            }
            Spacer()
            if !granted {
                Button("Grant", action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(DS.brand.opacity(0.9))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DS.radius)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radius)
                        .strokeBorder(granted ? DS.brand.opacity(0.35) : DS.border, lineWidth: 1)
                )
        )
    }

    // MARK: step 2 - engine & language

    private var engineStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Engine & language", "Where transcription runs. Change it anytime in Settings.")

            engineCard(.local, "On this Mac - private & free",
                       "Whisper large-v3-turbo. One-time 547 MB download. Works offline.")
                .fixedSize(horizontal: false, vertical: true)
            // Four cloud cards as a 2x2 grid: a fifth full-width row no longer fits 600 pt.
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    engineCard(.groq, "Groq - ~$3/mo",
                               "Fastest. Whisper large-v3-turbo, key at console.groq.com.")
                    engineCard(.openai, "OpenAI - ~$8/mo",
                               "Most accurate. gpt-transcribe, key at platform.openai.com.")
                }
                GridRow {
                    engineCard(.soniox, "Soniox - ~$3/mo",
                               "stt-async-v5. Key at console.soniox.com.")
                    engineCard(.fish, "Fish Audio - ~$11/mo",
                               "transcribe-1-pro. Key at fish.audio.")
                }
            }

            if settings.engine == .local {
                localModelStatus
            } else {
                apiKeyEntry
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("LANGUAGE").font(DS.label(10)).tracking(3).foregroundStyle(DS.fg3)
                LanguagePicker()
            }
            .padding(.top, 4)
        }
    }

    private func engineCard(_ kind: EngineKind, _ title: String, _ detail: String) -> some View {
        Button {
            settings.engine = kind
            (NSApp.delegate as? AppDelegate)?.rebuildTranscriber()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: settings.engine == kind ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(settings.engine == kind ? DS.brand : DS.fg3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.fg)
                    Text(detail).font(.system(size: 11)).foregroundStyle(DS.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSm)
                    .fill(Color.white.opacity(settings.engine == kind ? 0.07 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSm)
                            .strokeBorder(settings.engine == kind ? DS.brand.opacity(0.4) : DS.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(settings.engine == kind ? "Selected" : "Not selected")
    }

    @ViewBuilder
    private var localModelStatus: some View {
        if LocalWhisper.modelExists {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.brand).font(.system(size: 12))
                Text("Model ready").font(.system(size: 11)).foregroundStyle(DS.fg2)
            }
        } else if downloader.downloading {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: downloader.progress).tint(DS.brand)
                    .accessibilityLabel("Downloading transcription model")
                    .accessibilityValue("\(Int(downloader.progress * 100)) percent")
                Text("Downloading model… \(Int(downloader.progress * 100)) %")
                    .font(.system(size: 11)).foregroundStyle(DS.fg3)
                Button("Cancel", action: downloader.cancel)
                    .buttonStyle(.borderless).foregroundStyle(DS.fg3)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let error = downloader.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(DS.destructive)
                }
                Button("Download model (547 MB)") { downloader.start() }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.brand.opacity(0.9))
            }
        }
    }

    @ViewBuilder
    private var apiKeyEntry: some View {
        if let path = settings.engine.apiKeyPath {
            SecureField("Paste API key…", text: $settings[dynamicMember: path])
                .textFieldStyle(.plain)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: DS.radiusSm).fill(Color.white.opacity(0.06)))
                .onChange(of: settings.groqAPIKey) { (NSApp.delegate as? AppDelegate)?.rebuildTranscriber() }
                .onChange(of: settings.openaiAPIKey) { (NSApp.delegate as? AppDelegate)?.rebuildTranscriber() }
            Text("Audio is sent directly to \(settings.engine.shortName) for transcription. Your key stays in your macOS Keychain.")
                .font(.system(size: 10)).foregroundStyle(DS.fg3)
        }
    }

    // MARK: step 3 - your text

    private var textStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Your text", "Choose how much Hlas edits what you said. Hold Option while pressing \(settings.hotkey.shortName) to get a plain transcript once.")

            HStack(spacing: 10) {
                outputCard(.transcript, "Transcript", "Exactly your words, with punctuation. Nothing leaves the Mac with the Local engine.")
                outputCard(.smart, "Smart text", "Cleans up, fixes grammar and picks paragraphs or lists. Sends the text to OpenAI or Groq with your key.")
            }

            Text("ALWAYS ON THIS MAC, IN BOTH MODES").font(DS.label(10)).tracking(3).foregroundStyle(DS.fg3)
                .padding(.top, 4)
            onboardingToggle("Remove filler sounds", "ehm, eee, hmm and um disappear.", isOn: $settings.removeFillers)
            onboardingToggle("Spoken line breaks", "Say \u{201E}nový odstavec\u{201C} or \u{201E}nový řádek\u{201C} on its own to break the text.", isOn: $settings.spokenFormatting)

            tipRow("More in **Settings**: vocabulary with how words get misheard, exact replacements, and **Labs** with experiments such as spoken symbols (\u{201E}zavináč\u{201C} becomes @).")
        }
    }

    private func outputCard(_ mode: OutputMode, _ title: String, _ detail: String) -> some View {
        let selected = settings.outputMode == mode
        return Button { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { settings.outputMode = mode } } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? DS.brand : DS.fg3)
                        .contentTransition(.symbolEffect(.replace))
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.fg)
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(DS.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSm)
                    .fill(Color.white.opacity(selected ? 0.07 : 0.04))
                    .overlay(RoundedRectangle(cornerRadius: DS.radiusSm)
                        .strokeBorder(selected ? DS.brand.opacity(0.4) : DS.border, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .frame(height: 104)
        .accessibilityElement(children: .combine)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func onboardingToggle(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(DS.fg)
                Text(detail).font(.system(size: 11)).foregroundStyle(DS.fg3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(DS.brand)
    }

    // MARK: step 4 - try it

    private var tryItStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Try it now", "Click into the field, hold \(settings.hotkey.shortName), say something, release.")

            TryItField()

            HStack(spacing: 10) {
                Text("No Fn key? Use").font(.system(size: 12)).foregroundStyle(DS.fg2)
                HotkeyPicker().frame(width: 180)
            }

            if let last = history.entries.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LAST TRANSCRIPT").font(DS.label(9)).tracking(3).foregroundStyle(DS.fg3)
                    Text(last.text)
                        .font(.system(size: 12)).foregroundStyle(DS.fg2)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: DS.radiusSm).fill(Color.white.opacity(0.05)))
                }
            }

            Toggle(isOn: $launchAtLogin) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Hlas at login").font(.system(size: 13)).foregroundStyle(DS.fg)
                    Text("Lives quietly in the menu bar.").font(.system(size: 11)).foregroundStyle(DS.fg3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .tint(DS.brand)
            .onChange(of: launchAtLogin) { _, on in
                do {
                    if on { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    Log.write("launch-at-login toggle failed: \(error.localizedDescription)")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                tipRow("**Ctrl+Option+V** pastes your last dictation again.")
                tipRow("Everything here can be changed later: click the **Hlas icon** in the menu bar, then **Settings**.")
            }
        }
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(DS.brand).frame(width: 4, height: 4).padding(.top, 6)
            Text(.init(text)).font(.system(size: 12)).foregroundStyle(DS.fg2)
        }
    }

    // MARK: chrome

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DS.text(22, weight: .bold))
                .foregroundStyle(DS.fg)
            Text(subtitle)
                .font(DS.text(13))
                .foregroundStyle(DS.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { go(to: step - 1) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(DS.fg3)
            }
            Spacer()
            Button(step == Self.lastStep ? "Start dictating" : "Continue") {
                if step == Self.lastStep { close() } else { go(to: step + 1) }
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.brand.opacity(0.9))
            .disabled(step == 1 && !permissions.allGranted)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 20)
    }
}

/// Plain test target for the first dictation.
private struct TryItField: View {
    @State private var text = ""
    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14))
            .foregroundStyle(DS.fg)
            .scrollContentBackground(.hidden)
            .padding(10)
            .frame(height: 84)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSm)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: DS.radiusSm).strokeBorder(DS.border, lineWidth: 1))
            )
    }
}
