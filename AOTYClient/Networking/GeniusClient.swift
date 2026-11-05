import Foundation

/// Genius data for the song page. JSON comes from genius.com's public web endpoints (the ones
/// its own site uses); lyrics come from the song page HTML, parsed with Resources/genius.js.
enum GeniusClient {
    struct SongHit: Hashable {
        let id: Int
        let url: URL
        let title: String
        let artist: String
        let art: URL?
    }

    struct Song {
        let id: Int
        let title: String
        let artist: String
        let album: String?
        let releaseDate: String?
        let about: String?
        let art: URL?
        let url: URL
        let annotationCount: Int?
        let commentCount: Int?
        let pageviews: Int?
    }

    struct Segment: Decodable, Hashable {
        let t: String
        let r: Int?
    }

    struct Lyrics: Decodable {
        let segments: [Segment]
        let songId: Int?
        let instrumental: Bool
        var plainText: String { segments.map(\.t).joined() }
    }

    struct Annotation: Hashable, Identifiable {
        let id: Int
        let body: String
        let votes: Int
        let authors: [String]
        let verified: Bool
    }

    struct Referent: Hashable, Identifiable {
        let id: Int
        let fragment: String
        let annotations: [Annotation]
    }

    struct Comment: Hashable, Identifiable {
        let id: Int
        let body: String
        let author: String
        let avatar: URL?
        let votes: Int
        let date: Date?
    }

    enum GeniusError: LocalizedError {
        case blocked, notFound
        var errorDescription: String? {
            switch self {
            case .blocked: "Genius didn't respond."
            case .notFound: "Not found on Genius."
            }
        }
    }

    private static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private static func json(_ path: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://genius.com" + path) else { throw GeniusError.notFound }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = obj["response"] as? [String: Any] else { throw GeniusError.blocked }
        return response
    }

    // MARK: Search

    static func search(artist: String, title: String) async -> SongHit? {
        let cleanTitle = title.replacingOccurrences(of: #"\s*[\(\[].*?(feat|ft|with|prod)\.?[^\)\]]*[\)\]]"#, with: "", options: [.regularExpression, .caseInsensitive])
        let q = "\(artist) \(cleanTitle)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let resp = try? await json("/api/search/song?q=\(q)&per_page=5"),
              let sections = resp["sections"] as? [[String: Any]] else { return nil }
        let results = sections.flatMap { ($0["hits"] as? [[String: Any]]) ?? [] }.compactMap { $0["result"] as? [String: Any] }
        let norm = { (s: String) in s.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber } }
        let a = norm(artist), t = norm(cleanTitle)
        func artistName(_ r: [String: Any]) -> String { ((r["primary_artist"] as? [String: Any])?["name"] as? String) ?? (r["artist_names"] as? String) ?? "" }
        let pick = results.first { norm(artistName($0)).contains(a.prefix(6)) && norm(($0["title"] as? String) ?? "").hasPrefix(t.prefix(8)) }
            ?? results.first { norm(($0["title"] as? String) ?? "").hasPrefix(t.prefix(8)) }
        guard let r = pick, let id = r["id"] as? Int, let u = (r["url"] as? String).flatMap(URL.init(string:)) else { return nil }
        return SongHit(id: id, url: u, title: (r["title"] as? String) ?? title, artist: artistName(r),
                       art: (r["song_art_image_url"] as? String).flatMap(URL.init(string:)))
    }

    // MARK: Album tracklist (fallback when AOTY has none)

    static func albumTracks(artist: String, album: String) async -> [Track] {
        let q = "\(artist) \(album)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let resp = try? await json("/api/search/album?q=\(q)&per_page=5"),
              let sections = resp["sections"] as? [[String: Any]] else { return [] }
        let results = sections.flatMap { ($0["hits"] as? [[String: Any]]) ?? [] }.compactMap { $0["result"] as? [String: Any] }
        let norm = { (s: String) in
            s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                .replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
                .filter { $0.isLetter || $0.isNumber }
        }
        let a = norm(artist), t = norm(album)
        func artistName(_ r: [String: Any]) -> String { ((r["artist"] as? [String: Any])?["name"] as? String) ?? (r["artist_names"] as? String) ?? "" }
        let pick = results.first { norm(($0["name"] as? String) ?? "") == t && norm(artistName($0)).contains(a.prefix(6)) }
            ?? results.first { norm(($0["name"] as? String) ?? "").hasPrefix(t.prefix(10)) && norm(artistName($0)).contains(a.prefix(5)) }
        guard let id = pick?["id"] as? Int,
              let tr = try? await json("/api/albums/\(id)/tracks?per_page=50"),
              let tracks = tr["tracks"] as? [[String: Any]] else { return [] }
        return tracks.enumerated().compactMap { i, x in
            guard let song = x["song"] as? [String: Any], let title = song["title"] as? String else { return nil }
            return Track(number: (x["number"] as? Int) ?? i + 1, title: title, length: nil, rating: nil, features: nil)
        }
    }

