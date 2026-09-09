import AVFoundation
import HlasCore

// Decode bounded chunks off the UI thread; never silently truncate a file.
enum AudioFileImporter {
    static func read(_ url: URL, token: CancellationToken) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard Double(file.length) / file.processingFormat.sampleRate <= 600 else {
            throw NSError(domain: "Hlas", code: 413,
                userInfo: [NSLocalizedDescriptionKey: "Choose an audio file up to 10 minutes long."])
        }
        guard let converter = AVAudioConverter(from: file.processingFormat, to: AudioRecorder.targetFormat),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192),
              let output = AVAudioPCMBuffer(pcmFormat: AudioRecorder.targetFormat, frameCapacity: 8192) else {
            throw NSError(domain: "Hlas", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format."])
        }
        var result: [Float] = []
        result.reserveCapacity(min(AudioPreparation.maxSamples, Int(Double(file.length) / file.processingFormat.sampleRate * 16000)))
        while true {
            try token.check()
            var readError: Error?
            var convertError: NSError?
            let status = converter.convert(to: output, error: &convertError) { requested, state in
                guard file.framePosition < file.length, requested > 0 else { state.pointee = .endOfStream; return nil }
                do {
                    try file.read(into: input, frameCount: min(requested, input.frameCapacity))
                    state.pointee = input.frameLength == 0 ? .endOfStream : .haveData
                    return input.frameLength == 0 ? nil : input
                } catch { readError = error; state.pointee = .endOfStream; return nil }
            }
            if let readError { throw readError }
            if let convertError { throw convertError }
            if let channel = output.floatChannelData?[0] {
                result.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            }
            guard result.count <= AudioPreparation.maxSamples else {
                throw NSError(domain: "Hlas", code: 413, userInfo: [NSLocalizedDescriptionKey: "Audio exceeds the 10-minute limit."])
            }
            if status == .endOfStream { break }
            if status == .error { throw NSError(domain: "Hlas", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not decode this audio file."]) }
        }
        return result
    }
}
