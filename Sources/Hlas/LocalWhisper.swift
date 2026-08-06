import CryptoKit
import Foundation
import CWhisper

/// whisper.cpp engine. The model loads on first use and is freed after
/// `modelKeepAliveSeconds` of inactivity, so idle RAM stays near zero.
final class LocalWhisper: Transcriber, @unchecked Sendable {
    private var ctx: OpaquePointer?
    private var unloadTimer: Timer?
    private let queue = DispatchQueue(label: "hlas.whisper", qos: .userInitiated)

    static let modelDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hlas/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let modelName = "ggml-large-v3-turbo-q5_0.bin"
    static let modelByteCount = 574_041_195
    static var modelURL: URL { modelDir.appendingPathComponent(modelName) }
    static var modelExists: Bool {
        (try? modelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) == modelByteCount
    }

    func transcribe(samples: [Float], language: String?) async throws -> String {
        guard Self.modelExists else {
            throw NSError(domain: "Hlas", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Model not downloaded - open Settings"
            ])
        }
        let vocabPrompt = await Settings.shared.vocabularyPrompt
        let keepAlive = await Settings.shared.modelKeepAliveSeconds

        return try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                do {
                    let text = try run(samples: samples, language: language, prompt: vocabPrompt)
                    scheduleUnload(after: keepAlive)
                    cont.resume(returning: text)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func run(samples: [Float], language: String?, prompt: String?) throws -> String {
        if ctx == nil {
            var cparams = whisper_context_default_params()
            cparams.use_gpu = true
            cparams.flash_attn = true
            ctx = whisper_init_from_file_with_params(Self.modelURL.path, cparams)
        }
        guard let ctx else {
            throw NSError(domain: "Hlas", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Failed to load model"
            ])
        }

        // Beam search: measurably better Czech than greedy, near-zero cost on
        // Metal (benchmarked ~1.1–1.5s for 11s audio on M1 Pro either way).
        var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        params.beam_search.beam_size = 5
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.no_timestamps = true
        params.suppress_blank = true
        params.temperature = 0
        params.n_threads = Int32(max(2, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))

        let langHolder = strdup(language ?? "auto")
        defer { free(langHolder) }
        params.language = UnsafePointer(langHolder)

        // Priming prompt (VoiceInk technique): a well-formed sentence in the
        // target language steers diacritics + punctuation; custom vocabulary
        // is appended so names/jargon decode correctly.
        let priming: String
        switch language {
        case "cs": priming = "Toto je přesný přepis mluveného projevu se správnou diakritikou, interpunkcí a velkými písmeny."
        case "sk": priming = "Toto je presný prepis hovoreného prejavu so správnou diakritikou a interpunkciou."
        case "en": priming = "This is an accurate transcript with proper punctuation and capitalization."
        default: priming = ""
        }
        let fullPrompt = [priming, prompt ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        let promptHolder = fullPrompt.isEmpty ? nil : strdup(fullPrompt)
        defer { promptHolder.map { free($0) } }
        if let promptHolder { params.initial_prompt = UnsafePointer(promptHolder) }

        let status = samples.withUnsafeBufferPointer { buf in
            whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
        guard status == 0 else {
            throw NSError(domain: "Hlas", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Transcription failed (\(status))"
            ])
        }

        var text = ""
        for i in 0..<whisper_full_n_segments(ctx) {
            if let seg = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: seg)
            }
        }
        return text
    }

    private func scheduleUnload(after seconds: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.unloadTimer?.invalidate()
            guard seconds >= 0 else { return } // negative = keep forever
            self?.unloadTimer = Timer.scheduledTimer(withTimeInterval: max(1, seconds), repeats: false) { _ in
                self?.unload()
            }
        }
    }

    func unload() {
        queue.async { [self] in
            if let c = ctx {
                whisper_free(c)
                ctx = nil
                NSLog("Hlas: model unloaded")
            }
        }
    }
}

/// Single shared instance so repeated dictations reuse the loaded model.
enum LocalTranscriberHolder {
    static let shared = LocalWhisper()
}

/// Downloads the quantized turbo model from Hugging Face with progress.
@MainActor
final class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: Double = 0
    @Published var downloading = false
    @Published var error: String?

    static let remote = URL(string:
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!
    nonisolated private static let expectedByteCount = LocalWhisper.modelByteCount
    nonisolated private static let expectedSHA256 = "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
    nonisolated private static var stagingURL: URL {
        LocalWhisper.modelDir.appendingPathComponent("\(LocalWhisper.modelName).download")
    }

    private var session: URLSession!
    private var task: URLSessionDownloadTask?

    func start() {
        guard !downloading else { return }
        downloading = true
        error = nil
        progress = 0
        try? FileManager.default.removeItem(at: Self.stagingURL)
        let delegateQueue = OperationQueue()
        delegateQueue.qualityOfService = .userInitiated
        delegateQueue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
        let task = session.downloadTask(with: Self.remote)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let p = Double(totalBytesWritten) / Double(max(1, totalBytesExpectedToWrite))
        Task { @MainActor in self.progress = p }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw ModelDownloadError.invalidResponse
            }
            let fileManager = FileManager.default
            let staging = Self.stagingURL
            try? fileManager.removeItem(at: staging)
            try fileManager.moveItem(at: location, to: staging)
            try Self.validate(staging)
            try Self.install(staging, at: LocalWhisper.modelURL)
            Task { @MainActor in
                self.downloading = false
                self.progress = 1
                self.task = nil
            }
        } catch {
            try? FileManager.default.removeItem(at: Self.stagingURL)
            Task { @MainActor in
                self.downloading = false
                self.error = error.localizedDescription
                self.task = nil
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            let cancelled = (error as NSError).domain == NSURLErrorDomain
                && (error as NSError).code == NSURLErrorCancelled
            Task { @MainActor in
                self.downloading = false
                self.task = nil
                self.error = cancelled ? nil : "Could not download the model. Check your connection and try again."
            }
        }
    }

    nonisolated private static func validate(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard Int64(values.fileSize ?? 0) == expectedByteCount else {
            throw ModelDownloadError.invalidSize
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256 else {
            throw ModelDownloadError.invalidChecksum
        }
    }

    nonisolated private static func install(_ staging: URL, at destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
    }
}

private enum ModelDownloadError: LocalizedError {
    case invalidResponse
    case invalidSize
    case invalidChecksum

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The model server did not return a valid download. Try again later."
        case .invalidSize, .invalidChecksum:
            return "The downloaded model could not be verified. Your existing model was kept safe. Try again."
        }
    }
}
