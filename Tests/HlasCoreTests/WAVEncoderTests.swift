import Foundation
import HlasCore
import Testing

@Suite("WAV encoder")
struct WAVEncoderTests {
    @Test("Writes a valid mono PCM header and clips samples")
    func headerAndSamples() {
        let data = WAVEncoder.encode(samples: [-2, 0, 2])

        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        #expect(data.count == 50)
        #expect(uint32(data, at: 4) == 42)
        #expect(uint32(data, at: 24) == 16_000)
        #expect(uint32(data, at: 40) == 6)
        #expect(int16(data, at: 44) == -32_767)
        #expect(int16(data, at: 46) == 0)
        #expect(int16(data, at: 48) == 32_767)
    }

    private func uint32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private func int16(_ data: Data, at offset: Int) -> Int16 {
        Int16(bitPattern: UInt16(data[offset]) | UInt16(data[offset + 1]) << 8)
    }
}
