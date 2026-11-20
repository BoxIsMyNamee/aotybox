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
        #if os(iOS)
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = false
        config.allowsAirPlayForMediaPlayback = false
        #endif
        config.mediaTypesRequiringUserActionForPlayback = .all
        // Look like Safari (the default in-app user agent has no "Safari" token, which Cloudflare's
        // check is pickier about). Same for every web view, so the clearance cookie fits all of them.
        let v = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
        config.applicationNameForUserAgent = "Version/\(v.majorVersion).\(v.minorVersion) Mobile/15E148 Safari/604.1"
        #else
        config.applicationNameForUserAgent = "Version/\(v.majorVersion).\(v.minorVersion) Safari/605.1.15"
        #endif
        return config
    }

    static func signOut() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        let aoty = records.filter { $0.displayName.contains("albumoftheyear") }
        await dataStore.removeData(ofTypes: types, for: aoty)
    }
}

#if os(iOS)
private typealias PlatformWebViewRepresentable = UIViewRepresentable
#else
private typealias PlatformWebViewRepresentable = NSViewRepresentable
#endif

struct AOTYWebView: PlatformWebViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    /// If set, taps on AOTY album links open the native album page instead.
    var onAlbumTap: ((String) -> Void)? = nil
    /// If set, taps on AOTY artist links open the native artist page ("/artist/123-name/").
    var onArtistTap: ((String) -> Void)? = nil
    /// Called after each page finishes loading (to check sign-in / Cloudflare state).
    var onFinish: ((WKWebView) -> Void)? = nil

    private func makeWebView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: AOTYSession.makeConfiguration())
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        context.coordinator.loadedURL = url
        web.load(URLRequest(url: url))
        return web
    }

    private func updateWebView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            web.load(URLRequest(url: url))
        }
    }

    #if os(iOS)
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ web: WKWebView, context: Context) { updateWebView(web, context: context) }
    #else
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ web: WKWebView, context: Context) { updateWebView(web, context: context) }
    #endif

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
                .inlineNavTitle()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    if loading { ToolbarItem(placement: .platformTopBarLeading) { ProgressView() } }
                }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 540)
        #endif
    }
}
