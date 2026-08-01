---
name: project-conventions
description: KeyClean（AIKeyWipe）项目代码风格与约定。写代码或审查代码时自动应用，确保一致性。
user-invocable: false
allowed-tools: Read, Grep, Glob
---

## 命名规范

### Rust
- **函数/变量**: snake_case
- **类型/trait**: PascalCase
- **常量**: SCREAMING_SNAKE_CASE
- **文件名**: snake_case.rs

### 前端（HTML/CSS/JS）
- **CSS 类名**: kebab-case
- **JS 变量/函数**: camelCase
- **HTML ID**: kebab-case
- **文件名**: kebab-case

## 架构模式

### Rust 后端（src-tauri/src/）
- **状态管理**: 使用 Tauri State 管理 AppState
- **序列化/反序列化**: 使用 serde + serde_json
- **错误处理**: 使用 Result<T, E>，避免 unwrap()
- **文件路径**: 使用 dirs crate 获取标准目录
- **正则匹配**: 使用 regex crate 预编译模式，一次性匹配多种 API Key 格式

### 前端（src/）
- **原生 JS**: 不使用任何前端框架，保持轻量
- **直接 DOM 操作**: 使用 document.getElementById / querySelector
- **CSS**: 集中式 style.css 管理，避免内联样式

## 安全约定
- API Key 匹配模式定义在 Rust 后端（models.rs）
- 敏感数据在内存中及时清除
- 文件写入使用临时文件 + 原子重命名模式
- 平台路径处理区分 macOS / Windows / Linux

## 禁止事项
- 不要在 JS 中硬编码 API Key 正则模式（由 Rust 侧定义）
- 不要使用 unwrap() / expect()（使用 match 或 ? 操作符）
- 不要在前端日志中输出完整文件路径
- 不要直接修改 Cargo.lock（使用 cargo update）
