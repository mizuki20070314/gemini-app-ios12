import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let win = UIWindow(frame: UIScreen.main.bounds)
        self.window = win
        AppRouter.shared.start(window: win)
        // Kick off on-device Gemini Web bootstrap immediately (Guest or Logged-in Cookie session)
        GeminiWebClient.shared.initialize(completion: nil)
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        if GeminiCookieStore.shared.importPendingDropInIfPresent() {
            GeminiWebClient.shared.initialize(completion: nil)
        } else if GeminiWebClient.shared.bootstrapState == nil && !GeminiWebClient.shared.isBootstrapping {
            GeminiWebClient.shared.initialize(completion: nil)
        }
    }
}
