import SwiftUI

enum AppTheme {
    case light
    case dark
    case system
}

struct Theme {
    // MARK: - Messenger-inspired Colors

    // Primary gradient for sent messages (Messenger blue-purple gradient)
    static let messengerGradient = LinearGradient(
        colors: [Color(hex: "0078FF"), Color(hex: "00C6FF")],
        startPoint: .bottomLeading,
        endPoint: .topTrailing
    )

    static let messengerGradientDark = LinearGradient(
        colors: [Color(hex: "0066DD"), Color(hex: "00A8DD")],
        startPoint: .bottomLeading,
        endPoint: .topTrailing
    )

    // MARK: - Adaptive Colors

    struct Colors {
        // Background colors
        static let primaryBackground = Color("PrimaryBackground")
        static let secondaryBackground = Color("SecondaryBackground")
        static let tertiaryBackground = Color("TertiaryBackground")

        // Text colors
        static let primaryText = Color("PrimaryText")
        static let secondaryText = Color("SecondaryText")

        // Accent colors
        static let accent = Color(hex: "0078FF")
        static let accentLight = Color(hex: "00C6FF")

        // Message bubble colors
        static let sentBubble = Color(hex: "0078FF")
        static let receivedBubble = Color("ReceivedBubble")
        static let sentText = Color.white
        static let receivedText = Color("PrimaryText")

        // Status colors
        static let online = Color.green
        static let offline = Color.gray
        static let error = Color.red
        static let warning = Color.orange

        // Divider
        static let divider = Color("Divider")

        // Sidebar
        static let sidebarBackground = Color("SidebarBackground")
        static let sidebarSelected = Color("SidebarSelected")
    }

    // MARK: - Spacing

    struct Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    struct CornerRadius {
        static let small: CGFloat = 4
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let bubble: CGFloat = 18
        static let avatar: CGFloat = 20
    }

    // MARK: - Typography

    struct Typography {
        static let largeTitle = Font.system(size: 28, weight: .bold)
        static let title = Font.system(size: 22, weight: .semibold)
        static let headline = Font.system(size: 17, weight: .semibold)
        static let body = Font.system(size: 15, weight: .regular)
        static let callout = Font.system(size: 14, weight: .regular)
        static let caption = Font.system(size: 12, weight: .regular)
        static let footnote = Font.system(size: 11, weight: .regular)
    }

    // MARK: - Shadows

    struct Shadows {
        static let small = Shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        static let medium = Shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        static let large = Shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    // MARK: - Animation

    struct Animation {
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
    }
}

// MARK: - Shadow Helper

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func applyShadow(_ shadow: Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Theme Manager

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @AppStorage("selectedTheme") var selectedTheme: String = "system" {
        didSet {
            objectWillChange.send()
        }
    }

    var currentTheme: AppTheme {
        switch selectedTheme {
        case "light": return .light
        case "dark": return .dark
        default: return .system
        }
    }

    var effectiveColorScheme: ColorScheme? {
        switch selectedTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil  // Use system appearance
        }
    }

    func setTheme(_ theme: AppTheme) {
        switch theme {
        case .light: selectedTheme = "light"
        case .dark: selectedTheme = "dark"
        case .system: selectedTheme = "system"
        }
    }
}
