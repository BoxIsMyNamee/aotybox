import SwiftUI
import PhotosUI
import UIKit
import Security

/// Your own picture behind the top of your profile. Kept on this device only (backed up in Keychain
/// and Documents so app updates or sideload reinstalls never wipe it).
enum ProfileBackground {
    static let revKey = "profileBackgroundRev"
    private static let kcService = "com.harper.aotyclient.profilebg"
    private static let kcAccount = "background.jpg"
    private static var cached: UIImage?

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

    static func load() -> UIImage? {
        if let cached { return cached }
        if let img = UIImage(contentsOfFile: url.path) {
            cached = img
            // Backfill Keychain/Documents for backgrounds saved before this update.
            if loadKeychain() == nil, let d = try? Data(contentsOf: url) {
                saveKeychain(d)
                try? d.write(to: docURL, options: .atomic)
            }
            return img
        }
        if let img = UIImage(contentsOfFile: docURL.path) {
            cached = img
            if let d = try? Data(contentsOf: docURL) {
                try? d.write(to: url, options: .atomic)
                if loadKeychain() == nil { saveKeychain(d) }
            }
            return img
        }
        if let d = loadKeychain(), let img = UIImage(data: d) {
            cached = img
            try? d.write(to: url, options: .atomic)
            try? d.write(to: docURL, options: .atomic)
            return img
        }
        return nil
    }

    static func save(_ data: Data) -> Bool {
        guard let img = UIImage(data: data) else { return false }
        // Keep it a sensible size (a banner, not a 48 MP photo).
        let maxW: CGFloat = 1600
        let scale = min(1, maxW / max(img.size.width, 1))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpg = resized.jpegData(compressionQuality: 0.82) else { return false }
        let wrote = (try? jpg.write(to: url, options: .atomic)) != nil
        try? jpg.write(to: docURL, options: .atomic)
        saveKeychain(jpg)
        cached = UIImage(data: jpg) ?? resized
        return wrote || cached != nil
    }

    static func remove() {
        cached = nil
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: docURL)
        deleteKeychain()
    }

    private static func saveKeychain(_ data: Data) {
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
    }

    private static func loadKeychain() -> Data? {
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
    }

    private static func deleteKeychain() {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: kcAccount,
        ]
        SecItemDelete(base as CFDictionary)
    }
}

/// Fills its frame with the image, cropped around a saved focus point and zoom.
struct FocusedFillImage: View {
    let image: UIImage
    var focusX: Double = 0.5
    var focusY: Double = 0.5
    var zoom: Double = 1

    var body: some View {
        GeometryReader { geo in
            let size = fittedSize(geo.size)
            let dx: CGFloat = (geo.size.width - size.width) * CGFloat(focusX)
            let dy: CGFloat = (geo.size.height - size.height) * CGFloat(focusY)
            Image(uiImage: image).resizable()
                .frame(width: size.width, height: size.height)
                .offset(x: dx, y: dy)
        }
        .clipped()
    }

    private func fittedSize(_ box: CGSize) -> CGSize {
        let iw: CGFloat = max(image.size.width, 1)
        let ih: CGFloat = max(image.size.height, 1)
        let fill: CGFloat = max(box.width / iw, box.height / ih)
        let scale: CGFloat = fill * CGFloat(max(zoom, 1))
        return CGSize(width: iw * scale, height: ih * scale)
    }
}

extension ProfileBackground {
    static let xKey = "profileBackgroundX"
    static let yKey = "profileBackgroundY"
    static let zoomKey = "profileBackgroundZoom"
}

/// Settings row: pick, preview (tap to pan & pinch), or remove the background.
struct ProfileBackgroundSettings: View {
    @AppStorage(ProfileBackground.revKey) private var rev = 0
    @AppStorage(ProfileBackground.xKey) private var focusX = 0.5
    @AppStorage(ProfileBackground.yKey) private var focusY = 0.5
    @AppStorage(ProfileBackground.zoomKey) private var zoom = 1.0
    @AppStorage("profileUsername") private var myUsername = ""
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var profile: Profile?
    @State private var editing = false
    @State private var failed = false

