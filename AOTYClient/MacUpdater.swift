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
            while kill -0 \(pid) 2>/dev/null; do sleep 0.15; done
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
                        NSApp.terminate(nil)
                    }
                }
            }
            return
        }

        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.15; done
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
            NSApp.terminate(nil)
        } catch {
            if let stagingDir { try? FileManager.default.removeItem(at: stagingDir) }
            errorMessage = error.localizedDescription
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
}

struct MacUpdateSettingsSection: View {
    @ObservedObject private var updater = MacUpdater.shared
    @State private var pickingUpdate = false
    @State private var dropTargeted = false

    var body: some View {
        Section {
            LabeledContent("Version", value: "\(updater.currentVersion) (Build \(updater.currentBuild))")
            LabeledContent("Location", value: updater.isInApplications ? "Applications" : Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent)

            if !updater.isInApplications {
                Button("Move AOTY to Applications") {
                    updater.moveToApplications()
                }
            }

            Button {
                pickingUpdate = true
            } label: {
                HStack {
                    Label("Install Update (.zip or .app)…", systemImage: "arrow.down.doc")
                    Spacer()
                    if updater.busy {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(updater.busy)
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    let ext = url.pathExtension.lowercased()
                    guard ext == "zip" || ext == "app" else { return }
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
            Text("Pick or drop a downloaded AOTY.app or .zip to replace \(updater.defaultTargetURL.path) and relaunch.")
        }
        .fileImporter(isPresented: $pickingUpdate, allowedContentTypes: [.zip, .applicationBundle]) { result in
            if case let .success(url) = result {
                Task { await updater.prepareUpdate(from: url) }
            }
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
