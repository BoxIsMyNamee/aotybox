import SwiftUI
import UIKit

/// Floating glass segmented switcher for the bottom of a screen. Tap a segment, or drag across
/// it and the bubble follows your finger (light haptic each time it lands on a new segment).
struct GlassSegmented<T: Hashable>: View {
    @Binding var selection: T
    let items: [(T, String)]
    @Namespace private var ns
    @State private var width: CGFloat = 1

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { item in
                let on = item.0 == selection
                Text(item.1)
                    .font(.subheadline.weight(on ? .semibold : .medium))
                    .foregroundStyle(on ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background {
                        if on {
                            Capsule().fill(.white.opacity(0.16))
                                .matchedGeometryEffect(id: "bubble", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { pick(item.0) }
            }
        }
        .padding(4)
        .glassEffect(.regular, in: Capsule())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
        .gesture(DragGesture(minimumDistance: 4).onChanged { v in
            let i = Int((v.location.x / width) * CGFloat(items.count))
            pick(items[max(0, min(items.count - 1, i))].0)
        })
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    private func pick(_ v: T) {
        guard v != selection else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { selection = v }
    }
}
