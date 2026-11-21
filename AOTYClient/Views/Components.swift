import SwiftUI

/// AOTY-style score pill: green ≥ 70, yellow ≥ 50, red below.
struct ScoreBadge: View {
    let label: String
    let score: Double?
    var count: Int? = nil

    var body: some View {
        VStack(spacing: 2) {
            Text(score.map { String(Int($0.rounded())) } ?? "NR")
                .font(.system(.headline, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 40, minHeight: 28)
                .background(color, in: RoundedRectangle(cornerRadius: 6))
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(count.map { "\($0)" } ?? " ").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var color: Color { scoreColor(score) }
}

struct Cover: View {
    let url: URL?
    var size: CGFloat = 56

    var body: some View {
        CachedImage(url: url, maxPixel: size * 3) {
            Rectangle().fill(.quaternary.opacity(0.5))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 100 ? 10 : 4))
    }
}

struct AlbumRow: View {
    let artist: String
    let title: String
    let cover: URL?
    var subtitle: String? = nil
    var rank: Int? = nil
    var critic: Double? = nil
    var user: Double? = nil
    var mustHear: Bool = false
    var coverSize: CGFloat = 56
    var genres: String? = nil
    /// Keep the date and genre lines' space even before they arrive, so rows never shift.
    var reserveLines: Bool = false

    private var effectiveCoverSize: CGFloat {
        #if os(macOS)
        max(coverSize, 78)
        #else
        coverSize
        #endif
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let rank {
                Text("\(rank)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28)
            }
            Cover(url: cover, size: effectiveCoverSize)
            VStack(alignment: .leading, spacing: 3) {
                Text(artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 4) {
                    Text(title).font(.body.weight(.semibold)).lineLimit(2)
                    if mustHear { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.tint) }
                }
                // Date first, genres under it — same order everywhere.
                if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                else if reserveLines { Text(" ").font(.caption) }
                if let genres, !genres.isEmpty { Text(genres).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                else if reserveLines { Text(" ").font(.caption) }
            }
            Spacer(minLength: 4)
            if critic != nil || user != nil {
                VStack(alignment: .leading, spacing: 10) {
                    if let critic { SiteScore(score: critic, label: "critic") }
                    if let user { SiteScore(score: user, label: "user") }
                }
                .frame(width: 72, alignment: .leading)
            }
        }
        #if os(macOS)
        .padding(.vertical, 6)
        #else
        .padding(.vertical, 2)
        #endif
    }
}

extension AlbumRow {
    init(_ a: AlbumBlock, coverSize: CGFloat = 56, genres: String? = nil) {
        self.init(artist: a.artist, title: a.title, cover: a.coverURL, subtitle: a.releaseDate,
                  critic: a.criticScore, user: a.userScore, mustHear: a.mustHear ?? false, coverSize: coverSize, genres: genres)
    }
}

#if os(macOS)
/// Responsive desktop album grid: 4–5 large cards per row on a typical Mac window.
let macAlbumGridColumns: [GridItem] = [
    GridItem(.adaptive(minimum: 185, maximum: 235), spacing: 24, alignment: .top)
]

/// Desktop AOTY-style album card for Releases, Charts, Artist, and Search grids on macOS.
struct MacAlbumCard<Value: Hashable>: View {
    let value: Value
    let artist: String
    let title: String
    let cover: URL?
    var subtitle: String? = nil
    var accentSubtitle: Bool = false
    var rank: Int? = nil
    var critic: Double? = nil
    var user: Double? = nil
    var mustHear: Bool = false
    var genres: String? = nil
    var isSingle: Bool = false
    @Environment(\.push) private var push
    @State private var hovered = false

    var body: some View {
        Button { push(value) } label: {
            VStack(alignment: .leading, spacing: 8) {
                CachedImage(url: cover, maxPixel: 512) {
                    Rectangle().fill(.quaternary.opacity(0.5))
                }
                .aspectRatio(1, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(hovered ? 0.22 : 0.08), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if let rank {
                        Text("#\(rank)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.75), in: Capsule())
                            .padding(8)
                    }
                }
                .shadow(color: .black.opacity(hovered ? 0.35 : 0.18), radius: hovered ? 10 : 5, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if mustHear {
                            Image(systemName: "star.fill").font(.caption2).foregroundStyle(.tint)
                        }
                    }
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption.weight(accentSubtitle ? .semibold : .regular))
                            .foregroundStyle(accentSubtitle ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                            .lineLimit(1)
                    }
                    if let genres, !genres.isEmpty {
                        Text(genres)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if critic != nil || user != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        if let critic { SiteScore(score: critic, label: "critic score") }
                        if let user { SiteScore(score: user, label: "user score") }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            Button {
                if isSingle {
                    push(SongRoute(artist: artist, title: title, album: nil, cover: cover))
                } else {
                    push(LearnAlbumRoute(artist: artist, album: title, cover: cover))
                }
            } label: {
                Label("Learn", systemImage: "book.pages")
            }
            Button {
                Task {
                    await MusicAppLink.open(
                        artist: artist,
                        album: isSingle ? nil : title,
                        song: isSingle ? title : nil,
                        appleMusicURL: nil
                    )
                }
            } label: {
                Label("Open in \(MusicAppLink.name)", systemImage: "music.note")
            }
        }
    }
}
#endif

/// AOTY-style score: the number with a thin colored bar under it and a small label.
struct SiteScore: View {
    let score: Double
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(String(Int(score.rounded())))
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(scoreColor(score)).frame(width: 38 * min(max(score, 0), 100) / 100)
            }
            .frame(width: 38, height: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) score \(Int(score.rounded()))")
    }
}

/// Compact horizontal score: "88  Critic".
struct MiniScore: View {
    let label: String
    let score: Double?
    var large = false
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(score.map { String(Int($0.rounded())) } ?? "NR")
                .font(.system(large ? .title3 : .subheadline, design: .rounded).weight(large ? .bold : .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: large ? 46 : 34, minHeight: large ? 32 : 24)
                .background(scoreColor(score), in: RoundedRectangle(cornerRadius: large ? 7 : 5))
        }
    }
}

func scoreColor(_ s: Double?) -> Color {
    guard let s else { return .gray }
    // Settings → Color-blind friendly scores: blue / orange / purple instead of green / yellow / red.
    if UserDefaults.standard.bool(forKey: "colorBlindScores") {
        if s >= 70 { return Color(red: 0.25, green: 0.55, blue: 0.95) }
        if s >= 50 { return Color(red: 0.98, green: 0.6, blue: 0.15) }
        return Color(red: 0.62, green: 0.35, blue: 0.85)
    }
    if s >= 70 { return .green }
    if s >= 50 { return .yellow.opacity(0.9) }
    return .red
}

/// One user review: avatar, name, score, text. Tapping a truncated review opens it in full on AOTY.
struct UserReviewRow: View {
    let review: UserReview
    var lineLimit: Int? = 6
    /// Swipe right: Learn about the album this review is for.
    var learn: (() -> Void)? = nil
    @State private var showFull = false
    @Environment(\.push) private var push
    @Environment(\.shareAlbum) private var album

