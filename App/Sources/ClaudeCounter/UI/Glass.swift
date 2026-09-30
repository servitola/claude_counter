import SwiftUI

extension Color {
    static let claudeBrand = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let codexBrand = Color(red: 0.06, green: 0.64, blue: 0.50)
}

extension View {
    /// Liquid Glass on macOS 26+, a material surface on macOS 15 (the deployment floor).
    @ViewBuilder
    func glassSurface(
        in shape: some Shape,
        tint: Color? = nil,
        interactive: Bool = false
    )
        -> some View
    {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background((tint ?? .clear).opacity(0.35), in: shape)
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 1))
        }
    }

    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

// MARK: - GlassLayout

/// Frosted cards fill the window; only a thin rim of the clear pane shows the
/// desktop, so the see-through look stays decorative instead of legible text.
enum GlassLayout {
    static let rim: CGFloat = 8
    static let cardRadius: CGFloat = 16
    /// Room for the traffic lights, which sit on the top card.
    static let titlebarClearance: CGFloat = 34
}

// MARK: - GlassGroup

/// Lets sibling glass shapes blend and morph into each other on macOS 26+.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - GlassBackdrop

/// The desktop shows through a blurred glass pane; a faint brand-colored mesh
/// on top keeps the window from reading as flat gray over a dull wallpaper.
struct GlassBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    private static let points: [SIMD2<Float>] = [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [0.55, 0.45], [1, 0.5],
        [0, 1], [0.5, 1], [1, 1]
    ]

    private static let light: [Color] = [
        Color(red: 1.00, green: 0.80, blue: 0.68),
        Color(red: 1.00, green: 0.92, blue: 0.85),
        Color(red: 0.86, green: 0.84, blue: 1.00),
        Color(red: 0.99, green: 0.87, blue: 0.78),
        Color(red: 0.98, green: 0.97, blue: 0.96),
        Color(red: 0.80, green: 0.93, blue: 0.89),
        Color(red: 0.90, green: 0.86, blue: 0.98),
        Color(red: 0.83, green: 0.91, blue: 0.98),
        Color(red: 0.72, green: 0.90, blue: 0.84)
    ]

    private static let dark: [Color] = [
        Color(red: 0.38, green: 0.16, blue: 0.10),
        Color(red: 0.22, green: 0.10, blue: 0.22),
        Color(red: 0.10, green: 0.10, blue: 0.28),
        Color(red: 0.30, green: 0.13, blue: 0.10),
        Color(red: 0.09, green: 0.09, blue: 0.12),
        Color(red: 0.04, green: 0.20, blue: 0.21),
        Color(red: 0.09, green: 0.10, blue: 0.24),
        Color(red: 0.03, green: 0.15, blue: 0.17),
        Color(red: 0.03, green: 0.24, blue: 0.18)
    ]

    var body: some View {
        ZStack {
            WindowGlass()
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.points,
                colors: scheme == .dark ? Self.dark : Self.light
            )
            .opacity(0.18)
        }
        .ignoresSafeArea()
    }
}

// MARK: - ScrollEdgeFade

extension View {
    /// Content dissolves into the window edge instead of being cut off there.
    /// Each edge fades only while there is more content past it, so the top
    /// card is untouched at rest.
    func scrollEdgeFade(top: CGFloat = 56, bottom: CGFloat = 28) -> some View {
        modifier(ScrollEdgeFade(topHeight: top, bottomHeight: bottom))
    }
}

// MARK: - ScrollEdgeFade

private struct ScrollEdgeFade: ViewModifier {
    let topHeight: CGFloat
    let bottomHeight: CGFloat
    @State private var overflow = Overflow(top: false, bottom: false)

    struct Overflow: Equatable {
        let top: Bool
        let bottom: Bool
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Overflow.self) { geo in
                let visibleBottom = geo.contentOffset.y + geo.containerSize.height
                return Overflow(
                    top: geo.contentOffset.y + geo.contentInsets.top > 1,
                    bottom: visibleBottom < geo.contentSize.height + geo.contentInsets.bottom - 1
                )
            } action: { _, new in
                withAnimation(.easeOut(duration: 0.2)) { overflow = new }
            }
            .mask {
                VStack(spacing: 0) {
                    edge(height: topHeight, faded: overflow.top, fadesUp: true)
                    Rectangle()
                    edge(height: bottomHeight, faded: overflow.bottom, fadesUp: false)
                }
                .ignoresSafeArea()
            }
    }

    private func edge(height: CGFloat, faded: Bool, fadesUp: Bool) -> some View {
        LinearGradient(
            colors: [.black.opacity(faded ? 0 : 1), .black],
            startPoint: fadesUp ? .top : .bottom,
            endPoint: fadesUp ? .bottom : .top
        )
        .frame(height: height)
    }
}
