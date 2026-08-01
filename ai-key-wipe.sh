#!/bin/bash
# =============================================================================
# AI-Key-Wipe — macOS AI API Key & Config Privacy Cleaner
# 一键清除本地 AI API Key 和 AI 配置文件 | One-click AI Privacy Wipe
# =============================================================================
# 安全说明 / Safety Notes:
#   1. 脚本会自动备份所有被清除的文件到 ~/AI-Key-Wipe/backups/ 目录
#   2. 备份文件名带有时间戳，可随时恢复（见 restore-wipe.sh）
#   3. 清除前会列出所有发现项，需要你确认才会执行
#   4. 钥匙串条目需要你手动在弹窗中确认删除
# =============================================================================

set -euo pipefail

VERSION="1.0.0"
BACKUP_DIR="$HOME/AI-Key-Wipe/backups/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$HOME/AI-Key-Wipe/wipe-log.txt"
USER_HOME="$HOME"

# ─── 颜色 / Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─── Header ──────────────────────────────────────────────────────────────────
print_banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}AI-Key-Wipe v${VERSION}${NC}            ${BOLD}AI 隐私密钥清理工具${NC}      ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log() {
    local msg="[$(date '+%H:%M:%S')] $1"
    echo -e "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

info()  { echo -e "${BLUE}[ℹ]${NC} $1"; }
ok()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
header() { echo ""; echo -e "${BOLD}${CYAN}── $1 ──${NC}"; echo ""; }

# ─── 安全检查 / Safety Check ──────────────────────────────────────────────
check_safety() {
    if [ "$(id -u)" = "0" ]; then
        error "请不要以 root/sudo 运行此脚本！/ Do not run as root!"
        exit 1
    fi
}

# ─── 备份文件 / Backup file ─────────────────────────────────────────────────
backup_file() {
    local file="$1"
    if [ -f "$file" ] || [ -d "$file" ]; then
        mkdir -p "$BACKUP_DIR"
        local rel_path="${file#$HOME/}"
        local dest="$BACKUP_DIR/$rel_path"
        mkdir -p "$(dirname "$dest")"
        cp -R "$file" "$dest" 2>/dev/null && ok "已备份: ~/$rel_path" || warn "备份失败: ~/$rel_path"
    fi
}

# ─── 扫描阶段 1: .env 文件 ──────────────────────────────────────────────────
scan_env_files() {
    header "📄 扫描 .env 文件中的 API Key"
    
    local env_files=(
        "$HOME/.reasonix/.env"
        "$HOME/.hermes/.env"
        "$HOME/.omniroute/.env"
        "$HOME/.hermes/hermes-agent/.envrc"
    )

    FOUND_ENTRIES=()

    for f in "${env_files[@]}"; do
        if [ -f "$f" ]; then
            local rel="${f#$HOME/}"
            local keys=$(grep -n 'KEY\|TOKEN\|SECRET\|PASSWORD' "$f" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v 'your_key_here\|your_google\|your_ollama\|your_hermes\|your_key\|replace_me\|example\|xxxxx\|YOUR_\|your_' || true)
            if [ -n "$keys" ]; then
                warn "发现 API Key 在 ~/$rel"
                while IFS= read -r line; do
                    local var_name=$(echo "$line" | sed -n 's/^[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p')
                    local masked_line=$(echo "$line" | sed 's/=[^:]*$/=******/')
                    echo "       $masked_line"
                    if [ -n "$var_name" ]; then
                        FOUND_ENTRIES+=("$var_name|$f")
                    fi
                done <<< "$keys"
            else
                ok "~/$rel 中未发现活跃 API Key"
            fi
        fi
    done
}

# ─── 扫描阶段 2: Hermes config.yaml ─────────────────────────────────────────
scan_hermes_config() {
    header "⚙️ 扫描 Hermes Agent 配置"

    local config="$HOME/.hermes/config.yaml"
    if [ -f "$config" ]; then
        local keys=$(grep -n 'api_key:' "$config" 2>/dev/null | grep -v '^[[:space:]]*#' || true)
        if [ -n "$keys" ]; then
            warn "发现 API Key 在 ~/.hermes/config.yaml"
            while IFS= read -r line; do
                local masked=$(echo "$line" | sed 's/\(api_key:\)[[:space:]]*.*/\1 ******/')
                echo "       $masked"
                FOUND_ENTRIES+=("config_api_key|$config")
            done <<< "$keys"
        else
            ok "~/.hermes/config.yaml 中未发现 API Key"
        fi
    fi

    # 检查 auth.json
    local auth="$HOME/.hermes/auth.json"
    if [ -f "$auth" ]; then
        warn "发现认证文件 ~/.hermes/auth.json（可能包含令牌）"
        FOUND_ENTRIES+=("auth_json|$auth")
    fi

    # 检查 gateway_state.json
    local gw="$HOME/.hermes/gateway_state.json"
    if [ -f "$gw" ]; then
        if grep -q '"token"\|"key"\|"auth"' "$gw" 2>/dev/null; then
            warn "发现 ~/.hermes/gateway_state.json（可能包含令牌）"
            FOUND_ENTRIES+=("gateway_state|$gw")
        fi
    fi
}

# ─── 扫描阶段 3: Claude 配置 ────────────────────────────────────────────────
scan_claude_config() {
    header "🤖 扫描 Claude 配置"

    local claude_dir="$HOME/.claude"
    if [ -d "$claude_dir" ]; then
        local settings="$claude_dir/settings.json"
        if [ -f "$settings" ]; then
            warn "发现 Claude 设置文件 ~/.claude/settings.json"
            FOUND_ENTRIES+=("claude_settings|$settings")
        fi
        local settings_local="$claude_dir/settings.local.json"
        if [ -f "$settings_local" ]; then
            warn "发现 Claude 本地设置 ~/.claude/settings.local.json"
            FOUND_ENTRIES+=("claude_settings_local|$settings_local")
        fi
        local mcp="$claude_dir/mcp.json"
        if [ -f "$mcp" ]; then
            warn "发现 Claude MCP 配置 ~/.claude/mcp.json（可能包含令牌）"
            FOUND_ENTRIES+=("claude_mcp|$mcp")
        fi
        local history="$claude_dir/history.jsonl"
        if [ -f "$history" ]; then
            warn "发现 Claude 对话历史 ~/.claude/history.jsonl（可能包含敏感信息）"
            FOUND_ENTRIES+=("claude_history|$history")
        fi
        # 扫描 Claude 目录下的其他敏感文件
        local mcp_json="$claude_dir/mcp.json"
        if [ -f "$mcp_json" ] && grep -q 'token\|key\|secret\|password' "$mcp_json" 2>/dev/null; then
            warn "   ~/.claude/mcp.json 中包含密钥信息"
        fi
    else
        ok "未发现 Claude 配置目录"
    fi
}

# ─── 扫描阶段 4: GitHub Copilot ────────────────────────────────────────────
scan_github_copilot() {
    header "👨‍💻 扫描 GitHub Copilot 配置"

    local copilot_dir="$HOME/.config/github-copilot"
    if [ -d "$copilot_dir" ]; then
        local hosts="$copilot_dir/hosts.json"
        if [ -f "$hosts" ]; then
            if grep -q 'oauth_token' "$hosts" 2>/dev/null; then
                warn "发现 GitHub Copilot OAuth 令牌"
                FOUND_ENTRIES+=("copilot_hosts|$hosts")
            fi
        fi
        # apps.json
        local apps="$copilot_dir/apps.json"
        if [ -f "$apps" ]; then
            warn "发现 GitHub Copilot 应用配置"
            FOUND_ENTRIES+=("copilot_apps|$apps")
        fi
    fi

    # 其他 AI 工具配置
    local opencode_dir="$HOME/.config/opencode"
    if [ -d "$opencode_dir" ]; then
        warn "发现 OpenCode 配置目录 ~/.config/opencode/"
        FOUND_ENTRIES+=("opencode|$opencode_dir")
    fi

    local codex_dir="$HOME/.config/Codex++"
    if [ -d "$codex_dir" ]; then
        warn "发现 Codex++ 配置 ~/.config/Codex++/"
        FOUND_ENTRIES+=("codex|$codex_dir")
    fi
}

# ─── 扫描阶段 5: 钥匙串 ────────────────────────────────────────────────────
scan_keychain() {
    header "🔑 扫描系统钥匙串"

    local found_something=false

    # 搜索常见的 AI 相关钥匙串条目
    local search_terms=("API" "api" "key" "Key" "token" "Token" "secret" "Secret" "Claude" "OpenAI" "openai" "Anthropic" "DeepSeek" "deepseek" "Gemini" "gemini" "Copilot" "copilot")

    for term in "${search_terms[@]}"; do
        local results=$(security find-generic-password -s "$term" 2>/dev/null || true)
        if [ -n "$results" ]; then
            local acct=$(echo "$results" | grep "acct" | sed 's/.*"\(.*\)".*/\1/' 2>/dev/null || echo "unknown")
            local svce=$(echo "$results" | grep "svce" | sed 's/.*"\(.*\)".*/\1/' 2>/dev/null || echo "unknown")
            if [ -n "$acct" ] && [ "$acct" != "unknown" ]; then
                warn "发现钥匙串条目: $svce / $acct"
                FOUND_KEYCHAIN_ITEMS+=("$svce|$acct")
                found_something=true
            fi
        fi
    done

    if [ "$found_something" = false ]; then
        ok "未发现 AI 相关的钥匙串条目"
    fi
}

# ─── 清除阶段 1: 清除 .env 中的 Key ───────────────────────────────────────
wipe_env_keys() {
    header "🧹 清除 .env 文件中的 API Key"

    for entry in "${FOUND_ENTRIES[@]}"; do
        local var_name="${entry%%|*}"
        local file_path="${entry##*|}"
        local rel="${file_path#$HOME/}"

        # 只处理 .env 类型的条目
        case "$var_name" in
            config_api_key|auth_json|gateway_state|claude_*|copilot_*|opencode|codex)
                continue ;;
        esac

        if [[ "$file_path" != *.env ]] && [[ "$file_path" != *.envrc ]]; then
            continue
        fi

        info "清理 ~/$rel 中的 $var_name"
        backup_file "$file_path"

        # 注释掉该行（而非删除，保留文件结构）
        if grep -q "export $var_name=" "$file_path" 2>/dev/null; then
            sed -i '' "s/^export $var_name=.*/# WIPED $(date '+%Y-%m-%d %H:%M:%S') — was: export $var_name=***WIPED***/" "$file_path"
        elif grep -q "^${var_name}=" "$file_path" 2>/dev/null; then
            sed -i '' "s/^${var_name}=.*/# WIPED $(date '+%Y-%m-%d %H:%M:%S') — was: ${var_name}=***WIPED***/" "$file_path"
        fi
        ok "已清除 ~/$rel 中的 $var_name"
    done
}

