import Foundation

/// 单个清除目标
struct WipeTarget: Identifiable, Codable, Equatable, Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    var id: UUID
    var name: String          // 显示名称，如 "Reasonix Keys"
    var filePath: String      // 文件路径，如 "~/.reasonix/.env"
    var enabled: Bool         // 启用/禁用
    var customPatterns: [String]  // 自定义匹配模式，如 ["QQ_BOT", "STORAGE_ENCRYPTION"]

    init(id: UUID = UUID(), name: String, filePath: String, enabled: Bool = true,
         customPatterns: [String] = []) {
        self.id = id
        self.name = name
        self.filePath = filePath
        self.enabled = enabled
        self.customPatterns = customPatterns
    }

    /// 自定义解码：兼容没有 customPatterns 字段的旧数据
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        filePath = try container.decode(String.self, forKey: .filePath)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        customPatterns = try container.decodeIfPresent([String].self, forKey: .customPatterns) ?? []
    }

    /// 展开 ~ 为完整路径
    var expandedPath: String {
        (filePath as NSString).expandingTildeInPath
    }
}

/// 清除结果
struct WipeResult: Identifiable {
    let id = UUID()
    let targetId: UUID?         // 对应 WipeTarget.id，用于清除后自动移除
    let targetName: String
    let status: WipeStatus
    let message: String
    let timestamp: Date

    enum WipeStatus {
        case success
        case skipped
        case failed
        case backedUp
    }
}

/// 预设模板（一键添加常见路径）
struct PresetTemplate: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let description: String
}
