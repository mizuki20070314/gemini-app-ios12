import Foundation

// MARK: - Bootstrap & Preferences State

struct GeminiPreferences {
    var slot25: Bool = false
    var slot100: String = ""
    var slot145UploadTerms: Double = 0
    var slot222TaskOnboarded: Bool = false
    var slot261: Bool = false
}

struct GeminiBootstrap {
    let snlM0e: String
    let bl: String
    let fsid: String
    let language: String
    let email: String
    let uploadURL: String
    let uploadPushID: String
    let uploadClientContext: String
    let uploadTermsWindowSec: TimeInterval
    let termsToken: String
    let apiKey: String
    let serverToken: String
    let isGuest: Bool
    var models: [GeminiModel] = []
    var toolOptions: [GeminiFeature: [ToolOption]] = [:]
    var personalIntelligence: Bool = false
    var preferences: GeminiPreferences = GeminiPreferences()
    var usage: GeminiUsageInfo? = nil

    var defaultModel: GeminiModel {
        return models.first(where: { $0.isDefault }) ?? models.first ?? GeminiModel.fallbackGuest
    }

    func resolveModel(id: String) -> GeminiModel {
        let lower = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return defaultModel }
        if let m = models.first(where: {
            $0.id.lowercased() == lower || $0.displayName.lowercased() == lower || $0.hash.lowercased() == lower
        }) {
            return m
        }
        return defaultModel
    }
}

struct GeneratedImageMeta {
    let url: String
    let fileName: String
    let mimeType: String
    let width: Int
    let height: Int
    let entry: [Any]
    let cid: String
    let rid: String
    let rcid: String
    let index: Int
    let mode: Int
    let variant: String
    let level: ThinkingLevel
    let temporaryChat: Bool
}

// MARK: - JSON / JSPB Navigation Helpers

enum JSONNav {
    static func arrayAt(_ arr: [Any]?, _ idx: Int) -> [Any]? {
        guard let arr = arr, idx >= 0, idx < arr.count else { return nil }
        return arr[idx] as? [Any]
    }

    static func stringAt(_ arr: [Any]?, _ idx: Int) -> String? {
        guard let arr = arr, idx >= 0, idx < arr.count else { return nil }
        return arr[idx] as? String
    }

    static func intAt(_ arr: [Any]?, _ idx: Int) -> Int? {
        guard let arr = arr, idx >= 0, idx < arr.count else { return nil }
        if let n = arr[idx] as? Int { return n }
        if let d = arr[idx] as? Double { return Int(d) }
        if let n = arr[idx] as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.intValue
        }
        return nil
    }

    static func doubleAt(_ arr: [Any]?, _ idx: Int) -> Double? {
        guard let arr = arr, idx >= 0, idx < arr.count else { return nil }
        if let d = arr[idx] as? Double { return d }
        if let n = arr[idx] as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.doubleValue
        }
        return nil
    }

    static func boolAt(_ arr: [Any]?, _ idx: Int) -> Bool? {
        guard let arr = arr, idx >= 0, idx < arr.count else { return nil }
        if let b = arr[idx] as? Bool { return b }
        if let n = arr[idx] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() {
            return n.boolValue
        }
        return nil
    }

    static func valuePath(_ root: Any?, _ indices: Int...) -> Any? {
        var cur: Any? = root
        for idx in indices {
            guard let arr = cur as? [Any], idx >= 0, idx < arr.count else { return nil }
            cur = arr[idx]
        }
        if cur is NSNull { return nil }
        return cur
    }

    static func stringPath(_ root: Any?, _ indices: Int...) -> String? {
        var cur: Any? = root
        for idx in indices {
            guard let arr = cur as? [Any], idx >= 0, idx < arr.count else { return nil }
            cur = arr[idx]
        }
        return cur as? String
    }

    static func intPath(_ root: Any?, _ indices: Int...) -> Int? {
        var cur: Any? = root
        for idx in indices {
            guard let arr = cur as? [Any], idx >= 0, idx < arr.count else { return nil }
            cur = arr[idx]
        }
        if let n = cur as? Int { return n }
        if let d = cur as? Double { return Int(d) }
        if let n = cur as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
        return nil
    }

    /// Reads a JSPB field at 0-based index OR from a trailing sparse dictionary keyed by 1-based string index ("11" -> index 10)
    static func jspbField(_ arr: [Any]?, _ index: Int) -> Any? {
        guard let arr = arr else { return nil }
        if index >= 0 && index < arr.count {
            let v = arr[index]
            if !(v is NSNull) { return v }
        }
        if let sparse = arr.last as? [String: Any] {
            let key = String(index + 1)
            if let v = sparse[key], !(v is NSNull) {
                return v
            }
        }
        return nil
    }

    static func jspbString(_ arr: [Any]?, _ index: Int) -> String? {
        return jspbField(arr, index) as? String
    }

    static func firstString(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let arr = value as? [Any] {
            for item in arr {
                if let s = item as? String, !s.isEmpty { return s }
            }
        }
        return nil
    }
}

