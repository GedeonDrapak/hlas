import Foundation

/// Whisper hallucinates subtitle credits and stock phrases on silence or
/// noise-only audio. If the entire output is one of these, drop it.
enum Hallucinations {
    private static let patterns: [String] = [
        // Czech subtitle-credit hallucinations
        "titulky vytvořil",
        "titulky vytvorila",
        "překlad a titulky",
        "www.zelenka.cz",
        // English
        "subtitles by",
        "subs by",
        "thanks for watching",
        "thank you for watching",
        "please subscribe",
        // Generic
        "amara.org",
        "www.youtube.com",
    ]

    static func filter(_ text: String) -> String {
        let lower = text.lowercased()
        for pattern in patterns where lower.contains(pattern) {
            // Only drop when the hallucination dominates the output -
            // a real dictation that merely mentions YouTube must survive.
            if Double(pattern.count) / Double(max(1, lower.count)) > 0.3 {
                Log.write("dropped hallucination: \"\(text.prefix(60))\"")
                return ""
            }
        }
        return text
    }
}
