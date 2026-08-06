import Foundation
import HlasCore

/// Shared multipart upload for OpenAI-compatible transcription endpoints
/// (Groq and OpenAI both speak the same protocol).
struct OpenAICompatibleTranscriber: Transcriber {
    let endpoint: URL
    let apiKey: String
    let model: String
    let providerName: String

    func transcribe(samples: [Float], language: String?) async throws -> String {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "Hlas", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "API key missing - open Settings"
            ])
        }
        let wav = WAVEncoder.encode(samples: samples)
        let boundary = "hlas-\(UUID().uuidString)"

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", model)
        field("response_format", "json")
        field("temperature", "0")
        if let language { field("language", language) }
        if let prompt = await Settings.shared.vocabularyPrompt { field("prompt", prompt) }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranscriptionNetworkError.from(error, provider: providerName)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TranscriptionNetworkError.http(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1,
                provider: providerName
            )
        }
        struct Reply: Decodable { let text: String }
        do {
            return try JSONDecoder().decode(Reply.self, from: data).text
        } catch {
            throw TranscriptionNetworkError.invalidResponse(provider: providerName)
        }
    }
}

@MainActor
enum TranscriberFactory {
    static func make() -> Transcriber {
        let s = Settings.shared
        switch s.engine {
        case .groq:
            return OpenAICompatibleTranscriber(
                endpoint: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!,
                apiKey: s.groqAPIKey,
                model: "whisper-large-v3-turbo",
                providerName: "Groq"
            )
        case .openai:
            // gpt-transcribe (July 2026): beats gpt-4o-transcribe, cheaper
            // ($0.0045/min), supports context/keyword prompts.
            return OpenAICompatibleTranscriber(
                endpoint: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
                apiKey: s.openaiAPIKey,
                model: "gpt-transcribe",
                providerName: "OpenAI"
            )
        case .local:
            return LocalTranscriberHolder.shared
        }
    }
}
