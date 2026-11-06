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
            Rectangle().fill(.clear)
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

    var body: some View {
        HStack(spacing: 12) {
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
                if let genres { Text(genres).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 4)
            if critic != nil && user != nil && coverSize > 60 {
                // Two scores next to big art: stack them so the art keeps its room.
                VStack(alignment: .trailing, spacing: 6) {
                    MiniScore(label: "Critic", score: critic)
                    MiniScore(label: "User", score: user)
                }
            } else {
                if critic != nil { ScoreBadge(label: "Critic", score: critic) }
                if user != nil { ScoreBadge(label: "User", score: user) }
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

/// Compact horizontal score: "88  Critic".
struct MiniScore: View {
    let label: String
    let score: Double?
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(score.map { String(Int($0.rounded())) } ?? "NR")
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 34, minHeight: 24)
                .background(scoreColor(score), in: RoundedRectangle(cornerRadius: 5))
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
    @State private var showFull = false
    @Environment(\.push) private var push

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    if let slug = review.userSlug { push(UserRoute(username: slug, name: review.username, avatar: review.avatar)) }
                } label: {
                    HStack(spacing: 10) {
                        Avatar(url: review.avatarURL, name: review.username)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(review.username).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
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
            if !review.text.isEmpty {
                Text(review.text).font(.callout).foregroundStyle(.secondary).lineLimit(lineLimit)
            }
            HStack(spacing: 14) {
                if let likes = review.likes, likes > 0 {
                    Label("\(likes)", systemImage: "heart").font(.caption).foregroundStyle(.tertiary)
                }
                if review.isTruncated == true || (lineLimit != nil && review.text.count > 280) {
                    Text("Read full review").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                }
            }
        }
        .padding(.vertical, 4)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .contentShape(Rectangle())
        .onTapGesture { if review.url != nil { showFull = true } }
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
