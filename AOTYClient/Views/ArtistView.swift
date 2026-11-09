import SwiftUI
import UIKit

/// Native artist page: wide photo, scores + details, then Albums / EPs / Singles (switch at the
/// bottom). The filter button adds AOTY's other release types (reissues, live, …) into Albums.
struct ArtistView: View {
    let path: String?
    let fallbackName: String

    enum Category: String, CaseIterable, Identifiable {
        case albums = "Albums", eps = "EPs", singles = "Singles", appears = "Appears On"
        var id: String { rawValue }
        var aotyType: String { switch self { case .albums: "lp"; case .eps: "ep"; case .singles: "single"; case .appears: "appears" } }
        var short: String { self == .appears ? "Features" : rawValue }
    }
    /// Extra AOTY types that can be folded into Albums.
    static let extras: [(String, String)] = [
        ("reissue", "Reissues & Deluxes"), ("live", "Live"), ("compilation", "Compilations"),
        ("mixtape", "Mixtapes"), ("remix", "Remixes"), ("demo", "Demos"), ("miscellaneous", "Miscellaneous"),
    ]

    @State private var base: String?
    @State private var artist: AOTYAPI.Artist?          // featured page: header, info
    @State private var lists: [String: [AlbumBlock]] = [:]   // by AOTY type
    @State private var loadingTypes: Set<String> = []
    @State private var failedTypes: Set<String> = []
    @State private var error: String?
    @State private var category: Category = .albums
    @State private var following: Bool?        // nil = what the page said
    @State private var followBusy = false
    @State private var followError: String?
    @AppStorage("artistExtras") private var extrasRaw = ""
    @Environment(\.push) private var push
    @Environment(\.openURL) private var openURL

    private var extrasOn: Set<String> { Set(extrasRaw.split(separator: ",").map(String.init)) }
    private func setExtra(_ t: String, _ on: Bool) {
        var s = extrasOn; if on { s.insert(t) } else { s.remove(t) }
        extrasRaw = s.sorted().joined(separator: ",")
    }

