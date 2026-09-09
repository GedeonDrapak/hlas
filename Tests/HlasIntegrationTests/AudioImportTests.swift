import AVFoundation
import Foundation
import Testing
import HlasCore
@testable import Hlas

@Suite("Audio file decoding") struct AudioImportTests {
    @Test func resamplesStereoAndHonorsCancellation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        do {
            var settings = format.settings
            settings[AVLinearPCMIsNonInterleaved] = false
            let file = try AVAudioFile(forWriting: url, settings: settings)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000))
            buffer.frameLength = 48000
            for channel in 0..<2 { for index in 0..<48000 { buffer.floatChannelData![channel][index] = 0.2 } }
            try file.write(from: buffer)
        }
        let samples = try AudioFileImporter.read(url, token: CancellationToken())
        #expect(abs(samples.count - 16000) < 32)
        #expect(abs(samples[8000] - 0.2) < 0.01)
        let token = CancellationToken(); token.cancel()
        #expect(throws: CancellationError.self) { try AudioFileImporter.read(url, token: token) }
    }
}
