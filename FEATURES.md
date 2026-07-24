# AI-Key-Wipe 功能文档

> **版本**: 1.0.0  
> **最后更新**: 2026-07-23

---

## 目录

1. [目标管理](#1-目标管理)
2. [匹配模式系统](#2-匹配模式系统)
3. [文件清除引擎](#3-文件清除引擎)
4. [Shell 历史清洗](#4-shell-历史清洗)
5. [对话历史清空](#5-对话历史清空)
6. [备份与恢复](#6-备份与恢复)
7. [选择与清除逻辑](#7-选择与清除逻辑)
8. [自动移除](#8-自动移除)
9. [文件路径选择器](#9-文件路径选择器)
10. [预设模板](#10-预设模板)
11. [持久化存储](#11-持久化存储)
12. [UI 交互规范](#12-ui-交互规范)

---

## 1. 目标管理

### 1.1 数据模型 (WipeTarget)

```swift
struct WipeTarget: Identifiable, Codable, Equatable, Hashable {
    var id: UUID              // 唯一标识
    var name: String          // 显示名称，如 "Reasonix Keys"
    var filePath: String      // 文件路径，如 "~/.reasonix/.env"
    var enabled: Bool         // 启用/禁用
    var customPatterns: [String]  // 自定义匹配模式
}
```

### 1.2 CRUD 操作 (TargetStore)

| 操作 | 方法 | 说明 |
|------|------|------|
| 新增 | `add(_ target:)` | 添加目标到列表并持久化 |
| 删除 | `remove(_ target:)` | 从列表删除并持久化 |
| 更新 | `update(_ target:)` | 更新目标属性并持久化 |
| 切换启用 | `toggle(_ target:)` | 切换启用/禁用状态 |
| 添加预设 | `addPreset(_ preset:)` | 去重添加预设模板 |

### 1.3 多选管理

```swift
@State private var selectedIds: Set<WipeTarget.ID> = []

// 实时计算属性——始终从 store 中查找最新数据
private var selectedTargets: [WipeTarget] {
    store.targets.filter { selectedIds.contains($0.id) }
}
```

**设计原因**：`WipeTarget` 是值类型。若直接存 `Set<WipeTarget>` 则右侧详情持有值副本，编辑时 `store.update(t)` 后副本不同步。改用 `Set<UUID>` + 计算属性每次从 `store.targets` 实时查找，保证数据始终最新。

### 1.4 交互方式

- **单击**: 选中单个目标，右侧显示详情
- **⌘+点击**: 切换选中/取消（多选）
- **⇧+点击**: 范围连选
- **⌘+A**: 全选
- **右键菜单**: 编辑 / 启用禁用 / 删除
- **删除键**: 删除选中目标

---

## 2. 匹配模式系统

### 2.1 架构

匹配模式采用 **内置默认模式 + 用户自定义模式** 合并策略：

```
buildPatterns(custom: [String]) → [String]
    │
    ├── 1. 载入内置默认模式
    │      ["KEY=", "API_KEY=", "TOKEN=", "SECRET=", 
    │       "PASSWORD=", "api_key:", "token:", "secret:", "_API_KEY"]
    │
    ├── 2. 遍历用户自定义模式，去重追加
    │      (大小写不敏感去重)
    │
    └── 3. 返回合并后的模式列表
```

### 2.2 内置默认模式

| 模式 | 匹配示例 |
|------|----------|
| `KEY=` | `DEEPSEEK_API_KEY=sk-xxx` |
| `API_KEY=` | `OPENAI_API_KEY=sk-xxx` |
| `TOKEN=` | `GITEE_ACCESS_TOKEN=xxx` |
| `SECRET=` | `QQ_CLIENT_SECRET=xxx` |
| `PASSWORD=` | `SUDO_PASSWORD=xxx` |
| `api_key:` | YAML 格式 `api_key: sk-xxx` |
| `token:` | YAML 格式 `token: xxx` |
| `secret:` | YAML 格式 `secret: xxx` |
| `_API_KEY` | 兜底匹配 `OPENROUTER_API_KEY` 等 |

### 2.3 自定义模式

每个目标可独立配置自定义匹配模式：

```
界面入口：详情页 → 自定义匹配模式 区域
格式：   一行一个关键词
示例：   QQ_BOT
         STORAGE_ENCRYPTION
         MINIMAX
```

自定义关键词与内置模式**合并匹配**，不覆盖内置模式。

### 2.4 扫描 (scanFile)

```swift
func scanFile(at path: String, customPatterns: [String] = []) -> [String]
```

- 按行读取文件
- 跳过注释行（`#` / `//` 开头）
- 用合并后的模式列表逐行匹配
- 返回匹配到的内容（值已被 `=******` 脱敏）

---

## 3. 文件清除引擎

### 3.1 核心方法

```swift
func wipeFile(at path: String, customPatterns: [String] = [], 
              targetId: UUID? = nil, backup: Bool = true) -> WipeResult?
```

### 3.2 处理流程

```
wipeFile(path)
    │
    ├── 1. 文件存在性检查
    │      └── 不存在 → return nil
    │
    ├── 2. 备份
    │      └── 复制到 ~/AI-Key-Wipe/backups/{timestamp}/
    │
    ├── 3. 逐行处理
    │      ├── 注释行 → 保留
    │      ├── 匹配行 → 清除值（见下方格式处理）
    │      └── 其他行 → 保留
    │
    └── 4. 写入文件 → 返回 WipeResult
```

### 3.3 格式处理

| 原始格式 | 示例输入 | 清除后 |
|----------|----------|--------|
| export KEY=value | `export OPENAI_KEY=sk-xxx` | `export OPENAI_KEY=` |
| KEY=value | `DEEPSEEK_API_KEY=sk-xxx` | `DEEPSEEK_API_KEY=` |
| YAML key: value | `api_key: sk-xxx` | `api_key: ""` |
| YAML key:\n  value | `api_key:\n  sk-xxx` | `api_key: ""` (并跳过下行) |

### 3.4 多行值处理 (skipIndentedValue)

```swift
var skipIndentedValue = false
```

当遇到 YAML `key:` 行且冒号后无值时：
1. 将该行替换为 `key: ""`
2. 设置 `skipIndentedValue = true`
3. 下一行若是缩进内容（以空格开头），则跳过

```yaml
# 清除前                          # 清除后
providers:                        providers:
  deepseek:                         deepseek:
    api_key:                        api_key: ""
      sk-HNSCKzuPrFP1sxOsBMy        ← 自动跳过这行
```

### 3.5 清除结果 (WipeResult)

```swift
struct WipeResult: Identifiable {
    let id = UUID()
    let targetId: UUID?         // 对应 WipeTarget.id
    let targetName: String      // 显示名称
    let status: WipeStatus      // success / skipped / failed / backedUp
    let message: String         // 详情消息
    let timestamp: Date         // 操作时间
}
```

---

## 4. Shell 历史清洗

### 4.1 处理文件

- `~/.zsh_history`
- `~/.bash_history`

### 4.2 过滤逻辑

逐行检查，删除包含以下关键词的行（大小写不敏感）：

```
API_KEY, APIKEY, OPENAI, ANTHROPIC, DEEPSEEK, GEMINI, SECRET
```

### 4.3 处理方式

```
原始历史:
> export DEEPSEEK_API_KEY=sk-xxx    ← 删除
> ls -la                            ← 保留
> curl https://api.openai.com/...   ← 删除
> cd projects                       ← 保留
```

---

## 5. 对话历史清空

### 5.1 处理文件

- `~/.hermes/.hermes_history`
- `~/.claude/history.jsonl`
- 任何以 `_history` 或 `history.jsonl` 结尾的文件

### 5.2 处理方式

将文件内容直接清空（写入空字符串），保留文件本身。

---

## 6. 备份与恢复

### 6.1 备份结构

```
~/AI-Key-Wipe/backups/
└── 20260723_183000/              # 时间戳目录
    ├── _manifest.txt             # 操作清单
    ├── reasonix-.env             # 原始文件副本
    ├── hermes-config.yaml
    └── ...
```

### 6.2 清单文件格式 (_manifest.txt)

```
1. Reasonix 密钥 → ~/.reasonix/.env
2. Hermes Config → ~/.hermes/config.yaml
3. Claude 设置 → ~/.claude/settings.json
```

### 6.3 恢复逻辑 (restore-wipe.sh)

1. 扫描 `backups/` 目录下的所有时间戳备份
2. 列出每个备份的文件数量和大小
3. 用户选择要恢复的时间点
4. 将备份文件覆盖回原路径
5. 恢复完成后提示重新打开 Terminal

---

## 7. 选择与清除逻辑

### 7.1 选择状态与清除范围

| 列表选择状态 | 按钮文字 | 清除范围 |
|-------------|----------|----------|
| 未选中任何目标 | 灰色不可点击 | — |
| 选中 1 个 | `清除所选 (1)` | 仅该文件 |
| 选中 3 个 | `清除所选 (3)` | 仅这 3 个文件 |
| 全选 (10 个) | `清除所选 (10)` | 全部 10 个 |

### 7.2 执行流程

```
点击「清除所选」按钮
    │
    ├──→ 弹出确认弹窗
    │      将清除 3 个选中的文件中的所有 API Key。
    │      Reasonix 密钥、Hermes Config、Claude 设置
    │      已备份的文件可随时恢复。
    │      [取消] [确认清除]
    │
    ├──→ 用户确认 → startWipe()
    │
    ├──→ WipeService.executeWipe() 按序处理每个目标
    │      ├── 跳过已禁用目标
    │      ├── 备份原始文件
    │      ├── 清除匹配到的 Key
    │      └── 返回结果
    │
    └──→ 显示结果面板
           ├── ✓ Hermes Config — 已清除 4 个 Key
           ├── ✓ Claude 设置 — 已清除 2 个 Key
           └── ⚠ Reasonix 密钥 — 文件不存在
```

### 7.3 右侧面板状态

| 条件 | 显示内容 |
|------|----------|
| 未选中任何目标 | 空状态提示："选择一个或多个清除目标" |
| 选中 1 个目标 | 目标详情编辑页 |
| 选中多个目标 | 多选摘要：列出所有选中目标的名称和路径 |
| 清除完成 | 结果面板：每条结果的状态图标 + 消息 |

---

## 8. 自动移除

### 8.1 功能描述

清除成功后可选择自动将目标从列表移除，避免手动删除的重复操作。

### 8.2 开关位置

列表底部「执行清除」按钮下方：
```
☐ 清除成功后自动从列表移除
```

默认开启。

### 8.3 实现逻辑

```swift
if autoRemoveAfterWipe {
    let successIds = results.compactMap { r in
        if case .success = r.status { return r.targetId }
        return nil
    }
    for id in successIds {
        if let target = store.targets.first(where: { $0.id == id }) {
            store.remove(target)
        }
    }
    selectedIds.subtract(Set(successIds))
}
```

- 仅移除 `status == .success` 的目标
- 失败或跳过的目标保留在列表中
- 同步从选中 ID 集合中移除

---

## 9. 文件路径选择器

### 9.1 使用场景

| 场景 | 触发方式 |
|------|----------|
| 添加自定义目标 | 点击列表底部 [+ 自定义] 按钮 |
| 修改目标路径 | 在详情页点击 [选择…] 按钮 |

### 9.2 NSOpenPanel 配置

```swift
panel.title = "选择要清除的文件或目录"
panel.prompt = "选择" / "添加"
panel.canChooseFiles = true
panel.canChooseDirectories = true
panel.allowsMultipleSelection = false
panel.showsHiddenFiles = true    // 显示隐藏文件（.env 等）
```

### 9.3 自动命名

选定文件后，自动生成目标名称：
```
选择: ~/.reasonix/.env
生成名称: reasonix/.env
```

使用父目录名 + 文件名作为默认名称，便于区分不同目录下同名文件。

---

## 10. 预设模板

### 10.1 数据定义

```swift
struct PresetTemplate: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let description: String
}
```

### 10.2 完整预设列表

| 名称 | 路径 | 描述 |
|------|------|------|
| Reasonix 密钥 | `~/.reasonix/.env` | DEEPSEEK, OPENROUTER, KIMI 等 API Key |
| Hermes 密钥 | `~/.hermes/.env` | Hermes Agent 主配置中的 Key |
| Hermes Config | `~/.hermes/config.yaml` | YAML 中 providers.*.api_key |
| Omniroute 密钥 | `~/.omniroute/.env` | 加密密钥等敏感信息 |
| Claude 设置 | `~/.claude/settings.json` | Claude 环境变量和模型配置 |
| Claude MCP 配置 | `~/.claude/mcp.json` | MCP 服务器令牌（如 GITEE_ACCESS_TOKEN） |
| Claude 对话历史 | `~/.claude/history.jsonl` | 完整对话记录（含上下文泄露的 Key） |
| GitHub Copilot | `~/.config/github-copilot/hosts.json` | Copilot OAuth Token |
| Shell 历史 | `~/.zsh_history` | 清除历史命令中泄露的 API Key |
| Hermes 历史记录 | `~/.hermes/.hermes_history` | Hermes 对话历史 |

### 10.3 去重机制

```swift
func addPreset(_ preset: PresetTemplate) {
    // 展开 ~ 后比较实际路径，避免重复添加
    if targets.contains(where: { $0.expandedPath == preset.path.fullPath }) {
        return
    }
    add(WipeTarget(name: preset.name, filePath: preset.path))
}
```

---

## 11. 持久化存储

### 11.1 目标配置

- **存储方式**: `UserDefaults`
- **存储键**: `wipeTargets`
- **数据格式**: JSON（`JSONEncoder` / `JSONDecoder`）
- **首次启动**: 自动加载全部 10 个预设模板

### 11.2 备份文件

- **存储位置**: `~/AI-Key-Wipe/backups/{timestamp}/`
- **存储内容**: 清除前的原始文件副本
- **附带文件**: `_manifest.txt` 操作清单

---

## 12. UI 交互规范

### 12.1 窗口布局

```
┌─────────────────────────────────────────────────┐
│  HSplitView                                      │
│                                                   │
│  ┌─────────── 280~400px ───────┬── 300px+ ──────┐│
│  │ 清除目标    3/10             │ (详情/结果区)    ││
│  │─────────────────────────────│                 ││
│  │ ☑ Reasonix 密钥             │ 选中 1 个:      ││
│  │ ☑ Hermes 密钥               │  名称/路径/启用  ││
│  │ ☑ Claude 设置               │  自定义模式     ││
│  │ ☑ GitHub Copilot            │  预扫描按钮     ││
│  │ ☑ Shell 历史                │                 ││
│  │ ...                         │ 选中多个:       ││
│  │                             │  多选摘要列表   ││
│  │─────────────────────────────│                 ││
│  │ [+ 模板] [+ 自定义]         │ 空状态:         ││
│  │                             │  选择提示       ││
│  │ ┌───────────────────────┐   │                 ││
│  │ │  清除所选 (3)         │   │ 结果:           ││
│  │ └───────────────────────┘   │  ✓/✓/✗ 列表    ││
│  │ ☐ 自动移除                   │                 ││
│  └─────────────────────────────┴─────────────────┘│
└─────────────────────────────────────────────────┘
```

### 12.2 反馈机制

| 场景 | 反馈方式 |
|------|----------|
| 清除执行中 | 按钮变进度条 + 底部 ProgressView |
| 清除完成 | 右侧切换为结果面板 |
| 操作取消 | Alert dismiss，不做任何更改 |
| 文件不存在 | 状态为 skipped，消息为 "文件不存在" |

### 12.3 键盘快捷键

| 快捷键 | 操作 |
|--------|------|
| ⌘+A | 全选 |
| Delete | 删除选中的目标 |
| ⌘+点击 | 切换选中/取消 |
| ⇧+点击 | 范围连选 |
