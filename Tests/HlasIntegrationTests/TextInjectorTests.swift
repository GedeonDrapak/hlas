import AppKit
import Testing
@testable import Hlas

@Suite("Automatic paste regression", .serialized)
@MainActor struct TextInjectorTests {
    @Test func acceptsApplicationWithoutAXField() {
        let target = TextInjector.Target(pid: 123)
        #expect(target.matches(foregroundPID: 123))
        #expect(!target.matches(foregroundPID: 456))
        #expect(!target.matches(foregroundPID: nil))
    }

    @Test func pastesAndRestoresLargeRichClipboard() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let original = Data(repeating: 0xA7, count: 2_000_000)
        board.setData(original, forType: .png)
        var received: String?
        let posted = TextInjector.insert("Přímý přepis do pole.", pasteboard: board) {
            received = board.string(forType: .string)
        }
        #expect(posted)
        #expect(received == "Přímý přepis do pole.")
        try await Task.sleep(for: .milliseconds(600))
        #expect(board.data(forType: .png) == original)
    }

    @Test func neverOverwritesANewerUserCopy() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Original clipboard", forType: .string)
        #expect(TextInjector.insert("Dictation", pasteboard: board, postPaste: {}))
        board.clearContents()
        board.setString("User copied this while dictating", forType: .string)
        try await Task.sleep(for: .milliseconds(600))
        #expect(board.string(forType: .string) == "User copied this while dictating")
    }
}
