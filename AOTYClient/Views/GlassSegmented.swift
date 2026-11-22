import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Floating glass segmented switcher for the bottom of a screen. Tap a segment, drag across it,
/// or (on macOS) two-finger swipe left/right on the trackpad to switch selections.
struct GlassSegmented<T: Hashable>: View {
    @Binding var selection: T
    let items: [(T, String)]
    @Namespace private var ns
    @State private var width: CGFloat = 1
    #if os(macOS)
    @State private var swipeMonitor: MacHorizontalSwipeMonitor?
    #endif

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
                            Capsule().fill(.white.opacity(0.22))
                                .matchedGeometryEffect(id: "bubble", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { pick(item.0) }
            }
        }
        .padding(4)
        .background(Color.platformBackground.opacity(0.75), in: Capsule())
        .glassEffect(.regular, in: Capsule())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
        .gesture(DragGesture(minimumDistance: 4).onChanged { v in
            let i = Int((v.location.x / width) * CGFloat(items.count))
            pick(items[max(0, min(items.count - 1, i))].0)
        })
        .shadow(color: .black.opacity(0.32), radius: 10, y: 4)
        #if os(macOS)
        .onAppear {
            let m = MacHorizontalSwipeMonitor { delta in
                step(delta)
            }
            m.start()
            swipeMonitor = m
        }
        .onDisappear {
            swipeMonitor?.stop()
            swipeMonitor = nil
        }
        #endif
    }

    private func pick(_ v: T) {
        guard v != selection else { return }
        Haptic.selection()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { selection = v }
    }

    #if os(macOS)
    private func step(_ delta: Int) {
        guard let idx = items.firstIndex(where: { $0.0 == selection }) else { return }
        let next = idx + delta
        guard items.indices.contains(next) else { return }
        pick(items[next].0)
    }
    #endif
}

#if os(macOS)
/// Detects two-finger horizontal trackpad swipes (scrollWheel) without interfering with vertical scrolling.
@MainActor
private final class MacHorizontalSwipeMonitor {
    private let onStep: @MainActor (Int) -> Void
    private var monitor: Any?
    private var sumX: CGFloat = 0
    private var sumY: CGFloat = 0
    private var fired = false

    init(onStep: @escaping @MainActor (Int) -> Void) {
        self.onStep = onStep
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        // Ignore momentum inertia and events while a modal sheet is presented over the window.
        guard event.momentumPhase.isEmpty else { return }
        guard let win = event.window, win == NSApp.keyWindow, win.attachedSheet == nil else { return }

        if event.phase == .began {
            sumX = 0
            sumY = 0
            fired = false
            return
        }
        if event.phase == .ended || event.phase == .cancelled {
            sumX = 0
            sumY = 0
            fired = false
            return
        }
        guard !fired, event.phase == .changed else { return }

        sumX += event.scrollingDeltaX
        sumY += event.scrollingDeltaY

        if abs(sumX) > 45 && abs(sumX) > abs(sumY) * 1.6 {
            fired = true
            // Natural scrolling: swiping fingers left produces negative deltaX → move to next tab (+1).
            let dir = sumX < 0 ? 1 : -1
            let step = event.isDirectionInvertedFromDevice ? dir : -dir
            onStep(step)
        }
    }
}
#endif
