import UIKit

enum RenderedBlock {
    case text(NSAttributedString)
    case code(language: String?, code: String)
    case table(headers: [String], rows: [[String]])
}

final class MarkdownRenderer {

    static let quoteAttribute = NSAttributedString.Key("MarkdownQuote")

    let style: MarkdownStyle

    init(style: MarkdownStyle) {
        self.style = style
    }

    func renderBlocks(_ markdown: String) -> [RenderedBlock] {
        let blocks = MarkdownParser.parse(markdown)
        var result: [RenderedBlock] = []
        for block in blocks {
            switch block {
            case .heading(let level, let text):
                result.append(.text(renderHeading(level: level, text: text)))
            case .paragraph(let text):
                result.append(.text(renderParagraph(text)))
            case .codeBlock(let language, let code):
                result.append(.code(language: language, code: code))
            case .bulletList(let items):
                result.append(.text(renderBulletList(items)))
            case .orderedList(let items):
                result.append(.text(renderOrderedList(items)))
            case .quote(let text):
                result.append(.text(renderQuote(text)))
            case .table(let headers, let rows):
                result.append(.table(headers: headers, rows: rows))
            case .horizontalRule:
                result.append(.text(renderHorizontalRule()))
            }
        }
        return result
    }

    func render(_ markdown: String) -> NSAttributedString {
        let rendered = renderBlocks(markdown)
        let result = NSMutableAttributedString()
        for (idx, block) in rendered.enumerated() {
            switch block {
            case .text(let attr):
                result.append(attr)
            case .code(let language, let code):
                result.append(renderCodeBlockFlattened(language: language, code: code))
            case .table(let headers, let rows):
                result.append(renderTableFlattened(headers: headers, rows: rows))
            }
            // spacing between blocks
            if idx < rendered.count - 1 {
                let para = NSMutableParagraphStyle()
                result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: para]))
            }
        }
        return result
    }

    // MARK: - Block rendering

    private func renderHeading(level: Int, text: String) -> NSAttributedString {
        let font = style.headingFont(level: level)
        let attr = buildInline(text, baseFont: font, bold: false, italic: false, strike: false)
        // ensure color
        attr.addAttribute(.foregroundColor, value: style.textColor, range: NSRange(location: 0, length: attr.length))
        let para = NSMutableParagraphStyle()
        para.headIndent = 0
        para.firstLineHeadIndent = 0
        para.tabStops = []
        para.paragraphSpacing = style.paragraphSpacing
        para.lineSpacing = style.lineSpacing
        attr.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: attr.length))
        return attr
    }

    private func renderParagraph(_ text: String) -> NSAttributedString {
        let attr = buildInline(text, baseFont: style.baseFont, bold: false, italic: false, strike: false)
        attr.addAttribute(.foregroundColor, value: style.textColor, range: NSRange(location: 0, length: attr.length))
        let para = NSMutableParagraphStyle()
        para.headIndent = 0
        para.firstLineHeadIndent = 0
        para.tabStops = []
        para.paragraphSpacing = style.paragraphSpacing
        para.lineSpacing = style.lineSpacing
        attr.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: attr.length))
        return attr
    }

    private func renderQuote(_ text: String) -> NSAttributedString {
        let attr = buildInline(text, baseFont: style.baseFont, bold: false, italic: false, strike: false)
        attr.addAttribute(.foregroundColor, value: style.secondaryTextColor, range: NSRange(location: 0, length: attr.length))
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 12
        para.headIndent = 12
        para.paragraphSpacing = style.paragraphSpacing
        para.lineSpacing = style.lineSpacing
        attr.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: attr.length))
        attr.addAttribute(MarkdownRenderer.quoteAttribute, value: true, range: NSRange(location: 0, length: attr.length))
        return attr
    }

    private func renderBulletList(_ items: [(Int, String)]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (idx, item) in items.enumerated() {
            let (level, text) = item
            let bullet: String
            switch level {
            case 0: bullet = "•"
            case 1: bullet = "◦"
            default: bullet = "▪"
            }
            let isTask = text.hasPrefix("☐ ") || text.hasPrefix("☑ ")
            var lineText = text
            var prefix = bullet
            if isTask {
                prefix = "" // checkbox replaces bullet
            }
            let indent = CGFloat(level) * 16.0
            let hanging: CGFloat = 16.0
            let para = NSMutableParagraphStyle()
            para.firstLineHeadIndent = indent
            para.headIndent = indent + (prefix.isEmpty ? 0 : hanging)
            if !prefix.isEmpty {
                para.tabStops = [NSTextTab(textAlignment: .left, location: indent + hanging)]
            }
            para.paragraphSpacing = 2
            para.lineSpacing = style.lineSpacing

            let line = NSMutableAttributedString()
            if !prefix.isEmpty {
                line.append(NSAttributedString(string: prefix + "\t", attributes: [
                    .font: style.baseFont,
                    .foregroundColor: style.textColor
                ]))
            }
            let inner = buildInline(lineText, baseFont: style.baseFont, bold: false, italic: false, strike: false)
            inner.addAttribute(.foregroundColor, value: style.textColor, range: NSRange(location: 0, length: inner.length))
            line.append(inner)
            line.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: line.length))
            result.append(line)
            if idx < items.count - 1 { result.append(NSAttributedString(string: "\n")) }
        }
        return result
    }

    private func renderOrderedList(_ items: [(Int, Int, String)]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (idx, item) in items.enumerated() {
            let (number, level, text) = item
            let indent = CGFloat(level) * 16.0
            let hanging: CGFloat = 24.0
            let para = NSMutableParagraphStyle()
            para.firstLineHeadIndent = indent
            para.headIndent = indent + hanging
            para.tabStops = [NSTextTab(textAlignment: .left, location: indent + hanging)]
            para.paragraphSpacing = 2
            para.lineSpacing = style.lineSpacing

            let line = NSMutableAttributedString()
            line.append(NSAttributedString(string: "\(number).\t", attributes: [
                .font: style.baseFont,
                .foregroundColor: style.textColor
            ]))
            let inner = buildInline(text, baseFont: style.baseFont, bold: false, italic: false, strike: false)
            inner.addAttribute(.foregroundColor, value: style.textColor, range: NSRange(location: 0, length: inner.length))
            line.append(inner)
            line.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: line.length))
            result.append(line)
            if idx < items.count - 1 { result.append(NSAttributedString(string: "\n")) }
        }
        return result
    }

    private func renderHorizontalRule() -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = style.paragraphSpacing
        let attr = NSMutableAttributedString(string: "————————————————————", attributes: [
            .font: style.baseFont,
            .foregroundColor: style.secondaryTextColor,
            .paragraphStyle: para
        ])
        return attr
    }

    private func renderCodeBlockFlattened(language: String?, code: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 8
        para.headIndent = 8
        para.paragraphSpacing = style.paragraphSpacing
        para.lineSpacing = style.lineSpacing
        let attr = NSMutableAttributedString(string: code, attributes: [
            .font: style.codeFont,
            .foregroundColor: style.codeBlockTextColor,
            .backgroundColor: style.codeBlockBackground,
            .paragraphStyle: para
        ])
        if let lang = language, !lang.isEmpty {
            let header = NSMutableAttributedString(string: lang + "\n", attributes: [
                .font: style.codeFont,
                .foregroundColor: style.secondaryTextColor,
                .backgroundColor: style.codeBlockBackground,
                .paragraphStyle: para
            ])
            header.append(attr)
            return header
        }
        return attr
    }

    private func renderTableFlattened(headers: [String], rows: [[String]]) -> NSAttributedString {
        // compute column widths
        let allRows = [headers] + rows
        let colCount = headers.count
        var widths: [Int] = Array(repeating: 0, count: colCount)
        for row in allRows {
            for (c, cell) in row.enumerated() {
                if c < colCount {
                    widths[c] = max(widths[c], cell.count)
                }
            }
        }
        func pad(_ s: String, to w: Int) -> String {
            if s.count >= w { return s }
            return s + String(repeating: " ", count: w - s.count)
        }
        var lines: [String] = []
        lines.append(headers.enumerated().map { pad($1, to: widths[$0]) }.joined(separator: "  "))
        lines.append(widths.map { String(repeating: "-", count: max(3, $0)) }.joined(separator: "  "))
        for row in rows {
            var cells: [String] = []
            for c in 0..<colCount {
                let val = c < row.count ? row[c] : ""
                cells.append(pad(val, to: widths[c]))
            }
            lines.append(cells.joined(separator: "  "))
        }
        let text = lines.joined(separator: "\n")
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = style.paragraphSpacing
        let attr = NSMutableAttributedString(string: text, attributes: [
            .font: style.codeFont,
            .foregroundColor: style.textColor,
            .paragraphStyle: para
        ])
        return attr
    }

    // MARK: - Inline parsing

    private func applyTraits(_ font: UIFont, bold: Bool, italic: Bool) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if let desc = font.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: desc, size: font.pointSize)
        }
        return font
    }

    private func buildInline(_ text: String, baseFont: UIFont, bold: Bool, italic: Bool, strike: Bool) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let font = applyTraits(baseFont, bold: bold, italic: italic)
        var i = text.startIndex
        let n = text.endIndex
        while i < n {
            let c = text[i]

            // Escape
            if c == "\\" {
                let next = text.index(after: i)
                if next < n {
                    appendRun(result, string: String(text[next]), font: font, strike: strike, color: style.textColor)
                    i = text.index(after: next)
                    continue
                }
            }

            // Inline code
            if c == "`" {
                let after = text.index(after: i)
                if let close = text[after...].firstIndex(of: "`") {
                    let code = String(text[after..<close])
                    let attr = NSMutableAttributedString(string: code, attributes: [
                        .font: style.inlineCodeFont,
                        .foregroundColor: style.inlineCodeTextColor,
                        .backgroundColor: style.inlineCodeBackground
                    ])
                    if strike {
                        attr.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attr.length))
                    }
                    result.append(attr)
                    i = text.index(after: close)
                    continue
                }
            }

            // Link [label](url)
            if c == "[" {
                if let parsed = parseLink(text, at: i) {
                    let (label, url, end) = parsed
                    let labelAttr = buildInline(label, baseFont: baseFont, bold: bold, italic: italic, strike: strike)
                    // apply link color
                    labelAttr.addAttribute(.foregroundColor, value: style.linkColor, range: NSRange(location: 0, length: labelAttr.length))
                    labelAttr.addAttribute(.link, value: url, range: NSRange(location: 0, length: labelAttr.length))
                    labelAttr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: labelAttr.length))
                    result.append(labelAttr)
                    i = end
                    continue
                }
            }

            // Autolink <url>
            if c == "<" {
                if let (url, end) = parseAutolink(text, at: i) {
                    let s = url.absoluteString
                    let attr = NSMutableAttributedString(string: s, attributes: [
                        .font: font,
                        .foregroundColor: style.linkColor,
                        .link: url,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ])
                    if strike { attr.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attr.length)) }
                    result.append(attr)
                    i = end
                    continue
                }
            }

            // Bare URL
            if isURLStart(text, at: i) {
                if let (url, end) = parseBareURL(text, at: i) {
                    let s = url.absoluteString
                    let attr = NSMutableAttributedString(string: s, attributes: [
                        .font: font,
                        .foregroundColor: style.linkColor,
                        .link: url,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ])
                    if strike { attr.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attr.length)) }
                    result.append(attr)
                    i = end
                    continue
                }
            }

            // Emphasis: *** bold italic ***
            if textHasPrefix(text, i, "***") {
                if let close = findClosing(text, from: text.index(i, offsetBy: 3), delimiter: "***") {
                    let innerStart = text.index(i, offsetBy: 3)
                    let inner = String(text[innerStart..<close])
                    let innerAttr = buildInline(inner, baseFont: baseFont, bold: true, italic: true, strike: strike)
                    // color
                    innerAttr.addAttribute(.foregroundColor, value: (bold||italic) ? style.textColor : style.textColor, range: NSRange(location: 0, length: innerAttr.length))
                    result.append(innerAttr)
                    i = text.index(close, offsetBy: 3)
                    continue
                }
            }

            // ** bold **
            if textHasPrefix(text, i, "**") {
                if let close = findClosing(text, from: text.index(i, offsetBy: 2), delimiter: "**") {
                    let innerStart = text.index(i, offsetBy: 2)
                    let inner = String(text[innerStart..<close])
                    let innerAttr = buildInline(inner, baseFont: baseFont, bold: true, italic: italic, strike: strike)
                    innerAttr.addAttribute(.foregroundColor, value: style.textColor, range: NSRange(location: 0, length: innerAttr.length))
                    result.append(innerAttr)
                    i = text.index(close, offsetBy: 2)
                    continue
                }
            }

            // __ bold __
            if textHasPrefix(text, i, "__") {
                if let close = findClosing(text, from: text.index(i, offsetBy: 2), delimiter: "__") {
                    let innerStart = text.index(i, offsetBy: 2)
                    let inner = String(text[innerStart..<close])
                    let innerAttr = buildInline(inner, baseFont: baseFont, bold: true, italic: italic, strike: strike)
                    innerAttr.addAttribute(.foregroundColor, value: style.textColor, range: NSRange(location: 0, length: innerAttr.length))
                    result.append(innerAttr)
                    i = text.index(close, offsetBy: 2)
                    continue
                }
            }

            // ~~ strike ~~
            if textHasPrefix(text, i, "~~") {
                if let close = findClosing(text, from: text.index(i, offsetBy: 2), delimiter: "~~") {
                    let innerStart = text.index(i, offsetBy: 2)
                    let inner = String(text[innerStart..<close])
                    let innerAttr = buildInline(inner, baseFont: baseFont, bold: bold, italic: italic, strike: true)
                    innerAttr.addAttribute(.foregroundColor, value: style.textColor, range: NSRange(location: 0, length: innerAttr.length))
                    result.append(innerAttr)
                    i = text.index(close, offsetBy: 2)
                    continue
                }
            }

            // * italic *
            if c == "*" {
                // ensure not part of ** (handled above)
                let after = text.index(after: i)
                if let close = findClosing(text, from: after, delimiter: "*") {
                    // boundary: closing should not be adjacent? simple
                    let innerStart = after
                    let inner = String(text[innerStart..<close])
                    if !inner.isEmpty {
                        let innerAttr = buildInline(inner, baseFont: baseFont, bold: bold, italic: true, strike: strike)
                        innerAttr.addAttribute(.foregroundColor, value: style.textColor, range: NSRange(location: 0, length: innerAttr.length))
                        result.append(innerAttr)
                        i = text.index(after: close)
                        continue
                    }
                }
            }

            // _ italic _ with word boundary
            if c == "_" {
                let after = text.index(after: i)
                // opening boundary
                let prevOK = (i == text.startIndex) || !isWordChar(text[text.index(before: i)])
                let nextOK = after < n && !text[after].isWhitespace
                if prevOK && nextOK {
                    if let close = findClosingUnderscore(text, from: after) {
                        let innerStart = after
                        let inner = String(text[innerStart..<close])
                        if !inner.isEmpty {
                            let innerAttr = buildInline(inner, baseFont: baseFont, bold: bold, italic: true, strike: strike)
                            innerAttr.addAttribute(.foregroundColor, value: style.textColor, range: NSRange(location: 0, length: innerAttr.length))
                            result.append(innerAttr)
                            i = text.index(after: close)
                            continue
                        }
                    }
                }
            }

            // Default char
            appendRun(result, string: String(c), font: font, strike: strike, color: style.textColor)
            i = text.index(after: i)
        }

        return result
    }

    private func appendRun(_ result: NSMutableAttributedString, string: String, font: UIFont, strike: Bool, color: UIColor) {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        if strike {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        result.append(NSAttributedString(string: string, attributes: attrs))
    }

    // MARK: - Inline helpers

    private func parseLink(_ text: String, at i: String.Index) -> (String, URL, String.Index)? {
        guard text[i] == "[" else { return nil }
        guard let closeBracket = text[text.index(after: i)...].firstIndex(of: "]") else { return nil }
        let afterBracket = text.index(after: closeBracket)
        guard afterBracket < text.endIndex, text[afterBracket] == "(" else { return nil }
        guard let closeParen = text[text.index(after: afterBracket)...].firstIndex(of: ")") else { return nil }
        let label = String(text[text.index(after: i)..<closeBracket])
        let urlStr = String(text[text.index(after: afterBracket)..<closeParen]).trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: urlStr) else { return nil }
        let end = text.index(after: closeParen)
        return (label, url, end)
    }

    private func parseAutolink(_ text: String, at i: String.Index) -> (URL, String.Index)? {
        guard text[i] == "<" else { return nil }
        guard let close = text[text.index(after: i)...].firstIndex(of: ">") else { return nil }
        let inner = String(text[text.index(after: i)..<close])
        guard inner.hasPrefix("http://") || inner.hasPrefix("https://") || inner.hasPrefix("mailto:") else { return nil }
        guard let url = URL(string: inner) else { return nil }
        return (url, text.index(after: close))
    }

    private func isURLStart(_ text: String, at i: String.Index) -> Bool {
        let rest = text[i...]
        return rest.hasPrefix("http://") || rest.hasPrefix("https://")
    }

    private func parseBareURL(_ text: String, at i: String.Index) -> (URL, String.Index)? {
        var j = i
        while j < text.endIndex {
            let ch = text[j]
            if ch.isWhitespace { break }
            j = text.index(after: j)
        }
        var urlStr = String(text[i..<j])
        // trim trailing punctuation
        while let last = urlStr.last, ".,!?;:)".contains(last) {
            urlStr.removeLast()
            j = text.index(before: j)
        }
        guard let url = URL(string: urlStr) else { return nil }
        return (url, j)
    }

    private func textHasPrefix(_ text: String, _ i: String.Index, _ prefix: String) -> Bool {
        let end = text.index(i, offsetBy: prefix.count, limitedBy: text.endIndex)
        guard let e = end else { return false }
        return text[i..<e] == prefix[...]
    }

    private func findClosing(_ text: String, from start: String.Index, delimiter: String) -> String.Index? {
        // returns index of start of closing delimiter
        var search = start
        while search < text.endIndex {
            if text[search...].hasPrefix(delimiter) {
                return search
            }
            search = text.index(after: search)
        }
        return nil
    }

    private func findClosingUnderscore(_ text: String, from start: String.Index) -> String.Index? {
        var search = start
        while search < text.endIndex {
            if text[search] == "_" {
                let prev = text[text.index(before: search)]
                let nextIdx = text.index(after: search)
                let nextOK = (nextIdx >= text.endIndex) || !isWordChar(text[nextIdx]) // closing boundary
                // closing: prev not space, next not word
                if !prev.isWhitespace && nextOK {
                    return search
                }
            }
            search = text.index(after: search)
        }
        return nil
    }

    private func isWordChar(_ ch: Character) -> Bool {
        return ch.isLetter || ch.isNumber || ch == "_"
    }
}
