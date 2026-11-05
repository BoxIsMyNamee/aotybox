import SwiftUI

/// The Profile tab: finds the signed-in user, then shows their profile.
struct ProfileView: View {
    @AppStorage("profileUsername") private var savedUsername = ""
    @AppStorage("profileUsernameOverride") private var overrideUsername = ""
    @State private var username: String?
    @State private var meAvatar: String?
    @State private var detecting = false
    @State private var error: String?
    @State private var showLogin = false
    @State private var showChange = false
    @State private var typedName = ""

    var body: some View {
        NavigationStack {
            Group {
                if let username {
                    UserProfileView(username: username, fallbackAvatar: meAvatar, isMe: true,
                                    onChangeUser: { typedName = username; showChange = true },
                                    onAutoDetect: overrideUsername.isEmpty ? nil : { overrideUsername = ""; Task { await detect() } })
                        .id(username)
                } else if detecting {
                    ProgressView("Finding your profile…")
                } else {
                    signedOut
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AlbumBlock.self) { AlbumDetailView(slug: $0.slug, fallbackTitle: $0.title) }
            .navigationDestination(for: FollowUser.self) { u in
                UserProfileView(username: u.username, fallbackAvatar: u.avatar, isMe: false)
                    .navigationTitle(u.name).navigationBarTitleDisplayMode(.inline)
            }
            .sheet(isPresented: $showLogin, onDismiss: { Task { await detect() } }) {
                AOTYWebSheet(url: AOTYSession.home, title: "Sign in").accentTint()
            }
            .alert("Your AOTY username", isPresented: $showChange) {
                TextField("username", text: $typedName).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save") {
                    let u = typedName.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@/"))
                    guard !u.isEmpty else { return }
                    overrideUsername = u
                    username = u
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("As it appears in your profile link: albumoftheyear.org/user/username")
            }
            .task { if username == nil { await detect() } }
        }
    }

    private var signedOut: some View {
        ContentUnavailableView {
            Label("Not signed in", systemImage: "person.crop.circle")
        } description: {
            Text(error ?? "Sign in to AOTY to see your profile and ratings here.")
        } actions: {
            Button("Sign in to AOTY") { showLogin = true }.buttonStyle(.borderedProminent)
            Button("Try again") { Task { await detect() } }
            Button("Enter username") { typedName = ""; showChange = true }
        }
    }

    private func detect() async {
        if !overrideUsername.isEmpty { username = overrideUsername; return }
        detecting = true; error = nil
        defer { detecting = false }
        do {
            let me = try await AOTYAPI.shared.me(refresh: true)
            if let u = me.username { username = u; meAvatar = me.avatar; savedUsername = u }
            else { username = nil }
        } catch {
            self.error = error.localizedDescription
            if !savedUsername.isEmpty { username = savedUsername }
        }
    }
}

/// Any AOTY user's profile: header, Friends, and every rating (albums + singles) newest first.
struct UserProfileView: View {
    let username: String
    var fallbackAvatar: String? = nil
    var isMe: Bool = false
    var onChangeUser: (() -> Void)? = nil
    var onAutoDetect: (() -> Void)? = nil

