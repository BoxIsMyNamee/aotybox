import SwiftUI
import UIKit

// One navigation style everywhere: each tab owns a NavigationPath and screens push typed
// values onto it. (Mixing destination-based NavigationLinks with value-based ones in the same
// stack is what made the Friends list push itself twice.)

struct AlbumRoute: Hashable { let slug: String?; let title: String }
struct SongRoute: Hashable { let artist: String; let title: String; let album: String?; let cover: URL? }
struct UserReviewsRoute: Hashable { let slug: String; let title: String; var range: String? = nil }
struct ArtistRoute: Hashable { let path: String; let name: String }
struct LearnAlbumRoute: Hashable { let artist: String; let album: String; let cover: URL? }
struct UserRoute: Hashable { let username: String; let name: String; let avatar: String? }
struct ProfileReviewsRoute: Hashable { let username: String }
struct ProfileRatingsRoute: Hashable { let username: String; let path: String?; let isMe: Bool }

struct PushAction {
    let action: (any Hashable) -> Void
    func callAsFunction(_ value: any Hashable) { action(value) }
}

private struct PushKey: EnvironmentKey {
    static let defaultValue = PushAction { _ in }
}

extension EnvironmentValues {
    var push: PushAction {
        get { self[PushKey.self] }
        set { self[PushKey.self] = newValue }
    }
}

extension View {
    func appDestinations() -> some View {
        self
            .navigationDestination(for: AlbumBlock.self) { AlbumDetailView(slug: $0.slug, fallbackTitle: $0.title) }
            .navigationDestination(for: ChartItem.self) { AlbumDetailView(slug: $0.slug, fallbackTitle: $0.album) }
            .navigationDestination(for: AlbumRoute.self) { AlbumDetailView(slug: $0.slug, fallbackTitle: $0.title) }
            .navigationDestination(for: SongRoute.self) { SongView(artist: $0.artist, title: $0.title, album: $0.album, albumCover: $0.cover) }
            .navigationDestination(for: UserReviewsRoute.self) { UserReviewsView(slug: $0.slug, title: $0.title, rangeLabel: $0.range) }
            .navigationDestination(for: ArtistRoute.self) { ArtistView(path: $0.path, fallbackName: $0.name) }
            .navigationDestination(for: LearnAlbumRoute.self) { LearnAlbumView(artist: $0.artist, album: $0.album, cover: $0.cover) }
            .navigationDestination(for: UserRoute.self) { u in
                UserProfileView(username: u.username, fallbackAvatar: u.avatar, isMe: false)
                    .navigationTitle(u.name).navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(for: ProfileReviewsRoute.self) { ProfileReviewsView(username: $0.username) }
            .navigationDestination(for: ProfileRatingsRoute.self) { ProfileRatingsView(username: $0.username, path: $0.path, isMe: $0.isMe) }
            .navigationDestination(for: FollowUser.self) { u in
                UserProfileView(username: u.username, fallbackAvatar: u.avatar, isMe: false)
                    .navigationTitle(u.name).navigationBarTitleDisplayMode(.inline)
            }
    }
}

/// A tab's navigation stack with a `push` action in the environment.
struct AppStack<Content: View>: View {
    @State private var path = NavigationPath()
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack(path: $path) {
            content().appDestinations()
        }
        .environment(\.push, PushAction { value in path.append(value) })
    }
}

// MARK: - Tap to open, press-and-hold to open in Marvis

struct TapAndHold: ViewModifier {
    let tap: () -> Void
    let hold: () -> Void
    @State private var pressing = false
    @State private var fired = false
    @State private var timer: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .scaleEffect(pressing ? 0.95 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: pressing)
            .onTapGesture {
                if fired { fired = false; return }   // the hold already handled this touch
                tap()
            }
            // The long press itself never completes (huge duration); it only reports press
            // state. A timer fires the hold action while the finger is still down.
            .onLongPressGesture(minimumDuration: 60, maximumDistance: 12, perform: {}) { isPressing in
                pressing = isPressing
                timer?.cancel()
                if isPressing {
                    fired = false
                    timer = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(420))
                        guard !Task.isCancelled, pressing else { return }
                        fired = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { pressing = false }
                        hold()
                    }
                }
            }
    }
}

extension View {
    func tapAndHold(tap: @escaping () -> Void, hold: @escaping () -> Void) -> some View {
        modifier(TapAndHold(tap: tap, hold: hold))
    }
}

/// List row: tap pushes `value`; press-and-hold opens the album/song in Marvis Pro.
struct NavRow<Label: View>: View {
    let value: any Hashable
    let artist: String
    var album: String? = nil
    var song: String? = nil
    var appleMusicURL: String? = nil
    var isSingle: Bool = false
    var cover: URL? = nil
    @ViewBuilder var label: () -> Label
    @Environment(\.push) private var push

    var body: some View {
        HStack(spacing: 8) {
            label()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture { push(value) }
        .swipeRow(
            learn: { push(Learn.route(artist: artist, album: album, song: song, isSingle: isSingle, cover: cover)) },
            open: { Task { await MusicAppLink.open(artist: artist, album: album, song: song, appleMusicURL: appleMusicURL) } }
        )
    }
}

/// Where "Learn" goes: a song's Genius page (lyrics, notes, Ask AI), or the album's.
enum Learn {
    static func cleanTitle(_ t: String) -> String {
        t.replacingOccurrences(of: #"\s+-\s+(Single|EP)$"#, with: "", options: [.regularExpression, .caseInsensitive])
    }
    static func route(artist: String, album: String?, song: String?, isSingle: Bool, cover: URL?) -> any Hashable {
        if let song { return SongRoute(artist: artist, title: song, album: album, cover: cover) }
        if isSingle, let album { return SongRoute(artist: artist, title: cleanTitle(album), album: album, cover: cover) }
        return LearnAlbumRoute(artist: artist, album: album ?? "", cover: cover)
    }
}
