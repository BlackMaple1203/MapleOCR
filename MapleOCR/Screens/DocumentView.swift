import SwiftUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - 内容提取模式
enum ExtractionMode: String, CaseIterable, Identifiable {
    case mixed      = "混合 OCR / 原文本"
    case fullPage   = "整页强制 OCR"
    case imageOnly  = "仅 OCR 图片"
    case textOnly   = "仅拷贝原有文本"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .mixed:     return "doc.text.image"
        case .fullPage:  return "doc.viewfinder"
        case .imageOnly: return "photo.on.rectangle.angled"
        case .textOnly:  return "doc.plaintext"
        }
    }
}



// MARK: - 任务状态
enum TaskState {
    case stop, running, paused
}

// MARK: - 文档处理状态
enum DocState {
    case idle, queued, processing(Int, Int), done, failed(String)

    var label: String {
        switch self {
        case .idle:                return ""
        case .queued:              return "排队"
        case .processing(let d, let t): return "\(d)/\(t)"
        case .done:                return "√"
        case .failed(let msg):     return "× \(msg)"
        }
    }
    var color: Color {
        switch self {
        case .idle, .queued:      return .secondary
        case .processing:         return .accentColor
        case .done:               return .green
        case .failed:             return .red
        }
    }
}

// MARK: - 文档条目模型
struct DocumentItem: Identifiable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    var ext: String { url.pathExtension.lowercased() }
    var isPDF: Bool { ext == "pdf" || ext == "xps" || ext == "epub" || ext == "mobi" }

    // 文档元信息（PDF 专属）
    var pageCount: Int = 1
    var rangeStart: Int = 1
    var rangeEnd: Int = 1
    var isEncrypted: Bool = false
    var password: String = ""

    // 任务状态
    var state: DocState = .idle

    var icon: String {
        switch ext {
        case "pdf":            return "doc.richtext"
        case "xps":            return "doc.richtext.fill"
        case "epub", "mobi":   return "book"
        case "png", "jpg", "jpeg", "tiff", "bmp", "heic":
                               return "photo"
        case "docx", "doc":   return "doc.text"
        default:               return "doc"
        }
    }

    var pagesLabel: String {
        if !isPDF { return "" }
        if rangeStart == 1 && rangeEnd == pageCount {
            return "\(pageCount)页"
        }
        return "p\(rangeStart)–\(rangeEnd)/\(pageCount)"
    }
}

// MARK: - 输出文件类型
struct OutputFileTypes {
    var pdfLayered    = true   // layered.pdf 双层可搜索文档
    var pdfOneLayer   = false  // text.pdf    单层纯文本文档
    var txt           = false  // txt 标准格式
    var txtPlain      = false  // p.txt 纯文字格式
    var csv           = false  // csv 表格（Excel）
    var jsonl         = false  // jsonl 原始信息
}

// MARK: - 主视图
struct DocumentView: View {
    @State private var documents: [DocumentItem] = []
    @State private var selectedID: UUID?
    @State private var isDraggingOver: Bool = false
    @State private var isHoveringDropZone: Bool = false

    // 任务控制
    @State private var taskState: TaskState = .stop
    @State private var processedPages: Int = 0
    @State private var totalPages: Int = 0

    // 右侧面板 Tab（0=设置, 1=记录）
    @State private var rightTab: Int = 0
    /// 每页识别结果行，用数组替代字符串追加，保证 O(1) append、避免 O(n²) 复制
    @State private var resultLines: [String] = []
    /// 预览时最多展示的最近页数（防止超长 Text 视图布局卡顿）
    private let previewPageLimit = 20

    // ── 提取 & 保存设置 ──────────────────────────
    @State private var extractionMode: ExtractionMode = .mixed
    /// 用户通过 NSOpenPanel 选定的输出目录（security-scoped URL，可直接 startAccessing）
    @State private var specifiedDirURL: URL? = nil
    @State private var fileNameFormat: String = "[OCR]_%name%range_%date"
    @State private var outputTypes: OutputFileTypes = OutputFileTypes()
    @State private var ignoreBlankPages: Bool = true
    @State private var recursiveSubfolders: Bool = false

    // ── 后台任务 ────────────────────────────────────
    /// 使用简单标志控制取消：每次启动自增版本号，任务内检查版本号是否一致
    @State private var taskVersion: Int = 0

