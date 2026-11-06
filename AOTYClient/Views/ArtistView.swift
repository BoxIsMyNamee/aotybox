import SwiftUI

/// Native artist page: big photo header, then the discography grouped by type. The floating
/// filter button loads AOTY's own lists (Featured, LP, EP, Single, Reissue, Live…).
struct ArtistView: View {
    let path: String?
    let fallbackName: String

    @State private var resolvedPath: String?
    @State private var artist: AOTYAPI.Artist?
    @State private var header: AOTYAPI.Artist?          // name + photo from the first load
    @State private var error: String?
    @State private var loading = false
    @State private var type = "featured"
    @AppStorage("artistHideEditions") private var hideEditions = false

    private static let types: [(String, String)] = [
        ("featured", "Featured"), ("all", "All"), ("lp", "LP"), ("ep", "EP"), ("single", "Single"),
        ("mixtape", "Mixtape"), ("compilation", "Compilation"), ("live", "Live"), ("reissue", "Reissue"),
        ("remix", "Remix"), ("demo", "Demo"), ("dj+mix", "DJ Mix"), ("instrumental", "Instrumental"),
        ("miscellaneous", "Miscellaneous"),
    ]
    private static let editionPattern = #"(?i)\b(deluxe|remaster(ed)?|anniversary|expanded|edition|reissue|bonus)\b"#
    private static let order = ["lp", "ep", "mixtape", "single", "compilation", "live", "remix", "soundtrack", "other"]

    private func typeKey(_ a: AlbumBlock) -> String {
        let t = (a.mediaType ?? "").lowercased()
        for k in ["live", "compilation", "remix", "soundtrack", "mixtape", "single", "ep", "lp", "album"] where t.contains(k) {
            return k == "album" ? "lp" : k
        }
        return "other"
    }
    private func sectionTitle(_ key: String) -> String {
        switch key {
        case "lp": "Albums"
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
    private var typeName: String { Self.types.first { $0.0 == type }?.1 ?? "Featured" }

    var body: some View {
        Group {
            if let artist { content(artist) }
            else if let error { ErrorView(message: error) { await load() } }
            else { ProgressView() }
        }
        .navigationTitle(header?.name ?? fallbackName)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            if artist != nil {
                Menu {
                    Picker("Type", selection: $type) {
                        ForEach(Self.types, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Divider()
                    Toggle("Hide deluxe & reissues", isOn: $hideEditions)
                } label: {
                    FloatingIcon(symbol: type == "featured" && !hideEditions
                                 ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
                .menuStyle(.button)
                .floatingGlass()
                .padding(.trailing, 20)
                .padding(.bottom, 16)
            }
        }
        .task { if artist == nil { await load() } }
        .onChange(of: type) { Task { await load() } }
    }

    private func visible(_ a: AOTYAPI.Artist) -> [AlbumBlock] {
        var seen = Set<String>()
        return a.albums.filter { seen.insert($0.url).inserted }
            .filter { !hideEditions || type == "reissue" || $0.title.range(of: Self.editionPattern, options: .regularExpression) == nil }
    }

    @ViewBuilder private func content(_ a: AOTYAPI.Artist) -> some View {
        let albums = visible(a)
        // Featured/All come mixed: group them. A single type is one list.
        let grouped = (type == "featured" || type == "all")
        let groups = grouped ? Dictionary(grouping: albums) { typeKey($0) } : [typeName: albums]
        let keys = grouped ? Self.order.filter { groups[$0] != nil } : [typeName]
        List {
            Section { hero(header ?? a, count: albums.count) }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            if loading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if albums.isEmpty {
                Section { Text("Nothing under \(typeName) for this artist.").foregroundStyle(.secondary) }
            }
            if !loading {
                ForEach(keys, id: \.self) { key in
                    Section(grouped ? sectionTitle(key) : key) {
                        ForEach(groups[key] ?? []) { album in
                            NavRow(value: album, artist: album.artist, album: album.title,
                                   isSingle: key == "single" || type == "single", cover: album.coverURL) {
                                AlbumRow(album, coverSize: 64)
                            }
                        }
                    }
                }
            }
            Color.clear.frame(height: 60).listRowBackground(Color.clear)   // room for the floating button
        }
        .listStyle(.insetGrouped)
        .environment(\.swipeRowBackground, Color(.secondarySystemGroupedBackground))
    }

    /// Wide photo across the top with the name over a soft fade.
    private func hero(_ a: AOTYAPI.Artist, count: Int) -> some View {
        ZStack(alignment: .bottomLeading) {
            CachedImage(url: a.image.flatMap(URL.init(string:))) {
                Rectangle().fill(.quaternary.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(a.name).font(.largeTitle.bold()).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.6)
                Text("\(typeName) · \(count) release\(count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func load() async {
        error = nil
        do {
            var p = resolvedPath ?? path
            if p == nil { p = await AOTYAPI.shared.findArtistPath(name: fallbackName) }
            guard let base = p else { error = "Couldn't find \(fallbackName) on AOTY."; return }
            resolvedPath = base
            loading = artist != nil
            defer { loading = false }
            let cleanBase = base.components(separatedBy: "?").first ?? base
            let a = try await AOTYAPI.shared.artist(path: type == "featured" ? cleanBase : cleanBase + "?type=" + type)
            await ImageCache.shared.warm([a.image.flatMap(URL.init(string:))] + a.albums.prefix(6).map(\.coverURL))
            if header == nil { header = a }
            artist = a
            Task { await ImageCache.shared.warm(a.albums.map(\.coverURL), timeout: 30) }
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }
}