    var body: some View {
        Group {
            if let artist { content(artist) }
            else if let error { ErrorView(message: error) { await load() } }
            else { ProgressView() }
        }
        .navigationTitle(artist?.name ?? fallbackName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if artist != nil {
                HStack(spacing: 12) {
                    GlassSegmented(selection: $category, items: Category.allCases.map { ($0, $0.short) })
                    Menu {
                        Section("Also show in Albums") {
                            ForEach(Self.extras, id: \.0) { t in
                                Toggle(t.1, isOn: Binding(get: { extrasOn.contains(t.0) }, set: { setExtra(t.0, $0) }))
                            }
                        }
                    } label: {
                        FloatingIcon(symbol: extrasOn.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .menuStyle(.button)
                    .floatingGlass()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .task { if artist == nil { await load() } }
        .onChange(of: category) { Task { await ensureLoaded() } }
        .onChange(of: extrasRaw) { Task { await ensureLoaded() } }
    }

    // MARK: Content

    private var shown: [AlbumBlock] {
        var types = [category.aotyType]
        if category == .albums { types += Self.extras.map(\.0).filter { extrasOn.contains($0) } }
        var seen = Set<String>()
        let all = types.flatMap { lists[$0] ?? [] }.filter { seen.insert($0.url).inserted }
        // Newest first (blocks carry "2026 • Label"); Appears On keeps AOTY's order.
        return category == .appears ? all : all.sorted { year($0) > year($1) }
    }
    private func year(_ a: AlbumBlock) -> Int { Int((a.releaseDate ?? "").prefix(4)) ?? 0 }
    private var currentTypes: Set<String> { Set([category.aotyType] + (category == .albums ? Array(extrasOn) : [])) }
    private var isLoadingCategory: Bool {
        !loadingTypes.isDisjoint(with: [category.aotyType] + (category == .albums ? Array(extrasOn) : []))
    }

    /// Follower count that moves with your own follow/unfollow.
    private func followersText(_ a: AOTYAPI.Artist) -> String? {
        guard let f = a.followers else { return nil }
        guard let now = following, let was = a.following, now != was else { return f }
        let digits = f.filter(\.isNumber)
        guard let n = Int(digits) else { return f }
        let m = max(0, n + (now ? 1 : -1))
        return "\(m.formatted()) Followers"
    }

    private func followButton(_ id: Int, _ a: AOTYAPI.Artist) -> some View {
        let on = following ?? a.following ?? false
        return Button {
            Task {
                followBusy = true; defer { followBusy = false }
                let want = !on
                following = want                                  // optimistic
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if await AOTYAPI.shared.setArtistFollow(id, follow: want) {
                    if let base { await AOTYScraper.shared.forget(base) }
                } else {
                    following = on
                    followError = "AOTY didn't accept that. Try again."
                }
            }
        } label: {
            Text(on ? "Following" : "Follow")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Color.primary : Color.white)
                .padding(.horizontal, 16).frame(height: 32)
                .background(on ? AnyShapeStyle(Color(.tertiarySystemFill)) : AnyShapeStyle(Color.accentColor), in: Capsule())
                .contentTransition(.interpolate)
        }
        .buttonStyle(.plain)
        .disabled(followBusy)
        .alert("Couldn't update follow", isPresented: Binding(get: { followError != nil }, set: { if !$0 { followError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(followError ?? "") }
    }

    @ViewBuilder private func content(_ a: AOTYAPI.Artist) -> some View {
        List {
            Section { hero(a) }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            if a.criticScore != nil || a.userScore != nil || a.followers != nil {
                Section {
                    HStack(spacing: 0) {
                        scoreCell("Critic", a.criticScore, a.criticCount.map { "\($0.formatted()) reviews" })
                        Divider().frame(height: 44)
                        scoreCell("User", a.userScore, a.userCount.map { "\($0.formatted()) ratings" })
                    }
                    if a.followers != nil || a.artistID != nil {
                        HStack {
                            if let f = followersText(a) { Label(f, systemImage: "person.2").font(.subheadline).foregroundStyle(.secondary) }
                            Spacer(minLength: 8)
                            if let id = a.artistID { followButton(id, a) }
                        }
                    }
                }
            }

            if let details = a.details, !details.isEmpty {
                Section("Details") {
                    ForEach(details, id: \.self) { d in detailRow(d) }
                }
            }

            Section {
                if isLoadingCategory && shown.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                } else if shown.isEmpty && !failedTypes.isDisjoint(with: currentTypes) {
                    HStack {
                        Text("Couldn't load \(category.rawValue.lowercased()).").foregroundStyle(.secondary)
                        Spacer()
                        Button("Retry") { failedTypes.subtract(currentTypes); Task { await ensureLoaded() } }
                    }
                } else if shown.isEmpty {
                    Text("No \(category.rawValue.lowercased()) on AOTY.").foregroundStyle(.secondary)
                }
                ForEach(shown) { album in
                    NavRow(value: album, artist: album.artist, album: album.title,
                           isSingle: category == .singles, cover: album.coverURL) {
                        AlbumRow(artist: album.artist, title: album.title, cover: album.coverURL, subtitle: album.releaseDate,
                                 critic: album.criticScore, user: album.userScore, mustHear: album.mustHear ?? false, coverSize: 64)
                    }
                }
            } header: {
                HStack {
                    Text(category.rawValue)
                    if category == .albums && !extrasOn.isEmpty { Text("+ \(extrasOn.count) filter\(extrasOn.count == 1 ? "" : "s")").foregroundStyle(.tint) }
                    Spacer()
                    if isLoadingCategory && !shown.isEmpty { ProgressView().controlSize(.mini) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.swipeRowBackground, Color(.secondarySystemGroupedBackground))
    }

    private func hero(_ a: AOTYAPI.Artist) -> some View {
        ZStack(alignment: .bottomLeading) {
            CachedImage(url: a.image.flatMap(URL.init(string:))) { Rectangle().fill(.quaternary.opacity(0.5)) }
                .frame(maxWidth: .infinity).frame(height: 300).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            Text(a.name).font(.largeTitle.bold()).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.6)
                .padding(16)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func scoreCell(_ label: String, _ score: Double?, _ sub: String?) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(score.map { String(Int($0.rounded())) } ?? "NR")
                .font(.system(.title, design: .rounded).weight(.bold)).foregroundStyle(scoreColor(score))
            if let sub { Text(sub).font(.caption2).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func detailRow(_ d: AOTYAPI.Artist.Detail) -> some View {
        let artistLinks = (d.links ?? []).filter { $0.href.contains("/artist/") }
        VStack(alignment: .leading, spacing: 4) {
            Text(d.label).font(.caption).foregroundStyle(.secondary)
            if !artistLinks.isEmpty {
                ChipLayout(spacing: 6) {
                    ForEach(artistLinks, id: \.self) { l in
                        Button(l.text) { push(ArtistRoute(path: URL(string: l.href, relativeTo: URL(string: "https://www.albumoftheyear.org"))?.path ?? l.href, name: l.text)) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            } else if d.label.lowercased().contains("website"), let l = d.links?.first,
                      let u = URL(string: l.href.hasPrefix("//") ? "https:" + l.href : l.href) {
                Button(d.value) { openURL(u) }
            } else {
                Text(d.value).font(.body)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Loading

    private func load() async {
        error = nil
        do {
            var p = base ?? path
            if p == nil { p = await AOTYAPI.shared.findArtistPath(name: fallbackName) }
            guard var b = p?.components(separatedBy: "?").first else { error = "Couldn't find \(fallbackName) on AOTY."; return }
            if !b.hasSuffix("/") { b += "/" }    // "/artist/123-name?type=ep" without the slash doesn't load the list
            base = b
            let a = try await AOTYAPI.shared.artist(path: b)
            await ImageCache.shared.warm([a.image.flatMap(URL.init(string:))])
            artist = a
            // The featured page already lists albums/EPs; use it until the full lists arrive.
            let groupedLP = a.albums.filter { ($0.mediaType ?? "").lowercased().contains("album") || ($0.mediaType ?? "").lowercased() == "lp" }
            if lists["lp"] == nil, !groupedLP.isEmpty { lists["lp"] = groupedLP }
            await ensureLoaded()
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    /// Fetch AOTY's full list for the current category (and enabled extras) if we don't have it.
    private func ensureLoaded() async {
        guard let base else { return }
        var types = [category.aotyType]
        if category == .albums { types += Array(extrasOn) }
        await withTaskGroup(of: Void.self) { group in
            for t in types where !loadingTypes.contains(t) && !failedTypes.contains(t) && (lists[t] == nil || (t == "lp" && !fullLP)) {
                loadingTypes.insert(t)
                group.addTask { @MainActor in
                    defer { loadingTypes.remove(t) }
                    do {
                        let albums: [AlbumBlock]
                        if t == "appears" { albums = try await AOTYAPI.shared.appearsOn(artistPath: base) }
                        else { albums = try await AOTYAPI.shared.artist(path: base + "?type=" + t).albums }
                        lists[t] = albums.filter { !$0.url.isEmpty && !$0.title.isEmpty }
                        failedTypes.remove(t)
                        if t == "lp" { fullLP = true }
                        Task { await ImageCache.shared.warm(albums.prefix(12).map(\.coverURL), timeout: 30) }
                    } catch {
                        failedTypes.insert(t)
                    }
                }
            }
        }
    }
    @State private var fullLP = false
}
