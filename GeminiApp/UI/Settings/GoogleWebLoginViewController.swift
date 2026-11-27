import UIKit
import WebKit

/// In-app Google Account login using WKWebView.
/// After signing in to gemini.google.com, extracts all Google cookies from WKHTTPCookieStore
/// directly into GeminiCookieStore (Keychain) so the app runs 100% on-device.
final class GoogleWebLoginViewController: UIViewController, WKNavigationDelegate {
    private var webView: WKWebView!
    private let statusLabel = UILabel()
    private let onComplete: (Bool, String?) -> Void

    init(onComplete: @escaping (Bool, String?) -> Void) {
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Google ログイン"
        let t = Theme.current
        view.backgroundColor = t.background

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "キャンセル", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Cookie 取得", style: .done, target: self, action: #selector(extractNowTapped))

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.navigationDelegate = self
        // Safari mobile UA avoids Google's `403 disallowed_useragent` block for embedded WebViews
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        statusLabel.text = "Google にサインインして Gemini 画面が開いたら自動で取得します（手動で右上「Cookie 取得」も可）"
        statusLabel.font = UIFont.systemFont(ofSize: 12)
        statusLabel.textColor = t.textSecondary
        statusLabel.backgroundColor = t.surface
        statusLabel.numberOfLines = 2
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),

            webView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        if let url = URL(string: "https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fgemini.google.com%2Fapp") {
            webView.load(URLRequest(url: url))
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true) { self.onComplete(false, nil) }
    }

    @objc private func extractNowTapped() {
        extractCookies(manual: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url?.absoluteString else { return }
        if url.contains("gemini.google.com/app") || url.contains("gemini.google.com/u/") {
            extractCookies(manual: false)
        }
    }

    private func extractCookies(manual: Bool) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            GeminiCookieStore.shared.importFromHTTPCookies(cookies)
            if GeminiCookieStore.shared.hasAccountCredentials {
                SettingsStore.shared.useGuestMode = false
                DispatchQueue.main.async {
                    self.statusLabel.text = "Cookie を取得しました！セッションを初期化中..."
                    GeminiWebClient.shared.initialize { res in
                        switch res {
                        case .success(let bs):
                            self.dismiss(animated: true) {
                                self.onComplete(true, "ログイン成功: \(bs.email.isEmpty ? "Google アカウント" : bs.email) (\(bs.models.count) モデル)")
                            }
                        case .failure(let err):
                            if manual {
                                self.dismiss(animated: true) { self.onComplete(false, err.localizedDescription) }
                            } else {
                                self.statusLabel.text = "初期化待ち: \(err.localizedDescription)"
                            }
                        }
                    }
                }
            } else if manual {
                DispatchQueue.main.async {
                    let alert = UIAlertController(
                        title: "必要な Cookie が見つかりません",
                        message: "Google へのサインイン完了後に gemini.google.com が開いている状態で再試行するか、設定画面の「Cookie ヘッダーをインポート」をご利用ください。",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }
}
