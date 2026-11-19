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

/// Settings row: pick, preview, position, or remove the background.
struct ProfileBackgroundSettings: View {
    @AppStorage(ProfileBackground.revKey) private var rev = 0
    @AppStorage(ProfileBackground.xKey) private var focusX = 0.5
    @AppStorage(ProfileBackground.yKey) private var focusY = 0.5
    @AppStorage(ProfileBackground.zoomKey) private var zoom = 1.0
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Section {
            if let image {
                FocusedFillImage(image: image, focusX: focusX, focusY: focusY, zoom: zoom)
                    .frame(height: 200).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                positionControls
            }
            PhotosPicker(selection: $item, matching: .images) {
                Label(image == nil ? "Choose Image" : "Change Image", systemImage: "photo")
            }
            if image != nil {
                Button("Remove Background", role: .destructive) {
                    ProfileBackground.remove(); image = nil; resetPosition(); rev += 1
                }
            }
        } header: {
            Text("Profile Background")
        } footer: {
            Text(failed ? "Couldn't use that image. Try another one." : "Shown behind the top of your profile. Only on this phone.")
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

    @ViewBuilder private var positionControls: some View {
        slider("Horizontal", value: $focusX, range: 0...1)
        slider("Vertical", value: $focusY, range: 0...1)
        slider("Zoom", value: $zoom, range: 1...3)
        if focusX != 0.5 || focusY != 0.5 || zoom != 1 {
            Button("Reset Position") { resetPosition() }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            Slider(value: value, in: range)
        }
    }

    private func resetPosition() {
        focusX = 0.5; focusY = 0.5; zoom = 1
    }
}
