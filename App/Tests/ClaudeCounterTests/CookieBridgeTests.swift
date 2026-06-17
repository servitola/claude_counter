import Foundation
import Testing
import WebKit
@testable import ClaudeCounter

// MARK: - CookieBridgeTests

@MainActor
struct CookieBridgeTests {
    /// A claude.ai response URL used for both seeding and write-back.
    private static let claudeURL: URL = {
        guard let url = URL(string: "https://claude.ai/api/organizations") else {
            preconditionFailure("Static URL string is invalid")
        }
        return url
    }()

    /// Builds a bridge over an isolated, non-persistent store so tests never
    /// touch the shared `.default()` cookie jar. `log` captures every emitted
    /// log line for the Decision-6 guard test.
    private func makeBridge(
        log: @escaping @MainActor (String) -> Void = { _ in }
    )
        -> (CookieBridge, WKHTTPCookieStore)
    {
        let store = WKWebsiteDataStore.nonPersistent()
        let bridge = CookieBridge(store: store, log: log)
        return (bridge, store.httpCookieStore)
    }

    private func cookie(
        domain: String, name: String, value: String, path: String = "/"
    )
        -> HTTPCookie
    {
        guard
            let cookie = HTTPCookie(properties: [
                .domain: domain,
                .path: path,
                .name: name,
                .value: value
            ])
        else {
            preconditionFailure("Failed to build test cookie")
        }
        return cookie
    }

    private func seed(_ cookies: [HTTPCookie], into store: WKHTTPCookieStore) async {
        for cookie in cookies {
            await store.setCookie(cookie)
        }
    }

    @Test func readReturnsOnlyClaudeAiCookies() async {
        let (bridge, store) = makeBridge()
        await seed([
            cookie(domain: "claude.ai", name: "sessionKey", value: "sk-claude"),
            cookie(domain: ".claude.ai", name: "cf_clearance", value: "cf-claude"),
            cookie(domain: "example.com", name: "foreign", value: "nope"),
            cookie(domain: "notclaude.ai", name: "lookalike", value: "nope2"),
            cookie(domain: "claude.ai.evil.com", name: "evil", value: "nope3")
        ], into: store)

        let cookies = await bridge.read()
        let names = Set(cookies.map(\.name))
        #expect(names == ["sessionKey", "cf_clearance"])

        let header = await bridge.cookieHeader()
        #expect(header.contains("sessionKey=sk-claude"))
        #expect(header.contains("cf_clearance=cf-claude"))
        #expect(!header.contains("foreign"))
        #expect(!header.contains("nope"))
        #expect(!header.contains("lookalike"))
        #expect(!header.contains("evil"))
    }

    @Test func readEmptyStoreReturnsEmpty() async {
        let (bridge, _) = makeBridge()
        let cookies = await bridge.read()
        #expect(cookies.isEmpty)
        let header = await bridge.cookieHeader()
        #expect(header.isEmpty)
    }

    @Test func writeBackInsertsSetCookieIntoStore() async {
        let (bridge, store) = makeBridge()

        await bridge.writeBack(
            setCookieHeaders: ["__cf_bm=rotated-bm; Path=/; Domain=claude.ai"],
            responseURL: Self.claudeURL
        )

        let cookies = await store.allCookies()
        let match = cookies.first { $0.name == "__cf_bm" }
        #expect(match?.value == "rotated-bm")
    }

    @Test func writeBackSkipsNonClaudeCookies() async {
        let (bridge, store) = makeBridge()
        // Response URL is claude.ai, but the Set-Cookie carries an explicit
        // foreign Domain attribute. Foundation parses it for a claude.ai URL,
        // so the cookie survives parsing and our own isClaudeScoped guard is
        // what must drop it (defense in depth).
        await bridge.writeBack(
            setCookieHeaders: ["foreign=nope; Path=/; Domain=example.com"],
            responseURL: Self.claudeURL
        )

        let cookies = await store.allCookies()
        #expect(cookies.allSatisfy { $0.name != "foreign" })
    }

    @Test func writeBackSkipsUnparseableButKeepsValidEntry() async {
        let (bridge, store) = makeBridge()
        // One garbage field, one valid claude.ai cookie. Parsing each field
        // individually must skip the garbage and still write the valid one.
        await bridge.writeBack(
            setCookieHeaders: [
                "=; =; ===",
                "sessionKey=rotated-sk; Path=/; Domain=claude.ai"
            ],
            responseURL: Self.claudeURL
        )

        let cookies = await store.allCookies()
        let match = cookies.first { $0.name == "sessionKey" }
        #expect(match?.value == "rotated-sk")
    }

    @Test func writeBackParsesEachFieldWithCommaInExpires() async {
        let (bridge, store) = makeBridge()
        // Two rotating cookies, each with an Expires attribute whose value
        // contains a comma (RFC 6265 date format). Comma-joining the fields
        // before parsing would mis-split and silently drop one cookie; parsing
        // each field individually must keep both.
        await bridge.writeBack(
            setCookieHeaders: [
                "__cf_bm=rotated-bm; Path=/; Domain=claude.ai; "
                    + "Expires=Wed, 09 Jun 2027 10:18:14 GMT",
                "sessionKey=rotated-sk; Path=/; Domain=claude.ai; "
                    + "Expires=Wed, 09 Jun 2027 10:18:14 GMT"
            ],
            responseURL: Self.claudeURL
        )

        let cookies = await store.allCookies()
        let names = Set(cookies.map(\.name))
        #expect(names.contains("__cf_bm"))
        #expect(names.contains("sessionKey"))
        #expect(cookies.first { $0.name == "__cf_bm" }?.value == "rotated-bm")
        #expect(cookies.first { $0.name == "sessionKey" }?.value == "rotated-sk")
    }

    @Test func noCookieValueAppearsInCapturedLogSink() async {
        let sink = LogSink()
        let (bridge, store) = makeBridge { line in sink.append(line) }

        let sentinelName = "sentinelCookieName"
        let sentinelValue = "S3CR3T-sentinel-value"

        await seed([
            cookie(domain: "claude.ai", name: sentinelName, value: sentinelValue)
        ], into: store)

        _ = await bridge.read()
        _ = await bridge.cookieHeader()
        await bridge.writeBack(
            setCookieHeaders: [
                "\(sentinelName)=\(sentinelValue); Path=/; Domain=claude.ai"
            ],
            responseURL: Self.claudeURL
        )

        let lines = sink.snapshot()
        // The seam must have been exercised; otherwise the assertion is vacuous.
        #expect(!lines.isEmpty)
        for line in lines {
            #expect(!line.contains(sentinelName))
            #expect(!line.contains(sentinelValue))
        }
    }
}

// MARK: - LogSink

/// MainActor-isolated collector for emitted log strings.
@MainActor
private final class LogSink {
    private var lines: [String] = []
    func append(_ line: String) {
        lines.append(line)
    }

    func snapshot() -> [String] {
        lines
    }
}
