import Foundation

final class SettingsStore {
    static let shared = SettingsStore()
    private let d = UserDefaults.standard

    static let didChange = Notification.Name("GeminiSettings.didChange")

    private init() {}

    var selectedModelId: String {
        get { return d.string(forKey: "gemini.selectedModelId") ?? "" }
        set { d.set(newValue, forKey: "gemini.selectedModelId"); notify() }
    }

    var thinkingLevel: ThinkingLevel {
        get {
            let raw = d.integer(forKey: "gemini.thinkingLevel")
            return ThinkingLevel(rawValue: raw) ?? .auto
        }
        set { d.set(newValue.rawValue, forKey: "gemini.thinkingLevel"); notify() }
    }

    var temporaryChat: Bool {
        get {
            if d.object(forKey: "gemini.temporaryChat") == nil { return true }
            return d.bool(forKey: "gemini.temporaryChat")
        }
        set { d.set(newValue, forKey: "gemini.temporaryChat"); notify() }
    }

    var authUser: Int {
        get { return max(0, d.integer(forKey: "gemini.authUser")) }
        set { d.set(max(0, newValue), forKey: "gemini.authUser"); notify() }
    }

    var returnToSend: Bool {
        get { return d.bool(forKey: "gemini.returnToSend") }
        set { d.set(newValue, forKey: "gemini.returnToSend"); notify() }
    }

    var hapticsEnabled: Bool {
        get {
            if d.object(forKey: "gemini.hapticsEnabled") == nil { return true }
            return d.bool(forKey: "gemini.hapticsEnabled")
        }
        set { d.set(newValue, forKey: "gemini.hapticsEnabled"); notify() }
    }

    var accountEmail: String {
        get { return d.string(forKey: "gemini.accountEmail") ?? "" }
        set { d.set(newValue, forKey: "gemini.accountEmail"); notify() }
    }

    var useGuestMode: Bool {
        get { return d.bool(forKey: "gemini.useGuestMode") }
        set { d.set(newValue, forKey: "gemini.useGuestMode"); notify() }
    }

    var imageAspectRatio: String {
        get { return d.string(forKey: "gemini.imageAspectRatio") ?? "1:1" }
        set { d.set(newValue, forKey: "gemini.imageAspectRatio"); notify() }
    }

    private func notify() {
        NotificationCenter.default.post(name: SettingsStore.didChange, object: self)
    }
}
