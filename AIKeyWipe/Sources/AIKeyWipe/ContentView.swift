import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TargetStore
    @State private var selectedIds: Set<WipeTarget.ID> = []

    /// 从 selectedIds 实时查询 store 中的目标（避免值副本不同步）
    private var selectedTargets: [WipeTarget] {
        store.targets.filter { selectedIds.contains($0.id) }
    }

    @State private var isWiping = false
    @State private var wipeProgress: Double = 0
    @State private var wipeResults: [WipeResult] = []
    @State private var progressMessage = ""
    @State private var showingConfirmAlert = false
    @State private var autoRemoveAfterWipe = true
    @State private var enableBackup = false
    @State private var isScanning = false

    private let wipeService = WipeService()

    var body: some View {
        HSplitView {
            // 左侧：目标列表
            if store.targets.isEmpty {
                // 空列表 → 居中显示扫描按钮
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "key.icloud")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("未发现 API Key 文件")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("点击下方按钮扫描 ~/ 目录下的配置文件")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button(action: { startScan() }) {
                        HStack {
                            if isScanning {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                            Text(isScanning ? "扫描中…" : "扫描文件")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: 200)
                        .padding(.vertical, 10)
                        .background(isScanning ? Color.gray.opacity(0.3) : Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isScanning)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    listHeader
                    targetList
                    listFooter
                }
                .frame(minWidth: 280, maxWidth: 400)
            }

            // 右侧：详情 + 结果
            VStack(spacing: 0) {
                if isScanning && selectedTargets.isEmpty && wipeResults.isEmpty {
                    scanAnimationView
                } else if selectedTargets.count == 1, let target = selectedTargets.first {
                    targetDetailView(target)
                } else if selectedTargets.count > 1 {
                    multiSelectInfo
                } else if !wipeResults.isEmpty {
                    resultsView
                } else {
                    emptyState
                }
            }
            .frame(minWidth: 300)
        }
        .alert("确认清除？", isPresented: $showingConfirmAlert) {
            Button("取消", role: .cancel) { }
            Button("确认清除", role: .destructive) { startWipe() }
        } message: {
            let count = selectedTargets.count
            let names = selectedTargets.prefix(3).map(\.name).joined(separator: "、")
            Text("将清除 \(count) 个选中的文件中的所有 API Key。\n\(names)\(count > 3 ? "等" : "")\n已备份的文件可随时恢复。")
        }
    }

    // MARK: - 左侧：列表头部
    private var listHeader: some View {
        HStack {
            Image(systemName: "key.icloud")
                .foregroundColor(.accentColor)
            Text("清除目标")
                .font(.headline)
            Spacer()
            Text("\(store.targets.filter(\.enabled).count)/\(store.targets.count)")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - 左侧：目标列表
    private var targetList: some View {
        List(selection: $selectedIds) {
            ForEach(store.targets) { target in
                TargetRow(target: target, store: store)
                    .tag(target.id)
                    .contextMenu {
                        Button("编辑") { selectedIds = [target.id] }
                        Divider()
                        Button("在访达中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target.expandedPath)])
                        }
                        Button("启用/禁用") { store.toggle(target) }
                        Button("删除", role: .destructive) { store.remove(target) }
                    }
            }
            .onDelete { indexSet in
                for i in indexSet {
                    store.remove(store.targets[i])
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - 左侧：列表底部
    private var listFooter: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: { pickFileAndAdd() }) {
                    Label("自定义", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("从 Finder 选择文件添加到清除列表")

                Button(action: { startScan() }) {
                    Label("扫描", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("自动扫描 ~/ 下含 API Key 的文件")
                .disabled(isScanning)

                Spacer()
            }
            .padding(.horizontal)

            // 执行按钮
            let selectionCount = selectedTargets.count
            Button(action: { showingConfirmAlert = true }) {
                HStack {
                    if isWiping {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "trash.fill")
                    }
                    Text(isWiping ? "清除中…" : "清除所选 (\(selectionCount))")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isWiping || selectionCount == 0
                    ? Color.gray.opacity(0.3)
                    : Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.borderless)
            .disabled(isWiping || selectionCount == 0)
            .padding(.horizontal)
            .padding(.bottom, 8)

            // 自动移除开关
            Toggle(isOn: $autoRemoveAfterWipe) {
                HStack(spacing: 4) {
                    Image(systemName: "trash.slash.fill")
                        .font(.caption)
                    Text("清除成功后自动从列表移除")
                        .font(.caption)
                }
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal)
            .padding(.bottom, 2)

            // 备份开关
            Toggle(isOn: $enableBackup) {
                HStack(spacing: 4) {
                    Image(systemName: "archivebox")
                        .font(.caption)
                    Text("清除前备份到 ~/AI-Key-Wipe/backups/")
                        .font(.caption)
                }
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal)
            .padding(.bottom, 4)

            if isWiping {
                ProgressView(value: wipeProgress) {
                    Text(progressMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 右侧：目标详情
    private func targetDetailView(_ target: WipeTarget) -> some View {
        Form {
            Section("基本信息") {
                HStack {
                    Text("名称")
                    Spacer()
                    TextField("名称", text: Binding(
                        get: { target.name },
                        set: {
                            var t = target
                            t.name = $0
                            store.update(t)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                }

                HStack {
                    Text("文件路径")
                    Spacer()
                    HStack(spacing: 4) {
                        Text(target.filePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.custom("SF Mono", size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: 160, alignment: .trailing)

                        Button("选择…") {
                            pickFileForTarget(target)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                HStack {
                    Text("实际路径")
                    Spacer()
                    Text(target.expandedPath)
                        .font(.custom("SF Mono", size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Spacer()
                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target.expandedPath)])
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("在访达中显示")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Toggle("启用", isOn: Binding(
                    get: { target.enabled },
                    set: {
                        var t = target
                        t.enabled = $0
                        store.update(t)
                    }
                ))
            }

            Section("自定义匹配模式") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("一行一个关键词，匹配到即清除。默认匹配 KEY= / TOKEN= / SECRET= / PASSWORD= 等")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: Binding(
                        get: { target.customPatterns.joined(separator: "\n") },
                        set: {
                            var t = target
                            t.customPatterns = $0
                                .components(separatedBy: .newlines)
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                            store.update(t)
                        }
                    ))
                    .font(.custom("SF Mono", size: 12))
                    .frame(minHeight: 80, maxHeight: 120)
                    .border(Color(NSColor.gridColor), width: 0.5)
                    .cornerRadius(4)
                }
            }

            Section("预扫描") {
                Button("扫描此文件") {
                    scanFile(target)
                }
                .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - 右侧：空状态
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.icloud")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("选择一个或多个清除目标")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("⌘+点击 多选，⇧+点击 连选")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 右侧：扫描动画
    private var scanAnimationView: some View {
        ScanAnimation()
    }

    // MARK: - 右侧：多选信息
    private var multiSelectInfo: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.badge.fill")
                .font(.system(size: 42))
                .foregroundColor(.accentColor)

            Text("已选中 \(selectedTargets.count) 个目标")
                .font(.title2)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(selectedTargets).sorted { $0.name < $1.name }) { target in
                    HStack(spacing: 8) {
                        Image(systemName: target.enabled ? "circle.fill" : "circle")
                            .font(.system(size: 6))
                            .foregroundColor(target.enabled ? .green : .gray)
                        Text(target.name)
                        Text(target.filePath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Text("点击底部「执行清除」将只清除以上选中的目标")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 右侧：结果视图
    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("清除结果")
                    .font(.headline)
                    .padding(.bottom, 4)

                ForEach(wipeResults) { result in
                    HStack(alignment: .top, spacing: 8) {
                        switch result.status {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        case .skipped:
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.orange)
                        case .failed:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        case .backedUp:
                            Image(systemName: "archivebox.fill")
                                .foregroundColor(.blue)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.targetName)
                                .fontWeight(.medium)
                            Text(result.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !wipeResults.isEmpty {
                    Divider().padding(.vertical, 4)
                    HStack {
                        let success = wipeResults.filter { r in
                            if case .success = r.status { return true }
                            return false
                        }.count
                        Text("成功: \(success) / 总计: \(wipeResults.count)")

                        Spacer()

                        Button("清除结果") {
                            wipeResults = []
                        }
                        .buttonStyle(.bordered)
                    }
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
            }
            .padding()
        }
    }

    // MARK: - 功能方法
    private func scanFile(_ target: WipeTarget) {
        let results = wipeService.scanFile(at: target.expandedPath, customPatterns: target.customPatterns)
        if results.isEmpty {
            wipeResults.append(WipeResult(
                targetId: target.id,
                targetName: target.name,
                status: .skipped,
                message: "未发现 API Key",
                timestamp: Date()
            ))
        } else {
            for r in results {
                wipeResults.append(WipeResult(
                    targetId: target.id,
                    targetName: target.name,
                    status: .backedUp,
                    message: "发现: \(r)",
                    timestamp: Date()
                ))
            }
        }
    }

    private func startWipe() {
        isWiping = true
        wipeProgress = 0
        wipeResults = []

        let targetsToWipe = Array(selectedTargets).filter(\.enabled)

        DispatchQueue.global(qos: .userInitiated).async {
            let results = wipeService.executeWipe(on: targetsToWipe, backup: enableBackup) { progress, message in
                DispatchQueue.main.async {
                    self.wipeProgress = progress
                    self.progressMessage = message
                }
            }

            DispatchQueue.main.async {
                self.wipeResults = results
                self.isWiping = false
                self.progressMessage = ""

                // 自动移除清除成功的目标
                if self.autoRemoveAfterWipe {
                    let successIds = results.compactMap { r in
                        if case .success = r.status { return r.targetId }
                        return nil
                    }
                    for id in successIds {
                        if let target = self.store.targets.first(where: { $0.id == id }) {
                            self.store.remove(target)
                        }
                    }
                    // 同步清除选中 ID
                    self.selectedIds.subtract(Set(successIds))
                }
            }
        }
    }

    // MARK: - 自动扫描磁盘上的 API Key 文件
    private func startScan() {
        isScanning = true
        wipeResults = []

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let found = wipeService.scanForApiKeyFiles { msg in
                DispatchQueue.main.async {
                    self.progressMessage = msg
                }
            }

            DispatchQueue.main.async {
                var added = 0
                var skipped = 0
                for (path, name) in found {
                    if store.targets.contains(where: { $0.expandedPath == path }) {
                        skipped += 1
                    } else {
                        store.add(WipeTarget(name: name, filePath: path))
                        added += 1
                    }
                }
                wipeResults.append(WipeResult(
                    targetId: nil,
                    targetName: "自动扫描",
                    status: .backedUp,
                    message: "发现 \(found.count) 个文件，新增 \(added) 个，\(skipped) 个已存在",
                    timestamp: Date()
                ))
                isScanning = false
                progressMessage = ""
            }
        }
    }

    // MARK: - 文件选择器 (NSOpenPanel)
    /// 为已有目标重新选择文件路径
    private func pickFileForTarget(_ target: WipeTarget) {
        let panel = NSOpenPanel()
        panel.title = "选择要清除的文件或目录"
        panel.message = "选择一个包含 API Key 的文件或目录进行清除"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true

        if FileManager.default.fileExists(atPath: target.expandedPath) {
            panel.directoryURL = URL(fileURLWithPath: target.expandedPath)
                .deletingLastPathComponent()
        }

        panel.begin { response in
            if response == .OK, let url = panel.url {
                let path = url.path
                let name = url.lastPathComponent
                var t = target
                t.filePath = path
                t.name = "\(url.deletingLastPathComponent().lastPathComponent)/\(name)"
                store.update(t)
            }
        }
    }

    /// 从 Finder 选择文件并添加为新目标
    private func pickFileAndAdd() {
        let panel = NSOpenPanel()
        panel.title = "选择要清除的文件或目录"
        panel.message = "选择后会自动添加到清除列表"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                let path = url.path
                let name = url.lastPathComponent
                let dirName = url.deletingLastPathComponent().lastPathComponent
                let newTarget = WipeTarget(
                    name: "\(dirName)/\(name)",
                    filePath: path
                )
                selectedIds = [newTarget.id]
                store.add(newTarget)
            }
        }
    }
}

// MARK: - 扫描动画组件
private struct ScanAnimation: View {
    @State private var angle: Double = 0
    let timer = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                // 文件夹图标（中心）
                Image(systemName: "folder.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.accentColor)

                // 放大镜（椭圆轨道）
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundColor(.orange)
                    .offset(
                        x: cos(angle) * 44,
                        y: sin(angle) * 22
                    )
            }
            .frame(width: 120, height: 80)

            Text("正在扫描文件…")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("扫描 ~/ 目录下的配置文件\n自动发现含 API Key 的文件")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { _ in
            angle += 0.063  // 约 100 步/圈，~2 秒一圈
            if angle > .pi * 2 { angle -= .pi * 2 }
        }
    }
}

// MARK: - 列表行组件
struct TargetRow: View {
    let target: WipeTarget
    let store: TargetStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: target.enabled ? "circle.fill" : "circle")
                .foregroundColor(target.enabled ? .green : .gray)
                .font(.system(size: 8))
                .onTapGesture { store.toggle(target) }

            VStack(alignment: .leading, spacing: 2) {
                Text(target.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(target.filePath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 扫描结果标记
extension WipeResult.WipeStatus {
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .backedUp: return "archivebox.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return .green
        case .skipped: return .orange
        case .failed: return .red
        case .backedUp: return .blue
        }
    }
}
