import SwiftUI

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
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 18) {
                    #if os(macOS)
                    Cover(url: cover, size: 124)
                    #else
                    Cover(url: cover, size: 96)
                    #endif
                    VStack(alignment: .leading, spacing: 5) {
                        Text(album)
                            #if os(macOS)
                            .font(.largeTitle.bold())
                            #else
                            .font(.title3.bold())
                            #endif
                            .lineLimit(3)
                        Text(artist)
                            #if os(macOS)
                            .font(.title3.weight(.semibold))
                            #else
                            .font(.subheadline)
                            #endif
                            .foregroundStyle(.secondary)
                        if let d = info?.releaseDate {
                            Text(d)
                                #if os(macOS)
                                .font(.subheadline)
                                #else
                                .font(.caption)
                                #endif
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                #if os(macOS)
                .padding(.vertical, 6)
                #endif
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
                                    HStack(spacing: 12) {
                                        Text("\(t.number)")
                                            #if os(macOS)
                                            .font(.title3.monospacedDigit())
                                            #endif
                                            .foregroundStyle(.secondary).monospacedDigit().frame(width: 28, alignment: .trailing)
                                        Text(t.title)
                                            #if os(macOS)
                                            .font(.title3.weight(.medium))
                                            #endif
                                            .foregroundStyle(.primary).multilineTextAlignment(.leading)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 12)
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
        .macPagePadding()
        .safeAreaInset(edge: .bottom) {
            if !keyboardUp {
                GlassSegmented(selection: $tab, items: Tab.allCases.map { ($0, $0.rawValue) })
                    #if os(macOS)
                    .frame(maxWidth: 440)
                    .padding(.bottom, 14)
                    #else
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
                    #endif
            }
        }
        .trackKeyboard($keyboardUp)
        .navigationTitle(album)
        .inlineNavTitle()
        .toolbar {
            if let u = info?.url { Button { openURL(u) } label: { Image(systemName: "arrow.up.right.square") } }
        }
        .onAppear { chat.attach(ChatThread.key("album", artist, album)) }
        .task { await load() }
        .task { try? await Task.sleep(for: .seconds(4)); kickOffAsk() }
        .onChange(of: tab) { if tab == .ask { kickOffAsk() } }
    }

    private var context: String {
        var lines = ["Album: \(album)", "Artist: \(artist)"]
        if let d = info?.releaseDate { lines.append("Released: \(d)") }
        if !tracks.isEmpty { lines.append("Tracklist: " + tracks.map { "\($0.number). \($0.title)" }.joined(separator: "; ")) }
        if let a = info?.about { lines.append("Genius write-up:\n\(a.prefix(3000))") }
        return lines.joined(separator: "\n")
    }

    private func kickOffAsk() {
        SongChatView(context: context, thread: chat, nothingOnGenius: false, subject: "album").autoAsk()
    }

    private func load() async {
        guard loading else { return }
        defer {
            loading = false
            kickOffAsk()
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
