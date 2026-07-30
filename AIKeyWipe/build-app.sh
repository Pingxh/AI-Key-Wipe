#!/bin/bash
# =============================================================================
# AIKeyWipe — Build Script
# 将 SwiftUI macOS App 编译为 .app 文件
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[ℹ]${NC} $1"; }
ok()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }

# ─── 配置 ──────────────────────────────────────────────────────────────────
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$PROJECT_DIR/Sources/AIKeyWipe"
APP_NAME="AIKeyWipe"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MIN_OS_VERSION="13.0"
ARCHS="arm64 x86_64"

# ─── 步骤 1: 检查环境 ────────────────────────────────────────────────────
check_env() {
    info "检查编译环境..."

    if ! xcrun --sdk macosx --show-sdk-path &>/dev/null; then
        error "macOS SDK 未找到，请确保已安装 Xcode"
        exit 1
    fi

    if ! swift --version &>/dev/null; then
        error "Swift 编译器未找到"
        exit 1
    fi

    local swift_ver=$(swift --version | head -1 | grep -o 'version [0-9.]*' | cut -d' ' -f2)
    info "Swift 版本: $swift_ver"

    ok "环境检查通过"
}

# ─── 步骤 2: 编译 ────────────────────────────────────────────────────────
compile() {
    info "编译 Swift 源码..."

    mkdir -p "$BUILD_DIR"

    local swift_files=$(find "$SOURCE_DIR" -name "*.swift" | tr '\n' ' ')

    if [ -z "$swift_files" ]; then
        error "未找到 Swift 源码文件"
        exit 1
    fi

    info "源文件: $swift_files"

    # 分别编译 arm64 和 x86_64
    local binaries=""
    for arch in $ARCHS; do
        local bin_path="$BUILD_DIR/${APP_NAME}_${arch}"
        info "编译 ${arch}..."
        xcrun swiftc \
            -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
            -target "${arch}-apple-macosx${MIN_OS_VERSION}" \
            -o "$bin_path" \
            -module-name "$APP_NAME" \
            -emit-executable \
            -framework SwiftUI \
            -framework AppKit \
            -framework Foundation \
            -framework UserNotifications \
            $swift_files
        binaries="$binaries $bin_path"
    done

    # 合成为通用二进制
    info "合并为 Universal Binary..."
    xcrun lipo -create -output "$BUILD_DIR/$APP_NAME" $binaries

    # 清理单架构二进制
    rm -f $binaries

    # 验证
    local archs_in_bin=$(xcrun lipo -archs "$BUILD_DIR/$APP_NAME" 2>/dev/null || echo "unknown")
    if [ -f "$BUILD_DIR/$APP_NAME" ]; then
        local size=$(du -h "$BUILD_DIR/$APP_NAME" | cut -f1)
        ok "编译成功! Universal Binary ($archs_in_bin), 大小: $size"
    else
        error "编译失败"
        exit 1
    fi
}

# ─── 步骤 3: 创建 .app Bundle ────────────────────────────────────────────
create_bundle() {
    info "创建 .app 包..."

    # 创建目录结构
    mkdir -p "$MACOS_DIR"
    mkdir -p "$RESOURCES_DIR"

    # 复制二进制
    cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
    chmod +x "$MACOS_DIR/$APP_NAME"

    # 创建 Info.plist
    cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>AIKeyWipe</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.atomcode.aikeywipetool</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AIKeyWipe</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_OS_VERSION}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>AI-Key-Wipe</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

    # 创建一个简单的 App 图标（使用 SF Symbols 生成）
    create_icon

    # 验证
    if [ -d "$APP_BUNDLE" ] && [ -f "$MACOS_DIR/$APP_NAME" ]; then
        ok "App Bundle 创建成功: $APP_BUNDLE"
    else
        error "App Bundle 创建失败"
        exit 1
    fi
}

# ─── 创建 App 图标 ──────────────────────────────────────────────────────
create_icon() {
    # 用一个简单的 shell 生成图标（实际使用 iconutil 把 iconset 转成 icns）
    local iconset_path="$BUILD_DIR/AppIcon.iconset"
    mkdir -p "$iconset_path"

    # 生成一个简单的 256x256 PNG 作为图标（使用内置工具）
    # 用最低分辨率即可，系统会自动缩放
    local icon_path="$iconset_path/icon_256x256.png"

    # 创建简单的 App 图标（一个红色盾牌样式）
    /usr/bin/python3 -c "
import struct, zlib

def create_png(width, height, pixels, filepath):
    # PNG signature
    signature = b'\x89PNG\r\n\x1a\n'

    # IHDR chunk
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    ihdr_crc = zlib.crc32(b'IHDR' + ihdr_data)
    ihdr = struct.pack('>I', 13) + b'IHDR' + ihdr_data + struct.pack('>I', ihdr_crc)

    # IDAT chunk
    raw = b''
    for row in pixels:
        raw += b'\x00'  # filter byte
        raw += bytes(row)
    compressed = zlib.compress(raw)
    idat_crc = zlib.crc32(b'IDAT' + compressed)
    idat = struct.pack('>I', len(compressed)) + b'IDAT' + compressed + struct.pack('>I', idat_crc)

    # IEND chunk
    iend_crc = zlib.crc32(b'IEND')
    iend = struct.pack('>I', 0) + b'IEND' + struct.pack('>I', iend_crc)

    with open(filepath, 'wb') as f:
        f.write(signature + ihdr + idat + iend)

size = 256
pixels = []
for y in range(size):
    row = []
    for x in range(size):
        # Distance from center
        cx, cy = size//2, size//2
        dx, dy = abs(x - cx), abs(y - cy)
        dist = (dx*dx + dy*dy) ** 0.5

        if dist < 80:
            # Red shield area
            r, g, b = 220, 50, 50
        elif dist < 90:
            # White border
            r, g, b = 255, 255, 255
        elif dist < 128:
            # Dark border
            r, g, b = 180, 40, 40
        else:
            # Transparent background
            r, g, b = 0, 0, 0
        row.extend([r, g, b])
    pixels.append(row)

create_png(size, size, pixels, '$icon_path')
print('Icon created')
" 2>/dev/null || warn "图标生成失败，将使用默认图标"

    # 转为 icns
    if [ -f "$icon_path" ]; then
        iconutil -c icns "$iconset_path" -o "$RESOURCES_DIR/AppIcon.icns" 2>/dev/null || warn "图标转换失败"
    fi

    # 清理
    rm -rf "$iconset_path"
}

# ─── 步骤 4: 清理编译产物 ────────────────────────────────────────────────
cleanup() {
    # 保留二进制但删除中间文件
    rm -f "$BUILD_DIR/$APP_NAME" 2>/dev/null || true
    info "清理编译中间文件"
}

# ─── 主入口 ────────────────────────────────────────────────────────────────
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}AIKeyWipe — Build Tool${NC}              ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""

    cd "$PROJECT_DIR"

    check_env
    echo ""
    compile
    echo ""
    create_bundle
    echo ""

    # 可选签名
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then
        info "使用身份签名: $CODESIGN_IDENTITY"
        codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE" || warn "签名失败（不影响运行）"
    fi

    cleanup

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  ✅ 构建完成！${NC}"
    echo -e "${GREEN}  📦 $APP_BUNDLE${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""

    # 自动打开 Finder 显示
    open -R "$APP_BUNDLE" 2>/dev/null || true
}

main "$@"
