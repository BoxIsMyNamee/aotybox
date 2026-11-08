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
    private var queueTail: Task<Void, Never> = Task {}
    /// Requests queued or running. Background work (genre lookups) waits until this is 0,
    /// so pages you open never sit behind it.
    private var pending = 0
    private var lastFetch = Date.distantPast
    private let minGap: TimeInterval = 0.4

    // Cache
    private let ttl: TimeInterval = 15 * 60
    private var memory: [String: (Date, Data)] = [:]
    private let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("aoty-v2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    override private init() {
        let config = AOTYSession.makeConfiguration()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 2, height: 2), configuration: config)
        if let url = Bundle.main.url(forResource: "extract", withExtension: "js"),
           let js = try? String(contentsOf: url, encoding: .utf8) {
            extractorJS = js
        } else {
            extractorJS = "throw new Error('extract.js missing from app bundle')"
        }
        super.init()
        webView.navigationDelegate = self
        pruneOldCache()
    }

    enum Kind: String { case blocks, chart, album, userReviews, me, profile, follows, userReviewList, textBlocks, artist, artistSearch }

    enum ScrapeError: LocalizedError {
        case blocked
        case stillBlocked
        case http(Int, String)
        case empty(String)
        case script(String)
        case navigation(String)
        case timeout

        var errorDescription: String? {
            switch self {
            case .blocked: "AOTY wants a quick check. Complete it in the sheet, then tap Retry."
            case .stillBlocked: "AOTY is still asking for a check. Wait a minute and tap Retry, or open the page in Settings → Sign in."
            case let .http(code, path): "AOTY returned HTTP \(code) for \(path)."
            case let .empty(info): "The page loaded but nothing could be read from it. \(info)"
            case let .script(msg): "Couldn't read the AOTY page: \(msg)"
            case let .navigation(msg): "Couldn't load AOTY: \(msg)"
            case .timeout: "AOTY took too long to respond. Tap Retry."
            }
        }
    }

    // MARK: - Public

    func fetch<T: Decodable>(_ path: String, kind: Kind, as type: T.Type, background: Bool = false) async throws -> T {
        if (background || Date() > bypassUntil), let fresh = cached(path), let value = try? JSONDecoder().decode(T.self, from: fresh) {
            return value
        }
        if background {
            while pending > 0 { try await Task.sleep(for: .milliseconds(300)) }
        }
        do {
            let data = try await serialized { try await self.withTimeout(30) { try await self.fetchJSON(path: path, kind: kind) } }
            let value = try JSONDecoder().decode(T.self, from: data)
            // Never save an empty list (it may just not have loaded yet).
            if !String(decoding: data.prefix(4000), as: UTF8.self).contains("\"albums\":[]") { store(path, data) }
            return value
        } catch {
            if let stale = cached(path, allowStale: true), let value = try? JSONDecoder().decode(T.self, from: stale) {
                return value
            }
            throw error
        }
    }

    /// Raw report of what AOTY returns for a path. Used by Settings → Diagnostics.
    func probe(_ path: String, kind: Kind) async -> String {
        do {
            return try await serialized {
                try await self.withTimeout(30) {
                    try await self.ensureOrigin()
                    try await self.throttle()
                    let body = self.extractorJS + """

                    let r, html;
                    try { r = await fetch(path, { credentials: "include", headers: { "Accept": "text/html" } }); html = await r.text(); }
                    catch (e) { return "fetch threw: " + e; }
                    const doc = new DOMParser().parseFromString(html, "text/html");
                    let count = "?";
                    try { const o = aotyExtract(kind, html, r.url); count = (o.albums || o.items || o.tracklist || []).length; } catch (e) { count = "extract error: " + e; }
                    return [
                      "HTTP " + r.status + (r.redirected ? " (redirected)" : ""),
                      "URL " + r.url,
                      "bytes " + html.length,
                      "title " + (doc.title || "").trim().slice(0, 80),
                      "challenge " + aotyIsChallenge(html, r.status),
                      ".albumBlock " + doc.querySelectorAll(".albumBlock").length + ", .albumListRow " + doc.querySelectorAll(".albumListRow").length,
                      "items " + count,
                      "sample " + aotySample(doc),
                      "text " + (doc.body ? doc.body.innerText || doc.body.textContent : "").replace(/\\s+/g, " ").trim().slice(0, 240)
                    ].join("\\n");
                    """
                    let result = try await self.webView.runAsyncJS(body, args: ["path": path, "kind": kind.rawValue])
                    return (result as? String) ?? "no result"
                }
            }
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    /// Run a JS snippet in the hidden web view (used to parse non-AOTY HTML such as Genius pages).
    /// `body` must `return` a string.
    func runJS(_ body: String, args: [String: Any], timeout: Double = 20) async throws -> String {
        try await serialized {
            try await self.withTimeout(timeout) {
                if self.webView.url == nil { try await self.ensureOrigin() }
                let r = try await self.webView.runAsyncJS(body, args: args)
                guard let s = r as? String else { throw ScrapeError.script("no result") }
                return s
            }
        }
    }

    func forget(_ path: String) {
        memory[path] = nil
        try? FileManager.default.removeItem(at: key(path))
    }

    /// Pull to refresh: for a few seconds, fetch pages fresh instead of using saved copies.
    private var bypassUntil = Date.distantPast
    func bypassCache(for seconds: TimeInterval = 4) { bypassUntil = Date().addingTimeInterval(seconds) }

    func clearCache() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Called by the challenge sheet when the user closes it.
    private var lastChallengeDone: Date?

    func challengeFinished() {
        lastChallengeDone = Date()
        challenge = nil
        originReady = false
        clearCache()
    }

    /// POST a form the way AOTY's own buttons do, then run the extractor on the HTML it returns.
    func postExtract<T: Decodable>(_ path: String, form: [String: String], kind: Kind, as type: T.Type) async throws -> T {
        let body = form.map { k, v in
            (k.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? k) + "=" + (v.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? v)
        }.joined(separator: "&")
        let js = extractorJS + """

        const r = await fetch(path, { method: "POST", credentials: "include",
          headers: { "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8", "X-Requested-With": "XMLHttpRequest" },
          body: form });
        const html = "<html><body>" + (await r.text()) + "</body></html>";
        if (aotyIsChallenge(html, r.status)) return JSON.stringify({ __challenge: true });
        if (!r.ok) return JSON.stringify({ __http: r.status });
        return JSON.stringify(aotyExtract(kind, html, location.href));
        """
        let out: String = try await serialized {
            try await self.withTimeout(30) {
                try await self.ensureOrigin()
                try await self.throttle()
                guard let s = try await self.webView.runAsyncJS(js, args: ["path": path, "form": body, "kind": kind.rawValue]) as? String else {
                    throw ScrapeError.script("no result")
                }
                return s
            }
        }
        if out.contains("\"__challenge\"") { throw ScrapeError.blocked }
        if out.contains("\"__http\"") { throw ScrapeError.http(0, path) }
        return try JSONDecoder().decode(T.self, from: Data(out.utf8))
    }

    // MARK: - Core

    private func fetchJSON(path: String, kind: Kind) async throws -> Data {
        let url = URL(string: "https://www.albumoftheyear.org" + path)!

        // Attempt 1: same-origin fetch from the hidden web view.
        try await ensureOrigin()
        if case let .ok(data) = try await runFetch(path: path, kind: kind) {
            // A filtered artist list came back empty: load the page for real (in case the list
            // is filled in by the site's own scripts) before believing it's empty.
            if kind == .artist, path.contains("?type="), String(decoding: data, as: UTF8.self).contains("\"albums\":[]") {
                try? await navigate(to: url)
                originReady = true
                if case let .ok(d2) = try await runOnLoadedPage(kind: kind, path: path, waitForBlocks: true) { return d2 }
            }
            return data
        }

        // Challenged on fetch: try loading the page for real in the hidden view
        // (a full navigation sometimes passes where fetch() doesn't).
        try await navigate(to: url)
        originReady = true
        if case let .ok(data) = try await runOnLoadedPage(kind: kind, path: path) { return data }

        // Still challenged: ask the user to pass the check, and fail this request.
        // If they just finished one, don't loop them straight back into the sheet.
        if let done = lastChallengeDone, Date().timeIntervalSince(done) < 90 {
            throw ScrapeError.stillBlocked
        }
        challenge = Challenge(url: url)
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
        const out = aotyExtract(kind, html, r.url);
        const n = (out.albums || out.items || out.reviews || []).length + (out.title ? 1 : 0);
        if (n === 0 && (kind === "blocks" || kind === "chart" || kind === "album")) {
          const d = new DOMParser().parseFromString(html, "text/html");
          return JSON.stringify({ __empty: "Page: " + (d.title || "untitled").trim().slice(0, 60) + " · " + html.length + " bytes · " + r.url.replace("https://www.albumoftheyear.org", "") });
        }
        return JSON.stringify(out);
        """
        return try await evaluate(body, args: ["path": path, "kind": kind.rawValue], path: path)
    }

    private func runOnLoadedPage(kind: Kind, path: String, waitForBlocks: Bool = false) async throws -> Outcome {
        let body = extractorJS + """

        if (wait) { for (let i = 0; i < 20 && !document.querySelector(".albumBlock"); i++) await new Promise(r => setTimeout(r, 200)); }
        const html = document.documentElement.outerHTML;
        if (aotyIsChallenge(html, 200)) return JSON.stringify({ __challenge: true });
        const out = aotyExtract(kind, html, location.href);
        const n = (out.albums || out.items || out.reviews || []).length + (out.title ? 1 : 0);
        if (n === 0 && (kind === "blocks" || kind === "chart" || kind === "album")) return JSON.stringify({ __empty: "Page: " + (document.title || "untitled").trim().slice(0, 60) + " · " + html.length + " bytes (loaded)" });
        return JSON.stringify(out);
        """
        return try await evaluate(body, args: ["kind": kind.rawValue, "wait": waitForBlocks], path: path)
    }

    private func evaluate(_ body: String, args: [String: Any], path: String) async throws -> Outcome {
        let result: Any?
        do {
            result = try await webView.runAsyncJS(body, args: args)
        } catch {
            throw ScrapeError.script(error.localizedDescription)
        }
        guard let json = result as? String, let data = json.data(using: .utf8) else {
            throw ScrapeError.script("empty result")
        }
        if let probe = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if probe["__challenge"] != nil { return .challenged }
            if let code = probe["__http"] as? Int { throw ScrapeError.http(code, path) }
            if let info = probe["__empty"] as? String { throw ScrapeError.empty(info) }
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

    private func throttle() async throws {
        let wait = minGap - Date().timeIntervalSince(lastFetch)
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        lastFetch = Date()
    }

    private final class Once { var done = false }

    /// Race `op` against a timer. Unlike a task group this returns as soon as the timer
    /// fires, even if WebKit never calls back, and it unsticks any pending navigation.
    private func withTimeout<T>(_ seconds: Double, _ op: @escaping @MainActor () async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            let once = Once()
            let work = Task { @MainActor in
                do {
                    let value = try await op()
                    if !once.done { once.done = true; cont.resume(returning: value) }
                } catch {
                    if !once.done { once.done = true; cont.resume(throwing: error) }
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                if !once.done {
                    once.done = true
                    work.cancel()
                    self.webView.stopLoading()
                    self.navContinuation?.resume(throwing: ScrapeError.timeout)
                    self.navContinuation = nil
                    self.originReady = false
                    cont.resume(throwing: ScrapeError.timeout)
                }
            }
        }
    }

    /// Run operations one at a time, in order.
    private func serialized<T>(_ op: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = queueTail
        pending += 1
        let task = Task { @MainActor () throws -> T in
            defer { self.pending -= 1 }
            _ = await previous.value
            return try await op()
        }
        queueTail = Task { _ = try? await task.value }
        return try await task.value
    }

    // MARK: - Cache

    /// Saved pages are tied to the parser version, so an app update never shows pages read the old way.
    private lazy var parserVersion: String = {
        var h: UInt64 = 1469598103934665603             // FNV-1a over extract.js
        for b in extractorJS.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 36)
    }()

    private func pruneOldCache() {
        let prefix = parserVersion + "-"
        let dir = cacheDir
        Task.detached(priority: .background) {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for f in files where !f.hasPrefix(prefix) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
        }
    }

    private func key(_ path: String) -> URL {
        let safe = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? String(path.hashValue)
        return cacheDir.appendingPathComponent(parserVersion + "-" + String(safe.prefix(200)) + ".json")
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


extension WKWebView {
    /// Wraps the completion-handler form of callAsyncJavaScript. The `async` Swift overlay lives in
    /// libswiftWebKit, which iOS 18 doesn't ship, and linking it crashes the app at launch.
    func runAsyncJS(_ js: String, args: [String: Any], world: WKContentWorld = .defaultClient) async throws -> Any? {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Any?, Error>) in
            self.callAsyncJavaScript(js, arguments: args, in: nil, in: world) { result in
                switch result {
                case let .success(value): cont.resume(returning: value)
                case let .failure(error): cont.resume(throwing: error)
                }
            }
        }
    }
}
