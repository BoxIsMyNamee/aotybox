import SwiftUI
import WebKit

/// Shared, persistent web session for albumoftheyear.org.
/// Login happens on AOTY's own pages, so the app never sees your password.
/// The session cookies stay in WebKit's store on this device. They are never
/// sent to the community API.
@MainActor
enum AOTYSession {
    static let dataStore = WKWebsiteDataStore.default()
    static let home = URL(string: "https://www.albumoftheyear.org/")!

    static func signOut() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        let aoty = records.filter { $0.displayName.contains("albumoftheyear") }
        await dataStore.removeData(ofTypes: types, for: aoty)
    }
}

struct AOTYWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    /// If set, taps on AOTY album links open the native album page instead.
    var onAlbumTap: ((String) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = AOTYSession.dataStore
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        context.coordinator.loadedURL = url
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            web.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: AOTYWebView
        var loadedURL: URL?
        init(_ parent: AOTYWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if let onAlbumTap = parent.onAlbumTap,
               action.navigationType == .linkActivated,
               let url = action.request.url,
               url.host?.contains("albumoftheyear.org") == true,
               url.path.hasPrefix("/album/"),
               let slug = AlbumSlug.from(url.absoluteString),
               url.path.hasSuffix(".php") || url.path.hasSuffix("/\(slug)/") || url.path.hasSuffix("/\(slug)") {
                decisionHandler(.cancel)
                onAlbumTap(slug)
                return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { parent.isLoading = true }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { parent.isLoading = false }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.isLoading = false }
    }
}

/// Sheet wrapper with a Done button. Use it for login, rating and reviewing.
struct AOTYWebSheet: View {
    let url: URL
    let title: String
    @State private var loading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AOTYWebView(url: url, isLoading: $loading)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    if loading { ToolbarItem(placement: .topBarLeading) { ProgressView() } }
                }
        }
    }
}
