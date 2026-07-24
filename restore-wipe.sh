#!/bin/bash
# =============================================================================
# AI-Key-Wipe — 备份恢复脚本 | Restore Tool
# 从 backup 目录恢复被清除的 API Key 和配置文件
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

BACKUP_BASE="$HOME/AI-Key-Wipe/backups"

info()  { echo -e "${BLUE}[ℹ]${NC} $1"; }
ok()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }

# ─── 列出所有可用备份 ─────────────────────────────────────────────────────
list_backups() {
    clear 2>/dev/null || true
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}AI-Key-Wipe — 备份恢复工具${NC}        ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    if [ ! -d "$BACKUP_BASE" ] || [ -z "$(ls -A "$BACKUP_BASE" 2>/dev/null)" ]; then
        error "没有找到任何备份目录"
        echo ""
        info "备份目录: $BACKUP_BASE"
        echo ""
        exit 1
    fi

    echo -e "${BOLD}可用的备份:${NC}"
    echo ""

    local i=1
    BACKUP_DIRS=()
    while IFS= read -r dir; do
        local name=$(basename "$dir")
        local file_count=$(find "$dir" -type f 2>/dev/null | wc -l | tr -d ' ')
        local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        echo "  ${BOLD}${i})${NC} $name  ${YELLOW}($file_count 个文件, $size)${NC}"
        BACKUP_DIRS+=("$dir")
        i=$((i + 1))
    done < <(ls -dt "$BACKUP_BASE"/*/ 2>/dev/null || true)

    echo ""
    echo "  ${BOLD}0)${NC} 退出"
    echo ""
}

# ─── 恢复选定备份 ─────────────────────────────────────────────────────────
restore_backup() {
    local backup_dir="$1"
    local backup_name=$(basename "$backup_dir")

    echo ""
    echo -e "${YELLOW}⚠️  将从以下备份恢复: ${BOLD}$backup_name${NC}"
    echo ""

    # 列出备份内容
    echo -e "${BOLD}备份内容:${NC}"
    find "$backup_dir" -type f 2>/dev/null | while read -r f; do
        local rel="${f#$backup_dir/}"
        echo "  • ~/$rel"
    done

    echo ""
    echo -n "确认恢复？输入大写的 ${BOLD}${RED}YES${NC} 确认: "
    read -r confirm </dev/tty

    if [ "$confirm" != "YES" ]; then
        warn "操作已取消"
        return
    fi

    echo ""
    info "开始恢复..."

    local restored=0
    local skipped=0
    while IFS= read -r file; do
        local rel="${file#$backup_dir/}"
        local target="$HOME/$rel"
        local target_dir="$(dirname "$target")"

        # 检查是否要覆盖
        if [ -f "$target" ] || [ -d "$target" ]; then
            mkdir -p "$target_dir"
            if cp -R "$file" "$target" 2>/dev/null; then
                ok "已恢复: ~/$rel"
                ((restored++))
            else
                warn "恢复失败: ~/$rel"
                ((skipped++))
            fi
        else
            mkdir -p "$target_dir"
            if cp -R "$file" "$target" 2>/dev/null; then
                ok "已恢复: ~/$rel"
                ((restored++))
            else
                warn "恢复失败: ~/$rel"
                ((skipped++))
            fi
        fi
    done < <(find "$backup_dir" -type f 2>/dev/null || true)

    # 恢复空目录结构
    while IFS= read -r dir; do
        local rel="${dir#$backup_dir/}"
        local target="$HOME/$rel"
        if [ ! -d "$target" ]; then
            mkdir -p "$target" 2>/dev/null || true
        fi
    done < <(find "$backup_dir" -type d 2>/dev/null || true)

    echo ""
    echo -e "${GREEN}${BOLD}✅ 恢复完成！${NC}"
    echo -e "   恢复文件: ${BOLD}$restored${NC}"
    [ "$skipped" -gt 0 ] && echo -e "   跳过: ${YELLOW}$skipped${NC}"
    echo ""
    echo -e "${YELLOW}💡 提示: 重新打开 Terminal 使环境变量恢复生效${NC}"
}

# ─── 主入口 ────────────────────────────────────────────────────────────────
main() {
    list_backups

    echo -n "请选择要恢复的备份编号 [0-${#BACKUP_DIRS[@]}]: "
    read -r choice </dev/tty

    if [ "$choice" = "0" ] || [ -z "$choice" ]; then
        info "已退出"
        exit 0
    fi

    local index=$((choice - 1))
    if [ "$index" -ge 0 ] && [ "$index" -lt "${#BACKUP_DIRS[@]}" ]; then
        restore_backup "${BACKUP_DIRS[$index]}"
    else
        error "无效的选择"
        exit 1
    fi
}

main "$@"
