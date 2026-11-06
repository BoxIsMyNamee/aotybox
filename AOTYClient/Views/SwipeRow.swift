import SwiftUI
import UIKit

/// Apollo-style row swipe: the row slides with your finger over a full-width color. It stays muted
/// until you pass the trigger point, then lights up with a light haptic tick; let go past it to fire.
/// Swipe right = Learn (green), swipe left = Open (blue). One continuous gesture can go either way.
struct SwipeRow: ViewModifier {
    let learn: () -> Void
    let open: () -> Void
    @Environment(\.swipeRowBackground) private var rowBackground
    @State private var offset: CGFloat = 0
    @State private var armed = false
    @State private var width: CGFloat = 390

    private var threshold: CGFloat { max(70, width * 0.22) }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(offset == 0 ? Color.clear : rowBackground)
            .offset(x: offset)
            .background { actionBackground }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .gesture(HorizontalPan(
                onChange: { t in
                    let nowArmed = abs(t) >= threshold
                    if nowArmed != armed {
                        armed = nowArmed
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    offset = t
                },
                onEnd: { t in
                    let fire = abs(t) >= threshold
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { offset = 0 }
                    armed = false
                    if fire { if t > 0 { learn() } else { open() } }
                }
            ))
            .listRowInsets(EdgeInsets())
    }

    @ViewBuilder private var actionBackground: some View {
        let right = offset > 0
        let color: Color = right ? .green : .blue
        ZStack {
            (offset == 0 ? Color.clear : (armed ? color : color.opacity(0.35)))
            HStack {
                if right {
                    actionIcon("magnifyingglass", "Learn").padding(.leading, 22)
                    Spacer()
                } else if offset < 0 {
                    Spacer()
                    actionIcon("play.fill", "Open").padding(.trailing, 22)
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: armed)
    }

    private func actionIcon(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.title3.weight(.semibold))
            Text(title).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .scaleEffect(armed ? 1.15 : 0.9)
        .opacity(Double(min(CGFloat(1), abs(offset) / CGFloat(50))))
    }
}

extension View {
    func swipeRow(learn: @escaping () -> Void, open: @escaping () -> Void) -> some View {
        modifier(SwipeRow(learn: learn, open: open))
    }
}

/// Background the row shows while it slides (match the list's cell color).
private struct SwipeRowBackgroundKey: EnvironmentKey { static let defaultValue = Color(.systemBackground) }
extension EnvironmentValues {
    var swipeRowBackground: Color {
        get { self[SwipeRowBackgroundKey.self] }
        set { self[SwipeRowBackgroundKey.self] = newValue }
    }
}

/// A pan that only starts for mostly-horizontal drags, so vertical scrolling stays untouched.
struct HorizontalPan: UIGestureRecognizerRepresentable {
    var onChange: (CGFloat) -> Void
    var onEnd: (CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.delegate = context.coordinator
        return g
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        let t = g.translation(in: g.view).x
        switch g.state {
        case .began, .changed: onChange(t)
        case .ended, .cancelled, .failed: onEnd(t)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 1.3
        }
    }
}
