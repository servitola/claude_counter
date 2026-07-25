import Foundation
import Testing
@testable import ClaudeCounter

struct SettingsStoreTests {
    /// An isolated UserDefaults suite so tests never touch the real domain.
    private func isolatedStore() throws -> SettingsStore {
        let suite = try #require(UserDefaults(suiteName: "settings-test-\(UUID().uuidString)"))
        return SettingsStore(defaults: suite)
    }

    @Test func defaults_to_both_when_unset() throws {
        let store = try isolatedStore()
        #expect(store.displayMode() == .both)
    }

    @Test func round_trips_each_mode() throws {
        let store = try isolatedStore()
        for mode in ProviderDisplayMode.allCases {
            store.setDisplayMode(mode)
            #expect(store.displayMode() == mode)
        }
    }

    @Test func invalid_persisted_value_falls_back_to_both() throws {
        let suite = try #require(UserDefaults(suiteName: "settings-test-\(UUID().uuidString)"))
        suite.set("garbage", forKey: SettingsStore.displayModeKey)
        let store = SettingsStore(defaults: suite)
        #expect(store.displayMode() == .both)
    }

    // MARK: - Title format

    @Test func titleFormat_defaults_to_full_when_unset() throws {
        let store = try isolatedStore()
        #expect(store.titleFormat() == TitleFormat())
    }

    @Test func titleFormat_round_trips_a_custom_config() throws {
        let store = try isolatedStore()
        let format = TitleFormat(
            preset: .custom,
            separator: " | ",
            customTemplate: "wk {claude.weekly}",
            customColorRule: ColorRule(driver: .claudeSession, target: .weekly, warn: 71, alert: 93)
        )
        store.setTitleFormat(format)
        #expect(store.titleFormat() == format)
    }

    @Test func titleFormat_round_trips_each_preset() throws {
        let store = try isolatedStore()
        for preset in TitlePreset.allCases {
            store.setTitleFormat(TitleFormat(preset: preset))
            #expect(store.titleFormat().preset == preset)
        }
    }

    @Test func titleFormat_invalid_preset_falls_back_to_full() throws {
        let suite = try #require(UserDefaults(suiteName: "settings-test-\(UUID().uuidString)"))
        suite.set("garbage", forKey: SettingsStore.presetKey)
        let store = SettingsStore(defaults: suite)
        #expect(store.titleFormat().preset == .full)
    }
}
