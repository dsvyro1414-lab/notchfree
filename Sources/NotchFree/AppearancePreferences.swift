import SwiftUI

enum AccentPreset: String, CaseIterable, Identifiable {
    case green, blue, purple, pink, orange, white
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .green: Color(red: 0.72, green: 0.91, blue: 0.67)
        case .blue: Color(red: 0.61, green: 0.78, blue: 1)
        case .purple: Color(red: 0.77, green: 0.66, blue: 1)
        case .pink: Color(red: 0.96, green: 0.66, blue: 0.78)
        case .orange: Color(red: 1, green: 0.76, blue: 0.54)
        case .white: Color(white: 0.95)
        }
    }
}

@MainActor final class AppearancePreferences: ObservableObject {
    @Published var accent: AccentPreset {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accentPreset") }
    }
    init() {
        accent = AccentPreset(rawValue: UserDefaults.standard.string(forKey: "accentPreset") ?? "") ?? .green
    }
}

private struct NookAccentKey: EnvironmentKey {
    static let defaultValue = AccentPreset.green.color
}
extension EnvironmentValues {
    var nookAccent: Color {
        get { self[NookAccentKey.self] }
        set { self[NookAccentKey.self] = newValue }
    }
}

struct AccentTheme: ViewModifier {
    @ObservedObject var appearance: AppearancePreferences
    func body(content: Content) -> some View {
        content.environment(\.nookAccent, appearance.accent.color).tint(appearance.accent.color)
    }
}