// MARK: - Protocol Parsers (Bootstrap, Model Catalog, Usage, Preferences, Gems)

enum GeminiProtocolParser {

    static func parseBootstrap(html: String, isGuest: Bool) throws -> GeminiBootstrap {
        let snl = firstMatch(html, pattern: #""SNlM0e":"([^"]+)""#)
        let bl = firstMatch(html, pattern: #""cfb2h":"([^"]+)""#)
        var fsid = firstMatch(html, pattern: #""FdrFJe":"([^"]+)""#)
        if fsid.isEmpty { fsid = firstMatch(html, pattern: #""f\.sid":"([^"]+)""#) }
        let lang = firstMatch(html, pattern: #""TuX5cc":"([^"]+)""#)
        let email = firstMatch(html, pattern: #""oPEP7c":"([^"]+)""#)
        let uploadURL = firstMatch(html, pattern: #""h1eoVe":"([^"]+)""#)
        let pushID = firstMatch(html, pattern: #""qKIAYe":"([^"]+)""#)
        let pctx = firstMatch(html, pattern: #""Ylro7b":"([^"]+)""#)
        let termsToken = firstMatch(html, pattern: #""thykhd":"([^"]+)""#)
        let termsSecStr = firstMatch(html, pattern: #""45725082\\?":(\d+)"#)
        let apiKey = firstMatch(html, pattern: #""d2zJAe":"([^"]+)""#)
        let serverToken = firstMatch(html, pattern: #""PI9WOb":"([^"]+)""#)

        if bl.isEmpty { throw GeminiWebError.protocolError("Geminiページから cfb2h を取得できませんでした。") }
        if fsid.isEmpty { throw GeminiWebError.protocolError("Geminiページから FdrFJe を取得できませんでした。") }
        if apiKey.isEmpty || serverToken.isEmpty {
            throw GeminiWebError.protocolError("Geminiページから APIキー/トークン を取得できませんでした。")
        }
        if !isGuest && snl.isEmpty {
            throw GeminiWebError.signedOut("セッションが切れています。Googleアカウントに再ログインするか、Cookieを再インポートしてください。")
        }

        return GeminiBootstrap(
            snlM0e: snl,
            bl: bl,
            fsid: fsid,
            language: lang.isEmpty ? "ja" : lang,
            email: email,
            uploadURL: uploadURL.isEmpty ? "https://push.clients6.google.com/upload/" : uploadURL,
            uploadPushID: pushID,
            uploadClientContext: pctx,
            uploadTermsWindowSec: TimeInterval(Int64(termsSecStr) ?? 0),
            termsToken: termsToken,
            apiKey: apiKey,
            serverToken: serverToken,
            isGuest: isGuest
        )
    }

    static func parseModelCatalog(payload: [Any], isGuest: Bool) -> (models: [GeminiModel], options: [GeminiFeature: [ToolOption]], personalIntelligence: Bool, accountStatus: Int?) {
        let accountStatus = JSONNav.intAt(payload, 14)
        guard let rows = JSONNav.arrayAt(payload, 15), !rows.isEmpty else {
            return ([GeminiModel.fallbackGuest], [:], false, accountStatus)
        }
        let defaultMode = JSONNav.intAt(payload, 0) ?? 0
        let chatPolicy = parsePolicy(payload: payload, surface: 1)
        let upgradeLockedModes = Set(chatPolicy.filter { $0.upgrade && $0.variant.isEmpty }.map { $0.mode })

        var models: [GeminiModel] = []
        for rawRow in rows {
            guard let row = rawRow as? [Any] else { continue }
            let hash = JSONNav.stringAt(row, 0) ?? ""
            let short = JSONNav.stringAt(row, 1) ?? ""
            var title = JSONNav.stringAt(row, 11) ?? ""
            if title.isEmpty { title = JSONNav.stringAt(row, 19) ?? "" }
            let mode = JSONNav.intAt(row, 17) ?? 0
            if hash.isEmpty || title.isEmpty || mode == 0 { continue }
            if upgradeLockedModes.contains(mode) { continue }
            let subtitle = JSONNav.stringAt(row, 12) ?? ""
            let (displayName, description) = resolveModelName(short: short, title: title, subtitle: subtitle)
            let levels = policyLevels(chatPolicy, mode: mode, variant: "") ?? []
            models.append(GeminiModel(
                id: slugModelID(displayName),
                displayName: displayName,
                description: description,
                hash: hash,
                mode: mode,
                isDefault: mode == defaultMode,
                thinkingLevels: levels,
                feature: .chat,
                gemId: "",
                variant: ""
            ))
        }

        if models.isEmpty {
            models.append(GeminiModel.fallbackGuest)
        }
        if !models.contains(where: { $0.isDefault }) {
            let first = models[0]
            models[0] = GeminiModel(
                id: first.id, displayName: first.displayName, description: first.description,
                hash: first.hash, mode: first.mode, isDefault: true,
                thinkingLevels: first.thinkingLevels, feature: first.feature, gemId: first.gemId, variant: first.variant
            )
        }

        // Strategy variant models (e.g. 4 Argon sharing mode 8 with 4 Carbon)
        for entry in chatPolicy {
            if entry.upgrade || entry.variant.isEmpty { continue }
            let (displayName, description) = resolveModelName(short: entry.short, title: entry.title, subtitle: entry.subtitle)
            models.append(GeminiModel(
                id: slugModelID(displayName),
                displayName: displayName,
                description: description,
                hash: entry.variant,
                mode: entry.mode,
                isDefault: false,
                thinkingLevels: entry.levels,
                feature: .chat,
                gemId: "",
                variant: entry.variant
            ))
        }

        models.sort { a, b in
            if a.isDefault != b.isDefault { return a.isDefault && !b.isDefault }
            return a.id < b.id
        }

        let personalIntelligence = (JSONNav.arrayAt(payload, 21) != nil)
        let options = parseToolOptions(payload: payload)

        if !isGuest {
            let defaultModel = models.first(where: { $0.isDefault }) ?? models[0]
            let caps = (JSONNav.arrayAt(payload, 17) ?? []).compactMap { ($0 as? NSNumber)?.intValue }
            let capSet = Set(caps)

            let tools: [(id: String, name: String, desc: String, feature: GeminiFeature, req: [Int])] = [
                ("gemini-3.1-flash-image", "Nano Banana 2 (画像生成)", "Gemini Web 画像生成・編集", .image, [82]),
                ("gemini-canvas", "Canvas", "ドキュメント・コード作成", .canvas, [51]),
                ("gemini-guided-learning", "Guided Learning", "対話型ガイド学習", .guidedLearning, [117]),
            ]
            for t in tools {
                if t.req.allSatisfy({ capSet.contains($0) }) {
                    models.append(GeminiModel(
                        id: t.id,
                        displayName: t.name,
                        description: t.desc,
                        hash: defaultModel.hash,
                        mode: defaultModel.mode,
                        isDefault: false,
                        thinkingLevels: defaultModel.thinkingLevels,
                        feature: t.feature,
                        gemId: "",
                        variant: defaultModel.variant
                    ))
                }
            }
        }

        return (models, options, personalIntelligence, accountStatus)
    }

    static func parsePreferences(payload: [Any]) -> GeminiPreferences {
        var prefs = GeminiPreferences()
        guard let arr = JSONNav.arrayAt(payload, 0) else { return prefs }
        func prefVal(_ field: Int) -> Any? {
            return JSONNav.jspbField(arr, field - 1)
        }
        if let v = prefVal(25) as? Bool { prefs.slot25 = v }
        else if let n = prefVal(25) as? NSNumber { prefs.slot25 = n.boolValue }
        if let s = prefVal(100) as? String { prefs.slot100 = s }
        if let d = prefVal(145) as? Double { prefs.slot145UploadTerms = d }
        else if let n = prefVal(145) as? NSNumber { prefs.slot145UploadTerms = n.doubleValue }
        if let v = prefVal(222) as? Bool { prefs.slot222TaskOnboarded = v }
        else if let n = prefVal(222) as? NSNumber { prefs.slot222TaskOnboarded = n.boolValue }
        if let v = prefVal(261) as? Bool { prefs.slot261 = v }
        else if let n = prefVal(261) as? NSNumber { prefs.slot261 = n.boolValue }
        return prefs
    }

    static func parseUsage(payload: [Any]) -> GeminiUsageInfo? {
        guard let tier = JSONNav.intAt(payload, 0) else { return nil }
        var windows: [UsageWindowInfo] = []
        if let rawWindows = JSONNav.arrayAt(payload, 1) {
            for item in rawWindows {
                guard let w = item as? [Any], let kind = JSONNav.intAt(w, 2) else { continue }
                let rem = JSONNav.doubleAt(w, 0)
                let used = JSONNav.doubleAt(w, 1)
                var resetDate: Date? = nil
                if let sec = JSONNav.intPath(w, 3, 0, 0), sec > 0 {
                    resetDate = Date(timeIntervalSince1970: TimeInterval(sec))
                }
                windows.append(UsageWindowInfo(kind: kind, remaining: rem, usedRatio: used, resetAt: resetDate))
            }
        }
        return GeminiUsageInfo(tierCode: tier, windows: windows)
    }

    static func parseGems(payload: [Any], baseModel: GeminiModel) -> [GeminiModel] {
        guard let list = JSONNav.arrayAt(payload, 2) else { return [] }
        var result: [GeminiModel] = []
        for raw in list {
            guard let row = raw as? [Any],
                  let gemId = JSONNav.stringAt(row, 0), !gemId.isEmpty else { continue }
            let name = JSONNav.stringPath(row, 1, 0) ?? gemId
            let desc = JSONNav.stringPath(row, 1, 1) ?? "Gem"
            result.append(GeminiModel(
                id: "gem-\(gemId)",
                displayName: "Gem: \(name)",
                description: desc,
                hash: baseModel.hash,
                mode: baseModel.mode,
                isDefault: false,
                thinkingLevels: baseModel.thinkingLevels,
                feature: .chat,
                gemId: gemId,
                variant: baseModel.variant
            ))
        }
        return result
    }

    // MARK: - Policy & Tool Option Helpers

    private struct PolicyEntry {
        let mode: Int
        let variant: String
        let upgrade: Bool
        let short: String
        let title: String
        let subtitle: String
        let levels: [ThinkingLevel]
    }

    private static func parsePolicy(payload: [Any], surface: Int) -> [PolicyEntry] {
        guard let policy = JSONNav.arrayAt(payload, 24),
              let rawEntries = JSONNav.arrayAt(policy, 1) else { return [] }
        var out: [PolicyEntry] = []
        for raw in rawEntries {
            guard let entry = raw as? [Any],
                  let header = JSONNav.arrayAt(entry, 0),
                  let mode = JSONNav.intAt(header, 1),
                  let surfaces = JSONNav.arrayAt(entry, 3),
                  JSONNav.intAt(surfaces, 0) == surface else { continue }
            let variant = JSONNav.stringAt(header, 3) ?? ""
            let short = JSONNav.stringAt(header, 4) ?? ""
            let subtitle = JSONNav.stringAt(header, 5) ?? ""
            let title = JSONNav.stringAt(header, 12) ?? ""
            let upgrade = (JSONNav.arrayAt(header, 14) != nil)
            var levels: [ThinkingLevel] = []
            if let opts = JSONNav.arrayAt(entry, 1) {
                for ro in opts {
                    if let o = ro as? [Any], let code = JSONNav.intAt(o, 0), let lvl = ThinkingLevel(rawValue: code) {
                        levels.append(lvl)
                    }
                }
            }
            out.append(PolicyEntry(mode: mode, variant: variant, upgrade: upgrade, short: short, title: title, subtitle: subtitle, levels: levels))
        }
        return out
    }

    private static func policyLevels(_ entries: [PolicyEntry], mode: Int, variant: String) -> [ThinkingLevel]? {
        for e in entries where e.mode == mode && e.variant == variant {
            return e.levels
        }
        return nil
    }

    private static func parseToolOptions(payload: [Any]) -> [GeminiFeature: [ToolOption]] {
        var result: [GeminiFeature: [ToolOption]] = [:]
        guard let groups = JSONNav.arrayAt(payload, 19) else { return result }
        for rawGroup in groups {
            guard let group = rawGroup as? [Any],
                  let fCode = JSONNav.intAt(group, 0),
                  let feature = GeminiFeature(rawValue: fCode),
                  let items = JSONNav.arrayAt(group, 7) else { continue }
            let kind = JSONNav.intAt(group, 2) ?? 0
            let name = JSONNav.stringAt(group, 3) ?? ""
            for rawItem in items {
                guard let item = rawItem as? [Any],
                      let id = JSONNav.intAt(item, 0) else { continue }
                let label = JSONNav.stringAt(item, 3) ?? ""
                let sel = JSONNav.boolAt(item, 2) ?? false
                result[feature, default: []].append(ToolOption(id: id, group: name, label: label, selected: sel, isSource: kind == 2))
            }
        }
        return result
    }

    private static func resolveModelName(short: String, title: String, subtitle: String) -> (String, String) {
        if !short.isEmpty && subtitle.contains(short) && !title.contains(short) {
            return (subtitle, title)
        }
        return (title, subtitle)
    }

    private static func slugModelID(_ displayName: String) -> String {
        let lower = displayName.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.")
        var out = ""
        var prevDash = false
        for scalar in lower.unicodeScalars {
            if allowed.contains(scalar) {
                out.unicodeScalars.append(scalar)
                prevDash = false
            } else if !prevDash {
                out.append("-")
                prevDash = true
            }
        }
        let slug = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.hasPrefix("gemini-") ? slug : "gemini-\(slug)"
    }

    static func firstMatch(_ text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return "" }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return "" }
        let raw = ns.substring(with: m.range(at: 1))
        return unescapeJSUnicode(raw)
    }

    static func unescapeJSUnicode(_ input: String) -> String {
        guard input.contains("\\u") else { return input }
        guard let regex = try? NSRegularExpression(pattern: #"\\u([0-9a-fA-F]{4})"#, options: []) else { return input }
        var result = input
        let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: (result as NSString).length))
        for m in matches.reversed() {
            let hex = (result as NSString).substring(with: m.range(at: 1))
            if let code = UInt32(hex, radix: 16), let scalar = UnicodeScalar(code) {
                if let range = Range(m.range, in: result) {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }
        return result
    }

    // MARK: - 99-Slot Payload & Model Header Builders

    static func buildGenerateInner99(
        model: GeminiModel,
        thinkingLevel: ThinkingLevel,
        language: String,
        preferences: GeminiPreferences,
        personalIntelligence: Bool,
        toolOptions: [ToolOption]?,
        aspectRatio: String,
        uploadedFiles: [(url: String, mime: String, fileName: String, fileId: String)],
        session: WebSessionState,
        requestUUID: String,
        contextID: String,
        temporaryChat: Bool,
        modelSwitched: Bool
    ) -> [Any] {
        var inner: [Any] = Array(repeating: NSNull(), count: 99)

        var attachmentsObj: Any = NSNull()
        if !uploadedFiles.isEmpty {
            attachmentsObj = uploadedFiles.map { f -> [Any] in
                let fileMeta: [Any] = [f.url, 1, NSNull(), f.mime, f.fileId]
                return [fileMeta, f.fileName, NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), [0]]
            }
        }

        var msgSlot: [Any] = ["", 0, NSNull(), attachmentsObj, NSNull(), NSNull(), 0]
        if model.feature == .image && !aspectRatio.isEmpty {
            let ratioInner: [Any] = [NSNull(), aspectRatio]
            let ratioOuter: [Any] = [NSNull(), ratioInner]
            let toolItem: [Any] = [NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), ratioOuter]
            let extra: [Any] = [NSNull(), NSNull(), toolItem]
            msgSlot.append(contentsOf: extra)
        }
        inner[0] = msgSlot
        inner[1] = [language]
        inner[4] = contextID
        inner[6] = [0]
        inner[7] = 1
        inner[10] = 1
        inner[11] = 0
        inner[17] = [[session.turns]]
        inner[18] = 0
        if !model.gemId.isEmpty {
            inner[19] = model.gemId
        }
        inner[27] = 1
        inner[30] = [4, 27, 28, 16, 19, 12]
        inner[41] = preferences.slot25 ? [1] : [2]
        if temporaryChat {
            inner[45] = 1
        }
        inner[49] = model.feature.rawValue
        inner[53] = 0

        if let opts = toolOptions, !opts.isEmpty {
            var selectedIds: [Int] = []
            var sourceIds: [Int] = []
            for o in opts {
                if o.group == "Aspect ratio" && !aspectRatio.isEmpty {
                    if o.label.contains(aspectRatio) {
                        selectedIds.append(o.id)
                    }
                } else if o.selected {
                    selectedIds.append(o.id)
                    if o.isSource { sourceIds.append(o.id) }
                }
            }
            if sourceIds.isEmpty {
                inner[54] = [Any]()
            } else {
                inner[54] = [[[[sourceIds]]]]
            }
            if selectedIds.isEmpty {
                inner[55] = [Any]()
            } else {
                inner[55] = [selectedIds]
            }
        }

        inner[59] = requestUUID
        inner[61] = [Any]()
        if personalIntelligence {
            inner[67] = temporaryChat ? 0 : 1
        }
        inner[68] = 1

        if !session.cid.isEmpty {
            let tok = temporaryChat ? "" : session.token
            let cont: [Any] = [session.cid, NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), tok]
            inner[71] = cont
        }

        inner[79] = model.mode
        if thinkingLevel != .auto {
            inner[80] = thinkingLevel.rawValue
        }
        if model.feature == .task {
            inner[83] = 1
        }
        inner[91] = preferences.slot261 ? 1 : 0
        inner[96] = modelSwitched ? 1 : 0
        inner[98] = 1
        return inner
    }

    static func buildModelHeaderProtobuf(
        features: [Int],
        model: GeminiModel,
        language: String,
        temporaryChat: Bool,
        tierCode: Int,
        thinkingLevel: ThinkingLevel,
        clientID: String,
        bl: String,
        elapsedMs: Double
    ) -> Data {
        let nowMs = floor(Date().timeIntervalSince1970 * 1000.0)
        func pageDuration(_ ms: Double) -> JSPBEncoder.Value {
            let sec = Int64(floor(ms / 1000.0))
            let ns = Int64(floor((ms - Double(sec) * 1000.0) * 1_000_000.0))
            var arr: [JSPBEncoder.Value] = [sec == 0 ? .null : .int(sec), ns == 0 ? .null : .int(ns)]
            while let last = arr.last, case .null = last { arr.removeLast() }
            return .array(arr)
        }
        let tz = TimeZone.current.identifier
        let timing: JSPBEncoder.Value = .array([pageDuration(elapsedMs), pageDuration(nowMs), .string(tz)])
        var vals: [JSPBEncoder.Value] = [
            .int(1), .null, .null, .null, .string(model.hash), .null, .string(language), .int(temporaryChat ? 1 : 0),
            .packedInts(features), .null, .null, .int(Int64(tierCode)), .null, .null, .int(Int64(model.mode)),
            thinkingLevel == .auto ? .null : .int(Int64(thinkingLevel.rawValue)),
            .string(clientID), .array([.string(bl)]), .null, timing
        ]
        if !model.variant.isEmpty {
            while vals.count < 24 { vals.append(.null) }
            vals.append(.string(model.variant))
        }
        return JSPBEncoder.encode(vals)
    }

    static func buildGenericHeaderJSON(
        features: [Int],
        language: String,
        clientID: String,
        bl: String,
        mode: Int = 0,
        variant: String = "",
        level: ThinkingLevel = .auto
    ) -> String {
        var arr: [Any] = [
            1, NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), language, NSNull(),
            features, NSNull(), NSNull(), NSNull(), NSNull(), NSNull(),
            mode == 0 ? NSNull() : mode,
            level == .auto ? NSNull() : level.rawValue,
            clientID, [bl]
        ]
        if !variant.isEmpty {
            while arr.count < 24 { arr.append(NSNull()) }
            arr.append(variant)
        }
        return GeminiEncoding.pageJSON(arr) ?? "[]"
    }

    // MARK: - Visible Text & Media Sanitization

    static func cleanVisibleText(_ raw: String, candidate: [Any]) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")

        // Strip leading ```json?chameleon ... ``` Bento blocks
        if text.hasPrefix("```json?chameleon") {
            if let range = text.range(of: "\n```\n") {
                text = String(text[range.upperBound...])
            } else if let range = text.range(of: "\n```") {
                text = String(text[range.upperBound...])
            } else {
                return ""
            }
        }

        // Convert Gemini code execution fenced blocks into clean readable Markdown code blocks
        text = replaceRegex(text, pattern: #"(?m)^```([^?`\r\n]*)\?code_reference&code_event_index=\d+"#, template: "```$1")
        text = replaceRegex(text, pattern: #"(?m)^```\?code_stdout&code_event_index=\d+"#, template: "```output")
        text = replaceRegex(text, pattern: #"(?m)^```\?code_stderr&code_event_index=\d+"#, template: "```error")

        // Strip image/video/music/card placeholder URLs & tags
        text = replaceRegex(text, pattern: #"(?m)^https?://googleusercontent\.com/(?:image_generation_content|generated_video_content|generated_music_content|card_content)/\S+\s*"#, template: "")
        text = replaceRegex(text, pattern: #"<Image alt="[^"]*" src="image_generation_content/\d+"/>\s*"#, template: "")

        // Strip follow-up suggestion XML tags
        text = replaceRegex(text, pattern: #"<ElicitationsGroup[^>]*>[\s\S]*?</ElicitationsGroup>"#, template: "")
        text = replaceRegex(text, pattern: #"<Elicitation\b[^>]*/?>"#, template: "")
        text = replaceRegex(text, pattern: #"<FollowUp\b[^>]*/?>"#, template: "")

        // Strip [cite: 1, 2] markers
        text = replaceRegex(text, pattern: #"\s*\[cite:\s*[0-9,\s]+\]"#, template: "")

        // Expand Canvas document chips if present in candidate[30]
        if text.contains("googleusercontent.com/immersive_entry_chip/"),
           let docs = JSONNav.arrayAt(candidate, 30) {
            for rawDoc in docs {
                if let doc = rawDoc as? [Any], let content = JSONNav.stringAt(doc, 4), !content.isEmpty {
                    text = replaceRegex(text, pattern: #"https?://googleusercontent\.com/immersive_entry_chip/\S+"#, template: "\n\n" + content.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "$", with: "\\$") + "\n\n")
                    break
                }
            }
        }

        // Trim <|im_end|>
        if let r = text.range(of: "<|im_end|>") {
            text = String(text[..<r.lowerBound])
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseCitations(from candidate: [Any]) -> [CitationItem] {
        var items: [CitationItem] = []
        var seen = Set<String>()

        // candidate[2][1] grounding groups
        if let groups = JSONNav.valuePath(candidate, 2, 1) as? [Any] {
            for rawGroup in groups {
                guard let group = rawGroup as? [Any],
                      let entries = JSONNav.arrayAt(group, 2) else { continue }
                for rawEntry in entries {
                    guard let entry = rawEntry as? [Any],
                          let url = JSONNav.stringAt(entry, 0), !url.isEmpty,
                          !seen.contains(url) else { continue }
                    seen.insert(url)
                    let title = JSONNav.stringAt(entry, 1) ?? URL(string: url)?.host ?? url
                    let pub = JSONNav.stringAt(entry, 6)
                    items.append(CitationItem(title: title, url: url, publisher: pub))
                }
            }
        }

        // candidate[12]["44"] marker citation table
        if let rich = JSONNav.arrayAt(candidate, 12),
           let table = JSONNav.jspbField(rich, 43) as? [Any] {
            for rawRow in table {
                guard let row = rawRow as? [Any],
                      let sources = JSONNav.arrayAt(row, 1) else { continue }
                for src in sources {
                    if let url = JSONNav.stringPath(src, 3, 0, 1), !url.isEmpty, !seen.contains(url) {
                        seen.insert(url)
                        let title = JSONNav.stringPath(src, 3, 0, 2) ?? URL(string: url)?.host ?? url
                        items.append(CitationItem(title: title, url: url, publisher: URL(string: url)?.host))
                    }
                }
            }
        }
        return items
    }

    static func parseGeneratedImages(from candidate: [Any], session: WebSessionState, rcid: String, model: GeminiModel, level: ThinkingLevel, temporaryChat: Bool) -> [GeneratedImageMeta] {
        guard let rich = JSONNav.arrayAt(candidate, 12),
              let block = JSONNav.jspbField(rich, 7) as? [Any],
              let items = JSONNav.arrayAt(block, 0) else { return [] }
        var out: [GeneratedImageMeta] = []
        for (idx, rawItem) in items.enumerated() {
            guard let item = rawItem as? [Any],
                  let url = JSONNav.stringPath(item, 0, 3, 3), !url.isEmpty else { continue }
            if url.contains("googleusercontent.com/image_generation_content/") { continue }
            let fileName = JSONNav.stringPath(item, 0, 3, 2) ?? "gemini_image_\(idx + 1).jpg"
            let mime = JSONNav.stringPath(item, 0, 3, 11) ?? "image/jpeg"
            let w = JSONNav.intPath(item, 0, 3, 15, 0) ?? 1024
            let h = JSONNav.intPath(item, 0, 3, 15, 1) ?? 1024
            out.append(GeneratedImageMeta(
                url: url, fileName: fileName, mimeType: mime, width: w, height: h,
                entry: item, cid: session.cid, rid: session.rid, rcid: rcid, index: idx,
                mode: model.mode, variant: model.variant, level: level, temporaryChat: temporaryChat
            ))
        }
        return out
    }

    private static func replaceRegex(_ input: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return input }
        let range = NSRange(location: 0, length: (input as NSString).length)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: template)
    }
}
