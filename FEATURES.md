# AI-Key-Wipe 功能文档

> **版本**: 1.0.0  
> **最后更新**: 2026-07-30  
> **平台**: macOS / Windows / Linux (Tauri v2)

---

## 目录

1. [目标管理](#1-目标管理)
2. [匹配模式系统](#2-匹配模式系统)
3. [文件清除引擎](#3-文件清除引擎)
4. [扫描引擎](#4-扫描引擎)
5. [选择与清除逻辑](#5-选择与清除逻辑)
6. [自动移除](#6-自动移除)
7. [文件路径选择器](#7-文件路径选择器)
8. [持久化存储](#8-持久化存储)
9. [UI 交互规范](#9-ui-交互规范)

---

## 1. 目标管理

### 1.1 数据模型 (WipeTarget)

```rust
struct WipeTarget {
    id: String,              // 唯一标识 (UUID)
    name: String,            // 显示名称
    file_path: String,       // 文件路径
    enabled: bool,           // 启用/禁用
    custom_patterns: Vec<String>,  // 自定义匹配模式
}
```

### 1.2 操作方式

| 操作 | 说明 |
|------|------|
| 扫描 | 自动递归扫描，发现的文件自动加入列表 |
| 自定义添加 | 通过文件选择器手动添加任意文件 |
| 删除 | 选中后按 Delete 键或点击「移出列表」 |
| 编辑 | 单击右侧详情面板编辑名称、路径、自定义模式 |
| 启用/禁用 | 每项目右侧绿色圆点切换 |

### 1.3 多选管理

```javascript
// 使用 Set<UUID> + 实时查找，保证数据始终最新
selectedIds: new Set()
```

---

## 2. 匹配模式系统

### 2.1 架构

匹配模式采用 **内置默认模式 + 用户自定义模式** 合并策略：

```rust
build_patterns(custom: &[String]) -> Vec<String>
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

---

## 3. 文件清除引擎

### 3.1 核心方法

```rust
fn wipe_file(path: &str, custom_patterns: &[String]) -> Result<WipeResult, String>
```

### 3.2 处理流程

```
wipe_file(path)
    │
    ├── 1. 读取文件内容
    │
    ├── 2. 逐行处理
    │      ├── 注释行 → 保留
    │      ├── 匹配行 → 清除值（见下方格式处理）
    │      └── 其他行 → 保留
    │
    └── 3. 写入文件 → 返回 WipeResult
```

### 3.3 格式处理

| 原始格式 | 示例输入 | 清除后 |
|----------|----------|--------|
| export KEY=value | `export OPENAI_KEY=sk-xxx` | `export OPENAI_KEY=` |
| KEY=value | `DEEPSEEK_API_KEY=sk-xxx` | `DEEPSEEK_API_KEY=` |
| YAML key: value | `api_key: sk-xxx` | `api_key: ""` |
| YAML key:\n  value | `api_key:\n  sk-xxx` | `api_key: ""` (并跳过下行) |

### 3.4 清除结果 (WipeResult)

```rust
struct WipeResult {
    target_id: Option<String>,
    target_name: String,
    status: String,        // "success" | "skipped" | "failed"
    message: String,
}
```

---

## 4. 扫描引擎

### 4.1 扫描策略

| 平台 | 最大深度 | 扫描范围 |
|------|---------|---------|
| macOS | 4 层 | `~/` 根目录 + 子目录，跳过 Library/Applications/Desktop 等 |
| Windows | 5 层 | `~/` + Desktop + Documents + Downloads + AppData\Roaming |
| Linux | 4 层 | `~/` 根目录 + 子目录 |

### 4.2 跳过目录

**通用跳过**（所有平台）：
`.git`, `node_modules`, `.cache`, `Caches`, `__pycache__`, `venv`, `.venv`, `.Trash`, `.rvm`, `.nvm`, `.oh-my-zsh`, `.gem`, `.cocoapods`, `.m2`, `Pods`, `build`, `dist`, `.next`, `.turbo`

**Windows 特定跳过**：
`AppData`, `Music`, `Pictures`, `Videos`, `Public`, `OneDrive`, `3D Objects`, `Contacts`, `Favorites`, `Links`, `Saved Games`, `Searches` + 系统目录

**注意**：Windows 上 `Desktop`、`Documents`、`Downloads` **不跳过**，因为这些是用户放项目文件的主要位置。

### 4.3 允许扫描的隐藏目录

`.ssh`, `.gnupg`, `.aws`, `.azure`, `.gcloud`, `.docker`, `.kube`

### 4.4 支持的配置文件扩展名

`.env`, `.envrc`, `.yaml`, `.yml`, `.json`, `.toml`, `.conf`, `.cfg`

---

## 5. 选择与清除逻辑

### 5.1 选择状态与清除范围

| 列表选择状态 | 按钮文字 | 清除范围 |
|-------------|----------|----------|
| 未选中任何目标 | 灰色不可点击 | — |
| 选中 1 个 | `清除所选 (1)` | 仅该文件 |
| 选中 3 个 | `清除所选 (3)` | 仅这 3 个文件 |
| 全选 | `清除所选 (N)` | 全部 N 个 |

### 5.2 执行流程

```
点击「清除所选」按钮
    │
    ├──→ 弹出确认弹窗
    │
    ├──→ 用户确认
    │
    ├──→ execute_wipe() 按序处理每个目标
    │      ├── 跳过已禁用目标
    │      ├── 清除匹配到的 Key
    │      └── 返回结果
    │
    └──→ 显示结果面板
```

---

## 6. 自动移除

清除成功后可选择自动将目标从列表移除。

- 开关位置：列表底部「清除所选」按钮下方
- 默认开启
- 仅移除 `status == "success"` 的目标
- 失败或跳过的目标保留在列表中

---

## 7. 文件路径选择器

通过 `rfd` (Rust File Dialog) 库调用系统原生文件选择器：

| 场景 | 触发方式 |
|------|----------|
| 添加自定义目标 | 点击列表底部「自定义」按钮 |
| 修改目标路径 | 在详情页点击「选择…」按钮 |

- 自动展开 `~` 为家目录
- 选中文件后自动生成名称（父目录名/文件名）

---

## 8. 持久化存储

### 目标配置

- **存储方式**: JSON 文件
- **存储位置**: `~/.config/com.keyclean/targets.json`
- **编码**: JSON (serde)

### 数据格式

```json
[
  {
    "id": "uuid-string",
    "name": "example/.env",
    "file_path": "/Users/name/example/.env",
    "enabled": true,
    "custom_patterns": ["MY_KEY"]
  }
]
```

---

## 9. UI 交互规范

### 9.1 窗口布局

```
┌─────────────────────────────────────────────────┐
│                                                   │
│  ┌─────────── 280~400px ───────┬── 300px+ ──────┐│
│  │ 目标列表    0/0              │ (详情/结果区)    ││
│  │─────────────────────────────│                 ││
│  │ 空状态:                     │ 扫描动画:       ││
│  │   🔑 未发现 API Key 文件   │   扫描中...      ││
│  │   点击下方按钮扫描配置文件   │                  ││
│  │                             │ 详情编辑:       ││
│  │ 有数据时:                   │   名称/路径/启用 ││
│  │   ☑ 文件1                   │   自定义模式     ││
│  │   ☑ 文件2                   │   预扫描按钮     ││
│  │   ...                       │                  ││
│  │                             │ 多选摘要:       ││
│  │─────────────────────────────│   选中 N 个目标  ││
│  │ [自定义] [扫描]              │                  ││
│  │ ┌───────────────────────┐   │ 结果:           ││
│  │ │  清除所选 (0)         │   │   ✓/✗ 列表      ││
│  │ └───────────────────────┘   │                  ││
│  │ ☐ 自动移除                   │                  ││
│  └─────────────────────────────┴──────────────────┘│
└─────────────────────────────────────────────────┘
```

### 9.2 键盘快捷键

| 快捷键 | 操作 |
|--------|------|
| ⌘/Ctrl+A | 全选 |
| Delete | 删除选中的目标 |
| ⌘/Ctrl+1 | 显示主窗口 |
| ⌘/Ctrl+Shift+W | 清除所有数据 |

### 9.3 系统托盘

- 关闭窗口时隐藏到系统托盘（不退出）
- 托盘图标右键菜单：主界面 / 清理所有数据 / 退出
- macOS：菜单栏图标
- Windows：系统托盘图标