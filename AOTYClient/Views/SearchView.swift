import SwiftUI

struct SearchView: View {
    @AppStorage(AOTYAPI.sourceKey) private var source = "device"
    @State private var query = ""
    @State private var submitted = ""
    @State private var results: [AlbumBlock] = []
    @State private var loading = false
    @State private var error: String?
    @State private var path: [String] = []   // album slugs

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if source == "device" { webResults } else { apiResults }
            }
            .navigationTitle("Search")
            .navigationDestination(for: String.self) { AlbumDetailView(slug: $0, fallbackTitle: "Album") }
            .searchable(text: $query, prompt: "Albums & artists")
            .onSubmit(of: .search) { Task { await run() } }
            .onChange(of: query) { if query.isEmpty { results = []; error = nil; submitted = "" } }
        }
    }

    // On-device mode: AOTY's own search page, with album taps opening the native page.
    @ViewBuilder private var webResults: some View {
        if let url = searchURL {
            AOTYWebView(url: url, isLoading: $loading, onAlbumTap: { path.append($0) })
                .overlay(alignment: .top) { if loading { ProgressView().padding(8) } }
        } else {
            ContentUnavailableView("Search AOTY", systemImage: "magnifyingglass",
                                   description: Text("Results come from albumoftheyear.org. Tap an album to open it here."))
        }
    }

    private var searchURL: URL? {
        guard !submitted.isEmpty else { return nil }
        var c = URLComponents(string: "https://www.albumoftheyear.org/search/albums/")!
        c.queryItems = [URLQueryItem(name: "q", value: submitted)]
        return c.url
    }

    // Community API mode: native list.
    private var apiResults: some View {
        List {
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            ForEach(results) { album in
                Button { if let s = album.slug { path.append(s) } } label: { AlbumRow(album) }
                    .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .overlay {
            if loading { ProgressView() }
            else if results.isEmpty && !submitted.isEmpty && error == nil { ContentUnavailableView.search(text: submitted) }
            else if submitted.isEmpty {
                ContentUnavailableView("Search albums", systemImage: "magnifyingglass",
                                       description: Text("Press Search to look up an album or artist."))
            }
        }
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        submitted = q
        guard source != "device" else { return }
        loading = true; error = nil; defer { loading = false }
        do { results = try await AOTYAPI.shared.searchAlbums(q) }
        catch { self.error = error.localizedDescription; results = [] }
    }
}
