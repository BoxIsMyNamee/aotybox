import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Shared horizontal drag state so a 2-finger trackpad swipe moves both the `GlassSegmented`
/// pill and any paired `SlidingPager` horizontally in lockstep (like macOS Mission Control).
@MainActor
final class MacPagerDragState: ObservableObject {
    static let shared = MacPagerDragState()
    @Published var dragOffset: CGFloat = 0
    @Published var isDragging: Bool = false
}

/// Floating glass segmented switcher for the bottom of a screen. Tap a segment, drag across it,
/// or (on macOS) two-finger swipe left/right on the trackpad to switch selections.
struct GlassSegmented<T: Hashable>: View {
    @Binding var selection: T
    let items: [(T, String)]
    @Namespace private var ns
    @State private var width: CGFloat = 1
    #if os(macOS)
    @State private var swipeMonitor: MacHorizontalSwipeMonitor?
    @Environment(\.navigationDepth) private var navDepth
    @Environment(\.popNavigation) private var popNavigation
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
            let m = MacHorizontalSwipeMonitor(
                isGlass: true,
                onDrag: { dx in
                    let idx = items.firstIndex(where: { $0.0 == selection }) ?? 0
                    // When on the first segment of a pushed screen (idx == 0) and swiping right (dx > 0),
                    // let the page rubber-band slightly right to hint back-navigation.
                    var adjusted = dx
                    if (idx == 0 && dx > 0) || (idx == items.count - 1 && dx < 0) {
                        adjusted = dx * 0.25
                    }
                    MacPagerDragState.shared.isDragging = true
                    MacPagerDragState.shared.dragOffset = adjusted
                },
                onEnd: { dx, velocityX in
                    MacPagerDragState.shared.isDragging = false
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        MacPagerDragState.shared.dragOffset = 0
                    }
                    let idx = items.firstIndex(where: { $0.0 == selection }) ?? 0
                    let projected = dx + velocityX * 0.18
                    // On a pushed screen (Learn, User Reviews): swiping right when on the first bottom tab pops back!
                    // Otherwise swiping left/right switches across the bottom tabs (`Lyrics <-> About <-> Comments <-> Ask AI` or `Popular <-> Recent <-> Lowest`).
                    if navDepth > 0 && idx == 0 && (dx > 55 || projected > 85) {
                        Haptic.selection()
                        popNavigation()
                        return
                    }
                    if abs(dx) > 55 || abs(projected) > 95 {
                        step(projected < 0 ? 1 : -1)
                    }
                }
            )
            m.start()
            swipeMonitor = m
        }
        .onDisappear {
            MacPagerDragState.shared.isDragging = false
            MacPagerDragState.shared.dragOffset = 0
            swipeMonitor?.stop()
            swipeMonitor = nil
        }
        #endif
    }

    private func pick(_ v: T) {
        guard v != selection else { return }
        Haptic.selection()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { selection = v }
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

/// Mission Control-style horizontal sliding container for views paired with `GlassSegmented`.
/// Lazily mounts each tab the first time it is visited (or when it is the active neighbour during a swipe)
/// so unvisited tabs don't lag initial load, and slides pages side-by-side smoothly.
struct SlidingPager<T: Hashable & Identifiable, Page: View>: View {
    let items: [T]
    @Binding var selection: T
    @ViewBuilder var page: (T) -> Page

    @State private var visited: Set<T> = []
    @State private var containerWidth: CGFloat = 1000
    @ObservedObject private var dragState = MacPagerDragState.shared

    private var selectedIndex: Int {
        items.firstIndex(of: selection) ?? 0
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                let isCurrent = idx == selectedIndex
                let isAdjacent = abs(idx - selectedIndex) == 1
                if isCurrent || visited.contains(item) || (dragState.isDragging && isAdjacent) {
                    page(item)
                        .frame(width: containerWidth)
                        .offset(x: CGFloat(idx - selectedIndex) * containerWidth + dragState.dragOffset)
                        // Never disable hit-testing on the current page: disabling allowsHitTesting on macOS
                        // drops NSScrollView's active 2-finger vertical scroll sequence!
                        .allowsHitTesting(isCurrent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
            if w > 1 { containerWidth = w }
        }
        .animation(dragState.isDragging ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: selectedIndex)
        .animation(dragState.isDragging ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: dragState.dragOffset)
        .onAppear {
            visited.insert(selection)
        }
        .onChange(of: selection) {
            visited.insert(selection)
        }
    }
}

#if os(macOS)
/// Detects two-finger horizontal trackpad swipes (`scrollWheel`) with live drag tracking for
/// Mission Control-style page sliding and swipe-right back navigation.
/// Uses a lifo stack for `GlassSegmented` monitors so pushed pages with a bottom switcher (like Learn or User Reviews)
/// override the root tab's bottom switcher without fighting each other.
@MainActor
final class MacHorizontalSwipeMonitor {
    private static var glassStack: [UUID] = []
    static var hasActiveGlass: Bool { !glassStack.isEmpty }

    private let id = UUID()
    private let isGlass: Bool
    private let onDrag: @MainActor (CGFloat) -> Void
    private let onEnd: @MainActor (CGFloat, CGFloat) -> Void
    private var monitor: Any?
    private var sumX: CGFloat = 0
    private var sumY: CGFloat = 0
    private var lastDX: CGFloat = 0
    private var lockedHorizontal: Bool? = nil

    init(
        isGlass: Bool,
        onDrag: @escaping @MainActor (CGFloat) -> Void,
        onEnd: @escaping @MainActor (CGFloat, CGFloat) -> Void
    ) {
        self.isGlass = isGlass
        self.onDrag = onDrag
        self.onEnd = onEnd
    }

    func start() {
        guard monitor == nil else { return }
        if isGlass {
            Self.glassStack.removeAll { $0 == id }
            Self.glassStack.append(id)
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if isGlass {
            Self.glassStack.removeAll { $0 == id }
        }
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private var isTopResponder: Bool {
        if isGlass {
            return Self.glassStack.last == id
        } else {
            return Self.glassStack.isEmpty
        }
    }

    private func handle(_ event: NSEvent) {
        guard isTopResponder else { return }
        guard event.momentumPhase.isEmpty else { return }
        guard let win = event.window, win == NSApp.keyWindow, win.attachedSheet == nil else { return }
        if MacThreeFingerTabMonitor.isThreeFingerActive {
            if lockedHorizontal == true {
                onDrag(0)
                lockedHorizontal = false
            }
            return
        }

        if event.phase == .began {
            sumX = 0
            sumY = 0
            lastDX = 0
            lockedHorizontal = nil
            return
        }
        if event.phase == .ended || event.phase == .cancelled {
            if lockedHorizontal == true {
                onEnd(sumX, lastDX * 8)
            }
            sumX = 0
            sumY = 0
            lastDX = 0
            lockedHorizontal = nil
            return
        }
        guard event.phase == .changed else { return }

        // Normalize so positive dx = fingers moving right on the trackpad (reveal left / go back),
        // negative dx = fingers moving left (reveal right / next tab).
        let rawDX = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        let rawDY = event.scrollingDeltaY

        sumX += rawDX
        sumY += rawDY
        lastDX = rawDX

        if lockedHorizontal == nil {
            let dist = hypot(sumX, sumY)
            guard dist > 12 else { return }
            lockedHorizontal = abs(sumX) > abs(sumY) * 1.4
        }

        if lockedHorizontal == true {
            onDrag(sumX)
        }
    }
}

/// Shared horizontal drag state for 3-finger top-level tab switching on macOS so top tabs
/// visibly slide side-by-side in lockstep with your 3 fingers (Mission Control style).
@MainActor
final class MacTopTabDragState: ObservableObject {
    static let shared = MacTopTabDragState()
    @Published var dragOffset: CGFloat = 0
    @Published var isDragging: Bool = false
}

/// Detects three-finger left/right trackpad swipes to switch between the top-level tabs with
/// live Mission Control-style horizontal drag tracking.
/// Enables indirect trackpad touches ONLY on the root `contentView` (never on `NSScrollView` subviews,
/// which would break standard 2-finger vertical scrolling).
@MainActor
final class MacThreeFingerTabMonitor {
    static var isThreeFingerActive = false

    private let onDrag: @MainActor (CGFloat) -> Void
    private let onEnd: @MainActor (CGFloat, CGFloat) -> Void
    private let onStep: @MainActor (Int) -> Void
    private var monitor: Any?
    private var startX: CGFloat?
    private var startY: CGFloat?
    private var lastX: CGFloat = 0
    private var velocityX: CGFloat = 0
    private var lockedHorizontal: Bool? = nil
    private var lastFireTime: TimeInterval = 0

    init(
        onDrag: @escaping @MainActor (CGFloat) -> Void,
        onEnd: @escaping @MainActor (CGFloat, CGFloat) -> Void,
        onStep: @escaping @MainActor (Int) -> Void
    ) {
        self.onDrag = onDrag
        self.onEnd = onEnd
        self.onStep = onStep
    }

    func start() {
        guard monitor == nil else { return }
        Self.enableIndirectTouchesOnRootWindowViews()
        let mask: NSEvent.EventTypeMask = [.swipe, .beginGesture, .gesture, .endGesture, .scrollWheel, .mouseMoved]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
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

    static func enableIndirectTouchesOnRootWindowViews() {
        for win in NSApp.windows {
            if let cv = win.contentView, !cv.allowedTouchTypes.contains(.indirect) {
                cv.allowedTouchTypes.insert(.indirect)
            }
        }
    }

    private func fireStep(_ step: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFireTime > 0.25 else { return }
        lastFireTime = now
        onStep(step)
    }

    private func handle(_ event: NSEvent) {
        guard let win = event.window, win == NSApp.keyWindow, win.attachedSheet == nil else { return }
        if let cv = win.contentView, !cv.allowedTouchTypes.contains(.indirect) {
            cv.allowedTouchTypes.insert(.indirect)
        }

        if event.type == .swipe {
            guard abs(event.deltaX) > abs(event.deltaY) else { return }
            if event.deltaX < 0 {
                fireStep(1)
            } else if event.deltaX > 0 {
                fireStep(-1)
            }
            return
        }

        let touches = event.touches(matching: [.began, .moved, .stationary, .touching], in: nil)
        processTouches(touches)
    }

    func processTouches(_ touches: Set<NSTouch>) {
        let winWidth = NSApp.keyWindow?.frame.width ?? 1160
        if touches.count == 3 {
            Self.isThreeFingerActive = true
            let avgX = touches.reduce(CGFloat(0)) { $0 + $1.normalizedPosition.x } / 3.0
            let avgY = touches.reduce(CGFloat(0)) { $0 + $1.normalizedPosition.y } / 3.0
            if startX == nil {
                startX = avgX
                startY = avgY
                lastX = avgX
                velocityX = 0
                lockedHorizontal = nil
                return
            }

            guard let sx = startX, let sy = startY else { return }
            let dxNorm = avgX - sx
            let dyNorm = avgY - sy
            velocityX = (avgX - lastX) * winWidth * 14
            lastX = avgX

            if lockedHorizontal == nil {
                let dist = hypot(dxNorm, dyNorm)
                guard dist > 0.015 else { return }
                lockedHorizontal = abs(dxNorm) > abs(dyNorm) * 1.2
            }

            if lockedHorizontal == true {
                let pixelDX = dxNorm * winWidth * 2.2
                onDrag(pixelDX)
            }
        } else if touches.count != 3 {
            if lockedHorizontal == true, let sx = startX {
                let totalDX = (lastX - sx) * winWidth * 2.2
                onEnd(totalDX, velocityX)
                lastFireTime = ProcessInfo.processInfo.systemUptime
            }
            if touches.count < 3 {
                Self.isThreeFingerActive = false
            }
            startX = nil
            startY = nil
            velocityX = 0
            lockedHorizontal = nil
        }
    }
}

/// Transparent background `NSView` with `allowedTouchTypes = [.indirect]` so macOS routes raw
/// multi-finger trackpad touch events to the window without interfering with `NSScrollView`.
struct MacThreeFingerTouchHost: NSViewRepresentable {
    var monitor: MacThreeFingerTabMonitor?

    func makeNSView(context: Context) -> TouchNSView {
        let v = TouchNSView()
        v.allowedTouchTypes = [.indirect]
        return v
    }

    func updateNSView(_ nsView: TouchNSView, context: Context) {
        nsView.monitor = monitor
        nsView.allowedTouchTypes = [.indirect]
    }

    final class TouchNSView: NSView {
        weak var monitor: MacThreeFingerTabMonitor?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            allowedTouchTypes = [.indirect]
            MacThreeFingerTabMonitor.enableIndirectTouchesOnRootWindowViews()
        }

        override func touchesBegan(with event: NSEvent) {
            super.touchesBegan(with: event)
            monitor?.processTouches(event.touches(matching: [.began, .moved, .stationary, .touching], in: nil))
        }

        override func touchesMoved(with event: NSEvent) {
            super.touchesMoved(with: event)
            monitor?.processTouches(event.touches(matching: [.began, .moved, .stationary, .touching], in: nil))
        }

        override func touchesEnded(with event: NSEvent) {
            super.touchesEnded(with: event)
            monitor?.processTouches(event.touches(matching: [.began, .moved, .stationary, .touching], in: nil))
        }

        override func touchesCancelled(with event: NSEvent) {
            super.touchesCancelled(with: event)
            monitor?.processTouches([])
        }
    }
}
#endif

