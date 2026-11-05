import SwiftUI

@main
struct AOTYClientApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ReleasesView().tabItem { Label("Releases", systemImage: "square.stack") }
                ChartsView().tabItem { Label("Charts", systemImage: "chart.bar") }
                SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
                SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .tint(.orange)
        }
    }
}

struct SettingsView: View {
    @AppStorage(AOTYAPI.baseURLKey) private var baseURL = AOTYAPI.defaultBaseURL
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
                    TextField("API base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Reset to community default") { baseURL = AOTYAPI.defaultBaseURL }
                } header: {
                    Text("Data source")
                } footer: {
                    Text("Point this at your own deployment of the AOTY API to stop relying on the shared community instance.")
                }

                Section {
                    Button("Clear cache") { Task { await AOTYAPI.shared.clearCache() } }
                }

                Section("About") {
                    Text("Unofficial client. Album data © Album of the Year and its contributing publications, fetched via the community AOTY API (github.com/edideaur/AOTY-api). Not affiliated with Album of the Year.")
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
