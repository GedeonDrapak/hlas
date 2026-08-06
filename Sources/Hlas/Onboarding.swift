import AppKit
import SwiftUI
import AVFoundation
import ServiceManagement

/// First-run onboarding: brand moment → permissions with LIVE status →
/// engine + language → try it. Shown when onboarding was never finished
/// or a required permission is missing.
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
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
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

    @State private var step = 0
    @StateObject private var permissions = PermissionModel()
    @StateObject private var downloader = ModelDownloader()
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var history = History.shared
    @State private var launchAtLogin = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(36)
            footer
        }
        .frame(width: 520, height: 620)
        .background(
            ZStack {
                VisualEffectBlur(material: .underWindowBackground)
                DS.bg.opacity(0.72)
                // Faint Eden-green glow, top center — brand signature
                RadialGradient(
                    colors: [DS.brand.opacity(step == 0 ? 0.16 : 0.07), .clear],
                    center: .init(x: 0.5, y: 0.05), startRadius: 0, endRadius: 420
                )
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
        .animation(.easeOut(duration: 0.25), value: step)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcome
        case 1: permissionsStep
        case 2: engineStep
        default: tryItStep
        }
    }

    // MARK: step 0 — welcome

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("HLAS")
                .font(.system(size: 44, weight: .bold))
                .tracking(20)
                .foregroundStyle(DS.fg)
                .padding(.leading, 20) // optically recenter the tracking
            Text("DICTATION. NOT TYPING.")
                .font(DS.label(11))
                .tracking(4)
                .foregroundStyle(DS.brand)
            Spacer().frame(height: 8)
            VStack(spacing: 10) {
                featureRow("waveform", "Hold **Fn**, speak Czech or English, release — text appears where your cursor is.")
                featureRow("lock", "Runs 100% locally by default. Nothing leaves your Mac.")
                featureRow("bolt", "2 MB app. Model loads only while transcribing.")
            }
            Spacer()
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
        .background(RoundedRectangle(cornerRadius: DS.radiusSm).fill(Color.white.opacity(0.04)))
    }

    // MARK: step 1 — permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader("PERMISSIONS", "Hlas needs two system permissions. Both stay on this Mac.")
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
                Text("System Settings opens → find Hlas in the list → switch it on. The checkmark here goes green the moment it works.")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.fg3)
            }
            Spacer()
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
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radius)
                        .strokeBorder(granted ? DS.brand.opacity(0.35) : DS.border, lineWidth: 1)
                )
        )
    }

    // MARK: step 2 — engine & language

    private var engineStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader("ENGINE", "Where should transcription run? You can switch anytime in Settings.")

            engineCard(.local, "On this Mac — private & free",
                       "Whisper large-v3-turbo. One-time 547 MB download. No internet needed.")
            engineCard(.groq, "Groq cloud — fastest, ~$3/month",
                       "Full whisper-large-v3. Needs a free API key from console.groq.com.")
            engineCard(.openai, "OpenAI cloud — best accuracy, ~$8/month",
                       "gpt-transcribe. Needs an API key from platform.openai.com.")

            if settings.engine == .local {
                localModelStatus
            } else {
                apiKeyEntry
            }

            HStack {
                Text("LANGUAGE").font(DS.label(10)).tracking(3).foregroundStyle(DS.fg3)
                Picker("", selection: $settings.language) {
                    Text("Čeština").tag("cs")
                    Text("English").tag("en")
                    Text("Auto").tag("auto")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Spacer()
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
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSm)
                    .fill(Color.white.opacity(settings.engine == kind ? 0.06 : 0.03))
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
            .background(RoundedRectangle(cornerRadius: DS.radiusSm).fill(Color.white.opacity(0.05)))
            .onChange(of: settings.groqAPIKey) { (NSApp.delegate as? AppDelegate)?.rebuildTranscriber() }
            .onChange(of: settings.openaiAPIKey) { (NSApp.delegate as? AppDelegate)?.rebuildTranscriber() }
    }

    // MARK: step 3 — try it

    private var tryItStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader("TRY IT", "Click into the field below, hold Fn, say something, release.")

            TryItField()

            if let last = history.entries.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LAST TRANSCRIPT").font(DS.label(9)).tracking(3).foregroundStyle(DS.fg3)
                    Text(last.text)
                        .font(.system(size: 12)).foregroundStyle(DS.fg2)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: DS.radiusSm).fill(Color.white.opacity(0.04)))
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
                tipRow("Hold **Fn** = push-to-talk. Quick **tap** = hands-free until the next tap.")
                tipRow("Add names & jargon in **Settings → Vocabulary** — the model learns to spell them.")
                tipRow("Menu bar **waveform icon** → Settings, history, quit.")
            }
            Spacer()
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
            Text(title).font(DS.label(11)).tracking(4).foregroundStyle(DS.brand)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(DS.fg2)
        }
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack {
            // Step dots
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? DS.brand : Color.white.opacity(0.15))
                        .frame(width: i == step ? 18 : 6, height: 6)
                }
            }
            Spacer()
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.borderless)
                    .foregroundStyle(DS.fg3)
            }
            Button(step == 3 ? "Start dictating" : "Continue") {
                if step == 3 { close() } else { step += 1 }
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.brand.opacity(0.9))
            .disabled(step == 1 && !permissions.allGranted)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(Color.white.opacity(0.03))
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
            .frame(height: 90)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSm)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: DS.radiusSm).strokeBorder(DS.border, lineWidth: 1))
            )
    }
}
