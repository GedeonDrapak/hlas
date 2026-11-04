import Foundation

/// Local, offline clean-up of a raw transcript. Runs before Smart text and
/// before replacements, in both output modes.
public struct TextCleanupOptions: Equatable, Sendable {
    public var removeFillers: Bool
    public var spokenFormatting: Bool
    public var spokenSymbols: Bool
    public init(removeFillers: Bool = true, spokenFormatting: Bool = true, spokenSymbols: Bool = false) {
        self.removeFillers = removeFillers
        self.spokenFormatting = spokenFormatting
        self.spokenSymbols = spokenSymbols
    }
}

public enum TextCleanup {
    /// Hesitation sounds only. Words that can carry meaning ("jako", "like",
    /// "mhm" = yes) are left to Smart text.
    public static let fillers = ["e{2,}", "é+", "eh+", "ehm+", "hm+", "mm+", "uh+", "uhm+", "um+", "erm+"]

    public static let lineCommands = ["nový řádek", "nová řádka", "další řádek", "new line", "newline"]
    public static let paragraphCommands = ["nový odstavec", "další odstavec", "new paragraph", "next paragraph"]

    enum Attach { case both, left, right }
    static let symbols: [(phrases: [String], symbol: String, attach: Attach)] = [
        (["zavináč", "at sign"], "@", .both),
        (["podtržítko", "underscore"], "_", .both),
        (["zpětné lomítko", "backslash"], "\\", .both),
        (["lomítko", "slash"], "/", .both),
        (["spojovník", "hyphen"], "-", .both),
        (["mřížka", "hashtag"], "#", .right),
        (["otevřít závorku", "levá závorka", "open parenthesis"], "(", .right),
        (["zavřít závorku", "pravá závorka", "close parenthesis"], ")", .left),
        (["dvojtečka", "colon"], ":", .left),
        (["středník", "semicolon"], ";", .left),
        (["otazník", "question mark"], "?", .left),
        (["vykřičník", "exclamation mark"], "!", .left),
        (["čárka", "comma"], ",", .left),
    ]
    static let topLevelDomains = ["com", "cz", "sk", "org", "net", "io", "ai", "eu", "de", "dev", "app", "co", "uk"]

    /// Marks a spot whose next word starts a sentence or line. Only lowercase
    /// words are capitalized there, so "iPhone" survives.
    static let capitalMark = "\u{1}"

    /// Returns "" when nothing but fillers was said.
    public static func apply(_ text: String, options: TextCleanupOptions) -> String {
        var result = text
        if options.removeFillers { result = removeFillers(result) }
        if options.spokenFormatting { result = applySpokenFormatting(result) }
        if options.spokenSymbols { result = applySpokenSymbols(result) }
        guard result != text else { return text }
        result = tidy(result)
        return result.contains(where: { $0.isLetter || $0.isNumber }) ? result : ""
    }

    // MARK: Fillers

