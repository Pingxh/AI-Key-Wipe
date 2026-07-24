# AI-Key-Wipe 产品文档

> **版本**: 1.0.0  
> **最后更新**: 2026-07-23  
> **平台**: macOS 14.0+ (arm64)

---

## 1. 产品概述

### 1.1 产品定位

AI-Key-Wipe 是一款面向 macOS 用户的 **AI 密钥隐私清理工具**。它帮助用户快速发现并清除本地存储的 AI API Key、令牌、认证凭据等敏感信息，适用于设备交接、隐私自查、环境重置等场景。

### 1.2 核心价值

| 维度 | 说明 |
|------|------|
| **隐私保护** | 一键清除散落在系统各处的 AI 凭据，防止泄露 |
| **安全可控** | 清除前自动备份，支持一键恢复 |
| **灵活定制** | 自定义扫描路径和匹配模式，不限于预设 |
| **所见即所得** | 选中即清除，精准控制清除范围 |

### 1.3 目标用户

- **AI 开发者**：本地配置了多个 LLM API Key（OpenRouter、DeepSeek、Kimi 等）
- **使用 AI 工具的用户**：Claude Desktop、GitHub Copilot、Hermes Agent 等
- **需要交接设备的人员**：出售/转赠 Mac 前擦除个人凭据

---

## 2. 产品架构

```
┌─────────────────────────────────────────────────────┐
│                    AIKeyWipe.app                      │
│  ┌─────────────────────────────────────────────────┐ │
│  │                SwiftUI UI Layer                  │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │ │
│  │  │ 目标列表  │  │ 目标详情  │  │ 结果面板     │  │ │
│  │  │ (多选)   │  │ (编辑)   │  │ (日志)      │  │ │
│  │  └────┬─────┘  └────┬─────┘  └──────┬───────┘  │ │
│  └───────┼──────────────┼───────────────┼──────────┘ │
│          ▼              ▼               ▼            │
│  ┌─────────────────────────────────────────────────┐ │
│  │                 Business Layer                   │ │
│  │  ┌──────────────────┐  ┌──────────────────────┐ │ │
│  │  │   TargetStore     │  │     WipeService      │ │ │
│  │  │  (持久化/CRUD)    │  │  (扫描/清除/备份)    │ │ │
│  │  └──────────────────┘  └──────────────────────┘ │ │
│  └─────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────┐ │
│  │              Persistence Layer                   │ │
│  │  ┌──────────────┐  ┌──────────────────────────┐ │ │
│  │  │ UserDefaults  │  │  文件系统 (备份/恢复)    │ │ │
│  │  │ (目标配置)    │  │  ~/AI-Key-Wipe/backups/  │ │ │
│  │  └──────────────┘  └──────────────────────────┘ │ │
│  └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

### 2.1 技术栈

| 组件 | 技术 |
|------|------|
| UI 框架 | SwiftUI + AppKit |
| 语言 | Swift 6.3 |
| 最低系统 | macOS 14.0 |
| 架构 | arm64 |
| 持久化 | UserDefaults (目标配置) + 文件系统 (备份) |
| 包大小 | ~960KB |

### 2.2 模块职责

| 模块 | 文件 | 职责 |
|------|------|------|
| App 入口 | `AIKeyWipeApp.swift` | 启动入口、WindowGroup 管理 |
| 主界面 | `ContentView.swift` | 左侧列表 + 右侧详情 + 底部操作栏 |
| 数据模型 | `Models.swift` | WipeTarget / WipeResult / PresetTemplate |
| 配置管理 | `TargetStore.swift` | 目标列表的 CRUD、UserDefaults 持久化、预设模板 |
| 清除引擎 | `WipeService.swift` | 文件扫描、匹配模式构建、清除执行、备份管理 |

---

## 3. 核心功能清单

### 3.1 目标管理

| 功能 | 说明 |
|------|------|
| 预设模板添加 | 一键添加常见 AI 配置文件路径（10 个预设） |
| 自定义路径添加 | 通过系统文件选择器（NSOpenPanel）选择任意文件/目录 |
| 多选操作 | ⌘+点击 多选，⇧+点击 连选 |
| 目标编辑 | 修改名称、重新选择路径、启用/禁用 |
| 自定义匹配模式 | 每目标独立配置额外匹配关键词 |
| 列表删除 | 右键菜单或键盘删除 |
| 自动移除 | 清除成功后自动从列表删除（可开关） |

### 3.2 扫描与清除

| 功能 | 说明 |
|------|------|
| 文件扫描 | 预览文件中的 API Key 匹配情况 |
| 单文件清除 | 选中单个目标后清除 |
| 批量清除 | 选中多个目标后批量清除 |
| 智能格式识别 | 自动识别 .env、YAML、export 等格式 |
| 多行值处理 | 处理 YAML 多行值（`key:\n  value`） |
| Shell 历史清洗 | 过滤 `.zsh_history`/`.bash_history` 中的敏感命令 |
| 对话历史清空 | 清空 `.hermes_history`/`history.jsonl` |

### 3.3 安全机制

| 功能 | 说明 |
|------|------|
| 自动备份 | 每次清除前将原始文件复制到 `~/AI-Key-Wipe/backups/` |
| 操作清单 | 备份目录中保存 `_manifest.txt` 记录本次操作详情 |
| 确认弹窗 | 执行前显示选中数量和名称列表 |
| 值清除而非注释 | 清空密钥值（`KEY=xxx` → `KEY=`），不保留原文 |
| 可恢复 | 通过 `restore-wipe.sh` 选择时间点恢复 |

---

## 4. 数据流

```
用户操作                    系统处理                        结果
─────────                  ────────                        ────
选择目标 ───→  List(selection) ───→  selectedIds (Set<UUID>)
                                         │
