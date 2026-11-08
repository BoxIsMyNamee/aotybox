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
                ToolbarItem(placement: .topBarTrailing) {
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
    /// The name as shown where you tapped (keeps its real capitals while the profile loads).
    var fallbackName: String? = nil
    var fallbackColor: String? = nil
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
    @State private var showAvatar = false

    var body: some View {
        List {
            header

            // One spinner until the profile is in, instead of sections popping in one by one.
            if profile == nil && error == nil {
                Section { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30) }
                    .listRowBackground(Color.clear)
            }

            if profile != nil || error != nil {
            if let reviews = profile?.reviews, !reviews.isEmpty {
                Section("Reviews") {
                    ForEach(reviews.prefix(5)) { r in ProfileReviewRow(review: r, own: isMe) }
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
        }
        .listStyle(.insetGrouped)
        .environment(\.swipeRowBackground, Color(.secondarySystemGroupedBackground))
        .listSectionSpacing(.compact)
        .contentMargins(.top, 4, for: .scrollContent)
        .refreshable { await load(force: true) }
        .toolbar {
            if isMe {
                ToolbarItem(placement: .topBarLeading) { Menu {
                    Button { showFullProfile = true } label: { Label("Open full profile", systemImage: "safari") }
                    Button { Task { await load(force: true) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    if let onChangeUser { Button(action: onChangeUser) { Label("Not you? Set username", systemImage: "person.crop.circle.badge.questionmark") } }
                    if let onAutoDetect { Button(action: onAutoDetect) { Label("Detect automatically", systemImage: "wand.and.stars") } }
                } label: { Image(systemName: "ellipsis") } }
            }
        }
        .fullScreenCover(isPresented: $showAvatar) {
            if let s = profile?.avatar ?? fallbackAvatar, let u = URL(string: Self.largeAvatar(s)) {
                CoverViewer(url: u, title: profile?.displayName ?? username, fallback: URL(string: s)).accentTint()
            }
        }
        .sheet(isPresented: $showFullProfile) {
            if let url = URL(string: "https://www.albumoftheyear.org/user/\(username)/") {
                AOTYWebSheet(url: url, title: username).accentTint()
            }
        }
        .task { if profile == nil && ratings.isEmpty { await load(force: false) } }
    }

    /// AOTY serves small "thumbs"; ask for the full-size picture for the viewer.
    static func largeAvatar(_ s: String) -> String {
        s.replacingOccurrences(of: "/user/thumbs/", with: "/user/")
    }

    /// "harbor 🎧 (HarperSeemsCool)" → name "harbor 🎧", handle "(HarperSeemsCool)".
    static func splitName(_ full: String) -> (name: String, handle: String?) {
        let clean = full.replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = clean.firstMatch(of: /^([\s\S]*?)\s*\(([^()]+)\)\s*$/) else { return (clean, nil) }
        let name = String(m.1).trimmingCharacters(in: .whitespacesAndNewlines)
        let handle = String(m.2).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || handle.isEmpty ? (clean, nil) : (name, "(" + handle + ")")
    }

    @ViewBuilder private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Avatar(url: (profile?.avatar ?? fallbackAvatar).flatMap(URL.init(string:)), name: username, size: 80)
                        .onTapGesture { if (profile?.avatar ?? fallbackAvatar) != nil { showAvatar = true } }
                        .accessibilityAddTraits(.isButton)
                    let full = profile?.displayName ?? fallbackName ?? username
                    let parts = Self.splitName(full)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(parts.name)
                            .font(.system(.title, design: .default).weight(.bold))
                            .lineLimit(2).minimumScaleFactor(0.7)
                            .foregroundStyle((profile?.nameColor ?? fallbackColor).map { Color(hex: $0) } ?? .primary)
                        if let handle = parts.handle {
                            Text(handle).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if let stats = profile?.stats, !stats.isEmpty {
                            // "100 followers · 520 ratings" — small, under the name (no separate card).
                            Text(stats.map { "\($0.value) \($0.label.lowercased())" }.joined(separator: " · "))
                                .font(.caption.weight(.medium)).foregroundStyle(.tertiary).lineLimit(2)
                                .padding(.top, 2)
                        }
                    }
                }
                if let about = profile?.about, !about.isEmpty {
                    Text(linkified(about))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))

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
            // Gather everything first, then show it all at once (no sections popping in).
            var newRatings = p.recent ?? []          // AOTY's own mixed order
            if newRatings.isEmpty { newRatings = (try? await AOTYAPI.shared.userRatings(username: username, page: 1)) ?? [] }
            var newFriends = excludeSelf(p.following ?? [])
            if newFriends.isEmpty { newFriends = excludeSelf((try? await AOTYAPI.shared.following(username: username)) ?? []) }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                profile = p
                ratings = newRatings
                friends = newFriends
            }
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
            await ImageCache.shared.warm(r.prefix(6).map(\.coverURL), timeout: 0.6)
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

    var own = false
    private var heart: some View {
        HStack(spacing: 2) {
            if review.url != nil { CommentButton(count: review.commentCount) { showFull = true } }
            HeartButton(reviewID: review.reviewId ?? Int(review.id), liked: review.liked ?? false, likes: review.likes ?? 0, canLike: !own)
        }
    }

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
                    Button { push(ArtistRoute(path: "", name: review.artist)) } label: {
                        Text(review.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    Text(review.album).font(.headline).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let d = review.date { Text(d).font(.caption).foregroundStyle(.tertiary) }
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                if let r = review.rating { MiniScore(label: "", score: r, large: true) }
            }

            if !review.text.isEmpty {
                let hasMore = review.text.count > 280 || review.isTruncated == true
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(linkified(bodyText))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !hasMore { heart.font(.caption.weight(.semibold)) }
                }
                if hasMore { HStack(spacing: 16) {
                    if hasMore {
                        Button { Task { await toggle() } } label: {
                            HStack(spacing: 6) {
                                Text(expanded ? "Show Less" : "Show More")
                                if loadingFull { ProgressView().controlSize(.mini) }
                            }
                        }
                        .disabled(loadingFull)
                    }
                    Spacer()
                    heart
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless) }
            }
        }
        .padding(.vertical, 4)
        // The whole review (art, title, text) opens the album; buttons inside keep their own taps.
        .contentShape(Rectangle())
        .onTapGesture { if let s = review.slug { push(AlbumRoute(slug: s, title: review.album)) } }
        .heartSwipe(reviewID: review.reviewId ?? Int(review.id), liked: review.liked ?? false, likes: review.likes ?? 0, enabled: !own,
                    learn: { push(Learn.route(artist: review.artist, album: review.album, song: nil, isSingle: false, cover: review.coverURL)) },
                    view: own || review.url == nil ? nil : { showFull = true })
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .sheet(isPresented: $showFull) {
            if let s = review.url, let u = URL(string: s) { AOTYWebSheet(url: u, title: review.album).accentTint() }
        }
    }
}

struct ProfileReviewsView: View {
    let username: String
    @AppStorage("profileUsername") private var myUsername = ""
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
                ProfileReviewRow(review: r, own: username.lowercased() == myUsername.lowercased())
                    .onAppear { if r == reviews.last { Task { await loadMore() } } }
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
        }
        .listStyle(.insetGrouped)
        .environment(\.swipeRowBackground, Color(.secondarySystemGroupedBackground))
        .navigationTitle("Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { if reviews.isEmpty { await reload() } }
    }

    private func reload() async {
        loading = true; error = nil; defer { loading = false }
        do {
            let r = try await AOTYAPI.shared.profileReviews(username: username)
            await ImageCache.shared.warm(r.prefix(6).map(\.coverURL), timeout: 0.6)
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
                            .foregroundStyle(f.nameColor.map { Color(hex: $0) } ?? .primary)
                    }
                    .tapAndHold(tap: { push(f) }, hold: {})
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
