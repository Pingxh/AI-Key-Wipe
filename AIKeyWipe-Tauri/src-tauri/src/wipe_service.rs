use std::fs;
use std::io::Read;
use std::path::Path;
use regex::Regex;
use crate::models::{WipeTarget, WipeResult, ScannedFile};

/// 内置默认匹配模式
const DEFAULT_PATTERNS: &[&str] = &[
    "KEY=", "API_KEY=", "TOKEN=", "SECRET=", "PASSWORD=",
    "api_key:", "token:", "secret:", "_API_KEY",
];

/// 要扫描的配置文件扩展名
const CONFIG_EXTS: &[&str] = &[".env", ".envrc", ".yaml", ".yml", ".json", ".toml", ".conf", ".cfg"];

/// 平台无关的通用跳过目录
const SKIP_DIRS_COMMON: &[&str] = &[
    ".git", "node_modules", ".cache", "Caches", "__pycache__",
    "venv", ".venv", ".Trash", ".rvm", ".nvm",
    ".oh-my-zsh", ".gem", ".cocoapods", ".m2",
    "Pods", "build", "dist", ".next", ".turbo",
];

/// macOS 特定跳过目录
#[cfg(target_os = "macos")]
const SKIP_DIRS_PLATFORM: &[&str] = &[
    "Library", "Applications", "Desktop", "Downloads", "Documents",
    "Public", "Music", "Pictures", "Movies",
];

/// Windows 特定跳过目录（Windows 用户目录结构不同）
/// 注意：Desktop/Documents/Downloads 不跳过，用户可能在这些目录下放项目文件
#[cfg(target_os = "windows")]
const SKIP_DIRS_PLATFORM: &[&str] = &[
    // 用户目录下的系统文件夹（不含项目文件）
    "AppData", "Application Data", "Local Settings",
    "Music", "Pictures", "Videos",
    "Public", "OneDrive", "3D Objects",
    "Contacts", "Favorites", "Links", "Saved Games", "Searches",
    // Windows 系统目录
    "Windows", "System32", "Program Files", "Program Files (x86)",
    "ProgramData", "Recovery", "System Volume Information",
];

/// Linux 特定跳过目录
#[cfg(target_os = "linux")]
const SKIP_DIRS_PLATFORM: &[&str] = &[
    "Desktop", "Downloads", "Documents", "Music", "Pictures", "Videos",
    "Public", "snap", "flatpak", ".local", ".config",
];

/// 合并所有跳过目录
fn is_skip_dir(name: &str) -> bool {
    SKIP_DIRS_COMMON.contains(&name) || SKIP_DIRS_PLATFORM.contains(&name)
}

/// 合并内置 + 自定义模式
fn build_patterns(custom: &[String]) -> Vec<String> {
    let mut all: Vec<String> = DEFAULT_PATTERNS.iter().map(|s| s.to_string()).collect();
    for p in custom {
        let upper = p.to_uppercase();
        if !all.iter().any(|x| x.to_uppercase() == upper) {
            all.push(p.clone());
        }
    }
    all
}

/// 判断是否为 YAML 格式行（= 出现在第一个 : 之前说明是 .env 格式）
fn is_yaml_key(line: &str) -> bool {
    if let Some(pos) = line.find(':') {
        let before = &line[..pos];
        !before.contains('=')
    } else {
        false
    }
}

