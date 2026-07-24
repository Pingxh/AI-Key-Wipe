#!/bin/bash
# =============================================================================
# AI-Key-Wipe Tauri — Build Script
# 编译 macOS / Windows / Linux 跨平台版本
# =============================================================================
set -euo pipefail

# 检查 Rust
if ! command -v cargo &>/dev/null; then
    echo "请先安装 Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
fi

cd "$(dirname "$0")"

echo "🔧 编译 AI-Key-Wipe Tauri 版本..."

# 编译后端
cd src-tauri
cargo build --release
cd ..

# 前端已就绪（纯 HTML/JS，无需构建）

# 打包
echo ""
echo "========================================"
echo "  ✅ 构建完成！"
echo "  运行: cd src-tauri && cargo run --release"
echo "  打包: cd src-tauri && cargo tauri build"
echo "========================================"
