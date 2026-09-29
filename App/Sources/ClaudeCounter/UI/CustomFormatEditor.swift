import SwiftUI

/// The advanced editor shown when the `.custom` preset is selected: a free-text
/// template field, a palette of clickable tokens, and the color-rule controls.
struct CustomFormatEditor: View {
    @Binding var format: TitleFormat

    /// Clicking a chip appends its `{token}` to the end of the template.
    private static let chips: [(label: String, suffix: String)] = [
        ("%", "session"),
        ("wk", "weekly"),
        ("reset", "session.reset"),
        ("wk reset", "weekly.reset")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Template", text: $format.customTemplate, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1 ... 3)
            tokenRow(provider: "claude", title: "Claude", tint: .claudeBrand)
            tokenRow(provider: "codex", title: "Codex", tint: .codexBrand)
            Divider()
            colorControls
        }
        .padding(.horizontal, 4)
    }

    private func tokenRow(provider: String, title: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 44, alignment: .leading)
            GlassGroup(spacing: 4) {
                HStack(spacing: 6) {
                    ForEach(Self.chips, id: \.suffix) { chip in
                        let token = "{\(provider).\(chip.suffix)}"
                        Button(chip.label) { format.customTemplate += token }
                            .font(.caption)
                            .controlSize(.small)
                            .glassButtonStyle()
                            .help(token)
                    }
                }
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
        .pickerStyle(.segmented)
        thresholdStepper("Orange at", value: $format.customColorRule.warn, dot: .orange)
        thresholdStepper("Red at", value: $format.customColorRule.alert, dot: .red)
    }

    private func thresholdStepper(_ title: String, value: Binding<Int>, dot: Color) -> some View {
        Stepper(value: value, in: 0 ... 100) {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text("\(title) \(value.wrappedValue)%")
                    .monospacedDigit()
            }
        }
    }
}
