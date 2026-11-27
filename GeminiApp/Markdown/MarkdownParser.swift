import Foundation

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case codeBlock(language: String?, code: String)
    case bulletList(items: [(Int, String)])
    case orderedList(items: [(Int, Int, String)])
    case quote(text: String)
    case table(headers: [String], rows: [[String]])
    case horizontalRule
}

final class MarkdownParser {

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var i = 0
        let n = lines.count

        func flushParagraph(_ acc: inout [String]) {
            if !acc.isEmpty {
                blocks.append(.paragraph(text: acc.joined(separator: "\n")))
                acc.removeAll()
            }
        }

        var paragraphAcc: [String] = []

        while i < n {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // Blank line
            if trimmed.isEmpty {
                flushParagraph(&paragraphAcc)
                i += 1
                continue
            }

            // Fenced code block
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph(&paragraphAcc)
                let fence = trimmed.hasPrefix("```") ? "```" : "~~~"
                let info = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let language: String? = info.isEmpty ? nil : info.components(separatedBy: .whitespaces).first
                var codeLines: [String] = []
                i += 1
                while i < n {
                    let l = lines[i]
                    let t = l.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(fence) {
                        i += 1
                        break
                    }
                    codeLines.append(l)
                    i += 1
                }
                let code = codeLines.joined(separator: "\n")
                blocks.append(.codeBlock(language: language, code: code))
                continue
            }

            // Heading
            if trimmed.hasPrefix("#") {
                var level = 0
                for ch in trimmed {
                    if ch == "#" { level += 1 } else { break }
                }
                if level >= 1 && level <= 6 {
                    let rest = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                    flushParagraph(&paragraphAcc)
                    blocks.append(.heading(level: level, text: String(rest)))
                    i += 1
                    continue
                }
            }

            // Horizontal rule
            if isHorizontalRule(trimmed) {
                flushParagraph(&paragraphAcc)
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Table
            if i + 1 < n {
                let nextTrimmed = lines[i+1].trimmingCharacters(in: .whitespaces)
                if trimmed.contains("|") && isTableSeparator(nextTrimmed) {
                    flushParagraph(&paragraphAcc)
                    let headers = parseTableRow(trimmed)
                    i += 2
                    var rows: [[String]] = []
                    while i < n {
                        let rowLine = lines[i].trimmingCharacters(in: .whitespaces)
                        if rowLine.isEmpty || !rowLine.contains("|") { break }
                        rows.append(parseTableRow(rowLine))
                        i += 1
                    }
                    blocks.append(.table(headers: headers, rows: rows))
                    continue
                }
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                flushParagraph(&paragraphAcc)
                var quoteLines: [String] = []
                while i < n {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(">") {
                        var line = t
                        if line.hasPrefix("> ") { line = String(line.dropFirst(2)) }
                        else { line = String(line.dropFirst(1)).trimmingCharacters(in: .whitespaces) }
                        quoteLines.append(line)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.quote(text: quoteLines.joined(separator: "\n")))
                continue
            }

            // Bullet list
            if let _ = parseBulletRaw(raw) {
                flushParagraph(&paragraphAcc)
                var items: [(Int, String)] = []
                while i < n {
                    let r = lines[i]
                    let t = r.trimmingCharacters(in: .whitespaces)
                    if t.isEmpty {
                        // End list when blank line is followed by a line indented < 4 spaces
                        // (or a non-list line). A line indented >= 4 spaces may continue.
                        var j = i
                        while j < n && lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                        if j < n && leadingSpaces(lines[j]) >= 4 && parseBulletRaw(lines[j]) != nil {
                            i = j
                            continue
                        }
                        break
                    }
                    if let m = parseBulletRaw(r) {
                        items.append(m)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            // Ordered list
            if let _ = parseOrderedRaw(raw) {
                flushParagraph(&paragraphAcc)
                var items: [(Int, Int, String)] = []
                while i < n {
                    let r = lines[i]
                    let t = r.trimmingCharacters(in: .whitespaces)
                    if t.isEmpty {
                        var j = i
                        while j < n && lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                        if j < n && leadingSpaces(lines[j]) >= 4 && parseOrderedRaw(lines[j]) != nil {
                            i = j
                            continue
                        }
                        break
                    }
                    if let m = parseOrderedRaw(r) {
                        items.append(m)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            // Paragraph: strip up to 3 leading spaces from the line.
            var paraLine = raw
            var stripped = 0
            while stripped < 3 && paraLine.hasPrefix(" ") {
                paraLine.removeFirst()
                stripped += 1
            }
            paragraphAcc.append(paraLine)
            i += 1
        }

        flushParagraph(&paragraphAcc)
        return blocks
    }

    // MARK: - helpers

    private static func isHorizontalRule(_ t: String) -> Bool {
        let s = t.replacingOccurrences(of: " ", with: "")
        if s.count < 3 { return false }
        if s.allSatisfy({ $0 == "-" }) { return true }
        if s.allSatisfy({ $0 == "*" }) { return true }
        if s.allSatisfy({ $0 == "_" }) { return true }
        return false
    }

    private static func parseTableRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s = String(s.dropFirst()) }
        if s.hasSuffix("|") { s = String(s.dropLast()) }
        return s.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespaces)
        guard s.contains("|") else { return false }
        let stripped = s.replacingOccurrences(of: " ", with: "")
        for ch in stripped {
            if "|-:".contains(ch) == false { return false }
        }
        return stripped.contains("-")
    }

    private static func leadingSpaces(_ raw: String) -> Int {
        var spaces = 0
        for ch in raw {
            if ch == " " { spaces += 1 }
            else if ch == "\t" { spaces += 4 }
            else { break }
        }
        return spaces
    }

    private static func indentLevel(_ raw: String) -> Int {
        var spaces = 0
        for ch in raw {
            if ch == " " { spaces += 1 }
            else if ch == "\t" { spaces += 4 }
            else { break }
        }
        return spaces / 2
    }

    private static func parseBulletRaw(_ raw: String) -> (Int, String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // marker
        var rest = trimmed
        var markerFound = false
        for m in ["- ", "* ", "+ "] {
            if trimmed.hasPrefix(m) {
                rest = String(trimmed.dropFirst(m.count))
                markerFound = true
                break
            }
        }
        // also handle "-\t"? 
        if !markerFound {
            // maybe marker followed by multiple spaces
            if trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("+") {
                let after = trimmed.dropFirst()
                if after.hasPrefix(" ") {
                    rest = after.trimmingCharacters(in: .whitespaces)
                    markerFound = true
                }
            }
        }
        if !markerFound { return nil }
        let level = indentLevel(raw)
        // task list conversion
        var text = rest
        if text.hasPrefix("[ ] ") {
            text = "☐ " + String(text.dropFirst(4))
        } else if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            text = "☑ " + String(text.dropFirst(4))
        }
        return (level, text)
    }

    private static func parseOrderedRaw(_ raw: String) -> (Int, Int, String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // number. text
        var idx = trimmed.startIndex
        var digits = ""
        while idx < trimmed.endIndex && trimmed[idx].isNumber {
            digits.append(trimmed[idx])
            idx = trimmed.index(after: idx)
        }
        guard !digits.isEmpty, idx < trimmed.endIndex, trimmed[idx] == "." else { return nil }
        idx = trimmed.index(after: idx)
        if idx >= trimmed.endIndex || !trimmed[idx].isWhitespace { return nil }
        let text = trimmed[idx...].trimmingCharacters(in: .whitespaces)
        let number = Int(digits) ?? 0
        let level = indentLevel(raw)
        return (number, level, text)
    }
}