# ─── 清除阶段 2: 清除 Hermes config.yaml 中的 Key ─────────────────────────
wipe_hermes_config() {
    header "🧹 清除 Hermes 配置中的 API Key"

    local config="$HOME/.hermes/config.yaml"
    if [ -f "$config" ] && [[ " ${FOUND_ENTRIES[*]} " =~ "config_api_key" ]]; then
        backup_file "$config"

        # 将所有 providers 下的 api_key 值置空
        info "清空 ~/.hermes/config.yaml 中的 api_key 值..."
        sed -i '' '/^[[:space:]]*api_key:/s/:[[:space:]].*/: ""/' "$config"
        ok "已清空 config.yaml 中的 API Key"

        # 清空 auth.json
        local auth="$HOME/.hermes/auth.json"
        if [[ " ${FOUND_ENTRIES[*]} " =~ "auth_json" ]] && [ -f "$auth" ]; then
            backup_file "$auth"
            echo "{}" > "$auth"
            ok "已清空 auth.json"
        fi

        # 清空 gateway_state.json 中的敏感字段
        local gw="$HOME/.hermes/gateway_state.json"
        if [[ " ${FOUND_ENTRIES[*]} " =~ "gateway_state" ]] && [ -f "$gw" ]; then
            backup_file "$gw"
            # 移除 token/auth 字段
            sed -i '' '/"token"/d; /"auth"/d; /"key"/d' "$gw" 2>/dev/null || true
            ok "已清理 gateway_state.json"
        fi
    else
        info "无需清理 Hermes 配置"
    fi
}

