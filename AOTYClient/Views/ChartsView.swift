import SwiftUI

/// Charts: Critics and Users as two pages you can switch by tapping the picker or swiping sideways.
struct ChartsView: View {
    enum Source: String, CaseIterable, Identifiable {
        case critics = "6-highest-rated", users = "user-highest-rated"
        var id: String { rawValue }
        var label: String { self == .critics ? "Critics" : "Users" }
    }

    @State private var source: Source = .critics
    @State private var period = String(Calendar.current.component(.year, from: .now))

    private var periods: [String] {
        let year = Calendar.current.component(.year, from: .now)
        return (0..<15).map { String(year - $0) } + ["all"]
    }

    var body: some View {
        AppStack {
            VStack(spacing: 0) {
                Picker("Source", selection: $source.animation(.easeInOut(duration: 0.25))) {
                    ForEach(Source.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                TabView(selection: $source) {
                    ForEach(Source.allCases) { s in
                        ChartList(source: s, period: period)
                            .id("\(s.rawValue)-\(period)")
                            .tag(s)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .tabTitle(period == "all" ? "All Time" : "Best of \(period)")
            .toolbar {
                Menu {
                    Picker("Year", selection: $period) {
                        ForEach(periods, id: \.self) { Text($0 == "all" ? "All time" : $0).tag($0) }
                    }
                } label: { Label("Year", systemImage: "calendar") }
            }
        }
    }
}

/// One chart page. Keeps its own data, so swiping back is instant.
private struct ChartList: View {
    let source: ChartsView.Source
    let period: String
    @State private var items: [ChartItem] = []
    @State private var page = 1
    @State private var totalPages = 1
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            if let error, items.isEmpty { ErrorView(message: error) { await reload() } }
            ForEach(items) { item in
                NavRow(value: item, artist: item.artist, album: item.album, cover: item.coverURL) {
                    AlbumRow(artist: item.artist, title: item.album, cover: item.coverURL,
                             subtitle: [item.date, item.genres?.first].compactMap { $0 }.joined(separator: " · "),
                             rank: item.rank,
                             critic: source == .critics ? item.score : nil,
                             user: source == .users ? item.score : nil,
                             mustHear: item.mustHear ?? false)
                }
                .onAppear { if item == items.last { Task { await loadMore() } } }
            }
            if loading { ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden) }
        }
        .listStyle(.plain)
        .refreshable { await refresh() }
        .task { if items.isEmpty { await reload() } }
    }

    private func refresh() async {
        await AOTYScraper.shared.clearCache()
        let started = Date()
        if let res = try? await AOTYAPI.shared.chart(source: source.rawValue, period: period, page: 1), !res.items.isEmpty {
            await ImageCache.shared.warm(res.items.prefix(6).map(\.coverURL), timeout: 0.6)
            let wait = 0.5 - Date().timeIntervalSince(started)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { items = res.items; page = 1; totalPages = res.totalPages ?? 1; error = nil }
        }
    }

    private func reload() async {
        error = nil; loading = true; defer { loading = false }
        do {
            let res = try await AOTYAPI.shared.chart(source: source.rawValue, period: period, page: 1)
            await ImageCache.shared.warm(res.items.prefix(6).map(\.coverURL), timeout: 0.6)
            items = res.items; page = 1; totalPages = res.totalPages ?? 1
            Task { await ImageCache.shared.warm(res.items.map(\.coverURL), timeout: 30) }
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription; items = [] }
    }

    private func loadMore() async {
        guard !loading, page < totalPages else { return }
        loading = true; defer { loading = false }
        if let res = try? await AOTYAPI.shared.chart(source: source.rawValue, period: period, page: page + 1) {
            await ImageCache.shared.warm(res.items.prefix(6).map(\.coverURL), timeout: 0.4)
            items += res.items.filter { n in !items.contains { $0.id == n.id } }
            page += 1
            Task { await ImageCache.shared.warm(res.items.map(\.coverURL), timeout: 30) }
        } else { totalPages = page }
    }
}
