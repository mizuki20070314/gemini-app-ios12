import UIKit

final class CodeBlockView: UIView {

    private let containerView = UIView()
    private let headerView = UIView()
    private let languageLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let codeLabel = UILabel()

    private var currentCode: String = ""
    private var resetTitleWorkItem: DispatchWorkItem?
    private var measuredHeight: CGFloat = 60

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        setup()
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: measuredHeight)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        containerView.layer.cornerRadius = 8
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor.gray.withAlphaComponent(0.3).cgColor
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        headerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(headerView)

        languageLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        languageLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(languageLabel)

        copyButton.setTitle("コピー", for: .normal)
        copyButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        headerView.addSubview(copyButton)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        containerView.addSubview(scrollView)

        codeLabel.numberOfLines = 0
        codeLabel.lineBreakMode = .byClipping
        codeLabel.translatesAutoresizingMaskIntoConstraints = true
        scrollView.addSubview(codeLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            headerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 28),

            languageLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            languageLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            copyButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            copyButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
    }

    func configure(language: String?, code: String, style: MarkdownStyle) {
        currentCode = code
        let lang = language ?? ""
        languageLabel.text = lang.isEmpty ? "code" : lang
        languageLabel.textColor = style.secondaryTextColor

        containerView.backgroundColor = style.codeBlockBackground
        containerView.layer.borderColor = style.secondaryTextColor.withAlphaComponent(0.3).cgColor
        headerView.backgroundColor = style.codeBlockBackground.withAlphaComponent(0.8)
        copyButton.setTitleColor(style.linkColor, for: .normal)

        let isDark = isDarkColor(style.codeBlockBackground)
        codeLabel.attributedText = highlight(code: code, language: language, style: style, isDark: isDark)
        codeLabel.font = style.codeFont

        // compute width via boundingRect
        let attr = codeLabel.attributedText ?? NSAttributedString(string: code, attributes: [.font: style.codeFont])
        let maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let rect = attr.boundingRect(with: maxSize, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let w = ceil(rect.width) + 16
        let h = ceil(rect.height) + 16
        codeLabel.frame = CGRect(x: 8, y: 8, width: max(w - 16, 0), height: max(h - 16, 0))
        scrollView.contentSize = CGSize(width: w, height: h)
        measuredHeight = h + 28
        invalidateIntrinsicContentSize()
    }

    @objc private func copyTapped() {
        UIPasteboard.general.string = currentCode
        copyButton.setTitle("コピーしました", for: .normal)
        resetTitleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.copyButton.setTitle("コピー", for: .normal)
        }
        resetTitleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: - Syntax highlighting

    private func isDarkColor(_ color: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        return lum < 0.5
    }

    private func highlight(code: String, language: String?, style: MarkdownStyle, isDark: Bool) -> NSAttributedString {
        let baseColor = style.codeBlockTextColor
        let result = NSMutableAttributedString(string: code, attributes: [.font: style.codeFont, .foregroundColor: baseColor])
        let lang = (language ?? "").lowercased()
        let keywords = keywordsFor(lang)
        if keywords.isEmpty && lang != "json" && lang != "html" { /* still highlight strings/numbers/comments for unknown? */ }

        // Palettes
        let keywordColor: UIColor
        let stringColor: UIColor
        let commentColor: UIColor
        let numberColor: UIColor
        if isDark {
            keywordColor = UIColor(red: 0.78, green: 0.55, blue: 0.95, alpha: 1)
            stringColor = UIColor(red: 0.86, green: 0.65, blue: 0.50, alpha: 1)
            commentColor = UIColor(red: 0.55, green: 0.65, blue: 0.55, alpha: 1)
            numberColor = UIColor(red: 0.65, green: 0.85, blue: 0.65, alpha: 1)
        } else {
            keywordColor = UIColor(red: 0.60, green: 0.15, blue: 0.65, alpha: 1)
            stringColor = UIColor(red: 0.75, green: 0.25, blue: 0.15, alpha: 1)
            commentColor = UIColor(red: 0.35, green: 0.55, blue: 0.35, alpha: 1)
            numberColor = UIColor(red: 0.15, green: 0.45, blue: 0.65, alpha: 1)
        }

        // Apply comments (line)
        applyLineComments(code: code, result: result, color: commentColor, markers: lineCommentMarkers(lang))
        // Apply block comments /* */ for c-style
        if ["swift","js","ts","javascript","typescript","java","c","cpp","c++"].contains(lang) {
            applyBlockComments(code: code, result: result, color: commentColor)
        }
        // Apply strings
        applyStrings(code: code, result: result, color: stringColor)
        // Apply numbers
        applyRegex(code: code, result: result, pattern: "\\b\\d+(\\.\\d+)?\\b", color: numberColor)
        // Apply keywords
        if !keywords.isEmpty {
            for kw in keywords {
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: kw) + "\\b"
                applyRegex(code: code, result: result, pattern: pattern, color: keywordColor)
            }
        }
        // HTML tags
        if lang == "html" {
            applyRegex(code: code, result: result, pattern: "</?[a-zA-Z][^>]*>", color: keywordColor)
        }

        return result
    }

    private func keywordsFor(_ lang: String) -> [String] {
        switch lang {
        case "swift":
            return ["import","func","let","var","if","else","guard","return","class","struct","enum","protocol","extension","public","private","internal","static","self","Self","true","false","nil","for","while","switch","case","default","break","continue","throw","throws","try","catch","do","in","where","as","is","init","deinit","super","weak","strong","lazy","override","final","open","associatedtype","typealias","some","any"]
        case "python","py":
            return ["def","class","import","from","as","if","elif","else","for","while","return","True","False","None","and","or","not","in","is","lambda","with","try","except","finally","raise","pass","break","continue","yield","global","nonlocal","async","await"]
        case "js","javascript","ts","typescript":
            return ["function","const","let","var","if","else","return","class","extends","import","export","from","default","new","this","true","false","null","undefined","for","while","switch","case","break","continue","try","catch","finally","throw","async","await","typeof","instanceof","in","of","interface","type","enum","implements","public","private","protected","readonly","static","get","set"]
        case "java":
            return ["public","private","protected","static","final","class","interface","extends","implements","new","return","if","else","for","while","switch","case","break","continue","try","catch","finally","throw","throws","import","package","void","int","long","double","float","boolean","char","byte","short","true","false","null","this","super","abstract","synchronized","volatile","transient","native","strictfp"]
        case "c","cpp","c++":
            return ["int","float","double","char","void","if","else","for","while","switch","case","break","continue","return","struct","class","public","private","protected","const","static","extern","include","define","true","false","NULL","nullptr","new","delete","template","typename","namespace","using","virtual","override","try","catch","throw"]
        case "bash","sh","shell":
            return ["if","then","else","fi","for","do","done","while","case","esac","function","return","export","local","echo","exit","in"]
        case "json":
            return ["true","false","null"]
        default:
            return []
        }
    }

    private func lineCommentMarkers(_ lang: String) -> [String] {
        switch lang {
        case "python","py","bash","sh","shell","ruby":
            return ["#"]
        case "html":
            return []
        default:
            return ["//"]
        }
    }

    private func applyLineComments(code: String, result: NSMutableAttributedString, color: UIColor, markers: [String]) {
        guard !markers.isEmpty else { return }
        let lines = code.components(separatedBy: "\n")
        var location = 0
        for line in lines {
            for marker in markers {
                if let range = line.range(of: marker) {
                    let start = line.distance(from: line.startIndex, to: range.lowerBound)
                    let len = line.count - start
                    let nsRange = NSRange(location: location + start, length: len)
                    result.addAttribute(.foregroundColor, value: color, range: nsRange)
                    break
                }
            }
            location += line.count + 1
        }
    }

    private func applyBlockComments(code: String, result: NSMutableAttributedString, color: UIColor) {
        var searchRange = code.startIndex..<code.endIndex
        while let start = code.range(of: "/*", range: searchRange) {
            if let end = code.range(of: "*/", range: start.upperBound..<code.endIndex) {
                let r = NSRange(location: code.distance(from: code.startIndex, to: start.lowerBound),
                                length: code.distance(from: start.lowerBound, to: end.upperBound))
                result.addAttribute(.foregroundColor, value: color, range: r)
                searchRange = end.upperBound..<code.endIndex
            } else {
                break
            }
        }
    }

    private func applyStrings(code: String, result: NSMutableAttributedString, color: UIColor) {
        // double and single quoted strings (simple, no escapes handling beyond basic)
        let patterns = ["\"(?:[^\"\\\\]|\\\\.)*\"", "'(?:[^'\\\\]|\\\\.)*'"]
        for p in patterns {
            applyRegex(code: code, result: result, pattern: p, color: color)
        }
    }

    private func applyRegex(code: String, result: NSMutableAttributedString, pattern: String, color: UIColor) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let nsRange = NSRange(location: 0, length: (code as NSString).length)
        for match in regex.matches(in: code, options: [], range: nsRange) {
            result.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
