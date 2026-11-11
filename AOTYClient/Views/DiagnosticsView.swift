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
        await new Promise(r => setTimeout(r, 4000));
        out.push("UA: " + navigator.userAgent);
        out.push("BODY CLASS: " + document.body.className + " · HTML CLASS: " + document.documentElement.className);
        // Pseudo-elements and tiny round things anywhere on the page (the dot may be CSS-only).
        const mp = document.querySelector(".mobileProfile");
        for (const el of [mp, mp && mp.querySelector("button"), mp && mp.querySelector("img")].filter(Boolean)) {
          for (const pe of ["::before", "::after"]) {
            const cs = getComputedStyle(el, pe);
            if (cs.content && cs.content !== "none" && cs.content !== "normal")
              out.push("PSEUDO " + el.tagName + pe + ": content=" + cs.content + " bg=" + cs.backgroundColor + " display=" + cs.display + " size=" + cs.width + "x" + cs.height);
          }
        }
        [...document.querySelectorAll("body *")].forEach(el => {
          const r = el.getBoundingClientRect(); if (!r.width || r.width > 20 || r.height > 20) return;
          const cs = getComputedStyle(el);
          if (parseFloat(cs.borderRadius) >= r.width / 2 - 1 && cs.backgroundColor !== "rgba(0, 0, 0, 0)")
            out.push("DOT? " + el.outerHTML.slice(0, 300) + " · parent " + (el.parentElement ? el.parentElement.outerHTML.slice(0, 300) : "") + " · bg " + cs.backgroundColor);
        });
        // Anything next to the profile button in the header.
        const hd = document.querySelector("#header");
        out.push("HEADER HTML: " + (hd ? hd.innerHTML.replace(/\s+/g, " ").replace(/<div id="userLinks"[\s\S]*?<\/div><\/div><\/div>/, "[userLinks]").slice(0, 2500) : "none"));
        // Stylesheet rules that mention notification/dot classes.
        for (const ss of document.styleSheets) {
          let rules; try { rules = ss.cssRules; } catch (e) { continue; }
          for (const r of rules || []) { const t = r.cssText || ""; if (/otif|unread|Dot\b|\.dot\b|mobileProfile/i.test(t) && t.length < 400) out.push("CSS: " + t); }
        }
        // Network: what the page asked AOTY for after loading.
        performance.getEntriesByType("resource").filter(e => /scripts\/|notif/i.test(e.name) && !/\.js|\.css/.test(e.name)).forEach(e => out.push("REQ: " + e.name));
        return out.join("\n").slice(0, 30000);
        """#
        // The notifications page too, loaded for real.
        let js2 = #"""
        await new Promise(r => setTimeout(r, 3000));
        const out = [];
        out.push("TEXT: " + document.body.innerText.replace(/\s+/g, " ").slice(0, 1500));
        const rows = [...document.querySelectorAll("[id^='notification_'], [class*='otification']")].filter(e => !e.closest("#header"));
        out.push("ROWS: " + rows.length);
        rows.slice(0, 5).forEach(el => out.push("ROW: " + el.outerHTML.replace(/\s+/g, " ").slice(0, 1200)));
        performance.getEntriesByType("resource").filter(e => /scripts\//.test(e.name) && !/\.js|\.css/.test(e.name)).forEach(e => out.push("REQ: " + e.name));
        return out.join("\n\n");
        """#
        do {
            var r = try await AOTYScraper.shared.runOnRealPage("/", js, timeout: 60)
            r += "\n\n========\n\n" + ((try? await AOTYScraper.shared.runOnRealPage("/notifications/", js2, timeout: 40)) ?? "notifications page failed")
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
