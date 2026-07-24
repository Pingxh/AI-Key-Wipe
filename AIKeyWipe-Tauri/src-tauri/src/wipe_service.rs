use std::fs;
use std::io::Read;
use regex::Regex;
use crate::models::{WipeTarget, WipeResult, ScannedFile};

/// 内置默认匹配模式
const DEFAULT_PATTERNS: &[&str] = &[
    "KEY=", "API_KEY=", "TOKEN=", "SECRET=", "PASSWORD=",
    "api_key:", "token:", "secret:", "_API_KEY",
];

/// 要扫描的配置文件扩展名
const CONFIG_EXTS: &[&str] = &[".env", ".envrc", ".yaml", ".yml", ".json", ".toml", ".conf", ".cfg"];

/// 跳过的目录
const SKIP_DIRS: &[&str] = &[
    "Library", "Applications", "Desktop", "Downloads", "Documents",
    "Public", "Music", "Pictures", "Movies", ".Trash", ".git",
    "node_modules", ".cache", "Caches", ".rvm", ".nvm",
    ".oh-my-zsh", ".gem", ".cocoapods", ".m2",
    "venv", ".venv", "__pycache__", "Pods",
];

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
pub fn scan_for_keys(progress: impl Fn(&str)) -> Vec<ScannedFile> {
    let mut results = Vec::new();
    let home = match dirs::home_dir() {
        Some(h) => h,
        None => return results,
    };
    let patterns = DEFAULT_PATTERNS;

    if let Ok(entries) = fs::read_dir(&home) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                let name = path.file_name().unwrap_or_default().to_string_lossy().to_string();
                if SKIP_DIRS.contains(&name.as_str()) { continue; }
                // 递归扫描子目录（深度1）
                if let Ok(sub_entries) = fs::read_dir(&path) {
                    for sub in sub_entries.flatten() {
                        let sub_path = sub.path();
                        if sub_path.is_file() {
                            check_file(&sub_path, patterns, &mut results, &progress);
                        }
                    }
                }
                continue;
            }
            if path.is_file() {
                check_file(&path, patterns, &mut results, &progress);
            }
        }
    }
    results
}

fn check_file(
    path: &std::path::PathBuf,
    patterns: &[&str],
    results: &mut Vec<ScannedFile>,
    progress: impl Fn(&str),
) {
    let ext = path.extension().map(|e| format!(".{}", e.to_string_lossy().to_lowercase()))
        .unwrap_or_default();
    if !CONFIG_EXTS.iter().any(|e| ext == *e) && !path.to_string_lossy().contains(".env") {
        return;
    }

    progress(&format!("扫描: {}", path.file_name().unwrap_or_default().to_string_lossy()));

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
            path.parent().and_then(|p| p.file_name()).map(|n| n.to_string_lossy()).unwrap_or_default(),
            path.file_name().map(|n| n.to_string_lossy()).unwrap_or_default());
        let full_path = path.to_string_lossy().to_string();
        if !results.iter().any(|r| r.path == full_path) {
            results.push(ScannedFile { path: full_path, name });
        }
    }
}
