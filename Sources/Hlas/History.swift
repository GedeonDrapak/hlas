import Foundation
import HlasCore
import Combine

@MainActor final class History: ObservableObject {
    static let shared = History()
    typealias Entry = TranscriptEntry
    @Published private(set) var entries: [Entry] = []
    private let storage = DispatchQueue(label: "hlas.history", qos: .utility)
    private var clearGeneration = 0
    private var observer: AnyCancellable?
    private var expiryTimer: Timer?
    private let url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Hlas/history.json")

    private init() {
        let url = url
        storage.async {
            let saved = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
            DispatchQueue.main.async {
                guard self.clearGeneration == 0 else { return }
                do {
                    let current = Set(self.entries.map(\.id))
                    self.entries += saved.filter { !current.contains($0.id) }
                    self.pruneAndSave()
                }
            }
        }
        observer = Settings.shared.$historyRetentionDays.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.pruneAndSave() }
        }
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneAndSave() }
        }
    }
    func add(_ text: String, raw: String? = nil, mode: OutputMode = .transcript,
             engine: String? = nil, duration: Double? = nil) {
        guard Settings.shared.historyEnabled else { return }
        entries.insert(Entry(text: text, rawText: raw, mode: mode, engine: engine, duration: duration), at: 0)
        pruneAndSave()
    }
    func update(_ id: UUID, text: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        if entries[index].rawText == nil { entries[index].rawText = entries[index].text }
        entries[index].text = text
        pruneAndSave()
    }
    func pruneAndSave() {
        let days = Settings.shared.historyRetentionDays
        if days > 0 { entries.removeAll { $0.date < Date().addingTimeInterval(-Double(days) * 86400) } }
        entries.sort { $0.date > $1.date }
        if entries.count > 50 { entries = Array(entries.prefix(50)) }
        let snapshot = entries; let url = url
        storage.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch { Log.write("history write failed") }
        }
    }
    func clear() {
        clearGeneration += 1
        entries = []
        let url = url
        storage.async { try? FileManager.default.removeItem(at: url) }
    }
}
