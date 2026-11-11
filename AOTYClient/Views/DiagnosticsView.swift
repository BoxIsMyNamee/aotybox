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
        await new Promise(r => setTimeout(r, 3000));          // let AOTY's own scripts add the dot
        const mp = document.querySelector(".mobileProfile");
        out.push("PROFILE AFTER SCRIPTS: " + (mp ? mp.outerHTML.replace(/\s+/g, " ").slice(0, 1500) : "none"));
        const hd = document.querySelector("#header");
        out.push("HEADER AFTER SCRIPTS: " + (hd ? hd.outerHTML.replace(/\s+/g, " ").slice(0, 2500) : "none"));
        const srcs = [...document.querySelectorAll("script[src]")].map(s => s.getAttribute("src")).filter(s => s && s.startsWith("/scripts/") && !s.includes("vendor"));
        out.push("SCRIPTS: " + srcs.join(" "));
        const get = async (u) => {
          const c = new AbortController(); const t = setTimeout(() => c.abort(), 15000);
          try { return await (await fetch(u, { credentials: "include", signal: c.signal })).text(); } catch (e) { return ""; } finally { clearTimeout(t); }
        };
        for (const src of srcs) {
          const t = await get(src);
          const re = /mobileProfile|otifCount|otificationCount|unread|newNotif|notifDot|checkNotif|getNotif|countNotif|notifications\.php|Notification\.php/gi; let m, n = 0, last = -5000;
          while ((m = re.exec(t)) && n < 10) { if (m.index - last < 800) continue; last = m.index; out.push("JS " + src + ": " + t.slice(Math.max(0, m.index - 400), m.index + 800)); n++; }
        }
        document.querySelectorAll("script:not([src])").forEach(sc => {
          const t = sc.textContent; const i = t.search(/otif|unread/i);
          if (i >= 0) out.push("INLINE: " + t.slice(Math.max(0, i - 400), i + 900));
        });
        return out.join("\n\n").slice(0, 30000);
        """#
        do {
            let r = try await AOTYScraper.shared.runOnRealPage("/", js, timeout: 60)
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
