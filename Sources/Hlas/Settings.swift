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
        didSet { d.set(groqAPIKey, forKey: "groqAPIKey") }
    }
    @Published var openaiAPIKey: String {
        didSet { d.set(openaiAPIKey, forKey: "openaiAPIKey") }
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

    private init() {
        engine = EngineKind(rawValue: d.string(forKey: "engine") ?? "") ?? .local
        language = d.string(forKey: "language") ?? "cs"
        groqAPIKey = d.string(forKey: "groqAPIKey") ?? ""
        openaiAPIKey = d.string(forKey: "openaiAPIKey") ?? ""
        modelKeepAliveSeconds = d.object(forKey: "modelKeepAlive") as? Double ?? 180
        vocabulary = d.stringArray(forKey: "vocabulary") ?? []
        favoriteLanguages = d.stringArray(forKey: "favoriteLanguages") ?? ["cs", "en"]
    }

    var vocabularyPrompt: String? {
        vocabulary.isEmpty ? nil : vocabulary.joined(separator: ", ")
    }
}
