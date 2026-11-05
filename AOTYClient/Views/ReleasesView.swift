import SwiftUI

struct ReleasesView: View {
    enum Feed: String, CaseIterable, Identifiable {
        case thisWeek = "This Week", new = "New", upcoming = "Upcoming"
        var id: String { rawValue }
    }

    @ObservedObject private var genreStore = GenreStore.shared
    @State private var feed: Feed = .thisWeek
    @State private var albums: [AlbumBlock] = []
    @State private var page = 1
    @State private var canLoadMore = true
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Picker("Feed", selection: $feed) {
                    ForEach(Feed.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                if let error, albums.isEmpty {
                    ErrorView(message: error) { await reload() }
                } else if albums.isEmpty && !loading {
                    ContentUnavailableView("Nothing here yet", systemImage: "square.stack",
                                           description: Text("Pull to refresh."))
                }

                ForEach(albums) { album in
                    NavigationLink(value: album) { AlbumRow(album, coverSize: 84, genres: genreStore.label(for: album.slug)) }
                        .onAppear {
                            genreStore.appeared(album.slug)
                            if album == albums.last { Task { await loadMore() } }
                        }
                        .onDisappear { genreStore.disappeared(album.slug) }
                }

                if loading { ProgressView().frame(maxWidth: .infinity) }
                if !albums.isEmpty && !canLoadMore { AttributionFooter() }
            }
            .listStyle(.plain)
            .navigationTitle("Releases")
            .navigationDestination(for: AlbumBlock.self) { AlbumDetailView(slug: $0.slug, fallbackTitle: $0.title) }
            .refreshable { await reload() }
            .task(id: feed) { await reload() }
        }
    }

    private func fetch(_ page: Int) async throws -> [AlbumBlock] {
        switch feed {
        case .thisWeek: return try await AOTYAPI.shared.thisWeek(page: page)
        case .new: return try await AOTYAPI.shared.releases(page: page)
        case .upcoming: return try await AOTYAPI.shared.upcoming(page: page)
        }
    }

    private func reload() async {
        page = 1; canLoadMore = true; error = nil
        loading = true; defer { loading = false }
        do { albums = dedupe(try await fetch(1)) }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription; albums = [] }
    }

    private func loadMore() async {
        guard !loading, canLoadMore else { return }
        loading = true; defer { loading = false }
        do {
            let next = try await fetch(page + 1)
            let fresh = next.filter { n in !albums.contains { $0.id == n.id } }
            if fresh.isEmpty { canLoadMore = false } else { albums += fresh; page += 1 }
        } catch { canLoadMore = false }
    }

    private func dedupe(_ list: [AlbumBlock]) -> [AlbumBlock] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.id).inserted }
    }
}