# ─── 清除阶段 3: 清除 Claude 配置 ──────────────────────────────────────────
wipe_claude_config() {
    header "🧹 清除 Claude 配置"

    local claude_dir="$HOME/.claude"
    if [ ! -d "$claude_dir" ]; then
        info "无需清理 Claude 配置"
        return
    fi

    # settings.json — 清除 env 中的敏感信息，保留其他设置
    local settings="$claude_dir/settings.json"
    if [ -f "$settings" ] && [[ " ${FOUND_ENTRIES[*]} " =~ "claude_settings" ]]; then
        backup_file "$settings"
        # 清空 env 字段
        if grep -q '"env"' "$settings" 2>/dev/null; then
            sed -i '' 's/"env":{[^}]*}/"env":{}/g' "$settings" 2>/dev/null || true
            ok "已清除 settings.json 中的环境变量"
        fi
    fi

    # mcp.json — 清除其中的密钥
    local mcp="$claude_dir/mcp.json"
    if [ -f "$mcp" ] && [[ " ${FOUND_ENTRIES[*]} " =~ "claude_mcp" ]]; then
        backup_file "$mcp"
        # 清除所有 env 字段中的 token/key
        sed -i '' '/"GITEE_ACCESS_TOKEN"/d; /"GITHUB_TOKEN"/d; /"API_KEY"/d' "$mcp" 2>/dev/null || true
        ok "已清理 mcp.json 中的密钥"
    fi

    # 删除对话历史（包含敏感信息）
    local history="$claude_dir/history.jsonl"
    if [ -f "$history" ] && [[ " ${FOUND_ENTRIES[*]} " =~ "claude_history" ]]; then
        backup_file "$history"
        : > "$history"
        ok "已清空 Claude 对话历史"
    fi
}

