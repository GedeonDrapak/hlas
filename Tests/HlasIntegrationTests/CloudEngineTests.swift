import Foundation
import Testing
import HlasCore
@testable import Hlas

/// Hits the real Soniox and Fish Audio APIs. Invalid-key checks need only the network;
/// transcription runs per engine when SONIOX_API_KEY / FISH_API_KEY is set.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["HLAS_LIVE_TESTS"] == "1"))
struct CloudEngineTests {
    private static let env = ProcessInfo.processInfo.environment

    private func jfk() throws -> [Float] {
        let path = Self.env["HLAS_TEST_AUDIO"] ?? URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("whisper.cpp/samples/jfk.wav").path
        return try AudioFileImporter.read(URL(fileURLWithPath: path), token: CancellationToken())
    }

    @Test func rejectsInvalidKeys() async throws {
        let samples = try jfk()
        let engines: [(String, Transcriber)] = [
            ("Soniox", SonioxTranscriber(apiKey: "hlas-invalid-key")),
            ("Fish Audio", FishAudioTranscriber(apiKey: "hlas-invalid-key"))
        ]
        for (name, engine) in engines {
            do {
                _ = try await engine.transcribe(samples: samples, language: "en", prompt: nil, keepAlive: 0)
                Issue.record("\(name) accepted an invalid key")
            } catch {
                print("CLOUD_INVALID_KEY \(name) | \(error.localizedDescription)")
                #expect(error.localizedDescription == "Your \(name) API key was rejected. Check it in Settings.")
            }
        }
    }

    @Test(.enabled(if: env["SONIOX_API_KEY"] != nil))
    func sonioxTranscribes() async throws {
        let engine = SonioxTranscriber(apiKey: Self.env["SONIOX_API_KEY"]!)
        let text = try await engine.transcribe(samples: try jfk(), language: "en", prompt: "Kennedy", keepAlive: 0)
        print("SONIOX_FIXTURE | \(text)")
        #expect(text.localizedCaseInsensitiveContains("country"))
    }

    @Test(.enabled(if: env["FISH_API_KEY"] != nil))
    func fishAudioTranscribes() async throws {
        let engine = FishAudioTranscriber(apiKey: Self.env["FISH_API_KEY"]!)
        let text = try await engine.transcribe(samples: try jfk(), language: "en", prompt: nil, keepAlive: 0)
        print("FISH_FIXTURE | \(text)")
        #expect(text.localizedCaseInsensitiveContains("country"))
        #expect(!text.contains("<|speaker"))
    }
}
