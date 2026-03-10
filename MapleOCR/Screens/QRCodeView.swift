//
//  QRCodeView.swift
//  MapleOCR
//
//  二维码扫码 & 生成 —— 参照 Umi-OCR 二维码功能完整实现
//  功能：截图扫码、粘贴扫码、拖入扫码、从文件导入、
//       条码/二维码生成（QR Code / Aztec / PDF417 / Code128）、
//       结果记录、自动复制、图片保存
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 二维码主视图
struct QRCodeView: View {
    @State private var selectedTab: QRTab = .scan
    @State private var scanOutputs: [QRCodeScanOutput] = []
    @State private var isProcessing = false
    @State private var isDraggingOver = false

    // ── 图像预览 ──
    @State private var currentImage: NSImage?
    @State private var currentBoxes: [QRScanResult] = []
    @State private var imageScale: CGFloat = 1.0
    @State private var showBoxOverlay = true

    // ── 生成面板 ──
    @State private var generateText = ""
    @State private var barcodeFormat: BarcodeGenerateFormat = .qrCode
    @State private var barcodeWidth = 300
    @State private var barcodeHeight = 300
    @State private var ecLevel: QRErrorCorrection = .M
    @State private var autoRefresh = true
    @State private var generatedImage: NSImage?

    // ── 设置 ──
    @State private var copyOnScan = true
    @State private var popWindow = true

    // ── 引擎 ──
    private let engine = QRCodeEngine.shared
    private let overlayManager = ScreenshotOverlayManager()

    enum QRTab: String { case scan, generate, settings, results }

