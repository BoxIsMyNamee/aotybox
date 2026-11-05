import SwiftUI
import UIKit

/// Long-press → open the album or song in your music app (Marvis Pro by default).
/// The link format is editable in Settings → Music App, because Marvis lists its URL schemes
/// only inside the app (Marvis Settings → Tips & Tricks).
enum MusicAppLink {
    static let nameKey = "musicAppName"
    static let templateKey = "musicAppTemplate"
    static let defaultName = "Marvis Pro"
    static let defaultTemplate = "marvis://search?query={query}"

    static var name: String {
        let n = UserDefaults.standard.string(forKey: nameKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? defaultName : n
    }
    static var template: String {
        let t = UserDefaults.standard.string(forKey: templateKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return t.isEmpty ? defaultTemplate : t
    }

    /// Placeholders: {query} = "artist title", {artist}, {album}, {song}, {title} (song or album).
    static func url(artist: String, album: String?, song: String?, template: String = template) -> URL? {
        let title = song ?? album ?? ""
        let query = [artist, title].filter { !$0.isEmpty }.joined(separator: " ")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?+#"))) ?? s }
        let filled = template
            .replacingOccurrences(of: "{query}", with: enc(query))
            .replacingOccurrences(of: "{artist}", with: enc(artist))
            .replacingOccurrences(of: "{album}", with: enc(album ?? ""))
            .replacingOccurrences(of: "{song}", with: enc(song ?? ""))
            .replacingOccurrences(of: "{title}", with: enc(title))
        return URL(string: filled)
    }

    static func appleMusicSearch(artist: String, title: String) -> URL? {
        var c = URLComponents(string: "https://music.apple.com/search")!
        c.queryItems = [URLQueryItem(name: "term", value: "\(artist) \(title)")]
        return c.url
    }

    @MainActor
    static func open(_ url: URL?) {
        guard let url else { return }
        UIApplication.shared.open(url) { ok in
            if !ok { NotificationCenter.default.post(name: .musicAppOpenFailed, object: nil) }
        }
    }
}

extension Notification.Name {
    static let musicAppOpenFailed = Notification.Name("musicAppOpenFailed")
}

struct MusicAppMenu: ViewModifier {
    let artist: String
    let album: String?
    let song: String?

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                MusicAppLink.open(MusicAppLink.url(artist: artist, album: album, song: song))
            } label: {
                Label("Open in \(MusicAppLink.name)", systemImage: "music.note")
            }
            Button {
                MusicAppLink.open(MusicAppLink.appleMusicSearch(artist: artist, title: song ?? album ?? ""))
            } label: {
                Label("Search Apple Music", systemImage: "magnifyingglass")
            }
            Button {
                UIPasteboard.general.string = "\(artist) – \(song ?? album ?? "")"
            } label: {
                Label("Copy Title", systemImage: "doc.on.doc")
            }
        }
    }
}

extension View {
    /// Long-press menu: open in Marvis Pro (or your chosen app), search Apple Music, copy title.
    func musicAppMenu(artist: String, album: String? = nil, song: String? = nil) -> some View {
        modifier(MusicAppMenu(artist: artist, album: album, song: song))
    }
}

/// Settings screen for the long-press music app link.
struct MusicAppSettingsView: View {
    @AppStorage(MusicAppLink.nameKey) private var name = ""
    @AppStorage(MusicAppLink.templateKey) private var template = ""

    var body: some View {
        Form {
            Section {
                TextField("App name (default \(MusicAppLink.defaultName))", text: $name)
                TextField("Link (default \(MusicAppLink.defaultTemplate))", text: $template, axis: .vertical)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .font(.callout.monospaced())
            } footer: {
                Text("Placeholders: {query} (artist + title), {artist}, {album}, {song}, {title}.\n\nTo get Marvis's exact link format: open Marvis → Settings → Tips & Tricks → URL Schemes, find the search link, and paste it here with {query} where the search text goes.")
            }
            Section {
                Button("Test with “The Avalanches – No Bad Memories”") {
                    MusicAppLink.open(MusicAppLink.url(artist: "The Avalanches", album: "No Bad Memories", song: nil,
                                                       template: template.isEmpty ? MusicAppLink.defaultTemplate : template))
                }
                Button("Reset to default") { name = ""; template = "" }
            }
        }
        .navigationTitle("Music App")
    }
}
