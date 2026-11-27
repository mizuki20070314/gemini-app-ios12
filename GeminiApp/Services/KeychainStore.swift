import Foundation
import Security

final class KeychainStore {
    static let shared = KeychainStore()
    let service: String = "com.mizuki.geminiios12"
    private(set) var lastStatus: OSStatus = errSecSuccess

    private let fallbackDir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fallbackDir = base.appendingPathComponent("GeminiSecure", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
    }

    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        lastStatus = status
        if status == errSecSuccess, let data = result as? Data, let str = String(data: data, encoding: .utf8) {
            return str
        }
        // Fallback file if Keychain entitlement is unavailable in some sideload/test environments
        let fileURL = fallbackDir.appendingPathComponent(safeKey(key))
        if let data = try? Data(contentsOf: fileURL), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return nil
    }

    @discardableResult
    func set(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let delQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(delQuery as CFDictionary)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        lastStatus = status
        let fileURL = fallbackDir.appendingPathComponent(safeKey(key))
        if status == errSecSuccess {
            try? FileManager.default.removeItem(at: fileURL)
            return true
        }
        // Fallback write (0600) so cookies still persist even if Keychain returns -34018
        do {
            try data.write(to: fileURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        lastStatus = status
        let fileURL = fallbackDir.appendingPathComponent(safeKey(key))
        try? FileManager.default.removeItem(at: fileURL)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func safeKey(_ key: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return String(key.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
