import HlasCore
import Testing

@Suite("Hallucination filter")
struct HallucinationsTests {
    @Test(
        "Drops dominant stock phrases",
        arguments: [
            "Titulky vytvořil www.zelenka.cz",
            "Thanks for watching",
            "Subtitles by Amara.org",
        ]
    )
    func dropsDominantPhrase(_ text: String) {
        #expect(Hallucinations.filter(text).isEmpty)
    }

    @Test("Preserves real dictation that mentions a blocked phrase")
    func preservesRealSentence() {
        let text = "V prezentaci vysvětlím, proč fráze thanks for watching často působí neosobně a jak ji nahradit."
        #expect(Hallucinations.filter(text) == text)
    }
}
