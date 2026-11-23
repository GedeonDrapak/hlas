import Foundation
import HlasCore

enum EngineKind: String, CaseIterable, Codable {
    case local      // whisper.cpp
    case hlasCloud = "hlascloud" // Hlas Cloud subscription, our API (see cloud/)
    case groq       // Groq API whisper-large-v3-turbo
    case openai     // OpenAI transcription API
    case soniox     // Soniox async API stt-async-v5
    case fish       // Fish Audio ASR transcribe-1-pro

    var displayName: String {
        switch self {
        case .local: return "Local (whisper.cpp)"
        case .hlasCloud: return "Hlas Cloud"
        case .groq: return "Groq API"
        case .openai: return "OpenAI API"
        case .soniox: return "Soniox API"
        case .fish: return "Fish Audio API"
        }
    }

    /// Segmented-control label; five full names do not fit the Settings width.
    var shortName: String {
        switch self {
        case .local: return "Local"
        case .hlasCloud: return "Hlas Cloud"
        case .groq: return "Groq"
        case .openai: return "OpenAI"
        case .soniox: return "Soniox"
        case .fish: return "Fish Audio"
        }
    }

    /// Where this engine's key lives on Settings; nil for Local.
    @MainActor var apiKeyPath: ReferenceWritableKeyPath<Settings, String>? {
        switch self {
        case .local: return nil
        case .hlasCloud: return \.hlasCloudKey
        case .groq: return \.groqAPIKey
        case .openai: return \.openaiAPIKey
        case .soniox: return \.sonioxAPIKey
        case .fish: return \.fishAPIKey
        }
    }
}

