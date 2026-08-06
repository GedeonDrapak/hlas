import AppKit
import SwiftUI
import AVFoundation
import ServiceManagement

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
    }

    func requestMic() {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run { self.refresh() }
        }
    }

    func requestAccessibility() {
        _ = Hotkey.hasAccessibilityPermission(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
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

    private static let stepTitles = ["Welcome", "Permissions", "Engine & language", "Try it"]
    /// One Unsplash gradient per step, crossfaded.
    private static let gradients = ["gradient-dark", "gradient-purple", "gradient-blue", "gradient-dark"]

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
        .animation(.easeOut(duration: 0.3), value: step)
    }

    // MARK: left - gradient, brand, step list

    private var leftPanel: some View {
        ZStack {
            // Base fill + gradient image as overlay: the overlay pattern keeps
            // scaledToFill from blowing the layout past the panel bounds.
            Color(hex: 0x0F0F0F)
                .overlay(
                    ZStack {
                        ForEach(Array(Self.gradients.enumerated()), id: \.offset) { i, name in
                            if i == step, let img = Self.loadedImages[name] {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .transition(.opacity)
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
                Text("HLAS")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(12)
                    .foregroundStyle(.white.opacity(0.96))
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
        Button { if i < step { step = i } } label: {
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
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(i == step ? Color.white.opacity(0.92) : Color(hex: 0x0F0F0F).opacity(0.35))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: right - step content

    private var rightPanel: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: permissionsStep
                case 2: engineStep
                default: tryItStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 34)
            .padding(.top, 40)
            footer
        }
    }

    // MARK: step 0 - welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("Welcome to Hlas", "Your own dictation app. No subscription, no account, no cloud unless you ask for it.")
            featureRow("waveform", "**Hold Fn** and speak Czech or English. Release - the text pastes at your cursor, in any app.")
            featureRow("hand.tap", "**Quick-tap Fn** to latch hands-free mode. Tap again to stop.")
            featureRow("lock", "Local by default - audio never leaves this Mac. Cloud engines are opt-in.")
            featureRow("bolt", "A ~4 MB app that idles at ~60 MB RAM. The model loads on demand and unloads after inactivity.")
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
                detail: "To catch the Fn key globally and paste text at your cursor.",
                action: permissions.requestAccessibility
            )
            if !permissions.accessibility {
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
            stepHeader("Engine & language", "Where transcription runs. Switch anytime from the menu bar.")

            engineCard(.local, "On this Mac - private & free",
                       "Whisper large-v3-turbo. One-time 547 MB download. Works offline.")
            engineCard(.groq, "Groq cloud - fastest, ~$3/month",
                       "Full whisper-large-v3. Free API key at console.groq.com.")
            engineCard(.openai, "OpenAI cloud - best accuracy, ~$8/month",
                       "gpt-transcribe. API key at platform.openai.com.")

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
                }
                Spacer()
            }
            .padding(12)
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
                Text("Downloading model… \(Int(downloader.progress * 100)) %")
                    .font(.system(size: 11)).foregroundStyle(DS.fg3)
            }
        } else {
            Button("Download model (547 MB)") { downloader.start() }
                .buttonStyle(.borderedProminent)
                .tint(DS.brand.opacity(0.9))
        }
    }

    @ViewBuilder
    private var apiKeyEntry: some View {
        let binding = settings.engine == .groq ? $settings.groqAPIKey : $settings.openaiAPIKey
        SecureField("Paste API key…", text: binding)
            .textFieldStyle(.plain)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: DS.radiusSm).fill(Color.white.opacity(0.06)))
            .onChange(of: settings.groqAPIKey) { (NSApp.delegate as? AppDelegate)?.rebuildTranscriber() }
            .onChange(of: settings.openaiAPIKey) { (NSApp.delegate as? AppDelegate)?.rebuildTranscriber() }
    }

    // MARK: step 3 - try it

    private var tryItStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader("Try it now", "Click into the field, hold Fn, say something, release.")

            TryItField()

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
                tipRow("Add names & jargon in **Settings → Vocabulary** - the model learns to spell them.")
                tipRow("Menu bar **waveform icon** → Settings, history, this tour.")
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
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DS.fg)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(DS.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.borderless)
                    .foregroundStyle(DS.fg3)
            }
            Spacer()
            Button(step == 3 ? "Start dictating" : "Continue") {
                if step == 3 { close() } else { step += 1 }
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
