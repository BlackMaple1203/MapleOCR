//
//  ScreenshotView.swift
//  MapleOCR
//
//  截图识别主视图 —— 参照 Umi-OCR 截图OCR功能完整实现
//  功能：截图/粘贴/拖入/重复截图、区域选择、Vision OCR、
//       结果展示（文字框叠加、置信度、耗时）、自动复制、
//       段落合并策略、忽略区域、图片缩放/保存、通知提示
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 截图识别主视图

struct ScreenshotView: View {
    // ── 状态 ──
    @State private var selectedTab: ScreenshotTab = .settings
    @State private var ocrResults: [ScreenshotOCRResult] = []
    @State private var selectedResultID: UUID?
    @State private var isProcessing = false
    @State private var msnState: MissionState = .none

    // ── 图像 ──
    @State private var currentImage: NSImage?
    @State private var currentBoxes: [ScreenshotOCRResult.TextBox] = []
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var showTextOverlay = true

    // ── 设置 ──
    @State private var selectionMode: SelectionMode = .drag
    @State private var copyOnRecognize = true
    @State private var autoBringWindow = true
    @State private var paragraphStrategy: ParagraphStrategy = .multiPara
    @State private var hideWindowOnCapture = true

    // ── 拖入 ──
    @State private var isDraggingOver = false

    // ── 引擎 ──
    @StateObject private var engine = ScreenshotEngine.shared
    private let overlayManager = ScreenshotOverlayManager()