# ─── 清除阶段 4: 清除 GitHub Copilot 等 ────────────────────────────────────
wipe_copilot_config() {
    header "🧹 清除 AI 工具配置"

    local copilot_hosts="$HOME/.config/github-copilot/hosts.json"
    if [ -f "$copilot_hosts" ] && [[ " ${FOUND_ENTRIES[*]} " =~ "copilot_hosts" ]]; then
        backup_file "$copilot_hosts"
        # 保留文件结构但清除 token
        sed -i '' 's/"oauth_token":"[^"]*"/"oauth_token":"***WIPED***"/g' "$copilot_hosts"
        ok "已清除 GitHub Copilot OAuth Token"
    fi

    # 清除 OpenCode 配置
    local opencode_dir="$HOME/.config/opencode"
    if [ -d "$opencode_dir" ] && [[ " ${FOUND_ENTRIES[*]} " =~ "opencode" ]]; then
        backup_file "$opencode_dir"
        rm -rf "$opencode_dir" 2>/dev/null
        ok "已清除 OpenCode 配置"
    fi

    # 清除 Codex++ 配置
    local codex_dir="$HOME/.config/Codex++"
    if [ -d "$codex_dir" ] && [[ " ${FOUND_ENTRIES[*]} " =~ "codex" ]]; then
        backup_file "$codex_dir"
        rm -rf "$codex_dir" 2>/dev/null
        ok "已清除 Codex++ 配置"
    fi
}

