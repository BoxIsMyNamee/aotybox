import SwiftUI

struct SearchView: View {
    @State private var resetID = UUID()
    var body: some View {
        AppStack { SearchContent() }
            .id(resetID)
            .onReceive(NotificationCenter.default.publisher(for: .resetSearch)) { _ in resetID = UUID() }
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
    @State private var suggestions: [AOTYAPI.Suggestion] = []
    @State private var albums: [AlbumBlock] = []
    @State private var artists: [AOTYAPI.ArtistHit] = []
    @State private var searchError: String?

    private var recents: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(recentJSON.utf8))) ?? []
    }

    var body: some View {
        Group {
            if !submitted.isEmpty { results }
            else if !query.trimmingCharacters(in: .whitespaces).isEmpty { suggestionList }
            else { idle }
        }
        .tabTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Albums, artists, songs")
        .onSubmit(of: .search) { run(query) }
        .onReceive(NotificationCenter.default.publisher(for: .openLearn)) { n in
            guard let r = n.object as? SongRoute else { return }
            push(r)
        }
        .onChange(of: query) {
            if query.isEmpty { submitted = "" }
            else if query != submitted { submitted = "" }
        }
        // As you type: AOTY's own suggestions (debounced).
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2, submitted.isEmpty else { suggestions = []; return }
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            let s = await AOTYAPI.shared.suggestions(q)
            if !Task.isCancelled, query.trimmingCharacters(in: .whitespaces) == q { suggestions = s }
        }
        .task { if thisWeek.isEmpty { thisWeek = Array(((try? await AOTYAPI.shared.upcoming()) ?? []).prefix(24)) } }
    }

    // MARK: Idle

    private var idle: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NowPlayingCard()
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
                        Text("Upcoming").font(.title3.bold())
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                            ForEach(thisWeek) { a in
                                VStack(alignment: .leading, spacing: 4) {
                                    CachedImage(url: a.coverURL) { RoundedRectangle(cornerRadius: 8).fill(.quaternary) }
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(a.title).font(.caption.weight(.semibold)).lineLimit(1)
                                    Text(a.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    if let d = a.releaseDate, !d.isEmpty {
                                        Text(d).font(.caption2.weight(.medium)).foregroundStyle(.tint).lineLimit(1)
                                    }
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

    // MARK: Suggestions

    private var suggestionList: some View {
        List {
            let rec = recents.filter { $0.localizedCaseInsensitiveContains(query) && $0 != query }.prefix(3)
            ForEach(Array(rec), id: \.self) { r in
                Button { query = r; run(r) } label: {
                    Label(r, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
                }
            }
            ForEach(suggestions) { sg in
                Button { pick(sg) } label: {
                    HStack(spacing: 12) {
                        if sg.kind == "artist" {
                            Avatar(url: sg.image.flatMap(URL.init(string:)), name: sg.label, size: 40)
                        } else if let i = sg.image, let u = URL(string: i) {
                            Cover(url: u, size: 40)
                        } else {
                            Image(systemName: icon(sg.kind)).font(.body).foregroundStyle(.secondary).frame(width: 40, height: 40)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sg.label).foregroundStyle(.primary).lineLimit(1)
                            if let sub = sg.sub { Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { run(query) } label: {
                Label("Search for \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}", systemImage: "magnifyingglass")
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    private func icon(_ kind: String?) -> String {
        switch kind?.lowercased() { case "artist": "person"; case "song", "track": "music.note"; case "user": "person.circle"; default: "opticaldisc" }
    }

    private func pick(_ sg: AOTYAPI.Suggestion) {
        let path = sg.url.flatMap { URL(string: $0)?.path } ?? ""
        if path.contains("/album/") {
            remember(sg.label)
            push(AlbumRoute(slug: AlbumSlug.from(sg.url ?? ""), title: sg.label))
        } else if path.contains("/artist/") {
            remember(sg.label)
            push(ArtistRoute(path: path, name: sg.label))
        } else {
            query = sg.label; run(sg.label)
        }
    }

    // MARK: Results (in app)

    private var results: some View {
        List {
            if loading && albums.isEmpty && artists.isEmpty {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if albums.isEmpty && artists.isEmpty {
                ContentUnavailableView.search(text: submitted).listRowSeparator(.hidden)
            }
            if !artists.isEmpty {
                Section("Artists") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(artists.prefix(12)) { a in
                                Button { push(ArtistRoute(path: a.path, name: a.name)) } label: {
                                    VStack(spacing: 6) {
                                        Avatar(url: a.image.flatMap(URL.init(string:)), name: a.name, size: 72)
                                        Text(a.name).font(.caption).foregroundStyle(.primary).lineLimit(2)
                                            .multilineTextAlignment(.center).frame(width: 84)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            if !albums.isEmpty {
                Section("Albums") {
                    ForEach(albums) { a in
                        NavRow(value: a, artist: a.artist, album: a.title, isSingle: false, cover: a.coverURL) {
                            AlbumRow(artist: a.artist, title: a.title, cover: a.coverURL, subtitle: a.releaseDate,
                                     critic: a.criticScore, user: a.userScore, mustHear: a.mustHear ?? false, coverSize: 64)
                        }
                    }
                }
            }
            if let searchError { Text(searchError).font(.caption).foregroundStyle(.secondary) }
        }
        .scrollDismissesKeyboard(.immediately)
        .task(id: submitted) { await loadResults() }
    }

    private func loadResults() async {
        let q = submitted
        guard !q.isEmpty else { return }
        loading = true; defer { loading = false }
        albums = []; artists = []; searchError = nil
        async let al = try? AOTYAPI.shared.searchAlbums(q)
        async let ar = try? AOTYAPI.shared.searchArtists(q)
        let (a1, a2) = await (al, ar)
        guard q == submitted else { return }
        albums = a1 ?? []
        // AOTY also lists empty stub artists that share a name (no picture, no releases); drop those
        // when an artist with that name and a picture is there.
        let all = a2 ?? []
        let pictured = Set(all.filter { $0.image != nil }.map { $0.name.lowercased() })
        artists = all.filter { $0.image != nil || !pictured.contains($0.name.lowercased()) }
        if a1 == nil && a2 == nil { searchError = "Couldn't reach AOTY. Try again." }
    }

    private func remember(_ q: String) {
        var list = recents.filter { $0.caseInsensitiveCompare(q) != .orderedSame }
        list.insert(q, at: 0)
        save(Array(list.prefix(12)))
    }

    // MARK: Actions

    private func run(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        submitted = q
        suggestions = []
        remember(q)
    }

    private func remove(_ r: String) { withAnimation { save(recents.filter { $0 != r }) } }

    private func save(_ list: [String]) {
        if let d = try? JSONEncoder().encode(list), let s = String(data: d, encoding: .utf8) { recentJSON = s }
    }
}
