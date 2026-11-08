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
        // Your rating/review box on album pages: one you've reviewed (newest on your profile) and one you probably haven't.
        const me = (__ME__ || "").trim();
        let reviewed = null;
        if (me) {
          const rp = await (await fetch("/user/" + me + "/reviews/", { credentials: "include" })).text();
          const rd = new DOMParser().parseFromString(rp, "text/html");
          const link = [...rd.querySelectorAll("a[href*='/album/']")].map(a => a.getAttribute("href")).find(h => /\/album\/\d+-[^/]+\.php/.test(h));
          reviewed = link || null;
        }
        for (const [label, path] of [["REVIEWED ALBUM", reviewed], ["OTHER ALBUM", "/album/5361-the-beatles-the-white-album.php"]]) {
          if (!path) { out.push(label + ": none found"); continue; }
          const ap = await (await fetch(path, { credentials: "include" })).text();
          const ad = new DOMParser().parseFromString(ap, "text/html");
          out.push(label + " PATH: " + path);
          const sel = "#ratingBlock, #currentRatingBlock, #reviewBlock, #currentReviewBlock, #ratingContainer, .addListened, .removeListened, .addAlbumLike, .removeAlbumLike, [class*='Listen'], [class*='library'], [class*='Library'], textarea, #postReviewButton, .insertReview, .albumActionBox, [class*='userRating']";
          const seen = new Set();
          [...ad.querySelectorAll(sel)].forEach(el => {
            let box = el.closest("[id]") || el.parentElement || el;
            for (let k = 0; k < 2 && box.parentElement && box.outerHTML.length < 300; k++) box = box.parentElement;
            if (seen.has(box)) return; seen.add(box);
            if (seen.size <= 8) out.push(label + " BOX: " + box.outerHTML.replace(/\s+/g, " ").slice(0, 1400));
          });
        }

        // Notifications bell in the signed-in header
        const home = await (await fetch("/", { credentials: "include" })).text();
        const hdoc = new DOMParser().parseFromString(home, "text/html");
        const bells = [...hdoc.querySelectorAll("a[href*='otif'], [class*='otif'], [id*='otif'], .fa-bell, [class*='bell'], [class*='Bell']")];
        out.push("BELL COUNT: " + bells.length);
        bells.slice(0, 4).forEach((b, i) => {
          const box = b.closest("a") || b.parentElement || b;
          out.push("BELL " + i + ": " + (box.parentElement || box).outerHTML.slice(0, 900));
        });
        if (!bells.length) {
          const i = home.search(/notif|bell/i);
          out.push("BELL TEXT: " + (i < 0 ? "none" : home.slice(Math.max(0, i - 400), i + 600)));
        }
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
          const re = /addListened|removeListened|insertRating|insertReview|AlbumLike|addLibrary|SpinList|removeLibrary/gi; let m, n = 0;
          while ((m = re.exec(js)) && n < 14) { out.push("JS " + src + ": " + js.slice(Math.max(0, m.index - 300), m.index + 700)); re.lastIndex = m.index + 700; n++; }
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
