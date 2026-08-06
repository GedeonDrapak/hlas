import Foundation

/// Tiny file logger - ~/Library/Application Support/Hlas/debug.log
/// (unified log proved unreliable for a bare SwiftPM app).
enum Log {
    private static let maxBytes: UInt64 = 1_000_000
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hlas", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let file = dir.appendingPathComponent("debug.log")
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "privacyLogV1") {
            try? FileManager.default.removeItem(at: file)
            defaults.set(true, forKey: "privacyLogV1")
        } else if FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        return file
    }()

    private static let queue = DispatchQueue(label: "hlas.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        queue.async {
            let line = "\(formatter.string(from: Date())) \(message)\n"
            rotateIfNeeded(adding: line.utf8.count)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                FileManager.default.createFile(
                    atPath: url.path,
                    contents: Data(line.utf8),
                    attributes: [.posixPermissions: 0o600]
                )
            }
        }
    }

    private static func rotateIfNeeded(adding bytes: Int) {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              UInt64(size + bytes) > maxBytes else { return }
        let previous = url.appendingPathExtension("old")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: url, to: previous)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: previous.path)
    }
}
