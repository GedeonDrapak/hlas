import AppKit

enum Credits {
    static let creatorURL = URL(string: "https://gedeondrapak.com")!
    static let studioURL = URL(string: "https://edenmakers.ai")!

    /// About panel credits with both links.
    static var aboutText: NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style
        ]
        let text = NSMutableAttributedString(string: "Private dictation, Czech first.\nMade by ", attributes: base)
        text.append(NSAttributedString(string: "Gedeon Drapák", attributes: base.merging([.link: creatorURL]) { $1 }))
        text.append(NSAttributedString(string: " and ", attributes: base))
        text.append(NSAttributedString(string: "Edenmakers", attributes: base.merging([.link: studioURL]) { $1 }))
        text.append(NSAttributedString(string: " in Prague.", attributes: base))
        return text
    }
}
