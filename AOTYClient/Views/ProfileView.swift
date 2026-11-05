import SwiftUI

/// The signed-in user's AOTY profile: header, stats, and recent ratings, all native.
struct ProfileView: View {
    @AppStorage("profileUsername") private var savedUsername = ""
    @AppStorage("profileUsernameOverride") private var overrideUsername = ""
    @State private var showChange = false
    @State private var singles = false
    @State private var typedName = ""
    @State private var username: String?
    @State private var meAvatar: String?
    @State private var profile: Profile?
    @State private var ratings: [AlbumBlock] = []
    @State private var ratingsPage = 1
    @State private var moreRatings = true
    @State private var loading = false
    @State private var error: String?
    @State private var showLogin = false
    @State private var showFullProfile = false

    var body: some View {
        NavigationStack {
            Group {
                if let username { content(username) }
                else if loading { ProgressView("Finding your profile…") }
                else { signedOut }
            }
            .navigationTitle(profile?.displayName ?? username ?? "Profile")
            .navigationDestination(for: AlbumBlock.self) { AlbumDetailView(slug: $0.slug, fallbackTitle: $0.title) }
            .toolbar {
                if username != nil {
                    Menu {
                        Button { showFullProfile = true } label: { Label("Open full profile", systemImage: "safari") }
                        Button { Task { await detect(refresh: true) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        Button { typedName = username ?? ""; showChange = true } label: { Label("Not you? Set username", systemImage: "person.crop.circle.badge.questionmark") }
                        if !overrideUsername.isEmpty {
                            Button { overrideUsername = ""; Task { await detect(refresh: true) } } label: { Label("Detect automatically", systemImage: "wand.and.stars") }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showLogin, onDismiss: { Task { await detect(refresh: true) } }) {
                AOTYWebSheet(url: AOTYSession.home, title: "Sign in").accentTint()
            }
            .sheet(isPresented: $showFullProfile) {
                if let u = username, let url = URL(string: "https://www.albumoftheyear.org/user/\(u)/") {
                    AOTYWebSheet(url: url, title: u).accentTint()
                }
            }
            .task { if username == nil { await detect(refresh: true) } }
            .alert("Your AOTY username", isPresented: $showChange) {
                TextField("username", text: $typedName)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save") {
                    let u = typedName.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@/"))
                    guard !u.isEmpty else { return }
                    overrideUsername = u
                    Task { await detect(refresh: false) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("As it appears in your profile link: albumoftheyear.org/user/username")
            }
        }
    }

    private var signedOut: some View {
        ContentUnavailableView {
            Label("Not signed in", systemImage: "person.crop.circle")
        } description: {
            Text(error ?? "Sign in to AOTY to see your profile and ratings here.")
        } actions: {
            Button("Sign in to AOTY") { showLogin = true }.buttonStyle(.borderedProminent)
            Button("Try again") { Task { await detect(refresh: true) } }
            Button("Enter username") { typedName = ""; showChange = true }
        }
    }

    @ViewBuilder private func content(_ user: String) -> some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Avatar(url: (profile?.avatar ?? meAvatar).flatMap(URL.init(string:)), name: user, size: 76)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile?.displayName ?? user).font(.title2.bold())
                        Text("@\(user)").font(.subheadline).foregroundStyle(.secondary)
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
            }

            if let error, ratings.isEmpty { Section { Text(error).font(.footnote).foregroundStyle(.red) } }

            Section {
                Picker("Type", selection: $singles) {
                    Text("Albums").tag(false)
                    Text("Singles").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            if ratings.isEmpty && !loading && error == nil {
                Section { Text(singles ? "No rated singles yet." : "No ratings yet.").foregroundStyle(.secondary) }
            }

            if !ratings.isEmpty {
                Section(singles ? "Rated Singles" : "Recent Ratings") {
                    ForEach(ratings) { a in
                        NavigationLink(value: a) {
                            HStack {
                                AlbumRow(artist: a.artist, title: a.title, cover: a.coverURL, subtitle: a.releaseDate, coverSize: 56)
                                if let r = a.rating ?? a.userScore { MiniScore(label: "You", score: r) }
                            }
                        }
                        .onAppear { if a == ratings.last { Task { await loadMoreRatings(user) } } }
                    }
                }
            } else if !singles, let albums = profile?.albums, !albums.isEmpty {
                Section("On Your Profile") {
                    ForEach(albums) { a in NavigationLink(value: a) { AlbumRow(a) } }
                }
            }

            Section {
                Button { showFullProfile = true } label: { Label("Open full profile on AOTY", systemImage: "safari") }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load(user) }
        .onChange(of: singles) { Task { await loadRatings(user) } }
        .overlay { if loading && profile == nil { ProgressView() } }
    }

    private func detect(refresh: Bool) async {
        loading = true; error = nil
        defer { loading = false }
        if !overrideUsername.isEmpty {
            username = overrideUsername; meAvatar = nil; profile = nil; ratings = []
            await load(overrideUsername)
            return
        }
        do {
            let me = try await AOTYAPI.shared.me(refresh: refresh)
            if let u = me.username {
                if u != username { profile = nil; ratings = [] }
                username = u; meAvatar = me.avatar; savedUsername = u
                await load(u)
                return
            }
            username = nil
        } catch {
            self.error = error.localizedDescription
            // Fall back to the last known username so the tab still works offline.
            if !savedUsername.isEmpty { username = savedUsername; await load(savedUsername) }
        }
    }

    private func load(_ user: String) async {
        loading = true; defer { loading = false }
        async let p = try? AOTYAPI.shared.profile(username: user)
        await loadRatings(user)
        profile = await p
    }

    private func loadRatings(_ user: String) async {
        error = nil
        do {
            ratings = try await AOTYAPI.shared.userRatings(username: user, page: 1, type: singles ? "single" : nil)
            ratingsPage = 1; moreRatings = true
        } catch {
            ratings = []
            self.error = error.localizedDescription
        }
    }

    private func loadMoreRatings(_ user: String) async {
        guard moreRatings, !loading else { return }
        if let next = try? await AOTYAPI.shared.userRatings(username: user, page: ratingsPage + 1, type: singles ? "single" : nil) {
            let fresh = next.filter { n in !ratings.contains { $0.id == n.id } }
            if fresh.isEmpty { moreRatings = false } else { ratings += fresh; ratingsPage += 1 }
        } else { moreRatings = false }
    }
}
