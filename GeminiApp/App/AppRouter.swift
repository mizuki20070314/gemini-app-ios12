import UIKit

final class AppRouter {
    static let shared = AppRouter()
    var window: UIWindow?
    private weak var rootVC: RootViewController?

    private init() {}

    var isSidebarPersistent: Bool {
        return rootVC?.isSidebarPersistent ?? false
    }

    var topViewController: UIViewController? {
        var vc = window?.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }

    func start(window: UIWindow) {
        self.window = window
        let root = RootViewController()
        self.rootVC = root
        window.rootViewController = root
        window.backgroundColor = Theme.current.background
        window.makeKeyAndVisible()
        startNewChat()
    }

    func startNewChat() {
        let chat = ChatViewController(conversationId: nil)
        let nav = ThemedNavigationController(rootViewController: chat)
        rootVC?.setMainViewController(nav)
        rootVC?.closeSidebar()
    }

    func openConversation(id: String) {
        let chat = ChatViewController(conversationId: id)
        let nav = ThemedNavigationController(rootViewController: chat)
        rootVC?.setMainViewController(nav)
        rootVC?.closeSidebar()
    }

    func openSearch() {
        let vc = SearchViewController()
        let nav = ThemedNavigationController(rootViewController: vc)
        rootVC?.closeSidebar()
        topViewController?.present(nav, animated: true)
    }

    func openSettings() {
        let vc = SettingsViewController(style: .grouped)
        let nav = ThemedNavigationController(rootViewController: vc)
        if UIDevice.current.userInterfaceIdiom == .pad {
            nav.modalPresentationStyle = .formSheet
        }
        rootVC?.closeSidebar()
        topViewController?.present(nav, animated: true)
    }

    func toggleSidebar() {
        rootVC?.toggleSidebar()
    }

    func closeSidebar() {
        rootVC?.closeSidebar()
    }
}
