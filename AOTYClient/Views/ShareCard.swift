import SwiftUI
import UIKit

/// Everything a review share card shows.
struct ShareCardData: Hashable, Identifiable {
    var title: String
    var artist: String
    var cover: URL?
    var score: Double?
    var text: String
    var author: String
    var authorColor: String?
    var avatar: URL?
    /// When the text is AOTY's cut-off copy: where the whole review lives.
    var fullURL: String? = nil
    var id: String { title + artist + author }
}

/// Who wrote the reviews on a screen (so rows can put their name on a share card).
struct ShareAuthor: Equatable { var name: String; var color: String?; var avatar: URL? }
private struct ShareAuthorKey: EnvironmentKey { static let defaultValue: ShareAuthor? = nil }
extension EnvironmentValues {
    var shareAuthor: ShareAuthor? {
        get { self[ShareAuthorKey.self] }
        set { self[ShareAuthorKey.self] = newValue }
    }
}

/// Which album the reviews on a screen are about.
struct ShareAlbum: Equatable { var title: String; var artist: String; var cover: URL? }
private struct ShareAlbumKey: EnvironmentKey { static let defaultValue: ShareAlbum? = nil }
extension EnvironmentValues {
    var shareAlbum: ShareAlbum? {
        get { self[ShareAlbumKey.self] }
        set { self[ShareAlbumKey.self] = newValue }
    }
}

/// The card itself: blurred cover backdrop, cover + title, the score with its bar, the whole review,
/// and who wrote it. Drawn with images already in hand so it can be rendered to a picture.
struct ShareCardView: View {
    let data: ShareCardData
    let cover: UIImage?
    let avatar: UIImage?

    private var bodyFont: Font {
        switch data.text.count {
        case ..<240: .system(size: 19, weight: .regular)
        case ..<600: .system(size: 16, weight: .regular)
        case ..<1200: .system(size: 13.5, weight: .regular)
        default: .system(size: 11.5, weight: .regular)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Cover, title, artist and score centered on top; the review below.
            VStack(spacing: 10) {
                Group {
                    if let cover { Image(uiImage: cover).resizable().scaledToFill() }
                    else { Rectangle().fill(.white.opacity(0.12)) }
                }
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                .padding(.bottom, 4)
                Text(data.title).font(.system(size: 22, weight: .bold)).lineLimit(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(data.artist).font(.system(size: 15, weight: .medium)).opacity(0.75).lineLimit(2)
                    .multilineTextAlignment(.center)
                if let s = data.score {
                    VStack(spacing: 6) {
                        Text(String(Int(s.rounded())))
                            .font(.system(size: 46, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.18))
                            Capsule().fill(scoreColor(s)).frame(width: 120 * s / 100)
                        }
                        .frame(width: 120, height: 6)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)

            Text(data.text)
                .font(bodyFont)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Group {
                    if let avatar { Image(uiImage: avatar).resizable().scaledToFill() }
                    else { Circle().fill(.white.opacity(0.15)) }
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                Text(data.author).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(data.authorColor.map { Color(hex: $0) } ?? .white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let logo = UIImage(named: "aoty-logo") {
                    Image(uiImage: logo).renderingMode(.template).resizable().scaledToFit()
                        .frame(height: 16).opacity(0.7)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(width: 380)
        .background {
            ZStack {
                Color(white: 0.08)
                if let cover {
                    Image(uiImage: cover).resizable().scaledToFill()
                        .blur(radius: 40).opacity(0.55)
                }
                LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}

/// Hold a review → this sheet: the card as a picture, with Share (Messages, Instagram, Save Image…).
struct ShareCardSheet: View {
    let data: ShareCardData
    @State private var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    } else {
                        ProgressView().frame(height: 300)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Share Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if let image {
                        let pic = Image(uiImage: image)
                        ShareLink(item: pic, preview: SharePreview("\(data.title) review", image: pic)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await render() }
    }

    private func render() async {
        var data = self.data
        if let u = data.fullURL, let full = try? await AOTYAPI.shared.fullReview(url: u, preview: data.text) { data.text = full }
        data.text = data.text.replacingOccurrences(of: #"\s*(\.\.\.|…)?\s*read more\s*$"#, with: "…", options: [.regularExpression, .caseInsensitive])
        let cover: UIImage? = if let u = data.cover { await ImageCache.shared.image(for: u) } else { nil }
        let avatar: UIImage? = if let u = data.avatar { await ImageCache.shared.image(for: u) } else { nil }
        let r = ImageRenderer(content: ShareCardView(data: data, cover: cover, avatar: avatar))
        r.scale = 3
        r.isOpaque = false
        image = r.uiImage
    }
}

extension View {
    /// Hold to see the share card and share it as an image.
    @ViewBuilder
    func reviewShareMenu(_ data: ShareCardData?) -> some View {
        if let data { modifier(ReviewShareMenu(data: data)) } else { self }
    }
}

private struct ReviewShareMenu: ViewModifier {
    let data: ShareCardData
    @State private var sharing: ShareCardData?
    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button { sharing = data } label: { Label("Share as Image", systemImage: "photo.on.rectangle") }
            } preview: {
                ShareCardView(data: data,
                              cover: data.cover.flatMap { ImageCache.shared.cachedIncludingDisk($0) },
                              avatar: data.avatar.flatMap { ImageCache.shared.cachedIncludingDisk($0) })
            }
            .sheet(item: $sharing) { d in ShareCardSheet(data: d).accentTint() }
    }
}
