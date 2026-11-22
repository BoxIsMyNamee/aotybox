import SwiftUI

@main
struct AOTYClientApp: App {
    @StateObject private var scraper = AOTYScraper.shared
    @AppStorage(Theme.key) private var accentHex = Theme.defaultHex
    @AppStorage(Appearance.key) private var appearance = Appearance.dark.rawValue
    @State private var musicLinkFailed = false
    @State private var tab = UserDefaults.standard.integer(forKey: "initialTab")

    @State private var showSplash = true
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var showWelcome = false
    #if os(macOS)
    @StateObject private var macSearch = MacSearch.shared
    #endif

    var body: some Scene {
        WindowGroup {
            ZStack {
            #if os(macOS)
            TabView(selection: Binding(get: { tab == 2 ? 0 : tab }, set: { new in
                tab = new
                macSearch.clear()
            })) {
                ReleasesView().tabItem { Label("Releases", systemImage: "square.stack") }.tag(0)
                ChartsView().tabItem { Label("Charts", systemImage: "chart.bar") }.tag(1)
                ProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(3)
                ProofView().tabItem { Label("Notes", systemImage: "text.badge.checkmark") }.tag(4)
            }
            if macSearch.active {
                MacSearchOverlay(
                    query: $macSearch.query,
                    submitted: $macSearch.submitted,
                    forceOpen: $macSearch.forceOpen
                ) {
                    macSearch.clear()
                }
                .zIndex(1)
            }
            #else
            TabView(selection: Binding(get: { tab }, set: { new in
                if new == tab && new == 2 { NotificationCenter.default.post(name: .resetSearch, object: nil) }
                tab = new
            })) {
                ReleasesView().tabItem { Label("Releases", systemImage: "square.stack") }.tag(0)
                ChartsView().tabItem { Label("Charts", systemImage: "chart.bar") }.tag(1)
                SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(2)
                ProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(3)
                ProofView().tabItem { Label("Notes", systemImage: "text.badge.checkmark") }.tag(4)
            }
            #endif
            LikeNoticeToast().zIndex(3)
            if showSplash {
                LaunchSplash { showSplash = false }
                    .zIndex(2)
            }
            }
            .tint(Color(hex: accentHex))
            .preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
            .onAppear { Appearance.apply(appearance) }
            .onChange(of: appearance) { Appearance.apply(appearance) }
            .background(HiddenScraperHost().frame(width: 2, height: 2).allowsHitTesting(false))
            .sheet(item: $scraper.challenge) { ChallengeSheet(url: $0.url).accentTint() }
            .background {
                // First run: one sign-in sheet (which also gets you past Cloudflare) instead of
                // Cloudflare check sheets popping up for every screen.
                Color.clear
                    .sheet(isPresented: $showWelcome) {
                        WelcomeSignInSheet {
                            didOnboard = true
                            showWelcome = false
                            scraper.suppressChallenges = false
                            scraper.challengeFinished()      // also un-pauses and reloads
                        }
                        .accentTint()
                    }
            }
            .task {
                guard !didOnboard else { return }
                // Hold all of the app's own requests until you're signed in (or skip), so only this
                // sheet talks to AOTY while Cloudflare checks you.
                scraper.suppressChallenges = true
                scraper.paused = true
                try? await Task.sleep(for: .seconds(1.2))   // let the launch animation finish
                showWelcome = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .musicAppOpenFailed)) { _ in musicLinkFailed = true }
            .onReceive(NotificationCenter.default.publisher(for: .openNotes)) { _ in tab = 4 }
            .onReceive(NotificationCenter.default.publisher(for: ListenRequest.note)) { _ in tab = 0 }
            .onReceive(NotificationCenter.default.publisher(for: .adjustProfileBackground)) { _ in
                tab = 3
                #if os(macOS)
                NSApp.windows.first(where: { $0.canBecomeMain && $0.title != "Settings" })?.makeKeyAndOrderFront(nil)
                #endif
            }
            .onOpenURL { url in
                // aotybox://listen  → the Lock Screen widget: Releases, then listen.
                if url.scheme == "aotybox", url.host == "listen" {
                    tab = 0
                    ListenRequest.post()
                    return
                }
                // aotybox://open?b64=<music link>  → find that album on AOTY (from the share sheet).
                if url.scheme == "aotybox", url.host == "open" {
                    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    let raw = items.first(where: { $0.name == "b64" })?.value
                        .flatMap { Data(base64Encoded: $0.replacingOccurrences(of: " ", with: "+")) }
                        .flatMap { String(data: $0, encoding: .utf8) } ?? items.first(where: { $0.name == "url" })?.value
                    if let raw, let link = URL(string: raw) {
                        #if os(macOS)
                        macSearch.forceOpen = true
                        #else
                        tab = 2
                        #endif
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NotificationCenter.default.post(name: .openMusicLink, object: link)
                        }
                    }
                    return
                }
                // aotybox://notes?text=…  → put shared text (e.g. a Google Keep note) into Notes.
                if url.scheme == "aotybox", url.host == "notes" {
                    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    var text = items.first(where: { $0.name == "text" })?.value ?? ""
                    // Shortcuts can also send it base64-encoded (safer for long notes with symbols).
                    if let b = items.first(where: { $0.name == "b64" })?.value,
                       let d = Data(base64Encoded: b.replacingOccurrences(of: " ", with: "+")),
                       let s = String(data: d, encoding: .utf8) { text = s }
                    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { tab = 4; return }
                    UserDefaults.standard.set(text, forKey: "notesText")
                    tab = 4
                    NotificationCenter.default.post(name: .notesImported, object: nil)
                    return
                }
                // aotybox://learn?artist=…&title=…[&album=…]  → the song's Learn page on Search
                guard url.scheme == "aotybox", url.host == "learn",
                      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                      let title = items.first(where: { $0.name == "title" })?.value, !title.isEmpty else { return }
                let artist = items.first(where: { $0.name == "artist" })?.value ?? ""
                let album = items.first(where: { $0.name == "album" })?.value
                #if os(macOS)
                macSearch.forceOpen = true
                #else
                tab = 2
                #endif
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .openLearn, object: SongRoute(artist: artist, title: title, album: album, cover: nil))
                }
            }
            .alert("Couldn't open \(MusicAppLink.name)", isPresented: $musicLinkFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Make sure \(MusicAppLink.name) is installed, or pick another app in Settings → Music App.")
            }
            #if os(macOS)
            .frame(minWidth: 780, minHeight: 560)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1160, height: 780)
        #endif
        #if os(macOS)
        Settings {
            SettingsView(isWindow: true)
                .tint(Color(hex: accentHex))
                .preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
        }
        #endif
    }
}