    // MARK: Song

    static func song(id: Int) async throws -> Song {
        let resp = try await json("/api/songs/\(id)?text_format=plain")
        guard let s = resp["song"] as? [String: Any] else { throw GeniusError.notFound }
        let desc = ((s["description"] as? [String: Any])?["plain"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stats = s["stats"] as? [String: Any]
        return Song(
            id: id,
            title: (s["title"] as? String) ?? "",
            artist: (s["artist_names"] as? String) ?? ((s["primary_artist"] as? [String: Any])?["name"] as? String) ?? "",
            album: (s["album"] as? [String: Any])?["name"] as? String,
            releaseDate: s["release_date_for_display"] as? String,
            about: (desc == "?" || desc?.isEmpty == true) ? nil : desc,
            art: (s["song_art_image_url"] as? String).flatMap(URL.init(string:)),
            url: (s["url"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://genius.com")!,
            annotationCount: s["annotation_count"] as? Int,
            commentCount: s["comment_count"] as? Int,
            pageviews: stats?["pageviews"] as? Int
        )
    }

    // MARK: Lyrics

    private static let parserJS: String = {
        guard let u = Bundle.main.url(forResource: "genius", withExtension: "js"),
              let s = try? String(contentsOf: u, encoding: .utf8) else { return "" }
        return s
    }()

    static func lyrics(url: URL) async throws -> Lyrics {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let html = String(data: data, encoding: .utf8),
              html.contains("data-lyrics-container") || html.contains("instrumental") else { throw GeniusError.blocked }
        let body = parserJS + "\nreturn JSON.stringify(geniusParse(html));"
        let out = try await AOTYScraper.shared.runJS(body, args: ["html": html])
        return try JSONDecoder().decode(Lyrics.self, from: Data(out.utf8))
    }

    // MARK: Annotations & comments

    static func referents(songId: Int) async -> [Int: Referent] {
        var all: [Int: Referent] = [:]
        for page in 1...4 {
            guard let resp = try? await json("/api/referents?song_id=\(songId)&text_format=plain&per_page=50&page=\(page)"),
                  let refs = resp["referents"] as? [[String: Any]], !refs.isEmpty else { break }
            for r in refs {
                guard let id = r["id"] as? Int else { continue }
                let anns: [Annotation] = ((r["annotations"] as? [[String: Any]]) ?? []).compactMap { a in
                    guard let aid = a["id"] as? Int,
                          let body = (a["body"] as? [String: Any])?["plain"] as? String else { return nil }
                    let authors = ((a["authors"] as? [[String: Any]]) ?? []).compactMap { ($0["user"] as? [String: Any])?["login"] as? String }
                    return Annotation(id: aid, body: body.trimmingCharacters(in: .whitespacesAndNewlines),
                                      votes: (a["votes_total"] as? Int) ?? 0, authors: authors,
                                      verified: (a["verified"] as? Bool) ?? false)
                }
                all[id] = Referent(id: id, fragment: (r["fragment"] as? String) ?? "", annotations: anns)
            }
            if refs.count < 50 { break }
        }
        return all
    }

    static func comments(songId: Int) async -> [Comment] {
        guard let resp = try? await json("/api/songs/\(songId)/comments?text_format=plain&per_page=30"),
              let list = resp["comments"] as? [[String: Any]] else { return [] }
        return list.compactMap { c in
            guard let id = c["id"] as? Int, let body = (c["body"] as? [String: Any])?["plain"] as? String else { return nil }
            let author = c["author"] as? [String: Any]
            let avatar = ((author?["avatar"] as? [String: Any])?["thumb"] as? [String: Any])?["url"] as? String
            let created = (c["created_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            return Comment(id: id, body: body.trimmingCharacters(in: .whitespacesAndNewlines),
                           author: (author?["login"] as? String) ?? (author?["name"] as? String) ?? "Anonymous",
                           avatar: avatar.flatMap(URL.init(string:)), votes: (c["votes_total"] as? Int) ?? 0, date: created)
        }
    }
}
