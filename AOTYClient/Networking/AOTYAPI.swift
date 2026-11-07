import Foundation

/// Client for the unofficial AOTY community API (edideaur/AOTY-api).
///
/// Etiquette baked in, because the default host is someone's free Cloudflare Worker:
///  - requests are serialized and spaced at least `minInterval` apart
///  - responses are cached on disk (URLCache) and reused for `freshFor`
///  - every request carries an attributing User-Agent
///
/// The base URL is configurable in Settings so you can point at your own deployment.
actor AOTYAPI {
    static let shared = AOTYAPI()

    static let defaultBaseURL = "https://aoty.prigoana.com"
    static let baseURLKey = "apiBaseURL"
    /// "device" (default): fetch AOTY pages on the phone. "api": use the community API.
    static let sourceKey = "dataSource"

    /// Always on-device now (the community API is blocked by AOTY). API code kept for later.
    static var usesDevice: Bool { true }

    private let session: URLSession
    private let cache: URLCache
    private let decoder = JSONDecoder()
    private let minInterval: Duration = .milliseconds(250)
    private let freshFor: TimeInterval = 15 * 60
    private var lastRequest: ContinuousClock.Instant?

    init() {
        let cache = URLCache(memoryCapacity: 20_000_000, diskCapacity: 200_000_000, directory: nil)
        self.cache = cache
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "AOTYClient-iOS/0.1 (personal client; data: albumoftheyear.org via unofficial AOTY API)",
            "Accept": "application/json",
        ]
        session = URLSession(configuration: config)
    }

    // MARK: - Endpoints

    func releases(page: Int = 1, singles: Bool = false) async throws -> [AlbumBlock] {
        if singles { return try await device(page > 1 ? "/releases/singles/\(page)/" : "/releases/singles/", .blocks, AlbumListResponse.self).albums }
        if Self.usesDevice { return try await device(page > 1 ? "/releases/\(page)/" : "/releases/", .blocks, AlbumListResponse.self).albums }
        return try await get("/releases", ["page": "\(page)"], as: AlbumListResponse.self).albums
    }

    func thisWeek(page: Int = 1, singles: Bool = false) async throws -> [AlbumBlock] {
        if singles {
            let path = page > 1 ? "/releases/this-week/singles/\(page)/" : "/releases/this-week/singles/"
            return try await device(path, .blocks, AlbumListResponse.self).albums
        }
        if Self.usesDevice {
            let path = page > 1 ? "/releases/this-week/\(page)/" : "/releases/this-week/"
            return try await device(path, .blocks, AlbumListResponse.self).albums
        }
        return try await get("/releases/this-week", ["page": "\(page)"], as: AlbumListResponse.self).albums
    }

    func upcoming(page: Int = 1, singles: Bool = false) async throws -> [AlbumBlock] {
        if singles { return try await device(page > 1 ? "/upcoming/singles/\(page)/" : "/upcoming/singles/", .blocks, AlbumListResponse.self).albums }
        if Self.usesDevice { return try await device(page > 1 ? "/upcoming/\(page)/" : "/upcoming/", .blocks, AlbumListResponse.self).albums }
        return try await get("/upcoming", ["page": "\(page)"], as: AlbumListResponse.self).albums
    }

    /// source: "6-highest-rated" (critics) or "user-highest-rated" (users). period: a year like "2026", or "all".
    func chart(source: String, period: String, page: Int = 1) async throws -> ChartResponse {
        if Self.usesDevice { return try await device("/ratings/\(source)/\(period)/\(page)", .chart, ChartResponse.self) }
        return try await get("/ratings", ["source": source, "period": period, "page": "\(page)"], as: ChartResponse.self)
    }

    func searchAlbums(_ query: String, page: Int = 1) async throws -> [AlbumBlock] {
        try await get("/search/albums", ["q": query, "page": "\(page)"], as: AlbumListResponse.self).albums
    }

    /// `minimal=true` skips the extra stats/credits fetches the worker would otherwise make.
    func album(slug: String, background: Bool = false) async throws -> AlbumDetail {
        if background { return try await AOTYScraper.shared.fetch("/album/\(slug).php", kind: .album, as: AlbumDetail.self, background: true) }
        if Self.usesDevice { return try await device("/album/\(slug).php", .album, AlbumDetail.self) }
        return try await get("/album", ["slug": slug, "minimal": "true"], as: AlbumDetail.self)
    }

    /// sort: "best" (popular), "recent" or "worst". Always fetched on-device.
    func userReviews(slug: String, sort: String, page: Int) async throws -> UserReviewsPage {
        let path = "/album/\(slug)/user-reviews/?sort=\(sort)" + (page > 1 ? "&p=\(page)" : "")
        return try await device(path, .userReviews, UserReviewsPage.self)
    }

    /// The signed-in AOTY user, read from the site header.
    func me(refresh: Bool = false) async throws -> Me {
        if refresh { await AOTYScraper.shared.forget("/") }
        return try await device("/", .me, Me.self)
    }

    func profile(username: String) async throws -> Profile {
        try await device("/user/\(username)/", .profile, Profile.self)
    }

    /// type: nil for AOTY's default (albums), or "single", "ep", "mixtape", …
    func userRatings(username: String, page: Int, type: String? = nil) async throws -> [AlbumBlock] {
        let path = "/user/\(username)/ratings/" + (type.map { "\($0)/" } ?? "") + (page > 1 ? "\(page)/" : "")
        return try await device(path, .blocks, AlbumListResponse.self).albums
    }

    func following(username: String, page: Int = 1) async throws -> [FollowUser] {
        let path = "/user/\(username)/following/" + (page > 1 ? "\(page)/" : "")
        return try await device(path, .follows, FollowList.self).users
    }

    func profileReviews(username: String, page: Int = 1) async throws -> [ProfileReview] {
        let path = "/user/\(username)/reviews/" + (page > 1 ? "\(page)/" : "")
        return try await device(path, .userReviewList, ProfileReviewList.self).reviews
    }

    struct Artist: Decodable {
        struct Link: Decodable, Hashable { let text: String; let href: String }
        struct Detail: Decodable, Hashable { let label: String; let value: String; let links: [Link]? }
        let name: String
        let image: String?
        let score: Double?
        var criticScore: Double? = nil
        var criticCount: Int? = nil
        var userScore: Double? = nil
        var userCount: Int? = nil
        var followers: String? = nil
        var details: [Detail]? = nil
        let albums: [AlbumBlock]
    }

    enum LikeResult: Equatable { case ok, limited, failed(String) }

    /// Heart / un-heart a user review (same requests AOTY's own button sends, using your session).
    func setReviewLike(_ reviewID: Int, liked: Bool) async -> LikeResult {
        let js = """
        const r = await fetch(endpoint, { method: "POST", credentials: "include",
          headers: { "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8", "X-Requested-With": "XMLHttpRequest" },
          body: "reviewID=" + encodeURIComponent(id) });
        return r.status + "|" + (await r.text()).slice(0, 200);
        """
        let endpoint = liked ? "/scripts/insertReviewLike.php" : "/scripts/deleteReviewLike.php"
        do {
            let out = try await AOTYScraper.shared.runJS(js, args: ["endpoint": endpoint, "id": String(reviewID)])
            if out.contains("Limited") { return .limited }
            let parts = out.split(separator: "|", maxSplits: 1).map(String.init)
            let body = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            // AOTY answers 200 with an empty body (or a short "ok") when it worked.
            if parts.first == "200" && (body.isEmpty || body.count < 40 && !body.lowercased().contains("error") && !body.lowercased().contains("login")) { return .ok }
            return .failed("AOTY said: \(parts.first ?? "?") \(body.prefix(120))")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Releases by other artists that this artist appears on (AOTY's "Appears On" credits list).
    func appearsOn(artistPath: String) async throws -> [AlbumBlock] {
        guard let id = artistPath.firstMatch(of: /\/artist\/(\d+)/)?.1 else { return [] }
        struct R: Decodable { let albums: [AlbumBlock] }
        return try await AOTYScraper.shared.postExtract("/scripts/artistCreditList.php",
            form: ["artistID": String(id), "type": "Appears On", "albumClass": "0", "sort": ""],
            kind: .blocks, as: R.self).albums
    }

    /// Find a release on AOTY by artist + title (AOTY's album search). Returns its slug.
    func findAlbumSlug(artist: String, title: String) async -> String? {
        func norm(_ s: String) -> String {
            s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                .replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+-\s+(single|ep)$"#, with: "", options: .regularExpression)
                .filter { $0.isLetter || $0.isNumber }
        }
        let q = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        struct R: Decodable { let albums: [AlbumBlock] }
        guard let list = try? await device("/search/albums/?q=\(q)", .blocks, R.self).albums, !list.isEmpty else { return nil }
        let t = norm(title), a = norm(artist)
        let pick = list.first { norm($0.title) == t && norm($0.artist).contains(a.prefix(6)) }
            ?? list.first { norm($0.title).hasPrefix(t.prefix(8)) && norm($0.artist).contains(a.prefix(4)) }
            ?? list.first { norm($0.artist).contains(a.prefix(6)) }
        return pick?.slug
    }

    /// Best guess at an artist's AOTY page from their name.
    func findArtistPath(name: String) async -> String? {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        struct R: Decodable { let paths: [String] }
        return (try? await device("/search/artists/?q=\(q)", .artistSearch, R.self))?.paths.first
    }

    /// An artist page: "/artist/183-kanye-west/".
    func artist(path: String) async throws -> Artist {
        // Always "/artist/123-name/" (+ "?type=…"): without the slash AOTY drops the filter.
        var parts = path.components(separatedBy: "?")
        if !parts[0].hasSuffix("/") { parts[0] += "/" }
        return try await device(parts.joined(separator: "?"), .artist, Artist.self)
    }

    /// The full text of a review whose preview AOTY cut short.
    func fullReview(url: String, preview: String) async throws -> String? {
        guard let u = URL(string: url, relativeTo: URL(string: "https://www.albumoftheyear.org")) else { return nil }
        let path = u.path + (u.query.map { "?" + $0 } ?? "")
        struct Blocks: Decodable { let preferred: [String]?; let blocks: [String] }
        let page = try await device(path, .textBlocks, Blocks.self)
        func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let cleaned = preview.replacingOccurrences(of: #"\s*(\.\.\.|…)?\s*read more\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"(\.\.\.|…)\s*$"#, with: "", options: .regularExpression)
        let probe = String(key(cleaned).prefix(80))
        guard probe.count >= 20 else { return nil }
        // AOTY's review-text element if present; otherwise the longest block that starts with the preview.
        let pick = (page.preferred ?? []).filter { key($0).contains(probe) }.max { $0.count < $1.count }
            ?? page.blocks.filter { key($0).hasPrefix(probe) }.max { $0.count < $1.count }
        guard let pick, pick.count >= cleaned.count - 5 else { return nil }
        return pick.replacingOccurrences(of: #"\s*read more\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    /// Ratings from a path AOTY gave us (e.g. the profile's "View All" link), with paging.
    func ratings(path: String, page: Int) async throws -> [AlbumBlock] {
        var base = path.hasSuffix("/") ? path : path + "/"
        if page > 1 { base += "\(page)/" }
        return try await device(base, .blocks, AlbumListResponse.self).albums
    }

    func clearCache() async {
        cache.removeAllCachedResponses()
        await AOTYScraper.shared.clearCache()
        ImageCache.shared.clear()
    }

    private func device<T: Decodable>(_ path: String, _ kind: AOTYScraper.Kind, _ type: T.Type) async throws -> T {
        try await AOTYScraper.shared.fetch(path, kind: kind, as: type)
    }

    // MARK: - Core

    private var baseURL: String {
        let stored = UserDefaults.standard.string(forKey: Self.baseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (stored?.isEmpty == false ? stored! : Self.defaultBaseURL)
        return base.hasSuffix("/") ? String(base.dropLast()) : base
    }

    private func get<T: Decodable>(_ path: String, _ params: [String: String], as type: T.Type) async throws -> T {
        guard var comps = URLComponents(string: baseURL + path) else { throw APIError.badURL }
        comps.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw APIError.badURL }
        var request = URLRequest(url: url)

        // Serve from cache if we fetched this recently — no network, no throttle.
        if let cached = cache.cachedResponse(for: request),
           let stamp = cached.userInfo?["fetchedAt"] as? Date,
           Date().timeIntervalSince(stamp) < freshFor,
           let value = try? decoder.decode(T.self, from: cached.data) {
            return value
        }

        try await throttle()
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }

        guard (200..<300).contains(http.statusCode) else {
            let body = try? decoder.decode(APIErrorBody.self, from: data)
            throw APIError.http(http.statusCode, body?.detail ?? body?.error ?? body?.message)
        }

        let value: T
        do { value = try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(path, error) }

        cache.storeCachedResponse(
            CachedURLResponse(response: http, data: data, userInfo: ["fetchedAt": Date()], storagePolicy: .allowed),
            for: request
        )
        return value
    }

    private func throttle() async throws {
        // Reserve the next slot *before* sleeping so concurrent callers queue up
        // instead of all waking at once (actors are reentrant across `await`).
        let clock = ContinuousClock()
        let now = clock.now
        let slot = lastRequest.map { max(now, $0 + minInterval) } ?? now
        lastRequest = slot
        if slot > now { try await Task.sleep(until: slot, clock: clock) }
    }
}

enum APIError: LocalizedError {
    case badURL
    case badResponse
    case http(Int, String?)
    case decoding(String, Error)

    var errorDescription: String? {
        switch self {
        case .badURL: "Invalid API URL. Check Settings."
        case .badResponse: "No response from the API."
        case let .http(code, msg):
            if let msg, msg.contains("403") {
                "AOTY is blocking the community API right now (\(msg)). This isn't an app bug."
            } else {
                "API error \(code)" + (msg.map { ": \($0)" } ?? "")
            }
        case let .decoding(path, err): "Couldn't read \(path) — the API's format may have changed. (\(err.localizedDescription))"
        }
    }
}