/// 清除文件中的 API Key
pub fn wipe_file(path: &str, custom_patterns: &[String]) -> Result<WipeResult, String> {
    let content = fs::read_to_string(path)
        .map_err(|e| format!("读取失败: {}", e))?;

    let all_lines: Vec<&str> = content.lines().collect();
    let patterns = build_patterns(custom_patterns);
    let mut modified_lines: Vec<String> = Vec::new();
    let mut wiped_count = 0;
    let mut skip_indented = false;

    for (i, line) in all_lines.iter().enumerate() {
        if skip_indented {
            let trimmed = line.trim();
            if !trimmed.is_empty() && line.starts_with(' ') {
                skip_indented = false;
                continue;
            }
            skip_indented = false;
        }

        let trimmed = line.trim();
        let leading_spaces: &str = &line[..line.len() - line.trim_start().len()];

        // 跳过注释
        if trimmed.starts_with('#') || trimmed.starts_with("//") {
            modified_lines.push(line.to_string());
            continue;
        }

        // 匹配模式
        let is_key_line = patterns.iter().any(|p| trimmed.contains(p.as_str()));
        if !is_key_line {
            modified_lines.push(line.to_string());
            continue;
        }

        // 精确匹配自定义模式 → 整行删除
        if !custom_patterns.is_empty() {
            let trimmed2 = trimmed;
            if custom_patterns.iter().any(|cp| trimmed2 == cp.as_str() || trimmed2 == cp.trim()) {
                modified_lines.push(String::new());
                wiped_count += 1;
                continue;
            }
        }

        let yaml = is_yaml_key(trimmed);
        let has_inline_value = if yaml {
            let re = Regex::new(r"^[^:]*:\s*").unwrap();
            let after = re.replace(trimmed, "");
            !after.is_empty() && after != "\"\""
        } else {
            let re = Regex::new(r"^[^=]*=").unwrap();
            let after = re.replace(trimmed, "");
            !after.is_empty()
        };

        // 生成清除后的行
        if trimmed.contains("export ") {
            let re = Regex::new(r"^(export\s+[A-Za-z_][A-Za-z0-9_]*\s*=).*").unwrap();
            let clean = re.replace(trimmed, "$1");
            modified_lines.push(clean.to_string());
        } else if yaml {
            if has_inline_value {
                let re = Regex::new(r"^([a-zA-Z_][a-zA-Z0-9_]*\s*:\s*).*").unwrap();
                let clean = re.replace(trimmed, "$1\"\"");
                modified_lines.push(format!("{}{}", leading_spaces, clean));
            } else {
                let re = Regex::new(r":.*").unwrap();
                let clean = re.replace(trimmed, ": \"\"");
                modified_lines.push(format!("{}{}", leading_spaces, clean));
                if i + 1 < all_lines.len() {
                    let next = all_lines[i + 1];
                    if next.starts_with(' ') && !next.trim().is_empty() {
                        skip_indented = true;
                    }
                }
            }
        } else {
            if has_inline_value {
                let re = Regex::new(r"^([A-Za-z_][A-Za-z0-9_]*\s*=).*").unwrap();
                let clean = re.replace(trimmed, "$1");
                modified_lines.push(clean.to_string());
            } else {
                modified_lines.push(line.to_string());
            }
        }
        wiped_count += 1;
    }

    let new_content = modified_lines.join("\n");
    fs::write(path, &new_content)
        .map_err(|e| format!("写入失败: {}", e))?;

    let file_name = std::path::Path::new(path)
        .file_name().unwrap_or_default().to_string_lossy().to_string();

    Ok(WipeResult {
        target_id: None,
        target_name: file_name,
        status: "success".to_string(),
        message: format!("已清除 {} 个 Key", wiped_count),
    })
}

/// 批量执行清除
pub fn execute_wipe(targets: &[WipeTarget]) -> Vec<WipeResult> {
    let mut results = Vec::new();
    for target in targets {
        if !target.enabled {
            results.push(WipeResult {
                target_id: Some(target.id.clone()),
                target_name: target.name.clone(),
                status: "skipped".to_string(),
                message: "已禁用，跳过".to_string(),
            });
            continue;
        }
        let path = target.expanded_path();
        match wipe_file(&path, &target.custom_patterns) {
            Ok(mut r) => {
                r.target_id = Some(target.id.clone());
                r.target_name = target.name.clone();
                results.push(r);
            }
            Err(e) => {
                results.push(WipeResult {
                    target_id: Some(target.id.clone()),
                    target_name: target.name.clone(),
                    status: "failed".to_string(),
                    message: e,
                });
            }
        }
    }
    results
}

