import Foundation
import Testing
import HlasCore
@testable import Hlas

private final class StubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let body = path == "/truncated"
            ? "{\"choices\":[{\"message\":{\"content\":\"partial\"},\"finish_reason\":\"length\"}]}"
            : "{\"choices\":[{\"message\":{\"content\":\"- Zavolat Petrovi.\\n- Poslat nabídku.\\n- Ověřit rozpočet.\"},\"finish_reason\":\"stop\"}]}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: path == "/unauthorized" ? 401 : 200,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Smart text network contract") struct SmartTextNetworkTests {
    private func run(_ path: String) async throws -> String {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let processor = SmartTextProcessor(endpoint: URL(string: "https://example.invalid/\(path)")!,
            apiKey: "synthetic-test-key", model: "test", provider: "OpenAI")
        return try await processor.process("Zavolat Petrovi poslat nabídku ověřit rozpočet", session: session)
    }
    @Test func completeResult() async throws { #expect(try await run("complete").contains("Petrovi")) }
    @Test func refusesTruncatedResult() async {
        do { _ = try await run("truncated"); Issue.record("Truncated result accepted") }
        catch { #expect(error is SmartTextError) }
    }
    @Test func exposesAuthenticationFailure() async {
        do { _ = try await run("unauthorized"); Issue.record("401 accepted") }
        catch { #expect(error.localizedDescription.contains("key was rejected")) }
    }
}
