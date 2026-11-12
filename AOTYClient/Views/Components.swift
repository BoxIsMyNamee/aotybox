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
        CachedImage(url: url) {
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let rank {
                Text("\(rank)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28)
            }
            Cover(url: cover, size: coverSize)
            VStack(alignment: .leading, spacing: 2) {
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
        .padding(.vertical, 2)
    }
}

extension AlbumRow {
    init(_ a: AlbumBlock, coverSize: CGFloat = 56, genres: String? = nil) {
        self.init(artist: a.artist, title: a.title, cover: a.coverURL, subtitle: a.releaseDate,
                  critic: a.criticScore, user: a.userScore, mustHear: a.mustHear ?? false, coverSize: coverSize, genres: genres)
    }
}

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
