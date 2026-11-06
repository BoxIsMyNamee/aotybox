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
    @State private var showSettings = false

    var body: some View {
        AppStack {
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView().accentTint() }
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
        if !overrideUsername.isEmpty { username = overrideUsername; savedUsername = overrideUsername; return }
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

/// Any AOTY user's profile: header, Recently Rated (AOTY's own mixed order), reviews, friends.
struct UserProfileView: View {
    let username: String
    var fallbackAvatar: String? = nil
    var isMe: Bool = false
    var onChangeUser: (() -> Void)? = nil
    var onAutoDetect: (() -> Void)? = nil

    @AppStorage("profileUsername") private var myUsername = ""
    @Environment(\.push) private var push
    @State private var profile: Profile?
    @State private var ratings: [AlbumBlock] = []
    @State private var friends: [FollowUser] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showFullProfile = false

    var body: some View {
        List {
            header

            if let reviews = profile?.reviews, !reviews.isEmpty {
                Section("Reviews") {
                    ForEach(reviews.prefix(5)) { r in ProfileReviewRow(review: r) }
                    Button { push(ProfileReviewsRoute(username: username)) } label: {
                        Label("View All Reviews", systemImage: "text.bubble").foregroundStyle(.tint)
                    }
                }
            }

            Section("Recently Rated") {
                if ratings.isEmpty && loading { ProgressView().frame(maxWidth: .infinity) }
                else if ratings.isEmpty { Text(error ?? "No ratings yet.").foregroundStyle(.secondary) }
                ForEach(ratings.prefix(3)) { a in RatingRow(album: a, isMe: isMe) }
                if !ratings.isEmpty {
                    Button { push(ProfileRatingsRoute(username: username, path: profile?.ratingsPath, isMe: isMe)) } label: {
                        Label("View All Ratings", systemImage: "list.number").foregroundStyle(.tint)
                    }
                }
            }

            if !friends.isEmpty {
                Section(isMe ? "Friends" : "Following") {
                    FriendsRow(friends: friends)
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                }
            }

            Section {
                Button { showFullProfile = true } label: { Label("Open full profile on AOTY", systemImage: "safari") }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .contentMargins(.top, 4, for: .scrollContent)
        .refreshable { await load(force: true) }
        .toolbar {
            if isMe {
                Menu {
                    Button { showFullProfile = true } label: { Label("Open full profile", systemImage: "safari") }
                    Button { Task { await load(force: true) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
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
        .task { if profile == nil && ratings.isEmpty { await load(force: false) } }
    }

    @ViewBuilder private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Avatar(url: (profile?.avatar ?? fallbackAvatar).flatMap(URL.init(string:)), name: username, size: 80)
                    Text(profile?.displayName ?? username).font(.title3.bold()).lineLimit(3)
                }
                if let about = profile?.about, !about.isEmpty {
                    Text(about)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))

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
        }
    }

    // MARK: Loading

    private func excludeSelf(_ list: [FollowUser]) -> [FollowUser] {
        list.filter { $0.username.lowercased() != username.lowercased() && $0.username.lowercased() != myUsername.lowercased() }
    }

    private func load(force: Bool) async {
        loading = true; error = nil
        defer { loading = false }
        if force { await AOTYScraper.shared.forget("/user/\(username)/") }
        do {
            let p = try await AOTYAPI.shared.profile(username: username)
            await ImageCache.shared.warm([p.avatar.flatMap(URL.init(string:))]
                + (p.reviews ?? []).prefix(5).map(\.coverURL)
                + (p.recent ?? []).prefix(3).map(\.coverURL)
                + (p.following ?? []).prefix(8).map { $0.avatar.flatMap(URL.init(string:)) })
            profile = p
            if let recent = p.recent, !recent.isEmpty {
                ratings = recent           // AOTY's own mixed order
            } else {
                ratings = (try? await AOTYAPI.shared.userRatings(username: username, page: 1)) ?? []
            }
            let preview = excludeSelf(p.following ?? [])
            if !preview.isEmpty { friends = preview }
            else { friends = excludeSelf((try? await AOTYAPI.shared.following(username: username)) ?? []) }
        } catch {
            self.error = error.localizedDescription
        }
    }

}

// MARK: - Ratings

struct RatingRow: View {
    let album: AlbumBlock
    let isMe: Bool
    var body: some View {
        NavRow(value: album, artist: album.artist, album: album.title,
               isSingle: album.mediaType?.lowercased().contains("single") ?? false, cover: album.coverURL) {
            HStack {
                AlbumRow(artist: album.artist, title: album.title, cover: album.coverURL,
                         subtitle: [album.releaseDate, album.ratedDate].compactMap { $0 }.joined(separator: " · "),
                         coverSize: 76)
                if let r = album.rating ?? album.userScore { MiniScore(label: isMe ? "You" : "", score: r) }
            }
        }
    }
}

/// Every rating, paged, on its own screen.
struct ProfileRatingsView: View {
    let username: String
    let path: String?
    let isMe: Bool
    @State private var ratings: [AlbumBlock] = []
    @State private var page = 1
    @State private var more = true
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            if let error, ratings.isEmpty { ErrorView(message: error) { await reload() } }
            ForEach(ratings) { a in
                RatingRow(album: a, isMe: isMe)
                    .onAppear { if a == ratings.last { Task { await loadMore() } } }
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
        }
        .listStyle(.plain)
        .navigationTitle("Ratings")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { if ratings.isEmpty { await reload() } }
    }

    private var listPath: String { path ?? "/user/\(username)/ratings/" }

    private func reload() async {
        loading = true; error = nil; defer { loading = false }
        do {
            let r = try await AOTYAPI.shared.ratings(path: listPath, page: 1)
            await ImageCache.shared.warm(r.prefix(10).map(\.coverURL))
            ratings = r; page = 1; more = !ratings.isEmpty
        }
        catch { self.error = error.localizedDescription }
    }

    private func loadMore() async {
        guard more, !loading else { return }
        loading = true; defer { loading = false }
        let next = (try? await AOTYAPI.shared.ratings(path: listPath, page: page + 1)) ?? []
        let fresh = next.filter { n in !ratings.contains { $0.id == n.id } }
        if fresh.isEmpty { more = false } else { ratings += fresh; page += 1 }
    }
}

// MARK: - Reviews

struct ProfileReviewRow: View {
    let review: ProfileReview
    @State private var expanded = false
    @State private var showFull = false
    @State private var fullText: String?
    @State private var loadingFull = false
    @Environment(\.push) private var push

    private var needsFetch: Bool { review.isTruncated == true && review.url != nil && fullText == nil }
    private var bodyText: String {
        (fullText ?? review.text).replacingOccurrences(of: #"\s*(\.\.\.|…)?\s*read more\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    private func toggle() async {
        if expanded { expanded = false; return }
        if needsFetch, let url = review.url {
            loadingFull = true; defer { loadingFull = false }
            if let t = try? await AOTYAPI.shared.fullReview(url: url, preview: review.text) { fullText = t }
            else { showFull = true; return }            // couldn't read it: open the review page
        }
        expanded = true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Cover(url: review.coverURL, size: 76)
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Text(review.album).font(.headline).lineLimit(2)
                    if let d = review.date { Text(d).font(.caption).foregroundStyle(.tertiary) }
                }
                Spacer()
                if let r = review.rating { MiniScore(label: "", score: r) }
            }
            .contentShape(Rectangle())
            .onTapGesture { if let s = review.slug { push(AlbumRoute(slug: s, title: review.album)) } }

            if !review.text.isEmpty {
                Text(bodyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 6)
                    .textSelection(.enabled)
                HStack(spacing: 16) {
                    if review.text.count > 280 || review.isTruncated == true {
                        Button { Task { await toggle() } } label: {
                            HStack(spacing: 6) {
                                Text(expanded ? "Show Less" : "Show More")
                                if loadingFull { ProgressView().controlSize(.mini) }
                            }
                        }
                        .disabled(loadingFull)
                    }
                    Spacer()
                    if let l = review.likes, l > 0 { Label("\(l)", systemImage: "heart").font(.caption).foregroundStyle(.tertiary) }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { Task { await MusicAppLink.open(artist: review.artist, album: review.album, song: nil, appleMusicURL: nil) } } label: {
                Label("Open", systemImage: "play.fill")
            }.tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { push(Learn.route(artist: review.artist, album: review.album, song: nil, isSingle: false, cover: review.coverURL)) } label: {
                Label("Learn", systemImage: "sparkles")
            }.tint(.green)
        }
        .sheet(isPresented: $showFull) {
            if let s = review.url, let u = URL(string: s) { AOTYWebSheet(url: u, title: review.album).accentTint() }
        }
    }
}

struct ProfileReviewsView: View {
    let username: String
    @State private var reviews: [ProfileReview] = []
    @State private var page = 1
    @State private var more = true
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            if let error, reviews.isEmpty { ErrorView(message: error) { await reload() } }
            else if reviews.isEmpty && !loading { ContentUnavailableView("No reviews yet", systemImage: "text.bubble") }
            ForEach(reviews) { r in
                ProfileReviewRow(review: r)
                    .onAppear { if r == reviews.last { Task { await loadMore() } } }
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { if reviews.isEmpty { await reload() } }
    }

    private func reload() async {
        loading = true; error = nil; defer { loading = false }
        do {
            let r = try await AOTYAPI.shared.profileReviews(username: username)
            await ImageCache.shared.warm(r.prefix(6).map(\.coverURL))
            reviews = r; page = 1; more = !reviews.isEmpty
        }
        catch { self.error = error.localizedDescription }
    }

    private func loadMore() async {
        guard more, !loading else { return }
        loading = true; defer { loading = false }
        let next = (try? await AOTYAPI.shared.profileReviews(username: username, page: page + 1)) ?? []
        let fresh = next.filter { n in !reviews.contains { $0.id == n.id } }
        if fresh.isEmpty { more = false } else { reviews += fresh; page += 1 }
    }
}

// MARK: - Friends

/// Horizontal, swipeable row of the people a user follows.
struct FriendsRow: View {
    let friends: [FollowUser]
    @Environment(\.push) private var push

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 16) {
                ForEach(friends) { f in
                    VStack(spacing: 6) {
                        Avatar(url: f.avatar.flatMap(URL.init(string:)), name: f.name, size: 64)
                        Text(f.name).font(.caption).lineLimit(1).frame(width: 72)
                    }
                    .tapAndHold(tap: { push(f) }, hold: {})
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
