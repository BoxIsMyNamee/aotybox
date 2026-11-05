import SwiftUI
import UIKit

// One navigation style everywhere: each tab owns a NavigationPath and screens push typed
// values onto it. (Mixing destination-based NavigationLinks with value-based ones in the same
// stack is what made the Friends list push itself twice.)

struct AlbumRoute: Hashable { let slug: String?; let title: String }
struct SongRoute: Hashable { let artist: String; let title: String; let album: String?; let cover: URL? }
struct UserReviewsRoute: Hashable { let slug: String; let title: String }
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
            .navigationDestination(for: UserReviewsRoute.self) { UserReviewsView(slug: $0.slug, title: $0.title) }
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

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .scaleEffect(pressing ? 0.95 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: pressing)
            .onTapGesture(perform: tap)
            .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 12) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                hold()
            } onPressingChanged: { pressing = $0 }
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
    @ViewBuilder var label: () -> Label
    @Environment(\.push) private var push

    var body: some View {
        HStack(spacing: 8) {
            label()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .tapAndHold(tap: { push(value) }, hold: {
            Task { await MusicAppLink.open(artist: artist, album: album, song: song, appleMusicURL: appleMusicURL) }
        })
    }
}
