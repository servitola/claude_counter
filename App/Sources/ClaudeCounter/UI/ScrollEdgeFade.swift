import SwiftUI

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
