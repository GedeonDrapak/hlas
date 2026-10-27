import AppKit
import ServiceManagement
import SwiftUI
import HlasCore

@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    private weak var appDelegate: AppDelegate?

    func show(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(onEngineChange: { [weak self] in
                self?.appDelegate?.rebuildTranscriber()
            }))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var history = History.shared
    @StateObject private var downloader = ModelDownloader()
    @State private var newWord = ""
    @State private var replaceFrom = ""
    @State private var replaceTo = ""
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?
    var onEngineChange: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                section("HOTKEY") {
                    HotkeyPicker()
                    Text("Hold to dictate, quick-tap for hands-free. No Fn key on your keyboard? Pick a right-side modifier.")
                        .font(DS.text(11)).foregroundStyle(DS.fg2)
                }

                section("OUTPUT") {
                    Picker("Output", selection: $settings.outputMode) {
                        ForEach(OutputMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    Text(settings.outputMode == .smart
                        ? "Automatically cleans up your words and chooses paragraphs or lists. Keeps your language and meaning."
                        : "Your words, without an AI editing pass.")
                        .font(DS.text(11)).foregroundStyle(DS.fg2)
                    if settings.outputMode == .smart {
                        Text(SmartTextProcessor.configured().map { "Text is sent to \($0.provider) for editing, including with Local transcription." }
                             ?? "Add an OpenAI or Groq key below to use Smart text.")
                            .font(DS.text(11)).foregroundStyle(DS.fg3)
                        if settings.engine == .local {
                            apiKeyField("OpenAI API key", text: $settings.openaiAPIKey, hint: "Used only for Smart text. Local audio stays on this Mac.")
                        } else if settings.engine == .soniox || settings.engine == .fish {
                            apiKeyField("OpenAI API key", text: $settings.openaiAPIKey, hint: "Used only for Smart text editing.")
                        }
                    }
                    Text(settings.hotkey == .rightOption
                         ? "Hold Left Option when pressing Right Option to use Transcript once."
                         : "Hold Option when pressing \(settings.hotkey.shortName) to use Transcript once.")
                        .font(DS.text(10)).foregroundStyle(DS.fg3)
                }

                section("ENGINE") {
                    Picker("", selection: $settings.engine) {
                        ForEach(EngineKind.allCases, id: \.self) { Text($0.shortName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: settings.engine) { onEngineChange() }

                    switch settings.engine {
                    case .local: localEngineControls
                    case .groq: apiKeyField("Groq API key", text: $settings.groqAPIKey, hint: "Your Groq key is stored in macOS Keychain.")
                    case .openai: apiKeyField("OpenAI API key", text: $settings.openaiAPIKey, hint: "Your OpenAI key is stored in macOS Keychain.")
                    case .soniox: apiKeyField("Soniox API key", text: $settings.sonioxAPIKey, hint: "stt-async-v5, ~$0.10 per hour of audio. Key at console.soniox.com.")
                    case .fish: apiKeyField("Fish Audio API key", text: $settings.fishAPIKey, hint: "transcribe-1-pro, ~$0.36 per hour of audio. Key at fish.audio/app/api-keys. Vocabulary is not used.")
                    }
                }

                section("LANGUAGE") {
                    LanguagePicker()
                }

                section("MICROPHONE") {
                    InputDevicePicker()
                }

                section("GENERAL") {
                    Toggle(isOn: Binding(
                        get: { launchAtLogin },
                        set: updateLaunchAtLogin
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start Hlas at login").font(.system(size: 12)).foregroundStyle(DS.fg)
                            Text("Keep dictation ready in the menu bar.")
                                .font(.system(size: 10)).foregroundStyle(DS.fg3)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(DS.brand)
                    if let launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.system(size: 10))
                            .foregroundStyle(DS.destructive)
                    }
                    HStack(spacing: 12) {
                        Button("Privacy") { LegalDocuments.open("Privacy") }
                        Button("Third-party notices") { LegalDocuments.open("ThirdPartyNotices") }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.fg3)
                }

                section("SUPPORT") {
                    Text("Export a small troubleshooting file. It contains no transcripts or API keys.")
                        .font(.caption)
                        .foregroundStyle(DS.fg3)
                    Button("Export diagnostics…") { DiagnosticsExporter.present() }
                        .buttonStyle(.bordered)
                }

                section("VOCABULARY") {
                    Text("Names and jargon the model should recognize.")
                        .font(.system(size: 11)).foregroundStyle(DS.fg3)
                    HStack {
                        TextField("Add word…", text: $newWord)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: DS.radiusSm).fill(DS.surfaceHover))
                            .onSubmit(addWord)
                        Button("Add", action: addWord).buttonStyle(.borderless).tint(DS.brand)
                    }
                    if !settings.vocabulary.isEmpty {
                        FlowLayoutish(words: settings.vocabulary) { word in
                            settings.vocabulary.removeAll { $0 == word }
                        }
                    }
                }

                section("TEXT REPLACEMENTS") {
                    Text("Apply your exact spellings in either output mode.").font(DS.text(11)).foregroundStyle(DS.fg3)
                    HStack {
                        TextField("Heard as", text: $replaceFrom)
                        Image(systemName: "arrow.right").foregroundStyle(DS.fg3)
                        TextField("Replace with", text: $replaceTo)
                        Button("Add") {
                            settings.replacements.append(TextReplacement(from: replaceFrom.trimmingCharacters(in: .whitespaces), to: replaceTo))
                            replaceFrom = ""; replaceTo = ""
                        }.disabled(replaceFrom.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(settings.replacements) { rule in
                        HStack {
                            Text("\(rule.from) → \(rule.to)").font(DS.text(11))
                            Spacer()
                            Button { settings.replacements.removeAll { $0.id == rule.id } } label: { Image(systemName: "xmark") }
                                .buttonStyle(.borderless).accessibilityLabel("Remove replacement")
                        }
                    }
                }

                section("HISTORY") {
                    Toggle("Save dictation history", isOn: $settings.historyEnabled).toggleStyle(.switch).tint(DS.brand)
                    Text("When off, new dictations are not saved. The last result remains available until Hlas quits.")
                        .font(DS.text(10)).foregroundStyle(DS.fg3)
                    Picker("Keep history", selection: $settings.historyRetentionDays) {
                        Text("1 day").tag(1)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("Until cleared").tag(0)
                    }

                    HStack {
                        if history.entries.isEmpty {
                            Text("Nothing yet - hold \(settings.hotkey.shortName) and speak.")
                                .font(.system(size: 11)).foregroundStyle(DS.fg3)
                        }
                        Spacer()
                        if !history.entries.isEmpty {
                            Button("Clear", role: .destructive) { history.clear() }
                                .buttonStyle(.borderless)
                                .foregroundStyle(DS.destructive)
                        }
                    }
                    if history.entries.isEmpty {
                        EmptyView()
                    }
                    ForEach(history.entries.prefix(5)) { entry in
                        HStack(alignment: .top) {
                            Text(entry.text).font(.system(size: 12)).foregroundStyle(DS.fg2).lineLimit(2)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.text, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc").font(.system(size: 10))
                            }
                            .buttonStyle(.borderless).foregroundStyle(DS.fg3)
                            .accessibilityLabel("Copy transcript")
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: DS.radiusSm).fill(DS.surface))
                    }
                }
            }
            .padding(28)
        }
        .frame(width: 420, height: 560)
        .background(
            ZStack {
                VisualEffectBlur(material: .underWindowBackground)
                DS.bg.opacity(0.5) // slightly transparent - desktop shows through
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HLAS")
                .font(DS.display(15))
                .tracking(5)
                .foregroundStyle(DS.fg)
            Text("Hold \(settings.hotkey.shortName) · speak · release")
                .font(.system(size: 11))
                .foregroundStyle(DS.fg3)
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var localEngineControls: some View {
        Picker("Model memory", selection: $settings.modelKeepAliveSeconds) {
            Text("Save memory").tag(0.0)
            Text("Balanced · 3 min").tag(180.0)
            Text("Fast start · 10 min").tag(600.0)
        }

        if LocalWhisper.modelExists {
            HStack(spacing: 6) {
                Circle().fill(DS.brand).frame(width: 6, height: 6)
                Text("large-v3-turbo (quantized, 547 MB) ready")
                    .font(.system(size: 11)).foregroundStyle(DS.fg2)
            }
        } else if downloader.downloading {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: downloader.progress).tint(DS.brand)
                    .accessibilityLabel("Downloading transcription model")
                    .accessibilityValue("\(Int(downloader.progress * 100)) percent")
                Text("Downloading model… \(Int(downloader.progress * 100))%")
                    .font(.system(size: 11)).foregroundStyle(DS.fg3)
                Button("Cancel", action: downloader.cancel)
                    .buttonStyle(.borderless).foregroundStyle(DS.fg3)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Needs a one-time 547 MB model download.")
                    .font(.system(size: 11)).foregroundStyle(DS.fg3)
                if let error = downloader.error {
                    Text(error).font(.system(size: 11)).foregroundStyle(DS.destructive)
                }
                Button("Download model") { downloader.start() }
                    .buttonStyle(.borderedProminent).tint(DS.brand.opacity(0.9))
            }
        }
    }

    private func apiKeyField(_ label: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SecureField(label, text: text)
                .textFieldStyle(.plain)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: DS.radiusSm).fill(DS.surfaceHover))
            Text(hint).font(.system(size: 10)).foregroundStyle(DS.fg3)
            Text("Selected cloud transcription sends audio directly to \(label.replacingOccurrences(of: " API key", with: "")) for transcription. Your key stays in your macOS Keychain.")
                .font(.system(size: 10)).foregroundStyle(DS.fg3)
        }
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !settings.vocabulary.contains(word) else { return }
        settings.vocabulary.append(word)
        newWord = ""
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Could not update login setting."
            Log.write("launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .tracking(3)
                .foregroundStyle(DS.fg3)
            content()
        }
    }
}

