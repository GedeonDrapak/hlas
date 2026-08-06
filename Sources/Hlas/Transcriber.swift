import Foundation

protocol Transcriber {
    /// 16 kHz mono Float32 samples → text.
    func transcribe(samples: [Float], language: String?) async throws -> String
    /// Free model memory (local engines). No-op for API engines.
    func unload()
}

extension Transcriber {
    func unload() {}
}

/// Placeholder engine used until a real engine is configured.
struct EchoTranscriber: Transcriber {
    func transcribe(samples: [Float], language: String?) async throws -> String {
        let seconds = Double(samples.count) / 16_000
        return String(format: "[hlas: %.1fs recorded - no engine configured]", seconds)
    }
}
