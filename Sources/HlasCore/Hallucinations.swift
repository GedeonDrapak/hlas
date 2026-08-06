public enum Hallucinations {
    private static let patterns: [String] = [
        "titulky vytvořil",
        "titulky vytvorila",
        "překlad a titulky",
        "www.zelenka.cz",
        "subtitles by",
        "subs by",
        "thanks for watching",
        "thank you for watching",
        "please subscribe",
        "amara.org",
        "www.youtube.com",
    ]

    public static func filter(_ text: String) -> String {
        let lower = text.lowercased()
        for pattern in patterns where lower.contains(pattern) {
            if Double(pattern.count) / Double(max(1, lower.count)) > 0.3 {
                return ""
            }
        }
        return text
    }
}
