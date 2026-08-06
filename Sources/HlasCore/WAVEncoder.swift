import Foundation

public enum WAVEncoder {
    public static func encode(samples: [Float], sampleRate: Int = 16_000) -> Data {
        var data = Data()
        let byteRate = sampleRate * 2
        let dataSize = samples.count * 2

        func append(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(16)
        append16(1)
        append16(1)
        append(UInt32(sampleRate))
        append(UInt32(byteRate))
        append16(2)
        append16(16)
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))

        var pcm = [Int16](repeating: 0, count: samples.count)
        for (index, sample) in samples.enumerated() {
            pcm[index] = Int16(max(-1, min(1, sample)) * 32767)
        }
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
