import Foundation

/// Gemini Web thinking level protocol codes (mirrors internal/gemini/request.go)
enum ThinkingLevel: Int, Codable, CaseIterable {
    case auto = 0
    case low = 1
    case medium = 4
    case high = 2

    var displayName: String {
        switch self {
        case .auto: return "自動"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var shortLabel: String {
        switch self {
        case .auto: return "思考: 自動"
        case .low: return "思考: Low"
        case .medium: return "思考: Med"
        case .high: return "思考: High"
        }
    }

    var rank: Int {
        switch self {
        case .auto: return -1
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }
}

/// Gemini Web feature mode codes (mirrors internal/gemini/request.go)
enum GeminiFeature: Int, Codable {
    case chat = 0
    case deepResearch = 1
    case canvas = 2
    case video = 11
    case image = 14
    case music = 21
    case guidedLearning = 24
    case task = 40

    var savedChatOnly: Bool {
        return self == .task || self == .deepResearch || self == .video
    }
}

/// Dynamically discovered Gemini Web model / tool / Gem (from otAQ7b & CNgdBe)
struct GeminiModel: Codable, Equatable {
    let id: String
    let displayName: String
    let description: String
    let hash: String
    let mode: Int
    let isDefault: Bool
    let thinkingLevels: [ThinkingLevel]
    let feature: GeminiFeature
    let gemId: String
    let variant: String

    var isTool: Bool { return feature != .chat }
    var isGem: Bool { return !gemId.isEmpty }

    func resolvedThinkingLevel(_ requested: ThinkingLevel) -> ThinkingLevel {
        guard !thinkingLevels.isEmpty else { return .auto }
        if requested == .auto {
            // Prefer medium or first available
            if thinkingLevels.contains(.medium) { return .medium }
            return thinkingLevels.first ?? .auto
        }
        if thinkingLevels.contains(requested) { return requested }
        var selected = thinkingLevels[0]
        var found = false
        for lvl in thinkingLevels {
            if lvl.rank <= requested.rank && (!found || lvl.rank > selected.rank) {
                selected = lvl
                found = true
            }
            if !found && lvl.rank < selected.rank {
                selected = lvl
            }
        }
        return selected
    }

    static let fallbackGuest = GeminiModel(
        id: "gemini-auto",
        displayName: "Auto",
        description: "Adapts to your needs (Guest)",
        hash: "cf41b0e0dd7d53e5",
        mode: 6,
        isDefault: true,
        thinkingLevels: [],
        feature: .chat,
        gemId: "",
        variant: ""
    )
}

struct ToolOption: Codable {
    let id: Int
    let group: String
    let label: String
    let selected: Bool
    let isSource: Bool
}

struct UsageWindowInfo: Codable {
    let kind: Int // 1 = 5h, 2 = weekly, 3 = credits
    let remaining: Double?
    let usedRatio: Double?
    let resetAt: Date?
}

struct GeminiUsageInfo: Codable {
    let tierCode: Int // 1=Free, 2=Pro, 3/6=Ultra, 4=Plus
    let windows: [UsageWindowInfo]

    var tierName: String {
        switch tierCode {
        case 1: return "Free"
        case 2: return "AI Pro"
        case 3, 6: return "AI Ultra"
        case 4: return "AI Plus"
        default: return "Unknown"
        }
    }

    var contextWindow: Int {
        switch tierCode {
        case 2, 3, 6: return 1_048_576
        case 4: return 131_072
        default: return 32_768
        }
    }
}

/// Per-conversation Gemini Web session state (CID/RID/RCID/Token for multi-turn continuation)
struct WebSessionState: Codable, Equatable {
    var cid: String = ""
    var rid: String = ""
    var rcid: String = ""
    var token: String = ""
    var turns: Int = 0
    var saved: Bool = false
    var lastModelMode: Int = 0
}

struct CitationItem: Codable, Equatable {
    let title: String
    let url: String
    let publisher: String?
}

struct MessageAttachment: Codable, Equatable {
    let id: String
    let fileName: String
    let mimeType: String
    let localFileName: String // stored in GeminiData/media/
    var uploadedPath: String?
    var uploadedFileId: String?

    var isImage: Bool {
        return mimeType.lowercased().hasPrefix("image/")
    }
}

struct GeneratedMediaItem: Codable, Equatable {
    let id: String
    let url: String
    let fileName: String
    let mimeType: String
    let localFileName: String?
    let width: Int
    let height: Int
}

struct ChatMessage: Codable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: String
    let role: Role
    var text: String
    var thinking: String?
    var attachments: [MessageAttachment]
    var generatedMedia: [GeneratedMediaItem]
    var citations: [CitationItem]
    var modelName: String?
    var errorMessage: String?
    let createdAt: Date

    init(id: String = UUID().uuidString,
         role: Role,
         text: String,
         thinking: String? = nil,
         attachments: [MessageAttachment] = [],
         generatedMedia: [GeneratedMediaItem] = [],
         citations: [CitationItem] = [],
         modelName: String? = nil,
         errorMessage: String? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.thinking = thinking
        self.attachments = attachments
        self.generatedMedia = generatedMedia
        self.citations = citations
        self.modelName = modelName
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }
}

struct Conversation: Codable {
    let id: String
    var title: String
    var messages: [ChatMessage]
    var modelId: String
    var thinkingLevel: ThinkingLevel
    var isPinned: Bool
    var webSession: WebSessionState
    let createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         title: String = "新しいチャット",
         messages: [ChatMessage] = [],
         modelId: String = "",
         thinkingLevel: ThinkingLevel = .auto,
         isPinned: Bool = false,
         webSession: WebSessionState = WebSessionState(),
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.modelId = modelId
        self.thinkingLevel = thinkingLevel
        self.isPinned = isPinned
        self.webSession = webSession
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
