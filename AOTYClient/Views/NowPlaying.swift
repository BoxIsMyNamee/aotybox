import SwiftUI
import MediaPlayer

/// What's playing in Apple Music's system player (Marvis plays through it too), for one-tap Learn.
@MainActor
final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()
    struct Song: Equatable { let title: String; let artist: String; let album: String?; let art: UIImage? }

    @Published private(set) var song: Song?
    @Published private(set) var isPlaying = false
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
        isPlaying = player.playbackState == .playing
        guard let item = player.nowPlayingItem, let title = item.title, !title.isEmpty else { song = nil; return }
        song = Song(title: title, artist: item.artist ?? item.albumArtist ?? "", album: item.albumTitle,
                    art: item.artwork?.image(at: CGSize(width: 120, height: 120)))
    }
}

/// Card shown on Search: the current song with a Learn button.
struct NowPlayingCard: View {
    @ObservedObject private var np = NowPlaying.shared
    @Environment(\.push) private var push
    @State private var finding = false
    @State private var notFound: String?

    /// Find the playing song's album (or single) on AOTY and open its page.
    private func openRelease(_ s: NowPlaying.Song) async {
        finding = true; notFound = nil
        defer { finding = false }
        let title = (s.album ?? s.title).replacingOccurrences(of: #"\s+-\s+(Single|EP)$"#, with: "", options: .regularExpression)
        if let slug = await AOTYAPI.shared.findAlbumSlug(artist: s.artist, title: title) {
            push(AlbumRoute(slug: slug, title: title))
        } else {
            notFound = "Couldn't find “\(title)” on AOTY."
        }
    }

    var body: some View {
        Group {
            if let s = np.song {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Group {
                            if let art = s.art { Image(uiImage: art).resizable().scaledToFill() }
                            else { Rectangle().fill(.quaternary) }
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                EqualizerBars(playing: np.isPlaying)
                                Text("Now Playing")
                            }
                            .font(.caption.weight(.semibold)).foregroundStyle(.tint)
                            Text(s.title).font(.headline).lineLimit(1)
                            Text(s.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 10) {
                        Button { Task { await openRelease(s) } } label: {
                            HStack(spacing: 6) {
                                if finding { ProgressView().controlSize(.mini) } else { Image(systemName: "square.stack") }
                                Text(s.album.map { _ in "Album" } ?? "Release")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(.quaternary.opacity(0.6), in: Capsule())
                        }
                        .disabled(finding)
                        Button { push(SongRoute(artist: s.artist, title: s.title, album: s.album, cover: nil)) } label: {
                            Label("Learn", systemImage: "magnifyingglass")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(.green.opacity(0.2), in: Capsule())
                                .foregroundStyle(.green)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    if let notFound { Text(notFound).font(.caption).foregroundStyle(.secondary).padding(.top, 6) }
                }
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
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


/// Little equalizer: four bars that grow and shrink while music plays, resting low when paused.
struct EqualizerBars: View {
    let playing: Bool
    private let speeds: [Double] = [5.3, 7.1, 4.2, 6.4]
    private let phases: [Double] = [0, 1.7, 3.1, 4.6]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let wave = (sin(t * speeds[i] + phases[i]) + sin(t * speeds[i] * 0.53 + phases[i] * 2)) / 2   // -1…1
                    let h: CGFloat = playing ? 0.25 + 0.75 * CGFloat((wave + 1) / 2) : 0.25
                    Capsule().frame(width: 2.5, height: 12 * h)
                }
            }
            .frame(width: 16, height: 12, alignment: .bottom)
            .animation(.easeOut(duration: 0.25), value: playing)
        }
        .accessibilityHidden(true)
    }
}
