import SwiftUI
import PhotosUI
import UIKit

/// Your own picture behind the top of your profile. Kept on this device only.
enum ProfileBackground {
    static let revKey = "profileBackgroundRev"
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profileBackground.jpg")
    }
    static func load() -> UIImage? { UIImage(contentsOfFile: url.path) }
    static func save(_ data: Data) -> Bool {
        guard let img = UIImage(data: data) else { return false }
        // Keep it a sensible size (a banner, not a 48 MP photo).
        let maxW: CGFloat = 1600
        let scale = min(1, maxW / max(img.size.width, 1))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpg = resized.jpegData(compressionQuality: 0.85) else { return false }
        return (try? jpg.write(to: url, options: .atomic)) != nil
    }
    static func remove() { try? FileManager.default.removeItem(at: url) }
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
