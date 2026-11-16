import SwiftUI

/// Settings → Swipe Actions: which action each swipe direction does. Defaults match how the
/// app always worked (albums: right = Learn, left = Open; reviews: right = Learn/View, left = Like).
enum SwipeChoice {
    static let albumRight = "swipe.album.right", albumLeft = "swipe.album.left"
    static let reviewRight = "swipe.review.right", reviewLeft = "swipe.review.left"

    enum Album: String, CaseIterable, Identifiable {
        case learn, open, none
        var id: String { rawValue }
        var name: String { switch self { case .learn: "Learn"; case .open: "Open in Music App"; case .none: "Nothing" } }
    }

    enum Review: String, CaseIterable, Identifiable {
        case learn, like, none
        var id: String { rawValue }
        var name: String { switch self { case .learn: "Learn / View"; case .like: "Like"; case .none: "Nothing" } }
    }
}

struct SwipeSettingsSection: View {
    @AppStorage(SwipeChoice.albumRight) private var albumRight = SwipeChoice.Album.learn.rawValue
    @AppStorage(SwipeChoice.albumLeft) private var albumLeft = SwipeChoice.Album.open.rawValue
    @AppStorage(SwipeChoice.reviewRight) private var reviewRight = SwipeChoice.Review.learn.rawValue
    @AppStorage(SwipeChoice.reviewLeft) private var reviewLeft = SwipeChoice.Review.like.rawValue

    var body: some View {
        Section {
            Picker("Albums & songs: swipe right", selection: $albumRight) {
                ForEach(SwipeChoice.Album.allCases) { Text($0.name).tag($0.rawValue) }
            }
            Picker("Albums & songs: swipe left", selection: $albumLeft) {
                ForEach(SwipeChoice.Album.allCases) { Text($0.name).tag($0.rawValue) }
            }
            Picker("Reviews: swipe right", selection: $reviewRight) {
                ForEach(SwipeChoice.Review.allCases) { Text($0.name).tag($0.rawValue) }
            }
            Picker("Reviews: swipe left", selection: $reviewLeft) {
                ForEach(SwipeChoice.Review.allCases) { Text($0.name).tag($0.rawValue) }
            }
        } header: {
            Text("Swipe Actions")
        } footer: {
            Text("Learn / View opens Learn for your own reviews and the full review for other people's.")
        }
    }
}

/// Album and song rows: Learn and Open, on whichever sides Settings says.
struct AlbumSwipe: ViewModifier {
    let learn: () -> Void
    let open: () -> Void
    @AppStorage(SwipeChoice.albumRight) private var right = SwipeChoice.Album.learn.rawValue
    @AppStorage(SwipeChoice.albumLeft) private var left = SwipeChoice.Album.open.rawValue

    private func action(_ raw: String) -> SwipeAction? {
        switch SwipeChoice.Album(rawValue: raw) ?? .none {
        case .learn: SwipeAction(icon: "magnifyingglass", title: "Learn", color: .green, perform: learn)
        case .open: SwipeAction(icon: "play.fill", title: "Open", color: .blue, perform: open)
        case .none: nil
        }
    }

    func body(content: Content) -> some View {
        content.swipeRow(leading: action(right), trailing: action(left))
    }
}