    // ── 时间统计 ─────────────────────────────────────
    @State private var taskStartTime: Date? = nil

    // ── Toast 通知 ──────────────────────────────────────────
    @StateObject private var toastManager = ToastManager()

    // ── 页范围 & 密码弹窗 ──────────────────────────
    @State private var showPageRangeSheet: Bool = false
    @State private var pageRangeTarget: UUID?

    // 支持的文件类型
    private let supportedTypes: [UTType] = [
        .pdf, .png, .jpeg, .tiff, .bmp, .heic,
        UTType(filenameExtension: "xps") ?? .data,
        UTType(filenameExtension: "epub") ?? .data,
        UTType(filenameExtension: "mobi") ?? .data,
    ]

    var body: some View {
        HStack(spacing: 0) {

            // ── 左侧：文档列表 ──────────────────────────────
            leftPanel
                .frame(width: 280)
                .background(Color(NSColor.windowBackgroundColor))
                .overlay(
                    Rectangle()
                        .frame(width: 1)
                        .foregroundColor(Color(NSColor.separatorColor)),
                    alignment: .trailing
                )
                .onDrop(
                    of: [UTType.fileURL.identifier].compactMap { UTType($0) },
                    isTargeted: $isDraggingOver
                ) { providers in handleDrop(providers: providers) }

            // ── 右侧：控制 + 标签面板 ──────────────────────
            VStack(spacing: 0) {
                taskControlBar
                Divider()
                rightTabPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { ToastOverlay() }
        .environmentObject(toastManager)
        .sheet(isPresented: $showPageRangeSheet) {
            if let id = pageRangeTarget,
               let idx = documents.firstIndex(where: { $0.id == id }) {
                PageRangeSheet(doc: $documents[idx]) {
                    showPageRangeSheet = false
                }
            }
        }
    }

    // MARK: - 左侧面板
    private var leftPanel: some View {
        VStack(spacing: 0) {
            Text("文档列表")
                .font(.headline)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            // 文档列表 / 空态
            if documents.isEmpty { dropZone } 
            else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(documents) { doc in
                            DocumentRow(
                                doc: doc,
                                isSelected: selectedID == doc.id,
                                isLocked: taskState != .stop
                            ) {
                                selectedID = doc.id
                                if doc.isPDF {
                                    pageRangeTarget = doc.id
                                    showPageRangeSheet = true
                                }
                            } onDelete: {
                                remove(doc)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                }

                Divider()

                // 底部操作栏
                HStack(spacing: 8) {
                    Button("添加文档") { openFilePicker() }
                        .buttonStyle(.bordered)
                        .disabled(taskState != .stop)
                    Spacer()
                    Button("清空") {
                        clearAll()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .disabled(taskState != .stop)
                }
                .padding(10)
            }
        }
    }

    // MARK: - 拖拽空态
    private var dropZone: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: isDraggingOver ? "tray.and.arrow.down.fill" : "arrow.down.doc")
                .font(.system(size: 38, weight: .light))
                .foregroundColor((isDraggingOver || isHoveringDropZone) ? .accentColor : .secondary)
                .animation(.easeInOut(duration: 0.18), value: isDraggingOver)
                .animation(.easeInOut(duration: 0.18), value: isHoveringDropZone)
            Text("拖入或上传文档")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("支持 PDF · XPS · EPUB · MOBI")
                .font(.caption)
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
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
        .contentShape(Rectangle())
        .onTapGesture { openFilePicker() }
        .onHover { inside in
            isHoveringDropZone = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
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

    // MARK: - 任务控制栏
    private var taskControlBar: some View {
        HStack(spacing: 10) {
            // 当前任务进度
            if taskState != .stop {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(taskState == .paused ? "已暂停" : "识别中…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ProgressView(value: Double(processedPages),
                                     total: max(Double(totalPages), 1))
                            .progressViewStyle(.linear)
                            .frame(width: 140)
                        HStack(spacing: 4) {
                            Text("\(processedPages) / \(totalPages) 页")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            if let start = taskStartTime, taskState == .running {
                                let elapsed = Date().timeIntervalSince(start)
                                Text("· \(formatDuration(elapsed))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if processedPages > 0 {
                                    let remaining = elapsed / Double(processedPages)
                                        * Double(totalPages - processedPages)
                                    Text("· 剩余 ~\(formatDuration(remaining))")
                                        .font(.caption2)
                                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                                }
                            }
                        }
                    }
                    .padding(.leading, 4)
                }
            } else {
                Text(documents.isEmpty
                     ? "尚未添加文档"
                     : "\(documents.count) 个文档，共 \(documents.reduce(0) { $0 + ($1.rangeEnd - $1.rangeStart + 1) }) 页")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 控制按钮组
            switch taskState {
            case .stop:
                Button {
                    startTask()
                } label: {
                    Label("开始任务", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(documents.isEmpty)

            case .running:
                Button {
                    pauseTask()
                } label: {
                    Label("暂停", systemImage: "pause.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)

                Button {
                    stopTask()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)

            case .paused:
                Button {
                    resumeTask()
                } label: {
                    Label("继续", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)

                Button {
                    stopTask()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - 右侧标签面板
    private var rightTabPanel: some View {
        VStack(spacing: 0) {
            // 标签切换
            HStack(spacing: 0) {
                ForEach(["设置", "记录"].indices, id: \.self) { i in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { rightTab = i }
                    } label: {
                        Text(["设置", "记录"][i])
                            .font(.system(size: 12, weight: rightTab == i ? .semibold : .regular))
                            .foregroundColor(rightTab == i ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                rightTab == i
                                    ? Color(NSColor.controlBackgroundColor)
                                    : Color.clear
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(Color(NSColor.separatorColor)),
                alignment: .bottom
            )

            if rightTab == 0 {
                settingsPanel
            } else {
                resultsPanel
            }
        }
    }

    // MARK: - 设置面板
    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── 内容提取模式 ───────────────────────────
                SettingSection(title: "内容提取模式",
                               icon: "doc.text.image",
                               tooltip: "若一页文档既存在图片又存在文本时的处理方式") {
                    HStack(spacing: 4) {
                        ForEach(ExtractionMode.allCases) { mode in
                            ExtractionModeRow(
                                mode: mode,
                                isSelected: extractionMode == mode
                            ) { extractionMode = mode }
                        }
                    }
                }

                SettingDivider()

                // ── 保存设置 ──────────────────────────────
                SettingSection(title: "保存位置", icon: "folder") {
                    VStack(alignment: .leading, spacing: 8) {
                        // 输出目录路径
                        HStack(spacing: 6) {
                            // 只读展示已选路径（沙盒下手动输入路径无法获得写权限）
                            Text(specifiedDirURL?.path ?? "未选择目录")
                                .font(.system(size: 12))
                                .foregroundColor(specifiedDirURL == nil
                                    ? Color(NSColor.placeholderTextColor)
                                    : Color(NSColor.labelColor))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                                )
                            Button {
                                chooseOutputDir()
                            } label: {
                                Image(systemName: "folder.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .help("选择输出目录")
                        }

                        // 文件名格式
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("文件名格式")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("%name · %date · %range")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                            }
                            TextField("[OCR]_%name%range_%date", text: $fileNameFormat)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                }

                SettingDivider()

                // ── 输出文件类型 ──────────────────────────
                SettingSection(title: "输出文件类型", icon: "square.and.arrow.down") {
                    VStack(spacing: 0) {
                        OutputTypeRow(
                            label: "layered.pdf",
                            description: "双层可搜索文档（保留原图 + 透明文字层）",
                            icon: "doc.richtext",
                            isOn: $outputTypes.pdfLayered
                        )
                        OutputTypeRow(
                            label: "text.pdf",
                            description: "单层纯文本文档（仅文字，无图片）",
                            icon: "doc.plaintext",
                            isOn: $outputTypes.pdfOneLayer
                        )
                        OutputTypeRow(
                            label: "txt",
                            description: "标准格式（含页码信息）",
                            icon: "doc.text",
                            isOn: $outputTypes.txt
                        )
                        OutputTypeRow(
                            label: "p.txt",
                            description: "纯文字格式（仅输出识别文字）",
                            icon: "text.alignleft",
                            isOn: $outputTypes.txtPlain
                        )
                        OutputTypeRow(
                            label: "csv",
                            description: "表格文件（可用 Excel 打开）",
                            icon: "tablecells",
                            isOn: $outputTypes.csv
                        )
                        OutputTypeRow(
                            label: "jsonl",
                            description: "原始信息（每行一条 JSON，便于程序读取）",
                            icon: "curlybraces",
                            isOn: $outputTypes.jsonl
                        )
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.windowBackgroundColor))
                    )
                }

                SettingDivider()

                // ── 其他选项 ──────────────────────────────
                SettingSection(title: "其他选项", icon: "slider.horizontal.3") {
                    VStack(spacing: 0) {
                        ToggleRow(
                            label: "忽略空白页",
                            description: "跳过没有文字或识别失败的页面",
                            icon: "minus.circle",
                            isOn: $ignoreBlankPages
                        )
                        ToggleRow(
                            label: "递归读取子文件夹",
                            description: "导入文件夹时，同时导入子文件夹中的全部文档",
                            icon: "folder.badge.gearshape",
                            isOn: $recursiveSubfolders
                        )
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.windowBackgroundColor))
                    )
                }

                Spacer(minLength: 20)
            }
            .padding(14)
        }
    }

    // MARK: - 识别记录面板
    private var resultsPanel: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("识别记录")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if !resultLines.isEmpty {
                    Button {
                        copyResult()
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .help("复制所有识别结果")

                    Button {
                        resultLines = []
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("清空记录")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            if resultLines.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(.secondary)
                    Text("识别结果将在此显示")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("点击「开始任务」后，每页识别完成即更新")
                        .font(.caption)
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        let preview = resultLines.suffix(previewPageLimit).joined(separator: "\n")
                        Text(preview)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                        Color.clear
                            .frame(height: 1)
                            .id("ocrBottom")
                    }
                    .onChange(of: resultLines.count) { _ in
                        guard taskState != .stop else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("ocrBottom")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 操作
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = supportedTypes
        panel.message = "选择文档或文件夹（支持 PDF · XPS · EPUB · MOBI）"
        if panel.runModal() == .OK {
            addURLs(panel.urls)
        }
    }

    private func chooseOutputDir() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "选择 OCR 结果保存目录"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            specifiedDirURL = url
        }
    }

    private func addURLs(_ urls: [URL]) {
        let existing = Set(documents.map(\.url))
        for url in urls where !existing.contains(url) {
            var item = DocumentItem(url: url)
            // PDF：通过 PDFKit 读取真实页数
            if item.isPDF, let pdf = PDFDocument(url: url) {
                let count   = pdf.pageCount
                item.pageCount = count
                item.rangeEnd  = count
                // 检测加密
                item.isEncrypted = pdf.isEncrypted && !pdf.isLocked == false
            }
            documents.append(item)
        }
        if selectedID == nil { selectedID = documents.first?.id }
    }

    private func remove(_ doc: DocumentItem) {
        documents.removeAll { $0.id == doc.id }
        if selectedID == doc.id { selectedID = documents.first?.id }
        if documents.isEmpty { resultLines = [] }
    }

    private func clearAll() {
        documents.removeAll()
        selectedID = nil
        resultLines = []
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url {
                        DispatchQueue.main.async { self.addURLs([url]) }
                    }
                }
                handled = true
            }
        }
        return handled
    }

    // MARK: - 任务控制

    private func startTask() {
        guard !documents.isEmpty else { return }
        guard let outputDirURL = specifiedDirURL else {
            toastManager.show("请先选择输出目录", isSuccess: false)
            return
        }

        totalPages     = documents.reduce(0) { $0 + ($1.rangeEnd - $1.rangeStart + 1) }
        processedPages = 0
        resultLines    = []
        taskState      = .running
        taskStartTime  = Date()
        rightTab       = 1
        taskVersion   += 1
        for i in documents.indices { documents[i].state = .queued }

        let version      = taskVersion
        let mode         = extractionMode
        let docs         = documents          // 值类型快照
        let saveSettings = SaveSettings(
            outputDirURL:   outputDirURL,
            fileNameFormat: fileNameFormat,
            outputTypes:    outputTypes
        )

        Task.detached(priority: .userInitiated) {
            await self.runPipeline(docs: docs, mode: mode, version: version, saveSettings: saveSettings)
        }
    }

    private func pauseTask() {
        taskState = .paused
    }

    private func resumeTask() {
        taskState = .running
    }

    private func stopTask() {
        taskVersion   += 1          // 使旧 Task 检查到版本不一致后退出
        taskState     = .stop
        taskStartTime = nil
        for i in documents.indices {
            if case .queued    = documents[i].state { documents[i].state = .idle }
            if case .processing = documents[i].state { documents[i].state = .idle }
        }
    }

    // MARK: - OCR 流水线

    /// 顺序处理每个文档的每一页，在主线程更新 UI 状态。
    private func runPipeline(
        docs: [DocumentItem],
        mode: ExtractionMode,
        version: Int,
        saveSettings: SaveSettings
    ) async {
        for doc in docs {
            // ── 检查取消 / 暂停 ──────────────────────────────
            guard await shouldContinue(version: version) else { return }

            // 打开 PDF（图片文件走单独分支）
            let isPDF = doc.isPDF
            var pdfDoc: PDFDocument?
            if isPDF {
                pdfDoc = PDFDocument(url: doc.url)
                if pdfDoc == nil {
                    await markDoc(id: doc.id, state: .failed("无法打开"))
                    continue
                }
                // 密码解锁
                if let pd = pdfDoc, pd.isEncrypted {
                    let ok = pd.unlock(withPassword: doc.password)
                    if !ok {
                        await markDoc(id: doc.id, state: .failed("密码错误"))
                        continue
                    }
                }
            }

            // 计算本文档页列表（1-based → 0-based）
            let pageList: [Int] = isPDF
                ? Array((doc.rangeStart - 1) ..< doc.rangeEnd)
                : [0]   // 图片视为单页
            let pageTotal = pageList.count

            // 累积每页识别结果，文档处理完后统一写文件
            var pageResults: [(pageIndex: Int, pageRect: CGRect, blocks: [OCRTextBlock])] = []

            for (doneCount, pno) in pageList.enumerated() {
                // 检查取消 / 暂停
                guard await shouldContinue(version: version) else { return }

                // 更新文档行进度
                await markDoc(id: doc.id, state: .processing(doneCount, pageTotal))

                // 执行识别
                do {
                    let (blocks, pageRect): ([OCRTextBlock], CGRect)
                    if isPDF, let pd = pdfDoc, let page = pd.page(at: pno) {
                        (blocks, pageRect) = try await DocumentOCREngine.processPage(page, mode: mode)
                    } else {
                        (blocks, pageRect) = try await DocumentOCREngine.processImage(url: doc.url)
                    }

                    // 累积本页结果（供后续写文件用）
                    pageResults.append((pageIndex: pno, pageRect: pageRect, blocks: blocks))

                    // 组装本页文本并以 O(1) append 追加到界面结果数组
                    let pageText = blocks.map(\.text).joined(separator: "\n")
                    let entry = isPDF
                        ? "\n--- \(doc.name)  第 \(pno + 1) 页 ---\n" + pageText
                        : "\n--- \(doc.name) ---\n" + pageText
                    await MainActor.run {
                        self.resultLines.append(entry)
                        self.processedPages += 1
                    }
                } catch {
                    await MainActor.run {
                        self.resultLines.append("\n[\(doc.name) 第\(pno+1)页 OCR 失败: \(error.localizedDescription)]\n")
                        self.processedPages += 1
                    }
                }
            }

            await markDoc(id: doc.id, state: .done)

            // ── 写出文件 ──────────────────────────────────────────────
            // 至少有一种输出格式被勾选，且有识别结果，才写文件
            let hasOutput = saveSettings.outputTypes.pdfLayered
                || saveSettings.outputTypes.pdfOneLayer
                || saveSettings.outputTypes.txt
                || saveSettings.outputTypes.txtPlain
                || saveSettings.outputTypes.csv
                || saveSettings.outputTypes.jsonl

            if hasOutput, !pageResults.isEmpty {
                let docSnapshot = doc
                let resultsSnapshot = pageResults
                do {
                    try DocumentOutputWriter.writeOutputs(
                        sourceURL:   docSnapshot.url,
                        docItem:     docSnapshot,
                        pageResults: resultsSnapshot,
                        settings:    saveSettings
                    )
                    await MainActor.run {
                        self.toastManager.show("\(docSnapshot.name) 已保存", isSuccess: true)
                    }
                } catch {
                    await MainActor.run {
                        self.toastManager.show("写文件失败：\(error.localizedDescription)", isSuccess: false)
                    }
                }
            }
        }

        // 所有文档处理完毕
        await MainActor.run {
            if self.taskVersion == version {
                self.taskState     = .stop
                self.taskStartTime = nil
            }
        }
    }

    /// 等待暂停解除，并返回当前任务是否应继续（版本匹配 + 未停止）。
    private func shouldContinue(version: Int) async -> Bool {
        // 轮询等待暂停状态解除（暂停时休眠 0.2 s 后重试）
        while true {
            let (v, s) = await MainActor.run { (taskVersion, taskState) }
            if v != version || s == .stop { return false }
            if s == .running { return true }
            // paused — 等待
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    /// 将时间间隔格式化为人类可读字符串（s / m:ss / h:mm:ss）。
    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        if m > 0 { return String(format: "%d:%02d", m, s) }
        return "\(s)s"
    }

    /// 在主线程更新文档的状态标签。
    @MainActor
    private func markDoc(id: UUID, state: DocState) {
        if let idx = documents.firstIndex(where: { $0.id == id }) {
            documents[idx].state = state
        }
    }

    private func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultLines.joined(separator: "\n"), forType: .string)
    }

}

// MARK: - 设置分区标题
private struct SettingSection<Content: View>: View {
    let title: String
    let icon: String
    var tooltip: String = ""
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                if !tooltip.isEmpty {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .help(tooltip)
                }
            }
            content()
        }
    }
}

