import SwiftUI
import WebKit

/// Fetches AOTY pages on-device through a hidden WKWebView that shares the
/// user's AOTY session (and Cloudflare clearance), then extracts JSON with
/// Resources/extract.js. Nothing goes through a third-party server.
///
/// Flow per request:
///   1. Make sure the hidden web view sits on an albumoftheyear.org page (same origin).
///   2. `fetch()` the target page from inside it and run the extractor on the HTML.
///   3. If Cloudflare challenges, show the page to the user once (ChallengeSheet),
///      then retry. As a last resort, navigate the hidden view to the page itself.
@MainActor
final class AOTYScraper: NSObject, ObservableObject, WKNavigationDelegate {
    static let shared = AOTYScraper()

    struct Challenge: Identifiable { let id = UUID(); let url: URL }

    /// Set when the user needs to pass a Cloudflare check. Root view presents a sheet.
    @Published var challenge: Challenge?

    let webView: WKWebView
    private let extractorJS: String
    private var originReady = false
    private var navContinuation: CheckedContinuation<Void, Error>?
    private var challengeContinuation: CheckedContinuation<Void, Never>?
    private var queueTail: Task<Void, Never> = Task {}
    private var lastFetch = Date.distantPast
    private let minGap: TimeInterval = 0.4

    // Cache
    private let ttl: TimeInterval = 15 * 60
    private var memory: [String: (Date, Data)] = [:]
    private let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("aoty", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    override private init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = AOTYSession.dataStore
        config.mediaTypesRequiringUserActionForPlayback = .all
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 2, height: 2), configuration: config)
        if let url = Bundle.main.url(forResource: "extract", withExtension: "js"),
           let js = try? String(contentsOf: url, encoding: .utf8) {
            extractorJS = js
        } else {
            extractorJS = "throw new Error('extract.js missing from app bundle')"
        }
        super.init()
        webView.navigationDelegate = self
    }

    enum Kind: String { case blocks, chart, album }

    enum ScrapeError: LocalizedError {
        case blocked
        case http(Int)
        case script(String)
        case navigation(String)

        var errorDescription: String? {
            switch self {
            case .blocked: "AOTY's Cloudflare check didn't pass. Pull to refresh to try again."
            case let .http(code): "AOTY returned HTTP \(code)."
            case let .script(msg): "Couldn't read the AOTY page: \(msg)"
            case let .navigation(msg): "Couldn't load AOTY: \(msg)"
            }
        }
    }

    // MARK: - Public

    func fetch<T: Decodable>(_ path: String, kind: Kind, as type: T.Type) async throws -> T {
        if let fresh = cached(path), let value = try? JSONDecoder().decode(T.self, from: fresh) {
            return value
        }
        do {
            let data = try await serialized { try await self.fetchJSON(path: path, kind: kind) }
            store(path, data)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Offline or blocked: fall back to stale cache if we have any.
            if let stale = cached(path, allowStale: true), let value = try? JSONDecoder().decode(T.self, from: stale) {
                return value
            }
            throw error
        }
    }

    func clearCache() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Called by the challenge sheet when the user closes it.
    func challengeFinished() {
        challenge = nil
        originReady = false
        challengeContinuation?.resume()
        challengeContinuation = nil
    }

    // MARK: - Core

    private func fetchJSON(path: String, kind: Kind) async throws -> Data {
        let url = URL(string: AOTYSession.home.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)!

        // Attempt 1: same-origin fetch from the hidden web view.
        try await ensureOrigin()
        if case let .ok(data) = try await runFetch(path: path, kind: kind) { return data }

        // Challenged: let the user pass the check once, then retry.
        await presentChallenge(url)
        try await ensureOrigin()
        if case let .ok(data) = try await runFetch(path: path, kind: kind) { return data }

        // Last resort: navigate the hidden view to the page and extract from the live document.
        try await navigate(to: url)
        if case let .ok(data) = try await runOnLoadedPage(kind: kind) { return data }
        throw ScrapeError.blocked
    }

    private enum Outcome { case ok(Data), challenged }

    private func runFetch(path: String, kind: Kind) async throws -> Outcome {
        try await throttle()
        let body = extractorJS + """

        const r = await fetch(path, { credentials: "include", headers: { "Accept": "text/html" } });
        const html = await r.text();
        if (aotyIsChallenge(html, r.status)) return JSON.stringify({ __challenge: true });
        if (!r.ok) return JSON.stringify({ __http: r.status });
        return JSON.stringify(aotyExtract(kind, html, r.url));
        """
        return try await evaluate(body, args: ["path": path, "kind": kind.rawValue])
    }

    private func runOnLoadedPage(kind: Kind) async throws -> Outcome {
        let body = extractorJS + """

        const html = document.documentElement.outerHTML;
        if (aotyIsChallenge(html, 200)) return JSON.stringify({ __challenge: true });
        return JSON.stringify(aotyExtract(kind, html, location.href));
        """
        return try await evaluate(body, args: ["kind": kind.rawValue])
    }

    private func evaluate(_ body: String, args: [String: Any]) async throws -> Outcome {
        let result: Any?
        do {
            result = try await webView.callAsyncJavaScript(body, arguments: args, in: nil, contentWorld: .defaultClient)
        } catch {
            throw ScrapeError.script(error.localizedDescription)
        }
        guard let json = result as? String, let data = json.data(using: .utf8) else {
            throw ScrapeError.script("empty result")
        }
        if let probe = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if probe["__challenge"] != nil { return .challenged }
            if let code = probe["__http"] as? Int { throw ScrapeError.http(code) }
        }
        return .ok(data)
    }

    /// Put the hidden view on a lightweight same-origin page so `fetch()` carries AOTY cookies.
    private func ensureOrigin() async throws {
        if originReady, webView.url?.host?.contains("albumoftheyear.org") == true { return }
        try await navigate(to: URL(string: "https://www.albumoftheyear.org/robots.txt")!)
        originReady = true
    }

    private func navigate(to url: URL) async throws {
        navContinuation?.resume(throwing: CancellationError())
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            navContinuation = c
            webView.load(URLRequest(url: url))
        }
    }

    private func presentChallenge(_ url: URL) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            challengeContinuation = c
            challenge = Challenge(url: url)
        }
    }

    private func throttle() async throws {
        let wait = minGap - Date().timeIntervalSince(lastFetch)
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        lastFetch = Date()
    }

    /// Run operations one at a time, in order.
    private func serialized<T>(_ op: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = queueTail
        let task = Task { @MainActor () throws -> T in
            _ = await previous.value
            return try await op()
        }
        queueTail = Task { _ = try? await task.value }
        return try await task.value
    }

    // MARK: - Cache

    private func key(_ path: String) -> URL {
        let safe = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? String(path.hashValue)
        return cacheDir.appendingPathComponent(String(safe.prefix(200)) + ".json")
    }

    private func cached(_ path: String, allowStale: Bool = false) -> Data? {
        if let (date, data) = memory[path], allowStale || Date().timeIntervalSince(date) < ttl { return data }
        let file = key(path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let date = attrs[.modificationDate] as? Date,
              allowStale || Date().timeIntervalSince(date) < ttl,
              let data = try? Data(contentsOf: file) else { return nil }
        memory[path] = (date, data)
        return data
    }

    private func store(_ path: String, _ data: Data) {
        memory[path] = (Date(), data)
        try? data.write(to: key(path), options: .atomic)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navContinuation?.resume()
        navContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navContinuation?.resume(throwing: ScrapeError.navigation(error.localizedDescription))
        navContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navContinuation?.resume(throwing: ScrapeError.navigation(error.localizedDescription))
        navContinuation = nil
    }
}

/// Keeps the hidden fetcher web view inside the window hierarchy (WebKit throttles
/// web views that aren't on screen). It's 2×2 points and fully transparent.
struct HiddenScraperHost: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        host.isUserInteractionEnabled = false
        host.alpha = 0.01
        let web = AOTYScraper.shared.webView
        web.frame = host.bounds
        host.addSubview(web)
        return host
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Shown when Cloudflare wants a human check. The user passes it on AOTY's real page;
/// the clearance cookie lands in the shared WebKit store and the fetcher retries.
struct ChallengeSheet: View {
    let url: URL
    @State private var loading = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("AOTY wants a quick check. Complete it, then tap Done.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(8).frame(maxWidth: .infinity).background(.bar)
                AOTYWebView(url: url, isLoading: $loading)
            }
            .navigationTitle("Verify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { AOTYScraper.shared.challengeFinished() }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}
