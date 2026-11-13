import SwiftUI
import UIKit

/// Long-press → open the exact album or song in Marvis Pro (or Apple Music).
///
/// Marvis opens catalog items by Apple Music ID: marvis://open?id={ID}&type={album|song}.
/// IDs come from AOTY's own Apple Music link when we have it, otherwise from Apple's public
/// iTunes Search API. If nothing matches, it falls back to a Marvis search.
enum MusicAppLink {
    enum App: String, CaseIterable, Identifiable {
        case marvis, appleMusic
        var id: String { rawValue }
        var name: String { self == .marvis ? "Marvis Pro" : "Apple Music" }
    }

    static let appKey = "musicApp"
    static var app: App { App(rawValue: UserDefaults.standard.string(forKey: appKey) ?? "") ?? .marvis }

    /// How songs are opened in Marvis. Which one highlights the track depends on Marvis.
    enum SongStyle: String, CaseIterable, Identifiable {
        case songPage, albumTrack, songID
        var id: String { rawValue }
        var name: String {
            switch self {
            case .songPage: "Song page link"
            case .albumTrack: "Album link with track"
            case .songID: "Song ID"
            }
        }
    }
    static let songStyleKey = "marvisSongStyle"
    static var songStyle: SongStyle { SongStyle(rawValue: UserDefaults.standard.string(forKey: songStyleKey) ?? "") ?? .songPage }
    static var name: String { app.name }

    private static var storefront: String { (Locale.current.region?.identifier ?? "US").lowercased() }

    // MARK: Resolving Apple Music IDs

    private struct ITunesResponse: Decodable {
        struct Item: Decodable {
            let wrapperType: String?
            let collectionId: Int?
            let trackId: Int?
            let artistName: String?
            let collectionName: String?
            let trackName: String?
            var trackNumber: Int? = nil
            var discNumber: Int? = nil
            var trackTimeMillis: Int? = nil
        }
        let results: [Item]
    }

    private static func norm(_ s: String) -> String {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)   // (feat. …), [Deluxe]
            .replacingOccurrences(of: #"\s+(featuring|feat\.|ft\.|with)\s.*$"#, with: "", options: .regularExpression)   // "Guess featuring Billie Eilish - Single"
            .replacingOccurrences(of: #"\s+-\s+(single|ep)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&", with: "and")
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func itunes(_ path: String, _ items: [URLQueryItem]) async -> [ITunesResponse.Item] {
        var c = URLComponents(string: "https://itunes.apple.com/" + path)!
        c.queryItems = items + [URLQueryItem(name: "country", value: storefront)]
        guard let url = c.url,
              let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10)),
              let r = try? JSONDecoder().decode(ITunesResponse.self, from: data) else { return [] }
        return r.results
    }

    /// "https://music.apple.com/us/album/no-bad-memories/1234567890" → 1234567890
    static func albumID(fromAppleMusic url: String?) -> Int? {
        guard let url, url.contains("music.apple.com") || url.contains("itunes.apple.com") else { return nil }
        if let m = url.range(of: #"/album/[^/?]*/(?:id)?(\d+)"#, options: .regularExpression) {
            return Int(url[m].split(separator: "/").last.map { String($0).replacingOccurrences(of: "id", with: "") } ?? "")
        }
        if let m = url.range(of: #"/album/(?:id)?(\d+)"#, options: .regularExpression) {
            return Int(url[m].filter(\.isNumber))
        }
        return nil
    }

    private struct ArtistResponse: Decodable {
        struct Item: Decodable { let artistId: Int?; let artistName: String? }
        let results: [Item]
    }

