import HlasCore
import Testing

@Suite("Text clean-up")
struct TextCleanupTests {
    let all = TextCleanupOptions(removeFillers: true, spokenFormatting: true, spokenSymbols: true)

    @Test("Removes hesitation fillers and fixes the sentence start", arguments: [
        ("Ehm, ahoj Petře, eee, posílám ti to.", "Ahoj Petře, posílám ti to."),
        ("Dobře. Ehm, takže jdeme.", "Dobře. Takže jdeme."),
        ("Ahoj ehm Petře", "Ahoj Petře"),
        ("Posílám to, ehm.", "Posílám to."),
        ("Jablka, ehm, hrušky", "Jablka, hrušky"),
        ("Um, I think, uh, it works.", "I think, it works."),
        ("Ehm.", ""),
    ])
    func fillers(input: String, expected: String) {
        #expect(TextCleanup.apply(input, options: .init()) == expected)
    }

    @Test("Keeps words that only look like fillers", arguments: [
        "Hemingway a Emma jedou do Ostravy.",
        "Mhm, to beru.",
        "Je to jako sen.",
        "iPhone je tady.",
    ])
    func keepsWords(input: String) {
        #expect(TextCleanup.apply(input, options: .init()) == input)
    }

    @Test("Turns standalone line and paragraph commands into breaks", arguments: [
        ("Ahoj Petře, nový odstavec, posílám nabídku.", "Ahoj Petře,\n\nPosílám nabídku."),
        ("Nakoupit. Nový řádek. Mléko. Nový řádek. Chleba.", "Nakoupit.\nMléko.\nChleba."),
        ("First point. New paragraph. Second point.", "First point.\n\nSecond point."),
        ("Konec textu, nový řádek.", "Konec textu,"),
    ])
    func formatting(input: String, expected: String) {
        #expect(TextCleanup.apply(input, options: .init()) == expected)
    }

    @Test("Leaves the command words inside a sentence alone")
    func formattingInSentence() {
        let text = "Přidej nový řádek do tabulky a pošli to."
        #expect(TextCleanup.apply(text, options: .init()) == text)
    }

    @Test("Spoken symbols build addresses and punctuation", arguments: [
        ("Napiš na gedeon zavináč gmail tečka com.", "Napiš na gedeon@gmail.com."),
        ("Soubor final podtržítko v2", "Soubor final_v2"),
        ("Je to hotové otazník", "Je to hotové?"),
        ("Cesta je projects lomítko hlas", "Cesta je projects/hlas"),
        ("Pozor vykřičník", "Pozor!"),
        ("Tag mřížka hlas", "Tag #hlas"),
    ])
    func symbols(input: String, expected: String) {
        #expect(TextCleanup.apply(input, options: all) == expected)
    }

    @Test("Spoken symbols stay off unless enabled")
    func symbolsOff() {
        let text = "Je to hotové otazník"
        #expect(TextCleanup.apply(text, options: .init()) == text)
    }

    @Test("Vocabulary sounds-like variants map to the term")
    func vocabulary() {
        let rules = Vocabulary.rules(["Seedance": Vocabulary.parse("sídens, sí dens, sídens"), "Higgsfield": ["higs field"]])
        #expect(rules.count == 3)
        #expect(TextReplacement.apply(rules, to: "Pustím to přes Sí dens a higs field.") == "Pustím to přes Seedance a Higgsfield.")
    }
}
