import SwiftUI

/// Releases with three feeds you can switch by tapping the picker or swiping sideways.
struct ReleasesView: View {
    enum Feed: String, CaseIterable, Identifiable {
        case thisWeek = "This Week", upcoming = "Upcoming", new = "New"
        var id: String { rawValue }
    }

    /// Singles have no upcoming list on AOTY.
    private var feeds: [Feed] { singles ? [.thisWeek, .new] : [.thisWeek, .upcoming, .new] }

    @State private var feed: Feed = .thisWeek
    @State private var singles = false     // always opens on Albums

    var body: some View {
        AppStack {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    AOTYLogo().frame(height: 30)
                    Spacer()
                    NotificationBell()
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 12)

                // Every feed stays alive (instant switching); only the selected one shows.
                ZStack {
                    ForEach(feeds) { f in
                        FeedList(feed: f, singles: singles)
                            .id("\(f.rawValue)-\(singles)")
                            .opacity(f == feed ? 1 : 0)
                            .allowsHitTesting(f == feed)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Feed switcher + Albums/Singles, floating above the tab bar.
                HStack(spacing: 12) {
                    GlassSegmented(selection: $feed, items: feeds.map { ($0, $0.rawValue) })
                    KindToggle(singles: $singles, iconOnly: true)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationTitle(singles ? "Singles" : "Releases")
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: singles) { if singles && feed == .upcoming { feed = .new } }
        }
    }
}

/// One feed's list. Each page keeps its own data, so swiping back is instant.
private struct FeedList: View {
    let feed: ReleasesView.Feed
    let singles: Bool
    @ObservedObject private var genreStore = GenreStore.shared
    @State private var albums: [AlbumBlock] = []
    @State private var page = 1
    @State private var canLoadMore = true
    @State private var loading = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        List {
            if let error, albums.isEmpty {
                ErrorView(message: error) { await reload() }
            } else if albums.isEmpty && !loading && loaded {
                ContentUnavailableView("Nothing here yet", systemImage: "square.stack", description: Text("Pull to refresh."))
            }

            ForEach(albums) { album in
                NavRow(value: album, artist: album.artist, album: album.title,
                       isSingle: singles || (album.mediaType?.lowercased().contains("single") ?? false), cover: album.coverURL) {
                    let date = album.releaseDate ?? genreStore.date(for: album.slug)
                    if feed == .upcoming {
                        AlbumRow(artist: album.artist, title: album.title, cover: album.coverURL, subtitle: date,
                                 coverSize: 84, genres: genreStore.label(for: album.slug), reserveLines: true)
                    } else {
                        AlbumRow(artist: album.artist, title: album.title, cover: album.coverURL, subtitle: date,
                                 critic: album.criticScore, user: album.userScore, mustHear: album.mustHear ?? false,
                                 coverSize: 84, genres: genreStore.label(for: album.slug), reserveLines: true)
                    }
                }
                    .onAppear {
                        genreStore.appeared(album.slug)
                        if album == albums.last { Task { await loadMore() } }
                    }
                    .onDisappear { genreStore.disappeared(album.slug) }
            }

            if loading { ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Color.clear) }
        }
        .listStyle(.plain)
        .refreshable { await refresh() }
        .task { if !loaded { await reload() } }
    }

    private func fetch(_ page: Int) async throws -> [AlbumBlock] {
        switch feed {
        case .thisWeek: return try await AOTYAPI.shared.thisWeek(page: page, singles: singles)
        case .new: return try await AOTYAPI.shared.releases(page: page, singles: singles)
        case .upcoming: return try await AOTYAPI.shared.upcoming(page: page, singles: singles)
        }
    }

    private func refresh() async {
        AOTYScraper.shared.bypassCache()
        let started = Date()
        var seen = Set<String>()
        if let list = try? await fetch(1).filter({ seen.insert($0.id).inserted }), !list.isEmpty {
            await ImageCache.shared.warm(list.prefix(6).map(\.coverURL), timeout: 0.6)
            let wait = 0.5 - Date().timeIntervalSince(started)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { albums = list; page = 1; canLoadMore = true; error = nil }
        }
    }

    private func reload() async {
        page = 1; canLoadMore = true; error = nil
        loading = true
        defer {
            loading = false; loaded = true
            NotificationCenter.default.post(name: .releasesReady, object: nil)   // lifts the launch screen
        }
        do {
            var seen = Set<String>()
            let list = try await fetch(1).filter { seen.insert($0.id).inserted }
            await ImageCache.shared.warm(list.prefix(6).map(\.coverURL), timeout: 0.6)
            albums = list
            if feed == .thisWeek, !singles {      // covers for the next launch screen
                UserDefaults.standard.set(list.prefix(3).map(\.cover), forKey: "splashCovers")
            }
            Task { await ImageCache.shared.warm(list.dropFirst(6).map(\.coverURL), timeout: 20) }
        } catch is CancellationError {
        } catch {
            let msg = error.localizedDescription
            self.error = (singles && feed == .upcoming && msg.contains("404"))
                ? "AOTY doesn't have an upcoming singles list. Switch to Albums for upcoming releases."
                : msg
            albums = []
        }
    }

    private func loadMore() async {
        guard !loading, canLoadMore else { return }
        loading = true; defer { loading = false }
        do {
            let fresh = try await fetch(page + 1).filter { n in !albums.contains { $0.id == n.id } }
            Task { await ImageCache.shared.warm(fresh.map(\.coverURL), timeout: 20) }
            if fresh.isEmpty { canLoadMore = false } else { albums += fresh; page += 1 }
        } catch { canLoadMore = false }
    }
}