/// 扫描 ~/ 下的配置文件，返回含 API Key 的文件列表
/// 递归扫描
pub fn scan_for_keys(progress: impl Fn(&str)) -> Vec<ScannedFile> {
    let mut results = Vec::new();
    let home = match dirs::home_dir() {
        Some(h) => h,
        None => {
            progress("错误: 无法获取用户家目录路径");
            return results;
        }
    };

    let home_str = home.to_string_lossy().to_string();
    progress(&format!("开始扫描: {}", home_str));

    let patterns = DEFAULT_PATTERNS;

    // 不同平台扫描深度不同
    // Windows: 用户项目可能散落在 Desktop/Documents/Downloads 等目录，需要更深
    #[cfg(target_os = "windows")]
    let max_depth = 5;
    #[cfg(not(target_os = "windows"))]
    let max_depth = 4;

    // 递归扫描
    scan_dir_recursive(&home, 0, max_depth, patterns, &mut results, &progress);

    // Windows 额外扫描 AppData 中的常见配置文件位置
    #[cfg(target_os = "windows")]
    {
        let paths_to_check = [
            // 用户主目录下的 .env 等
            home.join(".env"),
            home.join(".envrc"),
            home.join(".gitconfig"),
            // AppData\Roaming 下的常见配置
            dirs::config_dir().map(|d| d.join("pip").join("pip.conf")),
            dirs::config_dir().map(|d| d.join("npmrc")),
            dirs::config_dir().map(|d| d.join(".buckconfig")),
        ];

        for p in paths_to_check.iter().flatten() {
            if p.is_file() {
                check_file(p, patterns, &mut results, &progress);
            }
        }

        // 扫描 AppData\Roaming\ 下的 .env 和 .json 文件（深度1）
        if let Some(config) = dirs::config_dir() {
            if let Ok(entries) = fs::read_dir(&config) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.is_file() {
                        check_file(&path, patterns, &mut results, &progress);
                    }
                }
            }
        }
    }

    progress(&format!("扫描完成，共发现 {} 个文件", results.len()));
    results
}

/// 递归扫描目录（最大深度限制）
fn scan_dir_recursive(
    dir: &Path,
    depth: usize,
    max_depth: usize,
    patterns: &[&str],
    results: &mut Vec<ScannedFile>,
    progress: impl Fn(&str),
) {
    if depth > max_depth {
        return;
    }

    // 深度 >= 2 时显示正在扫描的目录名，让用户知道进度
    if depth >= 2 {
        progress(&format!("扫描: {}", dir.display()));
    }

    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(e) => {
            progress(&format!("⚠ 无法读取目录 ({}): {}", dir.display(), e));
            return;
        }
    };

    for entry in entries.flatten() {
        let path = entry.path();

        // 检查是否为符号链接，避免循环引用
        if path.is_symlink() {
            continue;
        }

        if path.is_dir() {
            let name = path.file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string();

            // 跳过隐藏目录（以 . 开头的）除非是 .env 等常见配置目录
            if name.starts_with('.') && !is_allowed_hidden_dir(&name) {
                continue;
            }

            if is_skip_dir(&name) {
                continue;
            }

            // 递归下一层
            scan_dir_recursive(&path, depth + 1, max_depth, patterns, results, &progress);
            continue;
        }

        if path.is_file() {
            check_file(&path, patterns, results, &progress);
        }
    }
}

/// 允许扫描的隐藏目录（不跳过）
fn is_allowed_hidden_dir(name: &str) -> bool {
    matches!(name, ".ssh" | ".gnupg" | ".aws" | ".azure" | ".gcloud" | ".docker" | ".kube")
}

fn check_file(
    path: &Path,
    patterns: &[&str],
    results: &mut Vec<ScannedFile>,
    progress: impl Fn(&str),
) {
    let path_buf = path.to_path_buf();
    let ext = path_buf.extension().map(|e| format!(".{}", e.to_string_lossy().to_lowercase()))
        .unwrap_or_default();
    if !CONFIG_EXTS.iter().any(|e| ext == *e) && !path_buf.to_string_lossy().contains(".env") {
        return;
    }

    progress(&format!("扫描: {}", path_buf.file_name().unwrap_or_default().to_string_lossy()));

    // 读取前 10KB
    let mut file = match fs::File::open(path) {
        Ok(f) => f,
        _ => return,
    };
    let mut buf = vec![0u8; 10240];
    let n = file.read(&mut buf).unwrap_or(0);
    if n == 0 { return; }
    let content = String::from_utf8_lossy(&buf[..n]);

    let has_key = content.lines().any(|line| {
        let t = line.trim();
        if t.starts_with('#') || t.is_empty() { return false; }
        patterns.iter().any(|p| t.contains(p))
    });

    if has_key {
        let name = format!("{}/{}",
            path_buf.parent().and_then(|p| p.file_name()).map(|n| n.to_string_lossy()).unwrap_or_default(),
            path_buf.file_name().map(|n| n.to_string_lossy()).unwrap_or_default());
        let full_path = path_buf.to_string_lossy().to_string();
        if !results.iter().any(|r| r.path == full_path) {
            results.push(ScannedFile { path: full_path, name });
        }
    }
}
