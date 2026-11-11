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
                Button(capturing ? "Capturing…" : "Capture search info") { Task { await captureHeart() } }
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
        const get = async (u, opt) => {
          const c = new AbortController(); const t = setTimeout(() => c.abort(), 15000);
          try { const r = await fetch(u, Object.assign({ credentials: "include", signal: c.signal }, opt || {})); return r.status + " " + await r.text(); }
          catch (e) { return "ERR " + e.message; } finally { clearTimeout(t); }
        };
        // 1. Artist search results: every artist link with its surroundings.
        const sp = await get("/search/artists/?q=mac+miller");
        const d = new DOMParser().parseFromString(sp.replace(/^\d+ /, ""), "text/html");
        const links = [...d.querySelectorAll("a[href*='/artist/']")];
        out.push("ARTIST LINKS: " + links.length);
        links.slice(0, 12).forEach(a => out.push("LINK " + a.getAttribute("href") + " | " + JSON.stringify(a.textContent.trim().slice(0, 60)) + " | parent " + (a.parentElement ? a.parentElement.outerHTML.replace(/\s+/g, " ").slice(0, 500) : "")));
        // 2. The search box's suggestion source in AOTY's scripts.
        for (const src of ["/scripts/loggedInScript.js", "/scripts/main.js"]) {
          const t = await get(src);
          let i = t.indexOf("autocomplete"), n = 0;
          while (i >= 0 && n < 4) { out.push("AC " + src + ": " + t.slice(Math.max(0, i - 1500), i + 1500)); i = t.indexOf("autocomplete", i + 1500); n++; }
        }
        return out.join("\n\n").slice(0, 40000);
        """#
        do {
            let r = try await AOTYScraper.shared.runJS(js, args: [:], timeout: 50)
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
