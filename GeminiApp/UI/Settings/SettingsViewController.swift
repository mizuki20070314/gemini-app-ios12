import UIKit

final class SettingsViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case account
        case chat
        case appearance
        case data
        case diagnostics
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "設定"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完了", style: .done, target: self, action: #selector(closeTapped))
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: Theme.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadTable), name: GeminiWebClient.stateDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    @objc private func reloadTable() { tableView.reloadData() }

    @objc private func applyTheme() {
        let t = Theme.current
        view.backgroundColor = t.surface
        tableView.backgroundColor = t.surface
        tableView.separatorColor = t.separator
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .account: return "アカウント / Gemini Web セッション（端末完結）"
        case .chat: return "チャット・モデル"
        case .appearance: return "外観"
        case .data: return "データ管理"
        case .diagnostics: return "プロトコル診断・情報"
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .account: return 6
        case .chat: return 5
        case .appearance: return 1
        case .data: return 1
        case .diagnostics: return 4
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        let t = Theme.current
        cell.backgroundColor = t.background
        cell.textLabel?.textColor = t.textPrimary
        cell.detailTextLabel?.textColor = t.textSecondary

        let client = GeminiWebClient.shared
        let bs = client.bootstrapState

        switch Section(rawValue: indexPath.section)! {
        case .account:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "接続状態"
                cell.selectionStyle = .none
                if client.isBootstrapping {
                    cell.detailTextLabel?.text = "初期化中..."
                } else if client.isGuestSession {
                    cell.detailTextLabel?.text = "ゲストモード"
                } else {
                    let email = bs?.email.isEmpty == false ? bs!.email : (SettingsStore.shared.accountEmail.isEmpty ? "ログイン済み" : SettingsStore.shared.accountEmail)
                    cell.detailTextLabel?.text = email
                }
            case 1:
                cell.textLabel?.text = "Google アカウントでログイン (WebView)"
                cell.textLabel?.textColor = t.accent
                cell.accessoryType = .disclosureIndicator
            case 2:
                cell.textLabel?.text = "Cookie ヘッダー / JSON をインポート"
                cell.textLabel?.textColor = t.accent
                cell.accessoryType = .disclosureIndicator
            case 3:
                cell.textLabel?.text = "アカウント番号 (/u/N)"
                cell.detailTextLabel?.text = "/u/\(SettingsStore.shared.authUser)"
                cell.accessoryType = .disclosureIndicator
            case 4:
                cell.textLabel?.text = "セッション再取得 & Cookie ローテーション"
                cell.detailTextLabel?.text = "\(GeminiCookieStore.shared.count) 個"
            case 5:
                cell.textLabel?.text = client.isGuestSession ? "保存済み Cookie で再接続" : "サインアウト（ゲストモードへ）"
                cell.textLabel?.textColor = client.isGuestSession ? t.accent : t.destructive
            default: break
            }

        case .chat:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "デフォルトモデル"
                let m = bs?.resolveModel(id: SettingsStore.shared.selectedModelId) ?? GeminiModel.fallbackGuest
                cell.detailTextLabel?.text = m.displayName
                cell.accessoryType = .disclosureIndicator
            case 1:
                cell.textLabel?.text = "画像生成のアスペクト比"
                cell.detailTextLabel?.text = SettingsStore.shared.imageAspectRatio
                cell.accessoryType = .disclosureIndicator
            case 2:
                cell.textLabel?.text = "Temporary Chat (Google履歴に残さない)"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = SettingsStore.shared.temporaryChat
                sw.addTarget(self, action: #selector(tempChatChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 3:
                cell.textLabel?.text = "Return キーで送信"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = SettingsStore.shared.returnToSend
                sw.addTarget(self, action: #selector(returnSendChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 4:
                cell.textLabel?.text = "触覚フィードバック"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = SettingsStore.shared.hapticsEnabled
                sw.addTarget(self, action: #selector(hapticsChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            default: break
            }

        case .appearance:
            cell.textLabel?.text = "テーマ"
            switch Theme.mode {
            case .light: cell.detailTextLabel?.text = "ライト"
            case .dark: cell.detailTextLabel?.text = "ダーク"
            case .system: cell.detailTextLabel?.text = "システム"
            }
            cell.accessoryType = .disclosureIndicator

        case .data:
            cell.textLabel?.text = "ローカルの会話履歴をすべて削除"
            cell.textLabel?.textColor = t.destructive

        case .diagnostics:
            cell.selectionStyle = .none
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "プラン / 利用枠"
                if let u = bs?.usage {
                    let pcts = u.windows.compactMap { w -> String? in
                        guard let r = w.usedRatio else { return nil }
                        let label = w.kind == 1 ? "5h" : (w.kind == 2 ? "週" : "他")
                        return "\(label):\(Int(round(r * 100)))%"
                    }.joined(separator: " ")
                    cell.detailTextLabel?.text = pcts.isEmpty ? u.tierName : "\(u.tierName) (\(pcts))"
                } else {
                    cell.detailTextLabel?.text = client.isGuestSession ? "Guest (32K)" : "-"
                }
            case 1:
                cell.textLabel?.text = "モデル数 / 言語"
                cell.detailTextLabel?.text = "\(bs?.models.count ?? 0) / \(bs?.language ?? "-")"
            case 2:
                cell.textLabel?.text = "Build Label (bl)"
                cell.detailTextLabel?.text = bs?.bl ?? (client.lastError ?? "未取得")
            case 3:
                cell.textLabel?.text = "バージョン"
                cell.detailTextLabel?.text = "1.0.0 (Direct WebChannel)"
            default: break
            }
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .account:
            switch indexPath.row {
            case 1: openWebViewLogin()
            case 2: openCookieImportPrompt()
            case 3: openAuthUserPicker()
            case 4: runRefreshAndRotate()
            case 5: handleSignOutOrReconnect()
            default: break
            }
        case .chat:
            if indexPath.row == 0 {
                let picker = ModelPickerViewController(selectedModelId: SettingsStore.shared.selectedModelId, thinkingLevel: SettingsStore.shared.thinkingLevel) { [weak self] m, lvl in
                    SettingsStore.shared.selectedModelId = m.id
                    SettingsStore.shared.thinkingLevel = lvl
                    self?.tableView.reloadData()
                }
                BottomSheetController.present(picker, from: self)
            } else if indexPath.row == 1 {
                openAspectRatioPicker()
            }
        case .appearance:
            openThemePicker()
        case .data:
            confirmClearAllHistory()
        case .diagnostics:
            break
        }
    }

    // MARK: - Actions

    private func openWebViewLogin() {
        let vc = GoogleWebLoginViewController { [weak self] ok, msg in
            self?.tableView.reloadData()
            if let msg = msg {
                self?.showAlert(title: ok ? "ログイン完了" : "ログイン結果", message: msg)
            }
        }
        let nav = ThemedNavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    private func openCookieImportPrompt() {
        let alert = UIAlertController(
            title: "Cookie をインポート",
            message: "Chrome 等からコピーした Cookie ヘッダー（SAPISID=...; __Secure-1PSID=...）または gemini-web2api の認証 JSON を貼り付けてください。",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "SAPISID=...; __Secure-1PSID=...; __Secure-1PAPISID=..."
            if let clip = UIPasteboard.general.string, clip.contains("PSID") || clip.contains("SAPISID") {
                tf.text = clip
            }
        }
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "インポートして接続", style: .default) { [weak self] _ in
            let raw = alert.textFields?.first?.text ?? ""
            let res = GeminiCookieStore.shared.importRawInput(raw)
            guard res.imported > 0 else {
                self?.showAlert(title: "エラー", message: "有効な Cookie が読み取れませんでした。")
                return
            }
            if let au = res.authUser { SettingsStore.shared.authUser = au }
            if !res.hasRequired {
                self?.showAlert(title: "Cookie 不足", message: "\(res.imported) 個の Cookie を読み込みましたが、SAPISID または __Secure-1PSID が不足しています。")
                return
            }
            SettingsStore.shared.useGuestMode = false
            GeminiWebClient.shared.initialize { [weak self] initRes in
                self?.tableView.reloadData()
                switch initRes {
                case .success(let bs):
                    self?.showAlert(title: "接続成功", message: "\(bs.email.isEmpty ? "Google アカウント" : bs.email)\n\(bs.models.count) 個のモデルを読み込みました。")
                case .failure(let err):
                    self?.showAlert(title: "初期化エラー", message: err.localizedDescription)
                }
            }
        })
        present(alert, animated: true)
    }

    private func openAuthUserPicker() {
        let alert = UIAlertController(title: "マルチアカウント番号 (/u/N)", message: "ブラウザで複数 Google アカウントにログインしている場合の番号を指定します（通常は 0）。", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.keyboardType = .numberPad
            tf.text = "\(SettingsStore.shared.authUser)"
        }
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存して再接続", style: .default) { [weak self] _ in
            let n = Int(alert.textFields?.first?.text ?? "0") ?? 0
            SettingsStore.shared.authUser = max(0, n)
            GeminiWebClient.shared.initialize { _ in self?.tableView.reloadData() }
        })
        present(alert, animated: true)
    }

    private func runRefreshAndRotate() {
        if !GeminiWebClient.shared.isGuestSession {
            GeminiWebClient.shared.rotateCookies { [weak self] _, rotMsg in
                GeminiWebClient.shared.initialize { res in
                    self?.tableView.reloadData()
                    switch res {
                    case .success(let bs):
                        self?.showAlert(title: "更新完了", message: "\(rotMsg)\nモデル数: \(bs.models.count)")
                    case .failure(let err):
                        self?.showAlert(title: "エラー", message: "\(rotMsg)\n\(err.localizedDescription)")
                    }
                }
            }
        } else {
            GeminiWebClient.shared.initialize { [weak self] res in
                self?.tableView.reloadData()
                switch res {
                case .success(let bs):
                    self?.showAlert(title: "ゲスト接続完了", message: "利用可能モデル: \(bs.models.map { $0.displayName }.joined(separator: ", "))")
                case .failure(let err):
                    self?.showAlert(title: "接続エラー", message: err.localizedDescription)
                }
            }
        }
    }

    private func handleSignOutOrReconnect() {
        if GeminiWebClient.shared.isGuestSession {
            if GeminiCookieStore.shared.hasAccountCredentials {
                SettingsStore.shared.useGuestMode = false
                GeminiWebClient.shared.initialize { [weak self] _ in self?.tableView.reloadData() }
            } else {
                openWebViewLogin()
            }
        } else {
            let alert = UIAlertController(title: "サインアウト", message: "保存された Google Cookie を削除してゲストモードに戻りますか？", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
            alert.addAction(UIAlertAction(title: "サインアウト", style: .destructive) { [weak self] _ in
                GeminiCookieStore.shared.clearAll()
                SettingsStore.shared.accountEmail = ""
                SettingsStore.shared.useGuestMode = true
                GeminiWebClient.shared.initialize { _ in self?.tableView.reloadData() }
            })
            present(alert, animated: true)
        }
    }

    private func openAspectRatioPicker() {
        let sheet = UIAlertController(title: "画像生成のアスペクト比", message: nil, preferredStyle: .actionSheet)
        for ratio in ["1:1", "16:9", "9:16", "4:3", "3:4"] {
            sheet.addAction(UIAlertAction(title: ratio, style: .default) { [weak self] _ in
                SettingsStore.shared.imageAspectRatio = ratio
                self?.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        if let pop = sheet.popoverPresentationController { pop.sourceView = view; pop.sourceRect = view.bounds }
        present(sheet, animated: true)
    }

    private func openThemePicker() {
        let sheet = UIAlertController(title: "外観テーマ", message: nil, preferredStyle: .actionSheet)
        let opts: [(String, ThemeMode)] = [("ライト", .light), ("ダーク", .dark), ("システムに従う", .system)]
        for (label, mode) in opts {
            sheet.addAction(UIAlertAction(title: label, style: .default) { _ in Theme.setMode(mode) })
        }
        sheet.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        if let pop = sheet.popoverPresentationController { pop.sourceView = view; pop.sourceRect = view.bounds }
        present(sheet, animated: true)
    }

    private func confirmClearAllHistory() {
        let alert = UIAlertController(title: "すべての会話を削除", message: "端末に保存されたチャット履歴をすべて削除します。よろしいですか？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "削除する", style: .destructive) { _ in
            ConversationStore.shared.deleteAll()
            AppRouter.shared.startNewChat()
        })
        present(alert, animated: true)
    }

    @objc private func tempChatChanged(_ sender: UISwitch) { SettingsStore.shared.temporaryChat = sender.isOn }
    @objc private func returnSendChanged(_ sender: UISwitch) { SettingsStore.shared.returnToSend = sender.isOn }
    @objc private func hapticsChanged(_ sender: UISwitch) { SettingsStore.shared.hapticsEnabled = sender.isOn }

    private func showAlert(title: String, message: String) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }
}
