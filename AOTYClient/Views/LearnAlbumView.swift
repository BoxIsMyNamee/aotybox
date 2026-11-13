import SwiftUI
import UIKit

/// "Learn" for an album or EP: the Genius write-up and tracklist, plus Ask AI.
struct LearnAlbumView: View {
    let artist: String
    let album: String
    let cover: URL?

    enum Tab: String, CaseIterable, Identifiable { case about = "About", tracks = "Tracks", ask = "Ask AI"; var id: String { rawValue } }

    @State private var tab: Tab = .about
    @State private var info: GeniusClient.AlbumInfo?
    @State private var tracks: [Track] = []
    @State private var loading = true
    @State private var chat = ChatThread()
    @Environment(\.push) private var push
    @Environment(\.openURL) private var openURL
    @State private var keyboardUp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Cover(url: cover, size: 96)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(album).font(.title3.bold()).lineLimit(3)
                        Text(artist).font(.subheadline).foregroundStyle(.secondary)
                        if let d = info?.releaseDate { Text(d).font(.caption).foregroundStyle(.tertiary) }
                    }
                }
                switch tab {
                case .about:
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    else if let about = info?.about { GeniusRichText(text: about) }
                    else {
                        Text("Genius doesn't have a write-up for this one.").foregroundStyle(.secondary)
                        Button("Ask AI about it instead") { tab = .ask }
                    }
                case .tracks:
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    else if tracks.isEmpty { Text("No tracklist found.").foregroundStyle(.secondary) }
                    else {
                        VStack(spacing: 0) {
                            ForEach(tracks) { t in
                                Button { push(SongRoute(artist: artist, title: t.title, album: album, cover: cover)) } label: {
                                    HStack {
                                        Text("\(t.number)").foregroundStyle(.secondary).monospacedDigit().frame(width: 24, alignment: .trailing)
                                        Text(t.title).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if t != tracks.last { Divider() }
                            }
                        }
                    }
                case .ask:
                    SongChatView(context: context, thread: chat, nothingOnGenius: false, subject: "album")
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if !keyboardUp {
                GlassSegmented(selection: $tab, items: Tab.allCases.map { ($0, $0.rawValue) })
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .navigationTitle(album)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let u = info?.url { Button { openURL(u) } label: { Image(systemName: "arrow.up.right.square") } }
        }
        .task { await load() }
    }

    private var context: String {
        var lines = ["Album: \(album)", "Artist: \(artist)"]
        if let d = info?.releaseDate { lines.append("Released: \(d)") }
        if !tracks.isEmpty { lines.append("Tracklist: " + tracks.map { "\($0.number). \($0.title)" }.joined(separator: "; ")) }
        if let a = info?.about { lines.append("Genius write-up:\n\(a.prefix(3000))") }
        return lines.joined(separator: "\n")
    }

    private func load() async {
        guard loading else { return }
        defer {
            loading = false
            SongChatView(context: context, thread: chat, nothingOnGenius: false, subject: "album").autoAsk()
        }
        if let id = await GeniusClient.findAlbumID(artist: artist, album: album) {
            async let i = GeniusClient.albumInfo(id: id)
            async let t = GeniusClient.albumTracks(id: id)
            info = await i
            tracks = await t
        }
        if tracks.isEmpty {
            tracks = await MusicAppLink.tracklist(artist: artist, album: album, appleMusicURL: nil)
        }
    }
}
