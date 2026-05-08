import Testing
@testable import ClaudeCounter

struct ClaudeUsageTests {
    @Test func emptyIsNotLoaded() {
        #expect(ClaudeUsage.empty.isLoaded == false)
    }

    @Test func currentPercentSetMakesItLoaded() {
        var usage = ClaudeUsage.empty
        usage.currentPercent = 0
        #expect(usage.isLoaded == true)
    }

    @Test func weeklyPercentSetMakesItLoaded() {
        var usage = ClaudeUsage.empty
        usage.weeklyPercent = 0
        #expect(usage.isLoaded == true)
    }

    @Test func equatableIgnoresInstanceIdentity() {
        let lhs = ClaudeUsage(currentPercent: 5)
        let rhs = ClaudeUsage(currentPercent: 5)
        #expect(lhs == rhs)
    }
}
