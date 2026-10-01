import Foundation
import Testing
@testable import ClaudeCounter

struct OffHostRedirectGuardTests {
    private let codexGuard = OffHostRedirectGuard(
        host: "chatgpt.com", sensitiveHeaders: ["Authorization", CodexUsageClient.accountHeader]
    )

    private func request(to url: String) throws -> URLRequest {
        var request = try URLRequest(url: #require(URL(string: url)))
        request.setValue("Bearer token", forHTTPHeaderField: "Authorization")
        request.setValue("acct-1", forHTTPHeaderField: CodexUsageClient.accountHeader)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    @Test func off_host_redirect_drops_credentials_only() throws {
        let guarded = try codexGuard.guarded(request(to: "https://evil.example/usage"))

        #expect(guarded.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(guarded.value(forHTTPHeaderField: CodexUsageClient.accountHeader) == nil)
        #expect(guarded.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func on_host_and_subdomain_redirects_keep_credentials() throws {
        for url in ["https://chatgpt.com/backend-api/x", "https://API.chatgpt.com/y"] {
            let guarded = try codexGuard.guarded(request(to: url))
            #expect(guarded.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        }
    }

    @Test func lookalike_host_is_off_host() throws {
        let guarded = try codexGuard.guarded(request(to: "https://notchatgpt.com/usage"))

        #expect(guarded.value(forHTTPHeaderField: "Authorization") == nil)
    }
}
