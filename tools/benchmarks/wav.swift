import Foundation

@main enum WAVBenchmark {
    static func main() {
        for duration in [10, 180] {
            let samples = (0..<(16_000 * duration)).map { Float($0 % 100) / 100 - 0.5 }
            precondition(WAVEncoder.encode(samples: samples) == BaselineWAVEncoder.encode(samples: samples))
            for (name, encode) in [("baseline", BaselineWAVEncoder.encode), ("current", WAVEncoder.encode)] {
                var times: [Double] = []
                var bytes = 0
                for _ in 0..<9 {
                    let start = ContinuousClock.now
                    bytes += encode(samples, 16000).count
                    let duration = start.duration(to: .now)
                    times.append(Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15)
                }
                print("audio_s=\(duration) encoder=\(name) p50_ms=\(times.sorted()[4]) bytes=\(bytes)")
            }
        }
    }
}
