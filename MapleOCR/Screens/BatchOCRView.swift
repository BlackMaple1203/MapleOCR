//
//  BatchOCRView.swift
//  MapleOCR
//
//  批量识别主视图 —— 参照 Umi-OCR 批量OCR功能完整实现
//  功能：文件导入（拖拽/选取/文件夹递归）、批量 OCR 处理、
//       进度追踪（暂停/恢复/停止）、多格式输出（TXT/MD/CSV/JSONL）、
//       段落合并策略、结果展示与导出
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 批量 OCR 结果条目

struct OCRResultItem: Identifiable {
    let id = UUID()
    let imageName: String
    let imageURL: URL
    let text: String
    let confidence: Double
    let boxes: [ScreenshotOCRResult.TextBox]
    let time: String
    let duration: Double
    /// 状态码：100 = 成功，101 = 无文字，其他 = 错误
    let code: Int
}

// MARK: - 批量图片条目

struct BatchImageItem: Identifiable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    var duration: String = ""
    var status: BatchStatus = .waiting

    enum BatchStatus {
        case waiting, processing, success, failed, empty
        var label: String {
            switch self {
            case .waiting:    return "排队"
            case .processing: return "处理中"
            case .success:    return "✓"
            case .failed:     return "✗"
            case .empty:      return "└ 无文字"
            }
        }
        var color: Color {
            switch self {
            case .waiting:    return .secondary
            case .processing: return .blue
            case .success:    return .green
            case .failed:     return .red
            case .empty:      return .orange
            }
        }
    }
}

// MARK: - 任务控制状态

enum BatchMissionState {
    case idle       // 空闲
    case running    // 运行中
    case paused     // 已暂停
}

// MARK: - 输出文件格式

enum BatchOutputFormat: String, CaseIterable, Identifiable {
    case txt       = "标准文本"
    case txtPlain  = "纯文本"
    case md        = "Markdown"
    case csv       = "CSV"
    case jsonl     = "JSONL"

    var id: String { rawValue }
    var fileExtension: String {
        switch self {
        case .txt, .txtPlain: return "txt"
        case .md:    return "md"
        case .csv:   return "csv"
        case .jsonl: return "jsonl"
        }
    }
}

// MARK: - 保存目录模式

enum SaveDirMode: String, CaseIterable, Identifiable {
    case sourceDir  = "与图片同目录"
    case customDir  = "指定目录"
    var id: String { rawValue }
}

// MARK: - 批量 OCR 主视图

struct BatchOCRView: View {

    // ── 文件列表 ──
    @State private var images: [BatchImageItem] = []
    @State private var selectedID: UUID?
    @State private var isDraggingOver = false
    @State private var isHoveringDropZone = false

    // ── 任务状态 ──
    @State private var missionState: BatchMissionState = .idle
    @State private var processedCount = 0
    @State private var errorCount = 0
    @State private var startTime: Date?
    @State private var elapsedSeconds: Double = 0
    @State private var currentTaskID: UUID = UUID()  // 用于取消

    // ── 暂停控制 ──
    @State private var pauseContinuation: CheckedContinuation<Void, Never>?

    // ── 选项卡 ──
    @State private var selectedTab: BatchTab = .settings
    @State private var ocrResults: [OCRResultItem] = []

    // ── 设置 ──
    @State private var paragraphStrategy: ParagraphStrategy = .multiPara
    @State private var recurrence = false
    @State private var saveToFile = false
    @State private var saveDirMode: SaveDirMode = .sourceDir
    @State private var customSavePath: URL?
    @State private var outputFormats: Set<BatchOutputFormat> = [.txt]
    @State private var ignoreBlank = true
    @State private var fileNameFormat = "MapleOCR_%date"
    @State private var copyOnComplete = false

    // ── Toast ──
    @State private var toastMessage: String?
    @State private var toastIsSuccess = true

    // ── 引擎 ──
    private let engine = ScreenshotEngine.shared

    // ── 定时器 ──
    @State private var timer: Timer?