点击"清除所选"                          │
    │                                    ▼
    ├──→ 确认弹窗 (Alert)               │
    │       │                            │
    │   用户确认 YES                     │
    │       │                            │
    ▼       ▼                            ▼
showingConfirmAlert ──→ startWipe()
                            │
                            ├──→ WipeService.executeWipe()
                            │       │
                            │       ├──→ 备份原始文件
                            │       ├──→ 逐行扫描匹配模式
                            │       ├─── 内置模式 (KEY=, TOKEN=...)
                            │       └─── 自定义模式 (用户配置)
                            │       │
                            │       ├──→ 清除: KEY=xxx → KEY=
                            │       │   YAML key: val → key: ""
                            │       │   多行值 → key: "" + 跳过下行
                            │       │
                            │       └──→ 返回 WipeResult[]
                            │
                            ├──→ 显示结果面板
                            │
                            └──→ (可选) 自动移除成功目标
                                    ├──→ store.remove(target)
                                    └──→ selectedIds.subtract(id)
```

---

## 5. 预设模板

首次启动时自动加载以下 10 个预设目标：

| # | 名称 | 路径 | 说明 |
|---|------|------|------|
| 1 | Reasonix 密钥 | `~/.reasonix/.env` | DEEPSEEK, OPENROUTER, KIMI 等 |
| 2 | Hermes 密钥 | `~/.hermes/.env` | Hermes Agent 主配置 |
| 3 | Hermes Config | `~/.hermes/config.yaml` | YAML 中 providers.*.api_key |
| 4 | Omniroute 密钥 | `~/.omniroute/.env` | 加密密钥等 |
| 5 | Claude 设置 | `~/.claude/settings.json` | 环境变量和模型配置 |
| 6 | Claude MCP 配置 | `~/.claude/mcp.json` | MCP 服务器令牌 |
| 7 | Claude 对话历史 | `~/.claude/history.jsonl` | 对话记录 |
| 8 | GitHub Copilot | `~/.config/github-copilot/hosts.json` | OAuth Token |
| 9 | Shell 历史 | `~/.zsh_history` | 历史命令中的 Key 泄露 |
| 10 | Hermes 历史记录 | `~/.hermes/.hermes_history` | Hermes 对话历史 |

---

## 6. 系统要求

- **操作系统**: macOS 14.0 (Sonoma) 或更高
- **架构**: Apple Silicon (arm64) 或 Intel
- **存储**: App 本体 ~1MB，备份空间取决于清除文件大小
- **权限**: 读取/写入目标文件权限（用户目录下无需额外授权）

---

## 7. 项目文件结构

```
~/AI-Key-Wipe/                    # 产品根目录
├── AIKeyWipe/                    # Swift 项目
│   ├── build-app.sh              # 编译脚本
│   ├── build/
│   │   └── AIKeyWipe.app         # 编译产物
│   └── Sources/AIKeyWipe/
│       ├── AIKeyWipeApp.swift    # App 入口
│       ├── ContentView.swift     # 主界面 (~600行)
│       ├── Models.swift          # 数据模型
│       ├── TargetStore.swift     # 配置存储
│       └── WipeService.swift     # 清除引擎
├── ai-key-wipe.sh                # CLI 版脚本
├── Wipe-AI-Keys.command          # 双击 CLI 入口
├── restore-wipe.sh               # 恢复脚本
├── README.md                     # 快速上手
├── PRODUCT.md                    # 产品文档 (本文件)
├── FEATURES.md                   # 功能文档
└── backups/                      # 自动备份目录
    └── YYYYMMDD_HHMMSS/
        ├── _manifest.txt         # 操作清单
        └── (备份文件)
```

---

## 8. 备份与恢复

### 备份自动存储位置
```
~/AI-Key-Wipe/backups/20260723_183000/
├── _manifest.txt          # 操作清单（时间、目标列表）
├── reasonix-.env          # 清除前的原始文件
└── hermes-config.yaml
```

### 恢复操作
```bash
cd ~/AI-Key-Wipe
./restore-wipe.sh
# → 列出所有备份时间点
# → 选择要恢复的时间点
# → 输入 YES 确认
```

---

## 9. CLI 版本（备选）

对于偏好命令行的用户，同时提供了纯 shell 版：

| 文件 | 用途 |
|------|------|
| `ai-key-wipe.sh` | 核心扫描 + 清除（终端运行） |
| `Wipe-AI-Keys.command` | macOS 双击执行入口 |
| `restore-wipe.sh` | 备份恢复 |

CLI 版功能与 GUI 版一致，但不支持自定义匹配模式。

---

## 10. 安全说明

- 🔒 **数据不离开本机**：所有操作在本地完成，无网络请求
- 💾 **备份先于清除**：修改文件前先复制到备份目录
- 🧹 **彻底清除**：清空密钥值，不在文件中保留原文
- 🔄 **完全可逆**：通过 restore-wipe.sh 可还原任意时间点
- ✅ **操作确认**：每次清除需用户显式确认（大写的 YES）
