import Foundation
import HlasCore
import Testing

@Suite("Model file validator")
struct ModelFileValidatorTests {
    private let hash = "0755253d4ecc7040f0f8f0fcede88dc18b8fba31f3451055a581c7e7c303ff28"

    @Test("Accepts a file with the expected size and SHA-256")
    func acceptsValidFile() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }

        try ModelFileValidator.validate(url, expectedByteCount: 4, expectedSHA256: hash)
    }

    @Test("Rejects an unexpected size")
    func rejectsSize() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ModelFileValidationError.invalidSize) {
            try ModelFileValidator.validate(url, expectedByteCount: 5, expectedSHA256: hash)
        }
    }

    @Test("Rejects an unexpected checksum")
    func rejectsChecksum() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ModelFileValidationError.invalidChecksum) {
            try ModelFileValidator.validate(
                url,
                expectedByteCount: 4,
                expectedSHA256: String(repeating: "0", count: 64)
            )
        }
    }

    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hlas-model-test-\(UUID().uuidString)")
        try Data("hlas".utf8).write(to: url, options: .atomic)
        return url
    }
}