private struct SettingDivider: View {
    var body: some View {
        Divider().padding(.vertical, 10)
    }
}

// MARK: - 提取模式行
private struct ExtractionModeRow: View {
    let mode: ExtractionMode
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.5))
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                Image(systemName: mode.icon)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 18)
                Text(mode.rawValue)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.1)
                          : (isHovered ? Color(NSColor.labelColor).opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isSelected)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - 输出类型行
private struct OutputTypeRow: View {
    let label: String
    let description: String
    let icon: String
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(isOn ? .accentColor : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(isOn ? .primary : .secondary)
                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.75)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isHovered ? Color(NSColor.labelColor).opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Toggle 选项行
private struct ToggleRow: View {
    let label: String
    let description: String
    let icon: String
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(isOn ? .accentColor : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isOn ? .primary : .secondary)
                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .lineLimit(2)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.75)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isHovered ? Color(NSColor.labelColor).opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - 文档列表行
private struct DocumentRow: View {
    let doc: DocumentItem
    let isSelected: Bool
    let isLocked: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // 文件图标
            Image(systemName: doc.icon)
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 22)

            // 文件信息
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(doc.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if doc.isEncrypted {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                }
                HStack(spacing: 4) {
                    if !doc.pagesLabel.isEmpty {
                        Text(doc.pagesLabel)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    // 状态标签
                    if doc.state.label != "" {
                        Text(doc.state.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(doc.state.color)
                    } else {
                        Text(doc.url.deletingLastPathComponent().lastPathComponent)
                            .font(.system(size: 10))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // 删除按钮（悬浮时显示）
            if isHovered && !isLocked {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.15)
                        : (isHovered ? Color(NSColor.labelColor).opacity(0.06) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - 页范围 & 密码弹窗
struct PageRangeSheet: View {
    @Binding var doc: DocumentItem
    let onDismiss: () -> Void

    @State private var startText: String = ""
    @State private var endText: String   = ""
    @State private var password: String  = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: doc.icon)
                    .foregroundColor(.accentColor)
                Text(doc.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                // 页数信息
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                    Text("共 \(doc.pageCount) 页")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // 页范围
                VStack(alignment: .leading, spacing: 6) {
                    Label("识别页范围", systemImage: "text.book.closed")
                        .font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 8) {
                        TextField("起始页", text: $startText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("–")
                            .foregroundColor(.secondary)
                        TextField("结束页", text: $endText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("（共 \(doc.pageCount) 页）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }

                // 加密文档密码
                if doc.isEncrypted {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("文档密码", systemImage: "lock")
                            .font(.system(size: 12, weight: .semibold))
                        SecureField("输入密码以解锁文档", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding(16)

            Divider()

            // 底部按钮
            HStack {
                Button("取消") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("确认") {
                    applyChanges()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .frame(width: 380)
        .onAppear {
            startText = "\(doc.rangeStart)"
            endText   = "\(doc.rangeEnd)"
            password  = doc.password
        }
    }

    private func applyChanges() {
        if let s = Int(startText), s >= 1, s <= doc.pageCount {
            doc.rangeStart = s
        }
        if let e = Int(endText), e >= doc.rangeStart, e <= doc.pageCount {
            doc.rangeEnd = e
        }
        doc.password = password
    }
}

#Preview {
    DocumentView()
        .frame(width: 860, height: 580)
}
