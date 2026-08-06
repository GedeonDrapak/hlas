import Foundation

/// Last N transcripts, stored locally in Application Support. Nothing leaves the machine.
@MainActor
final class History: ObservableObject {
    static let shared = History()
    private static let maxEntries = 50

    struct Entry: Codable, Identifiable {
        let id: UUID
        let text: String
        let date: Date
    }

    @Published private(set) var entries: [Entry] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hlas", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func add(_ text: String) {
        entries.insert(Entry(id: UUID(), text: text, date: Date()), at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url)
        }
    }
}
