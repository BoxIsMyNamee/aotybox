import SwiftUI

struct AlbumDetailView: View {
    let slug: String?
    let fallbackTitle: String

    @State private var album: AlbumDetail?
    @State private var error: String?
    @State private var showAllTracks = false
    @State private var showRateSheet = false
    @State private var showCover = false
    @State private var fallbackTracks: [Track] = []
    @State private var fallbackSource: String?
    @State private var showChat = false
    @State private var chat = ChatThread()
    @Environment(\.openURL) private var openURL
    @Environment(\.push) private var push

    var body: some View {
        Group {
            if let album {
                content(album)
                    // Pull down for fresh reviews and scores.
                    .refreshable {
                        if let slug { await AOTYScraper.shared.forget("/album/\(slug).php") }
                        await AOTYScraper.shared.bypassCache()
                        await load()
                    }
            }
            else if let error { ErrorView(message: error) { await load() } }
            else { ProgressView() }
        }
        .navigationTitle(album?.title ?? fallbackTitle)
        .inlineNavTitle()
        .toolbar {
            if let album, let url = URL(string: album.url) {
                ToolbarItem(placement: .automatic) {
                    ShareLink(item: url)
                }
                #if os(macOS)
                ToolbarSpacer(.fixed)
                #endif
                ToolbarItem(placement: .automatic) {
                    Button { openURL(url) } label: { Image(systemName: "safari") }
                }
            }
            #if os(macOS)
            ToolbarSpacer(.fixed)
            MacSearchToolbarItem()
            #endif
        }
        .task { await load() }
        .platformFullScreenCover(isPresented: $showCover) {
            if let album, let url = album.coverURL { CoverViewer(url: url, title: album.title).accentTint() }
        }
        .sheet(isPresented: $showChat) {
            if let album { AlbumChatSheet(album: album, tracks: tracks(album), thread: chat).accentTint() }
        }
        .sheet(isPresented: $showRateSheet) {
            if let album, let url = URL(string: album.url) {
                AOTYWebSheet(url: url, title: "Rate & Review").accentTint()
            }
        }
    }

    private func appleMusicLink(_ a: AlbumDetail) -> String? {
        a.streamingLinks?.first { $0.platform.lowercased().contains("apple") || $0.url.contains("music.apple.com") }?.url
    }

    private func load() async {
        guard let slug else { error = "This item has no album link."; return }
        error = nil
        do {
            let a = try await AOTYAPI.shared.album(slug: slug)
            await ImageCache.shared.warm([a.coverURL] + (a.popularUserReviews ?? []).prefix(3).map(\.avatarURL))
            // Critic logos sit further down: fetch them without holding the page back.
            Task { await ImageCache.shared.warm((a.reviews ?? []).prefix(15).map { $0.image.flatMap(URL.init(string:)) }, timeout: 20) }
            album = a
        }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
        if let album, album.tracklist?.isEmpty ?? true, fallbackTracks.isEmpty { await loadFallbackTracks(album) }
    }

    private func artistPath(_ a: AlbumDetail) -> String? {
        guard let s = a.artistUrl, let u = URL(string: s, relativeTo: URL(string: "https://www.albumoftheyear.org")) else { return nil }
        return u.path.hasPrefix("/artist/") ? u.path : nil
    }

    private func isSingle(_ a: AlbumDetail) -> Bool { (a.format ?? "").lowercased().contains("single") }

    private func tracks(_ a: AlbumDetail) -> [Track] {
        if let t = a.tracklist, !t.isEmpty { return t }
        return fallbackTracks
    }

