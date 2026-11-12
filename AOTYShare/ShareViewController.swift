import UIKit
import UniformTypeIdentifiers

/// "AOTYbox" in the share sheet: takes the shared text (e.g. a Google Keep note) and opens
/// the app's Notes tab with it, through aotybox://notes?b64=…
final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        Task { await handle() }
    }

    private func handle() async {
        let text = await sharedText()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return finish() }
        var c = URLComponents()
        c.scheme = "aotybox"
        if let link = musicLink(in: text), let d = link.absoluteString.data(using: .utf8) {
            // A song/album link from Marvis, Apple Music, song.link, Spotify…: open the album in AOTY.
            c.host = "open"
            c.queryItems = [URLQueryItem(name: "b64", value: d.base64EncodedString())]
        } else {
            guard let data = text.data(using: .utf8) else { return finish() }
            c.host = "notes"
            c.queryItems = [URLQueryItem(name: "b64", value: data.base64EncodedString())]
        }
        if let url = c.url, openApp(url) { return finish() }
        // Couldn't hand off directly: leave it on the clipboard so Notes' Paste picks it up.
        UIPasteboard.general.string = text
        showMessage("Copied. Open AOTYbox → Notes → Paste.")
        try? await Task.sleep(for: .seconds(1.6))
        finish()
    }

    /// The first music-service link in what was shared (it may be inside a sentence).
    private func musicLink(in text: String) -> URL? {
        let hosts = ["music.apple.com", "itunes.apple.com", "song.link", "album.link", "odesli.co",
                     "open.spotify.com", "spotify.link", "tidal.com", "music.youtube.com", "deezer.com"]
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let ns = text as NSString
        for m in det.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let u = m.url, let h = u.host?.lowercased() else { continue }
            if hosts.contains(where: { h == $0 || h.hasSuffix("." + $0) }) { return u }
        }
        return nil
    }

    /// Everything shared, text and links together (apps often send a sentence plus a separate link).
    private func sharedText() async -> String? {
        var parts: [String] = []
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for p in item.attachments ?? [] {
                if p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let u = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    parts.append(u.absoluteString)
                } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let s = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) {
                    if let str = s as? String { parts.append(str) }
                    else if let d = s as? Data, let str = String(data: d, encoding: .utf8) { parts.append(str) }
                }
            }
            if parts.isEmpty, let t = item.attributedContentText?.string, !t.isEmpty { parts.append(t) }
        }
        // Text first (that's the note), then any links that weren't already in it.
        let texts = parts.filter { !$0.hasPrefix("http") }
        let links = parts.filter { $0.hasPrefix("http") && !texts.joined().contains($0) }
        let all = (texts + links).joined(separator: "\n")
        return all.isEmpty ? nil : all
    }

    /// Extensions can't call UIApplication.shared; find the application object through the
    /// responder chain and call its open(_:options:completionHandler:) by selector.
    @discardableResult private func openApp(_ url: URL) -> Bool {
        typealias OpenFn = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
        let sel = NSSelectorFromString("openURL:options:completionHandler:")
        var r: UIResponder? = self
        while let current = r {
            if NSStringFromClass(type(of: current)).contains("Application"), current.responds(to: sel),
               let imp = current.method(for: sel) {
                let f = unsafeBitCast(imp, to: OpenFn.self)
                f(current, sel, url as NSURL, NSDictionary(), nil)
                return true
            }
            r = current.next
        }
        return false
    }

    private func showMessage(_ s: String) {
        label.text = s
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .headline)
        label.backgroundColor = .secondarySystemBackground
        label.layer.cornerRadius = 16; label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 280),
            label.heightAnchor.constraint(equalToConstant: 90),
        ])
    }

    private func finish() { extensionContext?.completeRequest(returningItems: nil) }
}
