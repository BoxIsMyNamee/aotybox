import SwiftUI
import UIKit

/// Remembers hearts you tapped this session, so every screen agrees even when a page is cached.
@MainActor
final class LikeStore: ObservableObject {
    static let shared = LikeStore()
    @Published private(set) var state: [Int: (liked: Bool, count: Int)] = [:]

    func liked(_ id: Int?, default d: Bool) -> Bool { id.flatMap { state[$0]?.liked } ?? d }
    func count(_ id: Int?, default d: Int) -> Int { id.flatMap { state[$0]?.count } ?? d }

    /// Optimistic toggle; reverts if AOTY says no.
    func toggle(id: Int, liked: Bool, count: Int) async -> AOTYAPI.LikeResult {
        let new = (liked: !liked, count: max(0, count + (liked ? -1 : 1)))
        state[id] = new
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let r = await AOTYAPI.shared.setReviewLike(id, liked: new.liked)
        if r != .ok { state[id] = (liked, count) }
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

    var body: some View {
        let isLiked = store.liked(reviewID, default: liked)
        let count = store.count(reviewID, default: likes)
        Button {
            guard let reviewID, !busy else { return }
            Task {
                busy = true
                let r = await store.toggle(id: reviewID, liked: isLiked, count: count)
                limited = (r == .limited)
                if case let .failed(msg) = r { failure = msg }
                busy = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: limited ? "exclamationmark.triangle" : (isLiked ? "heart.fill" : "heart"))
                    .foregroundStyle(isLiked ? Color.red : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                if count > 0 { Text("\(count)").monospacedDigit().foregroundStyle(.secondary) }
            }
            .font(.caption)
            .padding(.vertical, 4).padding(.leading, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(reviewID == nil || !canLike)
        .opacity(canLike ? 1 : 0.6)
        .alert("Couldn't like this review", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(failure ?? "") }
        .accessibilityLabel(isLiked ? "Unlike review" : "Like review")
        .help(limited ? "AOTY's hourly like limit reached" : "")
    }
}

/// Reviews: swipe left to heart (or un-heart), swipe right to open the review's page to comment.
struct HeartSwipe: ViewModifier {
    let reviewID: Int?
    let liked: Bool
    let likes: Int
    var enabled = true
    var comment: (() -> Void)? = nil
    @ObservedObject private var store = LikeStore.shared

    func body(content: Content) -> some View {
        let isLiked = store.liked(reviewID, default: liked)
        let count = store.count(reviewID, default: likes)
        content.swipeRow(
            leading: comment.map { c in SwipeAction(icon: "bubble.left.fill", title: "Comment", color: .blue, perform: c) },
            trailing: (enabled && reviewID != nil) ? SwipeAction(
                icon: isLiked ? "heart.slash.fill" : "heart.fill",
                title: isLiked ? "Unlike" : "Like",
                color: .pink,
                perform: { if let id = reviewID { Task { _ = await store.toggle(id: id, liked: isLiked, count: count) } } }
            ) : nil
        )
    }
}

extension View {
    func heartSwipe(reviewID: Int?, liked: Bool, likes: Int, enabled: Bool = true, comment: (() -> Void)? = nil) -> some View {
        modifier(HeartSwipe(reviewID: reviewID, liked: liked, likes: likes, enabled: enabled, comment: comment))
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
