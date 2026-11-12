import SwiftUI
import UIKit

/// Remembers hearts you tapped this session, so every screen agrees even when a page is cached.
@MainActor
final class LikeStore: ObservableObject {
    static let shared = LikeStore()
    @Published private(set) var state: [Int: (liked: Bool, count: Int)] = [:]
    /// A short message when AOTY refuses a like (shown as a toast at the top of the app).
    @Published var notice: String?

    func liked(_ id: Int?, default d: Bool) -> Bool { id.flatMap { state[$0]?.liked } ?? d }
    func count(_ id: Int?, default d: Int) -> Int { id.flatMap { state[$0]?.count } ?? d }

    /// Optimistic toggle; reverts if AOTY says no.
    func toggle(id: Int, liked: Bool, count: Int) async -> AOTYAPI.LikeResult {
        let new = (liked: !liked, count: max(0, count + (liked ? -1 : 1)))
        state[id] = new
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let r = await AOTYAPI.shared.setReviewLike(id, liked: new.liked)
        if r != .ok {
            state[id] = (liked, count)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            switch r {
            case .limited: notice = "AOTY's hourly like limit reached. Try again in a bit."
            case .failed(let why): notice = "AOTY didn't take that like. " + why
            case .ok: break
            }
            let shown = notice
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if self.notice == shown { self.notice = nil } }
        }
        return r
    }
}

/// Heart button with count, for user reviews.
struct HeartButton: View {
    let reviewID: Int?
    let liked: Bool
    let likes: Int
    var canLike = true
    @ObservedObject private var store = LikeStore.shared
    @State private var busy = false
    @State private var limited = false
    @State private var failure: String?
    @State private var showLikers = false

    var body: some View {
        let isLiked = store.liked(reviewID, default: liked)
        let count = store.count(reviewID, default: likes)
        HStack(spacing: 0) {
            Button {
                guard let reviewID else { return }
                if !canLike { if count > 0 { showLikers = true }; return }   // your own review: see who liked it
                guard !busy else { return }
                Task {
                    busy = true
                    let r = await store.toggle(id: reviewID, liked: isLiked, count: count)
                    limited = (r == .limited)
                    if case let .failed(msg) = r { failure = msg }
                    busy = false
                }
            } label: {
                Image(systemName: limited ? "exclamationmark.triangle" : (isLiked ? "heart.fill" : "heart"))
                    .foregroundStyle(isLiked ? Color.red : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.vertical, 4).padding(.leading, 8).padding(.trailing, count > 0 ? 2 : 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(reviewID == nil || (!canLike && count == 0))
            .opacity(canLike || count > 0 ? 1 : 0.6)
            // The number: tap to see who liked it.
            if count > 0 {
                Button { if reviewID != nil { showLikers = true } } label: {
                    Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
                        .padding(.vertical, 4).padding(.trailing, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Liked by \(count). Show who")
            }
        }
        .font(.caption)
        .sheet(isPresented: $showLikers) {
            if let reviewID { LikersSheet(reviewID: reviewID, count: count) }
        }
        .alert("Couldn't like this review", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(failure ?? "") }
        .accessibilityLabel(isLiked ? "Unlike review" : "Like review")
        .help(limited ? "AOTY's hourly like limit reached" : "")
    }
}

/// Reviews: swipe left to heart (or un-heart), swipe right to Learn about the album.
/// On reviews you can't like (your own), the left swipe still moves and ticks; it just doesn't send.
struct HeartSwipe: ViewModifier {
    let reviewID: Int?
    let liked: Bool
    let likes: Int
    var enabled = true
    var learn: (() -> Void)? = nil
    /// Other people's reviews: swipe right to View the review instead of Learn.
    var view: (() -> Void)? = nil
    @ObservedObject private var store = LikeStore.shared

    func body(content: Content) -> some View {
        let isLiked = store.liked(reviewID, default: liked)
        let count = store.count(reviewID, default: likes)
        content.swipeRow(
            leading: view.map { v in SwipeAction(icon: "magnifyingglass", title: "View", color: .green, perform: v) }
                ?? learn.map { l in SwipeAction(icon: "magnifyingglass", title: "Learn", color: .green, perform: l) },
            trailing: SwipeAction(
                icon: isLiked ? "heart.slash.fill" : "heart.fill",
                title: isLiked ? "Unlike" : "Like",
                color: .pink,
                perform: {
                    guard enabled, let id = reviewID else { return }
                    Task { _ = await store.toggle(id: id, liked: isLiked, count: count) }
                }
            )
        )
    }
}

extension View {
    func heartSwipe(reviewID: Int?, liked: Bool, likes: Int, enabled: Bool = true, learn: (() -> Void)? = nil, view: (() -> Void)? = nil) -> some View {
        modifier(HeartSwipe(reviewID: reviewID, liked: liked, likes: likes, enabled: enabled, learn: learn, view: view))
    }
}

/// Text with every web link tappable.
func linkified(_ s: String) -> AttributedString {
    var a = AttributedString(s)
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return a }
    for m in detector.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
        guard let url = m.url, let r = Range(m.range, in: s), let ar = Range(r, in: a) else { continue }
        a[ar].link = url
        a[ar].underlineStyle = .single
    }
    return a
}


/// Speech-bubble button next to the heart: opens the review on AOTY (to read comments or add one).
struct CommentButton: View {
    let count: Int?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left").foregroundStyle(.secondary)
                if let count, count > 0 { Text("\(count)").monospacedDigit().foregroundStyle(.secondary) }
            }
            .font(.caption)
            .padding(.vertical, 4).padding(.leading, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\($0) comments" } ?? "Comments")
    }
}


/// "Liked By" for a review: the same list AOTY's popup shows.
struct LikersSheet: View {
    let reviewID: Int
    let count: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.push) private var push
    @State private var people: [AOTYAPI.Liker]?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let people, !people.isEmpty {
                    List(people) { p in
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                push(UserRoute(username: p.slug, name: p.name, avatar: p.avatar, nameColor: p.nameColor))
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(url: p.avatar.flatMap(URL.init(string:)), name: p.name, size: 40)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(p.name).font(.body.weight(.semibold))
                                        .foregroundStyle(p.nameColor.map { Color(hex: $0) } ?? .primary)
                                    if p.followsYou {
                                        Text("Follows you").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color(.tertiarySystemFill), in: Capsule())
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                } else if failed || people != nil {
                    ContentUnavailableView("Couldn't load likes", systemImage: "heart.slash",
                                           description: Text("Try again in a moment."))
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Liked By")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents(count > 6 ? [.medium, .large] : [.medium])
        .task {
            if let list = await AOTYAPI.shared.reviewLikers(reviewID) {
                withAnimation { people = list }
            } else { failed = true }
        }
    }
}


/// The like-refused toast.
struct LikeNoticeToast: View {
    @ObservedObject private var store = LikeStore.shared
    var body: some View {
        VStack {
            if let n = store.notice {
                Label(n, systemImage: "heart.slash")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(3)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { store.notice = nil }
            }
            Spacer()
        }
        .padding(.top, 6)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.notice)
        .allowsHitTesting(store.notice != nil)
    }
}