/// One-tap Albums ⇄ Singles switch.
struct KindToggle: View {
    @Binding var singles: Bool
    var iconOnly = false
    var body: some View {
        if iconOnly {
            Button(action: toggle) {
                FloatingIcon(symbol: icon)
            }
            .floatingGlass()
            .accessibilityLabel(singles ? "Showing singles" : "Showing albums")
        } else {
            Button(action: toggle) {
                Label(singles ? "Singles" : "Albums", systemImage: icon)
                    .labelStyle(.titleAndIcon)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }
    private var icon: String { singles ? "square.stack" : "music.note" }
    private func toggle() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation { singles.toggle() }
    }
}

/// Icon inside a floating round glass button (Releases' Albums/Singles, Artist filter).
struct FloatingIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.title2.weight(.medium))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 46, height: 46)
    }
}

extension View {
    func floatingGlass() -> some View {
        self.buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }
}

/// The AOTY wordmark (template image, follows the text color).
struct AOTYLogo: View {
    var body: some View {
        Group {
            if let img = UIImage(named: "aoty-logo") {
                Image(uiImage: img).renderingMode(.template).resizable().scaledToFit()
            } else {
                Text("AOTY").font(.largeTitle.bold())
            }
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Album of the Year")
        .accessibilityAddTraits(.isHeader)
    }
}


/// AOTY notifications: a bell with a red badge for unread ones; tap opens them on AOTY.
struct NotificationBell: View {
    @State private var count = 0
    @State private var href = "/notifications/"
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: count > 0 ? "bell.badge" : "bell")
                .font(.title3.weight(.medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(count > 0 ? Color.red : Color.primary, Color.primary)
                .frame(width: 40, height: 40)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                            .background(.red, in: Capsule())
                            .offset(x: 4, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(count) notifications" : "Notifications")
        .sheet(isPresented: $showing, onDismiss: { Task { await check(fresh: true) } }) {
            if let u = URL(string: href, relativeTo: URL(string: "https://www.albumoftheyear.org")) {
                AOTYWebSheet(url: u.absoluteURL, title: "Notifications").accentTint()
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2))      // let the first page load first
            while !Task.isCancelled {
                await check(fresh: true)
                try? await Task.sleep(for: .seconds(180))
            }
        }
    }

    private func check(fresh: Bool) async {
        guard let me = try? await AOTYAPI.shared.me(refresh: fresh), let n = me.notifications else { return }
        count = n.count ?? 0
        if let h = n.href, !h.isEmpty { href = h }
    }
}
