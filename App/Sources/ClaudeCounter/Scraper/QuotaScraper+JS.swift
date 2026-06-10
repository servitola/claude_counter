import Foundation

// JS regex literals inside a multiline string can't be wrapped without
// breaking semantics. SwiftLint's `blanket_disable_command` wants us to
// be explicit about file-scope disables, so we re-enable at EOF.
// swiftlint:disable line_length

extension QuotaScraper {
    /// Pure JS parser: takes a pre-aggregated `allText` plus a list of
    /// progressbar percentages and produces the same shape of object the
    /// scraper feeds into `QuotaPayload`.
    ///
    /// Pulled out as a standalone function so unit tests can run it via
    /// JavaScriptCore against fixture inputs — no WebKit, no DOM.
    /// Production calls it from `extractionJS` with values gathered from
    /// the live DOM.
    ///
    /// `nowMs` is injected so the absolute-time branch ("Resets at 9:30 PM")
    /// is deterministic in tests.
    nonisolated static let parserLibraryJS = """
    function parseQuotaFromText(allText, barPcts, nowMs) {
        var result = { found: false, raw: allText.substring(0, 4000) };

        var allMatches = [...allText.matchAll(/(\\d+\\.?\\d*)\\s*%\\s*used/gi)];
        result.percentages = allMatches.map(function(m) {
            return parseFloat(m[1]);
        });
        if (result.percentages.length > 0) { result.found = true; }

        // Reset-time patterns — claude.ai phrasings seen in the wild:
        //   "Resets in 2h 15m"
        //   "Resets in about 3 hours"
        //   "Resets at 9:30 PM" (absolute — handled separately)
        //   "1 hour and 23 minutes left"
        var resetPatterns = [
            /[Rr]eset[s]?\\s+in\\s+(?:about\\s+)?(\\d+)\\s*h(?:ou)?r?s?[,\\s]*(?:and\\s+)?(\\d+)\\s*m(?:in)?(?:ute)?s?/,
            /[Rr]eset[s]?\\s+in\\s+(?:about\\s+)?(\\d+)\\s*h(?:ou)?r?s?/,
            /[Rr]eset[s]?\\s+in\\s+(?:about\\s+)?(\\d+)\\s*m(?:in)?(?:ute)?s?/,
            /(\\d+)\\s*h(?:ou)?r?s?[,\\s]+(?:and\\s+)?(\\d+)\\s*m(?:in)?(?:ute)?s?\\s*(?:left|remaining)/i,
            /(\\d+)\\s*m(?:in)?(?:ute)?s?\\s*(?:left|remaining)/i,
            /(\\d+)\\s*h(?:ou)?r?s?\\s*(?:left|remaining)/i
        ];
        // Only search for reset time in the current-session section —
        // text that appears before the "Weekly" header. This prevents
        // the weekly reset time from being picked up when the current
        // session hasn't started ("Starts when a message is sent").
        // Also takes the earliest match by position so "Resets in 28 min"
        // beats "Resets in 10 hr 8 min" even if both were in the same section.
        var weeklyIdx = allText.search(/\\bWeekly\\b/i);
        var sessionText = weeklyIdx !== -1 ? allText.substring(0, weeklyIdx) : allText;
        var bestMatch = null;
        var bestIndex = Infinity;
        var bestPi = -1;
        for (var pi = 0; pi < resetPatterns.length; pi++) {
            var m = resetPatterns[pi].exec(sessionText);
            if (m !== null && m.index < bestIndex) {
                bestIndex = m.index;
                bestMatch = m;
                bestPi = pi;
            }
        }
        if (bestMatch !== null) {
            if (bestPi === 0 || bestPi === 3) {
                result.resetMinutes =
                    parseInt(bestMatch[1] || '0') * 60 + parseInt(bestMatch[2] || '0');
            } else if (bestPi === 1 || bestPi === 5) {
                result.resetMinutes = parseInt(bestMatch[1]) * 60;
            } else {
                result.resetMinutes = parseInt(bestMatch[1]);
            }
            result.matchedPattern = bestPi;
            result.matchedText = bestMatch[0];
            result.found = true;
        }

        // Extract the weekly reset time — first "Resets in X" after the
        // "Weekly" header. Kept separate from the current-session reset so
        // both can be displayed independently in the menu bar.
        if (weeklyIdx !== -1) {
            var weeklyText = allText.substring(weeklyIdx);
            var wBest = null, wBestIdx = Infinity, wBestPi = -1;
            for (var wpi = 0; wpi < resetPatterns.length; wpi++) {
                var wm = resetPatterns[wpi].exec(weeklyText);
                if (wm !== null && wm.index < wBestIdx) {
                    wBestIdx = wm.index; wBest = wm; wBestPi = wpi;
                }
            }
            if (wBest !== null) {
                if (wBestPi === 0 || wBestPi === 3) {
                    result.weeklyResetMinutes =
                        parseInt(wBest[1] || '0') * 60 + parseInt(wBest[2] || '0');
                } else if (wBestPi === 1 || wBestPi === 5) {
                    result.weeklyResetMinutes = parseInt(wBest[1]) * 60;
                } else {
                    result.weeklyResetMinutes = parseInt(wBest[1]);
                }
            }
        }

        // Absolute reset time: "Resets at 9:30 PM" → minutes-from-now.
        if (result.resetMinutes == null) {
            var atMatch = allText.match(
                /[Rr]eset[s]?\\s+at\\s+(\\d{1,2})[:\\.](\\d{2})\\s*(AM|PM|am|pm)?/
            );
            if (atMatch) {
                var hh = parseInt(atMatch[1]);
                var mm = parseInt(atMatch[2]);
                var ampm = (atMatch[3] || '').toUpperCase();
                if (ampm === 'PM' && hh < 12) { hh += 12; }
                if (ampm === 'AM' && hh === 12) { hh = 0; }
                var now = new Date(nowMs);
                var target = new Date(
                    now.getFullYear(), now.getMonth(), now.getDate(), hh, mm
                );
                if (target <= now) {
                    target = new Date(target.getTime() + 24 * 3600 * 1000);
                }
                result.resetMinutes = Math.round((target - now) / 60000);
                result.matchedPattern = 'absolute';
                result.matchedText = atMatch[0];
                result.found = true;
            }
        }

        if (barPcts && barPcts.length > 0) {
            result.barPercents = barPcts;
            result.found = true;
        }

        return result;
    }
    """