/// Simple wrapping chip list for vocabulary words.
struct FlowLayoutish: View {
    let words: [String]
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(words, id: \.self) { word in
                HStack(spacing: 4) {
                    Text(word).font(.system(size: 11)).foregroundStyle(DS.fg2).lineLimit(1)
                    Button { onRemove(word) } label: {
                        Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                    }
                    .buttonStyle(.borderless).foregroundStyle(DS.fg3)
                    .accessibilityLabel("Remove \(word) from vocabulary")
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(DS.surfaceHover))
            }
        }
    }
}

/// Hold-to-talk key menu, styled like the microphone picker.
struct HotkeyPicker: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Menu {
            ForEach(HotkeyChoice.allCases, id: \.self) { choice in
                if choice == .f13 { Divider() }
                Button { settings.hotkey = choice } label: {
                    HStack {
                        if settings.hotkey == choice { Image(systemName: "checkmark") }
                        Text(choice.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "keyboard").font(.system(size: 11)).foregroundStyle(DS.fg2)
                Text(settings.hotkey.title).font(.system(size: 12)).foregroundStyle(DS.fg)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(DS.fg3)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: DS.radiusSm).fill(Color.white.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Dictation hotkey")
        .accessibilityValue(settings.hotkey.title)
        .accessibilityHint("Choose the key you hold to dictate")
    }
}
