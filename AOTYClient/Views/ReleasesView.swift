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
    @AppStorage("releasesSingles") private var singles = false

    var body: some View {
        AppStack {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    AOTYLogo().frame(height: 30)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 12)

                Picker("Feed", selection: $feed.animation(.easeInOut(duration: 0.25))) {
                    ForEach(feeds) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                TabView(selection: $feed) {
                    ForEach(feeds) { f in
                        FeedList(feed: f, singles: singles)
                            .id("\(f.rawValue)-\(singles)")
                            .tag(f)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .overlay(alignment: .bottomTrailing) {
                // Floating Albums/Singles switch, bottom right above the tab bar.
                KindToggle(singles: $singles, iconOnly: true)
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
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
                    if feed == .upcoming {
                        AlbumRow(artist: album.artist, title: album.title, cover: album.coverURL, subtitle: album.releaseDate,
                                 coverSize: 84, genres: genreStore.label(for: album.slug))
                    } else {
                        AlbumRow(album, coverSize: 84, genres: genreStore.label(for: album.slug))
                    }
                }
                    .onAppear {
                        genreStore.appeared(album.slug)
                        if album == albums.last { Task { await loadMore() } }
                    }
                    .onDisappear { genreStore.disappeared(album.slug) }
            }

            if loading { ProgressView().frame(maxWidth: .infinity) }
        }
        .listStyle(.plain)
        .refreshable { await reload() }
        .task { if !loaded { await reload() } }
    }

    private func fetch(_ page: Int) async throws -> [AlbumBlock] {
        switch feed {
        case .thisWeek: return try await AOTYAPI.shared.thisWeek(page: page, singles: singles)
        case .new: return try await AOTYAPI.shared.releases(page: page, singles: singles)
        case .upcoming: return try await AOTYAPI.shared.upcoming(page: page, singles: singles)
        }
    }

    private func reload() async {
        page = 1; canLoadMore = true; error = nil
        loading = true; defer { loading = false; loaded = true }
        do {
            var seen = Set<String>()
            let list = try await fetch(1).filter { seen.insert($0.id).inserted }
            await ImageCache.shared.warm(list.prefix(6).map(\.coverURL), timeout: 0.6)
            albums = list
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
                Image(systemName: icon)
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
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
