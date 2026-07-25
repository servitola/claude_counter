import Foundation
import Testing
@testable import ClaudeCounter

struct CodexAuthStoreTests {
    /// Write `contents` to a unique temp auth.json and return a store over it.
    private func store(contents: String) throws -> (CodexAuthStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("auth.json")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return (CodexAuthStore(path: file), dir)
    }

    @Test func reads_token_and_account_id() throws {
        let (store, dir) = try store(contents: """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "abc.def.ghi",
            "refresh_token": "refresh-xyz",
            "account_id": "acct-1234"
          },
          "last_refresh": "2026-07-20T00:00:00Z"
        }
        """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let auth = try #require(store.read())
        #expect(auth.accessToken == "abc.def.ghi")
        #expect(auth.accountId == "acct-1234")
        #expect(auth.refreshToken == "refresh-xyz")
    }

    @Test func missing_file_returns_nil() {
        let store = CodexAuthStore(
            path: FileManager.default.temporaryDirectory
                .appendingPathComponent("does-not-exist-\(UUID().uuidString).json")
        )
        #expect(store.read() == nil)
    }

    @Test func malformed_json_returns_nil() throws {
        let (store, dir) = try store(contents: "{ not json")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(store.read() == nil)
    }

    @Test func empty_token_returns_nil() throws {
        let (store, dir) = try store(contents: """
        { "tokens": { "access_token": "", "account_id": "acct" } }
        """)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(store.read() == nil)
    }

    /// When `tokens.account_id` is absent, fall back to the JWT claim
    /// `https://api.openai.com/auth → chatgpt_account_id`.
    @Test func account_id_falls_back_to_jwt_claim() throws {
        let header = base64URL(#"{"alg":"none"}"#)
        let payload =
            base64URL(#"{"https://api.openai.com/auth":{"chatgpt_account_id":"jwt-acct-99"}}"#)
        let jwt = "\(header).\(payload).sig"

        let (store, dir) = try store(contents: """
        { "tokens": { "access_token": "\(jwt)" } }
        """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let auth = try #require(store.read())
        #expect(auth.accountId == "jwt-acct-99")
    }

    private func base64URL(_ json: String) -> String {
        Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
