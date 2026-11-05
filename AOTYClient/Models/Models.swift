import Foundation

// Shapes mirror src/types.ts in edideaur/AOTY-api.
// Only the fields the app uses are declared; JSONDecoder ignores the rest.

/// A compact album card — used by releases, upcoming, discover and search.
struct AlbumBlock: Decodable, Identifiable, Hashable {
    let url: String
    let artist: String
    let title: String
    let cover: String
    let mediaType: String?
    let releaseDate: String?
    let criticScore: Double?
    let criticCount: Int?
    let userScore: Double?
    let userCount: Int?
    let mustHear: Bool?

    var id: String { url }
    var slug: String? { AlbumSlug.from(url) }
    var coverURL: URL? { URL(string: cover) }
}

/// One row on a ratings chart (/ratings).
struct ChartItem: Decodable, Identifiable, Hashable {
    let rank: Int
    let artist: String
    let album: String
    let url: String
    let cover: String?
    let date: String?
    let genres: [String]?
    let score: Double?
    let ratingCount: Int?
    let mustHear: Bool?

    var id: String { url }
    var slug: String? { AlbumSlug.from(url) }
    var coverURL: URL? { cover.flatMap(URL.init(string:)) }
}

struct Track: Decodable, Identifiable, Hashable {
    let number: Int
    let title: String
    let length: String?
    let rating: Double?
    let features: [String]?
    var id: String { "\(number)-\(title)" }
}

struct CriticReview: Decodable, Identifiable, Hashable {
    let image: String?
    let score: Double?
    let publication: String
    let author: String?
    let text: String
    let url: String?
    let date: String?
    var id: String { publication + (author ?? "") + (date ?? "") }
}

struct UserReview: Decodable, Identifiable, Hashable {
    let reviewId: Int?
    let username: String
    let avatar: String?
    let rating: Double?
    let text: String
    let isTruncated: Bool?
    let url: String?
    let likes: Int?
    let date: String?
    var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }
    var id: String { reviewId.map(String.init) ?? username + (date ?? "") }
}

struct StreamingLink: Decodable, Hashable {
    let platform: String
    let url: String
}

struct RankingInfo: Decodable, Hashable {
    let year: Int?
    let rank: Int
    let total: Int?
}

/// Full album page (/album?slug=…).
struct AlbumDetail: Decodable, Hashable {
    let url: String
    let title: String
    let artist: String
    let artistUrl: String?
    let cover: String
    let datePublished: String?
    let format: String?
    let label: String?
    let genres: [String]?
    let tags: [String]?
    let totalLength: String?
    let mustHear: Bool?
    let criticScore: Double?
    let criticCount: Int?
    let criticRanking: RankingInfo?
    let userScore: Double?
    let userCount: Int?
    let userRanking: RankingInfo?
    let tracklist: [Track]?
    let streamingLinks: [StreamingLink]?
    let reviews: [CriticReview]?
    let popularUserReviews: [UserReview]?
    let similarAlbums: [AlbumBlock]?
    let moreAlbums: [AlbumBlock]?

    var coverURL: URL? { URL(string: cover) }
}

// MARK: - Response envelopes

struct DistributionRow: Decodable, Hashable {
    let label: String
    let count: Int
}

struct UserReviewsPage: Decodable {
    let reviews: [UserReview]
    let total: Int?
    let totalPages: Int?
    let distribution: [DistributionRow]?
}

struct AlbumListResponse: Decodable {
    let page: Int?
    let albums: [AlbumBlock]
}

struct ChartResponse: Decodable {
    let source: String?
    let period: String?
    let page: Int?
    let totalPages: Int?
    let items: [ChartItem]
}

struct APIErrorBody: Decodable {
    let error: String?
    let message: String?
    let detail: String?
}

// MARK: - Slugs

enum AlbumSlug {
    /// "https://www.albumoftheyear.org/album/12345-artist-title.php" → "12345-artist-title"
    /// Also handles relative "/album/12345-artist-title/" forms.
    static func from(_ url: String) -> String? {
        guard let range = url.range(of: "/album/") else { return nil }
        var rest = String(url[range.upperBound...])
        if let q = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) { rest = String(rest[..<q]) }
        rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if rest.hasSuffix(".php") { rest.removeLast(4) }
        if let slash = rest.firstIndex(of: "/") { rest = String(rest[..<slash]) }
        return rest.isEmpty ? nil : rest
    }
}
