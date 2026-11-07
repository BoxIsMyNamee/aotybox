import SwiftUI

/// Every user review for an album, paged like AOTY's "User Reviews" tab.
struct UserReviewsView: View {
    let slug: String
    let title: String
    /// A rating bucket from the distribution chart ("100", "90 - 99"): shows only those reviews.
    var rangeLabel: String? = nil
    var artist: String? = nil
    var cover: URL? = nil
    @Environment(\.push) private var push

    private var range: ClosedRange<Double>? {
        guard let rangeLabel else { return nil }
        let nums = rangeLabel.split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }
        guard let lo = nums.first else { return nil }
        return lo...(nums.count > 1 ? nums[1] + 0.999 : lo + 0.999)
    }
    private var sortParam: String { range.map { $0.lowerBound < 60 ? "worst" : "best" } ?? sort.param }
    private func inRange(_ r: UserReview) -> Bool { range.map { r.rating.map($0.contains) ?? false } ?? true }

    enum Sort: String, CaseIterable, Identifiable {
        case best = "Popular", recent = "Recent", worst = "Lowest"
        var id: String { rawValue }
        var param: String { switch self { case .best: "best"; case .recent: "recent"; case .worst: "worst" } }
    }

    @State private var sort: Sort = .best
    @State private var reviews: [UserReview] = []
    @State private var distribution: [DistributionRow] = []
    @State private var total: Int?
    @State private var page = 1
    @State private var totalPages = 1
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            if range == nil {
                if !distribution.isEmpty {
                    Section {
                        DistributionChart(rows: distribution) { label in
                            push(UserReviewsRoute(slug: slug, title: title, range: label, artist: artist, cover: cover))
                        }
                    } header: { Text("Rating Distribution") } footer: { Text("Tap a row to see those reviews.") }
                }
            }

            if let error, reviews.isEmpty {
                ErrorView(message: error) { await reload() }
            }

            Section(range != nil ? "Rated \(rangeLabel ?? "")" : (total.map { "\($0.formatted()) user reviews" } ?? "")) {
                ForEach(reviews) { r in
                    UserReviewRow(review: r, lineLimit: 10, learn: artist.map { art in
                        { push(Learn.route(artist: art, album: title, song: nil, isSingle: false, cover: cover)) }
                    })
                        .onAppear { if r == reviews.last { Task { await loadMore() } } }
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if range != nil && !loading && reviews.isEmpty && error == nil {
                    Text("No reviews in this range.").foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            // Sort switcher floating at the bottom, like Releases and Charts.
            if range == nil {
                GlassSegmented(selection: $sort, items: Sort.allCases.map { ($0, $0.rawValue) })
                    .frame(maxWidth: 320)
                    .padding(.bottom, 8)
            }
        }
        .environment(\.swipeRowBackground, Color(.secondarySystemGroupedBackground))
        .navigationTitle(rangeLabel.map { "Rated \($0)" } ?? "User Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task(id: sort) { await reload() }
    }

    private func reload() async {
        error = nil; loading = true; defer { loading = false }
        do {
            let p = try await AOTYAPI.shared.userReviews(slug: slug, sort: sortParam, page: 1)
            await ImageCache.shared.warm(p.reviews.prefix(6).map(\.avatarURL), timeout: 0.6)
            reviews = p.reviews.filter(inRange); page = 1; totalPages = p.totalPages ?? 1; total = p.total
            if let d = p.distribution, !d.isEmpty { distribution = d }
            if range != nil { await scan(target: 10) }
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription; reviews = [] }
    }

    /// Filtered view: AOTY can't filter by rating, so read more pages until enough match.
    /// "Lowest" is sorted ascending, so it stops once ratings pass the range.
    private func scan(target: Int) async {
        guard let range else { return }
        var pagesRead = 0
        while reviews.count < target, page < totalPages, pagesRead < 12, !Task.isCancelled {
            guard let p = try? await AOTYAPI.shared.userReviews(slug: slug, sort: sortParam, page: page + 1) else { totalPages = page; break }
            page += 1; pagesRead += 1
            reviews += p.reviews.filter(inRange).filter { n in !reviews.contains { $0.id == n.id } }
            if sortParam == "worst", let maxR = p.reviews.compactMap(\.rating).max(), maxR > range.upperBound { totalPages = page; break }
        }
    }

    private func loadMore() async {
        guard !loading, page < totalPages else { return }
        loading = true; defer { loading = false }
        if range != nil { await scan(target: reviews.count + 10); return }
        if let p = try? await AOTYAPI.shared.userReviews(slug: slug, sort: sortParam, page: page + 1) {
            reviews += p.reviews.filter { n in !reviews.contains { $0.id == n.id } }
            page += 1
        } else { totalPages = page }
    }
}

struct DistributionChart: View {
    let rows: [DistributionRow]
    var onSelect: ((String) -> Void)? = nil
    var body: some View {
        let maxCount = max(rows.map(\.count).max() ?? 1, 1)
        VStack(spacing: 6) {
            ForEach(rows, id: \.label) { row in
                Button { onSelect?(row.label) } label: { HStack(spacing: 8) {
                    Text(row.label).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                    Text(row.count.formatted()).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 48, alignment: .trailing)
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor(row.label))
                            .frame(width: max(2, g.size.width * CGFloat(row.count) / CGFloat(maxCount)))
                    }
                    .frame(height: 12)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .disabled(onSelect == nil || row.count == 0)
            }
        }
        .padding(.vertical, 4)
    }

    private func barColor(_ label: String) -> Color {
        let n = Double(label.split(separator: " ").first.flatMap { Int($0) } ?? 0)
        return scoreColor(n == 100 ? 100 : n + 5)
    }
}
