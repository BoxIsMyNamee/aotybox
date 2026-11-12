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
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return finish() }
        var c = URLComponents()
        c.scheme = "aotybox"; c.host = "notes"
        c.queryItems = [URLQueryItem(name: "b64", value: data.base64EncodedString())]
        if let url = c.url, openApp(url) { return finish() }
        // Couldn't hand off directly: leave it on the clipboard so Notes' Paste picks it up.
        UIPasteboard.general.string = text
        showMessage("Copied. Open AOTYbox → Notes → Paste.")
        try? await Task.sleep(for: .seconds(1.6))
        finish()
    }

    private func sharedText() async -> String? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for p in item.attachments ?? [] {
                if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let s = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) {
                    if let str = s as? String { return str }
                    if let d = s as? Data, let str = String(data: d, encoding: .utf8) { return str }
                }
                if p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let u = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    return u.absoluteString
                }
            }
            if let t = item.attributedContentText?.string, !t.isEmpty { return t }
        }
        return nil
    }

    /// Extensions can't call UIApplication.shared directly; reach it through the responder chain.
    @discardableResult private func openApp(_ url: URL) -> Bool {
        var r: UIResponder? = self
        while let current = r {
            if let app = current as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
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
