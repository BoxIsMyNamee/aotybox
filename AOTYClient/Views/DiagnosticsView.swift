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
                Button(capturing ? "Capturing…" : "Capture AOTY button info") { Task { await captureHeart() } }
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
        const page = await (await fetch("/album/2915-outkast-aquemini/user-reviews/", { credentials: "include" })).text();
        const doc = new DOMParser().parseFromString(page, "text/html");
        out.push("SIGNED IN: " + !!doc.querySelector("a[href*='logout'], a[href*='signout'], a[href*='/settings/']"));
        const links = doc.querySelectorAll(".albumReviewLinks");
        for (let i = 0; i < Math.min(2, links.length); i++) out.push("LINKS: " + links[i].outerHTML.slice(0, 1500));
        doc.querySelectorAll("script:not([src])").forEach(s => {
          const t = s.textContent; const re = /like/gi; let m, n = 0;
          while ((m = re.exec(t)) && n < 4) { out.push("INLINE: " + t.slice(Math.max(0, m.index - 300), m.index + 700)); re.lastIndex = m.index + 700; n++; }
        });
        const artistPage = await (await fetch("/artist/183-kanye-west/", { credentials: "include" })).text();
        const adoc = new DOMParser().parseFromString(artistPage, "text/html");
        const credit = adoc.querySelector(".artistCreditList");
        out.push("CREDIT BUTTON: " + (credit ? credit.outerHTML : "none"));
        const srcs = [...new Set([...doc.querySelectorAll("script[src]"), ...adoc.querySelectorAll("script[src]")].map(s => s.getAttribute("src")))].filter(s => s && s.startsWith("/scripts/") && !s.includes("vendor"));
        out.push("SCRIPTS: " + srcs.join(" "));
        for (const src of srcs) {
          const js = await (await fetch(src, { credentials: "include" })).text();
          const re = /artistCreditList|insertReviewLike/gi; let m, n = 0;
          while ((m = re.exec(js)) && n < 6) { out.push("JS " + src + ": " + js.slice(Math.max(0, m.index - 300), m.index + 700)); re.lastIndex = m.index + 700; n++; }
        }
        return out.join("\n\n").slice(0, 30000);
        """#
        do {
            let r = try await AOTYScraper.shared.runJS(js, args: [:])
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
