import SwiftUI
import UIKit

/// Apollo-style row swipe: the row slides with your finger over a full-width color. It stays muted
/// until you pass the trigger point, then lights up with a light haptic tick; let go past it to fire.
/// Swipe right = Learn (green), swipe left = Open (blue). One continuous gesture can go either way.
/// One side of an Apollo-style swipe.
struct SwipeAction {
    let icon: String
    let title: String
    let color: Color
    let perform: () -> Void
}

/// Apollo-style row swipe: the row slides with your finger over a full-width color. It stays muted
/// until you pass the trigger point, then lights up with a light haptic tick; let go past it to fire.
/// `leading` is revealed by swiping right, `trailing` by swiping left. A side with no action doesn't move.
struct SwipeRow: ViewModifier {
    let leading: SwipeAction?
    let trailing: SwipeAction?
    @Environment(\.swipeRowBackground) private var rowBackground
    @State private var offset: CGFloat = 0
    @State private var armed = false
    @State private var width: CGFloat = 390
    /// Which side is showing (+1 leading, -1 trailing). Kept until the row has fully slid back,
    /// so the color stays behind it on the way home instead of vanishing the instant you let go.
    @State private var side: Int = 0
    @State private var firedLit = false
    @State private var dragging = false

    private var threshold: CGFloat { max(70, width * 0.22) }
    private var active: SwipeAction? { side > 0 ? leading : (side < 0 ? trailing : nil) }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(side == 0 ? Color.clear : rowBackground)
            .offset(x: offset)
            .background { actionBackground }
            // Follow the finger exactly while dragging; glide home when let go. (An implicit animation:
            // withAnimation from the UIKit pan callback was being dropped, so the row snapped back.)
            .animation(dragging ? nil : .smooth(duration: 0.32), value: offset)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .gesture(HorizontalPan(
                onChange: { raw in
                    var t = raw
                    if t > 0 && leading == nil { t = 0 }
                    if t < 0 && trailing == nil { t = 0 }
                    let nowArmed = t != 0 && abs(t) >= threshold
                    if nowArmed != armed {
                        armed = nowArmed
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    if t != 0 { side = t > 0 ? 1 : -1 }
                    dragging = true
                    offset = t
                },
                onEnd: { _ in
                    let fire = armed ? active : nil
                    firedLit = fire != nil          // keep the color lit while it slides back
                    dragging = false
                    offset = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                        if offset == 0 && !dragging { side = 0; firedLit = false; armed = false }
                    }
                    if fire == nil { armed = false }
                    // Let the slide-back start before the action re-renders the row.
                    if let fire { DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { fire.perform() } }
                }
            ))
            .listRowInsets(EdgeInsets())
    }

    @ViewBuilder private var actionBackground: some View {
        if let a = active {
            ZStack {
                (armed || firedLit) ? a.color : a.color.opacity(0.35)
                HStack {
                    if side > 0 { icon(a).padding(.leading, 22); Spacer() }
                    else { Spacer(); icon(a).padding(.trailing, 22) }
                }
            }
            .animation(.easeOut(duration: 0.12), value: armed)
            .animation(dragging ? nil : .smooth(duration: 0.32), value: offset)
        }
    }

    private func icon(_ a: SwipeAction) -> some View {
        VStack(spacing: 3) {
            Image(systemName: a.icon).font(.title3.weight(.semibold))
            Text(a.title).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .scaleEffect((armed || firedLit) ? 1.15 : 0.9)
        .opacity(Double(min(CGFloat(1), abs(offset) / CGFloat(50))))
    }
}

extension View {
    func swipeRow(leading: SwipeAction?, trailing: SwipeAction?) -> some View {
        modifier(SwipeRow(leading: leading, trailing: trailing))
    }
    /// Albums and songs: right = Learn (green), left = Open in the music app (blue).
    func swipeRow(learn: @escaping () -> Void, open: @escaping () -> Void) -> some View {
        modifier(SwipeRow(leading: SwipeAction(icon: "magnifyingglass", title: "Learn", color: .green, perform: learn),
                          trailing: SwipeAction(icon: "play.fill", title: "Open", color: .blue, perform: open)))
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
