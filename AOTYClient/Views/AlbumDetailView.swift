import SwiftUI

struct AlbumDetailView: View {
    let slug: String?
    let fallbackTitle: String

    @State private var album: AlbumDetail?
    @State private var error: String?
    @State private var showAllTracks = false
    @State private var showRateSheet = false
    @State private var showCover = false
    @State private var openingTrack: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let album { content(album) }
            else if let error { ErrorView(message: error) { await load() } }
            else { ProgressView() }
        }
        .navigationTitle(album?.title ?? fallbackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let album, let url = URL(string: album.url) {
                ShareLink(item: url)
                Button { openURL(url) } label: { Image(systemName: "safari") }
            }
        }
        .task { await load() }
        .fullScreenCover(isPresented: $showCover) {
            if let album, let url = album.coverURL { CoverViewer(url: url, title: album.title) }
        }
        .sheet(isPresented: $showRateSheet) {
            if let album, let url = URL(string: album.url) {
                AOTYWebSheet(url: url, title: "Rate & Review")
            }
        }
    }

    private func openGenius(artist: String, track: Track) {
        guard openingTrack == nil else { return }
        openingTrack = track.id
        Task {
            let url = await Genius.url(artist: artist, title: track.title)
            openingTrack = nil
            openURL(url)
        }
    }

    private func load() async {
        guard let slug else { error = "This item has no album link."; return }
        error = nil
        do { album = try await AOTYAPI.shared.album(slug: slug) }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }

    @ViewBuilder
    private func content(_ a: AlbumDetail) -> some View {
        List {
            // Header
            Section {
                VStack(spacing: 12) {
                    Button { showCover = true } label: {
                        Cover(url: a.coverURL, size: 240).shadow(radius: 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View cover art")
                    VStack(spacing: 4) {
                        Text(a.title).font(.title2.bold()).multilineTextAlignment(.center)
                        Text(a.artist).font(.headline).foregroundStyle(.secondary)
                        Text([a.datePublished, a.format, a.label].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    }
                    HStack(spacing: 28) {
                        ScoreBadge(label: "Critic", score: a.criticScore, count: a.criticCount)
                        ScoreBadge(label: "User", score: a.userScore, count: a.userCount)
                    }
                    if let r = a.criticRanking ?? a.userRanking {
                        Text("#\(r.rank) of \(r.year.map(String.init) ?? "the year")")
                            .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    }
                    if let genres = a.genres, !genres.isEmpty {
                        Text(genres.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            // Rate / review on AOTY itself (uses your signed-in web session)
            Section {
                Button {
                    showRateSheet = true
                } label: {
                    Label("Rate or review on AOTY", systemImage: "star.bubble")
                }
            }

            // Listen
            if let links = a.streamingLinks, !links.isEmpty {
                Section("Listen") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(links, id: \.url) { link in
                                if let url = URL(string: link.url) {
                                    Button(link.platform.capitalized) { openURL(url) }.buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
            }

            // Tracklist
            if let tracks = a.tracklist, !tracks.isEmpty {
                Section("Tracklist" + (a.totalLength.map { " · \($0)" } ?? "")) {
                    ForEach(showAllTracks ? tracks : Array(tracks.prefix(8))) { t in
                        Button { openGenius(artist: a.artist, track: t) } label: {
                            HStack {
                                Text("\(t.number)").foregroundStyle(.secondary).monospacedDigit().frame(width: 24, alignment: .trailing)
                                VStack(alignment: .leading) {
                                    Text(t.title).foregroundStyle(.primary)
                                    if let f = t.features, !f.isEmpty {
                                        Text("feat. " + f.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if openingTrack == t.id {
                                    ProgressView().controlSize(.small)
                                } else {
                                    if let r = t.rating { Text(String(Int(r.rounded()))).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                                    if let l = t.length { Text(l).font(.caption.monospacedDigit()).foregroundStyle(.tertiary) }
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if tracks.count > 8 {
                        Button(showAllTracks ? "Show Less…" : "Show More…") { withAnimation { showAllTracks.toggle() } }
                    }
                }
            }

            // Critic reviews
            if let reviews = a.reviews, !reviews.isEmpty {
                Section("Critic Reviews") {
                    ForEach(reviews.prefix(15)) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(r.publication).font(.subheadline.weight(.semibold))
                                Spacer()
                                if let s = r.score { Text(String(Int(s.rounded()))).font(.headline.monospacedDigit()) }
                            }
                            if !r.text.isEmpty { Text(r.text).font(.callout).foregroundStyle(.secondary).lineLimit(4) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if let s = r.url, let u = URL(string: s) { openURL(u) } }
                    }
                }
            }

            // User reviews
            if let reviews = a.popularUserReviews, !reviews.isEmpty {
                Section("Popular User Reviews") {
                    ForEach(reviews.prefix(5)) { r in UserReviewRow(review: r) }
                    if let slug {
                        NavigationLink {
                            UserReviewsView(slug: slug, title: a.title)
                        } label: {
                            Label("See all user reviews", systemImage: "text.bubble")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } else if let slug {
                Section {
                    NavigationLink { UserReviewsView(slug: slug, title: a.title) } label: {
                        Label("User reviews", systemImage: "text.bubble").foregroundStyle(.orange)
                    }
                }
            }

            // Similar
            if let similar = a.similarAlbums, !similar.isEmpty {
                Section("Similar Albums") {
                    ForEach(similar.prefix(10)) { s in
                        NavigationLink { AlbumDetailView(slug: s.slug, fallbackTitle: s.title) } label: { AlbumRow(s) }
                    }
                }
            }

            AttributionFooter()
        }
        .listStyle(.insetGrouped)
    }
}
