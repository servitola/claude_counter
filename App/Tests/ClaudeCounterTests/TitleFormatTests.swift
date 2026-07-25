import Testing
@testable import ClaudeCounter

struct TitleFormatTests {
    @Test func defaultPresetIsFull() {
        #expect(TitleFormat().preset == .full)
    }

    @Test func weeklyBothGeneratesTwoWeeklyTokens() {
        let format = TitleFormat(preset: .weekly)
        #expect(
            format.resolvedTemplate(mode: .both)
                == "  {claude.weekly}  ·  {codex.weekly}"
        )
    }

    @Test func sessionClaudeGeneratesSessionChip() {
        let format = TitleFormat(preset: .session)
        #expect(
            format.resolvedTemplate(mode: .claude)
                == "  {claude.session} {claude.session.reset}"
        )
    }

    @Test func customUsesRawTemplateIgnoringMode() {
        let format = TitleFormat(preset: .custom, customTemplate: "X{codex.weekly}")
        #expect(format.resolvedTemplate(mode: .both) == "X{codex.weekly}")
    }

    @Test func weeklyAlertColorRuleDrivenByClaudeSession() {
        let format = TitleFormat(preset: .weeklyAlert)
        #expect(
            format.resolvedColorRule
                == ColorRule(driver: .claudeSession, target: .weekly, warn: 70, alert: 92)
        )
    }

    @Test func fullColorRuleIsOwnSession8090() {
        let format = TitleFormat(preset: .full)
        #expect(
            format.resolvedColorRule
                == ColorRule(driver: .ownSession, target: .session, warn: 80, alert: 90)
        )
    }

    @Test func customUsesItsOwnColorRule() {
        let rule = ColorRule(driver: .claudeSession, target: .weekly, warn: 50, alert: 60)
        let format = TitleFormat(preset: .custom, customColorRule: rule)
        #expect(format.resolvedColorRule == rule)
    }
}
