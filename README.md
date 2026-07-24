# AI-Key-Wipe — macOS AI 密钥隐私清理工具

> **一键清除 Mac 上的 AI API Key、令牌和敏感配置**
> 安全 | 可恢复 | 开源

![macOS](https://img.shields.io/badge/platform-macOS-blue)
![Shell](https://img.shields.io/badge/shell-bash-green)
![Version](https://img.shields.io/badge/version-1.0.0-orange)

---

## 它能做什么？

扫描并清除 Mac 上以下位置的 **AI API Key 和敏感配置**：

| 扫描目标 | 说明 |
|----------|------|
| `.env` 文件 | 扫描 `~/.reasonix/`、`~/.hermes/`、`~/.omniroute/` 等目录下的 env 文件中的 API Key |
| Hermes Agent 配置 | 清除 `~/.hermes/config.yaml` 中的明文 API Key、`auth.json`、`gateway_state.json` |
| Claude 配置 | 清除 `~/.claude/settings.json` 中的环境变量、`mcp.json` 中的令牌、对话历史 |
| GitHub Copilot | 清除 `~/.config/github-copilot/hosts.json` 中的 OAuth Token |
| OpenCode / Codex++ | 清除这些 AI 工具的本地配置 |
| 系统钥匙串 | 删除 "Claude Safe Storage"、"DEEPSEEK_API_KEY" 等 AI 相关钥匙串条目 |
| Shell 历史 | 清除 `.zsh_history` / `.bash_history` 中泄露的 API Key |
| Hermes 历史 | 清空 `~/.hermes/.hermes_history` |

---

## 快速开始

### 方式 1：双击运行（推荐）

1. 打开文件夹 `~/AI-Key-Wipe/`
2. 双击 **`Wipe-AI-Keys.command`**
3. 在弹出的 Terminal 窗口中查看扫描结果
4. 输入 `YES` 确认清除

### 方式 2：命令行运行

```bash
cd ~/AI-Key-Wipe
chmod +x ai-key-wipe.sh
./ai-key-wipe.sh
```

---

## 操作流程

```
1️⃣ 扫描 →  自动发现所有 API Key 和敏感配置
           显示每个位置的具体内容（密钥已脱敏显示）

2️⃣ 确认 →  让你选择：
            [1] 清除所有发现的内容
            [2] 仅扫描不执行
            [3] 退出

3️⃣ 清除 →  输入 YES 确认后执行清除
           自动备份所有被修改的文件

4️⃣ 完成 →  显示清除摘要和备份位置
```

---

## 安全机制

### ✅ 自动备份
所有被修改/删除的文件都会自动备份到：
```
~/AI-Key-Wipe/backups/YYYYMMDD_HHMMSS/
```

### ✅ 可恢复
运行恢复脚本即可还原所有内容：
```bash
~/AI-Key-Wipe/restore-wipe.sh
```

### ✅ 操作确认
- 每次清除前都会列出完整清单
- 必须输入大写的 `YES` 才会执行
- 钥匙串删除会逐条确认

### ✅ 非破坏性处理
- `.env` 文件中的 Key 被**注释掉**而非删除
- 保留文件结构，仅清空敏感值
- 只有确认需要删除的目录才会被移除

---

## 文件结构

```
~/AI-Key-Wipe/
├── ai-key-wipe.sh              # 核心扫描+清除脚本
├── Wipe-AI-Keys.command        # macOS 双击入口文件
├── restore-wipe.sh             # 备份恢复脚本
└── backups/                    # 自动生成的备份目录
    └── YYYYMMDD_HHMMSS/        # 每次清除的备份
        ├── .hermes/
        ├── .claude/
        └── ...
```

---

## 恢复指南

```
./restore-wipe.sh
```

会列出所有可用的备份，选择你想恢复的时间点即可。

---

## 适用场景

- 🔒 **出售/转赠 Mac** — 清除所有 AI 凭据再交给别人
- 🧹 **定期隐私清理** — 每月清理一次，防止 API Key 积累
- 🔄 **切换 AI 供应商** — 一键清空旧配置，重新配置
- 🚀 **演示/共享电脑** — 快速擦除个人 AI 密钥

---

## 注意事项

- 本工具 **不会** 清除系统环境变量（`export` 在 `.zshrc` 等中的定义，因为你的 shell 配置中未发现 API Key）
- 钥匙串删除需要 **系统弹窗确认**，请按提示操作
- 清除后需要 **重新打开 Terminal** 才会生效（shell 配置变更）
- 本脚本是**只读扫描 + 选择性清除**，不会修改未发现敏感信息的文件

---

## License

MIT — 随意使用、修改、分享。
