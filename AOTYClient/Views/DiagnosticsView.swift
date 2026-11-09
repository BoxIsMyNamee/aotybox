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
                Button(capturing ? "Capturing…" : "Capture artist page info") { Task { await captureHeart() } }
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
        // Artist page: album blocks (scores), follow button, and the scripts behind them.
        const path = "/artist/105779-underscores/";
        const ap = await (await fetch(path, { credentials: "include" })).text();
        const ad = new DOMParser().parseFromString(ap, "text/html");
        out.push("SIGNED IN: " + !!ad.querySelector("a[href*='logout'], a[href*='/settings/']"));
        const blocks = [...ad.querySelectorAll(".albumBlock")];
        out.push("BLOCKS: " + blocks.length);
        blocks.slice(0, 4).forEach((b, i) => out.push("BLOCK " + i + ": " + b.outerHTML.replace(/\s+/g, " ").slice(0, 1800)));
        const fish = blocks.find(b => /fishmonger/i.test(b.textContent));
        if (fish) out.push("FISHMONGER: " + fish.outerHTML.replace(/\s+/g, " ").slice(0, 1800));
        const fc = ad.querySelector(".followCount");
        let fb = fc; for (let k = 0; k < 3 && fb && fb.parentElement; k++) fb = fb.parentElement;
        out.push("FOLLOW AREA: " + (fb ? fb.outerHTML.replace(/\s+/g, " ").slice(0, 2500) : "none"));
        [...ad.querySelectorAll("[class*='ollow'], [id*='ollow']")].slice(0, 8).forEach(el =>
          out.push("FOLLOW EL: " + el.outerHTML.replace(/\s+/g, " ").slice(0, 600)));
        const srcs = [...new Set([...ad.querySelectorAll("script[src]")].map(s => s.getAttribute("src")))].filter(s => s && s.startsWith("/scripts/"));
        out.push("SCRIPTS: " + srcs.join(" "));
        for (const src of srcs) {
          const t = await (await fetch(src, { credentials: "include" })).text();
          const re = /ollow/g; let m, n = 0, last = -2000;
          while ((m = re.exec(t)) && n < 12) { if (m.index - last < 900) continue; last = m.index; out.push("JS " + src + ": " + t.slice(Math.max(0, m.index - 300), m.index + 700)); n++; }
        }
        return out.join("\n\n").slice(0, 30000);
        """#
        do {
            let r = try await AOTYScraper.shared.runJS(js.replacingOccurrences(of: "__ME__", with: "\"\(myUsername)\""), args: [:], timeout: 75)
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
