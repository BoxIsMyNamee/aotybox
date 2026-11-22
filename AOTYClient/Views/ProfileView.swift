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

    private var activeUsername: String? {
        if !overrideUsername.isEmpty { return overrideUsername }
        if let username, !username.isEmpty { return username }
        if !savedUsername.isEmpty { return savedUsername }
        return nil
    }

    var body: some View {
        AppStack {
            Group {
                if let u = activeUsername {
                    UserProfileView(username: u, fallbackAvatar: meAvatar, isMe: true,
                                    onChangeUser: { typedName = u; showChange = true },
                                    onAutoDetect: overrideUsername.isEmpty ? nil : { overrideUsername = ""; Task { await detect() } })
                        .id(u)
                } else if detecting {
                    ProgressView("Finding your profile…")
                } else {
                    signedOut
                }
            }
            .navigationTitle("Profile")
            .inlineNavTitle()
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .platformTopBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView().accentTint() }
            #else
            .toolbar {
                MacSearchToolbarItem()
            }
            #endif
            .sheet(isPresented: $showLogin, onDismiss: { Task { await detect() } }) {
                AOTYWebSheet(url: AOTYSession.home, title: "Sign in").accentTint()
            }
            .alert("Your AOTY username", isPresented: $showChange) {
                TextField("username", text: $typedName).noAutocap().autocorrectionDisabled()
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
            .task {
                if activeUsername == nil { await detect() }
                else { await detect(silent: true) }
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
            Button("Try again") { Task { await detect() } }
            Button("Enter username") { typedName = ""; showChange = true }
        }
    }

    private func detect(silent: Bool = false) async {
        if !overrideUsername.isEmpty { username = overrideUsername; savedUsername = overrideUsername; return }
        if !silent { detecting = true; error = nil }
        defer { if !silent { detecting = false } }
        do {
            let me = try await AOTYAPI.shared.me(refresh: true)
            if let u = me.username { username = u; meAvatar = me.avatar; savedUsername = u }
            else if !silent { username = nil; savedUsername = "" }
        } catch {
            if !silent {
                self.error = error.localizedDescription
                if !savedUsername.isEmpty { username = savedUsername }
            }
        }
    }
}

