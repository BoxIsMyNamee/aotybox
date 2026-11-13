import SwiftUI

/// Shows exactly what AOTY returns to this phone for each page the app reads.
/// Screenshot this when something doesn't load.
struct DiagnosticsView: View {
    private let probes: [(String, String, AOTYScraper.Kind)] = [
        ("This Week", "/releases/this-week/", .blocks),
        ("New", "/releases/", .blocks),
        ("Upcoming", "/upcoming/", .blocks),
        ("Charts (critics)", "/ratings/6-highest-rated/\(Calendar.current.component(.year, from: .now))/1", .chart),
        ("Album", "/album/2915-outkast-aquemini.php", .album),
        ("Artist", "/artist/183-kanye-west/", .artist),
        ("Artist singles", "/artist/183-kanye-west/?type=single", .artist),
        ("Artist reissues", "/artist/183-kanye-west/?type=reissue", .artist),
    ]
    @State private var results: [String: String] = [:]
    @State private var running = false
    @State private var heartInfo: String?
    @AppStorage("profileUsername") private var myUsername = ""
    @State private var capturing = false

    var body: some View {
        List {
            Section {
                Button(running ? "Running…" : "Run diagnostics") { Task { await run() } }
                    .disabled(running)
                Button("Copy results") {
                    UIPasteboard.general.string = probes.map { "## \($0.0) \($0.1)\n\(results[$0.1] ?? "-")" }.joined(separator: "\n\n")
                }
                .disabled(results.isEmpty || running)
            } footer: {
                Text("Loads each page the app uses and reports what came back. Takes a few seconds.")
            }
            Section {
                Button(capturing ? "Capturing…" : "Capture friends & sort info") { Task { await captureHeart() } }
                    .disabled(capturing)
                if let heartInfo {
                    Text(heartInfo.prefix(1500) + (heartInfo.count > 1500 ? "…" : ""))
                        .font(.caption2.monospaced()).textSelection(.enabled)
                }
            } header: {
                Text("AOTY buttons")
            } footer: {
                Text(heartInfo == nil ? "Reads how AOTY's like button works while you're signed in. The result is copied so you can paste it to Claude. It only contains page code, no password."
                                      : "Copied to clipboard. Paste it into the chat.")
            }
            ForEach(probes, id: \.1) { name, path, _ in
                Section(name) {
                    Text(results[path] ?? "—")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Diagnostics")
    }

    private func captureHeart() async {
        capturing = true; defer { capturing = false }
        let js = #"""
        const out = [];
        const get = async (u) => {
          const c = new AbortController(); const t = setTimeout(() => c.abort(), 15000);
          try { return await (await fetch(u, { credentials: "include", signal: c.signal })).text(); }
          catch (e) { out.push("FETCH " + u + " failed: " + e.message); return ""; } finally { clearTimeout(t); }
        };
        const me = (__ME__ || "").trim();
        // 1. Your reviews page: its sort options.
        const rp = await get("/user/" + me + "/reviews/");
        const rd = new DOMParser().parseFromString(rp, "text/html");
        [...rd.querySelectorAll("a[href*='sort'], a[href*='?'], select, option, #sortDrop, .menuDropSelected")].slice(0, 25)
          .forEach(el => out.push("REVIEWS SORT: " + el.outerHTML.replace(/\s+/g, " ").slice(0, 400)));
        // 2. An album page you rated: anything about friends' ratings.
        const link = [...rd.querySelectorAll("a[href*='/album/']")].map(a => a.getAttribute("href")).find(h => /\/album\/\d+-[^/]+\.php/.test(h));
        out.push("ALBUM: " + link);
        if (link) {
          const ap = await get(link);
          let last = -5000, n = 0;
          for (const m of ap.matchAll(/friend/gi)) {
            if (m.index - last < 1200 || n >= 6) continue;
            last = m.index; n++;
            out.push("FRIEND CTX: " + ap.slice(Math.max(0, m.index - 300), m.index + 1200).replace(/\s+/g, " "));
          }
          out.push("FRIEND MENTIONS: " + n);
          const ad = new DOMParser().parseFromString(ap, "text/html");
          [...ad.querySelectorAll("a[href*='friend'], [class*='riend'], [id*='riend']")].slice(0, 8)
            .forEach(el => out.push("FRIEND EL: " + el.outerHTML.replace(/\s+/g, " ").slice(0, 1500)));
        }
        return out.join("\n\n").slice(0, 40000);
        """#
        do {
            let r = try await AOTYScraper.shared.runJS(js.replacingOccurrences(of: "__ME__", with: "\"\(myUsername)\""), args: [:], timeout: 50)
            heartInfo = r
            UIPasteboard.general.string = r
        } catch {
            heartInfo = "Failed: \(error.localizedDescription)"
        }
    }

    private func run() async {
        running = true; defer { running = false }
        results = [:]
        for (_, path, kind) in probes {
            results[path] = "…"
            results[path] = await AOTYScraper.shared.probe(path, kind: kind)
        }
    }
}