    var body: some View {
        Section {
            if let image {
                Button { editing = true } label: {
                    ProfileHeaderMock(image: image, focusX: focusX, focusY: focusY, zoom: zoom,
                                      username: myUsername, profile: profile)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .topTrailing) {
                            Label("Adjust", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.black.opacity(0.55), in: Capsule())
                                .padding(10)
                        }
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            PhotosPicker(selection: $item, matching: .images) {
                Label(image == nil ? "Choose Image" : "Change Image", systemImage: "photo")
            }
            if image != nil && (focusX != 0.5 || focusY != 0.5 || zoom != 1) {
                Button("Reset Position") { resetPosition() }
            }
            if image != nil {
                Button("Remove Background", role: .destructive) {
                    ProfileBackground.remove(); image = nil; resetPosition(); rev += 1
                }
            }
        } header: {
            Text("Profile Background")
        } footer: {
            Text(failed ? "Couldn't use that image. Try another one."
                 : (image == nil ? "Shown behind the top of your profile. Only on this phone."
                    : "Tap the preview to drag and pinch the image into place."))
        }
        .onAppear { image = ProfileBackground.load() }
        .task(id: myUsername) {
            guard !myUsername.isEmpty, profile == nil else { return }
            profile = try? await AOTYAPI.shared.profile(username: myUsername)
        }
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
        .sheet(isPresented: $editing) {
            if let image {
                ProfileBackgroundEditor(image: image, username: myUsername, profile: profile,
                                        focusX: $focusX, focusY: $focusY, zoom: $zoom)
            }
        }
    }

    private func resetPosition() {
        focusX = 0.5; focusY = 0.5; zoom = 1
    }
}

/// Interactive drag + pinch editor showing the full-width profile header preview.
private struct ProfileBackgroundEditor: View {
    let image: UIImage
    let username: String
    let profile: Profile?
    @Binding var focusX: Double
    @Binding var focusY: Double
    @Binding var zoom: Double
    @Environment(\.dismiss) private var dismiss

    @State private var boxSize: CGSize = .zero
    @State private var dragStart: (Double, Double)?
    @State private var zoomStart: Double?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProfileHeaderMock(image: image, focusX: focusX, focusY: focusY, zoom: zoom,
                                  username: username, profile: profile)
                    .background {
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { boxSize = geo.size }
                                .onChange(of: geo.size) { _, s in boxSize = s }
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .simultaneousGesture(pinchGesture)
                    .onTapGesture(count: 2) {
                        withAnimation(.smooth) { focusX = 0.5; focusY = 0.5; zoom = 1 }
                    }

                Spacer()

                Text("Drag to move · Pinch to zoom · Double-tap to reset")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Position Background")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        withAnimation(.smooth) { focusX = 0.5; focusY = 0.5; zoom = 1 }
                    }
                    .disabled(focusX == 0.5 && focusY == 0.5 && zoom == 1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil { dragStart = (focusX, focusY) }
                guard let start = dragStart else { return }
                let slack = currentSlack()
                if slack.width > 1 {
                    let nx = start.0 - Double(value.translation.width / slack.width)
                    focusX = min(max(nx, 0), 1)
                }
                if slack.height > 1 {
                    let ny = start.1 - Double(value.translation.height / slack.height)
                    focusY = min(max(ny, 0), 1)
                }
            }
            .onEnded { _ in dragStart = nil }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomStart == nil { zoomStart = zoom }
                guard let start = zoomStart else { return }
                zoom = min(max(start * value.magnification, 1), 4)
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func currentSlack() -> CGSize {
        guard boxSize.width > 0, boxSize.height > 0 else { return .zero }
        let iw = max(image.size.width, 1)
        let ih = max(image.size.height, 1)
        let fill = max(boxSize.width / iw, boxSize.height / ih)
        let scale = fill * CGFloat(max(zoom, 1))
        return CGSize(width: max(0, iw * scale - boxSize.width),
                      height: max(0, ih * scale - boxSize.height))
    }
}

/// Renders a realistic preview of the user's profile header over the chosen background.
private struct ProfileHeaderMock: View {
    let image: UIImage
    let focusX: Double
    let focusY: Double
    let zoom: Double
    let username: String
    let profile: Profile?

    private var displayName: String {
        profile?.displayName ?? (username.isEmpty ? "Your Profile" : username)
    }

    var body: some View {
        let parts = UserProfileView.splitName(displayName)
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.frame(height: 120)
            HStack(spacing: 16) {
                Avatar(url: (profile?.avatar).flatMap(URL.init(string:)), name: displayName, size: 80)
                VStack(alignment: .leading, spacing: 2) {
                    Text(parts.name)
                        .font(.system(.title, design: .default).weight(.bold))
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .foregroundStyle((profile?.nameColor).map { Color(hex: $0) } ?? .primary)
                        .shadow(color: .black.opacity(0.95), radius: 2, x: 0, y: 1)
                        .shadow(color: .black.opacity(0.85), radius: 6, x: 0, y: 2)
                    if let handle = parts.handle {
                        Text(handle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.95), radius: 2, x: 0, y: 1)
                            .shadow(color: .black.opacity(0.75), radius: 4, x: 0, y: 2)
                    }
                }
            }
            if let stats = profile?.stats, !stats.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(stats.prefix(4).enumerated()), id: \.offset) { idx, s in
                        if idx > 0 { Divider().frame(height: 32) }
                        VStack(spacing: 3) {
                            Text(s.value)
                                .font(.system(.headline, design: .rounded).weight(.bold).monospacedDigit())
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(s.label.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.top, 12).padding(.horizontal, 16).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
        .background {
            FocusedFillImage(image: image, focusX: focusX, focusY: focusY, zoom: zoom)
                .overlay {
                    LinearGradient(stops: [.init(color: .black.opacity(0.05), location: 0),
                                           .init(color: .black.opacity(0.35), location: 0.45),
                                           .init(color: Color(.systemBackground), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .clipped()
        }
    }
}