    @State private var profile: Profile?
    @State private var ratings: [AlbumBlock] = []
    @State private var albumPage = 1, singlePage = 1
    @State private var moreAlbums = true, moreSingles = true
    @State private var loading = false
    @State private var error: String?
    @State private var showFullProfile = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Avatar(url: (profile?.avatar ?? fallbackAvatar).flatMap(URL.init(string:)), name: username, size: 76)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile?.displayName ?? username).font(.title3.bold()).lineLimit(2)
                        Text("@\(username)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)

                if let stats = profile?.stats, !stats.isEmpty {
                    HStack {
                        ForEach(stats, id: \.label) { s in
                            VStack(spacing: 2) {
                                Text(s.value).font(.headline.monospacedDigit())
                                Text(s.label).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                if let about = profile?.about { Text(about).font(.callout).foregroundStyle(.secondary) }

                NavigationLink {
                    FriendsView(username: username, isMe: isMe)
                } label: {
                    Label(isMe ? "Friends" : "Following", systemImage: "person.2")
                }
            }

            if let error, ratings.isEmpty { Section { Text(error).font(.footnote).foregroundStyle(.red) } }

            Section("Recently Rated") {
                if ratings.isEmpty && loading { ProgressView().frame(maxWidth: .infinity) }
                else if ratings.isEmpty && error == nil { Text("No ratings yet.").foregroundStyle(.secondary) }
                ForEach(ratings) { a in
                    NavigationLink(value: a) {
                        HStack {
                            AlbumRow(artist: a.artist, title: a.title, cover: a.coverURL,
                                     subtitle: [a.releaseDate, a.ratedDate].compactMap { $0 }.joined(separator: " · "),
                                     coverSize: 56)
                            if let r = a.rating ?? a.userScore { MiniScore(label: isMe ? "You" : "", score: r) }
                        }
                    }
                    .musicAppMenu(artist: a.artist, album: a.title)
                    .onAppear { if a == ratings.last { Task { await loadMore() } } }
                }
                if loading && !ratings.isEmpty { ProgressView().frame(maxWidth: .infinity) }
            }

            Section {
                Button { showFullProfile = true } label: { Label("Open full profile on AOTY", systemImage: "safari") }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
        .toolbar {
            if isMe {
                Menu {
                    Button { showFullProfile = true } label: { Label("Open full profile", systemImage: "safari") }
                    Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    if let onChangeUser { Button(action: onChangeUser) { Label("Not you? Set username", systemImage: "person.crop.circle.badge.questionmark") } }
                    if let onAutoDetect { Button(action: onAutoDetect) { Label("Detect automatically", systemImage: "wand.and.stars") } }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showFullProfile) {
            if let url = URL(string: "https://www.albumoftheyear.org/user/\(username)/") {
                AOTYWebSheet(url: url, title: username).accentTint()
            }
        }
        .task { if profile == nil && ratings.isEmpty { await load() } }
    }

    // MARK: Loading

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        async let p = try? AOTYAPI.shared.profile(username: username)
        async let albums = try? AOTYAPI.shared.userRatings(username: username, page: 1)
        async let singles = try? AOTYAPI.shared.userRatings(username: username, page: 1, type: "single")
        let (a, s) = await (albums, singles)
        if a == nil && s == nil { error = "Couldn't load ratings." }
        albumPage = 1; singlePage = 1
        moreAlbums = !(a ?? []).isEmpty; moreSingles = !(s ?? []).isEmpty
        ratings = merge([], a ?? [], s ?? [])
        profile = await p
    }

    private func loadMore() async {
        guard !loading, moreAlbums || moreSingles else { return }
        loading = true; defer { loading = false }
        var newA: [AlbumBlock] = [], newS: [AlbumBlock] = []
        if moreAlbums {
            newA = (try? await AOTYAPI.shared.userRatings(username: username, page: albumPage + 1)) ?? []
            if newA.isEmpty { moreAlbums = false } else { albumPage += 1 }
        }
        if moreSingles {
            newS = (try? await AOTYAPI.shared.userRatings(username: username, page: singlePage + 1, type: "single")) ?? []
            if newS.isEmpty { moreSingles = false } else { singlePage += 1 }
        }
        ratings = merge(ratings, newA, newS)
    }

    /// Merge both lists newest-first by rating date. Items without a readable date keep their place.
    private func merge(_ existing: [AlbumBlock], _ a: [AlbumBlock], _ b: [AlbumBlock]) -> [AlbumBlock] {
        var seen = Set<String>()
        let all = (existing + a + b).filter { seen.insert($0.id).inserted }
        let now = Date()
        let keyed = all.enumerated().map { (i, item) in (i, item, RatedDate.parse(item.ratedDate, now: now)) }
        return keyed.sorted { x, y in
            switch (x.2, y.2) {
            case let (dx?, dy?): return dx == dy ? x.0 < y.0 : dx > dy
            case (_?, nil): return true
            case (nil, _?): return false
            default: return x.0 < y.0
            }
        }.map(\.1)
    }
}

/// Who a user follows.
struct FriendsView: View {
    let username: String
    let isMe: Bool
    @State private var users: [FollowUser] = []
    @State private var page = 1
    @State private var more = true
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            if let error, users.isEmpty { ErrorView(message: error) { await reload() } }
            else if users.isEmpty && !loading { ContentUnavailableView("Not following anyone yet", systemImage: "person.2") }
            ForEach(users) { u in
                NavigationLink(value: u) {
                    HStack(spacing: 12) {
                        Avatar(url: u.avatar.flatMap(URL.init(string:)), name: u.name, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.name).font(.body.weight(.semibold))
                            Text("@\(u.username)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onAppear { if u == users.last { Task { await loadMore() } } }
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
        }
        .listStyle(.plain)
        .navigationTitle(isMe ? "Friends" : "Following")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { if users.isEmpty { await reload() } }
    }

    private func reload() async {
        loading = true; error = nil; defer { loading = false }
        do { users = try await AOTYAPI.shared.following(username: username); page = 1; more = !users.isEmpty }
        catch { self.error = error.localizedDescription }
    }

    private func loadMore() async {
        guard more, !loading else { return }
        loading = true; defer { loading = false }
        let next = (try? await AOTYAPI.shared.following(username: username, page: page + 1)) ?? []
        let fresh = next.filter { n in !users.contains(n) }
        if fresh.isEmpty { more = false } else { users += fresh; page += 1 }
    }
}