    private var shareData: ShareCardData? {
        guard let album, !review.text.isEmpty else { return nil }
        return ShareCardData(title: album.title, artist: album.artist, cover: album.cover, score: review.rating,
                             text: review.text, author: review.username, authorColor: review.nameColor, avatar: review.avatarURL,
                             fullURL: review.isTruncated == true ? review.url : nil,
                             pageURL: review.url.flatMap { URL(string: $0, relativeTo: URL(string: "https://www.albumoftheyear.org"))?.absoluteURL })
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if review.url != nil { CommentButton(count: review.commentCount) { showFull = true } }
            HeartButton(reviewID: review.reviewId, liked: review.liked ?? false, likes: review.likes ?? 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    if let slug = review.userSlug { push(UserRoute(username: slug, name: review.username, avatar: review.avatar, nameColor: review.nameColor)) }
                } label: {
                    HStack(spacing: 10) {
                        Avatar(url: review.avatarURL, name: review.username)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(review.username).font(.subheadline.weight(.semibold))
                                .foregroundStyle(review.nameColor.map { Color(hex: $0) } ?? .primary)
                            if let d = review.date { Text(d).font(.caption2).foregroundStyle(.tertiary) }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(review.userSlug == nil)
                Spacer()
                if let r = review.rating {
                    Text(String(Int(r.rounded())))
                        .font(.headline.monospacedDigit())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(scoreColor(r).opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            let hasMore = review.isTruncated == true || (lineLimit != nil && review.text.count > 280)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(linkified(review.text)).font(.callout).foregroundStyle(.secondary).lineLimit(lineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !hasMore { actions }
            }
            if hasMore {
                HStack {
                    Text("Read full review").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    Spacer()
                    actions
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if review.url != nil { showFull = true } }
        .reviewShareMenu(shareData)
        .heartSwipe(reviewID: review.reviewId, liked: review.liked ?? false, likes: review.likes ?? 0, learn: learn,
                    view: review.url != nil ? { showFull = true } : nil)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .sheet(isPresented: $showFull) {
            if let s = review.url, let u = URL(string: s) { AOTYWebSheet(url: u, title: review.username).accentTint() }
        }
    }
}

struct ErrorView: View {
    let message: String
    let retry: () async -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Couldn't load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") { Task { await retry() } }.buttonStyle(.bordered)
        }
    }
}

struct AttributionFooter: View {
    var body: some View {
        Text("Data from albumoftheyear.org. Not affiliated with Album of the Year.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .listRowBackground(Color.clear)
    }
}
