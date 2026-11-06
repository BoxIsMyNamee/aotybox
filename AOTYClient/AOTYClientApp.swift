import SwiftUI

@main
struct AOTYClientApp: App {
    @StateObject private var scraper = AOTYScraper.shared
    @AppStorage(Theme.key) private var accentHex = Theme.defaultHex
    @State private var musicLinkFailed = false
    @State private var tab = UserDefaults.standard.integer(forKey: "initialTab")

    init() {
        // Proof keeps nothing between launches; clear what older builds saved.
        UserDefaults.standard.removeObject(forKey: "proofDraft")
        UserDefaults.standard.removeObject(forKey: "proofAlbum")
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                ReleasesView().tabItem { Label("Releases", systemImage: "square.stack") }.tag(0)
                ChartsView().tabItem { Label("Charts", systemImage: "chart.bar") }.tag(1)
                SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(2)
                ProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(3)
                ProofView().tabItem { Label("Proof", systemImage: "text.badge.checkmark") }.tag(4)
            }
            .tint(Color(hex: accentHex))
            .background(HiddenScraperHost().frame(width: 2, height: 2).allowsHitTesting(false))
            .sheet(item: $scraper.challenge) { ChallengeSheet(url: $0.url).accentTint() }
            .onReceive(NotificationCenter.default.publisher(for: .musicAppOpenFailed)) { _ in musicLinkFailed = true }
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
    @State private var clearing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Accent Color") {
                    AccentColorPicker()
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
