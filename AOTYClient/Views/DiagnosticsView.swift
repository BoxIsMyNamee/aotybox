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
        out.push("PAGE: " + location.href);
        // Every type link on the artist page, its markup around it, and how many releases each really has.
        const links = [...document.querySelectorAll("a[href*='type='], option[value*='type=']")];
        const first = links[0];
        let box = first; for (let k = 0; k < 3 && box && box.parentElement; k++) box = box.parentElement;
        out.push("TYPE MENU: " + (box ? box.outerHTML.replace(/\s+/g, " ").slice(0, 3000) : "none"));
        const seen = new Set();
        for (const el of links) {
          const h = el.getAttribute("href") || el.getAttribute("value") || "";
          if (seen.has(h)) continue; seen.add(h);
          let n = "?";
          try {
            const t = await (await fetch(h, { credentials: "include" })).text();
            n = new DOMParser().parseFromString(t, "text/html").querySelectorAll(".albumBlock").length;
          } catch (e) { n = "err"; }
          out.push("TYPE " + JSON.stringify(el.textContent.trim()) + " -> " + h + " · " + n + " blocks (fetched)");
        }
        return out.join("\n");
        """#
        do {
            var parts: [String] = []
            let base = (await AOTYAPI.shared.findArtistPath(name: "kanye west")) ?? "/artist/183-kanye-west/"
            let b = base.hasSuffix("/") ? base : base + "/"
            parts.append((try? await AOTYScraper.shared.runOnRealPage(b, js, timeout: 90)) ?? "FAILED " + b)
            let r = parts.joined(separator: "\n\n")
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
