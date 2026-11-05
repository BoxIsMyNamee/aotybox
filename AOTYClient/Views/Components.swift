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
            if let count { Text("\(count)").font(.caption2).foregroundStyle(.tertiary) }
        }
    }

    private var color: Color {
        guard let s = score else { return .gray }
        if s >= 70 { return .green }
        if s >= 50 { return .yellow.opacity(0.9) }
        return .red
    }
}

struct Cover: View {
    let url: URL?
    var size: CGFloat = 56

    var body: some View {
        AsyncImage(url: url, transaction: .init(animation: .easeIn(duration: 0.15))) { phase in
            switch phase {
            case let .success(image): image.resizable().scaledToFill()
            default: Rectangle().fill(.quaternary).overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            }
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

    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                Text("\(rank)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28)
            }
            Cover(url: cover)
            VStack(alignment: .leading, spacing: 2) {
                Text(artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 4) {
                    Text(title).font(.body.weight(.semibold)).lineLimit(2)
                    if mustHear { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange) }
                }
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 4)
            if critic != nil { ScoreBadge(label: "Critic", score: critic) }
            if user != nil { ScoreBadge(label: "User", score: user) }
        }
        .padding(.vertical, 2)
    }
}

extension AlbumRow {
    init(_ a: AlbumBlock) {
        self.init(artist: a.artist, title: a.title, cover: a.coverURL, subtitle: a.releaseDate,
                  critic: a.criticScore, user: a.userScore, mustHear: a.mustHear ?? false)
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
        Text("Data from albumoftheyear.org via the unofficial AOTY API. Not affiliated with Album of the Year.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .listRowBackground(Color.clear)
    }
}
