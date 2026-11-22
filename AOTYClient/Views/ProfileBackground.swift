import SwiftUI
import PhotosUI
import Security

/// Your own picture behind the top of your profile. Kept on this device only (backed up in Keychain
/// and Documents so app updates or sideload reinstalls never wipe it).
enum ProfileBackground {
    static let revKey = "profileBackgroundRev"
    private static let kcService = "com.harper.aotyclient.profilebg"
    private static let kcAccount = "background.jpg"
    private static var cached: PlatformImage?

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profileBackground.jpg")
    }
    private static var docURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profileBackground.jpg")
    }

    static func load() -> PlatformImage? {
        if let cached { return cached }
        if let img = PlatformImage(contentsOfFile: url.path) {
            cached = img
            // Backfill Keychain/Documents for backgrounds saved before this update.
            if loadKeychain() == nil, let d = try? Data(contentsOf: url) {
                saveKeychain(d)
                try? d.write(to: docURL, options: .atomic)
            }
            return img
        }
        if let img = PlatformImage(contentsOfFile: docURL.path) {
            cached = img
            if let d = try? Data(contentsOf: docURL) {
                try? d.write(to: url, options: .atomic)
                if loadKeychain() == nil { saveKeychain(d) }
            }
            return img
        }
        if let d = loadKeychain(), let img = PlatformImage(data: d) {
            cached = img
            try? d.write(to: url, options: .atomic)
            try? d.write(to: docURL, options: .atomic)
            return img
        }
        return nil
    }

    static func rawData() -> Data? {
        if let d = try? Data(contentsOf: url) { return d }
        if let d = try? Data(contentsOf: docURL) { return d }
        if let d = loadKeychain() { return d }
        return cached?.jpegDataValue(compressionQuality: 0.82)
    }

    static func save(_ data: Data) -> Bool {
        guard let img = PlatformImage(data: data) else { return false }
        // Keep it a sensible size (a banner, not a 48 MP photo).
        let resized = PlatformImage.resized(img, maxWidth: 1600)
        guard let jpg = resized.jpegDataValue(compressionQuality: 0.82) else { return false }
        let wrote = (try? jpg.write(to: url, options: .atomic)) != nil
        try? jpg.write(to: docURL, options: .atomic)
        saveKeychain(jpg)
        cached = PlatformImage(data: jpg) ?? resized
        return wrote || cached != nil
    }

    static func remove() {
        cached = nil
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: docURL)
        deleteKeychain()
    }

    private static func saveKeychain(_ data: Data) {
        #if os(iOS)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: kcAccount,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
        #endif
    }

    private static func loadKeychain() -> Data? {
        #if os(iOS)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: kcAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
        #else
        return nil
        #endif
    }

    private static func deleteKeychain() {
        #if os(iOS)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: kcAccount,
        ]
        SecItemDelete(base as CFDictionary)
        #endif
    }
}

/// Fills its frame with the image, cropped around a saved focus point and zoom.
/// If panned or zoomed past an edge, a blurred copy of the image fills in seamlessly behind it.
struct FocusedFillImage: View {
    let image: PlatformImage
    var focusX: Double = 0.5
    var focusY: Double = 0.5
    var zoom: Double = 1

    private var offEdge: Bool {
        zoom < 0.99 || focusX < 0 || focusX > 1 || focusY < 0 || focusY > 1
    }

    var body: some View {
        GeometryReader { geo in
            let size = fittedSize(geo.size)
            let rangeX = max(size.width - geo.size.width, geo.size.width * 0.6)
            let rangeY = max(size.height - geo.size.height, geo.size.height * 0.6)
            let centerX = (geo.size.width - size.width) / 2
            let centerY = (geo.size.height - size.height) / 2
            let dx: CGFloat = centerX - (CGFloat(focusX) - 0.5) * rangeX
            let dy: CGFloat = centerY - (CGFloat(focusY) - 0.5) * rangeY

            ZStack(alignment: .topLeading) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .blur(radius: 34)
                    .scaleEffect(1.18)
                    .opacity(0.9)

                Image(platformImage: image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .mask {
                        if offEdge {
                            RoundedRectangle(cornerRadius: 12)
                                .padding(10)
                                .blur(radius: 14)
                        } else {
                            Rectangle()
                        }
                    }
                    .offset(x: dx, y: dy)
            }
        }
        .clipped()
    }

    private func fittedSize(_ box: CGSize) -> CGSize {
        let iw: CGFloat = max(image.size.width, 1)
        let ih: CGFloat = max(image.size.height, 1)
        let fill: CGFloat = max(box.width / iw, box.height / ih)
        let scale: CGFloat = fill * CGFloat(max(zoom, 0.5))
        return CGSize(width: iw * scale, height: ih * scale)
    }
}

extension ProfileBackground {
    static let xKey = "profileBackgroundX"
    static let yKey = "profileBackgroundY"
    static let zoomKey = "profileBackgroundZoom"
}

/// Reads the saved focus/zoom directly so List's listRowBackground updates live while dragging/pinching.
struct ProfileBackgroundLayer: View {
    let image: PlatformImage
    @AppStorage(ProfileBackground.xKey) private var focusX = 0.5
    @AppStorage(ProfileBackground.yKey) private var focusY = 0.5
    @AppStorage(ProfileBackground.zoomKey) private var zoom = 1.0

