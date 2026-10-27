import Foundation
import HlasCore

/// multipart/form-data body builder shared by the cloud engines.
struct MultipartForm {
    let boundary = "hlas-\(UUID().uuidString)"
    private(set) var body = Data()

    mutating func field(_ name: String, _ value: String) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func wav(_ name: String, _ data: Data) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    func request(_ url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body + Data("--\(boundary)--\r\n".utf8)
        return request
    }
}

/// One HTTP round trip with the cancellation and error mapping every engine needs.
enum CloudHTTP {
    static func requireKey(_ apiKey: String) throws {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "Hlas", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "API key missing - open Settings"
            ])
        }
    }

    static func send(_ request: URLRequest, provider: String) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw TranscriptionNetworkError.from(error, provider: provider)
        }
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw TranscriptionNetworkError.http(statusCode: status, provider: provider)
        }
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, provider: String) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw TranscriptionNetworkError.invalidResponse(provider: provider) }
    }

    /// Upload timeout scaled to recording length.
    static func timeout(for samples: [Float]) -> TimeInterval {
        max(30, min(120, Double(samples.count) / 16000 * 0.3))
    }
}

/// Shared multipart upload for OpenAI-compatible transcription endpoints
/// (Groq and OpenAI both speak the same protocol).
struct OpenAICompatibleTranscriber: Transcriber {
    let endpoint: URL
    let apiKey: String
    let model: String
    let providerName: String

    func transcribe(samples: [Float], language: String?, prompt: String?, keepAlive: Double) async throws -> String {
        try CloudHTTP.requireKey(apiKey)
        try Task.checkCancellation()
        var form = MultipartForm()
        form.field("model", model)
        form.field("response_format", "json")
        form.field("temperature", "0")
        if let language { form.field("language", language) }
        if let prompt { form.field("prompt", prompt) }
        form.wav("file", WAVEncoder.encode(samples: samples))

        var request = form.request(endpoint, apiKey: apiKey)
        request.timeoutInterval = CloudHTTP.timeout(for: samples)
        let data = try await CloudHTTP.send(request, provider: providerName)
        struct Reply: Decodable { let text: String }
        return try CloudHTTP.decode(Reply.self, from: data, provider: providerName).text
    }
}

/// Soniox async STT (stt-async-v5, $0.10/h). No single-request endpoint exists:
/// upload, create, poll, fetch, then delete both so no audio stays on their side.
struct SonioxTranscriber: Transcriber {
    let apiKey: String
    private let base = URL(string: "https://api.soniox.com/v1")!
    private let provider = "Soniox"

    func transcribe(samples: [Float], language: String?, prompt: String?, keepAlive: Double) async throws -> String {
        try CloudHTTP.requireKey(apiKey)
        try Task.checkCancellation()

        var form = MultipartForm()
        form.wav("file", WAVEncoder.encode(samples: samples))
        var upload = form.request(base.appendingPathComponent("files"), apiKey: apiKey)
        upload.timeoutInterval = CloudHTTP.timeout(for: samples)
        struct Created: Decodable { let id: String }
        let fileID = try CloudHTTP.decode(Created.self, from: try await CloudHTTP.send(upload, provider: provider), provider: provider).id

        var transcriptionID: String?
        defer { cleanUp(fileID: fileID, transcriptionID: transcriptionID) }

        var body: [String: Any] = ["model": "stt-async-v5", "file_id": fileID]
        if let language { body["language_hints"] = [language] }
        if let prompt {
            body["context"] = ["terms": prompt.components(separatedBy: ", ")]
        }
        var create = request("transcriptions", method: "POST")
        create.httpBody = try JSONSerialization.data(withJSONObject: body)
        create.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let id = try CloudHTTP.decode(Created.self, from: try await CloudHTTP.send(create, provider: provider), provider: provider).id
        transcriptionID = id

        struct Job: Decodable { let status: String; let error_type: String? }
        let deadline = Date().addingTimeInterval(30 + Double(samples.count) / 16000)
        while true {
            try await Task.sleep(for: .milliseconds(250))
            let job = try CloudHTTP.decode(Job.self, from: try await CloudHTTP.send(request("transcriptions/\(id)"), provider: provider), provider: provider)
            if job.status == "completed" { break }
            if job.status == "error" || job.status == "failed" {
                // Job failures arrive as HTTP 200; reuse the HTTP messages.
                let balance = job.error_type?.contains("balance") == true
                throw TranscriptionNetworkError.http(statusCode: balance ? 402 : 400, provider: provider)
            }
            if Date() > deadline { throw TranscriptionNetworkError.timedOut(provider: provider) }
        }

        struct Transcript: Decodable { let text: String }
        let data = try await CloudHTTP.send(request("transcriptions/\(id)/transcript"), provider: provider)
        return try CloudHTTP.decode(Transcript.self, from: data, provider: provider).text
    }

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        return request
    }

    /// Detached so a cancelled dictation still cleans up. Soniox refuses to delete
    /// a job that is still processing; such leftovers expire after 30 days.
    private func cleanUp(fileID: String, transcriptionID: String?) {
        let transcription = transcriptionID.map { request("transcriptions/\($0)", method: "DELETE") }
        let file = request("files/\(fileID)", method: "DELETE")
        Task.detached {
            if let transcription { _ = try? await URLSession.shared.data(for: transcription) }
            _ = try? await URLSession.shared.data(for: file)
        }
    }
}

/// Fish Audio ASR (transcribe-1-pro, $0.36/h). One synchronous request.
/// No vocabulary parameter exists, so the prompt is not sent.
struct FishAudioTranscriber: Transcriber {
    let apiKey: String
    private let provider = "Fish Audio"

    func transcribe(samples: [Float], language: String?, prompt: String?, keepAlive: Double) async throws -> String {
        try CloudHTTP.requireKey(apiKey)
        try Task.checkCancellation()
        var form = MultipartForm()
        form.wav("audio", WAVEncoder.encode(samples: samples))
        if let language { form.field("language", language) }
        form.field("ignore_timestamps", "true")
        // Off, or the text carries <|speaker:N|> markers and [laughter] cues.
        form.field("diarize", "false")
        form.field("tag_audio_events", "false")

        var request = form.request(URL(string: "https://api.fish.audio/v1/asr")!, apiKey: apiKey)
        // A header, not a form field; anything but an exact match silently falls back to transcribe-1.
        request.setValue("transcribe-1-pro", forHTTPHeaderField: "model")
        request.timeoutInterval = CloudHTTP.timeout(for: samples)
        let data = try await CloudHTTP.send(request, provider: provider)
        struct Reply: Decodable { let text: String }
        return try CloudHTTP.decode(Reply.self, from: data, provider: provider).text
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
        case .soniox:
            return SonioxTranscriber(apiKey: s.sonioxAPIKey)
        case .fish:
            return FishAudioTranscriber(apiKey: s.fishAPIKey)
        case .local:
            return LocalTranscriberHolder.shared
        }
    }
}
