mod models;
mod wipe_service;

use models::{WipeTarget, WipeResult, ScannedFile};

/// Tauri 命令：执行批量清除
#[tauri::command]
fn cmd_wipe(targets: Vec<WipeTarget>) -> Vec<WipeResult> {
    wipe_service::execute_wipe(&targets)
}

/// Tauri 命令：扫描配置文件
#[tauri::command]
fn cmd_scan() -> Vec<ScannedFile> {
    wipe_service::scan_for_keys(|_| {})
}

/// Tauri 命令：扫描单个文件
#[tauri::command]
fn cmd_scan_file(path: String, custom_patterns: Vec<String>) -> Vec<String> {
    let content = match std::fs::read_to_string(&path) {
        Ok(c) => c,
        _ => return vec!["无法读取文件".to_string()],
    };
    let patterns = vec!["KEY=", "API_KEY=", "TOKEN=", "SECRET=", "PASSWORD=",
                        "api_key:", "token:", "secret:", "_API_KEY"];
    let all_patterns: Vec<String> = patterns.iter().map(|s| s.to_string())
        .chain(custom_patterns).collect();

    let mut found = Vec::new();
    for line in content.lines() {
        let t = line.trim();
        if t.starts_with('#') || t.is_empty() { continue; }
        for p in &all_patterns {
            if t.contains(p.as_str()) {
                let masked = t.replace(&t[t.find('=').unwrap_or(t.len())..], "=******");
                found.push(masked);
                break;
            }
        }
    }
    found
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![cmd_wipe, cmd_scan, cmd_scan_file])
        .run(tauri::generate_context!())
        .expect("启动 AI-Key-Wipe 失败");
}
