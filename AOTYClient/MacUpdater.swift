#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Installs app updates from a `.zip` package selected in Settings and relaunches into `/Applications`.
@MainActor
final class MacUpdater: ObservableObject {
    static let shared = MacUpdater()

    struct PendingUpdate: Identifiable {
        let id = UUID()
        let stagingDir: URL
        let extractedApp: URL
        let targetURL: URL
        let version: String
        let build: String
    }

    @Published var pending: PendingUpdate?
    @Published var busy = false
    @Published var errorMessage: String?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }

    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var isInApplications: Bool {
        Bundle.main.bundleURL.standardizedFileURL.path.hasPrefix("/Applications/")
    }

    var defaultTargetURL: URL {
        if isInApplications {
            return Bundle.main.bundleURL.standardizedFileURL
        }
        return URL(fileURLWithPath: "/Applications/AOTY.app")
    }

    func prepareUpdate(from sourceURL: URL) async {
        busy = true
        errorMessage = nil
        defer { busy = false }

        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("aoty-update-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

            let appURL: URL
            if sourceURL.pathExtension.lowercased() == "app" {
                guard Self.isValidAppBundle(sourceURL) else {
                    try? FileManager.default.removeItem(at: staging)
                    errorMessage = "That doesn't look like a valid macOS .app bundle."
                    return
                }
                let stagedApp = staging.appendingPathComponent("AOTY.app", isDirectory: true)
                try await runProcess("/usr/bin/ditto", [sourceURL.path, stagedApp.path])
                appURL = stagedApp
            } else {
                let localZip = staging.appendingPathComponent("update.zip")
                let extractDir = staging.appendingPathComponent("extracted", isDirectory: true)
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: sourceURL, to: localZip)

                try await runProcess("/usr/bin/ditto", ["-xk", localZip.path, extractDir.path])

                guard let found = Self.findAppBundle(in: extractDir) else {
                    try? FileManager.default.removeItem(at: staging)
                    errorMessage = "No valid AOTY.app bundle was found inside that .zip file."
                    return
                }
                appURL = found
            }

            let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
            let info = NSDictionary(contentsOf: plistURL) as? [String: Any] ?? [:]
            let newVersion = info["CFBundleShortVersionString"] as? String ?? "?"
            let newBuild = info["CFBundleVersion"] as? String ?? "?"

            pending = PendingUpdate(
                stagingDir: staging,
                extractedApp: appURL,
                targetURL: defaultTargetURL,
                version: newVersion,
                build: newBuild
            )
        } catch {
            try? FileManager.default.removeItem(at: staging)
            errorMessage = error.localizedDescription
        }
    }

    func cancelPending() {
        if let p = pending {
            try? FileManager.default.removeItem(at: p.stagingDir)
            pending = nil
        }
    }

    func installPending() {
        guard let update = pending else { return }
        pending = nil
        installAndRelaunch(from: update.extractedApp, to: update.targetURL, cleanup: update.stagingDir)
    }

    func moveToApplications() {
        let current = Bundle.main.bundleURL.standardizedFileURL
        let target = URL(fileURLWithPath: "/Applications/AOTY.app")
        guard current != target else { return }
        installAndRelaunch(from: current, to: target, cleanup: nil)
    }

    private func installAndRelaunch(from sourceApp: URL, to targetApp: URL, cleanup stagingDir: URL?) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let parentDir = targetApp.deletingLastPathComponent().path
        let needsAdmin = !FileManager.default.isWritableFile(atPath: parentDir)
            || (FileManager.default.fileExists(atPath: targetApp.path) && !FileManager.default.isWritableFile(atPath: targetApp.path))

        let q = Self.shellQuote
        let cleanupCmd = stagingDir.map { "rm -rf \(q($0.path))" } ?? ""

        if needsAdmin {
            let adminScript = """
            kill -TERM \(pid) 2>/dev/null || true
            for i in 1 2 3 4 5 6 7 8 9 10; do
                kill -0 \(pid) 2>/dev/null || break
                sleep 0.15
            done
            kill -KILL \(pid) 2>/dev/null || true
            rm -rf \(q(targetApp.path))
            /usr/bin/ditto \(q(sourceApp.path)) \(q(targetApp.path))
            /usr/bin/xattr -dr com.apple.quarantine \(q(targetApp.path)) 2>/dev/null || true
            \(cleanupCmd)
            """
            let escaped = adminScript
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let appleScript = "do shell script \"\(escaped)\" with administrator privileges"

            DispatchQueue.global(qos: .userInitiated).async {
                var err: NSDictionary?
                let script = NSAppleScript(source: appleScript)
                _ = script?.executeAndReturnError(&err)
                if err == nil {
                    let openProc = Process()
                    openProc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    openProc.arguments = ["-n", targetApp.path]
                    try? openProc.run()
                }
                DispatchQueue.main.async {
                    if let err {
                        self.errorMessage = (err[NSAppleScript.errorMessage] as? String) ?? "Administrator permission was cancelled."
                        if let stagingDir { try? FileManager.default.removeItem(at: stagingDir) }
                    } else {
                        Self.forceQuitApp()
                    }
                }
            }
            return
        }

        let script = """
        sleep 0.25
        kill -TERM \(pid) 2>/dev/null || true
        for i in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 \(pid) 2>/dev/null || break
            sleep 0.15
        done
        kill -KILL \(pid) 2>/dev/null || true
        rm -rf \(q(targetApp.path))
        /usr/bin/ditto \(q(sourceApp.path)) \(q(targetApp.path))
        /usr/bin/xattr -dr com.apple.quarantine \(q(targetApp.path)) 2>/dev/null || true
        /usr/bin/open -n \(q(targetApp.path))
        \(cleanupCmd)
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", script]
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            Self.forceQuitApp()
        } catch {
            if let stagingDir { try? FileManager.default.removeItem(at: stagingDir) }
            errorMessage = error.localizedDescription
        }
    }

    private static func forceQuitApp() {
        UserDefaults.standard.synchronize()
        for win in NSApp.windows {
            if let sheet = win.attachedSheet {
                win.endSheet(sheet)
            }
        }
        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exit(0)
        }
    }

    private static func isValidAppBundle(_ url: URL) -> Bool {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) as? [String: Any],
              let execName = info["CFBundleExecutable"] as? String else { return false }
        return FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/\(execName)").path)
    }

    private static func findAppBundle(in root: URL) -> URL? {
        let fm = FileManager.default
        guard let e = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let expectedID = Bundle.main.bundleIdentifier
        var fallback: URL?

        for case let url as URL in e {
            if url.lastPathComponent == "__MACOSX" {
                e.skipDescendants()
                continue
            }
            guard url.pathExtension == "app" else { continue }
            e.skipDescendants()

            guard isValidAppBundle(url) else { continue }
            let plist = url.appendingPathComponent("Contents/Info.plist")
            let info = NSDictionary(contentsOf: plist) as? [String: Any] ?? [:]
            if let bundleID = info["CFBundleIdentifier"] as? String, bundleID == expectedID {
                return url
            }
            if fallback == nil { fallback = url }
        }
        return fallback
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func runProcess(_ launchPath: String, _ args: [String]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: launchPath)
                proc.arguments = args
                let errPipe = Pipe()
                proc.standardError = errPipe
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus == 0 {
                        cont.resume()
                    } else {
                        let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        cont.resume(throwing: NSError(
                            domain: "MacUpdater",
                            code: Int(proc.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: msg?.isEmpty == false ? msg! : "Copy/unzip failed (exit \(proc.terminationStatus))."]
                        ))
                    }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private static let latestUpdateURL = URL(string: "https://raw.githubusercontent.com/BoxIsMyNamee/aotybox/source/AOTY-macOS-arm64.aotyupdate")!
    private static let latestSourceJSONURL = URL(string: "https://raw.githubusercontent.com/BoxIsMyNamee/aotybox/source/source.json")!

    @Published var latestRemoteBuild: String?
    @Published var checkingRemote = false

    func checkLatestBuild() async {
        guard !checkingRemote else { return }
        checkingRemote = true
        defer { checkingRemote = false }
        var req = URLRequest(url: Self.latestSourceJSONURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apps = json["apps"] as? [[String: Any]],
              let versions = apps.first?["versions"] as? [[String: Any]],
              let latest = versions.first else { return }
        if let b = latest["buildVersion"] as? String {
            latestRemoteBuild = b
        } else if let v = latest["version"] as? String {
            latestRemoteBuild = v
        }
    }

    func downloadAndPrepareLatest() async {
        busy = true
        errorMessage = nil
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("AOTY-latest-\(UUID().uuidString).aotyupdate")
        do {
            var req = URLRequest(url: Self.latestUpdateURL)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (downloadedURL, response) = try await URLSession.shared.download(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                busy = false
                errorMessage = "GitHub returned HTTP \(http.statusCode) while downloading the update."
                return
            }
            try? FileManager.default.removeItem(at: tempFile)
            try FileManager.default.moveItem(at: downloadedURL, to: tempFile)
            await prepareUpdate(from: tempFile)
            try? FileManager.default.removeItem(at: tempFile)
        } catch {
            busy = false
            try? FileManager.default.removeItem(at: tempFile)
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    func findLatestInDownloads() -> URL? {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return nil }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: downloads,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let candidates = urls.filter { u in
            let name = u.lastPathComponent.lowercased()
            let ext = u.pathExtension.lowercased()
            if ext == "aotyupdate" { return true }
            if ext == "zip" && name.contains("aoty") { return true }
            if ext == "app" && name.hasPrefix("aoty") { return true }
            return false
        }
        return candidates.max { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
    }

    func pickUpdateFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose AOTY Update Package"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        var types: [UTType] = [.zip, .applicationBundle, .data]
        if let custom = UTType(filenameExtension: "aotyupdate") {
            types.insert(custom, at: 0)
        }
        panel.allowedContentTypes = types

        let handleChoice: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard let self else { return }
            if response == .OK, let url = panel?.url {
                Task { @MainActor in
                    await self.prepareUpdate(from: url)
                }
            } else if response == .abort, let fallback = self.findLatestInDownloads() {
                // If macOS's Open/Save Panel XPC service failed to connect, automatically fall back
                // to the newest AOTY update package in ~/Downloads.
                Task { @MainActor in
                    await self.prepareUpdate(from: fallback)
                }
            }
        }

        if let win = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: win, completionHandler: handleChoice)
        } else {
            panel.begin(completionHandler: handleChoice)
        }
    }
}

struct MacUpdateSettingsSection: View {
    @ObservedObject private var updater = MacUpdater.shared
    @State private var dropTargeted = false
    @State private var recentDownload: URL?

    var body: some View {
        Section {
            LabeledContent("Version", value: "\(updater.currentVersion) (Build \(updater.currentBuild))")
            if let remote = updater.latestRemoteBuild {
                LabeledContent("Latest on GitHub", value: "Build \(remote)")
            }
            LabeledContent("Location", value: updater.isInApplications ? "Applications" : Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent)

            if !updater.isInApplications {
                Button("Move AOTY to Applications") {
                    updater.moveToApplications()
                }
            }

            Button {
                Task { await updater.downloadAndPrepareLatest() }
            } label: {
                HStack {
                    Label(
                        updater.latestRemoteBuild.map { "Download & Install Latest (Build \($0))" } ?? "Download & Install Latest from GitHub",
                        systemImage: "icloud.and.arrow.down"
                    )
                    Spacer()
                    if updater.busy {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(updater.busy)

            if let recent = recentDownload {
                Button {
                    Task { await updater.prepareUpdate(from: recent) }
                } label: {
                    Label("Install \(recent.lastPathComponent) from Downloads", systemImage: "shippingbox")
                }
                .disabled(updater.busy)
            }

            Button {
                updater.pickUpdateFile()
            } label: {
                Label("Choose Update File or Drag Here…", systemImage: "folder")
            }
            .disabled(updater.busy)
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    let ext = url.pathExtension.lowercased()
                    guard ext == "aotyupdate" || ext == "zip" || ext == "app" else { return }
                    Task { @MainActor in
                        await updater.prepareUpdate(from: url)
                    }
                }
                return true
            }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5]))
                }
            }
        } header: {
            Text("App Updates")
        } footer: {
            Text("Click 'Download & Install Latest' to update in one click, or drag an .aotyupdate / .zip / AOTY.app file onto this section.")
        }
        .task {
            recentDownload = updater.findLatestInDownloads()
            await updater.checkLatestBuild()
        }
        .alert(item: $updater.pending) { update in
            Alert(
                title: Text("Install AOTY \(update.version) (Build \(update.build))?"),
                message: Text("This will replace \(update.targetURL.path) and relaunch the app."),
                primaryButton: .default(Text("Install & Relaunch")) {
                    updater.installPending()
                },
                secondaryButton: .cancel {
                    updater.cancelPending()
                }
            )
        }
        .alert("Update Failed", isPresented: Binding(
            get: { updater.errorMessage != nil },
            set: { if !$0 { updater.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { updater.errorMessage = nil }
        } message: {
            Text(updater.errorMessage ?? "")
        }
    }
}
#endif
