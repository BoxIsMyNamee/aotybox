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
    private var failed: Set<String> = []
    private var working = false
    private let file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("genres.json")

    private init() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: [String]].self, from: data) {
            genres = saved
        }
    }

    func label(for slug: String?) -> String? {
        guard let slug, let g = genres[slug], !g.isEmpty else { return nil }
        return g.prefix(2).joined(separator: ", ")
    }

    func appeared(_ slug: String?) {
        guard let slug, genres[slug] == nil, !failed.contains(slug) else { return }
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
                    genres[next] = album.genres ?? []
                    save()
                } catch {
                    failed.insert(next)
                }
            }
            return
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(genres) { try? data.write(to: file, options: .atomic) }
    }
}
