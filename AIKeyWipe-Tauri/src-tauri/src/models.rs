use serde::{Deserialize, Serialize};

/// 单个清除目标
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WipeTarget {
    pub id: String,
    pub name: String,
    pub file_path: String,
    pub enabled: bool,
    pub custom_patterns: Vec<String>,
}

impl WipeTarget {
    pub fn expanded_path(&self) -> String {
        if self.file_path.starts_with("~/") {
            let home = dirs::home_dir().map(|h| h.to_string_lossy().to_string()).unwrap_or_default();
            self.file_path.replacen("~/", &format!("{}/", home), 1)
        } else if self.file_path == "~" {
            dirs::home_dir().map(|h| h.to_string_lossy().to_string()).unwrap_or_default()
        } else {
            self.file_path.clone()
        }
    }
}

/// 清除结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WipeResult {
    pub target_id: Option<String>,
    pub target_name: String,
    pub status: String,        // "success" | "skipped" | "failed"
    pub message: String,
}

/// 扫描结果项
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScannedFile {
    pub path: String,
    pub name: String,
}
