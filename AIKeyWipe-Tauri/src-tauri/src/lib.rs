mod models;
mod wipe_service;

use models::{WipeTarget, WipeResult, ScannedFile};
use tauri::Manager;
use tauri::menu::{MenuBuilder, SubmenuBuilder, MenuItemBuilder, PredefinedMenuItem};

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

/// Tauri 命令：在访达中显示文件（macOS only）
#[tauri::command]
fn cmd_reveal(path: String) {
    #[cfg(target_os = "macos")]
    std::process::Command::new("open")
        .args(["-R", &path])
        .spawn()
        .ok();
}

/// Tauri 命令：打开文件选择器，返回选中路径
#[tauri::command]
fn cmd_pick_file(default_dir: Option<String>) -> Option<String> {
    let mut dialog = rfd::FileDialog::new().set_title("选择文件");
    if let Some(dir) = default_dir {
        // 展开 ~ 为家目录
        let expanded = if dir == "~" || dir.starts_with("~/") {
            dirs::home_dir().map(|h| {
                let rest = dir.trim_start_matches('~');
                if rest.is_empty() { h } else { h.join(rest.trim_start_matches('/')) }
            })
        } else {
            Some(std::path::PathBuf::from(&dir))
        };
        if let Some(ref p) = expanded {
            if p.exists() {
                let target = if p.is_dir() { p.clone() } else { p.parent().map(|x| x.to_path_buf()).unwrap_or(p.clone()) };
                dialog = dialog.set_directory(&target);
            }
        }
    }
    dialog.pick_file().map(|p| p.to_string_lossy().to_string())
}

/// Tauri 命令：原生确认对话框
#[tauri::command]
fn cmd_confirm(message: String) -> bool {
    rfd::MessageDialog::new()
        .set_title("AI-Key-Wipe")
        .set_description(&message)
        .set_buttons(rfd::MessageButtons::YesNo)
        .show()
        == rfd::MessageDialogResult::Yes
}

/// Tauri 命令：原生提示对话框
#[tauri::command]
fn cmd_alert(message: String) {
    rfd::MessageDialog::new()
        .set_title("AI-Key-Wipe")
        .set_description(&message)
        .set_buttons(rfd::MessageButtons::Ok)
        .show();
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let show_item = MenuItemBuilder::with_id("show-window", "主界面")
                .accelerator("CmdOrCtrl+1")
                .build(app)?;
            let wipe_item = MenuItemBuilder::with_id("wipe-all", "清理所有数据")
                .accelerator("CmdOrCtrl+Shift+W")
                .build(app)?;
            let quit_item = PredefinedMenuItem::quit(app, Some("退出"))?;

            let app_submenu = SubmenuBuilder::new(app, "AI-Key-Wipe")
                .item(&show_item)
                .item(&wipe_item)
                .separator()
                .item(&quit_item)
                .build()?;

            let menu = MenuBuilder::new(app)
                .item(&app_submenu)
                .build()?;

            app.set_menu(menu)?;

            // 给托盘图标设置菜单
            let tray_menu = MenuBuilder::new(app)
                .item(&show_item)
                .item(&wipe_item)
                .separator()
                .item(&quit_item)
                .build()?;
            if let Some(tray) = app.tray_by_id("main") {
                let _ = tray.set_menu(Some(tray_menu));
            }

            Ok(())
        })
        .on_menu_event(|app, event| {
            match event.id().as_ref() {
                "show-window" => {
                    #[cfg(target_os = "macos")]
                    let _ = app.set_activation_policy(tauri::ActivationPolicy::Regular);
                    if let Some(w) = app.get_webview_window("main") {
                        let _ = w.show();
                        let _ = w.set_focus();
                    }
                }
                "wipe-all" => {
                    if let Some(w) = app.get_webview_window("main") {
                        let _ = w.eval("(async() => { if(state.targets.length > 0) { state.selectedIds = new Set(state.targets.map(t => t.id)); confirmWipe(); } })()");
                    }
                }
                _ => {}
            }
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
                #[cfg(target_os = "macos")]
                let _ = window.app_handle().set_activation_policy(tauri::ActivationPolicy::Accessory);
            }
        })
        .invoke_handler(tauri::generate_handler![cmd_wipe, cmd_scan, cmd_scan_file, cmd_reveal, cmd_pick_file, cmd_confirm, cmd_alert])
        .run(tauri::generate_context!())
        .expect("启动 AI-Key-Wipe 失败");
}
