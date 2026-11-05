import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var results: [AlbumBlock] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red).font(.callout) }
                ForEach(results) { album in
                    NavigationLink(value: album) { AlbumRow(album) }
                }
            }
            .listStyle(.plain)
            .overlay {
                if loading { ProgressView() }
                else if results.isEmpty && !query.isEmpty && error == nil {
                    ContentUnavailableView.search(text: query)
                } else if query.isEmpty {
                    ContentUnavailableView("Search albums", systemImage: "magnifyingglass",
                                           description: Text("Press Search to look up an album or artist."))
                }
            }
            .navigationTitle("Search")
            .navigationDestination(for: AlbumBlock.self) { AlbumDetailView(slug: $0.slug, fallbackTitle: $0.title) }
            .searchable(text: $query, prompt: "Albums")
            // Search only on submit (no search-as-you-type) to keep request volume low.
            .onSubmit(of: .search) { Task { await run() } }
            .onChange(of: query) { if query.isEmpty { results = []; error = nil } }
        }
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        loading = true; error = nil; defer { loading = false }
        do { results = try await AOTYAPI.shared.searchAlbums(q) }
        catch { self.error = error.localizedDescription; results = [] }
    }
}
