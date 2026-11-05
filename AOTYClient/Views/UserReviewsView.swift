import SwiftUI

/// Every user review for an album, paged like AOTY's "User Reviews" tab.
struct UserReviewsView: View {
    let slug: String
    let title: String

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
            Section {
                Picker("Sort", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            if !distribution.isEmpty {
                Section("Rating Distribution") { DistributionChart(rows: distribution) }
            }

            if let error, reviews.isEmpty {
                ErrorView(message: error) { await reload() }
            }

            Section(total.map { "\($0.formatted()) user reviews" } ?? "") {
                ForEach(reviews) { r in
                    UserReviewRow(review: r, lineLimit: 10)
                        .onAppear { if r == reviews.last { Task { await loadMore() } } }
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("User Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task(id: sort) { await reload() }
    }

    private func reload() async {
        error = nil; loading = true; defer { loading = false }
        do {
            let p = try await AOTYAPI.shared.userReviews(slug: slug, sort: sort.param, page: 1)
            reviews = p.reviews; page = 1; totalPages = p.totalPages ?? 1; total = p.total
            if let d = p.distribution, !d.isEmpty { distribution = d }
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription; reviews = [] }
    }

    private func loadMore() async {
        guard !loading, page < totalPages else { return }
        loading = true; defer { loading = false }
        if let p = try? await AOTYAPI.shared.userReviews(slug: slug, sort: sort.param, page: page + 1) {
            reviews += p.reviews.filter { n in !reviews.contains { $0.id == n.id } }
            page += 1
        } else { totalPages = page }
    }
}

struct DistributionChart: View {
    let rows: [DistributionRow]
    var body: some View {
        let maxCount = max(rows.map(\.count).max() ?? 1, 1)
        VStack(spacing: 6) {
            ForEach(rows, id: \.label) { row in
                HStack(spacing: 8) {
                    Text(row.label).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                    Text(row.count.formatted()).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 48, alignment: .trailing)
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor(row.label))
                            .frame(width: max(2, g.size.width * CGFloat(row.count) / CGFloat(maxCount)))
                    }
                    .frame(height: 12)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func barColor(_ label: String) -> Color {
        let n = Double(label.split(separator: " ").first.flatMap { Int($0) } ?? 0)
        return scoreColor(n == 100 ? 100 : n + 5)
    }
}