    /// AOTY has no tracklist (common for singles): try Apple Music, then Genius,
    /// and for a single fall back to the title track.
    private func loadFallbackTracks(_ a: AlbumDetail) async {
        let am = await MusicAppLink.tracklist(artist: a.artist, album: a.title, appleMusicURL: appleMusicLink(a))
        if !am.isEmpty { fallbackTracks = am; fallbackSource = "Apple Music"; return }
        let g = await GeniusClient.albumTracks(artist: a.artist, album: a.title)
        if !g.isEmpty { fallbackTracks = g; fallbackSource = "Genius"; return }
        if isSingle(a) {
            let title = a.title.replacingOccurrences(of: #"\s+-\s+(Single|EP)$"#, with: "", options: [.regularExpression, .caseInsensitive])
            fallbackTracks = [Track(number: 1, title: title, length: nil, rating: nil, features: nil)]
            fallbackSource = nil
        }
    }

    @ViewBuilder
    private func content(_ a: AlbumDetail) -> some View {
        List {
            // Header
            Section {
                VStack(spacing: 14) {
                    Cover(url: a.coverURL, size: 256).shadow(radius: 10)
                        .tapAndHold(tap: { showCover = true }, hold: { showChat = true })
                        .accessibilityLabel("View cover art")
                        .accessibilityHint("Hold to ask the AI about this \(isSingle(a) ? "single" : "album")")
                    VStack(spacing: 5) {
                        Text(a.title)
                            #if os(macOS)
                            .font(.largeTitle.bold())
                            #else
                            .font(.title2.bold())
                            #endif
                            .multilineTextAlignment(.center)
                        Button { push(ArtistRoute(path: artistPath(a) ?? "", name: a.artist)) } label: {
                            Text(a.artist)
                                #if os(macOS)
                                .font(.title3.weight(.semibold))
                                #else
                                .font(.headline)
                                #endif
                                .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                        Text([a.datePublished, a.format, a.label].compactMap { $0 }.joined(separator: " · "))
                            #if os(macOS)
                            .font(.subheadline)
                            #else
                            .font(.caption)
                            #endif
                            .foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    }
                    HStack(spacing: 32) {
                        ScoreBadge(label: "Critic", score: a.criticScore, count: a.criticCount)
                        ScoreBadge(label: "User", score: a.userScore, count: a.userCount)
                    }
                    if let r = a.criticRanking ?? a.userRanking {
                        Text("#\(r.rank) of \(r.year.map(String.init) ?? "the year")")
                            #if os(macOS)
                            .font(.subheadline.weight(.semibold))
                            #else
                            .font(.caption.weight(.semibold))
                            #endif
                            .foregroundStyle(.tint)
                    }
                    if let genres = a.genres, !genres.isEmpty {
                        Text(genres.joined(separator: ", "))
                            #if os(macOS)
                            .font(.subheadline)
                            #else
                            .font(.caption)
                            #endif
                            .foregroundStyle(.secondary)
                    }
                    #if os(macOS)
                    HStack(spacing: 14) {
                        let accent = Color(hex: UserDefaults.standard.string(forKey: Theme.key) ?? Theme.defaultHex)
                        Button {
                            push(Learn.route(artist: a.artist, album: a.title, song: nil, isSingle: isSingle(a), cover: a.coverURL))
                        } label: {
                            Label("Learn about this \(isSingle(a) ? "Song" : "Album")", systemImage: "magnifyingglass")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 20).padding(.vertical, 11)
                                .background(Color.platformSecondaryGroupedBackground, in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await MusicAppLink.open(artist: a.artist, album: a.title, song: nil, appleMusicURL: appleMusicLink(a)) }
                        } label: {
                            Label("Listen on \(MusicAppLink.name)", systemImage: "play.circle")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 20).padding(.vertical, 11)
                                .background(Color.platformSecondaryGroupedBackground, in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 6)
                    #endif
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            #if os(iOS)
            Section {
                Button {
                    push(Learn.route(artist: a.artist, album: a.title, song: nil, isSingle: isSingle(a), cover: a.coverURL))
                } label: {
                    Label("Learn about this \(isSingle(a) ? "Song" : "Album")", systemImage: "magnifyingglass")
                }
                // Same group as Learn (one card, two rows).
                Button {
                    Task { await MusicAppLink.open(artist: a.artist, album: a.title, song: nil, appleMusicURL: appleMusicLink(a)) }
                } label: {
                    Label("Listen on \(MusicAppLink.name)", systemImage: "play.circle")
                }
            }
            #endif

            // Your score, review, and Listened / Like / Save (signed in)
            if let me = a.me, me.albumID != nil {
                Section {
                    MyAlbumCard(box: me, slug: slug, album: ShareAlbum(title: a.title, artist: a.artist, cover: a.coverURL))
                        .id(me)      // a refresh brings in the latest score / review
                        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                        #if os(macOS)
                        .padding(20)
                        .background(Color.platformSecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        #endif
                }
            }

            // Tracklist
            let trackList = tracks(a)
            if !trackList.isEmpty {
                Section {
                    ForEach(showAllTracks ? trackList : Array(trackList.prefix(8))) { t in
                        NavRow(value: SongRoute(artist: a.artist, title: t.title, album: a.title, cover: a.coverURL, artistPath: artistPath(a)),
                               artist: a.artist, album: a.title, song: t.title, appleMusicURL: appleMusicLink(a), cover: a.coverURL) {
                            HStack(spacing: 12) {
                                Text("\(t.number)")
                                    #if os(macOS)
                                    .font(.title3.monospacedDigit())
                                    #endif
                                    .foregroundStyle(.secondary).monospacedDigit().frame(width: 28, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title)
                                        #if os(macOS)
                                        .font(.title3.weight(.medium))
                                        #endif
                                        .foregroundStyle(.primary)
                                    if let f = t.features, !f.isEmpty {
                                        Text("feat. " + f.joined(separator: ", "))
                                            #if os(macOS)
                                            .font(.subheadline)
                                            #else
                                            .font(.caption)
                                            #endif
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if let r = t.rating {
                                    Text(String(Int(r.rounded())))
                                        #if os(macOS)
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        #else
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        #endif
                                        .foregroundStyle(scoreColor(r))
                                }
                                if let l = t.length {
                                    Text(l)
                                        #if os(macOS)
                                        .font(.subheadline.monospacedDigit())
                                        #else
                                        .font(.caption.monospacedDigit())
                                        #endif
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            #if os(macOS)
                            .padding(.vertical, 4)
                            #endif
                        }
                    }
                    if trackList.count > 8 {
                        Button(showAllTracks ? "Show Less…" : "Show More…") { withAnimation { showAllTracks.toggle() } }
                    }
                } header: {
                    Text("Tracklist" + (a.totalLength.map { " · \($0)" } ?? ""))
                } footer: {
                    if let fallbackSource { Text("Tracklist from \(fallbackSource)") }
                }
            }

            // User reviews
            if let reviews = a.popularUserReviews, !reviews.isEmpty {
                Section("Popular User Reviews") {
                    ForEach(reviews.prefix(3)) { r in
                        UserReviewRow(review: r, learn: { push(Learn.route(artist: a.artist, album: a.title, song: nil, isSingle: isSingle(a), cover: a.coverURL)) })
                            .environment(\.shareAlbum, ShareAlbum(title: a.title, artist: a.artist, cover: a.coverURL))
                    }
                    if let slug {
                        Button { push(UserReviewsRoute(slug: slug, title: a.title, artist: a.artist, cover: a.coverURL)) } label: {
                            Label("See all user reviews", systemImage: "text.bubble")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            } else if let slug {
                Section {
                    Button { push(UserReviewsRoute(slug: slug, title: a.title, artist: a.artist, cover: a.coverURL)) } label: {
                        Label("User reviews", systemImage: "text.bubble").foregroundStyle(.tint)
                    }
                }
            }

            // Critic reviews
            if let reviews = a.reviews, !reviews.isEmpty {
                Section("Critic Reviews") {
                    ForEach(reviews.prefix(15)) { r in
                        HStack(alignment: .top, spacing: 14) {
                            CachedImage(url: r.image.flatMap(URL.init(string:))) {
                                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                                    .overlay(Text(String(r.publication.prefix(1))).font(.caption.bold()).foregroundStyle(.secondary))
                            }
                            #if os(macOS)
                            .frame(width: 48, height: 48)
                            #else
                            .frame(width: 36, height: 36)
                            #endif
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.publication)
                                            #if os(macOS)
                                            .font(.headline)
                                            #else
                                            .font(.subheadline.weight(.semibold))
                                            #endif
                                        if let author = r.author, !author.isEmpty {
                                            Text(author)
                                                #if os(macOS)
                                                .font(.caption)
                                                #else
                                                .font(.caption2)
                                                #endif
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    if let s = r.score {
                                        Text(String(Int(s.rounded())))
                                            #if os(macOS)
                                            .font(.title3.bold().monospacedDigit())
                                            #else
                                            .font(.headline.monospacedDigit())
                                            #endif
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(scoreColor(s).opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                                if !r.text.isEmpty {
                                    Text(r.text)
                                        #if os(macOS)
                                        .font(.system(size: 15))
                                        #else
                                        .font(.callout)
                                        #endif
                                        .foregroundStyle(.secondary).lineLimit(5)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { if let s = r.url, let u = URL(string: s) { openURL(u) } }
                    }
                }
            }

            // Similar
            if let similar = a.similarAlbums, !similar.isEmpty {
                Section("Similar Albums") {
                    ForEach(similar.prefix(10)) { s in
                        NavRow(value: s, artist: s.artist, album: s.title, cover: s.coverURL) { AlbumRow(s) }
                    }
                }
            }

        }
        .insetGroupedListStyle()
        .macPagePadding()
        .environment(\.swipeRowBackground, Color.platformSecondaryGroupedBackground)
    }
}

// MARK: - Album chat (hold the cover)

struct AlbumChatSheet: View {
    let album: AlbumDetail
    let tracks: [Track]
    let thread: ChatThread
    @Environment(\.dismiss) private var dismiss

    private var kind: String { (album.format ?? "").lowercased().contains("single") ? "single" : "album" }

    private var context: String {
        var lines = ["\(kind.capitalized): \(album.title)", "Artist: \(album.artist)"]
        if let d = album.datePublished { lines.append("Released: \(d)") }
        if let f = album.format { lines.append("Format: \(f)") }
        if let l = album.label { lines.append("Label: \(l)") }
        if let g = album.genres, !g.isEmpty { lines.append("Genres: " + g.joined(separator: ", ")) }
        if let c = album.criticScore { lines.append("AOTY critic score: \(Int(c)) from \(album.criticCount ?? 0) reviews") }
        if let u = album.userScore { lines.append("AOTY user score: \(u) from \(album.userCount ?? 0) ratings") }
        if !tracks.isEmpty { lines.append("Tracklist: " + tracks.map { "\($0.number). \($0.title)" }.joined(separator: "; ")) }
        let critics = (album.reviews ?? []).prefix(5).map { "\($0.publication): \($0.text.prefix(200))" }
        if !critics.isEmpty { lines.append("Critic excerpts:\n" + critics.joined(separator: "\n")) }
        return "Context from Album of the Year:\n" + lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Cover(url: album.coverURL, size: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.title).font(.headline).lineLimit(2)
                            Text(album.artist).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    SongChatView(context: context, thread: thread, nothingOnGenius: false, subject: kind)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Ask AI")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if !thread.messages.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { thread.messages.removeAll(); thread.error = nil } label: { Image(systemName: "arrow.counterclockwise") }
                            .accessibilityLabel("New chat")
                    }
                }
            }
        }
        .onAppear { thread.attach(ChatThread.key("album", album.artist, album.title)) }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
