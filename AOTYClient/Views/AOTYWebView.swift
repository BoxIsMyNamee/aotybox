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

    /// Shared config: AOTY session, and no autoplaying or picture-in-picture video ads.
    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = false
        config.allowsAirPlayForMediaPlayback = false
        config.mediaTypesRequiringUserActionForPlayback = .all
        return config
    }

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
    /// If set, taps on AOTY artist links open the native artist page ("/artist/123-name/").
    var onArtistTap: ((String) -> Void)? = nil
    /// Called after each page finishes loading (to check sign-in / Cloudflare state).
    var onFinish: ((WKWebView) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: AOTYSession.makeConfiguration())
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
            if let onArtistTap = parent.onArtistTap,
               action.navigationType == .linkActivated,
               let url = action.request.url,
               url.host?.contains("albumoftheyear.org") == true,
               url.path.range(of: #"^/artist/\d+[^/]*/?$"#, options: .regularExpression) != nil {
                decisionHandler(.cancel)
                onArtistTap(url.path)
                return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { parent.isLoading = true }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.onFinish?(webView)
        }
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
