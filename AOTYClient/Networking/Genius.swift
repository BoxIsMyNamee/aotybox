import Foundation

/// Finds a song's Genius page using Genius's public search endpoint (the one genius.com's
/// own search box uses). Falls back to the Genius search page if nothing matches.
enum Genius {
    private struct SearchResponse: Decodable {
        struct Response: Decodable { let sections: [Section] }
        struct Section: Decodable { let type: String; let hits: [Hit] }
        struct Hit: Decodable { let result: Result }
        struct Result: Decodable {
            let url: String?
            let title: String?
            let primary_artist: Artist?
        }
        struct Artist: Decodable { let name: String? }
        let response: Response
    }

    private static var memo: [String: URL] = [:]

    static func url(artist: String, title: String) async -> URL {
        let cleanTitle = title.replacingOccurrences(of: #"\s*[\(\[].*?(feat|ft|with|prod)\.?[^\)\]]*[\)\]]"#, with: "", options: [.regularExpression, .caseInsensitive])
        let query = "\(artist) \(cleanTitle)"
        if let hit = memo[query] { return hit }
        let fallback = searchPage(query)

        var c = URLComponents(string: "https://genius.com/api/search/song")!
        c.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "per_page", value: "5")]
        guard let api = c.url else { return fallback }
        var req = URLRequest(url: api, timeoutInterval: 8)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return fallback }

        let hits = decoded.response.sections.flatMap { $0.hits }.map(\.result)
        let norm = { (s: String) in s.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber } }
        let a = norm(artist), t = norm(cleanTitle)
        let best = hits.first { norm($0.primary_artist?.name ?? "").contains(a.prefix(6)) && norm($0.title ?? "").hasPrefix(t.prefix(8)) }
            ?? hits.first { norm($0.title ?? "").hasPrefix(t.prefix(8)) }
            ?? hits.first
        guard let s = best?.url, let url = URL(string: s) else { return fallback }
        memo[query] = url
        return url
    }

    private static func searchPage(_ q: String) -> URL {
        var c = URLComponents(string: "https://genius.com/search")!
        c.queryItems = [URLQueryItem(name: "q", value: q)]
        return c.url!
    }
}
