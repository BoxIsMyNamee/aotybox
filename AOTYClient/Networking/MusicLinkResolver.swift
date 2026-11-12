import Foundation

/// Turns an Apple Music, song.link / album.link or Spotify link into "artist + album".
enum MusicLinkResolver {
    struct Album { let artist: String; let title: String }

    static func isMusicLink(_ url: URL) -> Bool {
        let h = (url.host ?? "").lowercased()
        return ["music.apple.com", "itunes.apple.com", "song.link", "album.link", "odesli.co", "pods.link",
                "open.spotify.com", "spotify.link", "tidal.com", "listen.tidal.com", "music.youtube.com",
                "deezer.com", "www.deezer.com"].contains { h == $0 || h.hasSuffix("." + $0) }
    }

    static func resolve(_ url: URL) async -> Album? {
        let host = (url.host ?? "").lowercased()
        if host.hasSuffix("music.apple.com") || host.hasSuffix("itunes.apple.com"), let a = await appleMusic(url) { return a }
        return await odesli(url)
    }

    /// music.apple.com/us/album/name/123?i=456 → iTunes lookup of the song (456) or album (123).
    private static func appleMusic(_ url: URL) async -> Album? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let song = items.first { $0.name == "i" }?.value
        let album = url.pathComponents.last { Int($0) != nil }
        let id = song ?? album ?? url.pathComponents.last.flatMap { $0.hasPrefix("id") ? String($0.dropFirst(2)) : nil }
        guard let id else { return nil }
        return await lookup(id: id)
    }

    private static func lookup(id: String) async -> Album? {
        guard let u = URL(string: "https://itunes.apple.com/lookup?id=\(id)"),
              let (d, _) = try? await URLSession.shared.data(from: u),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let r = (j["results"] as? [[String: Any]])?.first,
              let artist = r["artistName"] as? String,
              let title = r["collectionName"] as? String else { return nil }
        return Album(artist: artist, title: clean(title))
    }

    /// Any other music link: Odesli (the service behind song.link) says what it is and gives its Apple Music link.
    private static func odesli(_ url: URL) async -> Album? {
        var c = URLComponents(string: "https://api.song.link/v1-alpha.1/links")!
        c.queryItems = [URLQueryItem(name: "url", value: url.absoluteString), URLQueryItem(name: "userCountry", value: "US")]
        guard let u = c.url, let (d, _) = try? await URLSession.shared.data(from: u),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        if let links = j["linksByPlatform"] as? [String: Any],
           let am = (links["appleMusic"] as? [String: Any])?["url"] as? String, let amURL = URL(string: am),
           let a = await appleMusic(amURL) { return a }
        // No Apple Music match: use what Odesli knows (a song gets looked up for its album).
        guard let key = j["entityUniqueId"] as? String,
              let e = (j["entitiesByUniqueId"] as? [String: Any])?[key] as? [String: Any],
              let title = e["title"] as? String, let artist = e["artistName"] as? String else { return nil }
        if (e["type"] as? String) == "song", let a = await songAlbum(artist: artist, song: title) { return a }
        return Album(artist: artist, title: clean(title))
    }

    private static func songAlbum(artist: String, song: String) async -> Album? {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [URLQueryItem(name: "term", value: "\(artist) \(song)"), URLQueryItem(name: "entity", value: "song"), URLQueryItem(name: "limit", value: "1")]
        guard let u = c.url, let (d, _) = try? await URLSession.shared.data(from: u),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let r = (j["results"] as? [[String: Any]])?.first,
              let a = r["artistName"] as? String, let t = r["collectionName"] as? String else { return nil }
        return Album(artist: a, title: clean(t))
    }

    private static func clean(_ t: String) -> String {
        t.replacingOccurrences(of: #"\s+-\s+(Single|EP)$"#, with: "", options: [.regularExpression, .caseInsensitive])
    }
}