    var body: some View {
        FocusedFillImage(image: image, focusX: focusX, focusY: focusY, zoom: zoom)
            .overlay {
                #if os(macOS)
                LinearGradient(stops: [.init(color: .black.opacity(0.05), location: 0),
                                       .init(color: .black.opacity(0.35), location: 0.42),
                                       .init(color: Color.platformBackground, location: 0.88),
                                       .init(color: Color.platformBackground, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                #else
                LinearGradient(stops: [.init(color: .black.opacity(0.05), location: 0),
                                       .init(color: .black.opacity(0.35), location: 0.45),
                                       .init(color: Color.platformBackground, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                #endif
            }
            .clipped()
            .padding(.horizontal, -40)
    }
}

extension Notification.Name {
    static let adjustProfileBackground = Notification.Name("adjustProfileBackground")
}

/// Settings row: pick, jump to your profile to position, or remove the background.
struct ProfileBackgroundSettings: View {
    @AppStorage(ProfileBackground.revKey) private var rev = 0
    @AppStorage(ProfileBackground.xKey) private var focusX = 0.5
    @AppStorage(ProfileBackground.yKey) private var focusY = 0.5
    @AppStorage(ProfileBackground.zoomKey) private var zoom = 1.0
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var image: PlatformImage?
    @State private var failed = false

    var body: some View {
        Section {
            PhotosPicker(selection: $item, matching: .images) {
                Label(image == nil ? "Choose Image" : "Change Image", systemImage: "photo")
            }
            if image != nil {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        NotificationCenter.default.post(name: .adjustProfileBackground, object: nil)
                    }
                } label: {
                    Label("Adjust Position", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                if focusX != 0.5 || focusY != 0.5 || zoom != 1 {
                    Button("Reset Position") { resetPosition() }
                }
                Button("Remove Background", role: .destructive) {
                    ProfileBackground.remove(); image = nil; resetPosition(); rev += 1
                }
            }
        } header: {
            Text("Profile Background")
        } footer: {
            Text(failed ? "Couldn't use that image. Try another one."
                 : "Shown behind the top of your profile. Only on this phone.")
        }
        .onAppear { image = ProfileBackground.load() }
        .onChange(of: item) {
            guard let item else { return }
            Task {
                failed = false
                if let data = try? await item.loadTransferable(type: Data.self), ProfileBackground.save(data) {
                    image = ProfileBackground.load(); resetPosition(); rev += 1
                } else { failed = true }
                self.item = nil
            }
        }
    }

    private func resetPosition() {
        focusX = 0.5; focusY = 0.5; zoom = 1
    }
}

#if os(iOS)
/// UIKit gesture overlay so List/UICollectionView never swallows pan, pinch, or double-tap.
struct PanPinchOverlay: UIViewRepresentable {
    var onPan: (CGSize, CGSize) -> Void
    var onPanEnd: () -> Void
    var onPinch: (CGFloat) -> Void
    var onPinchEnd: () -> Void
    var onDoubleTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap))
        tap.numberOfTapsRequired = 2
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PanPinchOverlay
        init(parent: PanPinchOverlay) { self.parent = parent }

        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let v = g.view else { return }
            switch g.state {
            case .began, .changed:
                let t = g.translation(in: v)
                parent.onPan(CGSize(width: t.x, height: t.y), v.bounds.size)
            case .ended, .cancelled, .failed:
                parent.onPanEnd()
            default: break
            }
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began, .changed:
                parent.onPinch(g.scale)
            case .ended, .cancelled, .failed:
                parent.onPinchEnd()
            default: break
            }
        }

        @objc func handleDoubleTap() {
            parent.onDoubleTap()
        }
    }
}
#else
/// AppKit mouse/trackpad overlay so macOS List/NSTableView never swallows drag, pinch, or double-click.
struct PanPinchOverlay: NSViewRepresentable {
    var onPan: (CGSize, CGSize) -> Void
    var onPanEnd: () -> Void
    var onPinch: (CGFloat) -> Void
    var onPinchEnd: () -> Void
    var onDoubleTap: () -> Void

    func makeNSView(context: Context) -> PanPinchNSView {
        let view = PanPinchNSView()
        view.callbacks = self
        return view
    }

    func updateNSView(_ nsView: PanPinchNSView, context: Context) {
        nsView.callbacks = self
    }

    final class PanPinchNSView: NSView {
        var callbacks: PanPinchOverlay?
        private var dragStart: CGPoint?
        private var pinchScale: CGFloat = 1

        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: dragStart != nil ? .closedHand : .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                callbacks?.onDoubleTap()
                return
            }
            dragStart = convert(event.locationInWindow, from: nil)
            NSCursor.closedHand.push()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = dragStart else { return }
            let p = convert(event.locationInWindow, from: nil)
            callbacks?.onPan(CGSize(width: p.x - start.x, height: p.y - start.y), bounds.size)
        }

        override func mouseUp(with event: NSEvent) {
            if dragStart != nil {
                dragStart = nil
                NSCursor.pop()
                callbacks?.onPanEnd()
            }
        }

        override func magnify(with event: NSEvent) {
            switch event.phase {
            case .began:
                pinchScale = max(0.2, 1 + event.magnification)
                callbacks?.onPinch(pinchScale)
            case .changed:
                pinchScale = max(0.2, pinchScale * (1 + event.magnification))
                callbacks?.onPinch(pinchScale)
            case .ended, .cancelled:
                pinchScale = 1
                callbacks?.onPinchEnd()
            default: break
            }
        }
    }
}
#endif
