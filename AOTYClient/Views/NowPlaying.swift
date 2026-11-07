import SwiftUI
import MediaPlayer

/// What's playing in Apple Music's system player (Marvis plays through it too), for one-tap Learn.
@MainActor
final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()
    struct Song: Equatable { let title: String; let artist: String; let album: String?; let art: UIImage? }

    @Published private(set) var song: Song?
    @Published private(set) var status = MPMediaLibrary.authorizationStatus()
    var authorized: Bool { status == .authorized }
    private var started = false

    func start() {
        guard !started else { refresh(); return }
        started = true
        if MPMediaLibrary.authorizationStatus() == .notDetermined {
            MPMediaLibrary.requestAuthorization { status in
                Task { @MainActor in self.status = status; self.observe() }
            }
        } else {
            observe()
        }
    }

    /// Ask again; if iOS doesn't answer in a few seconds (LiveContainer), say so instead of waiting forever.
    func requestAgain() {
        status = MPMediaLibrary.authorizationStatus()
        if status == .denied || status == .restricted {
            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            return
        }
        MPMediaLibrary.requestAuthorization { st in
            Task { @MainActor in self.status = st; if st == .authorized { self.observe() } }
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if self.status == .notDetermined { self.status = .restricted }   // no answer: treat as unavailable
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
        status = MPMediaLibrary.authorizationStatus()
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
            } else if np.status == .denied || np.status == .restricted {
                // Most likely running inside LiveContainer: iOS checks the host app for Apple Music access.
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "waveform.slash").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Now Playing is off").font(.subheadline.weight(.semibold))
                        Text("The app isn't allowed to see what's playing. Inside LiveContainer this can't be turned on; with a normal install (SideStore or TestFlight), allow Apple Music access in Settings.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Open Settings") {
                            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
            } else if np.authorized {
                note("Nothing playing", "Play something in Apple Music or Marvis and it'll show here with a Learn button.", button: nil)
            } else {
                // Not asked yet, or iOS never answered (happens inside LiveContainer).
                note("Now Playing", "Let the app see what's playing in Apple Music or Marvis to open it in Learn.",
                     button: ("Allow access", { np.requestAgain() }))
            }
        }
        .onAppear { np.start() }
    }

    private func note(_ title: String, _ text: String, button: (String, () -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary)
                if let button { Button(button.0, action: button.1).font(.caption.weight(.semibold)) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }
}
