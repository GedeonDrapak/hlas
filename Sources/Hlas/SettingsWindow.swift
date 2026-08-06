import AppKit
import SwiftUI

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
    var onEngineChange: () -> Void

    private static let languages: [(String, String)] = [
        ("cs", "Čeština"), ("en", "English"), ("sk", "Slovenčina"),
        ("de", "Deutsch"), ("auto", "Auto-detect"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                section("ENGINE") {
                    Picker("", selection: $settings.engine) {
                        ForEach(EngineKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: settings.engine) { onEngineChange() }

                    switch settings.engine {
                    case .local: localEngineControls
                    case .groq: apiKeyField("Groq API key", text: $settings.groqAPIKey, hint: "console.groq.com — ~$0.04/hr of audio")
                    case .openai: apiKeyField("OpenAI API key", text: $settings.openaiAPIKey, hint: "gpt-transcribe — ~$0.27/hr, best accuracy + vocabulary support")
                    }
                }

                section("LANGUAGE") {
                    Picker("", selection: $settings.language) {
                        ForEach(Self.languages, id: \.0) { code, name in Text(name).tag(code) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
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

                section("HISTORY") {
                    if history.entries.isEmpty {
                        Text("Nothing yet — hold Fn and speak.")
                            .font(.system(size: 11)).foregroundStyle(DS.fg3)
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
                DS.bg.opacity(0.72) // keep near-black identity over the blur
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HLAS")
                .font(.system(size: 13, weight: .bold))
                .tracking(6)
                .foregroundStyle(DS.fg)
            Text("Hold Fn · speak · release")
                .font(.system(size: 11))
                .foregroundStyle(DS.fg3)
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var localEngineControls: some View {
        if LocalWhisper.modelExists {
            HStack(spacing: 6) {
                Circle().fill(DS.brand).frame(width: 6, height: 6)
                Text("large-v3-turbo (quantized, 547 MB) ready")
                    .font(.system(size: 11)).foregroundStyle(DS.fg2)
            }
        } else if downloader.downloading {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: downloader.progress).tint(DS.brand)
                Text("Downloading model… \(Int(downloader.progress * 100))%")
                    .font(.system(size: 11)).foregroundStyle(DS.fg3)
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
        }
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !settings.vocabulary.contains(word) else { return }
        settings.vocabulary.append(word)
        newWord = ""
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
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(DS.surfaceHover))
            }
        }
    }
}
