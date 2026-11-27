import Foundation

enum GeminiWebError: Error, LocalizedError {
    case notInitialized
    case signedOut(String)
    case guestAttachmentsUnsupported
    case httpError(Int, String)
    case protocolError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notInitialized: return "Gemini セッションの初期化が完了していません。"
        case .signedOut(let msg): return msg
        case .guestAttachmentsUnsupported: return "ゲストモードでは画像・ファイル添付は利用できません。設定からGoogleアカウントでログインしてください。"
        case .httpError(let code, let msg): return "通信エラー (HTTP \(code)): \(msg)"
        case .protocolError(let msg): return msg
        case .cancelled: return "生成を停止しました。"
        }
    }
}

struct StreamCallbacks {
    var onThought: (String) -> Void
    var onText: (String) -> Void
    var onTitle: (String) -> Void
    var onModelName: (String) -> Void
    var onCitations: ([CitationItem]) -> Void
    var onGeneratedImages: ([GeneratedImageMeta]) -> Void
    var onComplete: (WebSessionState) -> Void
    var onError: (Error) -> Void
}

/// Complete on-device Gemini Web protocol client (no external relay server).
/// Ports gemini-web2api: Bootstrap -> otAQ7b / ESY5D / jSf9Qc / CNgdBe ->
/// push.clients6.google.com upload + ProcessFile -> WebChannel v1/processSession streaming ->
/// c8o8Fe + ?alr=yes media download -> RotateCookies background rotation.
final class GeminiWebClient: NSObject {
    static let shared = GeminiWebClient()
    static let stateDidChange = Notification.Name("GeminiWebClient.stateDidChange")

    private let geminiOrigin = "https://gemini.google.com"
    private let channelURL = "https://geminiweb-pa.clients6.google.com/v1/processSession"
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/157.0.0.0 Safari/537.36"

    private let loginFeatures = [4, 33, 22, 5, 6, 8, 16, 19, 20, 38]
    private let guestFeatures = [4, 33, 22, 6, 16, 19, 20, 38]

    private let clientID = UUID().uuidString.uppercased()
    private let startTime = Date()
    private var lastTimingMs: Double = 0
    private var reqSeq: Int64 = 0
    private lazy var reqBase: Int64 = {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        let h = Int64(comps.hour ?? 0)
        let m = Int64(comps.minute ?? 0)
        let s = Int64(comps.second ?? 0)
        return h * 3600 + m * 60 + s
    }()

    private let stateQueue = DispatchQueue(label: "com.mizuki.geminiios12.webclient.state")
    private var _bootstrap: GeminiBootstrap?
    private var _isBootstrapping = false
    private var _lastError: String?

    private var activeSession: ActiveWebChannel?
    private var rotationTimer: Timer?
    private var rotationBody: String?

