#!/bin/bash
# =============================================================================
# AI-Key-Wipe — macOS 双击执行入口
# Double-click to run AI Key Wipe
# =============================================================================

# 获取脚本所在目录
DIR="$(cd "$(dirname "$0")" && pwd)"

# 确保脚本可执行
chmod +x "$DIR/ai-key-wipe.sh" 2>/dev/null

# 打开 Terminal 窗口并执行
osascript -e "
tell application \"Terminal\"
    activate
    set newTab to do script \"clear && echo '============================================' && echo '  AI-Key-Wipe — AI Privacy Cleaner' && echo '============================================' && echo '' && exec $DIR/ai-key-wipe.sh\"
end tell
" 2>/dev/null || {
    # Fallback: 直接用 Terminal 执行
    open -a Terminal "$DIR/ai-key-wipe.sh"
}
