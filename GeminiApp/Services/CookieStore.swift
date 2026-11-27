import Foundation
import CommonCrypto

struct StoredCookie: Codable, Equatable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var secure: Bool
    var httpOnly: Bool
    var expires: TimeInterval // 0 = session
}

/// Manages Google/Gemini cookies with Keychain persistence, RFC-like domain matching,
/// Set-Cookie absorption, Cookie header / gemini-web2api JSON import, and SAPISIDHASH generation.
final class GeminiCookieStore {
    static let shared = GeminiCookieStore()

    private let keychainKey = "gemini_cookies_v1"
    private let lock = NSLock()
    private var cookies: [String: StoredCookie] = [:]

    private init() {
        loadFromKeychain()
        _ = importPendingDropInIfPresent()
    }

    /// Checks for a drop-in cookie file (`GeminiSecure/pending_cookies.txt`), imports it into Keychain,
    /// switches out of guest mode, and deletes the drop-in file.
    @discardableResult
    func importPendingDropInIfPresent() -> Bool {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let pendingURL = base.appendingPathComponent("GeminiSecure", isDirectory: true)
            .appendingPathComponent("pending_cookies.txt")
        guard FileManager.default.fileExists(atPath: pendingURL.path),
              let raw = try? String(contentsOf: pendingURL, encoding: .utf8) else {
            return false
        }
        try? FileManager.default.removeItem(at: pendingURL)
        let res = importRawInput(raw)
        if res.imported > 0 && res.hasRequired {
            if let au = res.authUser { SettingsStore.shared.authUser = au }
            SettingsStore.shared.useGuestMode = false
            return true
        }
        return false
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return cookies.count
    }

    var hasAccountCredentials: Bool {
        lock.lock(); defer { lock.unlock() }
        let has1PSID = cookies.values.contains { $0.name == "__Secure-1PSID" && !$0.value.isEmpty }
        let hasSAPISID = cookies.values.contains { ($0.name == "SAPISID" || $0.name == "__Secure-1PAPISID" || $0.name == "__Secure-3PAPISID") && !$0.value.isEmpty }
        return has1PSID && hasSAPISID
    }

    func clearAll() {
        lock.lock()
        cookies.removeAll()
        lock.unlock()
        _ = KeychainStore.shared.delete(keychainKey)
    }

    func replaceCookies(_ newCookies: [StoredCookie]) {
        lock.lock()
        cookies.removeAll()
        for c in newCookies where !c.name.isEmpty {
            cookies[keyFor(c)] = c
        }
        let snapshot = Array(cookies.values)
        lock.unlock()
        saveToKeychain(snapshot)
    }

    func importFromHTTPCookies(_ list: [HTTPCookie]) {
        var imported: [StoredCookie] = []
        for c in list {
            let dom = c.domain.lowercased()
            guard dom.contains("google.com") || dom.contains("googleusercontent.com") else { continue }
            let exp = c.expiresDate?.timeIntervalSince1970 ?? 0
            imported.append(StoredCookie(
                name: c.name,
                value: c.value,
                domain: c.domain,
                path: c.path.isEmpty ? "/" : c.path,
                secure: c.isSecure,
                httpOnly: c.isHTTPOnly,
                expires: exp
            ))
        }
        guard !imported.isEmpty else { return }
        lock.lock()
        for c in imported {
            cookies[keyFor(c)] = c
        }
        let snapshot = Array(cookies.values)
        lock.unlock()
        saveToKeychain(snapshot)
    }

    /// Imports either a raw `Cookie:` header string (`SAPISID=...; __Secure-1PSID=...`)
    /// or a `gemini-web2api` auth JSON (`{"cookies":[...]}`) or Chrome extension JSON array.
    func importRawInput(_ raw: String) -> (imported: Int, hasRequired: Bool, authUser: Int?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (0, false, nil) }

