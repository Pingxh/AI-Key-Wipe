# 构建与打包文档

## 技术栈

- 前端：HTML + CSS + JS（原生 Tauri 前端）
- 后端：Rust + Tauri v2
- 构建工具：`cargo tauri build`

---

## 环境要求

### macOS

| 工具 | 版本要求 | 安装方式 |
|------|---------|---------|
| Xcode | >= 15 | App Store 或 Xcode 15.x |
| Rust | stable | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| Tauri CLI | 2.x | `cargo install tauri-cli --version "^2"` |

### Windows

| 工具 | 说明 |
|------|------|
| Microsoft Visual Studio Build Tools | 需要 C++ 构建工具链（WebView2 已内置于 Win10+） |
| Rust | stable-x86_64-pc-windows-msvc |
| Tauri CLI | 同上 |

### Linux

| 工具 | 安装命令 |
|------|---------|
| 系统依赖 | `sudo apt install libwebkit2gtk-4.1-dev build-essential curl wget file libssl-dev libayatana-appindicator3-dev librsvg2-dev` |
| Rust | 同上 |
| Tauri CLI | 同上 |

---

## 构建命令

### 开发模式（实时预览）

```bash
cd AIKeyWipe-Tauri
cargo tauri dev
```

纯前端修改热更新，Rust 后端修改需手动重新编译。

### 生产构建

```bash
cd AIKeyWipe-Tauri
cargo tauri build
```

默认 target 在 `tauri.conf.json` 中配置为 `"all"`，macOS 下会同时产出：

- `.app` — macOS 可执行包
- `.dmg` — 安装镜像

### 构建产物位置

```
src-tauri/target/release/bundle/
├── macos/KeyClean.app          # .app 包
└── dmg/KeyClean_1.0.0_aarch64.dmg  # 安装镜像
```

---

## 图标替换

图标文件在 `src-tauri/icons/` 目录下：

| 文件 | 尺寸 | 用途 |
|------|------|------|
| `32x32.png` | 32×32 | 应用图标（小尺寸） |
| `128x128.png` | 128×128 | 应用图标 |
| `128x128@2x.png` | 256×256 | 应用图标（Retina） |
| `icon.png` | 32×32 | 通用入口（实际由上面覆盖） |
| `icon.icns` | — | macOS 图标（从 iconset 生成） |
| `icon.ico` | — | Windows 图标 |
| `tray-icon.png` | 32×32 | 菜单栏托盘图标 |

### 重新生成 macOS .icns

```bash
cd src-tauri/icons
rm -f icon.icns
iconutil -c icns iconset.iconset -o icon.icns
```

iconset 目录结构要求：

```
iconset.iconset/
├── icon-16.png       (16×16)
├── icon-16@2x.png    (32×32)
├── icon-32.png       (32×32)
├── icon-32@2x.png    (64×64)
├── icon-128.png      (128×128)
├── icon-128@2x.png   (256×256)
├── icon-256.png      (256×256)
├── icon-256@2x.png   (512×512)
├── icon-512.png      (512×512)
└── icon-512@2x.png   (1024×1024)
```

### 生成 Windows .ico

```bash
# 需要 ImageMagick 或 Pillow
magick convert icon-256.png icon.ico
```

---

## 跨平台构建

### 方案一：本地构建（推荐 macOS 开发者）

在 macOS 上只能构建 macOS 的 dmg/app。Windows 和 Linux 构建需要对应平台。

### 方案二：GitHub Actions CI/CD

项目已有 CI 配置（`.github/workflows/`）。提交 tag 后自动构建 Release：

```bash
git tag v1.0.1
git push origin v1.0.1
```

CI 会在 macOS / Windows / Ubuntu 三个 runner 上分别构建对应平台的产物，并上传到 GitHub Releases。

### 方案三：交叉编译（不推荐）

Tauri v2 的 WebView 绑定依赖原生 SDK，交叉编译极其复杂。建议直接用对应平台的物理机或 CI runner。

---

## 代码签名（macOS）

### 开发签名（Xcode 自动管理）

```bash
# 查看可用签名证书
security find-identity -v -p codesigning

# 手动签名 App
codesign --force --deep --sign "Developer ID Application: Your Name (TEAMID)" \
  src-tauri/target/release/bundle/macos/KeyClean.app
```

### 公证（Notarization）

从 macOS 10.15+ 起，未公证的 App 在默认安全设置下无法运行：

```bash
# 压缩并提交公证
ditto -c -k --keepParent KeyClean.app KeyClean.zip
xcrun notarytool submit KeyClean.zip \
  --apple-id "your@email.com" \
  --team-id "TEAMID" \
  --password "app-specific-password" \
  --wait

# 钉上公证凭证
xcrun stapler staple KeyClean.app
```

---

## 常见问题

### DMG 打包失败

```
Error failed to bundle project: error running bundle_dmg.sh
```

重试一次即可，偶发脚本竞争问题。如果持续失败，检查磁盘空间和 `/tmp/` 权限。

### 图标不更新

Tauri 构建会缓存图标。删除构建目录重新 build：

```bash
rm -rf src-tauri/target
cargo tauri build
```

### WebView2 运行时

Windows 10+ 已内置 WebView2。Windows 7/8 需要手动安装 Evergreen 运行时。

---

## 版本号与配置

版本号在 `src-tauri/tauri.conf.json` 的 `version` 字段和 `Cargo.toml` 的 `version` 字段中维护，两者必须一致。

```json
{
  "version": "1.0.0",
  "identifier": "com.keyclean",
  "bundle": {
    "macOS": {
      "minimumSystemVersion": "13.0"
    }
  }
}
```