    enum BatchTab { case settings, results }

    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "bmp", "tiff", "tif", "gif", "webp", "heic"]

    private let supportedImageTypes: [UTType] = [.png, .jpeg, .tiff, .bmp, .heic, .gif]

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // ── 左侧：文件列表 ──
            leftPanel
                .frame(width: 300)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // ── 右侧：设置 & 记录 ──
            rightPanel
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if let msg = toastMessage {
                toastView(msg, isSuccess: toastIsSuccess)
                    .padding(16)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: toastMessage)
    }

    // MARK: - 左侧面板

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // 顶部：任务控制栏
            missionControlBar
            Divider()

            // 文件列表 / 空态
            if images.isEmpty {
                dropZone
            } else {
                fileListView
            }

            Divider()

            // 底部：添加/清空/开始按钮
            bottomBar
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDraggingOver) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - 任务控制栏

    private var missionControlBar: some View {
        HStack(spacing: 8) {
            switch missionState {
            case .idle:
                Button {
                    startOCR()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("开始任务")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(images.isEmpty)

            case .running:
                Button {
                    pauseOCR()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 10))
                        Text("暂停")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    stopOCR()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                        Text("停止")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.bordered)

            case .paused:
                Button {
                    resumeOCR()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("继续")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.borderedProminent)

                Button {
                    stopOCR()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                        Text("停止")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            // 进度信息
            if missionState != .idle {
                progressInfo
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 进度信息

    private var progressInfo: some View {
        HStack(spacing: 8) {
            // 进度数字
            Text("\(processedCount) / \(images.count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)

            // 已用时间
            Text(formatDuration(elapsedSeconds))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)

            // 预计剩余
            if processedCount > 0 {
                let avgTime = elapsedSeconds / Double(processedCount)
                let remaining = avgTime * Double(images.count - processedCount)
                Text("剩余 \(formatDuration(remaining))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            // 速度
            if elapsedSeconds > 0 {
                let speed = Double(processedCount) / elapsedSeconds
                Text(String(format: "%.1f张/s", speed))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            if missionState == .paused {
                Text("已暂停")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - 文件列表

    private var fileListView: some View {
        VStack(spacing: 0) {
            // 表头
            HStack(spacing: 0) {
                Text("文件名")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("用时")
                    .frame(width: 48, alignment: .trailing)
                Text("状态")
                    .frame(width: 56, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            Divider()

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(images) { item in
                        BatchImageRow(
                            item: item,
                            isSelected: selectedID == item.id
                        ) {
                            selectedID = item.id
                            // 点击文件时，在结果面板中找到对应结果
                            if let result = ocrResults.first(where: { $0.imageURL == item.url }) {
                                selectedTab = .results
                                _ = result // 滚动到对应结果由 UI 处理
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // 进度条
            if missionState != .idle {
                VStack(spacing: 4) {
                    ProgressView(value: Double(processedCount), total: Double(max(1, images.count)))
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 12)
                    HStack {
                        Text("已处理 \(processedCount) / \(images.count)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        if errorCount > 0 {
                            Text("失败 \(errorCount)")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - 底部按钮栏

    private var bottomBar: some View {
        HStack(spacing: 6) {
            Button {
                openFilePicker()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                    Text("添加")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.bordered)
            .disabled(missionState != .idle)

            Button {
                openFolderPicker()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 10))
                    Text("文件夹")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.bordered)
            .disabled(missionState != .idle)

            Spacer()

            Text("\(images.count) 个文件")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Button("清空") {
                clearAll()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.red)
            .disabled(missionState != .idle || images.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - 右侧面板

    private var rightPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                batchTabButton("设置", tag: .settings)
                batchTabButton("记录 \(ocrResults.isEmpty ? "" : "(\(ocrResults.count))")", tag: .results)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Divider()

            if selectedTab == .settings {
                batchSettingsPanel
            } else {
                batchResultsPanel
            }
        }
    }

    // MARK: - 拖拽空态

    private var dropZone: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: isDraggingOver ? "tray.and.arrow.down.fill" : "photo.stack")
                .font(.system(size: 40, weight: .light))
                .foregroundColor((isDraggingOver || isHoveringDropZone) ? .accentColor : .secondary)
                .animation(.easeInOut(duration: 0.18), value: isDraggingOver)
                .animation(.easeInOut(duration: 0.18), value: isHoveringDropZone)
            Text("拖入图片、文件夹，或点击添加")
                .font(.callout)
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                Button {
                    openFilePicker()
                } label: {
                    Label("选择文件", systemImage: "photo.on.rectangle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)

                Button {
                    openFolderPicker()
                } label: {
                    Label("选择文件夹", systemImage: "folder")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill((isDraggingOver || isHoveringDropZone) ? Color.accentColor.opacity(0.07) : Color.clear)
                .padding(12)
                .animation(.easeInOut(duration: 0.18), value: isHoveringDropZone)
                .animation(.easeInOut(duration: 0.18), value: isDraggingOver)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    (isDraggingOver || isHoveringDropZone) ? Color.accentColor : Color(NSColor.separatorColor),
                    style: StrokeStyle(lineWidth: (isDraggingOver || isHoveringDropZone) ? 2 : 1, dash: [6])
                )
                .padding(12)
                .animation(.easeInOut(duration: 0.18), value: isHoveringDropZone)
                .animation(.easeInOut(duration: 0.18), value: isDraggingOver)
        )
    }

    // MARK: - 设置面板

    private var batchSettingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // OCR 文本后处理
                batchSettingsSection("OCR 文本后处理") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("段落合并策略")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Picker("", selection: $paragraphStrategy) {
                            ForEach(ParagraphStrategy.allCases) { strategy in
                                Text(strategy.rawValue).tag(strategy)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                // 任务设置
                batchSettingsSection("任务设置") {
                    batchSettingsToggle("子文件夹递归", icon: "folder.badge.gearshape", isOn: $recurrence)
                    batchSettingsToggle("跳过空白/失败图片输出", icon: "text.badge.minus", isOn: $ignoreBlank)
                    batchSettingsToggle("完成后复制全部结果", icon: "doc.on.doc", isOn: $copyOnComplete)
                }

                // 输出设置
                batchSettingsSection("文件输出") {
                    batchSettingsToggle("保存结果到文件", icon: "arrow.down.doc", isOn: $saveToFile)

                    if saveToFile {
                        // 输出格式多选
                        VStack(alignment: .leading, spacing: 6) {
                            Text("输出格式（可多选）")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            FlowLayout(spacing: 6) {
                                ForEach(BatchOutputFormat.allCases) { fmt in
                                    Toggle(isOn: Binding(
                                        get: { outputFormats.contains(fmt) },
                                        set: { on in
                                            if on { outputFormats.insert(fmt) }
                                            else { outputFormats.remove(fmt) }
                                        }
                                    )) {
                                        Text(fmt.rawValue)
                                            .font(.system(size: 11))
                                    }
                                    .toggleStyle(.button)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                        // 保存目录
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("保存位置", selection: $saveDirMode) {
                                ForEach(SaveDirMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .font(.system(size: 12))

                            if saveDirMode == .customDir {
                                HStack {
                                    Text(customSavePath?.path ?? "未选择")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button("浏览…") {
                                        browseSavePath()
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.system(size: 11))
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                        // 文件名格式
                        HStack {
                            Text("文件名格式")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            TextField("", text: $fileNameFormat)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)

                        Text("可用变量：%dat4e（日期）、%name（文件名）")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - 记录面板

    private var batchResultsPanel: some View {
        VStack(spacing: 0) {
            if ocrResults.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(.secondary)
                    Text("暂无识别记录")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(ocrResults) { item in
                                BatchOCRResultRow(item: item)
                                    .id(item.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: ocrResults.count) { _ in
                        if let last = ocrResults.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

            Divider()

            // 底部状态栏
            HStack {
                Text("\(ocrResults.count) 条记录")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                if errorCount > 0 {
                    Text("· \(errorCount) 失败")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                Spacer()
                if !ocrResults.isEmpty {
                    Button("复制全部") { copyAllResults() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    Button("导出…") { exportResults() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    Button("清空") {
                        ocrResults.removeAll()
                        errorCount = 0
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 核心功能：批量 OCR

    /// 开始批量 OCR
    private func startOCR() {
        guard !images.isEmpty else { return }

        // 重置状态
        missionState = .running
        processedCount = 0
        errorCount = 0
        ocrResults.removeAll()
        startTime = Date()
        elapsedSeconds = 0

        for i in images.indices {
            images[i].status = .waiting
            images[i].duration = ""
        }

        // 自动切换到记录页
        selectedTab = .results

        // 启动计时器
        let timerInstance = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if let st = startTime, missionState == .running {
                elapsedSeconds = Date().timeIntervalSince(st)
            }
        }
        self.timer = timerInstance

        // 记录当前任务 ID（用于取消检测）
        let taskID = UUID()
        currentTaskID = taskID

        Task {
            // 输出写入器
            var outputWriters: [BatchOutputWriter] = []
            if saveToFile && !outputFormats.isEmpty {
                outputWriters = createOutputWriters()
                for writer in outputWriters { writer.writeHeader() }
            }

            for i in images.indices {
                // 检查取消
                guard currentTaskID == taskID else { break }

                // 检查暂停
                if missionState == .paused {
                    await withCheckedContinuation { cont in
                        pauseContinuation = cont
                    }
                    // 恢复后再检查取消
                    guard currentTaskID == taskID else { break }
                }

                guard missionState != .idle else { break }

                // 标记当前处理
                images[i].status = .processing
                let itemStart = Date()

                // 执行 OCR
                let result = await engine.performOCR(on: images[i].url)

                let duration = Date().timeIntervalSince(itemStart)
                images[i].duration = String(format: "%.1fs", duration)

                // 更新文件列表状态
                switch result.code {
                case 100:
                    images[i].status = .success
                case 101:
                    images[i].status = .empty
                default:
                    images[i].status = .failed
                    errorCount += 1
                }

                // 格式化文本
                let formattedText = engine.formatText(result.boxes, strategy: paragraphStrategy)

                // 添加到结果列表
                let resultItem = OCRResultItem(
                    imageName: images[i].name,
                    imageURL: images[i].url,
                    text: formattedText,
                    confidence: result.confidence,
                    boxes: result.boxes,
                    time: formatTime(result.timestamp),
                    duration: duration,
                    code: result.code
                )
                ocrResults.append(resultItem)

                // 写入输出文件
                if saveToFile {
                    let shouldWrite = result.code == 100 || !ignoreBlank
                    if shouldWrite {
                        for writer in outputWriters {
                            writer.writeResult(
                                imageName: images[i].name,
                                text: formattedText,
                                confidence: result.confidence,
                                code: result.code
                            )
                        }
                    }
                }

                processedCount = i + 1
            }

            // 完成输出文件
            if saveToFile {
                for writer in outputWriters { writer.finalize() }
            }

            // 完成后操作
            timer?.invalidate()
            timer = nil
            if let st = startTime {
                elapsedSeconds = Date().timeIntervalSince(st)
            }

            let wasRunning = missionState != .idle
            missionState = .idle

            if wasRunning {
                // 复制结果
                if copyOnComplete {
                    copyAllResults()
                }

                let totalTime = formatDuration(elapsedSeconds)
                showToast("批量识别完成 —— \(processedCount) 张，耗时 \(totalTime)\(errorCount > 0 ? "，\(errorCount) 张失败" : "")", isSuccess: errorCount == 0)
            }
        }
    }

    /// 暂停
    private func pauseOCR() {
        missionState = .paused
    }

    /// 恢复
    private func resumeOCR() {
        missionState = .running
        // 恢复被挂起的 continuation
        if let cont = pauseContinuation {
            pauseContinuation = nil
            cont.resume()
        }
    }

    /// 停止
    private func stopOCR() {
        currentTaskID = UUID() // 使当前任务失效
        missionState = .idle
        timer?.invalidate()
        timer = nil

        // 恢复挂起的 continuation（让循环退出）
        if let cont = pauseContinuation {
            pauseContinuation = nil
            cont.resume()
        }

        showToast("任务已停止", isSuccess: false)
    }

    // MARK: - 文件操作

    /// 打开图片文件选取
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = supportedImageTypes
        panel.message = "选择需要识别的图片"
        if panel.runModal() == .OK {
            addURLs(panel.urls)
        }
    }

    /// 打开文件夹选取
    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "选择包含图片的文件夹"
        if panel.runModal() == .OK {
            var allImages: [URL] = []
            for url in panel.urls {
                allImages.append(contentsOf: collectImages(from: url, recursive: recurrence))
            }
            addURLs(allImages)
            if allImages.isEmpty {
                showToast("所选文件夹中未发现图片", isSuccess: false)
            } else {
                showToast("已添加 \(allImages.count) 张图片", isSuccess: true)
            }
        }
    }

    /// 从文件夹收集图片文件
    private func collectImages(from dirURL: URL, recursive: Bool) -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []

        guard let enumerator = fm.enumerator(
            at: dirURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: recursive ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if Self.imageExts.contains(ext) {
                results.append(fileURL)
            }
        }

        return results.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// 添加 URL（去重）
    private func addURLs(_ urls: [URL]) {
        let existing = Set(images.map(\.url))
        var added = 0
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    // 文件夹：递归收集
                    let dirImages = collectImages(from: url, recursive: recurrence)
                    for imgURL in dirImages where !existing.contains(imgURL) {
                        images.append(BatchImageItem(url: imgURL))
                        added += 1
                    }
                } else if Self.imageExts.contains(url.pathExtension.lowercased()), !existing.contains(url) {
                    images.append(BatchImageItem(url: url))
                    added += 1
                }
            }
        }
        if added > 0 && urls.count > 1 {
            showToast("已添加 \(added) 张图片", isSuccess: true)
        }
    }

    private func clearAll() {
        images.removeAll()
        ocrResults.removeAll()
        processedCount = 0
        errorCount = 0
        elapsedSeconds = 0
        startTime = nil
    }

    /// 处理拖入
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            // 文件 URL
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let urlData = data as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil)
                else { return }
                Task { @MainActor in addURLs([url]) }
            }
        }
    }

    // MARK: - 输出写入

    /// 创建输出写入器
    private func createOutputWriters() -> [BatchOutputWriter] {
        let dateStr = {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd_HHmmss"
            return f.string(from: Date())
        }()
        let baseName = fileNameFormat
            .replacingOccurrences(of: "%date", with: dateStr)
            .replacingOccurrences(of: "%name", with: "batch")

        // 确定输出目录
        let outputDir: URL
        if saveDirMode == .customDir, let custom = customSavePath {
            outputDir = custom
        } else if let firstImage = images.first {
            outputDir = firstImage.url.deletingLastPathComponent()
        } else {
            outputDir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        }

        return outputFormats.map { fmt in
            let fileURL = outputDir.appendingPathComponent("\(baseName).\(fmt.fileExtension)")
            return BatchOutputWriter(format: fmt, fileURL: fileURL)
        }
    }

    /// 浏览保存路径
    private func browseSavePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择输出目录"
        if panel.runModal() == .OK, let url = panel.url {
            customSavePath = url
        }
    }

    // MARK: - 复制 & 导出

    /// 复制全部结果
    private func copyAllResults() {
        let allText = ocrResults
            .filter { $0.code == 100 }
            .map(\.text)
            .joined(separator: "\n\n---\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allText, forType: .string)
        showToast("已复制 \(ocrResults.filter { $0.code == 100 }.count) 条结果", isSuccess: true)
    }

    /// 导出结果到文件
    private func exportResults() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "MapleOCR_批量结果_\(formatDateStamp()).txt"
        panel.message = "导出识别结果"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var content = ""
        for item in ocrResults where item.code == 100 {
            content += "≦ \(item.imageName) ≧\n"
            content += item.text
            content += "\n\n"
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            showToast("已导出到 \(url.lastPathComponent)", isSuccess: true)
        } catch {
            showToast("导出失败：\(error.localizedDescription)", isSuccess: false)
        }
    }

    // MARK: - Toast

    private func showToast(_ message: String, isSuccess: Bool) {
        toastMessage = message
        toastIsSuccess = isSuccess
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { toastMessage = nil }
        }
    }

    // MARK: - 辅助组件

    private func batchTabButton(_ title: String, tag: BatchTab) -> some View {
        Button(action: { selectedTab = tag }) {
            Text(title)
                .font(.system(size: 12, weight: selectedTab == tag ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    selectedTab == tag
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundColor(selectedTab == tag ? .accentColor : .primary)
    }

    private func batchSettingsSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 4)
            content()
        }
    }

    private func batchSettingsToggle(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13))
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func toastView(_ message: String, isSuccess: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isSuccess ? .green : .orange)
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundColor(.primary)
                .lineLimit(3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        )
    }

    // MARK: - 格式化工具

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    private func formatDateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}

// MARK: - 批量输出文件写入器

final class BatchOutputWriter {
    let format: BatchOutputFormat
    let fileURL: URL
    private var content = ""

    init(format: BatchOutputFormat, fileURL: URL) {
        self.format = format
        self.fileURL = fileURL
    }

    func writeHeader() {
        switch format {
        case .csv:
            content = "文件名,识别文本,置信度,状态码\n"
        case .jsonl:
            content = ""
        case .md:
            content = "# MapleOCR 批量识别结果\n\n"
            content += "> 生成时间：\(ISO8601DateFormatter().string(from: Date()))\n\n"
        case .txt:
            content = ""
        case .txtPlain:
            content = ""
        }
    }

    func writeResult(imageName: String, text: String, confidence: Double, code: Int) {
        switch format {
        case .txt:
            content += "≦ \(imageName) ≧\n"
            content += text.isEmpty ? "（无文字）" : text
            content += "\n\n"

        case .txtPlain:
            if !text.isEmpty {
                content += text + "\n"
            }

        case .md:
            content += "## \(imageName)\n\n"
            if text.isEmpty {
                content += "*（无文字）*\n\n"
            } else {
                content += text + "\n\n"
            }
            content += "---\n\n"

        case .csv:
            // 转义 CSV 字段
            let escaped = text
                .replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
            content += "\"\(imageName)\",\"\(escaped)\",\(String(format: "%.2f", confidence)),\(code)\n"

        case .jsonl:
            let obj: [String: Any] = [
                "file": imageName,
                "text": text,
                "confidence": confidence,
                "code": code
            ]
            if let data = try? JSONSerialization.data(withJSONObject: obj),
               let line = String(data: data, encoding: .utf8) {
                content += line + "\n"
            }
        }
    }

    func finalize() {
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - FlowLayout（多选标签布局）

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - 文件列表行

private struct BatchImageRow: View {
    let item: BatchImageItem
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // 状态图标
            Group {
                switch item.status {
                case .processing:
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 13, height: 13)
                default:
                    Image(systemName: statusIcon)
                        .font(.system(size: 11))
                        .foregroundColor(item.status.color)
                }
            }
            .frame(width: 22)
            .padding(.leading, 8)

            Text(item.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)

            if !item.duration.isEmpty {
                Text(item.duration)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }

            Text(item.status == .waiting ? "" : item.status.label)
                .font(.system(size: 11))
                .foregroundColor(item.status.color)
                .frame(width: 42, alignment: .trailing)
                .padding(.trailing, 8)
        }
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.13)
                        : (isHovered ? Color(NSColor.labelColor).opacity(0.05) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
        .padding(.horizontal, 6)
    }

    private var statusIcon: String {
        switch item.status {
        case .waiting:    return "clock"
        case .processing: return "arrow.triangle.2.circlepath"
        case .success:    return "checkmark.circle.fill"
        case .failed:     return "xmark.circle.fill"
        case .empty:      return "minus.circle"
        }
    }
}

#Preview {
    BatchOCRView()
        .frame(width: 900, height: 560)
}

// MARK: - 批量 OCR 结果行

struct BatchOCRResultRow: View {
    let item: OCRResultItem
    @State private var isExpanded = false
    @State private var isHovered = false

    private var statusIcon: String {
        switch item.code {
        case 100: return "doc.text.image"
        case 101: return "text.badge.minus"
        default:  return "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch item.code {
        case 100: return .secondary
        case 101: return .orange
        default:  return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                // 展开/折叠
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)

                Image(systemName: statusIcon)
                    .font(.system(size: 13))
                    .foregroundColor(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    // 文件名
                    Text(item.imageName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    // 文本内容
                    Text(item.text.isEmpty ? "（无文字）" : item.text)
                        .font(.system(size: 12))
                        .lineLimit(isExpanded ? nil : 2)
                        .foregroundColor(item.text.isEmpty ? .secondary : .primary)

                    // 元信息
                    HStack(spacing: 6) {
                        Text(item.time)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("\(item.duration, specifier: "%.2f")s")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        if item.confidence > 0 {
                            Text("\(Int(item.confidence * 100))%")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // 悬停操作
                if isHovered {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("复制文本")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovered ? Color(NSColor.labelColor).opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { isExpanded.toggle() }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
    }
}
