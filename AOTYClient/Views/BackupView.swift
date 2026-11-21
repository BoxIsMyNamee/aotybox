import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Portable snapshot of all AOTYbox settings, API keys, AOTY session cookies,
/// profile background, review drafts, and saved AI chats.
struct AppBackup: Codable {
    let version: Int
    let exportedAt: Date
    var strings: [String: String]
    var bools: [String: Bool]
    var doubles: [String: Double]
    var apiKeys: [String: String]
    var cookies: [SavedCookie]
    var profileBackground: Data?
    var aiChats: [String: Data]

    struct SavedCookie: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let expires: Date?
        let isSecure: Bool
        let isHTTPOnly: Bool
    }

    private static let stringKeys = [
        Appearance.key,
        Theme.key,
        "profileUsername",
        "profileUsernameOverride",
        SwipeChoice.albumRight,
        SwipeChoice.albumLeft,
        SwipeChoice.reviewRight,
        SwipeChoice.reviewLeft,
        MusicAppLink.appKey,
        MusicAppLink.songStyleKey,
        AISettings.providerKey,
        AISettings.modelKey,
        AISettings.baseURLKey,
        "notesText",
        "notesAlbum",
        "recentSearches",
        "artistExtras",
    ]

    private static let boolKeys = [
        "colorBlindScores",
        "notesAlbumCheck",
        LastFM.liveEnabledKey,
        AISettings.autoAskKey,
    ]

    private static let doubleKeys = [
        ProfileBackground.xKey,
        ProfileBackground.yKey,
        ProfileBackground.zoomKey,
    ]

    private static var chatsDir: URL {
        URL.applicationSupportDirectory.appending(path: "AIChats", directoryHint: .isDirectory)
    }

    @MainActor
    static func create() async -> AppBackup {
        let ud = UserDefaults.standard
        var strings: [String: String] = [:]
        for k in stringKeys {
            if let v = ud.string(forKey: k) { strings[k] = v }
        }
        // Include all saved review drafts.
        for (k, v) in ud.dictionaryRepresentation() where k.hasPrefix("draft.") {
            if let s = v as? String { strings[k] = s }
        }

        var bools: [String: Bool] = [:]
        for k in boolKeys where ud.object(forKey: k) != nil {
            bools[k] = ud.bool(forKey: k)
        }

        var doubles: [String: Double] = [:]
        for k in doubleKeys where ud.object(forKey: k) != nil {
            doubles[k] = ud.double(forKey: k)
        }

        var apiKeys: [String: String] = [:]
        if let lfm = LastFM.apiKey { apiKeys["lastfm"] = lfm }
        for p in AIProvider.allCases {
            if let k = AISettings.apiKey(p), !k.isEmpty {
                apiKeys["ai.\(p.rawValue)"] = k
            }
        }

        let allCookies = await AOTYSession.dataStore.httpCookieStore.allCookies()
        let aotyCookies = allCookies
            .filter { $0.domain.lowercased().contains("albumoftheyear.org") }
            .map {
                SavedCookie(
                    name: $0.name,
                    value: $0.value,
                    domain: $0.domain,
                    path: $0.path,
                    expires: $0.expiresDate,
                    isSecure: $0.isSecure,
                    isHTTPOnly: $0.isHTTPOnly
                )
            }

        var aiChats: [String: Data] = [:]
        if let files = try? FileManager.default.contentsOfDirectory(at: chatsDir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                if let d = try? Data(contentsOf: file) {
                    aiChats[file.lastPathComponent] = d
                }
            }
        }

        return AppBackup(
            version: 1,
            exportedAt: Date(),
            strings: strings,
            bools: bools,
            doubles: doubles,
            apiKeys: apiKeys,
            cookies: aotyCookies,
            profileBackground: ProfileBackground.rawData(),
            aiChats: aiChats
        )
    }

    @MainActor
    func restore() async -> RestoreSummary {
        let ud = UserDefaults.standard
        for (k, v) in strings { ud.set(v, forKey: k) }
        for (k, v) in bools { ud.set(v, forKey: k) }
        for (k, v) in doubles { ud.set(v, forKey: k) }

        var keyCount = 0
        if let lfm = apiKeys["lastfm"] {
            LastFM.setAPIKey(lfm)
            keyCount += 1
        }
        for p in AIProvider.allCases {
            if let k = apiKeys["ai.\(p.rawValue)"] {
                AISettings.setAPIKey(k, p)
                keyCount += 1
            }
        }

        var cookieCount = 0
        let store = AOTYSession.dataStore.httpCookieStore
        for c in cookies {
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: c.name,
                .value: c.value,
                .domain: c.domain,
                .path: c.path,
            ]
            if let exp = c.expires { props[.expires] = exp }
            if c.isSecure { props[.secure] = "TRUE" }
            if c.isHTTPOnly { props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if let cookie = HTTPCookie(properties: props) {
                await store.setCookie(cookie)
                cookieCount += 1
            }
        }

        var restoredBg = false
        if let bgData = profileBackground, ProfileBackground.save(bgData) {
            restoredBg = true
        }

        var chatCount = 0
        if !aiChats.isEmpty {
            try? FileManager.default.createDirectory(at: Self.chatsDir, withIntermediateDirectories: true)
            for (name, data) in aiChats {
                let safe = URL(fileURLWithPath: name).lastPathComponent
                guard safe.hasSuffix(".json") else { continue }
                if (try? data.write(to: Self.chatsDir.appending(path: safe), options: .atomic)) != nil {
                    chatCount += 1
                }
            }
        }

        ud.set(ud.integer(forKey: ProfileBackground.revKey) + 1, forKey: ProfileBackground.revKey)
        ud.set(ud.integer(forKey: LastFM.revKey) + 1, forKey: LastFM.revKey)
        await AOTYAPI.shared.clearCache()
        NotificationCenter.default.post(name: .aotyReady, object: nil)

        return RestoreSummary(
            settingsCount: strings.count + bools.count + doubles.count,
            apiKeyCount: keyCount,
            cookieCount: cookieCount,
            hasBackground: restoredBg,
            chatCount: chatCount
        )
    }

    struct RestoreSummary {
        let settingsCount: Int
        let apiKeyCount: Int
        let cookieCount: Int
        let hasBackground: Bool
        let chatCount: Int

        var description: String {
            var parts: [String] = []
            parts.append("\(settingsCount) settings")
            if apiKeyCount > 0 { parts.append("\(apiKeyCount) API key\(apiKeyCount == 1 ? "" : "s")") }
            if cookieCount > 0 { parts.append("AOTY login session") }
            if hasBackground { parts.append("profile background") }
            if chatCount > 0 { parts.append("\(chatCount) AI chat\(chatCount == 1 ? "" : "s")") }
            return "Restored " + parts.joined(separator: ", ") + "."
        }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = d
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Export or import a full app backup (settings, keys, login cookies, profile background, drafts, chats).
struct BackupSettingsView: View {
    @State private var busy = false
    @State private var exportDoc: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var status: String?
    @State private var isError = false

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await prepareExport() }
                } label: {
                    HStack {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                        if busy { Spacer(); ProgressView().controlSize(.small) }
                    }
                }
                .disabled(busy)

                Button {
                    showImporter = true
                } label: {
                    Label("Import Backup", systemImage: "square.and.arrow.down")
                }
                .disabled(busy)
            } footer: {
                Text("Saves all settings, theme, swipe actions, Last.fm and AI API keys, AOTY login cookies, profile background & position, review drafts, and AI chats into one JSON file you can move to another device or build.")
            }

            if let status {
                Section {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(isError ? .red : .secondary)
                }
            }

            Section("Privacy") {
                Text("Keep exported backup files private — they contain your API keys and AOTY session cookies. On a new device, Cloudflare may still ask for one quick check while keeping you signed in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Backup & Restore")
        .fileExporter(
            isPresented: $showExporter,
            document: exportDoc,
            contentType: .json,
            defaultFilename: "AOTYbox-Backup"
        ) { result in
            switch result {
            case .success:
                isError = false
                status = "Backup exported."
            case let .failure(err):
                isError = true
                status = "Export failed: \(err.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case let .success(url):
                Task { await performImport(from: url) }
            case let .failure(err):
                isError = true
                status = "Import failed: \(err.localizedDescription)"
            }
        }
    }

    private func prepareExport() async {
        busy = true; defer { busy = false }
        let backup = await AppBackup.create()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(backup) else {
            isError = true
            status = "Couldn't encode backup."
            return
        }
        exportDoc = BackupDocument(data: data)
        showExporter = true
    }

    private func performImport(from url: URL) async {
        busy = true; defer { busy = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let backup = try dec.decode(AppBackup.self, from: data)
            let summary = await backup.restore()
            isError = false
            status = summary.description
        } catch {
            isError = true
            status = "Couldn't read backup file: \(error.localizedDescription)"
        }
    }
}
