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
    @ObservedObject private var store = LikeStore.shared
    @State private var busy = false
    @State private var limited = false

    var body: some View {
        let isLiked = store.liked(reviewID, default: liked)
        let count = store.count(reviewID, default: likes)
        Button {
            guard let reviewID, !busy else { return }
            Task {
                busy = true
                let r = await store.toggle(id: reviewID, liked: isLiked, count: count)
                limited = (r == .limited)
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
        .disabled(reviewID == nil)
        .accessibilityLabel(isLiked ? "Unlike review" : "Like review")
        .help(limited ? "AOTY's hourly like limit reached" : "")
    }
}
