import CryptoKit
import Foundation

public enum ModelFileValidationError: LocalizedError, Equatable {
    case invalidSize
    case invalidChecksum
    case unreadable

    public var errorDescription: String? {
        "The downloaded model could not be verified. Your existing model was kept safe. Try again."
    }
}

public enum ModelFileValidator {
    public static func validate(
        _ url: URL,
        expectedByteCount: Int64,
        expectedSHA256: String
    ) throws {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard Int64(values.fileSize ?? 0) == expectedByteCount else {
                throw ModelFileValidationError.invalidSize
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
            guard digest == expectedSHA256.lowercased() else {
                throw ModelFileValidationError.invalidChecksum
            }
        } catch let error as ModelFileValidationError {
            throw error
        } catch {
            throw ModelFileValidationError.unreadable
        }
    }
}