#if os(macOS)
@MainActor
final class MacSearch: ObservableObject {
    static let shared = MacSearch()
    @Published var query = ""
    @Published var submitted = ""
    @Published var forceOpen = false

    var active: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || !submitted.isEmpty || forceOpen
    }

    func submit() {
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { submitted = q }
    }

    func clear() {
        query = ""
        submitted = ""
        forceOpen = false
    }
}

/// Reusable trailing search pill placed AFTER tab-specific toolbar buttons so buttons always sit to its left.
struct MacSearchToolbarItem: ToolbarContent {
    @ObservedObject private var search = MacSearch.shared

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            MacToolbarSearchField(
                text: $search.query,
                onSubmit: { search.submit() },
                onClear: { search.clear() }
            )
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

/// Fixed-width glass search pill for the macOS toolbar so its length never shifts across tabs
/// and adjacent toolbar buttons stay in their own separate pills.
private struct MacToolbarSearchField: View {
    @Binding var text: String
    var onSubmit: () -> Void
    var onClear: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Albums, artists, songs", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit(onSubmit)
                .onExitCommand {
                    if !text.isEmpty { onClear() }
                    focused = false
                }
            if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 430, height: 30)
        .glassEffect(.regular, in: Capsule())
    }
}
#endif

struct SettingsView: View {
    var isWindow = false
    @State private var showLogin = false
    @State private var cacheBytes: Int64?
    @AppStorage(Appearance.key) private var appearance = Appearance.dark.rawValue
    @AppStorage("notesAlbumCheck") private var albumCheckOn = false
    @AppStorage("colorBlindScores") private var colorBlind = false
    @AppStorage(LastFM.revKey) private var lastFMRev = 0
    @State private var clearing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = lastFMRev
        NavigationStack {
            Form {
                #if os(macOS)
                MacUpdateSettingsSection()
                #endif

                Section("Accent Color") {
                    AccentColorPicker()
                }

                Section {
                    Picker("Theme", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.name).tag($0.rawValue) }
                    }
                    Toggle("Color-blind friendly scores", isOn: $colorBlind)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Black is pure black (best on OLED). Dim uses softer dark grays. Color-blind friendly scores use blue, orange and purple instead of green, yellow and red.")
                }

