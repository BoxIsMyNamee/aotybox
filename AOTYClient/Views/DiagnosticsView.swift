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
                Button(capturing ? "Capturing…" : "Capture friends & sort info (2)") { Task { await captureHeart() } }
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
          try { const r = await fetch(u, Object.assign({ credentials: "include", signal: c.signal }, opt || {})); return r.status + " " + r.url.replace(location.origin, "") + " :: " + await r.text(); }
          catch (e) { return "ERR " + e.message; } finally { clearTimeout(t); }
        };
        const me = (__ME__ || "").trim();
        const ratingsOf = h => { const d = new DOMParser().parseFromString(h.replace(/^[^:]*:: /, ""), "text/html");
          return [...d.querySelectorAll(".albumReviewRow .rating, .reviewRow .rating, .rating")].slice(0, 8).map(e => e.textContent.trim()).join(","); };
        // 1. Do review pages sort by path or query? (first scores on each)
        for (const p of ["/user/" + me + "/reviews/", "/user/" + me + "/reviews/highest/", "/user/" + me + "/reviews/lowest/",
                         "/user/" + me + "/reviews/?sort=highest", "/user/" + me + "/reviews/popular/", "/user/" + me + "/reviews/?type=highest"]) {
          const h = await get(p);
          out.push("REVIEWS " + p + " -> " + h.slice(0, 60).split(" :: ")[0] + " · scores " + ratingsOf(h));
        }
        // 2. "Following" distribution on an album (AOTY's own toggle on album pages).
        const al = await get("/user/" + me + "/reviews/");
        const m = al.match(/\/album\/(\d+)-[^"']+\.php/);
        if (m) {
          out.push("ALBUM ID " + m[1] + " " + m[0]);
          const r = await get("/scripts/changeDistribution.php", { method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8", "X-Requested-With": "XMLHttpRequest" },
            body: "type=album&format=following&itemID=" + m[1] });
          out.push("DIST FOLLOWING: " + r.slice(0, 3000).replace(/\s+/g, " "));
          const slug = m[0].replace("/album/", "").replace(".php", "");
          for (const q of ["?type=following", "?following=1", "?sort=following", "following/"]) {
            const h = await get("/album/" + slug + "/user-reviews/" + q);
            const d = new DOMParser().parseFromString(h.replace(/^[^:]*:: /, ""), "text/html");
            out.push("USER-REVIEWS " + q + " -> " + h.slice(0, 80).split(" :: ")[0] + " · names " +
              [...d.querySelectorAll(".userReviewName a")].slice(0, 6).map(e => e.textContent.trim()).join(","));
          }
          const ap = await get(m[0]);
          const i = ap.search(/changeDistribution|Following/);
          out.push("ALBUM PAGE TOGGLE: " + (i < 0 ? "none" : ap.slice(Math.max(0, i - 600), i + 900).replace(/\s+/g, " ")));
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
