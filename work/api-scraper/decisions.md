# Decisions Log — api-scraper

Execution-time decisions and per-task completion reports. Populated as tasks
are implemented (one short entry per task: summary, review links, any
deviation from spec). Empty until implementation starts.

## Tasks

<!-- Append per-task entries here during execution. Template:
### Task N: <name>
- **Summary:** 1-3 sentences on what was implemented.
- **Reviews:** code-reviewer / security-auditor / test-reviewer → logs/working/task-N/*.json
- **Deviations:** none | <what and why>
-->

## Task 1: API models + JSON decoding + test fixtures

**Status:** Done
**Commit:** 2436bd8
**Agent:** models-coder
**Summary:** Added `App/Sources/ClaudeCounter/Scraper/UsageAPIModels.swift` with the
`Decodable` types `OrgSummary`, `UsageLimit`, `FlatWindow`, and `UsageResponse`
(snake_case `CodingKeys`; `percent`/`utilization` as `Double`), plus a
`UsageAPIModels.decoder` whose custom `dateDecodingStrategy` tries an ISO-8601
parse with fractional seconds and falls back to one without. Copied the committed
`usage.json`/`organizations.json` fixtures into the test target and wired them via
`Package.swift` `resources:` so they load through `Bundle.module`.
**Deviations:** Deviated from spec on two minor points to satisfy the repo's
pre-commit hooks (SwiftFormat + strict SwiftLint, warnings-as-errors): (1) the
shared decoder is a computed `static var` returning a fresh `JSONDecoder` per call
rather than a `static let` — `ISO8601DateFormatter`/`JSONDecoder` are not `Sendable`,
and a stored static is rejected under Swift 6 strict concurrency; formatters are
built locally inside the decode closure. (2) Added a one-line
`swiftlint:disable:next discouraged_optional_boolean` for the spec-mandated
`isActive: Bool?`. Behavior matches the spec exactly.

**Reviews:**

*Round 1:*
- code-reviewer: approved (2 low nits) → logs/working/task-1/code-reviewer-round1.json
- test-reviewer: changes_requested (1 high: untested malformed-date branch) → logs/working/task-1/test-reviewer-round1.json

*Round 2 (after fix af86bb9):*
- Added negative test `throwsOnMalformedResetsAt()`; finding resolved.

**Verification:**
- `cd App && swift test` → 54 tests pass (50 pre-existing + 4 new), 8 suites
- `cd App && swift build` → clean (strict concurrency, warnings-as-errors)
- SwiftFormat (lint) + SwiftLint (strict) pre-commit hooks → pass
