import Foundation
import HlasCore

protocol Transcriber {
    /// 16 kHz mono Float32 samples → text.
    func transcribe(samples: [Float], language: String?, prompt: String?, keepAlive: Double) async throws -> String
    /// Same audio with no prompt of any kind (local Whisper also drops its
    /// priming sentence). Used only to recover from a hallucination.
    func transcribeWithoutPrompt(samples: [Float], language: String?, keepAlive: Double) async throws -> String
    /// Free model memory (local engines). No-op for API engines.
    func unload()
}

extension Transcriber {
    func unload() {}
    func transcribeWithoutPrompt(samples: [Float], language: String?, keepAlive: Double) async throws -> String {
        try await transcribe(samples: samples, language: language, prompt: nil, keepAlive: keepAlive)
    }

    /// The Czech priming prompt occasionally turns a real dictation into a
    /// subtitle credit ("Titulky vytvořil JohnyX."), which the filter then
    /// drops. Retry once without any prompt before giving up on the audio.
    func transcribeRecovering(samples: [Float], language: String?, prompt: String?,
                              keepAlive: Double) async throws -> (text: String, retried: Bool) {
        let first = try await transcribe(samples: samples, language: language, prompt: prompt, keepAlive: keepAlive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty, Hallucinations.filter(first).isEmpty else { return (first, false) }
        try Task.checkCancellation()
        let second = try await transcribeWithoutPrompt(samples: samples, language: language, keepAlive: keepAlive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !second.isEmpty, !Hallucinations.filter(second).isEmpty else { return (first, true) }
        return (second, true)
    }
}

/// Placeholder engine used until a real engine is configured.
struct EchoTranscriber: Transcriber {
    func transcribe(samples: [Float], language: String?, prompt: String?, keepAlive: Double) async throws -> String {
        let seconds = Double(samples.count) / 16_000
        return String(format: "[hlas: %.1fs recorded - no engine configured]", seconds)
    }
}
