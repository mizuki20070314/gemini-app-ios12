import Foundation
import UIKit

final class ConversationStore {
    static let shared = ConversationStore()
    static let didChange = Notification.Name("GeminiConversationStore.didChange")

    private let queue = DispatchQueue(label: "com.mizuki.geminiios12.conversationstore")
    private var convMap: [String: Conversation] = [:]
    private let dir: URL
    private let mediaDir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        dir = base.appendingPathComponent("GeminiData", isDirectory: true)
        mediaDir = dir.appendingPathComponent("media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        loadAll()
    }

    var allConversations: [Conversation] {
        return queue.sync {
            Array(convMap.values).sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                return $0.updatedAt > $1.updatedAt
            }
        }
    }

    func conversation(id: String) -> Conversation? {
        return queue.sync { convMap[id] }
    }

    func save(_ conversation: Conversation, touch: Bool = true) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var c = conversation
            if touch { c.updatedAt = Date() }
            self.convMap[c.id] = c
            self.persist(c)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: ConversationStore.didChange, object: self)
            }
        }
    }

    func delete(id: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.convMap.removeValue(forKey: id)
            let url = self.dir.appendingPathComponent("conv_\(id).json")
            try? FileManager.default.removeItem(at: url)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: ConversationStore.didChange, object: self)
            }
        }
    }

    func deleteAll() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.convMap.removeAll()
            if let files = try? FileManager.default.contentsOfDirectory(at: self.dir, includingPropertiesForKeys: nil) {
                for f in files where f.lastPathComponent.hasPrefix("conv_") {
                    try? FileManager.default.removeItem(at: f)
                }
            }
            if let mfiles = try? FileManager.default.contentsOfDirectory(at: self.mediaDir, includingPropertiesForKeys: nil) {
                for f in mfiles { try? FileManager.default.removeItem(at: f) }
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: ConversationStore.didChange, object: self)
            }
        }
    }

    func rename(id: String, title: String) {
        if var c = conversation(id: id) {
            c.title = title
            save(c, touch: false)
        }
    }

    func togglePin(id: String) {
        if var c = conversation(id: id) {
            c.isPinned.toggle()
            save(c, touch: false)
        }
    }

    func search(query: String) -> [Conversation] {
        let q = query.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        guard !q.isEmpty else { return allConversations }
        return queue.sync {
            convMap.values.filter { c in
                if c.title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).contains(q) {
                    return true
                }
                for m in c.messages {
                    if m.text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).contains(q) {
                        return true
                    }
                }
                return false
            }.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    // MARK: - Media file helpers

    func saveMediaData(_ data: Data, preferredExtension ext: String) -> String {
        let cleanExt = ext.isEmpty ? "bin" : ext
        let name = "\(UUID().uuidString).\(cleanExt)"
        let url = mediaDir.appendingPathComponent(name)
        try? data.write(to: url, options: [.atomic])
        return name
    }

    func mediaData(fileName: String) -> Data? {
        let url = mediaDir.appendingPathComponent(fileName)
        return try? Data(contentsOf: url)
    }

    func mediaImage(fileName: String) -> UIImage? {
        guard let data = mediaData(fileName: fileName) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Persistence

    private func loadAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        for f in files {
            let name = f.lastPathComponent
            guard name.hasPrefix("conv_") && name.hasSuffix(".json") else { continue }
            if let data = try? Data(contentsOf: f), let c = try? dec.decode(Conversation.self, from: data) {
                convMap[c.id] = c
            }
        }
    }

    private func persist(_ c: Conversation) {
        let url = dir.appendingPathComponent("conv_\(c.id).json")
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(c) {
            try? data.write(to: url, options: [.atomic])
        }
    }
}