        // 1. Try JSON format (gemini-web2api auth.json or Cookie-Editor JSON array)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let data = trimmed.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                var parsed: [StoredCookie] = []
                var detectedAuthUser: Int?
                var cookieDicts: [[String: Any]] = []
                if let dict = obj as? [String: Any] {
                    if let arr = dict["cookies"] as? [[String: Any]] {
                        cookieDicts = arr
                    }
                    if let meta = dict["geminiWeb2api"] as? [String: Any],
                       let au = meta["authUser"] as? Int {
                        detectedAuthUser = au
                    }
                } else if let arr = obj as? [[String: Any]] {
                    cookieDicts = arr
                }
                for d in cookieDicts {
                    guard let name = d["name"] as? String, !name.isEmpty,
                          let val = d["value"] as? String else { continue }
                    let domain = (d["domain"] as? String) ?? (name.hasPrefix("__Host-") ? "gemini.google.com" : ".google.com")
                    let path = (d["path"] as? String) ?? "/"
                    let secure = (d["secure"] as? Bool) ?? true
                    let httpOnly = (d["httpOnly"] as? Bool) ?? false
                    let exp = (d["expires"] as? Double) ?? (d["expirationDate"] as? Double) ?? 0
                    parsed.append(StoredCookie(name: name, value: val, domain: domain, path: path, secure: secure, httpOnly: httpOnly, expires: exp))
                }
                if !parsed.isEmpty {
                    replaceCookies(parsed)
                    return (parsed.count, hasAccountCredentials, detectedAuthUser)
                }
            }
        }

        // 2. Raw Cookie header string (`Cookie: k=v; k2=v2` or `k=v; k2=v2`)
        var headerLine = trimmed
        if headerLine.lowercased().hasPrefix("cookie:") {
            headerLine = String(headerLine.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var parsed: [StoredCookie] = []
        for part in headerLine.components(separatedBy: ";") {
            let p = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = p.firstIndex(of: "=") else { continue }
            let name = String(p[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(p[p.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let domain = name.hasPrefix("__Host-") ? "gemini.google.com" : ".google.com"
            parsed.append(StoredCookie(name: name, value: value, domain: domain, path: "/", secure: true, httpOnly: false, expires: 0))
        }
        guard !parsed.isEmpty else { return (0, false, nil) }
        replaceCookies(parsed)
        return (parsed.count, hasAccountCredentials, nil)
    }

    func absorbResponse(_ response: HTTPURLResponse, for url: URL, guest: Bool) {
        guard !guest else { return }
        var headerFields: [String: String] = [:]
        for (k, v) in response.allHeaderFields {
            if let ks = k as? String, let vs = v as? String {
                headerFields[ks] = vs
            }
        }
        let received = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        guard !received.isEmpty else { return }
        lock.lock()
        var changed = false
        let now = Date().timeIntervalSince1970
        for c in received {
            let exp = c.expiresDate?.timeIntervalSince1970 ?? 0
            let sc = StoredCookie(
                name: c.name,
                value: c.value,
                domain: c.domain,
                path: c.path.isEmpty ? "/" : c.path,
                secure: c.isSecure,
                httpOnly: c.isHTTPOnly,
                expires: exp
            )
            let k = keyFor(sc)
            if exp > 0 && exp <= now {
                if cookies.removeValue(forKey: k) != nil { changed = true }
            } else if cookies[k] != sc {
                cookies[k] = sc
                changed = true
            }
        }
        let snapshot = changed ? Array(cookies.values) : nil
        lock.unlock()
        if let snap = snapshot {
            saveToKeychain(snap)
        }
    }

    func cookieHeader(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path.isEmpty ? "/" : url.path
        let isHTTPS = (url.scheme?.lowercased() == "https")
        let now = Date().timeIntervalSince1970

        lock.lock()
        let matched = cookies.values.filter { c in
            if c.expires > 0 && c.expires <= now { return false }
            if c.secure && !isHTTPS { return false }
            guard domainMatches(cookieDomain: c.domain.lowercased(), requestHost: host) else { return false }
            guard pathMatches(cookiePath: c.path, requestPath: path) else { return false }
            return true
        }
        lock.unlock()

        guard !matched.isEmpty else { return nil }
        // Deduplicate by name preferring more specific domain/path
        var byName: [String: StoredCookie] = [:]
        for c in matched {
            if let existing = byName[c.name] {
                if c.domain.count > existing.domain.count || c.path.count > existing.path.count {
                    byName[c.name] = c
                }
            } else {
                byName[c.name] = c
            }
        }
        return byName.values.sorted { $0.name < $1.name }.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func cookieValue(name: String) -> String {
        lock.lock(); defer { lock.unlock() }
        // Prefer .google.com
        if let exact = cookies[".google.com|/|"+name] { return exact.value }
        for c in cookies.values where c.name == name && !c.value.isEmpty {
            return c.value
        }
        return ""
    }

    /// Computes Google SAPISIDHASH authorization header:
    /// `SAPISIDHASH <ts>_<sha1> SAPISID1PHASH <ts>_<sha1> SAPISID3PHASH <ts>_<sha1>`
    func sapisidHashHeader(origin: String = "https://gemini.google.com") -> String {
        let stamp = String(Int64(Date().timeIntervalSince1970))
        func hashFor(_ cookieName: String) -> String {
            let val = cookieValue(name: cookieName)
            let input = "\(stamp) \(val) \(origin)"
            return "\(stamp)_\(sha1Hex(input))"
        }
        return "SAPISIDHASH \(hashFor("SAPISID")) SAPISID1PHASH \(hashFor("__Secure-1PAPISID")) SAPISID3PHASH \(hashFor("__Secure-3PAPISID"))"
    }

    private func sha1Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { rawBuf in
            if let base = rawBuf.baseAddress {
                CC_SHA1(base, CC_LONG(data.count), &digest)
            }
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func keyFor(_ c: StoredCookie) -> String {
        return "\(c.domain.lowercased())|\(c.path)|\(c.name)"
    }

    private func domainMatches(cookieDomain: String, requestHost: String) -> Bool {
        if cookieDomain.hasPrefix(".") {
            let bare = String(cookieDomain.dropFirst())
            return requestHost == bare || requestHost.hasSuffix(cookieDomain)
        }
        return requestHost == cookieDomain
    }

    private func pathMatches(cookiePath: String, requestPath: String) -> Bool {
        if cookiePath == "/" { return true }
        if requestPath == cookiePath { return true }
        if requestPath.hasPrefix(cookiePath) {
            if cookiePath.hasSuffix("/") { return true }
            let idx = requestPath.index(requestPath.startIndex, offsetBy: cookiePath.count)
            return requestPath[idx] == "/"
        }
        return false
    }

    private func loadFromKeychain() {
        guard let json = KeychainStore.shared.get(keychainKey),
              let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([StoredCookie].self, from: data) else { return }
        lock.lock()
        for c in arr { cookies[keyFor(c)] = c }
        lock.unlock()
    }

    private func saveToKeychain(_ snapshot: [StoredCookie]) {
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return }
        _ = KeychainStore.shared.set(json, for: keychainKey)
    }
}
