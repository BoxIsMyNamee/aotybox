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
            MacHorizontalSwipeMonitor.activeGlassCount += 1
            let m = MacHorizontalSwipeMonitor(
                onDrag: { dx in
                    // When deep inside a pushed page, swiping right pops back instead of sliding tabs.
                    if navDepth > 0 && dx > 0 {
                        MacPagerDragState.shared.isDragging = false
                        MacPagerDragState.shared.dragOffset = 0
                        return
                    }
                    let idx = items.firstIndex(where: { $0.0 == selection }) ?? 0
                    var adjusted = dx
                    if (idx == 0 && dx > 0) || (idx == items.count - 1 && dx < 0) {
                        adjusted = dx * 0.25 // rubber-band at edges
                    }
                    MacPagerDragState.shared.isDragging = true
                    MacPagerDragState.shared.dragOffset = adjusted
                },
                onEnd: { dx, velocityX in
                    MacPagerDragState.shared.isDragging = false
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        MacPagerDragState.shared.dragOffset = 0
                    }
                    let projected = dx + velocityX * 0.18
                    // Deep in navigation stack: 2-finger swipe right goes back to previous page.
                    if navDepth > 0 && (dx > 55 || projected > 85) {
                        Haptic.selection()
                        popNavigation()
                        return
                    }
                    if abs(dx) > 65 || abs(projected) > 105 {
                        step(projected < 0 ? 1 : -1)
                    }
                }
            )
            m.start()
            swipeMonitor = m
        }
        .onDisappear {
            MacHorizontalSwipeMonitor.activeGlassCount = max(0, MacHorizontalSwipeMonitor.activeGlassCount - 1)
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
                        .allowsHitTesting(isCurrent && !dragState.isDragging)
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
@MainActor
final class MacHorizontalSwipeMonitor {
    static var activeGlassCount: Int = 0

    private let onDrag: @MainActor (CGFloat) -> Void
    private let onEnd: @MainActor (CGFloat, CGFloat) -> Void
    private var monitor: Any?
    private var sumX: CGFloat = 0
    private var sumY: CGFloat = 0
    private var lastDX: CGFloat = 0
    private var lockedHorizontal: Bool? = nil

    init(
        onDrag: @escaping @MainActor (CGFloat) -> Void,
        onEnd: @escaping @MainActor (CGFloat, CGFloat) -> Void
    ) {
        self.onDrag = onDrag
        self.onEnd = onEnd
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
        guard event.momentumPhase.isEmpty else { return }
        guard let win = event.window, win == NSApp.keyWindow, win.attachedSheet == nil else { return }

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
            guard dist > 10 else { return }
            lockedHorizontal = abs(sumX) > abs(sumY) * 1.35
        }

        if lockedHorizontal == true {
            onDrag(sumX)
        }
    }
}

/// Detects three-finger left/right trackpad swipes to switch between the top-level tabs.
/// Supports both macOS `.swipe` events and raw 3-finger trackpad touch gestures.
@MainActor
final class MacThreeFingerTabMonitor {
    private let onStep: @MainActor (Int) -> Void
    private var monitor: Any?
    private var startX: CGFloat?
    private var startY: CGFloat?
    private var lastX: CGFloat = 0
    private var lastY: CGFloat = 0
    private var fired = false

    init(onStep: @escaping @MainActor (Int) -> Void) {
        self.onStep = onStep
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.swipe, .beginGesture, .gesture, .endGesture]) { [weak self] event in
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
        guard let win = event.window, win == NSApp.keyWindow, win.attachedSheet == nil else { return }

        if event.type == .swipe {
            guard abs(event.deltaX) > abs(event.deltaY) else { return }
            if event.deltaX < 0 {
                onStep(1)
            } else if event.deltaX > 0 {
                onStep(-1)
            }
            return
        }

        let touches = event.touches(matching: .touching, in: nil)
        if touches.count == 3 {
            let avgX = touches.reduce(CGFloat(0)) { $0 + $1.normalizedPosition.x } / 3.0
            let avgY = touches.reduce(CGFloat(0)) { $0 + $1.normalizedPosition.y } / 3.0
            if startX == nil {
                startX = avgX
                startY = avgY
                fired = false
            }
            lastX = avgX
            lastY = avgY

            if !fired, let sx = startX, let sy = startY {
                let dx = lastX - sx
                let dy = lastY - sy
                if abs(dx) > 0.14 && abs(dx) > abs(dy) * 1.5 {
                    fired = true
                    // Fingers moving left (dx < 0) switches to the next top tab (+1); moving right (-1).
                    onStep(dx < 0 ? 1 : -1)
                }
            }
        } else if touches.count < 3 {
            startX = nil
            startY = nil
            fired = false
        }
    }
}
#endif

