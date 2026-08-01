---
name: release-notes
description: 从 git 提交历史生成发布说明。用于 KeyClean 版本发布时自动生成用户友好的更新日志。
disable-model-invocation: true
allowed-tools: Read, Bash
---

## 使用说明

生成发布说明并以中文输出，按类型分组，面向最终用户。

## 执行流程

1. 获取最近标签：!`git describe --tags --abbrev=0 2>/dev/null || echo "无标签"`
2. 获取提交记录：!`git log $(git describe --tags --abbrev=0 2>/dev/null || echo "HEAD")..HEAD --oneline --no-decorate`
3. 获取详细提交信息：!`git log $(git describe --tags --abbrev=0 2>/dev/null || echo "HEAD")..HEAD --format="- %s%n%b" --no-merges`
4. 按 Conventional Commits 类型分组（feat/fix/docs/chore/refactor）
5. 将每个提交翻译为用户友好的中文描述
6. 格式化为 Markdown

## 输出格式

```markdown
## KeyClean v{version} - 更新说明

### ✨ 新功能
- 描述...

### 🐛 修复
- 描述...

### 🔧 优化
- 描述...

### 📝 其他
- 描述...
```
