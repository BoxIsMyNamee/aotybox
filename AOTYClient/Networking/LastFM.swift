import SwiftUI

/// Reads a user's live "Scrobbling now" status from Last.fm (uses the official API when an API key is set in Settings, with an HTML fallback).
enum LastFM {
    static let revKey = "lastFMConfigRev"
    private static let kcAccount = "lastfm_api_key"
    private static let placeholderHash = "2a96cbd8b46e442fc41c2b86b821562f"

    static var apiKey: String? {
        guard let k = Keychain.get(kcAccount)?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty else { return nil }
        return k
    }

    static func setAPIKey(_ key: String?) {
        let clean = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set((clean?.isEmpty == true) ? nil : clean, for: kcAccount)
    }

    struct NowPlaying: Equatable {
        let username: String
        let title: String
        let artist: String
        let album: String?
        let cover: URL?
        let profileURL: URL
    }

    enum FetchResult {
        case playing(NowPlaying)
        case idle
        case failed
    }

    /// Pulls a Last.fm username out of a profile's "Around the Web" links, if there is one.
    static func username(from links: [ProfileLink]?) -> (user: String, url: URL)? {
        guard let links else { return nil }
        for link in links {
            guard let u = link.destination,
                  let host = u.host?.lowercased(),
                  host == "last.fm" || host.hasSuffix(".last.fm") else { continue }
            let parts = u.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if parts.count >= 2, parts[0].lowercased() == "user" {
                return (parts[1], u)
            }
        }
        return nil
    }

    /// Fetches the user's current scrobble. Distinguishes `.idle` (confirmed not playing) from `.failed` (network hiccup).
    static func fetchStatus(username: String, profileURL: URL? = nil) async -> FetchResult {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let prof = profileURL ?? URL(string: "https://www.last.fm/user/\(encoded)")!
        if let key = apiKey {
            let apiRes = await fetchFromAPI(username: username, apiKey: key, profileURL: prof)
            switch apiRes {
            case .playing, .idle: return apiRes
            case .failed: break
            }
        }
        return await fetchFromHTML(username: username, encoded: encoded, profileURL: prof)
    }

    /// Convenience wrapper that returns `NowPlaying?` for initial load.
    static func nowPlaying(username: String, profileURL: URL? = nil) async -> NowPlaying? {
        if case let .playing(np) = await fetchStatus(username: username, profileURL: profileURL) {
            return np
        }
        return nil
    }

    // MARK: - Official Last.fm JSON API