    /// Album search first; Apple's album search misses brand-new releases, so fall back to the
    /// artist's full discography (lookup by artist ID), which does include them.
    static func findAlbum(artist: String, album: String) async -> Int? {
        let a = norm(artist), t = norm(album)
        func match(_ list: [ITunesResponse.Item]) -> Int? {
            let exact = list.first { $0.collectionId != nil && norm($0.collectionName ?? "") == t && norm($0.artistName ?? "").contains(a.prefix(8)) }
            let loose = list.first { $0.collectionId != nil && norm($0.collectionName ?? "").hasPrefix(t.prefix(10)) && norm($0.artistName ?? "").contains(a.prefix(5)) }
            return (exact ?? loose)?.collectionId
        }
        if let id = match(await itunes("search", [
            URLQueryItem(name: "term", value: "\(artist) \(album)"),
            URLQueryItem(name: "entity", value: "album"), URLQueryItem(name: "limit", value: "15"),
        ])) { return id }

        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [URLQueryItem(name: "term", value: artist), URLQueryItem(name: "entity", value: "musicArtist"),
                        URLQueryItem(name: "limit", value: "5"), URLQueryItem(name: "country", value: storefront)]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10)),
              let artists = try? JSONDecoder().decode(ArtistResponse.self, from: data).results,
              let artistID = (artists.first { norm($0.artistName ?? "") == a } ?? artists.first)?.artistId else { return nil }
        return match(await itunes("lookup", [
            URLQueryItem(name: "id", value: String(artistID)), URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "200"), URLQueryItem(name: "sort", value: "recent"),
        ]))
    }

    static func findSong(artist: String, song: String, album: String?, albumID: Int?) async -> (song: Int, album: Int?)? {
        let s = norm(song)
        // Best: look inside the known album so we get the exact track.
        if let albumID {
            let tracks = await itunes("lookup", [URLQueryItem(name: "id", value: String(albumID)), URLQueryItem(name: "entity", value: "song")])
                .filter { $0.wrapperType == "track" }
            if let t = tracks.first(where: { norm($0.trackName ?? "") == s }) ?? tracks.first(where: { norm($0.trackName ?? "").hasPrefix(s.prefix(10)) }),
               let id = t.trackId { return (id, albumID) }
        }
        let results = await itunes("search", [
            URLQueryItem(name: "term", value: "\(artist) \(song)"),
            URLQueryItem(name: "entity", value: "song"), URLQueryItem(name: "limit", value: "25"),
        ])
        let a = norm(artist), al = album.map(norm)
        let byArtist = results.filter { norm($0.artistName ?? "").contains(a.prefix(6)) && norm($0.trackName ?? "") == s }
        let pick = byArtist.first { al != nil && norm($0.collectionName ?? "") == al } ?? byArtist.first
            ?? results.first { norm($0.trackName ?? "").hasPrefix(s.prefix(10)) && norm($0.artistName ?? "").contains(a.prefix(5)) }
        guard let p = pick, let id = p.trackId else { return nil }
        return (id, p.collectionId)
    }

    // MARK: Tracklist fallback

    /// Apple Music's tracklist for an album or single (used when AOTY has none).
    static func tracklist(artist: String, album: String, appleMusicURL: String?) async -> [Track] {
        var id = albumID(fromAppleMusic: appleMusicURL)
        if id == nil { id = await findAlbum(artist: artist, album: album) }
        guard let id else { return [] }
        let items = await itunes("lookup", [URLQueryItem(name: "id", value: String(id)), URLQueryItem(name: "entity", value: "song")])
            .filter { $0.wrapperType == "track" && $0.trackName != nil }
            .sorted { ($0.discNumber ?? 1, $0.trackNumber ?? 0) < ($1.discNumber ?? 1, $1.trackNumber ?? 0) }
        let multiDisc = Set(items.map { $0.discNumber ?? 1 }).count > 1
        return items.enumerated().map { i, t in
            Track(number: multiDisc ? i + 1 : (t.trackNumber ?? i + 1), title: t.trackName ?? "",
                  length: t.trackTimeMillis.map { ms in String(format: "%d:%02d", ms / 60000, (ms / 1000) % 60) },
                  rating: nil, features: nil)
        }
    }

    /// Free-text album lookup ("the weeknd after hours") → name, artist and tracks. Used by Proof.
    /// Apple's free-text search often misses new releases or picks the wrong album, so the hit
    /// must actually look like what was typed; otherwise AOTY's own search finds the album and
    /// its tracklist (from AOTY, falling back to Apple's).
    static func searchAlbum(_ term: String) async -> (title: String, artist: String, tracks: [Track])? {
        let q = norm(term)
        let hits = await itunes("search", [URLQueryItem(name: "term", value: term),
                                           URLQueryItem(name: "entity", value: "album"), URLQueryItem(name: "limit", value: "10")])
        if let best = hits.first(where: { h in
            guard h.collectionId != nil else { return false }
            let t = norm(h.collectionName ?? "")
            return !t.isEmpty && q.contains(t.prefix(12))
        }), let id = best.collectionId {
            let tracks = await tracklist(artist: best.artistName ?? "", album: best.collectionName ?? "",
                                         appleMusicURL: "https://music.apple.com/us/album/x/\(id)")
            if !tracks.isEmpty {
                let title = (best.collectionName ?? "").replacingOccurrences(of: #"\s+-\s+(Single|EP)$"#, with: "", options: .regularExpression)
                return (title, best.artistName ?? "", tracks)
            }
        }
        // AOTY's search box.
        let sugg = await AOTYAPI.shared.suggestions(term)
        guard let s = sugg.first(where: { $0.kind == "album" }) else { return nil }
        let artist = s.sub?.components(separatedBy: " · ").first ?? ""
        if let url = s.url, let m = url.range(of: #"/album/[^/?#]+\.php"#, options: .regularExpression) {
            let slug = String(url[m].dropFirst(7).dropLast(4))
            if let d = try? await AOTYAPI.shared.album(slug: slug), let t = d.tracklist, !t.isEmpty {
                return (d.title, d.artist, t)
            }
        }
        let tracks = await tracklist(artist: artist, album: s.label, appleMusicURL: nil)
        return tracks.isEmpty ? nil : (s.label, artist, tracks)
    }

    // MARK: Opening

    @MainActor
    static func open(artist: String, album: String?, song: String?, appleMusicURL: String?) async {
        var url: URL?
        if let song {
            var albumID = albumID(fromAppleMusic: appleMusicURL)
            if albumID == nil, let album { albumID = await findAlbum(artist: artist, album: album) }
            if let hit = await findSong(artist: artist, song: song, album: album, albumID: albumID) {
                url = link(id: hit.song, type: "song", albumID: hit.album)
            }
        } else if let album {
            var id = albumID(fromAppleMusic: appleMusicURL)
            if id == nil { id = await findAlbum(artist: artist, album: album) }
            if let id { url = link(id: id, type: "album", albumID: id) }
        }
        if url == nil { url = searchLink(artist: artist, title: song ?? album ?? "") }
        guard let url else { return }
        UIApplication.shared.open(url) { ok in
            if !ok { NotificationCenter.default.post(name: .musicAppOpenFailed, object: nil) }
        }
    }

    private static func link(id: Int, type: String, albumID: Int?) -> URL? {
        switch app {
        case .marvis:
            // Songs: open the album's Apple Music URL with ?i=<track>, which points at that exact
            // track (Marvis "Open Resource by URL"). Albums: open by ID.
            if type == "song" {
                func viaURL(_ am: String) -> URL? {
                    URL(string: "marvis://open?url=" + (am.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? am))
                }
                switch songStyle {
                case .songPage: return viaURL("https://music.apple.com/\(storefront)/song/\(id)")
                case .albumTrack:
                    if let albumID { return viaURL("https://music.apple.com/\(storefront)/album/\(albumID)?i=\(id)") }
                    return URL(string: "marvis://open?id=\(id)&type=song")
                case .songID: return URL(string: "marvis://open?id=\(id)&type=song")
                }
            }
            return URL(string: "marvis://open?id=\(id)&type=\(type)")
        case .appleMusic:
            if type == "song", let albumID { return URL(string: "https://music.apple.com/\(storefront)/album/\(albumID)?i=\(id)") }
            if type == "song" { return URL(string: "https://music.apple.com/\(storefront)/song/\(id)") }
            return URL(string: "https://music.apple.com/\(storefront)/album/\(id)")
        }
    }

    private static func searchLink(artist: String, title: String) -> URL? {
        let q = "\(artist) \(title)"
        switch app {
        case .marvis:
            var c = URLComponents(string: "marvis://search")!
            c.queryItems = [URLQueryItem(name: "term", value: q), URLQueryItem(name: "source", value: "applemusic")]
            return c.url
        case .appleMusic:
            var c = URLComponents(string: "https://music.apple.com/\(storefront)/search")!
            c.queryItems = [URLQueryItem(name: "term", value: q)]
            return c.url
        }
    }
}

