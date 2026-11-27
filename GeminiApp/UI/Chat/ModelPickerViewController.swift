import UIKit

final class ModelPickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let selectedModelId: String
    private var selectedThinking: ThinkingLevel
    private let onSelect: (GeminiModel, ThinkingLevel) -> Void

    private let headerLabel = UILabel()
    private let refreshButton = UIButton(type: .system)
    private let thinkingControl = UISegmentedControl(items: ["自動", "Low", "Med", "High"])
    private let tableView = UITableView(frame: .zero, style: .plain)

    private var chatModels: [GeminiModel] = []
    private var toolModels: [GeminiModel] = []
    private var gemModels: [GeminiModel] = []

    init(selectedModelId: String, thinkingLevel: ThinkingLevel, onSelect: @escaping (GeminiModel, ThinkingLevel) -> Void) {
        self.selectedModelId = selectedModelId
        self.selectedThinking = thinkingLevel
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        self.preferredContentSize = CGSize(width: 320, height: 460)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let t = Theme.current
        view.backgroundColor = t.background

        headerLabel.text = "モデルと推論強度"
        headerLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        headerLabel.textColor = t.textPrimary
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)

        refreshButton.setTitle("再取得", for: .normal)
        refreshButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        refreshButton.setTitleColor(t.accent, for: .normal)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        view.addSubview(refreshButton)

        thinkingControl.tintColor = t.accent
        thinkingControl.selectedSegmentIndex = segmentIndex(for: selectedThinking)
        thinkingControl.translatesAutoresizingMaskIntoConstraints = false
        thinkingControl.addTarget(self, action: #selector(thinkingChanged), for: .valueChanged)
        view.addSubview(thinkingControl)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = t.background
        tableView.separatorColor = t.separator
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            refreshButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            thinkingControl.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
            thinkingControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            thinkingControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: thinkingControl.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        loadModels()
    }

    private func loadModels() {
        let all = GeminiWebClient.shared.availableModels
        chatModels = all.filter { !$0.isTool && !$0.isGem }
        toolModels = all.filter { $0.isTool }
        gemModels = all.filter { $0.isGem }
        tableView.reloadData()
    }

    private func segmentIndex(for level: ThinkingLevel) -> Int {
        switch level {
        case .auto: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    @objc private func thinkingChanged() {
        switch thinkingControl.selectedSegmentIndex {
        case 1: selectedThinking = .low
        case 2: selectedThinking = .medium
        case 3: selectedThinking = .high
        default: selectedThinking = .auto
        }
        let current = GeminiWebClient.shared.bootstrapState?.resolveModel(id: selectedModelId) ?? GeminiModel.fallbackGuest
        onSelect(current, selectedThinking)
    }

    @objc private func refreshTapped() {
        refreshButton.isEnabled = false
        refreshButton.setTitle("取得中...", for: .normal)
        GeminiWebClient.shared.initialize { [weak self] _ in
            self?.refreshButton.isEnabled = true
            self?.refreshButton.setTitle("再取得", for: .normal)
            self?.loadModels()
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int { return 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return chatModels.count
        case 1: return toolModels.count
        default: return gemModels.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return chatModels.isEmpty ? nil : "チャットモデル"
        case 1: return toolModels.isEmpty ? nil : "公式ツール"
        default: return gemModels.isEmpty ? nil : "Gems"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "MCell")
        let model = modelAt(indexPath)
        let t = Theme.current
        cell.backgroundColor = t.background
        cell.textLabel?.text = model.displayName
        cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        cell.textLabel?.textColor = t.textPrimary
        var sub = model.description
        if !model.thinkingLevels.isEmpty {
            let lvls = model.thinkingLevels.map { $0.displayName }.joined(separator: "/")
            sub = sub.isEmpty ? "思考: \(lvls)" : "\(sub) • 思考: \(lvls)"
        }
        cell.detailTextLabel?.text = sub
        cell.detailTextLabel?.textColor = t.textSecondary
        let activeId = selectedModelId.isEmpty ? (GeminiWebClient.shared.bootstrapState?.defaultModel.id ?? "") : selectedModelId
        if model.id == activeId {
            cell.accessoryView = UIImageView(image: Icons.image(.check, size: 18, color: t.accent))
        } else {
            cell.accessoryView = nil
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let model = modelAt(indexPath)
        onSelect(model, selectedThinking)
        if let sheet = parent as? BottomSheetController {
            sheet.dismissSheet()
        } else {
            dismiss(animated: true)
        }
    }

    private func modelAt(_ indexPath: IndexPath) -> GeminiModel {
        switch indexPath.section {
        case 0: return chatModels[indexPath.row]
        case 1: return toolModels[indexPath.row]
        default: return gemModels[indexPath.row]
        }
    }
}
