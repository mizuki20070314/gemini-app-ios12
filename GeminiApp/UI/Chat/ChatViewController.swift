import UIKit
import MobileCoreServices

final class ChatViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {

    private var conversation: Conversation
    private var isNewUnsaved: Bool

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyScrollView = UIScrollView()
    private let emptyContainer = UIView()
    private let emptySpark = GeminiSparkView()
    private let greetingLabel = UILabel()
    private let statusBadge = UIButton(type: .system)
    private let suggestionsStack = UIStackView()

    private let composer = ComposerView()
    private var composerBottomConstraint: NSLayoutConstraint!

    private var isStreaming = false
    private var streamingMessageId: String?
    private var expandedThinkingIds = Set<String>()
    private var lastReloadTime: TimeInterval = 0

    init(conversationId: String?) {
        if let cid = conversationId, let existing = ConversationStore.shared.conversation(id: cid) {
            self.conversation = existing
            self.isNewUnsaved = false
        } else {
            self.conversation = Conversation(
                modelId: SettingsStore.shared.selectedModelId,
                thinkingLevel: SettingsStore.shared.thinkingLevel
            )
            self.isNewUnsaved = true
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNav()
        setupViews()
        applyTheme()
        refreshModelLabel()
        updateEmptyState()

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: Theme.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleClientStateChange), name: GeminiWebClient.stateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNav() {
        updateTitle()
        if !AppRouter.shared.isSidebarPersistent {
            let menuBtn = IconButton(icon: .menu, size: 22)
            menuBtn.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: menuBtn)
        }
        let newBtn = IconButton(icon: .newChat, size: 20)
        newBtn.addTarget(self, action: #selector(newChatTapped), for: .touchUpInside)
        let settingsBtn = IconButton(icon: .settings, size: 20)
        settingsBtn.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(customView: newBtn),
            UIBarButtonItem(customView: settingsBtn)
        ]
    }

    private func setupViews() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .interactive
        tableView.estimatedRowHeight = 80
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(UserMessageCell.self, forCellReuseIdentifier: UserMessageCell.reuseId)
        tableView.register(AssistantMessageCell.self, forCellReuseIdentifier: AssistantMessageCell.reuseId)
        view.addSubview(tableView)

        emptyScrollView.translatesAutoresizingMaskIntoConstraints = false
        emptyScrollView.alwaysBounceVertical = true
        emptyScrollView.keyboardDismissMode = .interactive
        emptyScrollView.clipsToBounds = true
        view.addSubview(emptyScrollView)

        emptyContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyScrollView.addSubview(emptyContainer)

        emptySpark.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.addSubview(emptySpark)

        greetingLabel.text = "こんにちは\n何かお手伝いできますか？"
        greetingLabel.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        greetingLabel.numberOfLines = 0
        greetingLabel.textAlignment = .center
        greetingLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.addSubview(greetingLabel)

        statusBadge.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        statusBadge.layer.cornerRadius = 13
        statusBadge.contentEdgeInsets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        statusBadge.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        emptyContainer.addSubview(statusBadge)

        suggestionsStack.axis = .vertical
        suggestionsStack.spacing = 8
        suggestionsStack.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.addSubview(suggestionsStack)

        let prompts = [
            "Swift でクイックソートを書いて",
            "今日の晩ごはんのアイデアを3つ教えて",
            "iOS 12 で快適に動くアプリ設計のコツは？"
        ]
        for p in prompts {
            let btn = UIButton(type: .system)
            btn.setTitle(p, for: .normal)
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 13)
            btn.titleLabel?.numberOfLines = 1
            btn.contentHorizontalAlignment = .left
            btn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
            btn.layer.cornerRadius = 14
            btn.layer.borderWidth = 1
            btn.addTarget(self, action: #selector(suggestionTapped(_:)), for: .touchUpInside)
            suggestionsStack.addArrangedSubview(btn)
        }

        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.onSend = { [weak self] text in self?.sendMessage(text: text) }
        composer.onStop = { [weak self] in self?.stopStreaming() }
        composer.onAttachTapped = { [weak self] in self?.presentAttachmentMenu() }
        composer.onModelTapped = { [weak self] in self?.presentModelPicker() }
        composer.onRemoveAttachment = { [weak self] idx in
            guard let self = self, idx < self.composer.pendingAttachments.count else { return }
            self.composer.pendingAttachments.remove(at: idx)
        }
        view.addSubview(composer)

