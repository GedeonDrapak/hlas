import Foundation
import Testing
import HlasCore
@testable import Hlas

/// Engine that hallucinates a subtitle credit only when prompted.
private struct PrimedHallucination: Transcriber {
    var unprimed = "Chtěl bych shrnout dnešní poradu."
    func transcribe(samples: [Float], language: String?, prompt: String?, keepAlive: Double) async throws -> String {
        "Titulky vytvořil JohnyX."
    }
    func transcribeWithoutPrompt(samples: [Float], language: String?, keepAlive: Double) async throws -> String {
        unprimed
    }
}

@Suite("Hallucination retry")
struct HallucinationRetryTests {
    @Test func recoversTheDictationWithoutPrompt() async throws {
        let result = try await PrimedHallucination().transcribeRecovering(samples: [], language: "cs", prompt: nil, keepAlive: 0)
        #expect(result == ("Chtěl bych shrnout dnešní poradu.", true))
    }

    @Test func keepsTheOriginalWhenTheRetryIsAlsoNoise() async throws {
        let engine = PrimedHallucination(unprimed: "Titulky vytvořil JohnyX.")
        let result = try await engine.transcribeRecovering(samples: [], language: "cs", prompt: nil, keepAlive: 0)
        #expect(result == ("Titulky vytvořil JohnyX.", true))
    }

    @Test func doesNotRetryARealTranscript() async throws {
        let result = try await EchoTranscriber().transcribeRecovering(samples: [0], language: "cs", prompt: nil, keepAlive: 0)
        #expect(!result.retried)
    }

    /// Benchmark clip s19 (docs/benchmarks/parakeet-cs): a clean 16 s Czech
    /// dictation that the primed turbo model turned into "Titulky vytvořil JohnyX.".
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HLAS_S19_WAV"] != nil
                   && ProcessInfo.processInfo.environment["HLAS_MODEL_PATH"] != nil))
    func benchmarkClipS19() async throws {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HLAS_S19_WAV"]!)
        let samples = try #require(AudioPreparation.padded(try AudioFileImporter.read(url, token: CancellationToken())))
        let whisper = LocalWhisper()
        let primed = try await whisper.transcribe(samples: samples, language: "cs", prompt: nil, keepAlive: 0)
        let result = try await whisper.transcribeRecovering(samples: samples, language: "cs", prompt: nil, keepAlive: 0)
        print("S19_PRIMED | \(primed)")
        print("S19_RESULT retried=\(result.retried) | \(result.text)")
        #expect(result.text.localizedCaseInsensitiveContains("poradu"))
        #expect(!Hallucinations.filter(result.text).isEmpty)
        whisper.unloadAndWait()
    }
}
