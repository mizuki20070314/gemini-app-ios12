import UIKit

/// Visual style for Markdown rendering. Colors are injected (no Theme dependency).
struct MarkdownStyle {
    var baseFont: UIFont
    var textColor: UIColor
    var secondaryTextColor: UIColor
    var linkColor: UIColor
    var codeFont: UIFont
    var inlineCodeFont: UIFont
    var inlineCodeTextColor: UIColor
    var inlineCodeBackground: UIColor
    var codeBlockBackground: UIColor
    var codeBlockTextColor: UIColor
    var quoteBarColor: UIColor
    var lineSpacing: CGFloat
    var paragraphSpacing: CGFloat

    func headingFont(level: Int) -> UIFont {
        let size: CGFloat
        switch level {
        case 1: size = 22
        case 2: size = 20
        case 3: size = 18
        default: size = baseFont.pointSize
        }
        return UIFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func standard(textColor: UIColor,
                         secondary: UIColor,
                         accent: UIColor,
                         codeBackground: UIColor,
                         isDark: Bool) -> MarkdownStyle {
        let baseFont = UIFont.systemFont(ofSize: 16)
        let codeFont = UIFont(name: "Menlo", size: 14) ?? UIFont.systemFont(ofSize: 14)
        let inlineCodeFont = UIFont(name: "Menlo", size: baseFont.pointSize * 0.9) ?? UIFont.systemFont(ofSize: baseFont.pointSize * 0.9)
        return MarkdownStyle(
            baseFont: baseFont,
            textColor: textColor,
            secondaryTextColor: secondary,
            linkColor: accent,
            codeFont: codeFont,
            inlineCodeFont: inlineCodeFont,
            inlineCodeTextColor: textColor,
            inlineCodeBackground: codeBackground,
            codeBlockBackground: codeBackground,
            codeBlockTextColor: textColor,
            quoteBarColor: secondary,
            lineSpacing: 4,
            paragraphSpacing: 8
        )
    }
}
