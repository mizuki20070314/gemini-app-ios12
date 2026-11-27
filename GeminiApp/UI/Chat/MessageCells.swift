import UIKit

final class UserMessageCell: UITableViewCell {
    static let reuseId = "UserMessageCell"

    private let bubble = UIView()
    private let stack = UIStackView()
    private let thumbStack = UIStackView()
    private let messageLabel = UILabel()

    var onImageTap: ((UIImage) -> Void)?
    private var displayedImages: [UIImage] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        bubble.layer.cornerRadius = 18
        bubble.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubble)

        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(stack)

        thumbStack.axis = .horizontal
        thumbStack.spacing = 6
        thumbStack.alignment = .center
        stack.addArrangedSubview(thumbStack)

        messageLabel.numberOfLines = 0
        messageLabel.font = UIFont.systemFont(ofSize: 16)
        stack.addArrangedSubview(messageLabel)

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 56),

            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(message: ChatMessage) {
        let t = Theme.current
        bubble.backgroundColor = t.userBubble
        messageLabel.textColor = t.textPrimary
        messageLabel.text = message.text
        messageLabel.isHidden = message.text.isEmpty

        for v in thumbStack.arrangedSubviews {
            thumbStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        displayedImages.removeAll()
        thumbStack.isHidden = message.attachments.isEmpty

        for att in message.attachments {
            if att.isImage, let img = ConversationStore.shared.mediaImage(fileName: att.localFileName) {
                let idx = displayedImages.count
                displayedImages.append(img)
                let btn = UIButton(type: .custom)
                btn.tag = idx
                btn.setImage(img, for: .normal)
                btn.imageView?.contentMode = .scaleAspectFill
                btn.layer.cornerRadius = 10
                btn.clipsToBounds = true
                btn.translatesAutoresizingMaskIntoConstraints = false
                btn.widthAnchor.constraint(equalToConstant: 80).isActive = true
                btn.heightAnchor.constraint(equalToConstant: 80).isActive = true
                btn.addTarget(self, action: #selector(thumbTapped(_:)), for: .touchUpInside)
                thumbStack.addArrangedSubview(btn)
            } else {
                let pill = UILabel()
                pill.text = " 📎 \(att.fileName) "
                pill.font = UIFont.systemFont(ofSize: 12)
                pill.textColor = t.textSecondary
                pill.backgroundColor = t.background
                pill.layer.cornerRadius = 8
                pill.clipsToBounds = true
                thumbStack.addArrangedSubview(pill)
            }
        }
    }

    @objc private func thumbTapped(_ sender: UIButton) {
        guard sender.tag < displayedImages.count else { return }
        onImageTap?(displayedImages[sender.tag])
    }
}

final class AssistantMessageCell: UITableViewCell {
    static let reuseId = "AssistantMessageCell"

    private let headerRow = UIView()
    private let sparkView = GeminiSparkView()
    private let modelLabel = UILabel()

    private let bodyStack = UIStackView()
    private let thinkingView = ThinkingView()
    private var markdownView: MarkdownContentView?
    private let mediaStack = UIStackView()
    private let citationScroll = UIScrollView()
    private let citationStack = UIStackView()
    private let errorLabel = UILabel()
    private let actionRow = UIStackView()

    private var currentText = ""
    private var displayedImages: [UIImage] = []
    private var currentCitations: [CitationItem] = []

    var onCopy: ((String) -> Void)?
    var onRetry: (() -> Void)?
    var onShare: ((String) -> Void)?
    var onToggleThinking: (() -> Void)?
    var onImageTap: ((UIImage) -> Void)?
    var onCitationTap: ((URL) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        headerRow.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerRow)

        sparkView.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(sparkView)

        modelLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        modelLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(modelLabel)

        bodyStack.axis = .vertical
        bodyStack.spacing = 8
        bodyStack.alignment = .fill
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bodyStack)

        thinkingView.onToggle = { [weak self] in self?.onToggleThinking?() }
        bodyStack.addArrangedSubview(thinkingView)

        mediaStack.axis = .vertical
        mediaStack.spacing = 8
        mediaStack.alignment = .leading
        bodyStack.addArrangedSubview(mediaStack)

        citationScroll.showsHorizontalScrollIndicator = false
        citationScroll.translatesAutoresizingMaskIntoConstraints = false
        citationScroll.heightAnchor.constraint(equalToConstant: 30).isActive = true
        citationStack.axis = .horizontal
        citationStack.spacing = 6
        citationStack.translatesAutoresizingMaskIntoConstraints = false
        citationScroll.addSubview(citationStack)
        NSLayoutConstraint.activate([
            citationStack.topAnchor.constraint(equalTo: citationScroll.topAnchor),
            citationStack.leadingAnchor.constraint(equalTo: citationScroll.leadingAnchor),
            citationStack.trailingAnchor.constraint(equalTo: citationScroll.trailingAnchor),
            citationStack.bottomAnchor.constraint(equalTo: citationScroll.bottomAnchor),
            citationStack.heightAnchor.constraint(equalTo: citationScroll.heightAnchor),
        ])
        bodyStack.addArrangedSubview(citationScroll)

        errorLabel.numberOfLines = 0
        errorLabel.font = UIFont.systemFont(ofSize: 14)
        bodyStack.addArrangedSubview(errorLabel)

        actionRow.axis = .horizontal
        actionRow.spacing = 12
        actionRow.alignment = .center
        bodyStack.addArrangedSubview(actionRow)

        NSLayoutConstraint.activate([
            headerRow.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            headerRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            headerRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            headerRow.heightAnchor.constraint(equalToConstant: 22),

            sparkView.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            sparkView.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            sparkView.widthAnchor.constraint(equalToConstant: 18),
            sparkView.heightAnchor.constraint(equalToConstant: 18),

            modelLabel.leadingAnchor.constraint(equalTo: sparkView.trailingAnchor, constant: 6),
            modelLabel.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),

            bodyStack.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 6),
            bodyStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            bodyStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            bodyStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(message: ChatMessage, isStreaming: Bool, thinkingExpanded: Bool) {
        let t = Theme.current
        currentText = message.text
        modelLabel.text = message.modelName ?? "Gemini"
        modelLabel.textColor = t.textSecondary

        if isStreaming {
            sparkView.startPulsing()
        } else {
            sparkView.stopPulsing()
        }

        // Thinking
        if let think = message.thinking, !think.isEmpty {
            thinkingView.isHidden = false
            thinkingView.configure(thinking: think, isStreaming: isStreaming && message.text.isEmpty, expanded: thinkingExpanded)
        } else {
            thinkingView.isHidden = true
        }

        // Markdown content
        let mdStyle = MarkdownStyle.standard(
            textColor: t.textPrimary,
            secondary: t.textSecondary,
            accent: t.accent,
            codeBackground: t.codeBackground,
            isDark: t.isDark
        )
        if let existing = markdownView {
            existing.removeFromSuperview()
            bodyStack.removeArrangedSubview(existing)
        }
        if !message.text.isEmpty {
            let md = MarkdownContentView(style: mdStyle)
            md.update(markdown: message.text)
            bodyStack.insertArrangedSubview(md, at: 1)
            markdownView = md
        } else {
            markdownView = nil
        }

        // Generated Images
        for v in mediaStack.arrangedSubviews {
            mediaStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        displayedImages.removeAll()
        mediaStack.isHidden = message.generatedMedia.isEmpty
        for m in message.generatedMedia {
            if let fname = m.localFileName, let img = ConversationStore.shared.mediaImage(fileName: fname) {
                let idx = displayedImages.count
                displayedImages.append(img)
                let btn = UIButton(type: .custom)
                btn.tag = idx
                btn.setImage(img, for: .normal)
                btn.imageView?.contentMode = .scaleAspectFit
                btn.layer.cornerRadius = 12
                btn.clipsToBounds = true
                btn.backgroundColor = t.surface
                btn.translatesAutoresizingMaskIntoConstraints = false
                let maxW = min(UIScreen.main.bounds.width - 28, 280)
                let ratio = img.size.width > 0 ? (img.size.height / img.size.width) : 1.0
                btn.widthAnchor.constraint(equalToConstant: maxW).isActive = true
                btn.heightAnchor.constraint(equalToConstant: min(maxW * ratio, 300)).isActive = true
                btn.addTarget(self, action: #selector(mediaImageTapped(_:)), for: .touchUpInside)
                mediaStack.addArrangedSubview(btn)
            } else {
                let lbl = UILabel()
                lbl.text = "画像を読み込み中..."
                lbl.font = UIFont.systemFont(ofSize: 13)
                lbl.textColor = t.textSecondary
                mediaStack.addArrangedSubview(lbl)
            }
        }

        // Citations
        for v in citationStack.arrangedSubviews {
            citationStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        currentCitations = message.citations
        citationScroll.isHidden = message.citations.isEmpty
        for (idx, c) in message.citations.prefix(8).enumerated() {
            let btn = UIButton(type: .system)
            btn.tag = idx
            let label = c.publisher?.isEmpty == false ? c.publisher! : c.title
            btn.setTitle("🌐 \(label.prefix(24))", for: .normal)
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .medium)
            btn.setTitleColor(t.accent, for: .normal)
            btn.backgroundColor = t.accentSoft
            btn.layer.cornerRadius = 12
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            btn.addTarget(self, action: #selector(citationTapped(_:)), for: .touchUpInside)
            citationStack.addArrangedSubview(btn)
        }

        // Error
        if let err = message.errorMessage, !err.isEmpty {
            errorLabel.isHidden = false
            errorLabel.text = err
            errorLabel.textColor = t.destructive
        } else {
            errorLabel.isHidden = true
        }

        // Action row
        for v in actionRow.arrangedSubviews {
            actionRow.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        actionRow.isHidden = isStreaming
        if !isStreaming {
            let copyBtn = makeActionBtn(icon: .copy, action: #selector(copyTapped))
            let retryBtn = makeActionBtn(icon: .retry, action: #selector(retryTapped))
            let shareBtn = makeActionBtn(icon: .share, action: #selector(shareTapped))
            actionRow.addArrangedSubview(copyBtn)
            actionRow.addArrangedSubview(retryBtn)
            actionRow.addArrangedSubview(shareBtn)
            let spacer = UIView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            actionRow.addArrangedSubview(spacer)
        }
    }

    private func makeActionBtn(icon: IconName, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(Icons.image(icon, size: 16, color: Theme.current.textSecondary), for: .normal)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 32).isActive = true
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    @objc private func copyTapped() { onCopy?(currentText) }
    @objc private func retryTapped() { onRetry?() }
    @objc private func shareTapped() { onShare?(currentText) }

    @objc private func mediaImageTapped(_ sender: UIButton) {
        guard sender.tag < displayedImages.count else { return }
        onImageTap?(displayedImages[sender.tag])
    }

    @objc private func citationTapped(_ sender: UIButton) {
        guard sender.tag < currentCitations.count,
              let url = URL(string: currentCitations[sender.tag].url) else { return }
        onCitationTap?(url)
    }
}
