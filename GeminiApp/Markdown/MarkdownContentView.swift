import UIKit

final class MarkdownContentView: UIView {

    private let renderer: MarkdownRenderer
    private let stackView = UIStackView()
    private var blockViews: [UIView] = []
    private var currentBlocks: [RenderedBlock] = []

    init(style: MarkdownStyle) {
        self.renderer = MarkdownRenderer(style: style)
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        // style unknown; use standard dark? but avoid. Require programmatic.
        self.renderer = MarkdownRenderer(style: MarkdownStyle.standard(textColor: .black, secondary: .gray, accent: .blue, codeBackground: .lightGray, isDark: false))
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    var style: MarkdownStyle { renderer.style }

    func update(markdown: String) {
        let newBlocks = renderer.renderBlocks(markdown)

        // Determine if structure (count + types) unchanged
        if newBlocks.count == currentBlocks.count && sameTypes(newBlocks, currentBlocks) {
            // reuse; update only last block
            if let lastView = blockViews.last, let lastBlock = newBlocks.last {
                updateView(lastView, with: lastBlock)
            }
            currentBlocks = newBlocks
            return
        }

        // Rebuild
        for v in blockViews { v.removeFromSuperview() }
        blockViews.removeAll()
        for block in newBlocks {
            let v = makeView(for: block)
            blockViews.append(v)
            stackView.addArrangedSubview(v)
        }
        currentBlocks = newBlocks
    }

    private func sameTypes(_ a: [RenderedBlock], _ b: [RenderedBlock]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) {
            if typeKey(x) != typeKey(y) { return false }
        }
        return true
    }

    private func typeKey(_ block: RenderedBlock) -> Int {
        switch block {
        case .text: return 0
        case .code: return 1
        case .table: return 2
        }
    }

    private func makeView(for block: RenderedBlock) -> UIView {
        switch block {
        case .text(let attr):
            let tv = UITextView()
            tv.isScrollEnabled = false
            tv.isEditable = false
            tv.isSelectable = true
            tv.contentInset = .zero
            tv.textContainerInset = .zero
            tv.textContainer.lineFragmentPadding = 0
            tv.dataDetectorTypes = .link
            tv.attributedText = attr
            tv.backgroundColor = .clear
            return tv
        case .code(let lang, let code):
            let v = CodeBlockView()
            v.configure(language: lang, code: code, style: renderer.style)
            return v
        case .table(let headers, let rows):
            return makeTableView(headers: headers, rows: rows, style: renderer.style)
        }
    }

    private func updateView(_ view: UIView, with block: RenderedBlock) {
        switch block {
        case .text(let attr):
            if let tv = view as? UITextView {
                tv.attributedText = attr
            }
        case .code(let lang, let code):
            if let cv = view as? CodeBlockView {
                cv.configure(language: lang, code: code, style: renderer.style)
            }
        case .table(let headers, let rows):
            updateTableView(view, headers: headers, rows: rows, style: renderer.style)
        }
    }

    // MARK: - Table view

    private func makeTableView(headers: [String], rows: [[String]], style: MarkdownStyle) -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = true
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(container)
        // Build grid
        populateGrid(container: container, scroll: scroll, headers: headers, rows: rows, style: style)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let h = container.frame.height
        scroll.heightAnchor.constraint(equalToConstant: max(h, 24)).isActive = true
        return scroll
    }

    private func populateGrid(container: UIView, scroll: UIScrollView, headers: [String], rows: [[String]], style: MarkdownStyle) {
        // remove existing
        for v in container.subviews { v.removeFromSuperview() }
        let allRows = [headers] + rows
        let colCount = headers.count
        var colWidths: [CGFloat] = Array(repeating: 0, count: colCount)
        let font = style.codeFont
        for row in allRows {
            for c in 0..<colCount {
                let val = c < row.count ? row[c] : ""
                let size = (val as NSString).size(withAttributes: [.font: font])
                colWidths[c] = max(colWidths[c], size.width + 12)
            }
        }
        let rowHeight: CGFloat = 24
        var y: CGFloat = 0
        for (ri, row) in allRows.enumerated() {
            var x: CGFloat = 0
            for c in 0..<colCount {
                let val = c < row.count ? row[c] : ""
                let lbl = UILabel()
                lbl.font = font
                lbl.text = val
                lbl.textColor = (ri == 0) ? style.linkColor : style.textColor
                if ri == 0 { lbl.font = UIFont(name: "Menlo-Bold", size: font.pointSize) ?? font }
                lbl.frame = CGRect(x: x, y: y, width: colWidths[c], height: rowHeight)
                lbl.layer.borderWidth = 0.5
                lbl.layer.borderColor = style.secondaryTextColor.withAlphaComponent(0.3).cgColor
                container.addSubview(lbl)
                x += colWidths[c]
            }
            y += rowHeight
        }
        container.frame = CGRect(x: 0, y: 0, width: colWidths.reduce(0,+), height: y)
        scroll.contentSize = container.frame.size
    }

    private func updateTableView(_ view: UIView, headers: [String], rows: [[String]], style: MarkdownStyle) {
        guard let scroll = view as? UIScrollView else { return }
        guard let container = scroll.subviews.first else { return }
        populateGrid(container: container, scroll: scroll, headers: headers, rows: rows, style: style)
    }
}
