import SwiftUI

/// The advanced editor shown when the `.custom` preset is selected: a free-text
/// template field, a palette of clickable tokens, and the color-rule controls.
struct CustomFormatEditor: View {
    @Binding var format: TitleFormat

    /// The full token vocabulary, grouped visually by provider. Clicking a
    /// button appends its `{token}` to the end of the template.
    private static let tokens: [(label: String, token: String)] = [
        ("C %", "{claude.session}"),
        ("C wk", "{claude.weekly}"),
        ("C reset", "{claude.session.reset}"),
        ("C wk reset", "{claude.weekly.reset}"),
        ("X %", "{codex.session}"),
        ("X wk", "{codex.weekly}"),
        ("X reset", "{codex.session.reset}"),
        ("X wk reset", "{codex.weekly.reset}")
    ]

    var body: some View {
        TextField("Template", text: $format.customTemplate, axis: .vertical)
            .lineLimit(1 ... 3)
        tokenPalette
        colorControls
    }

    private var tokenPalette: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible()), count: 4),
            spacing: 6
        ) {
            ForEach(Self.tokens, id: \.token) { entry in
                Button(entry.label) { format.customTemplate += entry.token }
                    .font(.caption)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var colorControls: some View {
        Picker("Color by", selection: $format.customColorRule.driver) {
            ForEach(ColorDriver.allCases, id: \.self) { driver in
                Text(driver.title).tag(driver)
            }
        }
        Picker("Color target", selection: $format.customColorRule.target) {
            ForEach(ColorTarget.allCases, id: \.self) { target in
                Text(target.title).tag(target)
            }
        }
        Stepper(
            "Orange at \(format.customColorRule.warn)%",
            value: $format.customColorRule.warn, in: 0 ... 100
        )
        Stepper(
            "Red at \(format.customColorRule.alert)%",
            value: $format.customColorRule.alert, in: 0 ... 100
        )
    }
}
