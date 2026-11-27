import UIKit

final class ThemedNavigationController: UINavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: Theme.didChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.current.statusBarStyle
    }

    override var childForStatusBarStyle: UIViewController? {
        return nil
    }

    @objc func applyTheme() {
        let t = Theme.current
        view.backgroundColor = t.background
        navigationBar.isTranslucent = false
        navigationBar.barStyle = t.isDark ? .black : .default
        navigationBar.barTintColor = t.background
        navigationBar.tintColor = t.accent
        navigationBar.shadowImage = UIImage()
        navigationBar.setBackgroundImage(UIImage(), for: .default)
        navigationBar.titleTextAttributes = [
            .foregroundColor: t.textPrimary,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        setNeedsStatusBarAppearanceUpdate()
    }
}