/// Flat UserDefaults-backed settings. No accounts, no sync, no telemetry.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var engine: EngineKind {
        didSet { d.set(engine.rawValue, forKey: "engine") }
    }
    /// ISO 639-1 code, or "auto".
    @Published var language: String {
        didSet { d.set(language, forKey: "language") }
    }
    /// Hlas Cloud license key (hlas_XXXXX-...), the bearer credential for our API.
    @Published var hlasCloudKey: String {
        didSet {
            if !KeychainStore.set(hlasCloudKey, for: "hlascloud") {
                Log.write("failed to save Hlas Cloud license key to Keychain")
            }
        }
    }
    @Published var groqAPIKey: String {
        didSet {
            if !KeychainStore.set(groqAPIKey, for: "groq") {
                Log.write("failed to save Groq API key to Keychain")
            }
        }
    }
    @Published var openaiAPIKey: String {
        didSet {
            if !KeychainStore.set(openaiAPIKey, for: "openai") {
                Log.write("failed to save OpenAI API key to Keychain")
            }
        }
    }
    @Published var sonioxAPIKey: String {
        didSet {
            if !KeychainStore.set(sonioxAPIKey, for: "soniox") {
                Log.write("failed to save Soniox API key to Keychain")
            }
        }
    }
    @Published var fishAPIKey: String {
        didSet {
            if !KeychainStore.set(fishAPIKey, for: "fish") {
                Log.write("failed to save Fish Audio API key to Keychain")
            }
        }
    }
    /// Seconds to keep the local model in RAM after last use. 0 = unload instantly.
    @Published var modelKeepAliveSeconds: Double {
        didSet { d.set(modelKeepAliveSeconds, forKey: "modelKeepAlive") }
    }
    /// Custom vocabulary hints (names, jargon) fed to the engine as a prompt.
    @Published var vocabulary: [String] {
        didSet { d.set(vocabulary, forKey: "vocabulary") }
    }
    /// Quick-switch language chips ("auto" is implicit, always shown).
    @Published var favoriteLanguages: [String] {
        didSet { d.set(favoriteLanguages, forKey: "favoriteLanguages") }
    }
    /// Input device UID. "" = follow system default, "builtin" = always the
    /// built-in mic (ignores AirPods auto-switch), else a specific device UID.
    @Published var inputDeviceUID: String {
        didSet { d.set(inputDeviceUID, forKey: "inputDeviceUID") }
    }

    @Published var hotkey: HotkeyChoice {
        didSet { d.set(hotkey.rawValue, forKey: "hotkey") }
    }
    /// Quick-tap the hotkey to latch hands-free recording; tap again to stop.
    /// Off: every release stops, however short the press.
    @Published var quickTapEnabled: Bool {
        didSet { d.set(quickTapEnabled, forKey: "quickTapEnabled") }
    }

    @Published var outputMode: OutputMode {
        didSet { d.set(outputMode.rawValue, forKey: "outputMode") }
    }
    @Published var historyEnabled: Bool {
        didSet { d.set(historyEnabled, forKey: "historyEnabled") }
    }
    @Published var historyRetentionDays: Int {
        didSet { d.set(historyRetentionDays, forKey: "historyRetentionDays") }
    }
    @Published var replacements: [TextReplacement] {
        didSet { d.set(try? JSONEncoder().encode(replacements), forKey: "replacements") }
    }
    /// Vocabulary term -> how the engine tends to mishear it ("Seedance": ["sídens"]).
    @Published var vocabularySoundsLike: [String: [String]] {
        didSet { d.set(vocabularySoundsLike, forKey: "vocabularySoundsLike") }
    }
    @Published var removeFillers: Bool {
        didSet { d.set(removeFillers, forKey: "removeFillers") }
    }
    @Published var spokenFormatting: Bool {
        didSet { d.set(spokenFormatting, forKey: "spokenFormatting") }
    }
    /// Labs: experiments, off by default.
    @Published var labsSpokenSymbols: Bool {
        didSet { d.set(labsSpokenSymbols, forKey: "labsSpokenSymbols") }
    }

    private init() {
        hotkey = HotkeyChoice(rawValue: d.string(forKey: "hotkey") ?? "") ?? .fn
        quickTapEnabled = d.object(forKey: "quickTapEnabled") as? Bool ?? true
        outputMode = OutputMode(rawValue: d.string(forKey: "outputMode") ?? "") ?? .transcript
        historyEnabled = d.object(forKey: "historyEnabled") as? Bool ?? true
        historyRetentionDays = d.object(forKey: "historyRetentionDays") as? Int ?? 0
        replacements = d.data(forKey: "replacements").flatMap { try? JSONDecoder().decode([TextReplacement].self, from: $0) } ?? []
        vocabularySoundsLike = d.dictionary(forKey: "vocabularySoundsLike") as? [String: [String]] ?? [:]
        removeFillers = d.object(forKey: "removeFillers") as? Bool ?? true
        spokenFormatting = d.object(forKey: "spokenFormatting") as? Bool ?? true
        labsSpokenSymbols = d.object(forKey: "labsSpokenSymbols") as? Bool ?? false

        engine = EngineKind(rawValue: d.string(forKey: "engine") ?? "") ?? .local
        language = d.string(forKey: "language") ?? "cs"
        hlasCloudKey = KeychainStore.string(for: "hlascloud") ?? ""
        groqAPIKey = Self.loadAPIKey(account: "groq", legacyKey: "groqAPIKey", defaults: d)
        openaiAPIKey = Self.loadAPIKey(account: "openai", legacyKey: "openaiAPIKey", defaults: d)
        sonioxAPIKey = KeychainStore.string(for: "soniox") ?? ""
        fishAPIKey = KeychainStore.string(for: "fish") ?? ""
        modelKeepAliveSeconds = d.object(forKey: "modelKeepAlive") as? Double ?? 180
        vocabulary = d.stringArray(forKey: "vocabulary") ?? []
        favoriteLanguages = d.stringArray(forKey: "favoriteLanguages") ?? ["cs", "en"]
        inputDeviceUID = d.string(forKey: "inputDeviceUID") ?? "builtin"
    }

    private static func loadAPIKey(account: String, legacyKey: String, defaults: UserDefaults) -> String {
        if let saved = KeychainStore.string(for: account) { return saved }
        guard let legacy = defaults.string(forKey: legacyKey), !legacy.isEmpty else { return "" }
        if KeychainStore.set(legacy, for: account) {
            defaults.removeObject(forKey: legacyKey)
        }
        return legacy
    }

    var vocabularyPrompt: String? {
        vocabulary.isEmpty ? nil : vocabulary.joined(separator: ", ")
    }

    var cleanupOptions: TextCleanupOptions {
        TextCleanupOptions(removeFillers: removeFillers, spokenFormatting: spokenFormatting, spokenSymbols: labsSpokenSymbols)
    }

    /// Sounds-like fixes first, so a user's own replacement can still refine the term.
    var allReplacements: [TextReplacement] {
        Vocabulary.rules(vocabularySoundsLike.filter { vocabulary.contains($0.key) }) + replacements
    }

    func removeVocabulary(_ word: String) {
        vocabulary.removeAll { $0 == word }
        vocabularySoundsLike[word] = nil
    }
}
