import SwiftUI

/// Genres for album rows on Releases. AOTY's list pages don't include genres, so this looks
/// them up from each album's page, only for rows you actually scroll to, one at a time, newest
/// request first. Results are saved permanently (an album's genres rarely change).
@MainActor
final class GenreStore: ObservableObject {
    static let shared = GenreStore()

    @Published private(set) var genres: [String: [String]] = [:]

    private var wanted: [String] = []          // most recent last
    private var visible: Set<String> = []
    private var retryAfter: [String: Date] = [:]   // failed or empty lookups wait a bit, then retry
    private var working = false
    private let file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("genres.json")

    private init() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: [String]].self, from: data) {
            genres = saved.filter { !$0.value.isEmpty }   // empty = looked up too early; try again
        }
    }

    func label(for slug: String?) -> String? {
        guard let slug, let g = genres[slug], !g.isEmpty else { return nil }
        return g.prefix(2).joined(separator: ", ")
    }

    func appeared(_ slug: String?) {
        guard let slug, genres[slug] == nil else { return }
        if let t = retryAfter[slug], t > Date() { return }
        visible.insert(slug)
        wanted.removeAll { $0 == slug }
        wanted.append(slug)
        pump()
    }

    func disappeared(_ slug: String?) {
        guard let slug else { return }
        visible.remove(slug)
    }

    private func pump() {
        guard !working else { return }
        // Newest visible request first; drop rows scrolled away from.
        while let next = wanted.popLast() {
            guard visible.contains(next), genres[next] == nil else { continue }
            working = true
            Task {
                defer { working = false; pump() }
                do {
                    let album = try await AOTYAPI.shared.album(slug: next)
                    if let g = album.genres, !g.isEmpty {
                        genres[next] = g
                        retryAfter[next] = nil
                        save()
                    } else {
                        retryAfter[next] = Date().addingTimeInterval(30 * 60)   // AOTY may add genres later
                    }
                } catch {
                    retryAfter[next] = Date().addingTimeInterval(20)
                }
            }
            return
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(genres) { try? data.write(to: file, options: .atomic) }
    }
}
