import SwiftUI

struct SearchView: View {
    var body: some View {
        AppStack { SearchContent() }
    }
}

/// Search: recent searches + this week's covers when idle; AOTY's results when searching
/// (album taps open the native album page).
private struct SearchContent: View {
    @AppStorage("recentSearches") private var recentJSON = "[]"
    @Environment(\.push) private var push
    @State private var query = ""
    @State private var submitted = ""
    @State private var loading = false
    @State private var thisWeek: [AlbumBlock] = []

    private var recents: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(recentJSON.utf8))) ?? []
    }

    var body: some View {
        Group {
            if let url = searchURL {
                AOTYWebView(url: url, isLoading: $loading,
                            onAlbumTap: { push(AlbumRoute(slug: $0, title: "Album")) },
                            onArtistTap: { push(ArtistRoute(path: $0, name: "Artist")) })
                    .overlay(alignment: .top) { if loading { ProgressView().padding(8) } }
                    .ignoresSafeArea(edges: .bottom)
            } else {
                idle
            }
        }
        .tabTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Albums, artists, songs")
        .searchSuggestions {
            if !query.isEmpty {
                ForEach(recents.filter { $0.localizedCaseInsensitiveContains(query) && $0 != query }.prefix(5), id: \.self) { r in
                    Label(r, systemImage: "clock.arrow.circlepath").searchCompletion(r)
                }
            }
        }
        .onSubmit(of: .search) { run(query) }
        .onChange(of: query) { if query.isEmpty { submitted = "" } }
        .task { if thisWeek.isEmpty { thisWeek = Array(((try? await AOTYAPI.shared.thisWeek()) ?? []).prefix(18)) } }
    }

    // MARK: Idle

    private var idle: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !recents.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Recent").font(.title3.bold())
                            Spacer()
                            Button("Clear") { withAnimation { recentJSON = "[]" } }.font(.subheadline)
                        }
                        ForEach(recents, id: \.self) { r in
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                                Text(r).foregroundStyle(.primary)
                                Spacer()
                                Button { remove(r) } label: { Image(systemName: "xmark").font(.caption).foregroundStyle(.tertiary) }
                                    .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .onTapGesture { query = r; run(r) }
                            Divider()
                        }
                    }
                }

                if !thisWeek.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("New This Week").font(.title3.bold())
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                            ForEach(thisWeek) { a in
                                VStack(alignment: .leading, spacing: 4) {
                                    CachedImage(url: a.coverURL) { RoundedRectangle(cornerRadius: 8).fill(.quaternary) }
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(a.title).font(.caption.weight(.semibold)).lineLimit(1)
                                    Text(a.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { push(a) }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: Actions

    private var searchURL: URL? {
        guard !submitted.isEmpty else { return nil }
        var c = URLComponents(string: "https://www.albumoftheyear.org/search/albums/")!
        c.queryItems = [URLQueryItem(name: "q", value: submitted)]
        return c.url
    }

    private func run(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        submitted = q
        var list = recents.filter { $0.caseInsensitiveCompare(q) != .orderedSame }
        list.insert(q, at: 0)
        save(Array(list.prefix(12)))
    }

    private func remove(_ r: String) { withAnimation { save(recents.filter { $0 != r }) } }

    private func save(_ list: [String]) {
        if let d = try? JSONEncoder().encode(list), let s = String(data: d, encoding: .utf8) { recentJSON = s }
    }
}
