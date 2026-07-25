import Foundation

// MARK: - CodexAuth

/// Credentials read from the Codex CLI's `~/.codex/auth.json` (written by
/// `codex login`). We never persist or log these tokens ourselves — this is a
/// read-only view over the file the Codex CLI already maintains and refreshes.
struct CodexAuth: Equatable {
    let accessToken: String
    let accountId: String?
    let refreshToken: String?
}

// MARK: - CodexAuthStore

/// Locates and parses `~/.codex/auth.json` (honoring `$CODEX_HOME`). The file
/// path is injectable so tests read a fixture instead of the real home
/// directory. Unlike the Claude path there is no login UI here: the user logs
/// in once via the `codex` CLI and this reads the resulting token.
struct CodexAuthStore: Sendable {
    private let path: URL

    /// - Parameter path: explicit `auth.json` location (tests). When nil,
    ///   resolves `$CODEX_HOME/auth.json`, defaulting to `~/.codex/auth.json`.
    init(path: URL? = nil) {
        if let path {
            self.path = path
        } else if let home = ProcessInfo.processInfo.environment["CODEX_HOME"] {
            let dir = URL(fileURLWithPath: Self.expandTilde(home), isDirectory: true)
            self.path = dir.appendingPathComponent("auth.json")
        } else {
            self.path = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("auth.json")
        }
    }

    /// The parsed auth, or `nil` when the file is absent/unreadable/malformed or
    /// carries no access token (i.e. Codex isn't logged in) — the caller then
    /// surfaces a "log in via codex CLI" state.
    func read() -> CodexAuth? {
        guard
            let data = try? Data(contentsOf: path),
            let root = try? JSONDecoder().decode(CodexAuthFile.self, from: data),
            let token = root.tokens?.accessToken, !token.isEmpty
        else {
            return nil
        }
        let accountId = root.tokens?.accountId ?? Self.accountId(fromJWT: token)
        return CodexAuth(
            accessToken: token,
            accountId: accountId,
            refreshToken: root.tokens?.refreshToken
        )
    }

    /// Expand a leading `~` against the current user's home directory without
    /// bridging to `NSString`.
    private static func expandTilde(_ value: String) -> String {
        guard value.hasPrefix("~") else { return value }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + value.dropFirst()
    }

    // MARK: - JWT fallback

    /// Extract the ChatGPT account id from the access-token JWT claims when
    /// `tokens.account_id` is absent. OpenAI nests it under the auth namespace
    /// claim `https://api.openai.com/auth → chatgpt_account_id`.
    static func accountId(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard
            parts.count == 3,
            let payload = base64URLDecode(String(parts[1])),
            let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else {
            return nil
        }
        if
            let auth = obj["https://api.openai.com/auth"] as? [String: Any],
            let id = auth["chatgpt_account_id"] as? String
        {
            return id
        }
        return obj["chatgpt_account_id"] as? String ?? obj["account_id"] as? String
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var str = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while !str.count.isMultiple(of: 4) {
            str += "="
        }
        return Data(base64Encoded: str)
    }
}

// MARK: - CodexAuthFile

/// Decodable view of the parts of `auth.json` we read. Kept at file scope (not
/// nested) to satisfy the 2-level nesting limit.
private struct CodexAuthFile: Decodable {
    let tokens: Tokens?

    struct Tokens: Decodable {
        let accessToken: String?
        let accountId: String?
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountId = "account_id"
            case refreshToken = "refresh_token"
        }
    }
}
