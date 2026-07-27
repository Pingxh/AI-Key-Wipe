use std::fs;
use std::path::PathBuf;

use crate::models::WipeTarget;

/// 持久化存储：targets 保存为 app 沙盒 data 目录下的 targets.json
/// 路径基于 app 标识符（com.keyclean），与 tauri.conf.json 一致
pub fn storage_path() -> PathBuf {
    let app_dir = dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("com.keyclean");
    let _ = fs::create_dir_all(&app_dir);
    app_dir.join("targets.json")
}

/// 从本地 JSON 加载目标列表（首次启动返回空）
pub fn load_targets() -> Vec<WipeTarget> {
    let path = storage_path();
    if !path.exists() {
        return Vec::new();
    }
    let content = match fs::read_to_string(&path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("加载 targets 失败: {}", e);
            return Vec::new();
        }
    };
    serde_json::from_str(&content).unwrap_or_else(|e| {
        eprintln!("targets.json 解析失败: {}", e);
        Vec::new()
    })
}

/// 将目标列表持久化到本地 JSON
pub fn save_targets(targets: &[WipeTarget]) {
    let path = storage_path();
    let content = match serde_json::to_string_pretty(targets) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("序列化 targets 失败: {}", e);
            return;
        }
    };
    if let Err(e) = fs::write(&path, &content) {
        eprintln!("保存 targets 失败: {}", e);
    }
}

/// 检查文件路径是否存在
pub fn path_exists(path: &str) -> bool {
    let expanded = if path.starts_with("~/") {
        dirs::home_dir()
            .map(|h| h.join(&path[2..]).to_string_lossy().to_string())
            .unwrap_or_default()
    } else {
        path.to_string()
    };
    std::path::Path::new(&expanded).exists()
}
