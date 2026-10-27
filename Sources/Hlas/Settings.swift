import Foundation
import HlasCore

enum EngineKind: String, CaseIterable, Codable {
    case local      // whisper.cpp
    case groq       // Groq API whisper-large-v3-turbo
    case openai     // OpenAI transcription API
    case soniox     // Soniox async API stt-async-v5
    case fish       // Fish Audio ASR transcribe-1-pro

    var displayName: String {
        switch self {
        case .local: return "Local (whisper.cpp)"
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

    private init() {
        hotkey = HotkeyChoice(rawValue: d.string(forKey: "hotkey") ?? "") ?? .fn
        outputMode = OutputMode(rawValue: d.string(forKey: "outputMode") ?? "") ?? .transcript
        historyEnabled = d.object(forKey: "historyEnabled") as? Bool ?? true
        historyRetentionDays = d.object(forKey: "historyRetentionDays") as? Int ?? 0
        replacements = d.data(forKey: "replacements").flatMap { try? JSONDecoder().decode([TextReplacement].self, from: $0) } ?? []

        engine = EngineKind(rawValue: d.string(forKey: "engine") ?? "") ?? .local
        language = d.string(forKey: "language") ?? "cs"
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
}
