import Foundation

enum EngineKind: String, CaseIterable, Codable {
    case local      // whisper.cpp
    case groq       // Groq API whisper-large-v3-turbo
    case openai     // OpenAI transcription API

    var displayName: String {
        switch self {
        case .local: return "Local (whisper.cpp)"
        case .groq: return "Groq API"
        case .openai: return "OpenAI API"
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

    private init() {
        engine = EngineKind(rawValue: d.string(forKey: "engine") ?? "") ?? .local
        language = d.string(forKey: "language") ?? "cs"
        groqAPIKey = Self.loadAPIKey(account: "groq", legacyKey: "groqAPIKey", defaults: d)
        openaiAPIKey = Self.loadAPIKey(account: "openai", legacyKey: "openaiAPIKey", defaults: d)
        modelKeepAliveSeconds = d.object(forKey: "modelKeepAlive") as? Double ?? 180
        vocabulary = d.stringArray(forKey: "vocabulary") ?? []
        favoriteLanguages = d.stringArray(forKey: "favoriteLanguages") ?? ["cs", "en"]
        inputDeviceUID = d.string(forKey: "inputDeviceUID") ?? ""
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
