import AppKit

enum LegalDocuments {
    static func open(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else {
            Log.write("missing legal document: \(name)")
            return
        }
        NSWorkspace.shared.open(url)
    }
}
