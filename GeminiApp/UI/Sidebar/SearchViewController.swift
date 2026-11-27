import UIKit

final class SearchViewController: UIViewController, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate {
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var results: [Conversation] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "チャットを検索"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "閉じる", style: .done, target: self, action: #selector(closeTapped))

        let t = Theme.current
        view.backgroundColor = t.background

        searchBar.delegate = self
        searchBar.placeholder = "タイトルやメッセージ内容を検索..."
        searchBar.searchBarStyle = .minimal
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = t.background
        tableView.separatorColor = t.separator
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        results = ConversationStore.shared.allConversations
        searchBar.becomeFirstResponder()
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        results = ConversationStore.shared.search(query: searchText)
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return results.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SearchCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "SearchCell")
        let conv = results[indexPath.row]
        let t = Theme.current
        cell.backgroundColor = t.background
        cell.textLabel?.text = conv.title
        cell.textLabel?.textColor = t.textPrimary
        cell.detailTextLabel?.text = conv.messages.last?.text ?? ""
        cell.detailTextLabel?.textColor = t.textSecondary
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let conv = results[indexPath.row]
        dismiss(animated: true) {
            AppRouter.shared.openConversation(id: conv.id)
        }
    }
}