    public static func removeFillers(_ text: String) -> String {
        let pattern = "([,;]\\s*)?(?<![\\p{L}\\p{N}])(?:" + fillers.joined(separator: "|")
            + ")(?![\\p{L}\\p{N}])(\\s*[,…]+)?(\\s*[.!?])?"
        return replace(pattern, in: text) { match, ns in
            let pre = match.range(at: 1).location != NSNotFound
            let post = match.range(at: 2).location != NSNotFound
            let end = match.range(at: 3)
            if end.location != NSNotFound {
                return ns.substring(with: end).trimmingCharacters(in: .whitespaces)
            }
            // A capitalized filler opened a sentence: the next word opens it now.
            let filler = ns.substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: ",; "))
            let startsSentence = filler.first?.isUppercase == true
            return (pre && post ? ", " : " ") + (startsSentence ? capitalMark : "")
        }
    }

    // MARK: Spoken formatting

    /// "nový řádek" / "nový odstavec" become line breaks only when they stand
    /// apart from the sentence (punctuation or an edge on at least one side),
    /// so "přidej nový řádek do tabulky" stays content.
    public static func applySpokenFormatting(_ text: String) -> String {
        var result = text
        for (phrases, breakText) in [(paragraphCommands, "\n\n"), (lineCommands, "\n")] {
            let alternatives = phrases.map(phrasePattern).joined(separator: "|")
            let pattern = "(^|[.,;:!?\\n])?[ \\t]*(?<![\\p{L}\\p{N}])(?:" + alternatives
                + ")(?![\\p{L}\\p{N}])([ \\t]*[.,;:!?]+)?[ \\t]*($)?"
            result = replace(pattern, in: result, options: [.caseInsensitive, .anchorsMatchLines]) { match, ns in
                let before = match.range(at: 1)
                let standsApart = before.location != NSNotFound
                    || match.range(at: 2).location != NSNotFound
                    || match.range(at: 3).location != NSNotFound
                guard standsApart else { return nil }
                let kept = before.location != NSNotFound ? ns.substring(with: before) : ""
                return (kept == "\n" ? "" : kept) + breakText + capitalMark
            }
        }
        return result
    }

    // MARK: Spoken symbols

    public static func applySpokenSymbols(_ text: String) -> String {
        var result = text
        for entry in symbols {
            let alternatives = entry.phrases.map(phrasePattern).joined(separator: "|")
            let word = "(?<![\\p{L}\\p{N}])(?:" + alternatives + ")(?![\\p{L}\\p{N}])"
            let pattern: String
            switch entry.attach {
            case .both: pattern = "[ \\t,]*" + word + "[ \\t]*[,.]?[ \\t]*"
            case .left: pattern = "[ \\t,]*" + word + "[.,]?"
            case .right: pattern = word + "[ \\t,]*"
            }
            result = replace(pattern, in: result) { _, _ in entry.symbol }
        }
        return joinDomains(result)
    }

    /// "gedeon zavináč gmail tečka com" -> "gedeon@gmail.com": "tečka"/"dot"
    /// joins only after an address-like token or before a known domain ending.
    static func joinDomains(_ text: String) -> String {
        let tlds = topLevelDomains.joined(separator: "|")
        let pattern = "(?<=[\\p{L}\\p{N}])[ \\t]+(?:tečka|dot)[ \\t]+(?=(?:" + tlds + ")(?![\\p{L}\\p{N}])|[\\p{L}\\p{N}]+[@/])"
        var result = replace(pattern, in: text) { _, _ in "." }
        let afterAddress = "(?<=[@/][\\p{L}\\p{N}._-]{1,63})[ \\t]+(?:tečka|dot)[ \\t]+(?=[\\p{L}\\p{N}])"
        result = replace(afterAddress, in: result) { _, _ in "." }
        return result
    }

    // MARK: Helpers

    /// Capitals where a sentence or line now starts, then whitespace and
    /// punctuation left behind by removals.
    static func tidy(_ text: String) -> String {
        var s = replace(capitalMark + "+([\\s]*)(\\p{Ll}[\\p{Ll}\\p{N}'-]*)(?![\\p{L}])", in: text,
                        options: []) { match, ns in
            let word = ns.substring(with: match.range(at: 2))
            return ns.substring(with: match.range(at: 1)) + word.prefix(1).uppercased() + word.dropFirst()
        }
        s = s.replacingOccurrences(of: capitalMark, with: "")
        s = replace("[ \\t]{2,}", in: s) { _, _ in " " }
        s = replace("[ \\t]+(?=[,.;:!?…)])", in: s) { _, _ in "" }
        s = replace("(?<=\\()[ \\t]+", in: s) { _, _ in "" }
        s = replace("[ \\t]+\\n", in: s) { _, _ in "\n" }
        s = replace("\\n[ \\t]+", in: s) { _, _ in "\n" }
        s = replace("^[ \\t,;]+", in: s, options: [.anchorsMatchLines]) { _, _ in "" }
        s = replace("\\n{3,}", in: s) { _, _ in "\n\n" }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func phrasePattern(_ phrase: String) -> String {
        phrase.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[ \\t]+")
    }

    /// Replaces from the end so earlier ranges stay valid. A nil replacement
    /// keeps the match.
    static func replace(_ pattern: String, in text: String,
                        options: NSRegularExpression.Options = [.caseInsensitive],
                        with make: (NSTextCheckingResult, NSString) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let ns = text as NSString
        let result = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard match.range.length > 0, let replacement = make(match, ns) else { continue }
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return result as String
    }
}

/// Vocabulary terms with how the engine tends to mishear them
/// ("Seedance" sounds like "sídens, sí dens").
public enum Vocabulary {
    public static func rules(_ soundsLike: [String: [String]]) -> [TextReplacement] {
        soundsLike
            .flatMap { term, variants in variants.map { TextReplacement(from: $0, to: term) } }
            .filter { !$0.from.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.from.count > $1.from.count }
    }

    /// "sídens, sí dens" -> ["sídens", "sí dens"]
    public static func parse(_ variants: String) -> [String] {
        var seen = Set<String>()
        return variants.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
