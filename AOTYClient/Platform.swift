import SwiftUI
import ImageIO

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformImage = NSImage
typealias PlatformColor = NSColor
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

extension PlatformImage {
    var cgImageValue: CGImage? {
        #if os(iOS)
        cgImage
        #else
        cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }

    func jpegDataValue(compressionQuality: CGFloat) -> Data? {
        #if os(iOS)
        jpegData(compressionQuality: compressionQuality)
        #else
        guard let cg = cgImageValue else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
        #endif
    }

    func preparedForDisplay() -> PlatformImage {
        #if os(iOS)
        preparingForDisplay() ?? self
        #else
        self
        #endif
    }

    static func fromCGImage(_ cg: CGImage) -> PlatformImage {
        #if os(iOS)
        UIImage(cgImage: cg)
        #else
        NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        #endif
    }

    static func resized(_ img: PlatformImage, maxWidth: CGFloat) -> PlatformImage {
        let scale = min(1, maxWidth / max(img.size.width, 1))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        #if os(iOS)
        return UIGraphicsImageRenderer(size: size).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
        #else
        let out = NSImage(size: size)
        out.lockFocus()
        img.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
        #endif
    }
}

enum PlatformPasteboard {
    static var string: String? {
        #if os(iOS)
        UIPasteboard.general.string
        #else
        NSPasteboard.general.string(forType: .string)
        #endif
    }

    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #else
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        #endif
    }

    static func copy(_ url: URL) {
        #if os(iOS)
        UIPasteboard.general.url = url
        #else
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
        #endif
    }
}

enum PlatformApp {
    @MainActor
    static func open(_ url: URL, completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        #if os(iOS)
        UIApplication.shared.open(url) { ok in
            if let completion {
                Task { @MainActor in completion(ok) }
            }
        }
        #else
        let ok = NSWorkspace.shared.open(url)
        completion?(ok)
        #endif
    }

    @MainActor
    static func openAppSettings() {
        #if os(iOS)
        if let u = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(u)
        }
        #else
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(u)
        }
        #endif
    }
}

extension Color {
    static var platformBackground: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var platformSecondaryBackground: Color {
        #if os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var platformSecondaryGroupedBackground: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var platformTertiaryFill: Color {
        #if os(iOS)
        Color(.tertiarySystemFill)
        #else
        Color.secondary.opacity(0.16)
        #endif
    }
}

enum Haptic {
    enum Style { case light, medium }

    static func impact(_ style: Style = .light) {
        #if os(iOS)
        let s: UIImpactFeedbackGenerator.FeedbackStyle = switch style {
        case .light: .light
        case .medium: .medium
        }
        UIImpactFeedbackGenerator(style: s).impactOccurred()
        #endif
    }

    static func selection() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func error() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}

extension ToolbarItemPlacement {
    static var platformTopBarLeading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    static var platformTopBarTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

extension View {
    @ViewBuilder
    func inlineNavTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func noAutocap() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder
    func urlKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.URL)
        #else
        self
        #endif
    }

    @ViewBuilder
    func numberKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func hideStatusBar() -> some View {
        #if os(iOS)
        statusBarHidden()
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformFullScreenCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }

    @ViewBuilder
    func platformFullScreenCover<Item: Identifiable, Content: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }

    @ViewBuilder
    func trackKeyboard(_ isUp: Binding<Bool>) -> some View {
        #if os(iOS)
        self
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in isUp.wrappedValue = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in isUp.wrappedValue = false }
        #else
        self
        #endif
    }

    @ViewBuilder
    func insetGroupedListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    @ViewBuilder
    func compactListSectionSpacing() -> some View {
        #if os(iOS)
        listSectionSpacing(.compact)
        #else
        self
        #endif
    }

    @ViewBuilder
    func hideNavBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformSearchable(text: Binding<String>, prompt: String) -> some View {
        #if os(iOS)
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        #else
        searchable(text: text, placement: .toolbar, prompt: prompt)
        #endif
    }

    /// Generous horizontal breathing room on macOS across lists and scroll views.
    @ViewBuilder
    func macPagePadding(_ amount: CGFloat = 64) -> some View {
        #if os(macOS)
        contentMargins(.horizontal, amount, for: .scrollContent)
        #else
        self
        #endif
    }
}
