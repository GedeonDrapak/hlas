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
        return String(format: "[hlas: %.1fs recorded — no engine configured]", seconds)
    }
}

/// Encodes Float32 samples as a 16-bit PCM WAV blob (for API upload).
enum WAVEncoder {
    static func encode(samples: [Float], sampleRate: Int = 16_000) -> Data {
        var data = Data()
        let byteRate = sampleRate * 2
        let dataSize = samples.count * 2

        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(16)
        append16(1)                      // PCM
        append16(1)                      // mono
        append(UInt32(sampleRate))
        append(UInt32(byteRate))
        append16(2)                      // block align
        append16(16)                     // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))

        var pcm = [Int16](repeating: 0, count: samples.count)
        for (i, s) in samples.enumerated() {
            pcm[i] = Int16(max(-1, min(1, s)) * 32767)
        }
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
