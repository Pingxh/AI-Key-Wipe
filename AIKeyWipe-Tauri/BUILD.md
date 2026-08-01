# 构建与打包文档

## 技术栈

- 前端：HTML + CSS + JS（原生 Tauri 前端，无框架依赖）
- 后端：Rust + Tauri v2
- 构建工具：`cargo tauri build`

---

## 环境要求

### macOS

| 工具 | 版本要求 | 安装方式 |
|------|---------|---------|
| Xcode | >= 15 | App Store 或 Xcode 15.x |
| Rust | stable | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh` |
| Tauri CLI | 2.x | `cargo install tauri-cli --version "^2"` |

### Windows

| 工具 | 说明 |
|------|------|
| Microsoft Visual Studio Build Tools | 需要 C++ 构建工具链（WebView2 已内置于 Win10+） |
| Rust | `stable-x86_64-pc-windows-msvc` |
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

前端为纯 HTML/JS，修改即时生效。Rust 后端修改需重新编译。

### 生产构建

```bash
cd AIKeyWipe-Tauri
cargo tauri build
```

`tauri.conf.json` 中 `bundle.targets` 为 `"all"`，会自动产出对应平台的安装包。

### 构建产物位置

```
src-tauri/target/release/bundle/
├── macos/KeyClean.app          # macOS .app 包
├── dmg/KeyClean_1.0.0_aarch64.dmg  # macOS 安装镜像
├── msi/KeyClean_1.0.0_x64.msi      # Windows 安装包
└── deb/KeyClean_1.0.0_amd64.deb    # Linux 安装包
```

---

## 跨平台构建

### 方案一：本地构建

在对应平台上直接运行 `cargo tauri build` 即可。

### 方案二：GitHub Actions CI/CD

项目已配置 CI（`.github/workflows/release.yml`）。推送 tag 后自动构建 Release：

```bash
git tag v1.0.0
git push origin v1.0.0
```

CI 会在 macOS / Windows / Ubuntu 三个 runner 上分别构建，上传到 GitHub Releases。

---

## 图标说明

图标文件在 `src-tauri/icons/` 目录下：

| 文件 | 用途 |
|------|------|
| `icon.icns` | macOS 图标 |
| `icon.ico` | Windows 图标 |
| `icon.png` | Linux / 通用图标 |
| `tray-icon.png` | 托盘图标 |
| `iconset.iconset/` | macOS 多尺寸图标源文件 |

### 重新生成 macOS .icns

```bash
cd src-tauri/icons
iconutil -c icns iconset.iconset -o icon.icns
```

### 生成 Windows .ico

```bash
# 需要 ImageMagick
magick convert icon-256.png icon.ico
```

---

## 版本号维护

版本号在 `src-tauri/tauri.conf.json` 的 `version` 字段中维护。

```json
{
  "version": "1.0.0",
  "identifier": "com.keyclean",
  "bundle": {
    "macOS": { "minimumSystemVersion": "13.0" }
  }
}
```

---

## 常见问题

### 构建失败：cargo tauri build 提示找不到 WebView2

- Windows 10+ 无需安装，已内置
- Windows 7/8 需手动安装 [Evergreen 运行时](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)

### macOS 构建失败：Xcode 版本不匹配

确保 `xcode-select -p` 指向正确的 Xcode 路径：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### DMG 打包偶发失败

```bash
Error failed to bundle project: error running bundle_dmg.sh
```

重试一次即可。持续失败则检查磁盘空间和 `/tmp/` 权限。

### 图标不更新

清理构建缓存后重新 build：

```bash
rm -rf src-tauri/target
cargo tauri build
```