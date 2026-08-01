import Foundation

/// 执行清除操作的服务
class WipeService {

    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()

    var backupBaseURL: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        let backups = home.appendingPathComponent("AI-Key-Wipe/backups")
        try? fileManager.createDirectory(at: backups, withIntermediateDirectories: true)
        return backups
    }

    // MARK: - 内置默认匹配模式
    private static let defaultPatterns = [
        "KEY=", "API_KEY=", "TOKEN=", "SECRET=", "PASSWORD=",
        "api_key:", "token:", "secret:", "_API_KEY"
    ]

    /// 合并内置 + 自定义模式（自定义优先）
    private func buildPatterns(custom: [String]) -> [String] {
        var all = Self.defaultPatterns
        for p in custom {
            let upper = p.uppercased()
            if !all.contains(where: { $0.uppercased() == upper }) {
                all.append(p)
            }
        }
        return all
    }

    // MARK: - 扫描文件中的 API Key
    func scanFile(at path: String, customPatterns: [String] = []) -> [String] {
        let url = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var found: [String] = []

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 跳过注释
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { continue }

            // 匹配 KEY= / TOKEN= / SECRET= / PASSWORD= 模式
            let patterns = buildPatterns(custom: customPatterns)
            for pattern in patterns {
                if trimmed.contains(pattern) {
                    let masked = trimmed.replacingOccurrences(
                        of: "=.*$", with: "=******",
                        options: .regularExpression
                    )
                    found.append(masked)
                    break
                }
            }
        }
        return found
    }

    // MARK: - 清除文件中的 Key
    func wipeFile(at path: String, customPatterns: [String] = [], targetId: UUID? = nil, backup: Bool = true) -> WipeResult? {
        let url = URL(fileURLWithPath: path)
        let fileName = url.lastPathComponent
        let dirName = url.deletingLastPathComponent().lastPathComponent
        let displayName = "\(dirName)/\(fileName)"

        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        // 1. 备份
        if backup {
            let dateStr = dateFormatter.string(from: Date())
            let backupDir = backupBaseURL.appendingPathComponent(dateStr)
            let dest = backupDir.appendingPathComponent("\(dirName)-\(fileName)")

            do {
                try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
                try fileManager.copyItem(at: url, to: dest)
            } catch {
                return WipeResult(
                    targetId: targetId,
                    targetName: displayName,
                    status: .failed,
                    message: "备份失败: \(error.localizedDescription)",
                    timestamp: Date()
                )
            }
        }

        do {
            var content = try String(contentsOf: url, encoding: .utf8)
            let allLines = content.components(separatedBy: .newlines)
            var modifiedLines: [String] = []
            var wipedCount = 0
            var skipIndentedValue = false  // 标记：下一行的缩进值是上一行 YAML key 的值，需要跳过

            for (i, line) in allLines.enumerated() {
                // ── 如果上一条是 YAML key: 且值在下一行，跳过本行 ──
                if skipIndentedValue {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && line.hasPrefix(" ") {
                        // 跳过这行（它是 key: 的换行值）
                        skipIndentedValue = false
                        continue
                    }
                    skipIndentedValue = false
                    // 不跳过——它不是缩进值，继续正常处理
                }

                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let leadingSpaces = line.prefix(while: { $0 == " " })

                // 跳过已注释的行
                if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") {
                    modifiedLines.append(line)
                    continue
                }

                // ── 检查是否包含 Key/Token/Secret ──
                let keyPatterns = buildPatterns(custom: customPatterns)
                var isKeyLine = false
                for pattern in keyPatterns {
                    if trimmed.contains(pattern) {
                        isKeyLine = true
                        break
                    }
                }

                if !isKeyLine {
                    modifiedLines.append(line)
                    continue
                }

                // ── 自定义模式精确匹配整行 → 整行删除 ──
                // 如果用户设置的某个自定义模式与整行内容完全相同，直接删除该行
                if !customPatterns.isEmpty {
                    let isExactMatch = customPatterns.contains { cp in
                        trimmed == cp || trimmed == cp.trimmingCharacters(in: .whitespaces)
                    }
                    if isExactMatch {
                        modifiedLines.append("")  // 空行 = 删除该行
                        wipedCount += 1
                        continue
                    }
                }

                // ── 判断是否多行值（key: 后面没值，值在下一行） ──
                // 注意：只有 YAML 用 ":" 做 key-value 分隔符，.env 用 "="
                // 如果 "=" 出现在第一个 ":" 之前，说明这是 .env 格式而非 YAML
                let isYamlKey: Bool = {
                    if let colonRange = trimmed.range(of: ":") {
                        let beforeColon = trimmed[..<colonRange.lowerBound]
                        return !beforeColon.contains("=")
                    }
                    return false
                }()
                let hasInlineValue: Bool = {
                    if isYamlKey {
                        // 冒号后有非空内容才算有行内值
                        let afterColon = trimmed.replacingOccurrences(
                            of: #"^[^:]*:\s*"#, with: "",
                            options: .regularExpression
                        )
                        return !afterColon.isEmpty && afterColon != "\"\""
                    }
                    // KEY= 格式，等号后有内容才算有行内值
                    let afterEq = trimmed.replacingOccurrences(
                        of: #"^[^=]*="#, with: "",
                        options: .regularExpression
                    )
                    return !afterEq.isEmpty
                }()

                // ── 生成清除后的行 ──
                if trimmed.contains("export ") {
                    // export KEY=value → export KEY=
                    let cleanLine = trimmed.replacingOccurrences(
                        of: #"^(export\s+[A-Za-z_][A-Za-z0-9_]*\s*=).*"#,
                        with: "$1",
                        options: .regularExpression
                    )
                    modifiedLines.append(cleanLine)
                } else if isYamlKey {
                    // YAML 格式 — 清空值
                    if hasInlineValue {
                        // api_key: value → api_key: ""（保留原始缩进）
                        let cleanLine = trimmed.replacingOccurrences(
                            of: #"^([a-zA-Z_][a-zA-Z0-9_]*\s*:\s*).*"#,
                            with: "$1\"\"",
                            options: .regularExpression
                        )
                        modifiedLines.append("\(String(leadingSpaces))\(cleanLine)")
                    } else {
                        // api_key:\n    value → api_key: ""（并标记跳过下一行）
                        let indent = String(leadingSpaces)
                        modifiedLines.append("\(indent)\(trimmed.replacingOccurrences(of: ":.*", with: ": \"\"", options: .regularExpression))")
                        // 检查下一行是否是缩进的值
                        if i + 1 < allLines.count {
                            let next = allLines[i + 1]
                            if next.hasPrefix(" ") && !next.trimmingCharacters(in: .whitespaces).isEmpty {
                                skipIndentedValue = true
                            }
                        }
                    }
                } else {
                    // KEY=value → KEY=
                    if hasInlineValue {
                        let cleanLine = trimmed.replacingOccurrences(
                            of: #"^([A-Za-z_][A-Za-z0-9_]*\s*=).*"#,
                            with: "$1",
                            options: .regularExpression
                        )
                        modifiedLines.append(cleanLine)
                    } else {
                        // 等号后面没值，但变量名本身匹配了 KEY 模式——保留原行
                        modifiedLines.append(line)
                    }
                }
                wipedCount += 1
            }

            let newContent = modifiedLines.joined(separator: "\n")
            try newContent.write(to: url, atomically: true, encoding: .utf8)

            return WipeResult(
                targetId: targetId,
                targetName: displayName,
                status: .success,
                message: "已清除 \(wipedCount) 个 Key",
                timestamp: Date()
            )

        } catch {
            return WipeResult(
                targetId: targetId,
                targetName: displayName,
                status: .failed,
                message: "写入失败: \(error.localizedDescription)",
                timestamp: Date()
            )
        }
    }

    // MARK: - 特殊处理：Shell 历史
    func wipeShellHistory(at path: String, targetId: UUID? = nil, backup: Bool = true) -> WipeResult? {
        let url = URL(fileURLWithPath: path)
        let fileName = url.lastPathComponent

        guard fileManager.fileExists(atPath: url.path) else { return nil }

        if backup {
            let dateStr = dateFormatter.string(from: Date())
            let backupDir = backupBaseURL.appendingPathComponent(dateStr)
            let dest = backupDir.appendingPathComponent(fileName)
            do {
                try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
                try fileManager.copyItem(at: url, to: dest)
            } catch {
                return WipeResult(
                    targetId: targetId,
                    targetName: fileName,
                    status: .failed,
                    message: "备份失败: \(error.localizedDescription)",
                    timestamp: Date()
                )
            }
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)

            // 过滤掉包含 API Key 的行
            let filteredLines = lines.filter { line in
                let upper = line.uppercased()
                return !upper.contains("API_KEY") &&
                       !upper.contains("APIKEY") &&
                       !upper.contains("OPENAI") &&
                       !upper.contains("ANTHROPIC") &&
                       !upper.contains("DEEPSEEK") &&
                       !upper.contains("GEMINI") &&
                       !upper.contains("SECRET")
            }

            let removed = lines.count - filteredLines.count
            let newContent = filteredLines.joined(separator: "\n")
            try newContent.write(to: url, atomically: true, encoding: .utf8)

            return WipeResult(
                targetId: targetId,
                targetName: fileName,
                status: .success,
                message: "已从 Shell 历史中移除 \(removed) 条敏感命令",
                timestamp: Date()
            )
        } catch {
            return WipeResult(
                targetId: targetId,
                targetName: fileName,
                status: .failed,
                message: "处理失败: \(error.localizedDescription)",
                timestamp: Date()
            )
        }
    }

    // MARK: - 批量执行
    func executeWipe(on targets: [WipeTarget], backup: Bool = true, progressHandler: (Double, String) -> Void) -> [WipeResult] {
        var results: [WipeResult] = []
        let total = Double(targets.count)
        let dateStr = dateFormatter.string(from: Date())
        let backupRoot = backupBaseURL.appendingPathComponent(dateStr)
        try? fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        // 保存本次操作的配置清单到备份目录
        let manifestURL = backupRoot.appendingPathComponent("_manifest.txt")
        let manifest = targets.enumerated().map { i, t in
            "\(i+1). \(t.name) → \(t.filePath)"
        }.joined(separator: "\n")
        try? manifest.write(to: manifestURL, atomically: true, encoding: .utf8)

        for (index, target) in targets.enumerated() {
            let progress = Double(index) / total
            progressHandler(progress, "正在处理: \(target.name)…")

            guard target.enabled else {
                results.append(WipeResult(
                    targetId: target.id,
                    targetName: target.name,
                    status: .skipped,
                    message: "已禁用，跳过",
                    timestamp: Date()
                ))
                continue
            }

            let path = target.expandedPath

            // 根据文件类型选择不同的处理方式
            if path.hasSuffix("_history") || path.hasSuffix(".zsh_history") || path.hasSuffix(".bash_history") {
                if let result = wipeShellHistory(at: path, targetId: target.id, backup: backup) {
                    results.append(result)
                } else {
                    results.append(WipeResult(
                        targetId: target.id,
                        targetName: target.name,
                        status: .skipped,
                        message: "文件不存在: \(path)",
                        timestamp: Date()
                    ))
                }
            } else if path.hasSuffix("history.jsonl") || path.hasSuffix(".hermes_history") {
                // JSONL 历史文件 — 直接清空
                let url = URL(fileURLWithPath: path)
                if fileManager.fileExists(atPath: path) {
                    // 备份
                    if backup {
                        let dest = backupRoot.appendingPathComponent(url.lastPathComponent)
                        try? fileManager.copyItem(at: url, to: dest)
                    }
                    // 清空
                    try? "".write(to: url, atomically: true, encoding: .utf8)
                    results.append(WipeResult(
                        targetId: target.id,
                        targetName: target.name,
                        status: .success,
                        message: "已清空历史文件",
                        timestamp: Date()
                    ))
                } else {
                    results.append(WipeResult(
                        targetId: target.id,
                        targetName: target.name,
                        status: .skipped,
                        message: "文件不存在",
                        timestamp: Date()
                    ))
                }
            } else {
                if let result = wipeFile(at: path, customPatterns: target.customPatterns, targetId: target.id, backup: backup) {
                    results.append(result)
                } else {
                    results.append(WipeResult(
                        targetId: target.id,
                        targetName: target.name,
                        status: .skipped,
                        message: "文件不存在: \(path)",
                        timestamp: Date()
                    ))
                }
            }
        }

        progressHandler(1.0, "清除完成！")
        return results
    }

    // MARK: - 自动扫描文件系统中的 API Key 文件
    /// 扫描 ~/ 下的 .env 和配置文件，返回发现的文件路径和推荐名称
    func scanForApiKeyFiles(progressHandler: (String) -> Void) -> [(path: String, name: String)] {
        var results: [(String, String)] = []
        let home = fileManager.homeDirectoryForCurrentUser
        let patterns = Self.defaultPatterns

        // 跳过的目录
        let skipDirs: Set<String> = [
            "Library", "Applications", "Desktop", "Downloads", "Documents",
            "Public", "Music", "Pictures", "Movies", ".Trash", ".git",
            "node_modules", ".cache", "Caches", ".rvm", ".nvm",
            ".oh-my-zsh", ".gem", ".cocoapods", ".m2",
            "venv", ".venv", "__pycache__", "Pods"
        ]

        // 要检查的文件扩展名
        let configExts: Set<String> = [".env", ".envrc", ".yaml", ".yml", ".json", ".toml", ".conf", ".cfg"]

        guard let enumerator = fileManager.enumerator(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var depthLimit = 4
        for case let url as URL in enumerator {
            guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else { continue }

            if resourceValues.isDirectory == true {
                // 跳过不需要的目录
                if skipDirs.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                // 深度限制
                let relativePath = url.path.replacingOccurrences(of: home.path, with: "")
                let depth = relativePath.components(separatedBy: "/").count
                if depth > depthLimit {
                    enumerator.skipDescendants()
                    continue
                }
                continue
            }

            guard resourceValues.isRegularFile == true else { continue }
            let ext = "." + url.pathExtension.lowercased()
            guard configExts.contains(ext) || url.lastPathComponent == ".env" else { continue }

            progressHandler("扫描: \(url.lastPathComponent)")

            // 只检查前 100 行
            guard let fileHandle = try? FileHandle(forReadingFrom: url) else { continue }
            let chunk = fileHandle.readData(ofLength: 10_240)
            fileHandle.closeFile()
            guard !chunk.isEmpty, let content = String(data: chunk, encoding: .utf8) else { continue }

            let lines = content.components(separatedBy: CharacterSet.newlines)
            var hasKey = false
            for line in lines {
                let t = line.trimmingCharacters(in: CharacterSet.whitespaces)
                if t.hasPrefix("#") || t.isEmpty { continue }
                for p in patterns {
                    if t.contains(p) {
                        hasKey = true
                        break
                    }
                }
                if hasKey { break }
            }

            if hasKey {
                let dirName = url.deletingLastPathComponent().lastPathComponent
                let fullPath = url.path
                let name = "\(dirName)/\(url.lastPathComponent)"
                // 去重
                if !results.contains(where: { $0.0 == fullPath }) {
                    results.append((fullPath, name))
                }
            }
        }
        return results
    }
}