                SwipeSettingsSection()

                ProfileBackgroundSettings()

                Section {
                    Toggle("Album track-name check", isOn: $albumCheckOn)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Shows an Album field in Notes that checks every track name you mention is in quotes.")
                }

                Section {
                    Button("Sign in / open my AOTY account") { showLogin = true }
                    Button("Sign out on this device", role: .destructive) {
                        Task { await AOTYSession.signOut() }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("You sign in on AOTY's own website, inside the app. Your login stays on this device and is never sent to the community API.")
                }

                Section("Music App") {
                    NavigationLink { MusicAppSettingsView() } label: {
                        LabeledContent("Long-press opens", value: MusicAppLink.name)
                    }
                    NavigationLink { LastFMSettingsView() } label: {
                        LabeledContent("Last.fm API key", value: LastFM.apiKey != nil ? "Added" : "Optional")
                    }
                }

                Section("AI Assistant") {
                    NavigationLink { AISettingsView() } label: {
                        LabeledContent("Provider", value: AISettings.isConfigured ? AISettings.provider.name : "Not set up")
                    }
                }

                Section {
                    LabeledContent("Cache size") {
                        if let cacheBytes { Text(ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file)) }
                        else { ProgressView().controlSize(.small) }
                    }
                    Button {
                        Task {
                            clearing = true
                            await AOTYAPI.shared.clearCache()
                            cacheBytes = await CacheSize.total()
                            clearing = false
                        }
                    } label: {
                        HStack { Text("Clear cache"); if clearing { Spacer(); ProgressView().controlSize(.small) } }
                    }
                    .disabled(clearing)
                    NavigationLink("Backup & Restore") { BackupSettingsView() }
                    NavigationLink("Diagnostics") { DiagnosticsView() }
                } footer: {
                    Text("Album art, pages and lyrics saved on this phone so things load fast. Safe to clear; they'll download again.")
                }

                Section("About") {
                    Text("Unofficial client. Album data © Album of the Year and its contributing publications. Page parsing adapted from the community AOTY API (github.com/edideaur/AOTY-api). Not affiliated with Album of the Year.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .task { cacheBytes = await CacheSize.total() }
            .toolbar {
                if !isWindow {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
            .sheet(isPresented: $showLogin) {
                AOTYWebSheet(url: AOTYSession.home, title: "AOTY").accentTint()
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 520, idealHeight: 640)
        #endif
    }
}

/// Everything in the app's Caches folder (image cache, page cache, web data caches).
enum CacheSize {
    static func total() async -> Int64 {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return 0 }
            #if os(macOS)
            var dirs = [base.appendingPathComponent("aoty-v2", isDirectory: true)]
            if let bid = Bundle.main.bundleIdentifier {
                dirs.append(base.appendingPathComponent(bid, isDirectory: true))
            }
            #else
            let dirs = [base]
            #endif
            var sum: Int64 = 0
            for dir in dirs {
                guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { continue }
                for case let url as URL in e {
                    guard let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]), v.isRegularFile == true else { continue }
                    sum += Int64(v.totalFileAllocatedSize ?? 0)
                }
            }
            return sum
        }.value
    }
}

