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
                Button(capturing ? "Capturing…" : "Capture notification info") { Task { await captureHeart() } }
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
        // The header (avatar + its little notification dot), and the notifications page.
        const home = await (await fetch("/", { credentials: "include" })).text();
        const d = new DOMParser().parseFromString(home, "text/html");
        const av = [...d.querySelectorAll("img")].find(i => /\/user\//.test(i.getAttribute("src") || "") && !i.closest(".albumReviewRow, .content"));
        let box = av; for (let k = 0; k < 4 && box && box.parentElement; k++) box = box.parentElement;
        out.push("HEADER: " + (box ? box.outerHTML.replace(/\s+/g, " ").slice(0, 4000) : "no avatar found"));
        [...d.querySelectorAll("[class*='otif'], [id*='otif'], [class*='dot'], [class*='Dot'], [class*='unread'], [class*='badge']")].slice(0, 12)
          .forEach(el => out.push("CAND: " + el.outerHTML.replace(/\s+/g, " ").slice(0, 500)));
        d.querySelectorAll("script:not([src])").forEach(sc => {
          const t = sc.textContent; const i = t.search(/otif/i);
          if (i >= 0) out.push("INLINE: " + t.slice(Math.max(0, i - 400), i + 800));
        });
        const np = await (await fetch("/notifications/", { credentials: "include" })).text();
        const nd = new DOMParser().parseFromString(np, "text/html");
        const items = [...nd.querySelectorAll("[id^='notification_'], .notification, [class*='notification']")];
        out.push("NOTIF ITEMS: " + items.length);
        items.slice(0, 3).forEach(el => out.push("ITEM: " + el.outerHTML.replace(/\s+/g, " ").slice(0, 1200)));
        if (!items.length) { const c = nd.querySelector(".content, #content, main"); out.push("NOTIF PAGE: " + (c ? c.outerHTML : np).replace(/\s+/g, " ").slice(0, 3000)); }
        return out.join("\n\n").slice(0, 30000);
        """#
        do {
            let r = try await AOTYScraper.shared.runJS(js, args: [:], timeout: 60)
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
