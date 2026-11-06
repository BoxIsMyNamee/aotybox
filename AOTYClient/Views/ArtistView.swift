import SwiftUI

/// Native artist page: photo, name, and the discography grouped by type (LPs, EPs, singles…).
struct ArtistView: View {
    let path: String
    let fallbackName: String
    @State private var artist: AOTYAPI.Artist?
    @State private var error: String?

    private static let order = ["lp", "album", "ep", "mixtape", "single", "compilation", "live", "remix", "soundtrack"]

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
        .task { if artist == nil { await load() } }
    }

    @ViewBuilder private func content(_ a: AOTYAPI.Artist) -> some View {
        var seen = Set<String>()
        let unique = a.albums.filter { seen.insert($0.url).inserted }
        let groups = Dictionary(grouping: unique) { typeKey($0) }
        let keys = (Self.order + ["other"]).filter { groups[$0] != nil }
        List {
            Section {
                VStack(spacing: 10) {
                    Avatar(url: a.image.flatMap(URL.init(string:)), name: a.name, size: 120)
                    Text(a.name).font(.title2.bold()).multilineTextAlignment(.center)
                    Text("\(unique.count) releases").font(.caption).foregroundStyle(.secondary)
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
            let a = try await AOTYAPI.shared.artist(path: path)
            await ImageCache.shared.warm([a.image.flatMap(URL.init(string:))] + a.albums.prefix(6).map(\.coverURL))
            artist = a
            Task { await ImageCache.shared.warm(a.albums.map(\.coverURL), timeout: 30) }
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }
}