# ─── 清除阶段 5: 钥匙串 ────────────────────────────────────────────────────
wipe_keychain() {
    header "🧹 清理系统钥匙串"

    local items_removed=0
    for item in "${FOUND_KEYCHAIN_ITEMS[@]}"; do
        local svce="${item%%|*}"
        local acct="${item##*|}"

        if [ -n "$svce" ] && [ -n "$acct" ]; then
            echo -e "${YELLOW}  是否删除钥匙串条目: $svce / $acct?${NC}"
            echo -n "    [y/N] "
            read -r confirm </dev/tty
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                security delete-generic-password -s "$svce" -a "$acct" 2>/dev/null && {
                    ok "已删除钥匙串: $svce / $acct"
                    ((items_removed++))
                } || warn "删除失败: $svce / $acct（可能需要手动删除）"
            else
                info "跳过: $svce / $acct"
            fi
        fi
    done

    if [ "$items_removed" -eq 0 ] && [ ${#FOUND_KEYCHAIN_ITEMS[@]} -gt 0 ]; then
        info "未删除任何钥匙串条目"
    elif [ ${#FOUND_KEYCHAIN_ITEMS[@]} -eq 0 ]; then
        ok "无需清理钥匙串"
    fi
}

# ─── 清除 Shell 历史中的 Key ──────────────────────────────────────────────
wipe_shell_history() {
    header "🗑️ 清理 Shell 历史中的 API Key"

    local cleaned=0
    for hist_file in "$HOME/.zsh_history" "$HOME/.bash_history"; do
        if [ -f "$hist_file" ]; then
            local before=$(wc -l < "$hist_file")
            # 删除包含 API_KEY 的行
            grep -v 'API_KEY\|api_key\|api-key\|ANTHROPIC\|OPENAI\|GEMINI\|DEEPSEEK' "$hist_file" > "${hist_file}.clean" 2>/dev/null && mv "${hist_file}.clean" "$hist_file"
            local after=$(wc -l < "$hist_file")
            local removed=$((before - after))
            if [ "$removed" -gt 0 ]; then
                ok "已清理 $hist_file（删除了 $removed 行敏感历史）"
                ((cleaned++))
            fi
        fi
    done

    # 清理 .hermes_history
    local hermes_hist="$HOME/.hermes/.hermes_history"
    if [ -f "$hermes_hist" ]; then
        backup_file "$hermes_hist"
        : > "$hermes_hist"
        ok "已清空 Hermes 对话历史"
    fi

    if [ "$cleaned" -eq 0 ]; then
        info "Shell 历史中未发现 API Key 痕迹"
    fi
}

# ─── 扫描主入口 ────────────────────────────────────────────────────────────
run_scan() {
    print_banner
    echo -e "${BOLD}开始扫描本地 AI 密钥和配置...${NC}"
    echo ""
    echo -e "备份目录: ${YELLOW}$BACKUP_DIR${NC}"
    echo -e "日志文件: ${YELLOW}$LOG_FILE${NC}"
    echo ""

    FOUND_ENTRIES=()
    FOUND_KEYCHAIN_ITEMS=()

    scan_env_files
    scan_hermes_config
    scan_claude_config
    scan_github_copilot
    scan_keychain

    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [ ${#FOUND_ENTRIES[@]} -eq 0 ] && [ ${#FOUND_KEYCHAIN_ITEMS[@]} -eq 0 ]; then
        echo -e "${GREEN}${BOLD}  未发现任何敏感信息，系统很干净！${NC}"
        echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        exit 0
    else
        echo -e "${RED}${BOLD}  发现 ${#FOUND_ENTRIES[@]} 个配置项 + ${#FOUND_KEYCHAIN_ITEMS[@]} 个钥匙串条目${NC}"
        echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    fi
}

# ─── 清除主入口 ────────────────────────────────────────────────────────────
run_wipe() {
    echo ""
    echo -e "${RED}${BOLD}⚠️  即将清除以上所有发现的 API Key 和配置信息${NC}"
    echo -e "${YELLOW}  备份将保存到: $BACKUP_DIR${NC}"
    echo ""
    echo -n "确认继续？输入大写的 ${BOLD}${RED}YES${NC} 确认: "
    read -r confirm </dev/tty

    if [ "$confirm" != "YES" ]; then
        echo ""
        warn "操作已取消，未做任何更改"
        exit 0
    fi

    echo ""
    log "=== 开始清除 ==="

    wipe_env_keys
    wipe_hermes_config
    wipe_claude_config
    wipe_copilot_config
    wipe_shell_history
    wipe_keychain

    echo ""
    echo -e "${GREEN}${BOLD}✅ AI-Key-Wipe 执行完成！${NC}"
    echo ""
    echo -e "  ${BLUE}备份位置:${NC}    $BACKUP_DIR"
    echo -e "  ${BLUE}操作日志:${NC}    $LOG_FILE"
    echo -e "  ${BLUE}恢复脚本:${NC}    ~/AI-Key-Wipe/restore-wipe.sh"
    echo ""
    echo -e "${YELLOW}💡 提示: 运行 restore-wipe.sh 可恢复所有被清除的内容${NC}"
    echo ""
}

# ─── 主入口 ────────────────────────────────────────────────────────────────
main() {
    check_safety
    mkdir -p "$HOME/AI-Key-Wipe"

    print_banner
    run_scan
    echo ""
    echo "可用操作:"
    echo "  ${BOLD}1${NC}) 清除以上所有内容并退出"
    echo "  ${BOLD}2${NC}) 仅扫描（不执行任何清除）"
    echo "  ${BOLD}3${NC}) 退出"
    echo ""
    echo -n "请选择 [1/2/3]: "
    read -r action </dev/tty

    case "$action" in
        1) run_wipe ;;
        2) info "仅扫描模式结束" ; exit 0 ;;
        3) info "已退出" ; exit 0 ;;
        *) warn "无效选择" ; exit 1 ;;
    esac
}

main "$@"