    private lazy var standardSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        cfg.timeoutIntervalForRequest = 45
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg, delegate: NoRedirectDelegate.shared, delegateQueue: nil)
    }()

    var bootstrapState: GeminiBootstrap? {
        return stateQueue.sync { _bootstrap }
    }

    var isBootstrapping: Bool {
        return stateQueue.sync { _isBootstrapping }
    }

    var lastError: String? {
        return stateQueue.sync { _lastError }
    }

    var isGuestSession: Bool {
        if SettingsStore.shared.useGuestMode { return true }
        return !GeminiCookieStore.shared.hasAccountCredentials
    }

    var availableModels: [GeminiModel] {
        return bootstrapState?.models ?? [GeminiModel.fallbackGuest]
    }

    private var authUser: Int {
        return isGuestSession ? 0 : SettingsStore.shared.authUser
    }

    private var pathPrefix: String {
        let au = authUser
        return au > 0 ? "/u/\(au)" : ""
    }

    private func pageURL(_ path: String) -> String {
        return geminiOrigin + pathPrefix + path
    }

    private func nextReqID() -> Int64 {
        return stateQueue.sync {
            reqSeq += 1
            return 1 + reqBase + (reqSeq - 1) * 100_000
        }
    }

    private func nextElapsedMs() -> Double {
        return stateQueue.sync {
            let perf = floor(Date().timeIntervalSince(startTime) * 10_000.0) / 10.0
            let elapsed = max(0, perf - lastTimingMs)
            lastTimingMs = perf
            return elapsed
        }
    }

    private func currentFeatures(isGuest: Bool) -> [Int] {
        return isGuest ? guestFeatures : loginFeatures
    }

    // MARK: - Bootstrap & Catalog Discovery

    func initialize(completion: ((Result<GeminiBootstrap, Error>) -> Void)? = nil) {
        let guest = isGuestSession
        stateQueue.sync {
            _isBootstrapping = true
            _lastError = nil
        }
        notifyStateChange()

        guard let url = URL(string: pageURL("/app")) else {
            finishInit(.failure(GeminiWebError.protocolError("Invalid Gemini URL")), completion: completion)
            return
        }

        var req = makeRequest(url: url, method: "GET", guest: guest)
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        req.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")

        standardSession.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                self.finishInit(.failure(error), completion: completion)
                return
            }
            guard let http = response as? HTTPURLResponse, let data = data else {
                self.finishInit(.failure(GeminiWebError.protocolError("レスポンスを取得できませんでした。")), completion: completion)
                return
            }
            GeminiCookieStore.shared.absorbResponse(http, for: url, guest: guest)
            if http.statusCode == 302 || http.statusCode == 301,
               let loc = http.allHeaderFields["Location"] as? String {
                if loc.contains("/sorry") {
                    self.finishInit(.failure(GeminiWebError.protocolError("Google の確認画面 (/sorry) にリダイレクトされました。しばらく待つか別のネットワークでお試しください。")), completion: completion)
                    return
                }
                if !guest && self.authUser > 0 {
                    self.finishInit(.failure(GeminiWebError.signedOut("アカウント番号 /u/\(self.authUser) のセッションが見つかりません。設定で authuser を確認してください。")), completion: completion)
                    return
                }
            }
            if http.statusCode != 200 {
                self.finishInit(.failure(GeminiWebError.httpError(http.statusCode, "Gemini ページの取得に失敗しました")), completion: completion)
                return
            }
            let html = String(data: data, encoding: .utf8) ?? ""
            do {
                let bs = try GeminiProtocolParser.parseBootstrap(html: html, isGuest: guest)
                if !bs.email.isEmpty {
                    DispatchQueue.main.async { SettingsStore.shared.accountEmail = bs.email }
                }
                self.fetchCatalogAndExtras(bootstrap: bs, completion: completion)
            } catch {
                self.finishInit(.failure(error), completion: completion)
            }
        }.resume()
    }

    private func fetchCatalogAndExtras(bootstrap: GeminiBootstrap, completion: ((Result<GeminiBootstrap, Error>) -> Void)?) {
        var bs = bootstrap
        // Step 2: otAQ7b (Model catalog, fixed hl=en so IDs are stable)
        batchExecute(bootstrap: bs, rpcID: "otAQ7b", payload: "[1]", sourcePath: "/app", language: "en", extensionHeader: "[]") { [weak self] res in
            guard let self = self else { return }
            switch res {
            case .failure(let err):
                self.finishInit(.failure(err), completion: completion)
            case .success(let payload):
                let parsed = GeminiProtocolParser.parseModelCatalog(payload: payload, isGuest: bs.isGuest)
                if !bs.isGuest, let status = parsed.accountStatus {
                    if status == 1016 {
                        self.finishInit(.failure(GeminiWebError.signedOut("セッションが失効しています (1016)。再ログインまたは Cookie 再インポートを行ってください。")), completion: completion)
                        return
                    }
                    if status == 1040 || status == 1042 {
                        let defMode = JSONNav.intAt(payload, 0) ?? 1
                        self.acceptAccountTerms(bootstrap: bs, mode: defMode) { _ in
                            self.fetchCatalogAndExtras(bootstrap: bs, completion: completion)
                        }
                        return
                    }
                }
                bs.models = parsed.models
                bs.toolOptions = parsed.options
                bs.personalIntelligence = parsed.personalIntelligence

                if bs.isGuest {
                    self.finishInit(.success(bs), completion: completion)
                    return
                }

                // Step 3: Fetch Preferences (ESY5D), Usage (jSf9Qc), and Gems (CNgdBe) in parallel
                let group = DispatchGroup()

                group.enter()
                let prefReq = "[null,[25,100,145,222,261]]"
                self.batchExecute(bootstrap: bs, rpcID: "ESY5D", payload: prefReq, sourcePath: "/app", language: bs.language, extensionHeader: "[0]") { r in
                    if case .success(let p) = r {
                        bs.preferences = GeminiProtocolParser.parsePreferences(payload: p)
                    }
                    group.leave()
                }

                group.enter()
                self.batchExecute(bootstrap: bs, rpcID: "jSf9Qc", payload: "[]", sourcePath: "/usage", language: bs.language, extensionHeader: "[0]") { r in
                    if case .success(let p) = r {
                        bs.usage = GeminiProtocolParser.parseUsage(payload: p)
                    }
                    group.leave()
                }

                group.enter()
                let gemReqArr: [Any] = [2, [bs.language], 0]
                let gemPayload = GeminiEncoding.pageJSON(gemReqArr) ?? "[2,[\"ja\"],0]"
                self.batchExecute(bootstrap: bs, rpcID: "CNgdBe", payload: gemPayload, sourcePath: "/app", language: bs.language, extensionHeader: "[0]") { r in
                    if case .success(let p) = r {
                        let gems = GeminiProtocolParser.parseGems(payload: p, baseModel: bs.defaultModel)
                        var seen = Set(bs.models.map { $0.id })
                        for g in gems where !seen.contains(g.id) {
                            seen.insert(g.id)
                            bs.models.append(g)
                        }
                    }
                    group.leave()
                }

                group.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
                    self.finishInit(.success(bs), completion: completion)
                    self.scheduleCookieRotation()
                }
            }
        }
    }

    private func acceptAccountTerms(bootstrap: GeminiBootstrap, mode: Int, completion: @escaping (Bool) -> Void) {
        batchExecute(bootstrap: bootstrap, rpcID: "F6qrid", payload: "[]", sourcePath: "/app", language: bootstrap.language, extensionHeader: "[0]", mode: mode) { [weak self] res in
            guard let self = self else { completion(false); return }
            var version = 0
            if case .success(let p) = res { version = JSONNav.intAt(p, 0) ?? 0 }
            let termsArr: [Any] = [version, bootstrap.language, bootstrap.termsToken]
            let body = GeminiEncoding.pageJSON(termsArr) ?? "[]"
            self.batchExecute(bootstrap: bootstrap, rpcID: "UVb0T", payload: body, sourcePath: "/app", language: bootstrap.language, extensionHeader: "[0]", mode: mode) { r2 in
                if case .success = r2 { completion(true) } else { completion(false) }
            }
        }
    }

    private func finishInit(_ result: Result<GeminiBootstrap, Error>, completion: ((Result<GeminiBootstrap, Error>) -> Void)?) {
        stateQueue.sync {
            _isBootstrapping = false
            switch result {
            case .success(let bs):
                _bootstrap = bs
                _lastError = nil
            case .failure(let err):
                _lastError = err.localizedDescription
            }
        }
        writeDiagnosticsStatus(result)
        if case .success(let bs) = result {
            let cur = SettingsStore.shared.selectedModelId
            if cur.isEmpty || !bs.models.contains(where: { $0.id.lowercased() == cur.lowercased() }) {
                DispatchQueue.main.async {
                    SettingsStore.shared.selectedModelId = bs.defaultModel.id
                }
            }
        }
        notifyStateChange()
        DispatchQueue.main.async {
            completion?(result)
        }
    }

    private func writeDiagnosticsStatus(_ result: Result<GeminiBootstrap, Error>) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("GeminiData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("status.json")
        var dict: [String: Any] = [
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "isGuestSession": isGuestSession,
            "useGuestMode": SettingsStore.shared.useGuestMode,
            "cookieCount": GeminiCookieStore.shared.count,
            "hasAccountCredentials": GeminiCookieStore.shared.hasAccountCredentials,
            "keychainLastStatus": Int(KeychainStore.shared.lastStatus)
        ]
        switch result {
        case .success(let bs):
            dict["ok"] = true
            dict["email"] = bs.email
            dict["bl"] = bs.bl
            dict["language"] = bs.language
            dict["tier"] = bs.usage?.tierName ?? (bs.isGuest ? "Guest" : "Unknown")
            dict["modelCount"] = bs.models.count
            dict["models"] = bs.models.map { $0.id }
        case .failure(let err):
            dict["ok"] = false
            dict["error"] = err.localizedDescription
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    private func notifyStateChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: GeminiWebClient.stateDidChange, object: self)
        }
    }

    // MARK: - BatchExecute RPC

    func batchExecute(
        bootstrap: GeminiBootstrap,
        rpcID: String,
        payload: String,
        sourcePath: String,
        language: String,
        extensionHeader: String,
        mode: Int = 0,
        variant: String = "",
        level: ThinkingLevel = .auto,
        conversationHeader: Bool = false,
        temporaryChat: Bool = false,
        completion: @escaping (Result<[Any], Error>) -> Void
    ) {
        let rpcTuple: [Any] = [rpcID, payload, NSNull(), "generic"]
        guard let fReq = GeminiEncoding.pageJSON([[rpcTuple]]) else {
            completion(.failure(GeminiWebError.protocolError("RPCエンコードに失敗しました")))
            return
        }
        let fullSourcePath = pathPrefix + sourcePath
        let q = "rpcids=\(GeminiEncoding.encodeURIComponent(rpcID))&source-path=\(GeminiEncoding.encodeURIComponent(fullSourcePath))&bl=\(GeminiEncoding.encodeURIComponent(bootstrap.bl))&f.sid=\(GeminiEncoding.encodeURIComponent(bootstrap.fsid))&hl=\(GeminiEncoding.encodeURIComponent(language))&_reqid=\(nextReqID())&rt=c"
        guard let url = URL(string: pageURL("/_/BardChatUi/data/batchexecute") + "?" + q) else {
            completion(.failure(GeminiWebError.protocolError("Invalid batchexecute URL")))
            return
        }

        let form = GeminiEncoding.protocolForm(fReq: fReq, atToken: bootstrap.snlM0e)
        var req = makeRequest(url: url, method: "POST", guest: bootstrap.isGuest)
        req.httpBody = Data(form.utf8)
        req.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue(geminiOrigin, forHTTPHeaderField: "Origin")
        req.setValue(geminiOrigin + "/", forHTTPHeaderField: "Referer")
        req.setValue("1", forHTTPHeaderField: "x-same-domain")
        req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")

        let feats = currentFeatures(isGuest: bootstrap.isGuest)
        let hdr525: String
        if conversationHeader {
            var arr: [Any] = [
                1, NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), language, temporaryChat ? 1 : 0,
                feats + feats, NSNull(), NSNull(), NSNull(), NSNull(), NSNull(),
                mode, level.rawValue, clientID, [bootstrap.bl]
            ]
            if !variant.isEmpty {
                while arr.count < 24 { arr.append(NSNull()) }
                arr.append(variant)
            }
            hdr525 = GeminiEncoding.pageJSON(arr) ?? "[]"
        } else {
            hdr525 = GeminiProtocolParser.buildGenericHeaderJSON(
                features: feats, language: language, clientID: clientID, bl: bootstrap.bl,
                mode: mode, variant: variant, level: level
            )
        }
        req.setValue(hdr525, forHTTPHeaderField: "x-goog-ext-525001261-jspb")
        req.setValue(extensionHeader, forHTTPHeaderField: "x-goog-ext-73010989-jspb")

        standardSession.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse, let data = data else {
                completion(.failure(GeminiWebError.protocolError("空のレスポンス (\(rpcID))")))
                return
            }
            GeminiCookieStore.shared.absorbResponse(http, for: url, guest: bootstrap.isGuest)
            if http.statusCode == 401 || http.statusCode == 403 {
                completion(.failure(GeminiWebError.signedOut("認証エラー (HTTP \(http.statusCode))")))
                return
            }
            if http.statusCode != 200 {
                completion(.failure(GeminiWebError.httpError(http.statusCode, "RPC \(rpcID) 失敗")))
                return
            }
            let records = BatchExecuteParser.extractRecords(from: data)
            for rec in records {
                guard JSONNav.stringAt(rec, 0) == "wrb.fr",
                      JSONNav.stringAt(rec, 1) == rpcID else { continue }
                if let encoded = JSONNav.stringAt(rec, 2), !encoded.isEmpty,
                   let pData = encoded.data(using: .utf8),
                   let parsed = (try? JSONSerialization.jsonObject(with: pData)) as? [Any] {
                    completion(.success(parsed))
                    return
                }
                if let statusArr = JSONNav.arrayAt(rec, 5), JSONNav.intAt(statusArr, 0) == 7 {
                    completion(.failure(GeminiWebError.signedOut("セッションが失効しています (RPC status 7)")))
                    return
                }
            }
            completion(.failure(GeminiWebError.protocolError("RPC \(rpcID) の応答を解析できませんでした")))
        }.resume()
    }

    // MARK: - Attachment Upload (push.clients6.google.com + ProcessFile)

    private func uploadAttachments(
        bootstrap: GeminiBootstrap,
        model: GeminiModel,
        level: ThinkingLevel,
        attachments: [MessageAttachment],
        completion: @escaping (Result<[(url: String, mime: String, fileName: String, fileId: String)], Error>) -> Void
    ) {
        guard !attachments.isEmpty else {
            completion(.success([]))
            return
        }
        if bootstrap.isGuest {
            completion(.failure(GeminiWebError.guestAttachmentsUnsupported))
            return
        }

        let startUploads = {
            let group = DispatchGroup()
            let lock = NSLock()
            var uploaded: [Int: (url: String, mime: String, fileName: String, fileId: String)] = [:]
            var firstError: Error?

            for (idx, att) in attachments.enumerated() {
                if let u = att.uploadedPath, let fid = att.uploadedFileId, !u.isEmpty, !fid.isEmpty {
                    uploaded[idx] = (u, att.mimeType, att.fileName, fid)
                    continue
                }
                guard let fileData = ConversationStore.shared.mediaData(fileName: att.localFileName) else {
                    firstError = GeminiWebError.protocolError("添付ファイル \(att.fileName) を読み込めませんでした")
                    continue
                }
                group.enter()
                self.uploadSingleFile(bootstrap: bootstrap, model: model, level: level, data: fileData, fileName: att.fileName, mimeType: att.mimeType) { res in
                    lock.lock()
                    switch res {
                    case .success(let val): uploaded[idx] = val
                    case .failure(let err): if firstError == nil { firstError = err }
                    }
                    lock.unlock()
                    group.leave()
                }
            }

            group.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
                if let err = firstError {
                    completion(.failure(err))
                    return
                }
                let ordered = (0..<attachments.count).compactMap { uploaded[$0] }
                completion(.success(ordered))
            }
        }

        // Check upload terms expiry (preference slot 145)
        let nowSec = Date().timeIntervalSince1970
        let win = bootstrap.uploadTermsWindowSec
        if win > 0 && (bootstrap.preferences.slot145UploadTerms + win) <= nowSec {
            var msg: [Any] = Array(repeating: NSNull(), count: 145)
            msg[144] = Int64(nowSec)
            let pArr: [Any] = [msg, NSNull(), [145]]
            let p = GeminiEncoding.pageJSON(pArr) ?? "[]"
            batchExecute(bootstrap: bootstrap, rpcID: "L5adhe", payload: p, sourcePath: "/app", language: bootstrap.language, extensionHeader: "[0]", mode: model.mode, variant: model.variant, level: level) { [weak self] _ in
                self?.stateQueue.sync { self?._bootstrap?.preferences.slot145UploadTerms = nowSec }
                startUploads()
            }
        } else {
            startUploads()
        }
    }

    private func uploadSingleFile(
        bootstrap: GeminiBootstrap,
        model: GeminiModel,
        level: ThinkingLevel,
        data: Data,
        fileName: String,
        mimeType: String,
        completion: @escaping (Result<(url: String, mime: String, fileName: String, fileId: String), Error>) -> Void
    ) {
        var startURLStr = bootstrap.uploadURL
        if authUser > 0 {
            startURLStr += (startURLStr.contains("?") ? "&" : "?") + "authuser=\(authUser)"
        }
        guard let startURL = URL(string: startURLStr) else {
            completion(.failure(GeminiWebError.protocolError("Invalid upload URL")))
            return
        }
        var startReq = makeRequest(url: startURL, method: "POST", guest: false)
        startReq.httpBody = Data(("File name: " + fileName).utf8)
        startReq.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        startReq.setValue("resumable", forHTTPHeaderField: "x-goog-upload-protocol")
        startReq.setValue("start", forHTTPHeaderField: "x-goog-upload-command")
        startReq.setValue("\(data.count)", forHTTPHeaderField: "x-goog-upload-header-content-length")
        startReq.setValue(bootstrap.uploadPushID, forHTTPHeaderField: "push-id")
        startReq.setValue(bootstrap.uploadClientContext, forHTTPHeaderField: "x-client-pctx")
        startReq.setValue("bard-storage", forHTTPHeaderField: "x-tenant-id")
        startReq.setValue(geminiOrigin, forHTTPHeaderField: "Origin")
        startReq.setValue(geminiOrigin + "/", forHTTPHeaderField: "Referer")

        standardSession.dataTask(with: startReq) { [weak self] _, resp, err in
            guard let self = self else { return }
            if let err = err { completion(.failure(err)); return }
            guard let http = resp as? HTTPURLResponse else {
                completion(.failure(GeminiWebError.protocolError("アップロード開始に失敗しました")))
                return
            }
            GeminiCookieStore.shared.absorbResponse(http, for: startURL, guest: false)
            guard http.statusCode == 200 else {
                completion(.failure(GeminiWebError.httpError(http.statusCode, "アップロード開始エラー")))
                return
            }
            var uploadURLVal: String?
            for (k, v) in http.allHeaderFields {
                if let ks = k as? String, ks.lowercased() == "x-goog-upload-url", let vs = v as? String {
                    uploadURLVal = vs
                    break
                }
            }
            guard let upStr = uploadURLVal, let upURL = URL(string: upStr) else {
                completion(.failure(GeminiWebError.protocolError("アップロード先 URL が返されませんでした")))
                return
            }

            var finReq = self.makeRequest(url: upURL, method: "POST", guest: false)
            finReq.httpBody = data
            finReq.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
            finReq.setValue("upload, finalize", forHTTPHeaderField: "x-goog-upload-command")
            finReq.setValue("0", forHTTPHeaderField: "x-goog-upload-offset")
            finReq.setValue(bootstrap.uploadPushID, forHTTPHeaderField: "push-id")
            finReq.setValue(bootstrap.uploadClientContext, forHTTPHeaderField: "x-client-pctx")
            finReq.setValue("bard-storage", forHTTPHeaderField: "x-tenant-id")
            finReq.setValue(self.geminiOrigin, forHTTPHeaderField: "Origin")
            finReq.setValue(self.geminiOrigin + "/", forHTTPHeaderField: "Referer")

            self.standardSession.dataTask(with: finReq) { body, resp2, err2 in
                if let err2 = err2 { completion(.failure(err2)); return }
                guard let http2 = resp2 as? HTTPURLResponse, let body = body, http2.statusCode == 200 else {
                    completion(.failure(GeminiWebError.protocolError("ファイル送信に失敗しました")))
                    return
                }
                GeminiCookieStore.shared.absorbResponse(http2, for: upURL, guest: false)
                let remotePath = (String(data: body, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !remotePath.isEmpty else {
                    completion(.failure(GeminiWebError.protocolError("アップロードパスが空です")))
                    return
                }
                self.processFile(bootstrap: bootstrap, model: model, level: level, remotePath: remotePath, fileName: fileName, mimeType: mimeType, completion: completion)
            }.resume()
        }.resume()
    }

    private func processFile(
        bootstrap: GeminiBootstrap,
        model: GeminiModel,
        level: ThinkingLevel,
        remotePath: String,
        fileName: String,
        mimeType: String,
        completion: @escaping (Result<(url: String, mime: String, fileName: String, fileId: String), Error>) -> Void
    ) {
        let fileSpec: [Any] = [remotePath, NSNull(), 1, mimeType]
        let fileEntry: [Any] = [fileSpec, fileName, NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), [0]]
        let innerArr: [Any] = [fileEntry, NSNull(), 1, [bootstrap.language]]
        guard let innerStr = GeminiEncoding.pageJSON(innerArr),
              let outerStr = GeminiEncoding.pageJSON([NSNull(), innerStr] as [Any]) else {
            completion(.failure(GeminiWebError.protocolError("ProcessFile エンコードエラー")))
            return
        }
        let q = "bl=\(GeminiEncoding.encodeURIComponent(bootstrap.bl))&f.sid=\(GeminiEncoding.encodeURIComponent(bootstrap.fsid))&hl=\(GeminiEncoding.encodeURIComponent(bootstrap.language))&_reqid=\(nextReqID())&rt=c"
        guard let url = URL(string: pageURL("/_/BardChatUi/data/assistant.lamda.BardFrontendService/ProcessFile") + "?" + q) else {
            completion(.failure(GeminiWebError.protocolError("Invalid ProcessFile URL")))
            return
        }
        var req = makeRequest(url: url, method: "POST", guest: false)
        req.httpBody = Data(GeminiEncoding.protocolForm(fReq: outerStr, atToken: bootstrap.snlM0e).utf8)
        req.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue(geminiOrigin, forHTTPHeaderField: "Origin")
        req.setValue(geminiOrigin + "/", forHTTPHeaderField: "Referer")
        req.setValue("1", forHTTPHeaderField: "x-same-domain")

        var hdrArr: [Any] = [
            1, NSNull(), NSNull(), NSNull(), model.hash, NSNull(), bootstrap.language, NSNull(),
            loginFeatures, NSNull(), NSNull(), NSNull(), NSNull(), NSNull(),
            model.mode, level.rawValue, clientID, [bootstrap.bl]
        ]
        if !model.variant.isEmpty {
            while hdrArr.count < 24 { hdrArr.append(NSNull()) }
            hdrArr.append(model.variant)
        }
        req.setValue(GeminiEncoding.pageJSON(hdrArr) ?? "[]", forHTTPHeaderField: "x-goog-ext-525001261-jspb")

        standardSession.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            guard let http = resp as? HTTPURLResponse, let data = data, http.statusCode == 200 else {
                completion(.failure(GeminiWebError.protocolError("ProcessFile に失敗しました")))
                return
            }
            GeminiCookieStore.shared.absorbResponse(http, for: url, guest: false)
            for rec in BatchExecuteParser.extractRecords(from: data) {
                if JSONNav.stringAt(rec, 0) == "wrb.fr",
                   let encoded = JSONNav.stringAt(rec, 2),
                   let pData = encoded.data(using: .utf8),
                   let payload = (try? JSONSerialization.jsonObject(with: pData)) as? [Any],
                   let fileId = JSONNav.stringPath(payload, 3, 0), !fileId.isEmpty {
                    completion(.success((remotePath, mimeType, fileName, fileId)))
                    return
                }
            }
            completion(.failure(GeminiWebError.protocolError("ProcessFile からファイル ID を取得できませんでした")))
        }.resume()
    }

    // MARK: - WebChannel Streaming Generation (v1/processSession)

    func streamGenerate(
        prompt: String,
        modelId: String,
        thinkingLevel: ThinkingLevel,
        attachments: [MessageAttachment],
        session: WebSessionState,
        callbacks: StreamCallbacks
    ) {
        let executeWithBootstrap: (GeminiBootstrap) -> Void = { [weak self] bs in
            guard let self = self else { return }
            let model = bs.resolveModel(id: modelId)
            let resolvedLevel = model.resolvedThinkingLevel(thinkingLevel)
            let temporaryChat: Bool
            if bs.isGuest {
                temporaryChat = false
            } else if model.feature.savedChatOnly || session.saved {
                temporaryChat = false
            } else {
                temporaryChat = SettingsStore.shared.temporaryChat
            }

            self.uploadAttachments(bootstrap: bs, model: model, level: resolvedLevel, attachments: attachments) { uploadRes in
                switch uploadRes {
                case .failure(let err):
                    DispatchQueue.main.async { callbacks.onError(err) }
                case .success(let uploadedFiles):
                    self.startWebChannelStream(
                        bootstrap: bs,
                        model: model,
                        thinkingLevel: resolvedLevel,
                        temporaryChat: temporaryChat,
                        prompt: prompt,
                        uploadedFiles: uploadedFiles,
                        session: session,
                        callbacks: callbacks
                    )
                }
            }
        }

        if let bs = bootstrapState, bs.isGuest == isGuestSession {
            executeWithBootstrap(bs)
        } else {
            initialize { res in
                switch res {
                case .success(let bs): executeWithBootstrap(bs)
                case .failure(let err): DispatchQueue.main.async { callbacks.onError(err) }
                }
            }
        }
    }

    func cancelActiveGeneration() {
        let ch = stateQueue.sync { () -> ActiveWebChannel? in
            let current = activeSession
            activeSession = nil
            return current
        }
        ch?.cancel()
    }

    private func startWebChannelStream(
        bootstrap: GeminiBootstrap,
        model: GeminiModel,
        thinkingLevel: ThinkingLevel,
        temporaryChat: Bool,
        prompt: String,
        uploadedFiles: [(url: String, mime: String, fileName: String, fileId: String)],
        session: WebSessionState,
        callbacks: StreamCallbacks
    ) {
        cancelActiveGeneration()

        let requestUUID = UUID().uuidString.uppercased()
        let contextID = GeminiEncoding.randomContextID()
        let feats = currentFeatures(isGuest: bootstrap.isGuest)
        let tierCode = bootstrap.isGuest ? 1 : (bootstrap.usage?.tierCode ?? 1)
        let modelHeaderData = GeminiProtocolParser.buildModelHeaderProtobuf(
            features: feats,
            model: model,
            language: bootstrap.language,
            temporaryChat: temporaryChat,
            tierCode: tierCode,
            thinkingLevel: thinkingLevel,
            clientID: clientID,
            bl: bootstrap.bl,
            elapsedMs: nextElapsedMs()
        )

        var headerLines: [String] = []
        if !bootstrap.isGuest {
            headerLines.append("Authorization:\(GeminiCookieStore.shared.sapisidHashHeader())")
            headerLines.append("X-Goog-AuthUser:\(authUser)")
        }
        headerLines.append("X-Goog-Api-Key:\(bootstrap.apiKey)")
        headerLines.append("X-Server-Token:\(bootstrap.serverToken)")
        headerLines.append("x-goog-ext-525001261-bin:\(modelHeaderData.base64EncodedString())")
        headerLines.append("x-goog-ext-73010989-bin:\(JSPBEncoder.encode([.int(0)]).base64EncodedString())")
        headerLines.append("x-goog-ext-525005358-bin:\(JSPBEncoder.encode([.string(requestUUID), .int(1)]).base64EncodedString())")
        headerLines.append("x-goog-ext-73010990-bin:\(JSPBEncoder.encode([.int(0), .int(0), .int(0)]).base64EncodedString())")
        headerLines.append("X-WebChannel-Content-Type:application/json+protobuf")
        let httpHeadersStr = headerLines.joined(separator: "\r\n") + "\r\n"

        let prevMode = session.lastModelMode != 0 ? session.lastModelMode : bootstrap.defaultModel.mode
        let inner = GeminiProtocolParser.buildGenerateInner99(
            model: model,
            thinkingLevel: thinkingLevel,
            language: bootstrap.language,
            preferences: bootstrap.preferences,
            personalIntelligence: bootstrap.personalIntelligence,
            toolOptions: bootstrap.toolOptions[model.feature],
            aspectRatio: SettingsStore.shared.imageAspectRatio,
            uploadedFiles: uploadedFiles,
            session: session,
            requestUUID: requestUUID,
            contextID: contextID,
            temporaryChat: temporaryChat,
            modelSwitched: model.mode != prevMode
        )

        let metaHdr: [Any] = [1, model.hash, bootstrap.language, requestUUID]
        let innerWrap: [Any] = [inner, NSNull(), NSNull(), 1]
        let bodySlot: [Any] = [NSNull(), NSNull(), NSNull(), NSNull(), innerWrap]
        let req0Inner: [Any] = [metaHdr, 0, NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), bodySlot]
        let req0: [Any] = [req0Inner]
        let req1Inner: [Any] = [1, NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), [prompt]]
        let req1: [Any] = [NSNull(), req1Inner]

        let ch = ActiveWebChannel(
            client: self,
            bootstrap: bootstrap,
            model: model,
            thinkingLevel: thinkingLevel,
            temporaryChat: temporaryChat,
            initialSession: session,
            httpHeaders: httpHeadersStr,
            req0: req0,
            req1: req1,
            callbacks: callbacks
        )
        stateQueue.sync { activeSession = ch }
        ch.start()
    }

    // MARK: - Generated Image Download (c8o8Fe + ?alr=yes relay hops)

    func downloadGeneratedImage(meta: GeneratedImageMeta, completion: @escaping (Result<Data, Error>) -> Void) {
        if let bs = bootstrapState, !bs.isGuest, let c8Payload = buildImageDownloadPayload(meta: meta) {
            batchExecute(
                bootstrap: bs,
                rpcID: "c8o8Fe",
                payload: c8Payload,
                sourcePath: "/app",
                language: bs.language,
                extensionHeader: "[0]",
                mode: meta.mode,
                variant: meta.variant,
                level: meta.level,
                conversationHeader: true,
                temporaryChat: meta.temporaryChat
            ) { [weak self] res in
                guard let self = self else { return }
                if case .success(let p) = res, let dlURL = JSONNav.stringAt(p, 0), !dlURL.isEmpty {
                    self.fetchMediaWithRelay(urlString: dlURL + "=d-I", isGuest: bs.isGuest, hopsRemaining: 6, completion: completion)
                } else {
                    self.fetchMediaWithRelay(urlString: meta.url, isGuest: bs.isGuest, hopsRemaining: 6, completion: completion)
                }
            }
        } else {
            fetchMediaWithRelay(urlString: meta.url, isGuest: isGuestSession, hopsRemaining: 6, completion: completion)
        }
    }

    private func buildImageDownloadPayload(meta: GeneratedImageMeta) -> String? {
        let token = JSONNav.stringPath(meta.entry, 0, 3, 5) ?? ""
        let placeholder = JSONNav.stringPath(meta.entry, 1, 0) ?? ""
        let variant = JSONNav.intPath(meta.entry, 1, 1) ?? 0
        let source = JSONNav.arrayAt(meta.entry, 3)
        var details: [Any] = Array(repeating: NSNull(), count: 23)
        details[0] = JSONNav.intAt(source, 0) ?? 0
        details[1] = JSONNav.stringAt(source, 1) ?? ""
        details[16] = (JSONNav.boolAt(source, 16) ?? false) ? 1 : 0
        if let gen = JSONNav.valuePath(source, 18) { details[18] = gen }
        if let sig = JSONNav.valuePath(source, 22) { details[22] = sig }
        while details.last is NSNull { details.removeLast() }
        let artifactId = JSONNav.stringAt(meta.entry, 8) ?? ""
        var imageId = JSONNav.stringAt(meta.entry, 9) ?? ""
        if imageId.isEmpty {
            imageId = generatedImageID(rcid: meta.rcid, variant: variant, index: meta.index)
        }
        let tokSlot: [Any] = [NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), token]
        let tokWrap: [Any] = [NSNull(), NSNull(), NSNull(), tokSlot]
        let phSlot: [Any] = [placeholder, variant]
        let imageObj: [Any] = [
            tokWrap, phSlot, NSNull(), details,
            NSNull(), NSNull(), NSNull(), NSNull(),
            artifactId, imageId
        ]
        let sessSlot: [Any] = [meta.rid, meta.rcid, meta.cid, NSNull(), imageId]
        let payload: [Any] = [imageObj, sessSlot, 1, meta.temporaryChat ? 1 : 0, 1]
        return GeminiEncoding.pageJSON(payload)
    }

    private func generatedImageID(rcid: String, variant: Int, index: Int) -> String {
        var h: Int32 = 0
        for u in "\(rcid)_\(variant)_\(index)".utf16 {
            h = (h &<< 5) &- h &+ Int32(u)
        }
        let encoded = String(abs(Int64(h)), radix: 36)
        let tail = String(encoded.suffix(12))
        let rep = String(repeating: tail, count: 8)
        return String(rep.prefix(16))
    }

    private func fetchMediaWithRelay(urlString: String, isGuest: Bool, hopsRemaining: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        guard hopsRemaining > 0, var comps = URLComponents(string: urlString) else {
            completion(.failure(GeminiWebError.protocolError("画像ダウンロードのリダイレクト上限に達しました")))
            return
        }
        let host = (comps.host ?? "").lowercased()
        let isGG = (host == "lh3.googleusercontent.com" && (comps.path.hasPrefix("/gg-dl/") || comps.path.hasPrefix("/gg/")))
        if isGG {
            let lastSeg = comps.path.components(separatedBy: "/").last ?? ""
            if !lastSeg.contains("=") {
                comps.path += "=s1024-rj"
            }
            var qItems = comps.queryItems ?? []
            if !qItems.contains(where: { $0.name == "alr" }) {
                qItems.append(URLQueryItem(name: "alr", value: "yes"))
            }
            comps.queryItems = qItems
        }
        guard let url = comps.url else {
            completion(.failure(GeminiWebError.protocolError("Invalid media URL")))
            return
        }
        var req = makeRequest(url: url, method: "GET", guest: isGuest)
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue(geminiOrigin, forHTTPHeaderField: "Origin")
        req.setValue(geminiOrigin + "/", forHTTPHeaderField: "Referer")
        if host.hasSuffix(".usercontent.google.com") {
            req.setValue("same-site", forHTTPHeaderField: "Sec-Fetch-Site")
        } else {
            req.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
            req.setValue("active", forHTTPHeaderField: "Sec-Fetch-Storage-Access")
        }

        standardSession.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(GeminiWebError.protocolError("画像取得に失敗しました")))
                return
            }
            GeminiCookieStore.shared.absorbResponse(http, for: url, guest: isGuest)
            if (300..<400).contains(http.statusCode),
               let loc = http.allHeaderFields["Location"] as? String,
               let next = URL(string: loc, relativeTo: url)?.absoluteString {
                self.fetchMediaWithRelay(urlString: next, isGuest: isGuest, hopsRemaining: hopsRemaining - 1, completion: completion)
                return
            }
            guard http.statusCode == 200, let data = data else {
                completion(.failure(GeminiWebError.httpError(http.statusCode, "画像取得失敗")))
                return
            }
            let ct = (http.allHeaderFields["Content-Type"] as? String ?? "").lowercased()
            if ct.contains("text/plain"), let nextStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               nextStr.hasPrefix("https://") {
                self.fetchMediaWithRelay(urlString: nextStr, isGuest: isGuest, hopsRemaining: hopsRemaining - 1, completion: completion)
                return
            }
            completion(.success(data))
        }.resume()
    }

    // MARK: - Cookie Rotation (RotateCookiesPage + RotateCookies)

    func scheduleCookieRotation() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.rotationTimer?.invalidate()
            guard !self.isGuestSession else { return }
            self.rotationTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
                self?.rotateCookies(completion: nil)
            }
        }
    }

    func rotateCookies(completion: ((Bool, String) -> Void)?) {
        guard !isGuestSession else {
            DispatchQueue.main.async { completion?(false, "ゲストモードでは Cookie ローテーションは不要です") }
            return
        }
        let sendRotate: (String) -> Void = { [weak self] body in
            guard let self = self, let url = URL(string: "https://accounts.google.com/RotateCookies") else { return }
            var req = self.makeRequest(url: url, method: "POST", guest: false)
            req.httpBody = Data(body.utf8)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("https://accounts.google.com", forHTTPHeaderField: "Origin")
            req.setValue("https://accounts.google.com/RotateCookiesPage?og_pid=658&rot=3&origin=https%3A%2F%2Fgemini.google.com&exp_id=0", forHTTPHeaderField: "Referer")
            self.standardSession.dataTask(with: req) { _, resp, err in
                if let err = err {
                    DispatchQueue.main.async { completion?(false, err.localizedDescription) }
                    return
                }
                guard let http = resp as? HTTPURLResponse else {
                    DispatchQueue.main.async { completion?(false, "応答なし") }
                    return
                }
                GeminiCookieStore.shared.absorbResponse(http, for: url, guest: false)
                let ok = (http.statusCode == 200)
                DispatchQueue.main.async {
                    completion?(ok, ok ? "Cookie を更新しました (HTTP 200)" : "Cookie 更新失敗 (HTTP \(http.statusCode))")
                }
            }.resume()
        }

        if let body = stateQueue.sync(execute: { rotationBody }) {
            sendRotate(body)
            return
        }
        guard let pageURL = URL(string: "https://accounts.google.com/RotateCookiesPage?og_pid=658&rot=3&origin=https%3A%2F%2Fgemini.google.com&exp_id=0") else { return }
        var req = makeRequest(url: pageURL, method: "GET", guest: false)
        req.setValue(geminiOrigin + "/", forHTTPHeaderField: "Referer")
        standardSession.dataTask(with: req) { [weak self] data, resp, err in
            guard let self = self else { return }
            if let err = err {
                DispatchQueue.main.async { completion?(false, err.localizedDescription) }
                return
            }
            if let http = resp as? HTTPURLResponse {
                GeminiCookieStore.shared.absorbResponse(http, for: pageURL, guest: false)
            }
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let pattern = #"init\('(-?\d+)',\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*\)"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let m = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)),
               m.numberOfRanges >= 6 {
                let ns = text as NSString
                let sessionVal = ns.substring(with: m.range(at: 1))
                let ogPid = Int(Double(ns.substring(with: m.range(at: 2))) ?? 658)
                let body = "[\(ogPid),\"\(sessionVal)\"]"
                self.stateQueue.sync { self.rotationBody = body }
                sendRotate(body)
            } else {
                DispatchQueue.main.async { completion?(false, "RotateCookiesPage の初期化パラメータを取得できませんでした") }
            }
        }.resume()
    }

    // MARK: - Stop Generation (NkpXw) & Request Helpers

    func sendStopRPC(bootstrap: GeminiBootstrap, cid: String, rid: String, controlToken: String, model: GeminiModel, level: ThinkingLevel) {
        guard !cid.isEmpty, !rid.isEmpty, !controlToken.isEmpty else { return }
        guard let payload = GeminiEncoding.pageJSON([[cid, rid], [controlToken]]) else { return }
        batchExecute(bootstrap: bootstrap, rpcID: "NkpXw", payload: payload, sourcePath: "/app", language: bootstrap.language, extensionHeader: "[0]", mode: model.mode, variant: model.variant, level: level) { _ in }
    }

    fileprivate func makeRequest(url: URL, method: String, guest: Bool) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpShouldHandleCookies = false
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("ja,en-US;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        if !guest, let cookieHeader = GeminiCookieStore.shared.cookieHeader(for: url) {
            req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        return req
    }

    fileprivate func makeChannelRequest(query: String, method: String, body: String?, beacon: Bool, guest: Bool) -> URLRequest? {
        guard let url = URL(string: channelURL + "?" + query) else { return nil }
        var req = makeRequest(url: url, method: method, guest: guest)
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue(geminiOrigin, forHTTPHeaderField: "Origin")
        req.setValue(geminiOrigin + "/", forHTTPHeaderField: "Referer")
        req.setValue("same-site", forHTTPHeaderField: "Sec-Fetch-Site")
        req.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        if beacon {
            req.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.setValue("no-cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        } else {
            req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
            if method == "POST" {
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
        }
        if let body = body {
            req.httpBody = Data(body.utf8)
        }
        return req
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    static let shared = NoRedirectDelegate()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

// MARK: - Active WebChannel Streaming Session

private final class ActiveWebChannel: NSObject, URLSessionDataDelegate {
    private weak var client: GeminiWebClient?
    private let bootstrap: GeminiBootstrap
    private let model: GeminiModel
    private let thinkingLevel: ThinkingLevel
    private let temporaryChat: Bool
    private let httpHeaders: String
    private let req0: [Any]
    private let req1: [Any]
    private let callbacks: StreamCallbacks

    private let lock = NSLock()
    private var gsessionid: String = ""
    private var sid: String = ""
    private var rid: Int = Int.random(in: 10_000..<90_000)
    private var ofs: Int = 0
    private var aid: Int = 0
    private var ended = false
    private var finished = false
    private var cancelled = false

    private var sessionState: WebSessionState
    private var controlToken: String = ""
    private var lastThought: String = ""
    private var lastText: String = ""
    private var lastTitle: String = ""
    private var sawComplete = false
    private var emittedImageURLs = Set<String>()

    private var frameParser = WebChannelFrameParser()
    private var pollSession: URLSession?
    private var pollTask: URLSessionDataTask?
    private let delegateQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()

    init(
        client: GeminiWebClient,
        bootstrap: GeminiBootstrap,
        model: GeminiModel,
        thinkingLevel: ThinkingLevel,
        temporaryChat: Bool,
        initialSession: WebSessionState,
        httpHeaders: String,
        req0: [Any],
        req1: [Any],
        callbacks: StreamCallbacks
    ) {
        self.client = client
        self.bootstrap = bootstrap
        self.model = model
        self.thinkingLevel = thinkingLevel
        self.temporaryChat = temporaryChat
        var next = initialSession
        next.turns += 1
        next.saved = !temporaryChat
        next.lastModelMode = model.mode
        self.sessionState = next
        self.httpHeaders = httpHeaders
        self.req0 = req0
        self.req1 = req1
        self.callbacks = callbacks
        super.init()
    }

    func start() {
        guard let client = client else { return }
        let hsQuery = "VER=8&RID=\(rid)&CVER=22&X-HTTP-Session-Id=gsessionid&%24httpHeaders=\(GeminiEncoding.encodeURIComponent(httpHeaders))&zx=\(GeminiEncoding.randomZX())&t=1"
        rid += 1
        guard let req = client.makeChannelRequest(query: hsQuery, method: "POST", body: "count=0", beacon: false, guest: bootstrap.isGuest) else {
            fail(GeminiWebError.protocolError("WebChannel ハンドシェイク URL 生成失敗"))
            return
        }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 600
        let urlSession = URLSession(configuration: cfg, delegate: self, delegateQueue: delegateQueue)
        self.pollSession = urlSession

        urlSession.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            if self.isClosed { return }
            if let error = error {
                self.fail(error)
                return
            }
            guard let http = response as? HTTPURLResponse, let data = data else {
                self.fail(GeminiWebError.protocolError("ハンドシェイク応答が空です"))
                return
            }
            if let u = req.url {
                GeminiCookieStore.shared.absorbResponse(http, for: u, guest: self.bootstrap.isGuest)
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                self.fail(GeminiWebError.signedOut("セッション認証エラー (HTTP \(http.statusCode))。設定から再ログインしてください。"))
                return
            }
            guard http.statusCode == 200 else {
                self.fail(GeminiWebError.httpError(http.statusCode, "WebChannel ハンドシェイク失敗"))
                return
            }
            var gsid = ""
            for (k, v) in http.allHeaderFields {
                if let ks = k as? String, ks.lowercased() == "x-http-session-id", let vs = v as? String {
                    gsid = vs
                    break
                }
            }
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            let parsedSID = GeminiProtocolParser.firstMatch(bodyStr, pattern: #"\["c","([^"]+)""#)
            guard !gsid.isEmpty, !parsedSID.isEmpty else {
                self.fail(GeminiWebError.protocolError("WebChannel セッション ID の取得に失敗しました"))
                return
            }
            self.lock.lock()
            self.gsessionid = gsid
            self.sid = parsedSID
            self.lock.unlock()

            // Start long-poll AND send req0+req1 concurrently (exact browser/gemini-web2api behavior)
            self.startLongPoll()
            self.sendMessages([self.req0, self.req1])
        }.resume()
    }

    func cancel() {
        lock.lock()
        let already = cancelled || finished
        cancelled = true
        finished = true
        let cid = sessionState.cid
        let curRid = sessionState.rid
        let token = controlToken
        lock.unlock()
        if already { return }

        pollTask?.cancel()
        sendEndMessage()
        client?.sendStopRPC(bootstrap: bootstrap, cid: cid, rid: curRid, controlToken: token, model: model, level: thinkingLevel)
        sendTerminate()
        pollSession?.invalidateAndCancel()
    }

    private var isClosed: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled || finished
    }

    private func startLongPoll() {
        guard !isClosed, let client = client, let urlSession = pollSession else { return }
        lock.lock()
        let q = "gsessionid=\(GeminiEncoding.encodeURIComponent(gsessionid))&VER=8&RID=rpc&SID=\(GeminiEncoding.encodeURIComponent(sid))&AID=\(aid)&CI=0&TYPE=xmlhttp&zx=\(GeminiEncoding.randomZX())&t=1"
        lock.unlock()
        guard let req = client.makeChannelRequest(query: q, method: "GET", body: nil, beacon: false, guest: bootstrap.isGuest) else {
            fail(GeminiWebError.protocolError("ロングポーリング URL 生成失敗"))
            return
        }
        frameParser = WebChannelFrameParser()
        let task = urlSession.dataTask(with: req)
        lock.lock()
        self.pollTask = task
        lock.unlock()
        task.resume()
    }

    private func sendMessages(_ messages: [Any]) {
        guard !isClosed, let client = client, let urlSession = pollSession else { return }
        lock.lock()
        var parts = ["count=\(messages.count)", "ofs=\(ofs)"]
        for (i, msg) in messages.enumerated() {
            guard let json = GeminiEncoding.pageJSON(msg) else {
                lock.unlock()
                fail(GeminiWebError.protocolError("送信メッセージの JSON 化に失敗しました"))
                return
            }
            parts.append("req\(i)___data__=\(GeminiEncoding.encodeURIComponent(json))")
        }
        let q = "VER=8&gsessionid=\(GeminiEncoding.encodeURIComponent(gsessionid))&SID=\(GeminiEncoding.encodeURIComponent(sid))&RID=\(rid)&AID=\(aid)&zx=\(GeminiEncoding.randomZX())&t=1"
        rid += 1
        ofs += messages.count
        lock.unlock()

        guard let req = client.makeChannelRequest(query: q, method: "POST", body: parts.joined(separator: "&"), beacon: false, guest: bootstrap.isGuest) else {
            return
        }
        urlSession.dataTask(with: req) { [weak self] _, resp, err in
            guard let self = self, !self.isClosed else { return }
            if let err = err {
                self.fail(err)
                return
            }
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                self.fail(GeminiWebError.httpError(http.statusCode, "プロンプト送信に失敗しました"))
            }
        }.resume()
    }

    private func sendEndMessage() {
        lock.lock()
        if ended || gsessionid.isEmpty || sid.isEmpty {
            lock.unlock()
            return
        }
        ended = true
        lock.unlock()
        let endMsg: [Any] = [NSNull(), NSNull(), NSNull(), [1]]
        guard let client = client else { return }
        lock.lock()
        let json = GeminiEncoding.pageJSON(endMsg) ?? "[null,null,null,[1]]"
        let body = "count=1&ofs=\(ofs)&req0___data__=\(GeminiEncoding.encodeURIComponent(json))"
        let q = "VER=8&gsessionid=\(GeminiEncoding.encodeURIComponent(gsessionid))&SID=\(GeminiEncoding.encodeURIComponent(sid))&RID=\(rid)&AID=\(aid)&zx=\(GeminiEncoding.randomZX())&t=1"
        rid += 1
        ofs += 1
        lock.unlock()
        if let req = client.makeChannelRequest(query: q, method: "POST", body: body, beacon: false, guest: bootstrap.isGuest) {
            URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
        }
    }

    private func sendTerminate() {
        guard let client = client else { return }
        lock.lock()
        guard !gsessionid.isEmpty, !sid.isEmpty else { lock.unlock(); return }
        let q = "VER=8&gsessionid=\(GeminiEncoding.encodeURIComponent(gsessionid))&SID=\(GeminiEncoding.encodeURIComponent(sid))&RID=\(rid)&TYPE=terminate&zx=\(GeminiEncoding.randomZX())"
        rid += 1
        lock.unlock()
        if let req = client.makeChannelRequest(query: q, method: "POST", body: "", beacon: true, guest: bootstrap.isGuest) {
            URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
        }
    }

    // MARK: - URLSessionDataDelegate (Incremental Streaming)

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            if let u = dataTask.originalRequest?.url {
                GeminiCookieStore.shared.absorbResponse(http, for: u, guest: bootstrap.isGuest)
            }
            if http.statusCode != 200 {
                completionHandler(.cancel)
                fail(GeminiWebError.httpError(http.statusCode, "ストリーミング受信エラー"))
                return
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isClosed else { return }
        let frames = frameParser.append(data)
        for frameData in frames {
            if isClosed { return }
            processFrame(frameData)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !isClosed else { return }
        // Only handle completion of the active pollTask
        lock.lock()
        let isPoll = (task === pollTask)
        lock.unlock()
        guard isPoll else { return }

        if let err = error as NSError? {
            if err.code == NSURLErrorCancelled { return }
            fail(err)
            return
        }
        // Long-poll HTTP stream ended cleanly without terminal frame -> reconnect with updated AID
        if sawComplete {
            succeed()
        } else {
            startLongPoll()
        }
    }

    // MARK: - Frame Decoding

    private func processFrame(_ data: Data) {
        guard let outer = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return }
        for rawItem in outer {
            guard let item = rawItem as? [Any], item.count >= 2 else { continue }
            if let id = JSONNav.intAt(item, 0) {
                lock.lock()
                if id > aid { aid = id }
                lock.unlock()
            }
            let content = item[1]

            // Status / error envelope {"__sm__":{"status":...}}
            if let dict = content as? [String: Any], let sm = dict["__sm__"] as? [String: Any] {
                if let bardCode = JSONNav.intPath(sm["status"], 0, 0, 2, 0, 1, 0) {
                    fail(mapBardError(bardCode))
                    return
                }
                if let statusCode = JSONNav.intPath(sm["status"], 0, 0, 0), statusCode == 16 {
                    fail(GeminiWebError.signedOut("セッション認証が切れました (status 16)。再ログインしてください。"))
                    return
                }
                fail(GeminiWebError.protocolError("Gemini サーバーがエラー状態を返しました。"))
                return
            }

            guard let values = content as? [Any] else { continue }
            if let tag = JSONNav.stringAt(values, 0) {
                if tag == "noop" { continue }
                if tag == "close" {
                    if sawComplete || !lastText.isEmpty {
                        succeed()
                    } else {
                        fail(GeminiWebError.protocolError("応答が完了する前に接続が閉じられました。"))
                    }
                    return
                }
            }

            guard let message = JSONNav.arrayAt(values, 0) else { continue }
            // Terminal frame [null, null, null, []]
            if message.count == 4 && message[1] is NSNull && (message[3] is [Any]) {
                succeed()
                return
            }

            guard let list = JSONNav.valuePath(message, 1, 6) as? [Any] else { continue }
            for entry in list {
                guard let root = JSONNav.valuePath(entry, 3, 3) as? [Any] else { continue }
                decodePayload(root)

                // Check continuation token payload[25]
                if let tok = JSONNav.jspbString(root, 25), !tok.isEmpty {
                    if tok == "response_committed" {
                        sendEndMessage()
                    } else {
                        lock.lock()
                        sessionState.token = tok
                        lock.unlock()
                        succeed()
                        return
                    }
                }
            }
        }
    }

    private func decodePayload(_ payload: [Any]) {
        // Session CID / RID
        if let sessArr = JSONNav.arrayAt(payload, 1) {
            lock.lock()
            if let cid = JSONNav.stringAt(sessArr, 0), !cid.isEmpty { sessionState.cid = cid }
            if let ridVal = JSONNav.stringAt(sessArr, 1), !ridVal.isEmpty { sessionState.rid = ridVal }
            lock.unlock()
        }

        // Metadata: title (10), controlToken (20), modelName (42)
        if let title = JSONNav.firstString(JSONNav.jspbField(payload, 10)), !title.isEmpty, title != lastTitle {
            lastTitle = title
            DispatchQueue.main.async { self.callbacks.onTitle(title) }
        }
        if let ctl = JSONNav.firstString(JSONNav.jspbField(payload, 20)), !ctl.isEmpty {
            lock.lock()
            controlToken = ctl
            lock.unlock()
        }
        if let mName = JSONNav.jspbString(payload, 42), !mName.isEmpty {
            DispatchQueue.main.async { self.callbacks.onModelName(mName) }
        }

        // Candidates container: payload[4]
        guard let container = JSONNav.arrayAt(payload, 4) else { return }
        for rawCand in container {
            guard let cand = rawCand as? [Any],
                  let rcid = JSONNav.stringAt(cand, 0), rcid.hasPrefix("rc_") else { continue }

            lock.lock()
            sessionState.rcid = rcid
            let snap = sessionState
            lock.unlock()

            // Thinking summary: candidate[37][0][0]
            if let thought = JSONNav.stringPath(cand, 37, 0, 0), !thought.isEmpty, thought != lastThought {
                lastThought = thought
                DispatchQueue.main.async { self.callbacks.onThought(thought) }
            }

            // Visible text: candidate[1][0]
            if let rawText = JSONNav.stringPath(cand, 1, 0) {
                let cleaned = GeminiProtocolParser.cleanVisibleText(rawText, candidate: cand)
                if cleaned != lastText && (!cleaned.isEmpty || !lastText.isEmpty) {
                    lastText = cleaned
                    DispatchQueue.main.async { self.callbacks.onText(cleaned) }
                }
            }

            // Citations
            let citations = GeminiProtocolParser.parseCitations(from: cand)
            if !citations.isEmpty {
                DispatchQueue.main.async { self.callbacks.onCitations(citations) }
            }

            // Generated images
            let images = GeminiProtocolParser.parseGeneratedImages(
                from: cand, session: snap, rcid: rcid,
                model: model, level: thinkingLevel, temporaryChat: temporaryChat
            )
            let newImages = images.filter { !emittedImageURLs.contains($0.url) }
            if !newImages.isEmpty {
                for img in newImages { emittedImageURLs.insert(img.url) }
                DispatchQueue.main.async { self.callbacks.onGeneratedImages(newImages) }
            }

            // Phase: candidate[8][0] == 2 means complete
            if JSONNav.intPath(cand, 8, 0) == 2 {
                sawComplete = true
            }
            break // Primary candidate
        }
    }

    private func mapBardError(_ code: Int) -> Error {
        switch code {
        case 1037: return GeminiWebError.protocolError("このモデルの利用上限に達しました (1037)。別のモデルをお試しください。")
        case 1050: return GeminiWebError.protocolError("モデルと会話履歴が一致しません (1050)。新しいチャットを作成してください。")
        case 1052: return GeminiWebError.protocolError("モデルが一時的に利用できません (1052)。")
        case 1060: return GeminiWebError.protocolError("現在のネットワークからのアクセスが一時制限されています (1060)。")
        case 1095: return GeminiWebError.protocolError("リクエスト頻度制限に達しました (1095)。少し待ってから再試行してください。")
        case 1097: return GeminiWebError.protocolError("Webセッションの有効期限が切れました (1097)。新しいチャットでお試しください。")
        case 1100: return GeminiWebError.protocolError("添付ファイルを読み取れませんでした (1100)。")
        default: return GeminiWebError.protocolError("Gemini Web エラー (コード: \(code))")
        }
    }

    private func succeed() {
        lock.lock()
        if finished { lock.unlock(); return }
        finished = true
        let finalState = sessionState
        lock.unlock()

        sendEndMessage()
        sendTerminate()
        pollSession?.finishTasksAndInvalidate()
        DispatchQueue.main.async {
            self.callbacks.onComplete(finalState)
        }
    }

    private func fail(_ error: Error) {
        lock.lock()
        if finished { lock.unlock(); return }
        finished = true
        lock.unlock()

        pollTask?.cancel()
        sendTerminate()
        pollSession?.invalidateAndCancel()
        DispatchQueue.main.async {
            self.callbacks.onError(error)
        }
    }
}
