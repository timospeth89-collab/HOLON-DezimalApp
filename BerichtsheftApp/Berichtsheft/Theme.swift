import SwiftUI

/// HOLON-Look: dunkler Grund, Holon-Grün #29EB9F als Akzent
/// (gleicher Ton wie AccentColor / App-Icon der DezimalApp).
enum Theme {
    static let green = Color(red: 0x29 / 255.0, green: 0xEB / 255.0, blue: 0x9F / 255.0)
    static let background = Color(red: 0.04, green: 0.06, blue: 0.055)
    static let card = Color(red: 0.09, green: 0.125, blue: 0.115)
    static let cardBorder = Color(red: 0.16, green: 0.22, blue: 0.20)
    static let secondaryText = Color(white: 0.62)

    static func kindColor(_ kind: DayKind) -> Color {
        switch kind {
        case .pb:        return green
        case .ho:        return Color(red: 0.35, green: 0.65, blue: 1.0)
        case .dienstreise: return Color(red: 0.25, green: 0.82, blue: 0.78)
        case .ft:        return Color(red: 1.0, green: 0.72, blue: 0.3)
        case .urlaub:    return Color(red: 1.0, green: 0.55, blue: 0.45)
        case .ez:        return Color(red: 0.75, green: 0.55, blue: 1.0)
        case .kindKrank: return Color(red: 1.0, green: 0.45, blue: 0.75)
        case .krank:     return Color(red: 0.95, green: 0.35, blue: 0.35)
        case .frei:      return Color(white: 0.45)
        }
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.cardBorder, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// Kleines farbiges Kürzel-Badge für die Tagesart (PB, HO, U, …).
struct KindBadge: View {
    let kind: DayKind
    var body: some View {
        Text(kind.short)
            .font(.system(.caption, design: .monospaced).bold())
            .foregroundStyle(kind == .frei ? Theme.secondaryText : .black)
            .frame(minWidth: 40)
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(
                Capsule().fill(kind == .frei ? Theme.card : Theme.kindColor(kind))
            )
            .overlay(
                Capsule().strokeBorder(Theme.kindColor(kind).opacity(kind == .frei ? 0.5 : 0), lineWidth: 1)
            )
    }
}
