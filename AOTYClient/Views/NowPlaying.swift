import SwiftUI
import MediaPlayer

/// What's playing in Apple Music's system player (Marvis plays through it too), for one-tap Learn.
@MainActor
final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()
    struct Song: Equatable { let title: String; let artist: String; let album: String?; let art: UIImage? }

    @Published private(set) var song: Song?
    @Published private(set) var authorized = MPMediaLibrary.authorizationStatus() == .authorized
    private var started = false

    func start() {
        guard !started else { refresh(); return }
        started = true
        if MPMediaLibrary.authorizationStatus() == .notDetermined {
            MPMediaLibrary.requestAuthorization { status in
                Task { @MainActor in self.authorized = status == .authorized; self.observe() }
            }
        } else {
            observe()
        }
    }

    private func observe() {
        let player = MPMusicPlayerController.systemMusicPlayer
        player.beginGeneratingPlaybackNotifications()
        NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player, queue: .main) { _ in
            Task { @MainActor in self.refresh() }
        }
        NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: player, queue: .main) { _ in
            Task { @MainActor in self.refresh() }
        }
        refresh()
    }

    func refresh() {
        let player = MPMusicPlayerController.systemMusicPlayer
        guard let item = player.nowPlayingItem, let title = item.title, !title.isEmpty else { song = nil; return }
        song = Song(title: title, artist: item.artist ?? item.albumArtist ?? "", album: item.albumTitle,
                    art: item.artwork?.image(at: CGSize(width: 120, height: 120)))
    }
}

/// Card shown on Search: the current song with a Learn button.
struct NowPlayingCard: View {
    @ObservedObject private var np = NowPlaying.shared
    @Environment(\.push) private var push

    var body: some View {
        Group {
            if let s = np.song {
                Button {
                    push(SongRoute(artist: s.artist, title: s.title, album: s.album, cover: nil))
                } label: {
                    HStack(spacing: 12) {
                        Group {
                            if let art = s.art { Image(uiImage: art).resizable().scaledToFill() }
                            else { Rectangle().fill(.quaternary) }
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Now Playing", systemImage: "waveform").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                            Text(s.title).font(.headline).lineLimit(1)
                            Text(s.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Label("Learn", systemImage: "magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.green.opacity(0.2), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { np.start() }
    }
}
