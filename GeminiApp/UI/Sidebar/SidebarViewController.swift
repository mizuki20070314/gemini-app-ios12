import UIKit

final class SidebarViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let headerView = UIView()
    private let sparkView = GeminiSparkView()
    private let brandLabel = UILabel()
    private let searchBtn = IconButton(icon: .search, size: 20)

    private let newChatButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)

    private let footerView = UIView()
    private let footerSep = UIView()
    private let accountButton = UIButton(type: .system)
    private let avatarView = UIView()
    private let avatarLabel = UILabel()
    private let accountTitleLabel = UILabel()
    private let accountSubLabel = UILabel()
    private let settingsIcon = UIImageView()

    private var pinnedConversations: [Conversation] = []
    private var recentConversations: [Conversation] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        applyTheme()
        reloadData()

        NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: ConversationStore.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAccountFooter), name: GeminiWebClient.stateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAccountFooter), name: SettingsStore.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: Theme.didChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        sparkView.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(sparkView)

        brandLabel.text = "Gemini"
        brandLabel.font = UIFont.systemFont(ofSize: 21, weight: .semibold)
        brandLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(brandLabel)

        searchBtn.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
        headerView.addSubview(searchBtn)

        newChatButton.layer.cornerRadius = 20
        newChatButton.contentHorizontalAlignment = .left
        newChatButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        newChatButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        newChatButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        newChatButton.setTitle("新しいチャット", for: .normal)
        newChatButton.translatesAutoresizingMaskIntoConstraints = false
        newChatButton.addTarget(self, action: #selector(newChatTapped), for: .touchUpInside)
        view.addSubview(newChatButton)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ConvCell")
        view.addSubview(tableView)

        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        tableView.addGestureRecognizer(lp)

        footerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footerView)

        footerSep.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(footerSep)

        accountButton.translatesAutoresizingMaskIntoConstraints = false
        accountButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        footerView.addSubview(accountButton)

        avatarView.layer.cornerRadius = 16
        avatarView.isUserInteractionEnabled = false
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        accountButton.addSubview(avatarView)

        avatarLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        avatarLabel.textAlignment = .center
        avatarLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarView.addSubview(avatarLabel)

        accountTitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        accountTitleLabel.lineBreakMode = .byTruncatingTail
        accountTitleLabel.isUserInteractionEnabled = false
        accountTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        accountButton.addSubview(accountTitleLabel)

        accountSubLabel.font = UIFont.systemFont(ofSize: 12)
        accountSubLabel.lineBreakMode = .byTruncatingTail
        accountSubLabel.isUserInteractionEnabled = false
        accountSubLabel.translatesAutoresizingMaskIntoConstraints = false
        accountButton.addSubview(accountSubLabel)

        settingsIcon.contentMode = .scaleAspectFit
        settingsIcon.isUserInteractionEnabled = false
        settingsIcon.translatesAutoresizingMaskIntoConstraints = false
        accountButton.addSubview(settingsIcon)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            headerView.heightAnchor.constraint(equalToConstant: 44),

            sparkView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            sparkView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            sparkView.widthAnchor.constraint(equalToConstant: 24),
            sparkView.heightAnchor.constraint(equalToConstant: 24),

            brandLabel.leadingAnchor.constraint(equalTo: sparkView.trailingAnchor, constant: 8),
            brandLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            searchBtn.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            searchBtn.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            newChatButton.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            newChatButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            newChatButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            newChatButton.heightAnchor.constraint(equalToConstant: 40),

            tableView.topAnchor.constraint(equalTo: newChatButton.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 60),

            footerSep.topAnchor.constraint(equalTo: footerView.topAnchor),
            footerSep.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
            footerSep.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
            footerSep.heightAnchor.constraint(equalToConstant: 0.5),

            accountButton.topAnchor.constraint(equalTo: footerSep.bottomAnchor),
            accountButton.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
            accountButton.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
            accountButton.bottomAnchor.constraint(equalTo: footerView.bottomAnchor),

            avatarView.leadingAnchor.constraint(equalTo: accountButton.leadingAnchor, constant: 14),
            avatarView.centerYAnchor.constraint(equalTo: accountButton.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 32),
            avatarView.heightAnchor.constraint(equalToConstant: 32),

            avatarLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            accountTitleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            accountTitleLabel.trailingAnchor.constraint(equalTo: settingsIcon.leadingAnchor, constant: -8),
            accountTitleLabel.topAnchor.constraint(equalTo: accountButton.topAnchor, constant: 11),

            accountSubLabel.leadingAnchor.constraint(equalTo: accountTitleLabel.leadingAnchor),
            accountSubLabel.trailingAnchor.constraint(equalTo: accountTitleLabel.trailingAnchor),
            accountSubLabel.topAnchor.constraint(equalTo: accountTitleLabel.bottomAnchor, constant: 2),

            settingsIcon.trailingAnchor.constraint(equalTo: accountButton.trailingAnchor, constant: -14),
            settingsIcon.centerYAnchor.constraint(equalTo: accountButton.centerYAnchor),
            settingsIcon.widthAnchor.constraint(equalToConstant: 20),
            settingsIcon.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    @objc func reloadData() {
        let all = ConversationStore.shared.allConversations
        pinnedConversations = all.filter { $0.isPinned }
        recentConversations = all.filter { !$0.isPinned }
        tableView.reloadData()
        updateAccountFooter()
    }

    @objc func updateAccountFooter() {
        let client = GeminiWebClient.shared
        let bs = client.bootstrapState
        if client.isGuestSession {
            avatarLabel.text = "G"
            accountTitleLabel.text = "ゲストモード"
            accountSubLabel.text = client.isBootstrapping ? "接続中..." : "タップしてログイン / 設定"
        } else {
            let email = bs?.email.isEmpty == false ? bs!.email : SettingsStore.shared.accountEmail
            let name = email.isEmpty ? "Google アカウント" : email
            avatarLabel.text = String(name.prefix(1)).uppercased()
            accountTitleLabel.text = name
            if client.isBootstrapping {
                accountSubLabel.text = "セッション更新中..."
            } else if let usage = bs?.usage {
                accountSubLabel.text = "\(usage.tierName) • \(bs?.models.count ?? 0) モデル"
            } else if let err = client.lastError {
                accountSubLabel.text = "エラー: \(err)"
            } else {
                accountSubLabel.text = "\(bs?.models.count ?? 0) モデル利用可能"
            }
        }
    }

    @objc private func applyTheme() {
        let t = Theme.current
        view.backgroundColor = t.sidebarBackground
        brandLabel.textColor = t.textPrimary
        newChatButton.backgroundColor = t.accentSoft
        newChatButton.setTitleColor(t.accent, for: .normal)
        newChatButton.setImage(Icons.image(.plus, size: 18, color: t.accent), for: .normal)
        footerSep.backgroundColor = t.separator
        avatarView.backgroundColor = t.accent
        avatarLabel.textColor = t.onAccent
        accountTitleLabel.textColor = t.textPrimary
        accountSubLabel.textColor = t.textSecondary
        settingsIcon.image = Icons.image(.settings, size: 20, color: t.textSecondary)
        tableView.reloadData()
    }

    @objc private func newChatTapped() { AppRouter.shared.startNewChat() }
    @objc private func searchTapped() { AppRouter.shared.openSearch() }
    @objc private func settingsTapped() { AppRouter.shared.openSettings() }

    // MARK: - TableView

    func numberOfSections(in tableView: UITableView) -> Int { return 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? pinnedConversations.count : recentConversations.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 { return pinnedConversations.isEmpty ? nil : "ピン留め" }
        return recentConversations.isEmpty ? nil : "最近のチャット"
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let h = view as? UITableViewHeaderFooterView {
            h.contentView.backgroundColor = Theme.current.sidebarBackground
            h.textLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            h.textLabel?.textColor = Theme.current.textTertiary
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ConvCell", for: indexPath)
        let conv = conversation(at: indexPath)
        let t = Theme.current
        cell.backgroundColor = .clear
        cell.textLabel?.text = conv.title
        cell.textLabel?.font = UIFont.systemFont(ofSize: 14)
        cell.textLabel?.textColor = t.textPrimary
        cell.textLabel?.lineBreakMode = .byTruncatingTail
        cell.imageView?.image = Icons.image(conv.isPinned ? .starFill : .chat, size: 16, color: conv.isPinned ? t.accent : t.textSecondary)
        let sel = UIView()
        sel.backgroundColor = t.sidebarSelected
        cell.selectedBackgroundView = sel
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let conv = conversation(at: indexPath)
        AppRouter.shared.openConversation(id: conv.id)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let conv = conversation(at: indexPath)
            ConversationStore.shared.delete(id: conv.id)
        }
    }

    private func conversation(at indexPath: IndexPath) -> Conversation {
        return indexPath.section == 0 ? pinnedConversations[indexPath.row] : recentConversations[indexPath.row]
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began,
              let indexPath = tableView.indexPathForRow(at: g.location(in: tableView)) else { return }
        let conv = conversation(at: indexPath)
        let sheet = UIAlertController(title: conv.title, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: conv.isPinned ? "ピン留めを外す" : "ピン留めする", style: .default) { _ in
            ConversationStore.shared.togglePin(id: conv.id)
        })
        sheet.addAction(UIAlertAction(title: "名前を変更", style: .default) { [weak self] _ in
            self?.promptRename(conv)
        })
        sheet.addAction(UIAlertAction(title: "削除", style: .destructive) { _ in
            ConversationStore.shared.delete(id: conv.id)
        })
        sheet.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = tableView
            pop.sourceRect = tableView.rectForRow(at: indexPath)
        }
        present(sheet, animated: true)
    }

    private func promptRename(_ conv: Conversation) {
        let alert = UIAlertController(title: "チャット名を変更", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in tf.text = conv.title }
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !name.isEmpty {
                ConversationStore.shared.rename(id: conv.id, title: name)
            }
        })
        present(alert, animated: true)
    }
}
