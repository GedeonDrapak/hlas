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
    static var modelURL: URL { modelDir.appendingPathComponent(modelName) }
    static var modelExists: Bool { FileManager.default.fileExists(atPath: modelURL.path) }

    func transcribe(samples: [Float], language: String?) async throws -> String {
        guard Self.modelExists else {
            throw NSError(domain: "Hlas", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Model not downloaded — open Settings"
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

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
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

        let promptHolder = prompt.map { strdup($0) }
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

    private var session: URLSession!

    func start() {
        guard !downloading else { return }
        downloading = true
        error = nil
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        session.downloadTask(with: Self.remote).resume()
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let p = Double(totalBytesWritten) / Double(max(1, totalBytesExpectedToWrite))
        Task { @MainActor in self.progress = p }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        let dest = LocalWhisper.modelURL
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            Task { @MainActor in self.downloading = false; self.progress = 1 }
        } catch {
            Task { @MainActor in self.downloading = false; self.error = error.localizedDescription }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            Task { @MainActor in self.downloading = false; self.error = error.localizedDescription }
        }
    }
}
