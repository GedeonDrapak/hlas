import Foundation
import HlasCore
import Testing

@Suite("Transcription errors")
struct TranscriptionNetworkErrorTests {
    @Test("Explains rejected keys")
    func rejectedKey() {
        let error = TranscriptionNetworkError.http(statusCode: 401, provider: "OpenAI")
        #expect(error.errorDescription == "Your OpenAI API key was rejected. Check it in Settings.")
    }

    @Test("Explains exhausted credit")
    func exhaustedCredit() {
        let error = TranscriptionNetworkError.http(statusCode: 402, provider: "Soniox")
        #expect(error.errorDescription == "Your Soniox account is out of credit. Top it up or choose another engine in Settings.")
    }

    @Test("Explains rate limits")
    func rateLimit() {
        let error = TranscriptionNetworkError.http(statusCode: 429, provider: "Groq")
        #expect(error.errorDescription == "Groq has reached a limit. Try again in a moment.")
    }

    @Test("Maps offline URL errors")
    func offline() {
        let error = TranscriptionNetworkError.from(
            URLError(.notConnectedToInternet), provider: "OpenAI"
        )
        #expect(error.errorDescription == "No internet connection. Choose Local in Settings or reconnect.")
    }
}
