import UIKit

final class ComposerView: UIView, UITextViewDelegate {
    private let cardView = UIView()
    private let attachmentScroll = UIScrollView()
    private let attachmentStack = UIStackView()
    private var attachmentHeightConstraint: NSLayoutConstraint!

    let textView = UITextView()
    private let placeholderLabel = UILabel()
    private var textHeightConstraint: NSLayoutConstraint!

    private let toolbarView = UIView()
    private let attachButton = UIButton(type: .system)
    private let modelButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)

    var pendingAttachments: [MessageAttachment] = [] {
        didSet { rebuildAttachmentStrip() }
    }

    var isStreaming: Bool = false {
        didSet { updateSendButton() }
    }

    var onSend: ((String) -> Void)?
    var onStop: (() -> Void)?
    var onAttachTapped: (() -> Void)?
    var onModelTapped: (() -> Void)?
    var onRemoveAttachment: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: Theme.didChange, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setup() {
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        cardView.layer.cornerRadius = 22
        cardView.layer.borderWidth = 1
        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.setContentHuggingPriority(.required, for: .vertical)
        cardView.setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(cardView)

        attachmentScroll.showsHorizontalScrollIndicator = false
        attachmentScroll.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(attachmentScroll)

        attachmentStack.axis = .horizontal
        attachmentStack.spacing = 8
        attachmentStack.alignment = .center
        attachmentStack.translatesAutoresizingMaskIntoConstraints = false
        attachmentScroll.addSubview(attachmentStack)

        textView.delegate = self
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 6, right: 10)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(textView)

        placeholderLabel.text = "Gemini に相談する..."
        placeholderLabel.font = UIFont.systemFont(ofSize: 16)
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(placeholderLabel)

        toolbarView.backgroundColor = .clear
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(toolbarView)

        attachButton.translatesAutoresizingMaskIntoConstraints = false
        attachButton.addTarget(self, action: #selector(attachTapped), for: .touchUpInside)
        toolbarView.addSubview(attachButton)

        modelButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        modelButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        modelButton.layer.cornerRadius = 12
        modelButton.translatesAutoresizingMaskIntoConstraints = false
        modelButton.addTarget(self, action: #selector(modelTapped), for: .touchUpInside)
        toolbarView.addSubview(modelButton)

        sendButton.layer.cornerRadius = 17
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        toolbarView.addSubview(sendButton)

        attachmentHeightConstraint = attachmentScroll.heightAnchor.constraint(equalToConstant: 0)
        attachmentHeightConstraint.priority = .required
        textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: 40)
        textHeightConstraint.priority = .required

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            attachmentScroll.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 4),
            attachmentScroll.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            attachmentScroll.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            attachmentHeightConstraint,

            attachmentStack.topAnchor.constraint(equalTo: attachmentScroll.topAnchor),
            attachmentStack.leadingAnchor.constraint(equalTo: attachmentScroll.leadingAnchor),
            attachmentStack.trailingAnchor.constraint(equalTo: attachmentScroll.trailingAnchor),
            attachmentStack.bottomAnchor.constraint(equalTo: attachmentScroll.bottomAnchor),
            attachmentStack.heightAnchor.constraint(equalTo: attachmentScroll.heightAnchor),

            textView.topAnchor.constraint(equalTo: attachmentScroll.bottomAnchor, constant: 2),
            textView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 4),
            textView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -4),
            textHeightConstraint,

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 10),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 15),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -15),

            toolbarView.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 2),
            toolbarView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            toolbarView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -6),
            toolbarView.heightAnchor.constraint(equalToConstant: 38),

            attachButton.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: 6),
            attachButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: 36),
            attachButton.heightAnchor.constraint(equalToConstant: 36),

            modelButton.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 4),
            modelButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            modelButton.trailingAnchor.constraint(lessThanOrEqualTo: sendButton.leadingAnchor, constant: -8),

            sendButton.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: -8),
            sendButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 34),
            sendButton.heightAnchor.constraint(equalToConstant: 34),
        ])

        setModelTitle("Auto ⌄")
        updateSendButton()
    }

    func setModelTitle(_ title: String) {
        modelButton.setTitle(title, for: .normal)
    }

    func clearText() {
        textView.text = ""
        textViewDidChange(textView)
    }

    @objc func applyTheme() {
        let t = Theme.current
        backgroundColor = t.background
        cardView.backgroundColor = t.composerBackground
        cardView.layer.borderColor = t.border.cgColor
        textView.textColor = t.textPrimary
        textView.tintColor = t.accent
        textView.keyboardAppearance = t.keyboardAppearance
        placeholderLabel.textColor = t.textTertiary
        attachButton.setImage(Icons.image(.plus, size: 20, color: t.textPrimary), for: .normal)
        modelButton.backgroundColor = t.background
        modelButton.setTitleColor(t.textSecondary, for: .normal)
        updateSendButton()
    }

    private func updateSendButton() {
        let t = Theme.current
        let hasText = !(textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || textView.markedTextRange != nil
        let hasContent = hasText || !pendingAttachments.isEmpty
        if isStreaming {
            sendButton.backgroundColor = t.destructive
            sendButton.setImage(Icons.image(.stop, size: 16, color: .white), for: .normal)
            sendButton.isEnabled = true
        } else {
            sendButton.backgroundColor = hasContent ? t.sendButton : t.sendButtonDisabled
            sendButton.setImage(Icons.image(.send, size: 18, color: t.onAccent), for: .normal)
            sendButton.isEnabled = hasContent
        }
    }

    private func rebuildAttachmentStrip() {
        for v in attachmentStack.arrangedSubviews {
            attachmentStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        attachmentHeightConstraint.constant = pendingAttachments.isEmpty ? 0 : 62
        let t = Theme.current
        for (idx, att) in pendingAttachments.enumerated() {
            let box = UIView()
            box.layer.cornerRadius = 10
            box.layer.borderWidth = 1
            box.layer.borderColor = t.border.cgColor
            box.backgroundColor = t.background
            box.clipsToBounds = true
            box.translatesAutoresizingMaskIntoConstraints = false
            box.widthAnchor.constraint(equalToConstant: 56).isActive = true
            box.heightAnchor.constraint(equalToConstant: 56).isActive = true

            if att.isImage, let img = ConversationStore.shared.mediaImage(fileName: att.localFileName) {
                let iv = UIImageView(image: img)
                iv.contentMode = .scaleAspectFill
                iv.translatesAutoresizingMaskIntoConstraints = false
                box.addSubview(iv)
                NSLayoutConstraint.activate([
                    iv.topAnchor.constraint(equalTo: box.topAnchor),
                    iv.leadingAnchor.constraint(equalTo: box.leadingAnchor),
                    iv.trailingAnchor.constraint(equalTo: box.trailingAnchor),
                    iv.bottomAnchor.constraint(equalTo: box.bottomAnchor),
                ])
            } else {
                let lbl = UILabel()
                lbl.text = att.fileName
                lbl.font = UIFont.systemFont(ofSize: 10)
                lbl.textColor = t.textPrimary
                lbl.numberOfLines = 2
                lbl.textAlignment = .center
                lbl.translatesAutoresizingMaskIntoConstraints = false
                box.addSubview(lbl)
                NSLayoutConstraint.activate([
                    lbl.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
                    lbl.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -4),
                    lbl.centerYAnchor.constraint(equalTo: box.centerYAnchor),
                ])
            }

            let delBtn = UIButton(type: .system)
            delBtn.tag = idx
            delBtn.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            delBtn.layer.cornerRadius = 9
            delBtn.setImage(Icons.image(.close, size: 10, color: .white), for: .normal)
            delBtn.translatesAutoresizingMaskIntoConstraints = false
            delBtn.addTarget(self, action: #selector(removeAttTapped(_:)), for: .touchUpInside)
            box.addSubview(delBtn)
            NSLayoutConstraint.activate([
                delBtn.topAnchor.constraint(equalTo: box.topAnchor, constant: 2),
                delBtn.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -2),
                delBtn.widthAnchor.constraint(equalToConstant: 18),
                delBtn.heightAnchor.constraint(equalToConstant: 18),
            ])
            attachmentStack.addArrangedSubview(box)
        }
        updateSendButton()
    }

    @objc private func removeAttTapped(_ sender: UIButton) {
        onRemoveAttachment?(sender.tag)
    }

    @objc private func attachTapped() { onAttachTapped?() }
    @objc private func modelTapped() { onModelTapped?() }

    @objc private func sendTapped() {
        if isStreaming {
            onStop?()
            return
        }
        let txt = (textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !txt.isEmpty || !pendingAttachments.isEmpty else { return }
        onSend?(txt)
    }

    func textViewDidChange(_ textView: UITextView) {
        let hasAnyText = !(textView.text ?? "").isEmpty || textView.markedTextRange != nil
        placeholderLabel.isHidden = hasAnyText
        let width = textView.bounds.width > 0 ? textView.bounds.width : (UIScreen.main.bounds.width - 28)
        let fit = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let maxH: CGFloat = 110
        textView.isScrollEnabled = fit.height > maxH
        let newH = max(40, min(ceil(fit.height), maxH))
        if abs(textHeightConstraint.constant - newH) > 0.5 {
            textHeightConstraint.constant = newH
            superview?.layoutIfNeeded()
        }
        updateSendButton()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if SettingsStore.shared.returnToSend && text == "\n" && !isStreaming && textView.markedTextRange == nil {
            sendTapped()
            return false
        }
        return true
    }
}