    private static func fetchFromAPI(username: String, apiKey: String, profileURL: URL) async -> FetchResult {
        var c = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")!
        c.queryItems = [
            URLQueryItem(name: "method", value: "user.getrecenttracks"),
            URLQueryItem(name: "user", value: username),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970))),
        ]
        guard let url = c.url else { return .failed }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 8
        req.setValue("AOTYbox/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recent = root["recenttracks"] as? [String: Any] else {
            return .failed
        }

        let trackObj: [String: Any]?
        if let arr = recent["track"] as? [[String: Any]] {
            trackObj = arr.first
        } else if let single = recent["track"] as? [String: Any] {
            trackObj = single
        } else {
            return .idle
        }
        guard let track = trackObj else { return .idle }

        let attr = track["@attr"] as? [String: Any]
        let nowPlayingFlag = (attr?["nowplaying"] as? String)?.lowercased() == "true"
        guard nowPlayingFlag else { return .idle }

        let title = (track["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artistDict = track["artist"] as? [String: Any]
        let artist = ((artistDict?["#text"] as? String) ?? (artistDict?["name"] as? String) ?? (track["artist"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return .idle }

        let albumDict = track["album"] as? [String: Any]
        let rawAlbum = (albumDict?["#text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = (rawAlbum?.isEmpty == false) ? rawAlbum : nil

        var coverURL: URL?
        if let images = track["image"] as? [[String: Any]] {
            for img in images.reversed() {
                if let s = (img["#text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !s.isEmpty, !s.contains(placeholderHash),
                   let u = httpsURL(s) {
                    coverURL = u
                    break
                }
            }
        }
        if coverURL == nil {
            coverURL = await fallbackCover(artist: artist, title: title, album: album)
        }

        return .playing(NowPlaying(username: username, title: title, artist: artist, album: album, cover: coverURL, profileURL: profileURL))
    }

    /// Verifies an API key against Last.fm's API.
    static func testAPIKey(_ key: String, username: String?) async -> Result<String, Error> {
        let testUser = (username?.isEmpty == false) ? username! : "rj"
        var c = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")!
        c.queryItems = [
            URLQueryItem(name: "method", value: "user.getrecenttracks"),
            URLQueryItem(name: "user", value: testUser),
            URLQueryItem(name: "api_key", value: key.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = c.url else {
            return .failure(NSError(domain: "LastFM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL."]))
        }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 8
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let msg = root["message"] as? String {
                    return .failure(NSError(domain: "LastFM", code: (root["error"] as? Int) ?? -1, userInfo: [NSLocalizedDescriptionKey: msg]))
                }
                if root["recenttracks"] != nil {
                    if case let .playing(np) = await fetchFromAPI(username: testUser, apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines), profileURL: URL(string: "https://www.last.fm/user/\(testUser)")!) {
                        return .success("Connected — scrobbling “\(np.title)” by \(np.artist).")
                    }
                    return .success("Connected to Last.fm.")
                }
            }
            return .failure(NSError(domain: "LastFM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected response from Last.fm."]))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Public HTML Fallback

    private static func fetchFromHTML(username: String, encoded: String, profileURL: URL) async -> FetchResult {
        let ts = Int(Date().timeIntervalSince1970)
        let endpoints = [
            "https://www.last.fm/user/\(encoded)/partial/recenttracks?ajax=1&_=\(ts)",
            "https://www.last.fm/user/\(encoded)?_=\(ts)",
        ]
        for raw in endpoints {
            guard let url = URL(string: raw) else { continue }
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 8
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let html = String(data: data, encoding: .utf8),
                  html.contains("chartlist-row") else { continue }
            if let np = parseNowPlaying(html: html, username: username, profileURL: profileURL) {
                if np.cover != nil { return .playing(np) }
                let cover = await fallbackCover(artist: np.artist, title: np.title, album: np.album)
                return .playing(NowPlaying(username: np.username, title: np.title, artist: np.artist, album: np.album, cover: cover, profileURL: np.profileURL))
            }
            return .idle
        }
        return .failed
    }

    private static let coverCache = NSCache<NSString, NSURL>()

    private static func httpsURL(_ raw: String) -> URL? {
        let s = raw.hasPrefix("http://") ? "https://" + raw.dropFirst(7) : raw
        return URL(string: s)
    }

    /// Last.fm often omits artwork or sends a generic star placeholder; iTunes fills it in cleanly.
    private static func fallbackCover(artist: String, title: String, album: String?) async -> URL? {
        let key = "\(artist.lowercased())|\(album?.lowercased() ?? "")|\(title.lowercased())" as NSString
        if let hit = coverCache.object(forKey: key) { return hit as URL }

        let queries: [(String, String)] = {
            var q: [(String, String)] = []
            if let album, !album.isEmpty {
                q.append(("\(artist) \(album)", "album"))
            }
            q.append(("\(artist) \(title)", "song"))
            return q
        }()

        for (term, entity) in queries {
            var c = URLComponents(string: "https://itunes.apple.com/search")!
            c.queryItems = [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "entity", value: entity),
                URLQueryItem(name: "limit", value: "3"),
            ]
            guard let url = c.url else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = root["results"] as? [[String: Any]] else { continue }
            for item in results {
                if let art = item["artworkUrl100"] as? String {
                    let hi = art.replacingOccurrences(of: "100x100bb", with: "300x300bb")
                    if let u = httpsURL(hi) {
                        coverCache.setObject(u as NSURL, forKey: key)
                        return u
                    }
                }
            }
        }
        return nil
    }

    static func parseNowPlaying(html: String, username: String, profileURL: URL) -> NowPlaying? {
        let trPattern = #"<tr\b[^>]*chartlist-row--now-scrobbling[^>]*>([\s\S]*?)</tr>"#
        let rowHTML: String
        if let m = firstMatch(trPattern, in: html) {
            rowHTML = m
        } else {
            let anyRow = #"<tr\b[^>]*chartlist-row[^>]*>([\s\S]*?)</tr>"#
            guard let r = firstMatch(anyRow, in: html),
                  r.contains("scrobbling-now") || r.lowercased().contains("scrobbling now") else { return nil }
            rowHTML = r
        }

        let title = extractCellLink(classToken: "chartlist-name", in: rowHTML)
        let artist = extractCellLink(classToken: "chartlist-artist", in: rowHTML)
        guard let title, !title.isEmpty, let artist, !artist.isEmpty else { return nil }

        var coverURL: URL?
        var albumName: String?
        if let imgBlock = firstMatch(#"class="[^"]*chartlist-image[^"]*"[^>]*>([\s\S]*?)</td>"#, in: rowHTML),
           let imgTag = firstMatch(#"(<img\b[^>]*>)"#, in: imgBlock) {
            if let src = firstMatch(#"\bsrc="([^"]+)""#, in: imgTag),
               !src.contains(placeholderHash) {
                let hiRes = src
                    .replacingOccurrences(of: "/34s/", with: "/174s/")
                    .replacingOccurrences(of: "/64s/", with: "/174s/")
                coverURL = httpsURL(hiRes)
            }
            if let alt = firstMatch(#"\balt="([^"]*)""#, in: imgTag) {
                let decoded = decodeEntities(alt).trimmingCharacters(in: .whitespacesAndNewlines)
                if !decoded.isEmpty, decoded.lowercased() != title.lowercased() || coverURL != nil {
                    albumName = decoded
                }
            }
        }

        return NowPlaying(username: username, title: title, artist: artist, album: albumName, cover: coverURL, profileURL: profileURL)
    }

    private static func extractCellLink(classToken: String, in html: String) -> String? {
        let tdPattern = #"class="[^"]*\b"# + classToken + #"\b[^"]*"[^>]*>([\s\S]*?)</td>"#
        guard let cell = firstMatch(tdPattern, in: html) else { return nil }
        if let aText = firstMatch(#"<a\b[^>]*>([\s\S]*?)</a>"#, in: cell) {
            let clean = stripTags(aText)
            if !clean.isEmpty { return clean }
        }
        if let titleAttr = firstMatch(#"\btitle="([^"]+)""#, in: cell) {
            let clean = decodeEntities(titleAttr).trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { return clean }
        }
        let fallback = stripTags(cell)
        return fallback.isEmpty ? nil : fallback
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = rx.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func stripTags(_ s: String) -> String {
        let noTags = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return decodeEntities(noTags).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ s: String) -> String {
        var out = s
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        if out.contains("&#"), let rx = try? NSRegularExpression(pattern: #"&#(x?[0-9a-fA-F]+);"#) {
            let ns = out as NSString
            let matches = rx.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed()
            for m in matches where m.numberOfRanges > 1 {
                let codeStr = ns.substring(with: m.range(at: 1))
                let code: UInt32? = codeStr.lowercased().hasPrefix("x")
                    ? UInt32(codeStr.dropFirst(), radix: 16)
                    : UInt32(codeStr, radix: 10)
                if let code, let scalar = UnicodeScalar(code), let r = Range(m.range, in: out) {
                    out.replaceSubrange(r, with: String(Character(scalar)))
                }
            }
        }
        return out
    }
}

/// Settings screen to save a Last.fm API key in the iPhone Keychain.
struct LastFMSettingsView: View {
    @AppStorage(LastFM.revKey) private var rev = 0
    @State private var key = ""
    @State private var testing = false
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                SecureField("Last.fm API key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { save() }
            } header: {
                Text("API Key")
            } footer: {
                Text("Get a free API key at last.fm/api/account/create. Stored in the iPhone Keychain and used to check live Now Playing scrobbles reliably.")
            }

            Section {
                Button("Save") { save() }
                Button(testing ? "Testing…" : "Test connection") {
                    Task { await test() }
                }
                .disabled(testing || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let status {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
                if LastFM.apiKey != nil {
                    Button("Remove key", role: .destructive) {
                        LastFM.setAPIKey(nil)
                        key = ""
                        status = nil
                        rev += 1
                    }
                }
            }
        }
        .navigationTitle("Last.fm")
        .onAppear { key = LastFM.apiKey ?? "" }
        .onDisappear { save() }
    }

    private func save() {
        LastFM.setAPIKey(key)
        rev += 1
    }

    private func test() async {
        save()
        testing = true; defer { testing = false }
        switch await LastFM.testAPIKey(key, username: nil) {
        case let .success(msg): status = msg
        case let .failure(err): status = err.localizedDescription
        }
    }
}
