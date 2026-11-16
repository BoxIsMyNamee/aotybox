import AppIntents
import Foundation

/// "Identify a Song" from the lock screen / Control Center: opens the app and starts listening.
/// Built into both the app and the widget extension; it runs in the app, which it opens.
struct ListenIntent: AppIntent {
    static let title: LocalizedStringResource = "Identify a Song"
    static let description = IntentDescription("Opens AOTY and listens for the song playing around you.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ListenRequest.post()
        return .result()
    }
}

/// Hand-off to the listen sheet; also kept as a flag in case the screen isn't up yet.
enum ListenRequest {
    static let note = Notification.Name("aotyListenRequested")
    static let key = "listenPending"

    static func post() {
        UserDefaults.standard.set(true, forKey: key)
        NotificationCenter.default.post(name: note, object: nil)
    }

    /// True once per request.
    static func take() -> Bool {
        guard UserDefaults.standard.bool(forKey: key) else { return false }
        UserDefaults.standard.set(false, forKey: key)
        return true
    }
}
