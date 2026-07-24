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
        let path = self.file_path.replace("~", &dirs::home_dir()
            .unwrap_or_default().to_string_lossy());
        path
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
