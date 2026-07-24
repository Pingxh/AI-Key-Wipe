import Foundation
import Combine

/// 持久化存储清除目标列表
class TargetStore: ObservableObject {
    @Published var targets: [WipeTarget] = []

    private let saveKey = "wipeTargets"

    init() {
        load()
    }

    // MARK: - 预设模板（可一键添加）
    static let presets: [PresetTemplate] = [
        PresetTemplate(name: "Reasonix 密钥", path: "~/.reasonix/.env",
                       description: "DEEPSEEK, OPENROUTER, KIMI 等 API Key"),
        PresetTemplate(name: "Hermes 密钥", path: "~/.hermes/.env",
                       description: "Hermes Agent 主配置中的 Key"),
        PresetTemplate(name: "Hermes Config", path: "~/.hermes/config.yaml",
                       description: "YAML 中 providers.*.api_key"),
        PresetTemplate(name: "Omniroute 密钥", path: "~/.omniroute/.env",
                       description: "加密密钥等敏感信息"),
        PresetTemplate(name: "Claude 设置", path: "~/.claude/settings.json",
                       description: "Claude 环境变量和模型配置"),
        PresetTemplate(name: "Claude MCP 配置", path: "~/.claude/mcp.json",
                       description: "MCP 服务器令牌（如 GITEE_ACCESS_TOKEN）"),
        PresetTemplate(name: "Claude 对话历史", path: "~/.claude/history.jsonl",
                       description: "完整对话记录（含上下文泄露的 Key）"),
        PresetTemplate(name: "GitHub Copilot", path: "~/.config/github-copilot/hosts.json",
                       description: "Copilot OAuth Token"),
        PresetTemplate(name: "Shell 历史", path: "~/.zsh_history",
                       description: "清除历史命令中泄露的 API Key"),
        PresetTemplate(name: "Hermes 历史记录", path: "~/.hermes/.hermes_history",
                       description: "Hermes 对话历史"),
    ]

    // MARK: - 添加/删除/更新
    func add(_ target: WipeTarget) {
        targets.append(target)
        save()
    }

    func remove(_ target: WipeTarget) {
        targets.removeAll { $0.id == target.id }
        save()
    }

    func update(_ target: WipeTarget) {
        if let index = targets.firstIndex(where: { $0.id == target.id }) {
            targets[index] = target
            save()
        }
    }

    func toggle(_ target: WipeTarget) {
        if let index = targets.firstIndex(where: { $0.id == target.id }) {
            targets[index].enabled.toggle()
            save()
        }
    }

    /// 添加预设（去重）
    func addPreset(_ preset: PresetTemplate) {
        // 避免重复添加相同路径
        if targets.contains(where: { $0.expandedPath == (preset.path as NSString).expandingTildeInPath }) {
            return
        }
        add(WipeTarget(name: preset.name, filePath: preset.path))
    }

    // MARK: - 持久化
    private func save() {
        if let data = try? JSONEncoder().encode(targets) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([WipeTarget].self, from: data) {
            targets = decoded
        }
        // 首次启动或旧数据解码失败 → 空列表，由用户自行扫描添加
    }
}