/// Dark-mode levels. Black = iOS dark (pure black). Dim lifts every background a step
/// by using iOS's "elevated" interface level (the softer grays sheets use).
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark, dim
    static let key = "appearance"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .system:
            #if os(iOS)
            "Match iPhone"
            #else
            "Match Mac"
            #endif
        case .light: "Light"
        case .dark: "Black"
        case .dim: "Dim"
        }
    }
    var scheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; default: .dark }
    }

    @MainActor static func apply(_ raw: String) {
        let a = Appearance(rawValue: raw) ?? .dark
        #if os(iOS)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.traitOverrides.userInterfaceLevel = a == .dim ? .elevated : .base
            }
        }
        #else
        switch a {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark, .dim: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
        #endif
    }
}

extension Notification.Name {
    /// The first Releases list finished loading (lifts the launch screen).
    static let releasesReady = Notification.Name("releasesReady")
    /// Open a song's Learn page (from an aotybox:// link).
    static let openLearn = Notification.Name("openLearn")
    static let notesImported = Notification.Name("notesImported")
    static let openNotes = Notification.Name("openNotes")
    static let aotyReady = Notification.Name("aotyReady")
    static let openMusicLink = Notification.Name("openMusicLink")
    /// Tapping the Search tab while on it: back to a fresh search.
    static let resetSearch = Notification.Name("resetSearch")
}


/// Launch screen: a little stack of cards in your accent color flies in (like the stacked-albums icon),
/// the AOTY wordmark pops in under it, then it all drops away to reveal the app. Never stays longer than ~4 seconds.
struct LaunchSplash: View {
    let done: () -> Void
    @State private var dealt = 0            // how many cards have landed
    @State private var logoIn = false
    @State private var leaving = false
    @State private var fade = 1.0
    private let shownAt = Date()
    @AppStorage(Theme.key) private var accentHex = Theme.defaultHex

    var body: some View {
        ZStack {
            Color.platformBackground.ignoresSafeArea()
            VStack(spacing: 34) {
                ZStack {
                    ForEach((0..<3).reversed(), id: \.self) { i in card(i) }
                }
                .frame(width: 240, height: 170)
                AOTYLogo()
                    .frame(height: 40)
                    .scaleEffect(logoIn ? 1 : 0.4)
                    .opacity(logoIn ? 1 : 0)
            }
            .scaleEffect(leaving ? 0.35 : 1)
            .opacity(leaving ? 0 : 1)
            .blur(radius: leaving ? 6 : 0)
        }
        .opacity(fade)
        .allowsHitTesting(!leaving)
        .task { await intro() }
        .onReceive(NotificationCenter.default.publisher(for: .releasesReady)) { _ in leave() }
        .task { try? await Task.sleep(for: .seconds(4)); leave() }
    }

    /// Back cards fan out a little; the front card sits straight.
    private func card(_ i: Int) -> some View {
        let landed = dealt > (2 - i)
        let tilt: [Double] = [0, -7, 7]
        let shift: [CGFloat] = [0, -16, 16]
        // Your accent color (Settings → Accent Color), a shade darker for each card further back.
        let accent = Color(hex: accentHex)
        return ZStack {
            LinearGradient(colors: [accent, accent.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Color.black.opacity(Double(i) * 0.22)
        }
        .frame(width: 130, height: 130)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        .scaleEffect(1 - CGFloat(i) * 0.06)
        .rotationEffect(.degrees(landed ? tilt[i] : 0))
        .offset(x: landed ? shift[i] : 0, y: landed ? -CGFloat(i) * 8 : 520)
        .opacity(landed ? 1 : 0)
    }

    private func intro() async {
        for n in 1...3 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { dealt = n }
            try? await Task.sleep(for: .milliseconds(110))
        }
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.spring(response: 0.42, dampingFraction: 0.55).delay(0.1)) { logoIn = true }
    }

    private func leave() {
        guard !leaving else { return }
        let wait = max(0, 1.1 - Date().timeIntervalSince(shownAt))   // let the intro play
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            guard !leaving else { return }
            withAnimation(.easeIn(duration: 0.25)) { leaving = true }
            withAnimation(.easeOut(duration: 0.3).delay(0.18)) { fade = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) { done() }
        }
    }
}