    var body: some View {
        HStack(spacing: 0) {
            // ── 左侧：图像预览区 ────────────────────────────
            VStack(spacing: 0) {
                topToolbar
                Divider()
                imagePreviewArea
            }
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // ── 右侧：标签面板 ────────────────────────────
            VStack(spacing: 0) {
                tabBar
                Divider()

                switch selectedTab {
                case .scan:     scanPanel
                case .generate: generatePanel
                case .settings: qrSettingsPanel
                case .results:  qrResultsPanel
                }
            }
            .frame(width: 300)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            ToastOverlay()
                .environmentObject(ToastManager.shared)
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerQRScan)) { _ in
            startScreenshot()
        }
    }

    // MARK: - 顶部工具栏

    private var topToolbar: some View {
        HStack(spacing: 6) {
            qrActionButton(icon: "camera.viewfinder", title: "截图") {
                startScreenshot()
            }
            qrActionButton(icon: "doc.on.clipboard", title: "粘贴") {
                pasteFromClipboard()
            }

            if isProcessing {
                ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                Text("解析中…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if currentImage != nil || generatedImage != nil {
                Toggle("框选", isOn: $showBoxOverlay)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .help("显示/隐藏识别框")
            }
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
                // 扫码结果预览
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
                            .interpolation(.high)
                            .frame(width: displayW, height: displayH)
                            .overlay(alignment: .topLeading) {
                                if showBoxOverlay && !currentBoxes.isEmpty {
                                    ZStack(alignment: .topLeading) {
                                        ForEach(currentBoxes) { box in
                                            qrBoxOverlay(
                                                box: box,
                                                imageWidth: displayW,
                                                imageHeight: displayH
                                            )
                                        }
                                    }
                                    .frame(width: displayW, height: displayH)
                                }
                            }
                            .frame(
                                width: max(displayW, geo.size.width),
                                height: max(displayH, geo.size.height),
                                alignment: .topLeading
                            )
                    }
                }
            } else if selectedTab == .generate, let genImg = generatedImage {
                // 生成结果预览
                VStack(spacing: 12) {
                    Image(nsImage: genImg)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(maxWidth: 280, maxHeight: 280)
                        .background(Color.white)
                        .cornerRadius(8)
                        .shadow(radius: 4)

                    Button("保存图片") { saveGeneratedImage() }
                        .buttonStyle(.bordered)
                }
            } else {
                // 空态提示
                VStack(spacing: 12) {
                    Image(systemName: isDraggingOver ? "arrow.down.to.line.compact" : "qrcode.viewfinder")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(isDraggingOver ? .accentColor : .secondary)
                        .animation(.easeInOut(duration: 0.2), value: isDraggingOver)
                    Text(selectedTab == .generate ? "生成结果将显示在此处" : "截图、拖入或粘贴二维码图片")
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

    // MARK: - 二维码框叠加

    private func qrBoxOverlay(
        box: QRScanResult,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> some View {
        let bb = box.boundingBox
        // Vision 归一化坐标（左下原点）→ SwiftUI（左上原点）
        let x = bb.origin.x * imageWidth
        let y = (1 - bb.origin.y - bb.height) * imageHeight
        let w = bb.width * imageWidth
        let h = bb.height * imageHeight

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.green.opacity(0.15))
                .border(Color.green.opacity(0.7), width: 2)
            Text(box.format)
                .font(.system(size: max(8, min(h * 0.25, 12)), weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.7))
                .cornerRadius(3)
                .padding(2)
        }
        .frame(width: w, height: h)
        .position(x: x + w / 2, y: y + h / 2)
        .help("\(box.format): \(box.text)")
    }

    // MARK: - 标签栏

    private var tabBar: some View {
        HStack(spacing: 0) {
            qrTabButton("扫码", tag: .scan)
            qrTabButton("生成", tag: .generate)
            qrTabButton("设置", tag: .settings)
            qrTabButton("记录 \(scanOutputs.isEmpty ? "" : "(\(totalResultCount))")", tag: .results)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private var totalResultCount: Int {
        scanOutputs.reduce(0) { $0 + $1.codes.count }
    }

    // MARK: - 扫码面板

    private var scanPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("支持的格式")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 6) {
                    ForEach(["QR Code","Aztec","PDF417","Code128","Code39","EAN-13","EAN-8","DataMatrix"], id: \.self) { fmt in
                        Text(fmt)
                            .font(.system(size: 10))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(5)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - 生成面板

    private var generatePanel: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Button("设置") { selectedTab = .settings }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                Spacer()
                Toggle("自动刷新", isOn: $autoRefresh)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Button("生成") { refreshGenerated() }
                    .buttonStyle(.bordered)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // 格式选择
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(BarcodeGenerateFormat.allCases) { fmt in
                        Button(action: { barcodeFormat = fmt; refreshGenerated() }) {
                            Text(fmt.rawValue)
                                .font(.system(size: 11))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    barcodeFormat == fmt
                                        ? Color.accentColor.opacity(0.15)
                                        : Color(NSColor.controlBackgroundColor)
                                )
                                .foregroundColor(barcodeFormat == fmt ? .accentColor : .primary)
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 6)

            Divider()

            // 尺寸 & 纠错设置
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("宽").font(.system(size: 12)).foregroundColor(.secondary)
                    TextField("", value: $barcodeWidth, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("px").font(.system(size: 11)).foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Text("高").font(.system(size: 12)).foregroundColor(.secondary)
                    TextField("", value: $barcodeHeight, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("px").font(.system(size: 11)).foregroundColor(.secondary)
                }
                if barcodeFormat == .qrCode {
                    HStack(spacing: 4) {
                        Text("纠错").font(.system(size: 12)).foregroundColor(.secondary)
                        Picker("", selection: $ecLevel) {
                            ForEach(QRErrorCorrection.allCases) { level in
                                Text(level.rawValue).tag(level)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 55)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // 文本输入区
            ZStack(alignment: .topLeading) {
                TextEditor(text: $generateText)
                    .font(.system(.body))
                    .scrollContentBackground(.hidden)
                    .background(Color(NSColor.textBackgroundColor))
                    .onChange(of: generateText) { _, _ in
                        if autoRefresh { refreshGenerated() }
                    }
                if generateText.isEmpty {
                    Text("输入要生成的文字或 URL…")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .padding(10)
        }
    }

    // MARK: - 设置面板

    private var qrSettingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                qrSection("扫码动作") {
                    qrToggle("扫到结果后复制", icon: "doc.on.doc", isOn: $copyOnScan)
                    qrToggle("弹出主窗口", icon: "macwindow.badge.plus", isOn: $popWindow)
                }
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - 记录面板

    private var qrResultsPanel: some View {
        VStack(spacing: 0) {
            if scanOutputs.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(.secondary)
                    Text("暂无扫码记录")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(scanOutputs) { output in
                            ForEach(output.codes) { item in
                                QRResultRow(item: item, time: output.timestamp) {
                                    // 点击结果行：展示对应源图
                                    currentImage = output.sourceImage
                                    currentBoxes = output.codes
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }
            Divider()
            HStack {
                Text("\(totalResultCount) 条记录")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button("复制全部") { copyAllResults() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                    .disabled(scanOutputs.isEmpty)
                if !scanOutputs.isEmpty {
                    Button("清空") {
                        scanOutputs.removeAll()
                        currentImage = nil
                        currentBoxes = []
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

    // MARK: - 核心功能

    /// 截图扫码
    private func startScreenshot() {
        overlayManager.startCapture(mode: .drag, hideMainWindow: true) { image in
            guard let image else { return }
            processImage(image)
        }
    }

    /// 粘贴图片扫码
    private func pasteFromClipboard() {
        let content = ScreenshotEngine.shared.getClipboardContent()
        switch content {
        case .image(let image):
            processImage(image)
        case .filePaths(let urls):
            if let first = urls.first, let image = NSImage(contentsOf: first) {
                processImage(image)
            }
        case .text:
            showToast("剪贴板中为文本，非图片", isSuccess: false)
        case .empty:
            showToast("剪贴板为空", isSuccess: false)
        case .error(let msg):
            showToast(msg, isSuccess: false)
        }
    }

    /// 从文件导入
    private func openImageFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif, .heic]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let image = NSImage(contentsOf: url) {
                processImage(image)
            }
        }
    }

    /// 处理拖入
    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { image, _ in
                    if let image = image as? NSImage {
                        Task { @MainActor in processImage(image) }
                    }
                }
                return
            }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let urlData = data as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil),
                      let image = NSImage(contentsOf: url)
                else { return }
                Task { @MainActor in processImage(image) }
            }
        }
    }

    /// 对图片执行条码扫描
    private func processImage(_ image: NSImage) {
        currentImage = image
        currentBoxes = []
        isProcessing = true

        // 自动切换到记录页
        if selectedTab != .results {
            selectedTab = .results
        }

        Task {
            let output = await engine.scanImage(image)
            isProcessing = false
            handleScanOutput(output)
        }
    }

    /// 处理扫码结果
    private func handleScanOutput(_ output: QRCodeScanOutput) {
        scanOutputs.insert(output, at: 0)
        currentBoxes = output.codes
        if let img = output.sourceImage {
            currentImage = img
        }

        let timeStr = String(format: "%.2fs", output.duration)
        switch output.code {
        case 100:
            let texts = output.codes.map(\.text).joined(separator: "\n")
            if copyOnScan {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(texts, forType: .string)
                showToast("扫到 \(output.codes.count) 个码，已复制  —  \(timeStr)", isSuccess: true)
            } else {
                showToast("扫到 \(output.codes.count) 个码  —  \(timeStr)", isSuccess: true)
            }
        case 101:
            showToast("未识别到条码  —  \(timeStr)", isSuccess: false)
        default:
            showToast("扫码失败  —  \(timeStr)", isSuccess: false)
        }

        if popWindow {
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 刷新生成的条码
    private func refreshGenerated() {
        guard !generateText.isEmpty else {
            generatedImage = nil
            return
        }
        // 清除扫码预览，让生成预览显示
        currentImage = nil
        currentBoxes = []

        generatedImage = engine.generateBarcode(
            text: generateText,
            format: barcodeFormat,
            width: barcodeWidth,
            height: barcodeHeight,
            ecLevel: ecLevel
        )
        if generatedImage == nil {
            showToast("生成失败，请检查内容和格式是否匹配", isSuccess: false)
        }
    }

    /// 复制全部结果
    private func copyAllResults() {
        let allText = scanOutputs
            .flatMap(\.codes)
            .map { "[\($0.format)] \($0.text)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allText, forType: .string)
        showToast("已复制 \(totalResultCount) 条结果", isSuccess: true)
    }

    // MARK: - 图片保存

    private func saveCurrentImage() {
        let image = currentImage ?? generatedImage
        guard let image else {
            showToast("无可保存的图片", isSuccess: false)
            return
        }
        saveImageToFile(image, defaultName: "MapleOCR_扫码_\(formatTimestamp(Date())).png")
    }

    private func saveGeneratedImage() {
        guard let image = generatedImage else { return }
        saveImageToFile(image, defaultName: "MapleOCR_生成_\(formatTimestamp(Date())).png")
    }

    private func saveImageToFile(_ image: NSImage, defaultName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = defaultName
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:])
            else { return }
            try? pngData.write(to: url)
            Task { @MainActor in showToast("图片已保存", isSuccess: true) }
        }
    }

    // MARK: - 辅助组件

    private func qrTabButton(_ title: String, tag: QRTab) -> some View {
        Button(action: { selectedTab = tag }) {
            Text(title)
                .font(.system(size: 12, weight: selectedTab == tag ? .semibold : .regular))
                .padding(.horizontal, 10)
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

    private func qrActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
    }

    private func toolbarIconBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }

    private func scanOperationButton(icon: String, title: String, subtitle: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func qrSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
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

    private func qrToggle(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 18)
                Text(label).font(.system(size: 13))
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

// MARK: - 扫码结果行

private struct QRResultRow: View {
    let item: QRScanResult
    let time: Date
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForFormat(item.format))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.format)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(item.text)
                    .font(.system(size: 12))
                    .lineLimit(2)
                Text(formatTime(time))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isHovered {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("复制内容")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovered ? Color(NSColor.labelColor).opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }

    private func iconForFormat(_ format: String) -> String {
        switch format {
        case "QR Code":    return "qrcode"
        case "Aztec":      return "viewfinder.circle"
        case "PDF417":     return "barcode"
        case "DataMatrix": return "square.grid.3x3"
        default:           return "barcode"
        }
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

#Preview {
    QRCodeView()
        .frame(width: 800, height: 520)
}
