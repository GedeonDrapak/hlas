import Foundation
import Testing
@testable import HlasCore

@Suite("Dictation reliability") struct DictationTests {
    @Test func legacyHistoryKeepsOriginal() throws {
        let data = Data("[{\"id\":\"6F34D712-C8B8-490D-A0C2-AE8499B3F591\",\"text\":\"Původní text\",\"date\":0}]".utf8)
        let entries = try JSONDecoder().decode([TranscriptEntry].self, from: data)
        #expect(entries[0].original == "Původní text")
        #expect(entries[0].mode == nil)
        let newer = TranscriptEntry(text: "Upravený text", rawText: entries[0].original, mode: .smart)
        let roundTrip = try JSONDecoder().decode(TranscriptEntry.self, from: JSONEncoder().encode(newer))
        #expect(roundTrip.original == "Původní text")
        #expect(roundTrip.text == "Upravený text")
    }
    @Test func wordBoundariesAndLiteralReplacement() {
        let rules = [TextReplacement(from: "Eden makers", to: "Edenmakers"), TextReplacement(from: "cena", to: "$100")]
        #expect(TextReplacement.apply(rules, to: "Eden makers, cena. Cenami neplýtvej.") == "Edenmakers, $100. Cenami neplýtvej.")
        #expect(TextReplacement.apply([TextReplacement(from: "Řeč", to: "Hlas")], to: "řeč, řečník") == "Hlas, řečník")
    }
    @Test func silenceAndShortSpeech() {
        #expect(AudioPreparation.padded(Array(repeating: 0, count: 32_000)) == nil)
        #expect(AudioPreparation.padded(Array(repeating: 0.2, count: 4800)) == nil)
        let padded = AudioPreparation.padded(Array(repeating: Float(0.02), count: 8000))!
        #expect(padded.count == 19_200)
        #expect(padded[3999] == 0)
        #expect(padded[4000] == 0.02)
        #expect(padded[11_999] == 0.02)
        #expect(padded[12_000] == 0)
    }
    @Test func cancellationIsThreadSafe() async throws {
        let token = CancellationToken()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 { group.addTask { token.cancel(); #expect(token.isCancelled) } }
        }
        #expect(throws: CancellationError.self) { try token.check() }
    }
    @Test func invalidSmartResultsAreRecoverable() {
        #expect(throws: SmartTextError.self) { try SmartTextRules.validate("  ", original: "Ahoj") }
        #expect(throws: SmartTextError.self) { try SmartTextRules.validate(String(repeating: "a", count: 2000), original: "Ahoj") }
    }
    @Test func wavHandlesNonfiniteSamples() {
        let data = WAVEncoder.encode(samples: [.nan, .infinity, -.infinity, 1, -1])
        #expect(data.count == 54)
        #expect(Array(data[44..<50]) == Array(repeating: UInt8(0), count: 6))
        #expect(Array(data[50..<54]) == [255, 127, 1, 128])
    }
}
