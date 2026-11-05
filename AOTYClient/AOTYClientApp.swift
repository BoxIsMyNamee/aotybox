import SwiftUI

@main
struct AOTYClientApp: App {
    @StateObject private var scraper = AOTYScraper.shared
    @AppStorage(Theme.key) private var accentHex = Theme.defaultHex
    @State private var musicLinkFailed = false

    var body: some Scene {
        WindowGroup {
            TabView {
                ReleasesView().tabItem { Label("Releases", systemImage: "square.stack") }
                ChartsView().tabItem { Label("Charts", systemImage: "chart.bar") }
                SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
                ProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle") }
                ProofView().tabItem { Label("Proof", systemImage: "text.badge.checkmark") }
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
                    Button("Clear cache") { Task { await AOTYAPI.shared.clearCache() } }
                    NavigationLink("Diagnostics") { DiagnosticsView() }
                }

                Section("About") {
                    Text("Unofficial client. Album data © Album of the Year and its contributing publications. Page parsing adapted from the community AOTY API (github.com/edideaur/AOTY-api). Not affiliated with Album of the Year.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showLogin) {
                AOTYWebSheet(url: AOTYSession.home, title: "AOTY").accentTint()
            }
        }
    }
}
