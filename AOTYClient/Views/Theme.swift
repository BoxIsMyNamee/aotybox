import SwiftUI

/// App accent color, stored as a hex string so it survives relaunches.
enum Theme {
    static let key = "accentHex"
    static let defaultHex = "#FF9500"

    static let presets: [(String, String)] = [
        ("Orange", "#FF9500"), ("Red", "#FF3B30"), ("Pink", "#FF2D55"), ("Purple", "#AF52DE"),
        ("Indigo", "#5856D6"), ("Blue", "#007AFF"), ("Teal", "#30B0C7"), ("Mint", "#00C7BE"),
        ("Green", "#34C759"), ("Yellow", "#FFCC00"), ("Brown", "#A2845E"), ("Gray", "#8E8E93"),
    ]
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s, radix: 16) ?? 0xFF9500
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var hexString: String {
        let c = UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(round(max(0, min(1, r)) * 255)), Int(round(max(0, min(1, g)) * 255)), Int(round(max(0, min(1, b)) * 255)))
    }
}

struct AccentColorPicker: View {
    @AppStorage(Theme.key) private var hex = Theme.defaultHex
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Theme.presets, id: \.1) { name, value in
                    Button { hex = value } label: {
                        Circle()
                            .fill(Color(hex: value))
                            .frame(width: 34, height: 34)
                            .overlay {
                                if hex.uppercased() == value {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                }
                            }
                            .overlay(Circle().strokeBorder(.white.opacity(hex.uppercased() == value ? 0.9 : 0), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                }
            }
            ColorPicker("Custom color", selection: Binding(
                get: { Color(hex: hex) },
                set: { hex = $0.hexString }
            ), supportsOpacity: false)
        }
        .padding(.vertical, 6)
    }
}

/// Sheets and full-screen covers don't always inherit the app tint; apply it explicitly.
struct AccentTint: ViewModifier {
    @AppStorage(Theme.key) private var hex = Theme.defaultHex
    func body(content: Content) -> some View { content.tint(Color(hex: hex)) }
}

extension View {
    func accentTint() -> some View { modifier(AccentTint()) }
}