    enum ScreenshotTab: String { case settings = "设置", results = "记录" }
    enum MissionState { case none, running }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // ── 左侧：图像预览区 ──
            VStack(spacing: 0) {
                topToolbar
                Divider()
                imagePreviewArea
            }
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // ── 右侧：设置 & 记录 ──
            VStack(spacing: 0) {
                tabBar
                Divider()
                if selectedTab == .settings {
                    settingsPanel
                } else {
                    resultsPanel
                }
            }
            .frame(width: 280)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            ToastOverlay()
                .environmentObject(ToastManager.shared)
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerScreenshotOCR)) { _ in
            startScreenshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerPasteOCR)) { _ in
            pasteFromClipboard()
        }
    }

    // MARK: - 顶部工具栏

    private var topToolbar: some View {
        HStack(spacing: 6) {
            // 截图按钮
            actionButton(icon: "camera.viewfinder", title: "截图") {
                startScreenshot()
            }

            // 粘贴按钮
            actionButton(icon: "doc.on.clipboard", title: "粘贴") {
                pasteFromClipboard()
            }

            // 停止任务
            if msnState == .running {
                Button {
                    stopTask()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                        Text("停止")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }

            if isProcessing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
                Text("识别中…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 文字叠加开关
            Toggle("文字", isOn: $showTextOverlay)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .help("在图片上叠加显示识别文字")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - 图像预览区域

    private var imagePreviewArea: some View {
        ZStack {
            Color(NSColor.underPageBackgroundColor)

            if let image = currentImage {
                // 图片 + 文字框叠加
                GeometryReader { geo in
                    let imgSize = image.size
                    let fitScale = min(
                        geo.size.width / imgSize.width,
                        geo.size.height / imgSize.height
                    )
                    let displayW = imgSize.width * fitScale * imageScale
                    let displayH = imgSize.height * fitScale * imageScale

                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: displayW, height: displayH)
                            // 文字框叠加层：用 overlay 贴在 Image 上，不影响外层 frame 对齐
                            .overlay(alignment: .topLeading) {
                                if showTextOverlay && !currentBoxes.isEmpty {
                                    ZStack(alignment: .topLeading) {
                                        ForEach(currentBoxes) { box in
                                            textBoxOverlay(
                                                box: box,
                                                imageWidth: displayW,
                                                imageHeight: displayH
                                            )
                                        }
                                    }
                                    .frame(width: displayW, height: displayH)
                                }
                            }
                            // 将图片锚定到左上角，用透明区域填满剩余空间
                            .frame(
                                width: max(displayW, geo.size.width),
                                height: max(displayH, geo.size.height),
                                alignment: .topLeading
                            )
                    }
                }
            } else {
                // 空态提示
                VStack(spacing: 12) {
                    Image(systemName: isDraggingOver ? "arrow.down.to.line.compact" : "camera.viewfinder")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(isDraggingOver ? .accentColor : .secondary)
                        .animation(.easeInOut(duration: 0.2), value: isDraggingOver)
                    Text("截图、拖入或粘贴图片")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.image, .fileURL], isTargeted: $isDraggingOver) { providers in
            handleDrop(providers)
            return true
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    imageScale = max(0.1, min(10.0, value.magnification))
                }
        )
    }

    // MARK: - 文字框叠加

    private func textBoxOverlay(
        box: ScreenshotOCRResult.TextBox,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> some View {
        let bb = box.boundingBox
        // Vision 归一化坐标（左下角原点）→ SwiftUI 坐标（左上角原点）
        let x = bb.origin.x * imageWidth
        let y = (1 - bb.origin.y - bb.height) * imageHeight
        let w = bb.width * imageWidth
        let h = bb.height * imageHeight

        return ZStack(alignment: .topLeading) {
            // 半透明背景
            Rectangle()
                .fill(Color.accentColor.opacity(0.15))
                .border(Color.accentColor.opacity(0.6), width: 1)

            // 文字标签
            Text(box.text)
                .font(.system(size: max(8, min(h * 0.7, 14))))
                .foregroundColor(.primary)
                .lineLimit(1)
                .padding(.horizontal, 2)
        }
        .frame(width: w, height: h)
        .position(x: x + w / 2, y: y + h / 2)
        .help("\(box.text)\n置信度: \(String(format: "%.1f%%", box.confidence * 100))")
    }

    // MARK: - 标签栏

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("设置", tag: .settings)
            tabButton("记录 \(ocrResults.isEmpty ? "" : "(\(ocrResults.count))")", tag: .results)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    // MARK: - 设置面板

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // 识图后的操作
                settingsSection("识图后的操作") {
                    settingsToggle("复制结果到剪贴板", icon: "doc.on.doc", isOn: $copyOnRecognize)
                    settingsToggle("弹出主窗口", icon: "macwindow.badge.plus", isOn: $autoBringWindow)
                }

                // OCR 文本后处理
                settingsSection("OCR 文本后处理") {
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

                // 截图设置
                settingsSection("截图设置") {
                    settingsToggle("截图前隐藏主窗口", icon: "eye.slash", isOn: $hideWindowOnCapture)

                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.on.rectangle")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .frame(width: 18)
                            Text("截图模式")
                                .font(.system(size: 13))
                        }
                        Spacer()
                        Picker("", selection: $selectionMode) {
                            Text("拖动").tag(SelectionMode.drag)
                            Text("点击").tag(SelectionMode.click)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                }


            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - 记录面板

    private var resultsPanel: some View {
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
                                OCRResultRow(
                                    item: item,
                                    isSelected: selectedResultID == item.id,
                                    onSelect: {
                                        selectedResultID = item.id
                                        showResult(item)
                                    },
                                    onDelete: {
                                        ocrResults.removeAll { $0.id == item.id }
                                    }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: ocrResults.count) { _ in
                        if let last = ocrResults.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
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
                Spacer()
                Button("复制全部") {
                    copyAllResults()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
                .disabled(ocrResults.isEmpty)

                Button("清空") {
                    ocrResults.removeAll()
                    currentImage = nil
                    currentBoxes = []
                    selectedResultID = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.red)
                .disabled(ocrResults.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 核心功能

    /// 开始截图
    private func startScreenshot() {
        print("[DEBUG][ScreenshotView] startScreenshot() - 模式: \(selectionMode.rawValue)，截图前隐藏窗口: \(hideWindowOnCapture)")
        overlayManager.startCapture(
            mode: selectionMode,
            hideMainWindow: hideWindowOnCapture
        ) { image in
            guard let image else { return }   // 用户取消
            processImage(image)
        }
    }

    /// 从剪贴板粘贴
    private func pasteFromClipboard() {
        print("[DEBUG][ScreenshotView] pasteFromClipboard() - 从剪贴板粘贴")
        let content = engine.getClipboardContent()
        switch content {
        case .image(let image):
            processImage(image)

        case .filePaths(let paths):
            showToast("导入 \(paths.count) 条图片路径", isSuccess: true)
            processPaths(paths)

        case .text(let text):
            showToast("剪贴板中为文本：\(text.prefix(50))", isSuccess: false)

        case .empty:
            showToast("剪贴板为空", isSuccess: false)

        case .error(let msg):
            showToast(msg, isSuccess: false)
        }
    }

    /// 处理拖入的文件
    private func handleDrop(_ providers: [NSItemProvider]) {
        print("[DEBUG][ScreenshotView] handleDrop() - 拖入文件数: \(providers.count)")
        for provider in providers {
            // 图片数据
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { image, _ in
                    if let image = image as? NSImage {
                        Task { @MainActor in processImage(image) }
                    }
                }
                return
            }

            // 文件 URL
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let urlData = data as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil),
                      let image = NSImage(contentsOf: url)
                else { return }
                Task { @MainActor in processImage(image) }
            }
        }
    }

    /// 对单张图片执行 OCR
    private func processImage(_ image: NSImage) {
        print("[DEBUG][ScreenshotView] processImage() - 处理图片，尺寸: \(image.size)")
        currentImage = image
        currentBoxes = []
        isProcessing = true
        msnState = .running

        // 自动切换到记录页
        if selectedTab == .settings {
            selectedTab = .results
        }

        Task {
            let result = await engine.performOCR(on: image)
            isProcessing = false
            msnState = .none
            handleOCRResult(result)
        }
    }

    /// 对一批文件路径执行 OCR
    private func processPaths(_ paths: [URL]) {
        print("[DEBUG][ScreenshotView] processPaths() - 文件路径数: \(paths.count)")
        guard !paths.isEmpty else { return }
        isProcessing = true
        msnState = .running

        if selectedTab == .settings {
            selectedTab = .results
        }

        Task {
            for url in paths {
                guard msnState == .running else { break }
                if let image = NSImage(contentsOf: url) {
                    currentImage = image
                    currentBoxes = []
                    let result = await engine.performOCR(on: image)
                    handleOCRResult(result)
                }
            }
            isProcessing = false
            msnState = .none
        }
    }

    /// 处理 OCR 结果
    private func handleOCRResult(_ result: ScreenshotOCRResult) {
        print("[DEBUG][ScreenshotView] handleOCRResult() - 状态码: \(result.code)，置信度: \(String(format: "%.2f", result.confidence))，耗时: \(String(format: "%.2fs", result.duration))，文字框数: \(result.boxes.count)")
        ocrResults.append(result)
        selectedResultID = result.id

        // 更新图片框
        currentBoxes = result.boxes
        if let img = result.sourceImage {
            currentImage = img
        }

        // 生成格式化文本
        let formattedText = engine.formatText(result.boxes, strategy: paragraphStrategy)

        // 自动复制到剪贴板
        if copyOnRecognize && !formattedText.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(formattedText, forType: .string)
        }

        // 显示 Toast
        let timeStr = String(format: "%.2fs", result.duration)
        switch result.code {
        case 100:
            let title = copyOnRecognize ? "已复制到剪贴板" : "识图完成"
            showToast("\(title)  —  \(timeStr)", isSuccess: true)
        case 101:
            showToast("无文字  —  \(timeStr)", isSuccess: false)
        default:
            showToast("识别失败  —  \(timeStr)", isSuccess: false)
        }

        // 弹出主窗口
        if autoBringWindow {
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 停止当前任务
    private func stopTask() {
        print("[DEBUG][ScreenshotView] stopTask() - 停止当前任务")
        msnState = .none
        isProcessing = false
    }

    /// 选择并显示历史结果
    private func showResult(_ result: ScreenshotOCRResult) {
        print("[DEBUG][ScreenshotView] showResult() - 显示历史结果，文字框数: \(result.boxes.count)")
        currentImage = result.sourceImage
        currentBoxes = result.boxes
    }

    // MARK: - 图片操作

    /// 设为实际大小
    private func setActualSize() {
        guard let image = currentImage else { return }
        // 实际像素大小 / 当前容器大小 来计算缩放比
        // 简化处理：重置为 1:1 但可能需要更精确计算
        let pixelW = image.size.width
        if pixelW > 0 {
            imageScale = 1.0
        }
    }

    /// 保存图片
    private func saveImage() {
        print("[DEBUG][ScreenshotView] saveImage() - 保存图片")
        guard let image = currentImage else {
            print("[DEBUG][ScreenshotView] saveImage() - 无可保存的图片，取消")
            showToast("无可保存的图片", isSuccess: false)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "MapleOCR_截图_\(formatTimestamp(Date())).png"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:])
            else { return }
            try? pngData.write(to: url)
            Task { @MainActor in
                showToast("图片已保存", isSuccess: true)
            }
        }
    }

    /// 复制全部结果
    private func copyAllResults() {
        print("[DEBUG][ScreenshotView] copyAllResults() - 复制全部 \(ocrResults.count) 条结果")
        let allText = ocrResults
            .filter { $0.code == 100 }
            .map { engine.formatText($0.boxes, strategy: paragraphStrategy) }
            .joined(separator: "\n\n---\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allText, forType: .string)
        showToast("已复制 \(ocrResults.count) 条结果", isSuccess: true)
    }

    // MARK: - 辅助组件

    private func tabButton(_ title: String, tag: ScreenshotTab) -> some View {
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

    private func actionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
    }

    private func toolbarIconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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

    private func settingsToggle(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
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

    private func formatTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: date)
    }
}

// MARK: - OCR 结果行

struct OCRResultRow: View {
    let item: ScreenshotOCRResult
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

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
                // 展开/折叠按钮（仅点此按钮才展开）
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "折叠" : "展开")

                Image(systemName: statusIcon)
                    .font(.system(size: 13))
                    .foregroundColor(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    // 文本内容预览
                    Text(item.text.isEmpty ? "（无文字）" : item.text)
                        .font(.system(size: 12))
                        .lineLimit(isExpanded ? nil : 2)
                        .foregroundColor(item.text.isEmpty ? .secondary : .primary)

                    // 元信息：时间 + 耗时 + 置信度
                    HStack(spacing: 6) {
                        Text(formatTime(item.timestamp))
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

                // 悬停操作按钮
                if isHovered {
                    HStack(spacing: 4) {
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

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .help("删除记录")
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.12)
                        : (isHovered ? Color(NSColor.labelColor).opacity(0.05) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .animation(.easeInOut(duration: 0.1), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

#Preview {
    ScreenshotView()
        .frame(width: 900, height: 560)
}