        composerBottomConstraint = composer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: composer.topAnchor),

            emptyScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyScrollView.bottomAnchor.constraint(equalTo: composer.topAnchor),

            emptyContainer.topAnchor.constraint(equalTo: emptyScrollView.topAnchor),
            emptyContainer.leadingAnchor.constraint(equalTo: emptyScrollView.leadingAnchor),
            emptyContainer.trailingAnchor.constraint(equalTo: emptyScrollView.trailingAnchor),
            emptyContainer.bottomAnchor.constraint(equalTo: emptyScrollView.bottomAnchor),
            emptyContainer.widthAnchor.constraint(equalTo: emptyScrollView.widthAnchor),

            emptySpark.topAnchor.constraint(equalTo: emptyContainer.topAnchor, constant: 24),
            emptySpark.centerXAnchor.constraint(equalTo: emptyContainer.centerXAnchor),
            emptySpark.widthAnchor.constraint(equalToConstant: 42),
            emptySpark.heightAnchor.constraint(equalToConstant: 42),

            greetingLabel.topAnchor.constraint(equalTo: emptySpark.bottomAnchor, constant: 12),
            greetingLabel.leadingAnchor.constraint(equalTo: emptyContainer.leadingAnchor, constant: 24),
            greetingLabel.trailingAnchor.constraint(equalTo: emptyContainer.trailingAnchor, constant: -24),

            statusBadge.topAnchor.constraint(equalTo: greetingLabel.bottomAnchor, constant: 12),
            statusBadge.centerXAnchor.constraint(equalTo: emptyContainer.centerXAnchor),

            suggestionsStack.topAnchor.constraint(equalTo: statusBadge.bottomAnchor, constant: 18),
            suggestionsStack.leadingAnchor.constraint(equalTo: emptyContainer.leadingAnchor, constant: 20),
            suggestionsStack.trailingAnchor.constraint(equalTo: emptyContainer.trailingAnchor, constant: -20),
            suggestionsStack.bottomAnchor.constraint(equalTo: emptyContainer.bottomAnchor, constant: -16),

            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composerBottomConstraint,
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tap)
        let emptyTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        emptyTap.cancelsTouchesInView = false
        emptyScrollView.addGestureRecognizer(emptyTap)
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }
    @objc private func menuTapped() { AppRouter.shared.toggleSidebar() }
    @objc private func newChatTapped() {
        if isStreaming { stopStreaming() }
        AppRouter.shared.startNewChat()
    }
    @objc private func settingsTapped() { AppRouter.shared.openSettings() }

    @objc private func suggestionTapped(_ sender: UIButton) {
        if let txt = sender.title(for: .normal), !txt.isEmpty {
            sendMessage(text: txt)
        }
    }

    @objc private func applyTheme() {
        let t = Theme.current
        view.backgroundColor = t.background
        tableView.backgroundColor = t.background
        emptyScrollView.backgroundColor = t.background
        emptyContainer.backgroundColor = t.background
        greetingLabel.textColor = t.textPrimary
        statusBadge.backgroundColor = t.accentSoft
        statusBadge.setTitleColor(t.accent, for: .normal)
        for v in suggestionsStack.arrangedSubviews {
            if let b = v as? UIButton {
                b.backgroundColor = t.surface
                b.layer.borderColor = t.border.cgColor
                b.setTitleColor(t.textPrimary, for: .normal)
            }
        }
        tableView.reloadData()
    }

    @objc private func handleClientStateChange() {
        refreshModelLabel()
        updateStatusBadge()
    }

    private func updateTitle() {
        title = conversation.messages.isEmpty ? "Gemini" : conversation.title
    }

    private func updateEmptyState() {
        let isEmpty = conversation.messages.isEmpty
        emptyScrollView.isHidden = !isEmpty
        tableView.isHidden = isEmpty
        updateStatusBadge()
    }

    private func updateStatusBadge() {
        let client = GeminiWebClient.shared
        if client.isBootstrapping {
            statusBadge.setTitle("Gemini Web に接続中...", for: .normal)
        } else if let err = client.lastError {
            statusBadge.setTitle("接続エラー (設定を確認)", for: .normal)
            _ = err
        } else if let bs = client.bootstrapState {
            if bs.isGuest {
                statusBadge.setTitle("ゲストモード • \(bs.defaultModel.displayName) (ログイン可)", for: .normal)
            } else {
                let tier = bs.usage?.tierName ?? "ログイン済み"
                statusBadge.setTitle("\(tier) • \(bs.models.count) モデル利用可能", for: .normal)
            }
        } else {
            statusBadge.setTitle("タップしてアカウント設定", for: .normal)
        }
    }

    private func refreshModelLabel() {
        let model = GeminiWebClient.shared.bootstrapState?.resolveModel(id: conversation.modelId) ?? GeminiModel.fallbackGuest
        let lvl = conversation.thinkingLevel
        let titleText: String
        if lvl != .auto && !model.thinkingLevels.isEmpty {
            titleText = "\(model.displayName) (\(lvl.displayName)) ⌄"
        } else {
            titleText = "\(model.displayName) ⌄"
        }
        composer.setModelTitle(titleText)
    }

    // MARK: - Send & Streaming

    private func sendMessage(text: String) {
        guard !isStreaming else { return }
        if SettingsStore.shared.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        let attachments = composer.pendingAttachments
        composer.clearText()
        composer.pendingAttachments = []
        view.endEditing(true)

        let userMsg = ChatMessage(role: .user, text: text, attachments: attachments)
        let activeModel = GeminiWebClient.shared.bootstrapState?.resolveModel(id: conversation.modelId) ?? GeminiModel.fallbackGuest
        let assistantMsg = ChatMessage(role: .assistant, text: "", modelName: activeModel.displayName)

        if conversation.messages.isEmpty && !text.isEmpty {
            conversation.title = String(text.prefix(32))
        }
        conversation.messages.append(userMsg)
        conversation.messages.append(assistantMsg)
        isNewUnsaved = false
        ConversationStore.shared.save(conversation)

        updateTitle()
        updateEmptyState()
        tableView.reloadData()
        scrollToBottom(animated: true)

        startStreaming(forAssistantMessageId: assistantMsg.id, prompt: text, attachments: attachments)
    }

    private func startStreaming(forAssistantMessageId msgId: String, prompt: String, attachments: [MessageAttachment]) {
        isStreaming = true
        streamingMessageId = msgId
        composer.isStreaming = true

        let callbacks = StreamCallbacks(
            onThought: { [weak self] thought in
                self?.updateAssistantMessage(id: msgId) { $0.thinking = thought }
            },
            onText: { [weak self] text in
                self?.updateAssistantMessage(id: msgId) { $0.text = text }
            },
            onTitle: { [weak self] remoteTitle in
                guard let self = self else { return }
                if !remoteTitle.isEmpty {
                    self.conversation.title = remoteTitle
                    self.updateTitle()
                }
            },
            onModelName: { [weak self] modelName in
                self?.updateAssistantMessage(id: msgId) { $0.modelName = modelName }
            },
            onCitations: { [weak self] citations in
                self?.updateAssistantMessage(id: msgId) { $0.citations = citations }
            },
            onGeneratedImages: { [weak self] metas in
                self?.handleGeneratedImages(metas, messageId: msgId)
            },
            onComplete: { [weak self] newSession in
                guard let self = self else { return }
                self.isStreaming = false
                self.streamingMessageId = nil
                self.composer.isStreaming = false
                self.conversation.webSession = newSession
                ConversationStore.shared.save(self.conversation)
                self.tableView.reloadData()
                self.scrollToBottom(animated: true)
            },
            onError: { [weak self] err in
                guard let self = self else { return }
                self.isStreaming = false
                self.streamingMessageId = nil
                self.composer.isStreaming = false
                self.updateAssistantMessage(id: msgId) { $0.errorMessage = err.localizedDescription }
                ConversationStore.shared.save(self.conversation)
                self.tableView.reloadData()
                self.scrollToBottom(animated: true)
            }
        )

        GeminiWebClient.shared.streamGenerate(
            prompt: prompt.isEmpty ? "添付ファイルを確認してください。" : prompt,
            modelId: conversation.modelId,
            thinkingLevel: conversation.thinkingLevel,
            attachments: attachments,
            session: conversation.webSession,
            callbacks: callbacks
        )
    }

    private func handleGeneratedImages(_ metas: [GeneratedImageMeta], messageId: String) {
        for meta in metas {
            let itemId = UUID().uuidString
            let placeholder = GeneratedMediaItem(id: itemId, url: meta.url, fileName: meta.fileName, mimeType: meta.mimeType, localFileName: nil, width: meta.width, height: meta.height)
            updateAssistantMessage(id: messageId) { $0.generatedMedia.append(placeholder) }

            GeminiWebClient.shared.downloadGeneratedImage(meta: meta) { [weak self] res in
                guard let self = self else { return }
                if case .success(let data) = res {
                    let ext = meta.mimeType.contains("png") ? "png" : "jpg"
                    let localName = ConversationStore.shared.saveMediaData(data, preferredExtension: ext)
                    DispatchQueue.main.async {
                        self.updateAssistantMessage(id: messageId) { msg in
                            if let idx = msg.generatedMedia.firstIndex(where: { $0.id == itemId }) {
                                msg.generatedMedia[idx] = GeneratedMediaItem(
                                    id: itemId, url: meta.url, fileName: meta.fileName,
                                    mimeType: meta.mimeType, localFileName: localName,
                                    width: meta.width, height: meta.height
                                )
                            }
                        }
                        ConversationStore.shared.save(self.conversation)
                        self.tableView.reloadData()
                    }
                }
            }
        }
    }

    private func updateAssistantMessage(id: String, mutate: (inout ChatMessage) -> Void) {
        guard let idx = conversation.messages.lastIndex(where: { $0.id == id }) else { return }
        mutate(&conversation.messages[idx])
        let now = Date().timeIntervalSince1970
        if now - lastReloadTime >= 0.08 {
            lastReloadTime = now
            UIView.performWithoutAnimation {
                self.tableView.reloadData()
            }
            scrollToBottom(animated: false)
        }
    }

    private func stopStreaming() {
        GeminiWebClient.shared.cancelActiveGeneration()
        isStreaming = false
        streamingMessageId = nil
        composer.isStreaming = false
        ConversationStore.shared.save(conversation)
        tableView.reloadData()
    }

    private func retryAssistantMessage(at index: Int) {
        guard !isStreaming, index > 0 else { return }
        // Find preceding user message
        var userIdx = index - 1
        while userIdx >= 0 && conversation.messages[userIdx].role != .user {
            userIdx -= 1
        }
        guard userIdx >= 0 else { return }
        let userMsg = conversation.messages[userIdx]
        let activeModel = GeminiWebClient.shared.bootstrapState?.resolveModel(id: conversation.modelId) ?? GeminiModel.fallbackGuest
        let newAssistant = ChatMessage(role: .assistant, text: "", modelName: activeModel.displayName)
        conversation.messages[index] = newAssistant
        // Reset web session if retrying first turn
        if userIdx == 0 {
            conversation.webSession = WebSessionState()
        }
        ConversationStore.shared.save(conversation)
        tableView.reloadData()
        startStreaming(forAssistantMessageId: newAssistant.id, prompt: userMsg.text, attachments: userMsg.attachments)
    }

    private func scrollToBottom(animated: Bool) {
        let count = conversation.messages.count
        guard count > 0 else { return }
        let ip = IndexPath(row: count - 1, section: 0)
        tableView.scrollToRow(at: ip, at: .bottom, animated: animated)
    }

    // MARK: - Model Picker & Attachments

    private func presentModelPicker() {
        view.endEditing(true)
        let picker = ModelPickerViewController(selectedModelId: conversation.modelId, thinkingLevel: conversation.thinkingLevel) { [weak self] model, level in
            guard let self = self else { return }
            self.conversation.modelId = model.id
            self.conversation.thinkingLevel = level
            SettingsStore.shared.selectedModelId = model.id
            SettingsStore.shared.thinkingLevel = level
            self.refreshModelLabel()
        }
        BottomSheetController.present(picker, from: self)
    }

    private func presentAttachmentMenu() {
        view.endEditing(true)
        if GeminiWebClient.shared.isGuestSession {
            let alert = UIAlertController(
                title: "ログインが必要です",
                message: "画像・ファイルの添付は Google アカウントでログインしている場合に利用できます。設定画面を開きますか？",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
            alert.addAction(UIAlertAction(title: "設定を開く", style: .default) { _ in AppRouter.shared.openSettings() })
            present(alert, animated: true)
            return
        }

        let sheet = UIAlertController(title: "ファイルを添付", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "写真ライブラリ", style: .default) { [weak self] _ in
            self?.openImagePicker(source: .photoLibrary)
        })
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            sheet.addAction(UIAlertAction(title: "カメラで撮影", style: .default) { [weak self] _ in
                self?.openImagePicker(source: .camera)
            })
        }
        sheet.addAction(UIAlertAction(title: "ファイルを選択", style: .default) { [weak self] _ in
            let types = [kUTTypeText as String, kUTTypePDF as String, kUTTypeImage as String, kUTTypeData as String]
            let doc = UIDocumentPickerViewController(documentTypes: types, in: .import)
            doc.delegate = self
            self?.present(doc, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = composer
            pop.sourceRect = composer.bounds
        }
        present(sheet, animated: true)
    }

    private func openImagePicker(source: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.delegate = self
        present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage,
              let jpeg = ImageUtil.resizedJPEGData(from: image) else { return }
        let localName = ConversationStore.shared.saveMediaData(jpeg, preferredExtension: "jpg")
        let att = MessageAttachment(id: UUID().uuidString, fileName: "photo_\(Int(Date().timeIntervalSince1970)).jpg", mimeType: "image/jpeg", localFileName: localName)
        composer.pendingAttachments.append(att)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        let mime: String
        switch ext {
        case "jpg", "jpeg": mime = "image/jpeg"
        case "png": mime = "image/png"
        case "pdf": mime = "application/pdf"
        case "json": mime = "application/json"
        default: mime = "text/plain"
        }
        let localName = ConversationStore.shared.saveMediaData(data, preferredExtension: ext.isEmpty ? "txt" : ext)
        let att = MessageAttachment(id: UUID().uuidString, fileName: url.lastPathComponent, mimeType: mime, localFileName: localName)
        composer.pendingAttachments.append(att)
    }

    // MARK: - Keyboard

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let info = note.userInfo,
              let endFrame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }
        let converted = view.convert(endFrame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY - view.safeAreaInsets.bottom)
        composerBottomConstraint.constant = -overlap
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - TableView

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return conversation.messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let msg = conversation.messages[indexPath.row]
        if msg.role == .user {
            let cell = tableView.dequeueReusableCell(withIdentifier: UserMessageCell.reuseId, for: indexPath) as! UserMessageCell
            cell.configure(message: msg)
            cell.onImageTap = { [weak self] img in self?.openImagePreview(img) }
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: AssistantMessageCell.reuseId, for: indexPath) as! AssistantMessageCell
            let streaming = (isStreaming && streamingMessageId == msg.id)
            let expanded = expandedThinkingIds.contains(msg.id)
            cell.configure(message: msg, isStreaming: streaming, thinkingExpanded: expanded)
            cell.onToggleThinking = { [weak self] in
                guard let self = self else { return }
                if self.expandedThinkingIds.contains(msg.id) {
                    self.expandedThinkingIds.remove(msg.id)
                } else {
                    self.expandedThinkingIds.insert(msg.id)
                }
                UIView.performWithoutAnimation {
                    self.tableView.beginUpdates()
                    self.tableView.endUpdates()
                }
            }
            cell.onCopy = { [weak self] text in
                UIPasteboard.general.string = text
                self?.showToast("コピーしました")
            }
            cell.onRetry = { [weak self] in self?.retryAssistantMessage(at: indexPath.row) }
            cell.onShare = { [weak self] text in
                let ac = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                if let pop = ac.popoverPresentationController {
                    pop.sourceView = cell
                    pop.sourceRect = cell.bounds
                }
                self?.present(ac, animated: true)
            }
            cell.onImageTap = { [weak self] img in self?.openImagePreview(img) }
            cell.onCitationTap = { url in UIApplication.shared.open(url, options: [:], completionHandler: nil) }
            return cell
        }
    }

    private func openImagePreview(_ image: UIImage) {
        let vc = ImagePreviewViewController(image: image)
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    private func showToast(_ text: String) {
        let lbl = UILabel()
        lbl.text = "  \(text)  "
        lbl.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        lbl.textColor = .white
        lbl.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        lbl.layer.cornerRadius = 14
        lbl.clipsToBounds = true
        lbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lbl.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -14),
            lbl.heightAnchor.constraint(equalToConstant: 28),
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            UIView.animate(withDuration: 0.25, animations: { lbl.alpha = 0 }) { _ in lbl.removeFromSuperview() }
        }
    }
}
