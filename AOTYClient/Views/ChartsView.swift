import SwiftUI

struct ChartsView: View {
    enum Source: String, CaseIterable, Identifiable {
        case critics = "6-highest-rated", users = "user-highest-rated"
        var id: String { rawValue }
        var label: String { self == .critics ? "Critics" : "Users" }
    }

    @State private var source: Source = .critics
    @State private var period = String(Calendar.current.component(.year, from: .now))
    @State private var items: [ChartItem] = []
    @State private var page = 1
    @State private var totalPages = 1
    @State private var loading = false
    @State private var error: String?

    private var periods: [String] {
        let year = Calendar.current.component(.year, from: .now)
        return (0..<15).map { String(year - $0) } + ["all"]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Source", selection: $source) {
                        ForEach(Source.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }

                if let error, items.isEmpty { ErrorView(message: error) { await reload() } }

                ForEach(items) { item in
                    NavigationLink(value: item) {
                        AlbumRow(artist: item.artist, title: item.album, cover: item.coverURL,
                                 subtitle: [item.date, item.genres?.first].compactMap { $0 }.joined(separator: " · "),
                                 rank: item.rank,
                                 critic: source == .critics ? item.score : nil,
                                 user: source == .users ? item.score : nil,
                                 mustHear: item.mustHear ?? false)
                    }
                    .musicAppMenu(artist: item.artist, album: item.album)
                    .onAppear { if item == items.last { Task { await loadMore() } } }
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if !items.isEmpty && page >= totalPages { AttributionFooter() }
            }
            .listStyle(.plain)
            .navigationTitle(period == "all" ? "All Time" : "Best of \(period)")
            .toolbar {
                Menu {
                    Picker("Year", selection: $period) {
                        ForEach(periods, id: \.self) { Text($0 == "all" ? "All time" : $0).tag($0) }
                    }
                } label: { Label("Year", systemImage: "calendar") }
            }
            .navigationDestination(for: ChartItem.self) { AlbumDetailView(slug: $0.slug, fallbackTitle: $0.album) }
            .refreshable { await reload() }
            .task(id: "\(source.rawValue)|\(period)") { await reload() }
        }
    }

    private func reload() async {
        error = nil; loading = true; defer { loading = false }
        do {
            let res = try await AOTYAPI.shared.chart(source: source.rawValue, period: period, page: 1)
            items = res.items; page = 1; totalPages = res.totalPages ?? 1
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription; items = [] }
    }

    private func loadMore() async {
        guard !loading, page < totalPages else { return }
        loading = true; defer { loading = false }
        if let res = try? await AOTYAPI.shared.chart(source: source.rawValue, period: period, page: page + 1) {
            items += res.items.filter { n in !items.contains { $0.id == n.id } }
            page += 1
        } else { totalPages = page }
    }
}
