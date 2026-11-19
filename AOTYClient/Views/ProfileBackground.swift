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

/// Settings row: pick, preview, or remove the background.
struct ProfileBackgroundSettings: View {
    @AppStorage(ProfileBackground.revKey) private var rev = 0
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Section {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(height: 120).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            PhotosPicker(selection: $item, matching: .images) {
                Label(image == nil ? "Choose Image" : "Change Image", systemImage: "photo")
            }
            if image != nil {
                Button("Remove Background", role: .destructive) {
                    ProfileBackground.remove(); image = nil; rev += 1
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
                    image = ProfileBackground.load(); rev += 1
                } else { failed = true }
                self.item = nil
            }
        }
    }
}