extension Notification.Name {
    static let musicAppOpenFailed = Notification.Name("musicAppOpenFailed")
}

struct MusicAppSettingsView: View {
    @AppStorage(MusicAppLink.appKey) private var app = MusicAppLink.App.marvis.rawValue
    @AppStorage(MusicAppLink.songStyleKey) private var songStyle = MusicAppLink.SongStyle.songPage.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Long-press opens in", selection: $app) {
                    ForEach(MusicAppLink.App.allCases) { Text($0.name).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("Press and hold any album or song to open that exact item. The app finds it in the Apple Music catalog; if there's no match it opens a search instead.")
            }
            if app == MusicAppLink.App.marvis.rawValue {
                Section {
                    Picker("Songs open with", selection: $songStyle) {
                        ForEach(MusicAppLink.SongStyle.allCases) { Text($0.name).tag($0.rawValue) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    ForEach(MusicAppLink.SongStyle.allCases) { style in
                        Button("Test “\(style.name)”") {
                            songStyle = style.rawValue
                            Task { await MusicAppLink.open(artist: "The Avalanches", album: "No Bad Memories", song: "Every Single Weekend", appleMusicURL: nil) }
                        }
                    }
                } header: {
                    Text("Songs in Marvis")
                } footer: {
                    Text("Try each test and keep the one where Marvis shows “Every Single Weekend” highlighted or on its own page. Each test also selects that style.")
                }
            }
            Section {
                Button("Test with “The Avalanches – No Bad Memories”") {
                    Task { await MusicAppLink.open(artist: "The Avalanches", album: "No Bad Memories", song: nil, appleMusicURL: nil) }
                }
                Button("Test a song: “Every Single Weekend”") {
                    Task { await MusicAppLink.open(artist: "The Avalanches", album: "No Bad Memories", song: "Every Single Weekend", appleMusicURL: nil) }
                }
            }
        }
        .navigationTitle("Music App")
    }
}