    /// JS that reads claude.ai/settings/usage. Returns the same dict
    /// shape `parseQuotaFromText` produces; QuotaPayload(jsResult:)
    /// converts it to a typed value.
    ///
    /// claude.ai is a heavy SPA that doesn't populate `body.innerText`,
    /// so we walk the tree explicitly: every aria-label + every direct
    /// text node. This gives us the visible labels including
    /// "Resets in Xh Ym" which is what we actually care about.
    nonisolated static let extractionJS = parserLibraryJS + """

    (function() {
        var texts = [];
        document.querySelectorAll('*').forEach(function(el) {
            var l = el.getAttribute && el.getAttribute('aria-label');
            if (l) { texts.push(l); }
            if (el.childNodes) {
                for (var i = 0; i < el.childNodes.length; i++) {
                    var n = el.childNodes[i];
                    if (n.nodeType === 3) {
                        var t = (n.textContent || '').trim();
                        if (t) { texts.push(t); }
                    }
                }
            }
        });
        var allText = texts.join(' | ').replace(/[\\s\\u00a0]+/g, ' ');

        var barPcts = [];
        document.querySelectorAll('[role="progressbar"]').forEach(function(b) {
            var v = b.getAttribute('aria-valuenow');
            if (v) { barPcts.push(parseFloat(v)); return; }
            var w = b.style.width;
            if (w && w.endsWith('%')) { barPcts.push(parseFloat(w)); }
        });

        return parseQuotaFromText(allText, barPcts, Date.now());
    })()
    """
}

// swiftlint:enable line_length
