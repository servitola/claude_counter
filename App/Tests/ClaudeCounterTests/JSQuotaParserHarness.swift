import Foundation
import JavaScriptCore
@testable import ClaudeCounter

/// Drives the production `QuotaScraper.parserLibraryJS` from unit tests
/// via `JSContext`. Same JS string the scraper ships, run without
/// WebKit and without a DOM — we feed it the pre-aggregated `allText`
/// and `barPercents` directly.
///
/// `nowMs` is parameterised so the absolute-time branch ("Resets at
/// 9:30 PM") is deterministic.
enum JSQuotaParserHarness {
    static func parse(
        text: String,
        barPercents: [Double] = [],
        now: Date = Date(timeIntervalSince1970: 1_700_000_000)
    )
        -> QuotaPayload?
    {
        guard let context = JSContext() else { return nil }
        context.evaluateScript(QuotaScraper.parserLibraryJS)
        guard
            let parser = context.objectForKeyedSubscript("parseQuotaFromText"),
            !parser.isUndefined
        else { return nil }
        let nowMs = now.timeIntervalSince1970 * 1000
        let result = parser.call(withArguments: [text, barPercents, nowMs])
        guard let dict = result?.toDictionary() else { return nil }
        return QuotaPayload(jsResult: dict)
    }
}
