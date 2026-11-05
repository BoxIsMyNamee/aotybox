import SwiftUI

@main
struct AOTYClientApp: App {
    @StateObject private var scraper = AOTYScraper.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                ReleasesView().tabItem { Label("Releases", systemImage: "square.stack") }
                ChartsView().tabItem { Label("Charts", systemImage: "chart.bar") }
                SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
                SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .tint(.orange)
            .background(HiddenScraperHost().frame(width: 2, height: 2).allowsHitTesting(false))
            .sheet(item: $scraper.challenge) { ChallengeSheet(url: $0.url) }
        }
    }
}

struct SettingsView: View {
    @AppStorage(AOTYAPI.baseURLKey) private var baseURL = AOTYAPI.defaultBaseURL
    @AppStorage(AOTYAPI.sourceKey) private var source = "device"
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            Form {
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

                Section {
                    Picker("Fetch data", selection: $source) {
                        Text("On this phone").tag("device")
                        Text("Community API").tag("api")
                    }
                    if source == "api" {
                    TextField("API base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Reset to community default") { baseURL = AOTYAPI.defaultBaseURL }
                    }
                } header: {
                    Text("Data source")
                } footer: {
                    Text(source == "device"
                         ? "Pages are loaded from albumoftheyear.org on this phone, using your AOTY session. Nothing passes through another server."
                         : "Uses the community AOTY API server. Point this at your own deployment if you run one.")
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
            .sheet(isPresented: $showLogin) {
                AOTYWebSheet(url: AOTYSession.home, title: "AOTY")
            }
        }
    }
}