/// Persists the signed-in user's last profile snapshot so cold launches open straight to their real profile.
private struct ProfileSnapshot: Codable {
    let username: String
    let profile: Profile
    let ratings: [AlbumBlock]
    let friends: [FollowUser]

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("myProfileSnapshot.json")
    }

    static func load(for username: String) -> ProfileSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(ProfileSnapshot.self, from: data),
              snap.username.lowercased() == username.lowercased() else { return nil }
        return snap
    }

    static func save(_ snap: ProfileSnapshot) {
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: url, options: .atomic)
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
    @AppStorage(ProfileBackground.revKey) private var bgRev = 0
    @AppStorage(ProfileBackground.xKey) private var bgX = 0.5
    @AppStorage(ProfileBackground.yKey) private var bgY = 0.5
    @AppStorage(ProfileBackground.zoomKey) private var bgZoom = 1.0
    @AppStorage(LastFM.revKey) private var lastFMRev = 0
    @AppStorage(LastFM.liveEnabledKey) private var lastFMLiveEnabled = false
    var onChangeUser: (() -> Void)? = nil
    var onAutoDetect: (() -> Void)? = nil

    @AppStorage("profileUsername") private var myUsername = ""
    @Environment(\.push) private var push
    @Environment(\.openURL) private var openURL
    @State private var profile: Profile?
    @State private var ratings: [AlbumBlock] = []
    @State private var friends: [FollowUser] = []
    @State private var lastFMPlaying: LastFM.NowPlaying?
    @State private var loading = false
    @State private var error: String?
    @State private var showFullProfile = false
    @State private var showAvatar = false
    @State private var adjustingBg = false
    @State private var savedBgState: (Double, Double, Double)?
    @State private var bgBoxSize: CGSize = .zero
    @State private var bgDragStart: (Double, Double)?
    @State private var bgZoomStart: Double?

    init(username: String, fallbackAvatar: String? = nil, fallbackName: String? = nil, fallbackColor: String? = nil,
         isMe: Bool = false, onChangeUser: (() -> Void)? = nil, onAutoDetect: (() -> Void)? = nil) {
        self.username = username
        self.fallbackAvatar = fallbackAvatar
        self.fallbackName = fallbackName
        self.fallbackColor = fallbackColor
        self.isMe = isMe
        self.onChangeUser = onChangeUser
        self.onAutoDetect = onAutoDetect
        let savedMe = UserDefaults.standard.string(forKey: "profileUsername") ?? ""
        let isOwn = isMe || (!savedMe.isEmpty && username.lowercased() == savedMe.lowercased())
        if isOwn, let snap = ProfileSnapshot.load(for: username) {
            _profile = State(initialValue: snap.profile)
            _ratings = State(initialValue: snap.ratings)
            _friends = State(initialValue: snap.friends)
        }
    }

    private var ownProfile: Bool {
        isMe || (!myUsername.isEmpty && username.lowercased() == myUsername.lowercased())
    }

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
                    ForEach(reviews.prefix(5)) { r in
                        ProfileReviewRow(review: r, own: ownProfile)
                            .environment(\.shareAuthor, ShareAuthor(name: profile?.displayName ?? fallbackName ?? username,
                                                                    color: profile?.nameColor ?? fallbackColor,
                                                                    avatar: profile?.avatar.flatMap(URL.init(string:))))
                    }
                    Button { push(ProfileReviewsRoute(username: username)) } label: {
                        Label("View All Reviews", systemImage: "text.bubble").foregroundStyle(.tint)
                    }
                }
            }

            Section("Recently Rated") {
                if ratings.isEmpty && loading { ProgressView().frame(maxWidth: .infinity) }
                else if ratings.isEmpty { Text(error ?? "No ratings yet.").foregroundStyle(.secondary) }
                ForEach(ratings.prefix(3)) { a in RatingRow(album: a, isMe: ownProfile) }
                if !ratings.isEmpty {
                    Button { push(ProfileRatingsRoute(username: username, path: profile?.ratingsPath, isMe: ownProfile)) } label: {
                        Label("View All Ratings", systemImage: "list.number").foregroundStyle(.tint)
                    }
                }
            }

            if !friends.isEmpty {
                Section(ownProfile ? "Friends" : "Following") {
                    FriendsRow(friends: friends)
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                }
            }

            Section {
                Button { showFullProfile = true } label: { Label("Open full profile on AOTY", systemImage: "safari") }
            }
            }
        }
        .insetGroupedListStyle()
        .macPagePadding()
        .environment(\.swipeRowBackground, Color.platformSecondaryGroupedBackground)
        .compactListSectionSpacing()
        .contentMargins(.top, 4, for: .scrollContent)
        .refreshable { await refresh() }
        .toolbar {
            if isMe {
                ToolbarItem(placement: .platformTopBarLeading) {
                    Menu {
                        Button { showFullProfile = true } label: { Label("Open full profile", systemImage: "safari") }
                        Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        if let onChangeUser { Button(action: onChangeUser) { Label("Not you? Set username", systemImage: "person.crop.circle.badge.questionmark") } }
                        if let onAutoDetect { Button(action: onAutoDetect) { Label("Detect automatically", systemImage: "wand.and.stars") } }
                    } label: { Image(systemName: "ellipsis") }
                    .menuIndicator(.hidden)
                }
            }
        }
        .platformFullScreenCover(isPresented: $showAvatar) {
            if let s = profile?.avatar ?? fallbackAvatar, let u = URL(string: Self.largeAvatar(s)) {
                CoverViewer(url: u, title: profile?.displayName ?? username, fallback: URL(string: s)).accentTint()
            }
        }
        .sheet(isPresented: $showFullProfile) {
            if let url = URL(string: "https://www.albumoftheyear.org/user/\(username)/") {
                AOTYWebSheet(url: url, title: username).accentTint()
            }
        }
        .scrollDisabled(adjustingBg)
        .onReceive(NotificationCenter.default.publisher(for: .adjustProfileBackground)) { _ in
            guard ownProfile, ProfileBackground.load() != nil else { return }
            savedBgState = (bgX, bgY, bgZoom)
            adjustingBg = true
        }
        .safeAreaInset(edge: .bottom) {
            if adjustingBg { bgAdjustBar }
        }
        .task { await load(force: false) }
        .task(id: "\(profile?.links?.map(\.url).joined() ?? "")-\(lastFMRev)-\(lastFMLiveEnabled)") {
            guard lastFMLiveEnabled else {
                if lastFMPlaying != nil { lastFMPlaying = nil }
                return
            }
            guard let lfm = LastFM.username(from: profile?.links) else { return }
            // Check right away when an API key is added/changed or links arrive.
            await pollLastFM(user: lfm.user, url: lfm.url)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { break }
                await pollLastFM(user: lfm.user, url: lfm.url)
            }
        }
    }

    private var bgAdjustBar: some View {
        VStack(spacing: 8) {
            #if os(macOS)
            Text("Drag to move · Pinch or slide to zoom · Double-click to reset")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass").font(.caption).foregroundStyle(.secondary)
                Slider(value: $bgZoom, in: 0.6...3.0)
                    .frame(width: 180)
                Image(systemName: "plus.magnifyingglass").font(.caption).foregroundStyle(.secondary)
            }
            #else
            Text("Drag to move · Pinch to zoom · Double-tap to reset")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            #endif
            HStack(spacing: 12) {
                Button("Cancel") {
                    if let s = savedBgState { bgX = s.0; bgY = s.1; bgZoom = s.2 }
                    savedBgState = nil
                    adjustingBg = false
                }
                .buttonStyle(.glass)

                Button("Reset") {
                    withAnimation(.smooth) { bgX = 0.5; bgY = 0.5; bgZoom = 1 }
                }
                .buttonStyle(.glass)
                .disabled(bgX == 0.5 && bgY == 0.5 && bgZoom == 1)

                Button("Save") {
                    savedBgState = nil
                    adjustingBg = false
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func bgSlack(for image: PlatformImage, in box: CGSize) -> CGSize {
        guard box.width > 0, box.height > 0 else { return .zero }
        let iw = max(image.size.width, 1)
        let ih = max(image.size.height, 1)
        let fill = max(box.width / iw, box.height / ih)
        let scale = fill * CGFloat(max(bgZoom, 0.5))
        return CGSize(width: max(iw * scale - box.width, box.width * 0.6),
                      height: max(ih * scale - box.height, box.height * 0.6))
    }

    private func pollLastFM(user: String, url: URL) async {
        let res = await LastFM.fetchStatus(username: user, profileURL: url)
        guard !Task.isCancelled else { return }
        switch res {
        case let .playing(now):
            if let cover = now.cover {
                await ImageCache.shared.warm([cover], timeout: 0.4)
            }
            if !Task.isCancelled, lastFMPlaying != now {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { lastFMPlaying = now }
            }
        case .idle:
            if !Task.isCancelled, lastFMPlaying != nil {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { lastFMPlaying = nil }
            }
        case .failed:
            // Keep existing state on a transient network hiccup so the card never flickers away.
            break
        }
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
        let _ = bgRev
        let bg = ownProfile ? ProfileBackground.load() : nil
        Section {
            VStack(alignment: .leading, spacing: 14) {
                if bg != nil { Color.clear.frame(height: 120) }     // let the picture show above you
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
                            .shadow(color: .black.opacity(0.95), radius: 2, x: 0, y: 1)
                            .shadow(color: .black.opacity(0.85), radius: 6, x: 0, y: 2)
                        if let handle = parts.handle {
                            Text(handle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.95), radius: 2, x: 0, y: 1)
                                .shadow(color: .black.opacity(0.75), radius: 4, x: 0, y: 2)
                        }
                    }
                }
                if let stats = profile?.stats, !stats.isEmpty {
                    statsBar(stats)
                }
                if let about = profile?.about, !about.isEmpty {
                    VStack(alignment: .center, spacing: 6) {
                        Text("ABOUT")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(linkified(about))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
                if let links = profile?.links, !links.isEmpty {
                    aroundTheWeb(links)
                }
            }
            .overlay {
                if adjustingBg, let bg {
                    PanPinchOverlay(
                        onPan: { translation, box in
                            if bgDragStart == nil { bgDragStart = (bgX, bgY) }
                            guard let start = bgDragStart else { return }
                            let slack = bgSlack(for: bg, in: box)
                            if slack.width > 1 {
                                bgX = min(max(start.0 - Double(translation.width / slack.width), -0.4), 1.4)
                            }
                            if slack.height > 1 {
                                bgY = min(max(start.1 - Double(translation.height / slack.height), -0.4), 1.4)
                            }
                        },
                        onPanEnd: { bgDragStart = nil },
                        onPinch: { scale in
                            if bgZoomStart == nil { bgZoomStart = bgZoom }
                            guard let start = bgZoomStart else { return }
                            bgZoom = min(max(start * Double(scale), 0.6), 4)
                        },
                        onPinchEnd: { bgZoomStart = nil },
                        onDoubleTap: {
                            withAnimation(.smooth) { bgX = 0.5; bgY = 0.5; bgZoom = 1 }
                        }
                    )
                }
            }
            .listRowBackground(
                Group {
                    if let bg {
                        ProfileBackgroundLayer(image: bg)
                    } else { Color.clear }
                }
            )
            .listRowInsets(EdgeInsets(top: bg == nil ? 0 : 12, leading: bg == nil ? 4 : 16, bottom: 8, trailing: bg == nil ? 4 : 16))
            .listRowSeparator(.hidden)

        }
    }

    private func statsBar(_ stats: [ProfileStat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { idx, s in
                if idx > 0 {
                    Divider().frame(height: 32)
                }
                statCell(s)
            }
        }
        .padding(.vertical, 10)
        #if os(macOS)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.45)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        }
        #else
        .background(Color.platformSecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
        #endif
    }

    @ViewBuilder private func statCell(_ s: ProfileStat) -> some View {
        let cell = VStack(spacing: 3) {
            Text(s.value)
                .font(.system(.headline, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(s.label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())

        switch s.label.lowercased() {
        case "ratings":
            Button { push(ProfileRatingsRoute(username: username, path: profile?.ratingsPath, isMe: ownProfile)) } label: { cell }
                .buttonStyle(.plain)
        case "reviews":
            Button { push(ProfileReviewsRoute(username: username)) } label: { cell }
                .buttonStyle(.plain)
        default:
            cell
        }
    }

    private func aroundTheWeb(_ links: [ProfileLink]) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text("AROUND THE WEB")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            ChipLayout(spacing: 8, centered: true) {
                ForEach(links) { link in
                    if let url = link.destination {
                        Button {
                            openURL(url)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: Self.linkIcon(link))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(link.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.tint)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            #if os(macOS)
                            .background {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Capsule().fill(Color.black.opacity(0.45)))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                            }
                            #else
                            .background(Color.platformSecondaryGroupedBackground, in: Capsule())
                            #endif
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { openURL(url) } label: { Label("Open in Browser", systemImage: "safari") }
                            Button { PlatformPasteboard.copy(url.absoluteString) } label: { Label("Copy Link", systemImage: "doc.on.doc") }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            if let now = lastFMPlaying {
                lastFMNowPlayingRow(now)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func lastFMNowPlayingRow(_ now: LastFM.NowPlaying) -> some View {
        Button {
            push(SongRoute(artist: now.artist, title: now.title, album: now.album, cover: now.cover))
        } label: {
            HStack(spacing: 14) {
                #if os(macOS)
                Cover(url: now.cover, size: 60)
                #else
                Cover(url: now.cover, size: 42)
                #endif
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        EqualizerBars(playing: true)
                        Text("Listening on Last.fm")
                    }
                    #if os(macOS)
                    .font(.caption.weight(.semibold))
                    #else
                    .font(.caption2.weight(.semibold))
                    #endif
                    .foregroundStyle(.tint)
                    Text(now.title)
                        #if os(macOS)
                        .font(.title3.weight(.semibold))
                        #else
                        .font(.subheadline.weight(.semibold))
                        #endif
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(now.artist)
                        #if os(macOS)
                        .font(.subheadline)
                        #else
                        .font(.caption)
                        #endif
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            #if os(macOS)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(maxWidth: 460)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.45)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14), lineWidth: 1))
            }
            #else
            .padding(10)
            .background(Color.platformSecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
            #endif
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
        #endif
        .contextMenu {
            Button {
                push(SongRoute(artist: now.artist, title: now.title, album: now.album, cover: now.cover))
            } label: {
                Label("Open in Learn", systemImage: "text.book.closed")
            }
            Button {
                Task {
                    let q = (now.album ?? now.title).replacingOccurrences(of: #"\s+-\s+(Single|EP)$"#, with: "", options: .regularExpression)
                    if let slug = await AOTYAPI.shared.findAlbumSlug(artist: now.artist, title: q) {
                        push(AlbumRoute(slug: slug, title: q))
                    }
                }
            } label: {
                Label("Find Release on AOTY", systemImage: "square.stack")
            }
            Button {
                openURL(now.profileURL)
            } label: {
                Label("Open Last.fm Profile", systemImage: "safari")
            }
        }
    }

    static func linkIcon(_ link: ProfileLink) -> String {
        let icon = (link.icon ?? "").lowercased()
        if icon.contains("fa-link") { return "link" }
        let s = (icon + " " + link.name + " " + link.url).lowercased()
        if s.contains("last.fm") || s.contains("lastfm") { return "waveform" }
        if s.contains("spotify") || s.contains("apple") || s.contains("bandcamp") || s.contains("soundcloud") { return "music.note" }
        if s.contains("youtube") || s.contains("youtu.be") { return "play.rectangle" }
        if s.contains("instagram") { return "camera" }
        if s.contains("twitter") || s.contains("x.com") || s.contains("bsky") || s.contains("bluesky") || s.contains("mastodon") || s.contains("threads") { return "at" }
        if s.contains("discord") { return "bubble.left.and.bubble.right" }
        if s.contains("letterboxd") || s.contains("imdb") { return "film" }
        return "link"
    }

    // MARK: Loading

    private func excludeSelf(_ list: [FollowUser]) -> [FollowUser] {
        // Only the profile's owner is left out of their own friends list; on someone else's
        // profile you still show up if you're one of their friends.
        list.filter { $0.username.lowercased() != username.lowercased() }
    }

    /// Pull-to-refresh: runs in an unstructured task so SwiftUI's refreshable gesture cancellation
    /// never strands the UIKit spinner or leaves `loading` stuck.
    private func refresh() async {
        await Task { @MainActor in
            await AOTYScraper.shared.forget("/user/\(username)/")
            AOTYScraper.shared.bypassCache()
            await load(force: true)
        }.value
    }

    private func load(force: Bool) async {
        let hadProfile = profile != nil
        if !hadProfile { loading = true }
        error = nil
        defer { loading = false }
        if force { await AOTYScraper.shared.forget("/user/\(username)/") }
        do {
            let p = try await AOTYAPI.shared.profile(username: username)
            async let lfmTask: LastFM.FetchResult = {
                guard LastFM.isLiveEnabled, let lfm = LastFM.username(from: p.links) else { return .idle }
                return await LastFM.fetchStatus(username: lfm.user, profileURL: lfm.url)
            }()
            await ImageCache.shared.warm([p.avatar.flatMap(URL.init(string:))]
                + (p.reviews ?? []).prefix(5).map(\.coverURL)
                + (p.recent ?? []).prefix(3).map(\.coverURL)
                + (p.following ?? []).prefix(8).map { $0.avatar.flatMap(URL.init(string:)) },
                timeout: hadProfile ? 0.35 : 0.6)
            // Gather everything first, then show it all at once (no sections popping in).
            var newRatings = p.recent ?? []          // AOTY's own mixed order
            if newRatings.isEmpty { newRatings = (try? await AOTYAPI.shared.userRatings(username: username, page: 1)) ?? [] }
            var newFriends = excludeSelf(p.following ?? [])
            if newFriends.isEmpty { newFriends = excludeSelf((try? await AOTYAPI.shared.following(username: username)) ?? []) }
            let lfmRes = await lfmTask
            if case let .playing(np) = lfmRes, let cover = np.cover {
                await ImageCache.shared.warm([cover], timeout: 0.35)
            }
            if ownProfile {
                ProfileSnapshot.save(ProfileSnapshot(username: username, profile: p, ratings: newRatings, friends: newFriends))
            }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                profile = p
                ratings = newRatings
                friends = newFriends
                switch lfmRes {
                case let .playing(np): lastFMPlaying = np
                case .idle: lastFMPlaying = nil
                case .failed: break
                }
            }
        } catch is CancellationError {
        } catch {
            if !hadProfile { self.error = error.localizedDescription }
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
        .macPagePadding()
        .navigationTitle("Ratings")
        .inlineNavTitle()
        #if os(macOS)
        .toolbar { MacSearchToolbarItem() }
        #endif
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
    @Environment(\.shareAuthor) private var author

    var own = false
    private var shareData: ShareCardData? {
        guard let author, !review.text.isEmpty else { return nil }
        return ShareCardData(title: review.album, artist: review.artist, cover: review.coverURL, score: review.rating,
                             text: fullText ?? review.text, author: author.name, authorColor: author.color, avatar: author.avatar,
                             fullURL: (fullText == nil && review.isTruncated == true) ? review.url : nil,
                             pageURL: review.url.flatMap { URL(string: $0, relativeTo: URL(string: "https://www.albumoftheyear.org"))?.absoluteURL })
    }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                #if os(macOS)
                Cover(url: review.coverURL, size: 96)
                #else
                Cover(url: review.coverURL, size: 76)
                #endif
                VStack(alignment: .leading, spacing: 4) {
                    Button { push(ArtistRoute(path: "", name: review.artist)) } label: {
                        Text(review.artist)
                            #if os(macOS)
                            .font(.headline.weight(.medium))
                            #else
                            .font(.subheadline)
                            #endif
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    Text(review.album)
                        #if os(macOS)
                        .font(.title3.bold())
                        #else
                        .font(.headline)
                        #endif
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let d = review.date {
                        Text(d)
                            #if os(macOS)
                            .font(.subheadline)
                            #else
                            .font(.caption)
                            #endif
                            .foregroundStyle(.tertiary)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                if let r = review.rating { MiniScore(label: "", score: r, large: true) }
            }

            if !review.text.isEmpty {
                let hasMore = review.text.count > 280 || review.isTruncated == true
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(linkified(bodyText))
                        #if os(macOS)
                        .font(.system(size: 16))
                        .lineSpacing(4)
                        #else
                        .font(.callout)
                        #endif
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
                #if os(macOS)
                .font(.subheadline.weight(.semibold))
                #else
                .font(.caption.weight(.semibold))
                #endif
                .buttonStyle(.borderless) }
            }
        }
        #if os(macOS)
        .padding(.vertical, 10)
        #else
        .padding(.vertical, 4)
        #endif
        // The whole review (art, title, text) opens the album; double-clicking likes the review.
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard !own, let id = review.reviewId ?? Int(review.id) else { return }
            let store = LikeStore.shared
            let isLiked = store.liked(id, default: review.liked ?? false)
            let count = store.count(id, default: review.likes ?? 0)
            Task { _ = await store.toggle(id: id, liked: isLiked, count: count) }
        }
        .onTapGesture { if let s = review.slug { push(AlbumRoute(slug: s, title: review.album)) } }
        .reviewShareMenu(shareData)
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
    @State private var author: ShareAuthor?
    @State private var sort: ReviewSort = .newest
    @State private var loadingAll = false
    @State private var page = 1
    @State private var more = true
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            if let error, reviews.isEmpty { ErrorView(message: error) { await reload() } }
            else if reviews.isEmpty && !loading { ContentUnavailableView("No reviews yet", systemImage: "text.bubble") }
            if loadingAll {
                Label("Loading all reviews to sort…", systemImage: "arrow.up.arrow.down")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(shown) { r in
                ProfileReviewRow(review: r, own: username.lowercased() == myUsername.lowercased())
                    .environment(\.shareAuthor, author ?? ShareAuthor(name: username))
                    .onAppear { if sort == .newest && r == reviews.last { Task { await loadMore() } } }
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
        }
        .insetGroupedListStyle()
        .macPagePadding()
        .environment(\.swipeRowBackground, Color.platformSecondaryGroupedBackground)
        .task {
            if author == nil, let p = try? await AOTYAPI.shared.profile(username: username) {
                author = ShareAuthor(name: p.displayName ?? username, color: p.nameColor, avatar: p.avatar.flatMap(URL.init(string:)))
            }
        }
        .navigationTitle("Reviews")
        .inlineNavTitle()
        .toolbar {
            ToolbarItem(placement: .platformTopBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(ReviewSort.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
            }
            #if os(macOS)
            ToolbarSpacer(.fixed)
            MacSearchToolbarItem()
            #endif
        }
        // AOTY's reviews pages don't sort, so the app loads them all and sorts here.
        .onChange(of: sort) { if sort != .newest { Task { await loadAll() } } }
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

    enum ReviewSort: String, CaseIterable, Identifiable {
        case newest = "Newest", highest = "Highest", lowest = "Lowest", liked = "Most Liked"
        var id: String { rawValue }
        var icon: String {
            switch self { case .newest: "clock"; case .highest: "arrow.up"; case .lowest: "arrow.down"; case .liked: "heart" }
        }
    }

    private var shown: [ProfileReview] {
        switch sort {
        case .newest: return reviews
        case .highest: return reviews.sorted { ($0.rating ?? -1) > ($1.rating ?? -1) }
        case .lowest: return reviews.sorted { ($0.rating ?? 101) < ($1.rating ?? 101) }
        case .liked: return reviews.sorted { ($0.likes ?? 0) > ($1.likes ?? 0) }
        }
    }

    private func loadAll() async {
        guard more, !loadingAll else { return }
        loadingAll = true; defer { loadingAll = false }
        var guardPages = 0
        while more && guardPages < 60 {
            guardPages += 1
            while loading { try? await Task.sleep(for: .milliseconds(150)) }
            await loadMore()
        }
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
