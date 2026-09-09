import Foundation
import HlasCore

struct SmartTextProcessor: Sendable {
    let endpoint: URL
    let apiKey: String
    let model: String
    let provider: String

    @MainActor static func configured() -> Self? {
        let settings = Settings.shared
        if settings.engine == .groq, !settings.groqAPIKey.isEmpty {
            return groq(settings.groqAPIKey)
        }
        if !settings.openaiAPIKey.isEmpty {
            return Self(endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
                        apiKey: settings.openaiAPIKey, model: "gpt-4.1-mini", provider: "OpenAI")
        }
        return settings.groqAPIKey.isEmpty ? nil : groq(settings.groqAPIKey)
    }
    private static func groq(_ key: String) -> Self {
        Self(endpoint: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
             apiKey: key, model: "openai/gpt-oss-120b", provider: "Groq")
    }

    func process(_ text: String, session: URLSession = .shared) async throws -> String {
        try Task.checkCancellation()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["model": model, "temperature": 0,
            "max_completion_tokens": min(16_000, max(1024, text.utf8.count)),
            "messages": [["role": "system", "content": SmartTextRules.prompt], ["role": "user", "content": text]]]
        if provider == "Groq" { body["reasoning_effort"] = "low" }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw TranscriptionNetworkError.from(error, provider: provider)
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TranscriptionNetworkError.http(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1, provider: provider)
        }
        struct Reply: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
                let finish_reason: String?
            }
            let choices: [Choice]
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let choice = reply.choices.first, choice.finish_reason == "stop",
              let output = choice.message.content else { throw SmartTextError.incomplete }
        return try SmartTextRules.validate(output, original: text)
    }
}
