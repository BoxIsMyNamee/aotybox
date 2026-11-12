import SwiftUI

@main
struct AOTYClientApp: App {
    @StateObject private var scraper = AOTYScraper.shared
    @AppStorage(Theme.key) private var accentHex = Theme.defaultHex
    @AppStorage(Appearance.key) private var appearance = Appearance.dark.rawValue
    @State private var musicLinkFailed = false
    @State private var tab = UserDefaults.standard.integer(forKey: "initialTab")

    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
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
            LikeNoticeToast().zIndex(2)
            if showSplash {
                LaunchSplash { showSplash = false }
                    .zIndex(1)
            }
            }
            .tint(Color(hex: accentHex))
            .preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
            .onAppear { Appearance.apply(appearance) }
            .onChange(of: appearance) { Appearance.apply(appearance) }
            .background(HiddenScraperHost().frame(width: 2, height: 2).allowsHitTesting(false))
            .sheet(item: $scraper.challenge) { ChallengeSheet(url: $0.url).accentTint() }
            .onReceive(NotificationCenter.default.publisher(for: .musicAppOpenFailed)) { _ in musicLinkFailed = true }
            .onOpenURL { url in
                // aotybox://learn?artist=…&title=…[&album=…]  → the song's Learn page on Search
                guard url.scheme == "aotybox", url.host == "learn",
                      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                      let title = items.first(where: { $0.name == "title" })?.value, !title.isEmpty else { return }
                let artist = items.first(where: { $0.name == "artist" })?.value ?? ""
                let album = items.first(where: { $0.name == "album" })?.value
                tab = 2
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .openLearn, object: SongRoute(artist: artist, title: title, album: album, cover: nil))
                }
            }
            .alert("Couldn't open \(MusicAppLink.name)", isPresented: $musicLinkFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Make sure \(MusicAppLink.name) is installed, or pick another app in Settings → Music App.")
            }
        }
    }
}

struct SettingsView: View {
    @State private var showLogin = false
    @State private var cacheBytes: Int64?
    @AppStorage(Appearance.key) private var appearance = Appearance.dark.rawValue
    @AppStorage("notesAlbumCheck") private var albumCheckOn = false
    @State private var clearing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Accent Color") {
                    AccentColorPicker()
                }

                Section {
                    Picker("Theme", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.name).tag($0.rawValue) }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Black is pure black (best on OLED). Dim uses softer dark grays.")
                }

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
                    NavigationLink("Diagnostics") { DiagnosticsView() }
                } footer: {
                    Text("Album art, pages and lyrics saved on this phone so things load fast. Safe to clear; they'll download again.")
                }

                Section("About") {
                    Text("Unofficial client. Album data © Album of the Year and its contributing publications. Page parsing adapted from the community AOTY API (github.com/edideaur/AOTY-api). Not affiliated with Album of the Year.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task { cacheBytes = await CacheSize.total() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showLogin) {
                AOTYWebSheet(url: AOTYSession.home, title: "AOTY").accentTint()
            }
        }
    }
}

/// Everything in the app's Caches folder (image cache, page cache, web data caches).
enum CacheSize {
    static func total() async -> Int64 {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
                  let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
            var sum: Int64 = 0
            for case let url as URL in e {
                guard let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]), v.isRegularFile == true else { continue }
                sum += Int64(v.totalFileAllocatedSize ?? 0)
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
        case .system: "Match iPhone"
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
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.traitOverrides.userInterfaceLevel = a == .dim ? .elevated : .base
            }
        }
    }
}

extension Notification.Name {
    /// The first Releases list finished loading (lifts the launch screen).
    static let releasesReady = Notification.Name("releasesReady")
    /// Open a song's Learn page (from an aotybox:// link).
    static let openLearn = Notification.Name("openLearn")
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
            Color(.systemBackground).ignoresSafeArea()
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
