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

    func releases(page: Int = 1) async throws -> [AlbumBlock] {
        try await get("/releases", ["page": "\(page)"], as: AlbumListResponse.self).albums
    }

    func thisWeek(page: Int = 1) async throws -> [AlbumBlock] {
        try await get("/releases/this-week", ["page": "\(page)"], as: AlbumListResponse.self).albums
    }

    func upcoming(page: Int = 1) async throws -> [AlbumBlock] {
        try await get("/upcoming", ["page": "\(page)"], as: AlbumListResponse.self).albums
    }

    /// source: "6-highest-rated" (critics) or "user-highest-rated" (users). period: a year like "2026", or "all".
    func chart(source: String, period: String, page: Int = 1) async throws -> ChartResponse {
        try await get("/ratings", ["source": source, "period": period, "page": "\(page)"], as: ChartResponse.self)
    }

    func searchAlbums(_ query: String, page: Int = 1) async throws -> [AlbumBlock] {
        try await get("/search/albums", ["q": query, "page": "\(page)"], as: AlbumListResponse.self).albums
    }

    /// `minimal=true` skips the extra stats/credits fetches the worker would otherwise make.
    func album(slug: String) async throws -> AlbumDetail {
        try await get("/album", ["slug": slug, "minimal": "true"], as: AlbumDetail.self)
    }

    func clearCache() {
        cache.removeAllCachedResponses()
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
