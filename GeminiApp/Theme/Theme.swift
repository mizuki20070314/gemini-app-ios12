import UIKit

public enum ThemeMode: String {
    case light
    case dark
    case system
}

public struct Theme {
    public let isDark: Bool
    public let background: UIColor
    public let surface: UIColor
    public let sidebarBackground: UIColor
    public let sidebarSelected: UIColor
    public let textPrimary: UIColor
    public let textSecondary: UIColor
    public let textTertiary: UIColor
    public let accent: UIColor
    public let accentSoft: UIColor
    public let accentPurple: UIColor
    public let onAccent: UIColor
    public let userBubble: UIColor
    public let composerBackground: UIColor
    public let border: UIColor
    public let separator: UIColor
    public let codeBackground: UIColor
    public let inlineCodeBackground: UIColor
    public let thinkingBackground: UIColor
    public let sendButton: UIColor
    public let sendButtonDisabled: UIColor
    public let destructive: UIColor
    public let success: UIColor
    public let dimming: UIColor

    public static let didChange = Notification.Name("GeminiTheme.didChange")

    private static var currentMode: ThemeMode = {
        let raw = UserDefaults.standard.string(forKey: "gemini.themeMode") ?? "system"
        return ThemeMode(rawValue: raw) ?? .system
    }()

    public static var mode: ThemeMode { return currentMode }
    public static var forcedDark: Bool?

    public static var current: Theme {
        if let forced = forcedDark { return forced ? .dark : .light }
        switch currentMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return isSystemDark ? .dark : .light
        }
    }

    public static func setMode(_ mode: ThemeMode) {
        currentMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "gemini.themeMode")
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static var isSystemDark: Bool {
        if #available(iOS 13.0, *) {
            let style = UIApplication.shared.keyWindow?.traitCollection.userInterfaceStyle ?? .unspecified
            return style == .dark
        }
        return false
    }

    public var statusBarStyle: UIStatusBarStyle { return isDark ? .lightContent : .default }
    public var keyboardAppearance: UIKeyboardAppearance { return isDark ? .dark : .light }

    public static let light = Theme(
        isDark: false,
        background: UIColor(hex: "#FFFFFF"),
        surface: UIColor(hex: "#F0F4F9"),
        sidebarBackground: UIColor(hex: "#F0F4F9"),
        sidebarSelected: UIColor(hex: "#D3E3FD"),
        textPrimary: UIColor(hex: "#1F1F1F"),
        textSecondary: UIColor(hex: "#5F6368"),
        textTertiary: UIColor(hex: "#8E918F"),
        accent: UIColor(hex: "#1A73E8"),
        accentSoft: UIColor(hex: "#E8F0FE"),
        accentPurple: UIColor(hex: "#8E5BE8"),
        onAccent: UIColor(hex: "#FFFFFF"),
        userBubble: UIColor(hex: "#E8F0FE"),
        composerBackground: UIColor(hex: "#F0F4F9"),
        border: UIColor(hex: "#DDE3EA"),
        separator: UIColor(hex: "#E3E8EE"),
        codeBackground: UIColor(hex: "#F4F6FA"),
        inlineCodeBackground: UIColor(hex: "#EEF2F7"),
        thinkingBackground: UIColor(hex: "#F5F7FB"),
        sendButton: UIColor(hex: "#1A73E8"),
        sendButtonDisabled: UIColor(hex: "#C5D9F8"),
        destructive: UIColor(hex: "#D93025"),
        success: UIColor(hex: "#188038"),
        dimming: UIColor(white: 0, alpha: 0.35)
    )

    public static let dark = Theme(
        isDark: true,
        background: UIColor(hex: "#131314"),
        surface: UIColor(hex: "#1E1F20"),
        sidebarBackground: UIColor(hex: "#1E1F20"),
        sidebarSelected: UIColor(hex: "#004A77"),
        textPrimary: UIColor(hex: "#E3E3E3"),
        textSecondary: UIColor(hex: "#9AA0A6"),
        textTertiary: UIColor(hex: "#75787B"),
        accent: UIColor(hex: "#8AB4F8"),
        accentSoft: UIColor(hex: "#1F3047"),
        accentPurple: UIColor(hex: "#B69DF8"),
        onAccent: UIColor(hex: "#062E6F"),
        userBubble: UIColor(hex: "#282A2C"),
        composerBackground: UIColor(hex: "#1E1F20"),
        border: UIColor(hex: "#35373A"),
        separator: UIColor(hex: "#2D2F31"),
        codeBackground: UIColor(hex: "#1B1C1E"),
        inlineCodeBackground: UIColor(hex: "#282A2C"),
        thinkingBackground: UIColor(hex: "#1B1D21"),
        sendButton: UIColor(hex: "#8AB4F8"),
        sendButtonDisabled: UIColor(hex: "#35455C"),
        destructive: UIColor(hex: "#F28B82"),
        success: UIColor(hex: "#81C995"),
        dimming: UIColor(white: 0, alpha: 0.55)
    )
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt32 = 0
        Scanner(string: s).scanHexInt32(&rgb)
        let r, g, b, a: CGFloat
        switch s.count {
        case 6:
            r = CGFloat((rgb >> 16) & 0xFF) / 255.0
            g = CGFloat((rgb >> 8) & 0xFF) / 255.0
            b = CGFloat(rgb & 0xFF) / 255.0
            a = 1.0
        case 8:
            r = CGFloat((rgb >> 24) & 0xFF) / 255.0
            g = CGFloat((rgb >> 16) & 0xFF) / 255.0
            b = CGFloat((rgb >> 8) & 0xFF) / 255.0
            a = CGFloat(rgb & 0xFF) / 255.0
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
