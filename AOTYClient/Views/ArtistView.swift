import SwiftUI

/// Native artist page: photo, name, and the discography grouped by type (LPs, EPs, singles…).
struct ArtistView: View {
    let path: String?
    let fallbackName: String
    @State private var artist: AOTYAPI.Artist?
    @State private var error: String?
    @State private var filter: String = "all"
    @AppStorage("artistHideEditions") private var hideEditions = false

    private static let editionPattern = #"(?i)\b(deluxe|remaster(ed)?|anniversary|expanded|edition|reissue|bonus)\b"#

    private static let order = ["lp", "ep", "mixtape", "single", "compilation", "live", "remix", "soundtrack"]

    private func typeKey(_ a: AlbumBlock) -> String {
        let t = (a.mediaType ?? a.releaseDate ?? "").lowercased()
        // Most specific first, so "Live Albums" isn't filed under Albums.
        for k in ["live", "compilation", "remix", "soundtrack", "mixtape", "single", "ep", "lp", "album"] where t.contains(k) {
            return k == "album" ? "lp" : k
        }
        return "other"
    }
    private func title(_ key: String) -> String {
        switch key {
        case "lp", "album": "Albums"
        case "ep": "EPs"
        case "mixtape": "Mixtapes"
        case "single": "Singles"
        case "compilation": "Compilations"
        case "live": "Live"
        case "remix": "Remixes"
        case "soundtrack": "Soundtracks"
        default: "Other"
        }
    }

    var body: some View {
        Group {
            if let artist { content(artist) }
            else if let error { ErrorView(message: error) { await load() } }
            else { ProgressView() }
        }
        .navigationTitle(artist?.name ?? fallbackName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let artist {
                Menu {
                    Picker("Type", selection: $filter) {
                        Text("All").tag("all")
                        ForEach(keys(for: artist), id: \.self) { k in Text("\(title(k)) (\(groups(for: artist)[k]?.count ?? 0))").tag(k) }
                    }
                    Toggle("Hide deluxe & reissues", isOn: $hideEditions)
                } label: {
                    Image(systemName: filter == "all" && !hideEditions ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .task { if artist == nil { await load() } }
    }

    private func unique(_ a: AOTYAPI.Artist) -> [AlbumBlock] {
        var seen = Set<String>()
        return a.albums.filter { seen.insert($0.url).inserted }
            .filter { !hideEditions || $0.title.range(of: Self.editionPattern, options: .regularExpression) == nil }
    }
    private func groups(for a: AOTYAPI.Artist) -> [String: [AlbumBlock]] { Dictionary(grouping: unique(a)) { typeKey($0) } }
    private func keys(for a: AOTYAPI.Artist) -> [String] {
        let g = groups(for: a)
        return (Self.order + ["other"]).filter { g[$0] != nil }
    }

    @ViewBuilder private func content(_ a: AOTYAPI.Artist) -> some View {
        let unique = unique(a)
        let groups = groups(for: a)
        let keys = keys(for: a).filter { filter == "all" || $0 == filter }
        List {
            Section {
                VStack(spacing: 10) {
                    Avatar(url: a.image.flatMap(URL.init(string:)), name: a.name, size: 120)
                    Text(a.name).font(.title2.bold()).multilineTextAlignment(.center)
                    Text("\(unique.count) releases").font(.caption).foregroundStyle(.secondary)
                    if filter != "all" || hideEditions {
                        Button("Clear filters") { filter = "all"; hideEditions = false }.font(.caption.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            ForEach(keys, id: \.self) { key in
                Section(title(key)) {
                    ForEach(groups[key] ?? []) { album in
                        NavRow(value: album, artist: album.artist, album: album.title,
                               isSingle: key == "single", cover: album.coverURL) {
                            AlbumRow(album, coverSize: 64)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.swipeRowBackground, Color(.secondarySystemGroupedBackground))
    }

    private func load() async {
        error = nil
        do {
            var p = path
            if p == nil { p = await AOTYAPI.shared.findArtistPath(name: fallbackName) }
            guard let p else { error = "Couldn't find \(fallbackName) on AOTY."; return }
            let a = try await AOTYAPI.shared.artist(path: p)
            await ImageCache.shared.warm([a.image.flatMap(URL.init(string:))] + a.albums.prefix(6).map(\.coverURL))
            artist = a
            Task { await ImageCache.shared.warm(a.albums.map(\.coverURL), timeout: 30) }
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }
}
