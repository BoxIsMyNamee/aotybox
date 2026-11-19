import Foundation

/// Reads a user's live "Scrobbling now" status from their public Last.fm profile page (no API key needed).
enum LastFM {
    struct NowPlaying: Equatable {
        let username: String
        let title: String
        let artist: String
        let album: String?
        let cover: URL?
        let profileURL: URL
    }

    private static let placeholderHash = "2a96cbd8b46e442fc41c2b86b821562f"

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

    /// Fetches the user's current scrobble if they are listening right now; returns nil when idle.
    static func nowPlaying(username: String, profileURL: URL? = nil) async -> NowPlaying? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let prof = profileURL ?? URL(string: "https://www.last.fm/user/\(encoded)")!
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
            return parseNowPlaying(html: html, username: username, profileURL: prof)
        }
        return nil
    }

    /// Parses Last.fm's recent-tracks HTML for a `.chartlist-row--now-scrobbling` row.
    static func parseNowPlaying(html: String, username: String, profileURL: URL) -> NowPlaying? {
        // Isolate the currently-scrobbling <tr ...>...</tr>
        let trPattern = #"<tr\b[^>]*chartlist-row--now-scrobbling[^>]*>([\s\S]*?)</tr>"#
        let rowHTML: String
        if let m = firstMatch(trPattern, in: html) {
            rowHTML = m
        } else {
            // Fallback: check if any <tr class="...chartlist-row..."> contains scrobbling-now-inner
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
                coverURL = URL(string: hiRes)
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
