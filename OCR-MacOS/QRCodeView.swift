//
//  QRCodeView.swift
//  OCR-MacOS
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 二维码扫描结果
struct QRCodeResultItem: Identifiable {
    let id = UUID()
    let type: String    // QR Code / Code128 / ...
    let content: String
    let time: String
}

// MARK: - 二维码主视图
struct QRCodeView: View {
    @State private var selectedTab: QRTab = .scan
    @State private var scanResults: [QRCodeResultItem] = []
    @State private var isProcessing = false
    @State private var hasImage = false
    @State private var isDraggingOver = false

    // 生成面板
    @State private var generateText = ""
    @State private var barcodeFormat = "QR Code"
    @State private var barcodeWidth = 200
    @State private var barcodeHeight = 200
    @State private var quietZone = 1
    @State private var ecLevel = "M"
    @State private var autoRefresh = true
    @State private var hasGeneratedImage = false

    // 设置
    @State private var copyOnScan = true
    @State private var autoOpenURL = false
    @State private var multiScan = true

    enum QRTab { case scan, generate, settings, results }

    private let barcodeFormats = [
        "QR Code", "Aztec", "PDF417",
        "Code128", "Code39", "EAN-13", "EAN-8",
        "DataMatrix"
    ]

    var body: some View {
        HStack(spacing: 0) {
            // ── 左侧：图像预览区 ────────────────────────────
            VStack(spacing: 0) {
                // 顶部工具栏
                HStack(spacing: 6) {
                    qrActionButton(icon: "camera.viewfinder", title: "截图") {}
                    qrActionButton(icon: "doc.on.clipboard", title: "粘贴") {}

                    if isProcessing {
                        ProgressView().scaleEffect(0.6)
                        Text("解析中…")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if hasImage {
                        HStack(spacing: 2) {
                            toolbarIconBtn("arrow.up.left.and.arrow.down.right") {}
                            toolbarIconBtn("1.square") {}
                            toolbarIconBtn("square.and.arrow.down") {}
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // 预览区
                ZStack {
                    Color(NSColor.underPageBackgroundColor)
                    if hasImage {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .padding(20)
                            .overlay(
                                Text("图像预览区\n（识别后显示二维码及矩形框）")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            )
                    } else if selectedTab == .generate && hasGeneratedImage {
                        VStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .frame(width: 180, height: 180)
                                .shadow(radius: 4)
                                .overlay(
                                    VStack(spacing: 6) {
                                        Image(systemName: "qrcode")
                                            .font(.system(size: 64, weight: .light))
                                            .foregroundColor(.black.opacity(0.7))
                                        Text("生成预览")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                )
                            Button("保存图片") {}
                                .buttonStyle(.bordered)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: isDraggingOver ? "arrow.down.to.line.compact" : "qrcode.viewfinder")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(isDraggingOver ? .accentColor : .secondary)
                                .animation(.easeInOut(duration: 0.2), value: isDraggingOver)
                            Text(selectedTab == .generate ? "生成结果将显示在此处" : "截图、拖入或粘贴二维码图片")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    isDraggingOver ? Color.accentColor : Color(NSColor.separatorColor),
                                    style: StrokeStyle(lineWidth: isDraggingOver ? 2 : 1, dash: [6])
                                )
                                .padding(24)
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: ["public.image"], isTargeted: $isDraggingOver) { _ in true }
            }
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // ── 右侧：标签面板 ────────────────────────────
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    qrTabButton("扫码", tag: .scan)
                    qrTabButton("生成", tag: .generate)
                    qrTabButton("设置", tag: .settings)
                    qrTabButton("记录 \(scanResults.isEmpty ? "" : "(\(scanResults.count))")", tag: .results)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                Divider()

                switch selectedTab {
                case .scan:       scanPanel
                case .generate:   generatePanel
                case .settings:   qrSettingsPanel
                case .results:    qrResultsPanel
                }
            }
            .frame(width: 300)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 扫码面板
    private var scanPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("扫码操作")

                VStack(spacing: 8) {
                    scanOperationButton(icon: "camera.viewfinder", title: "屏幕截图", subtitle: "⌃⌥Q") {}
                    scanOperationButton(icon: "doc.on.clipboard", title: "粘贴图片", subtitle: "⌃⌥W") {}
                    scanOperationButton(icon: "photo", title: "从文件导入") {
                        openImageFile()
                    }
                }
                .padding(.horizontal, 12)

                Divider()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

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
                Button("生成") {
                    hasGeneratedImage = !generateText.isEmpty
                }
                .buttonStyle(.bordered)
                .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // 格式选择
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(barcodeFormats, id: \.self) { fmt in
                        Button(action: { barcodeFormat = fmt }) {
                            Text(fmt)
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

            // 尺寸设置
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
                if barcodeFormat == "QR Code" {
                    HStack(spacing: 4) {
                        Text("纠错").font(.system(size: 12)).foregroundColor(.secondary)
                        Picker("", selection: $ecLevel) {
                            ForEach(["L","M","Q","H"], id: \.self) { Text($0) }
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
                        if autoRefresh && !generateText.isEmpty {
                            hasGeneratedImage = true
                        }
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
                    qrToggle("自动打开 URL", icon: "safari", isOn: $autoOpenURL)
                    qrToggle("一张图识别多个码", icon: "rectangle.3.group", isOn: $multiScan)
                }
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - 记录面板
    private var qrResultsPanel: some View {
        VStack(spacing: 0) {
            if scanResults.isEmpty {
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
                        ForEach(scanResults) { item in
                            QRResultRow(item: item)
                        }
                    }
                    .padding(8)
                }
            }
            Divider()
            HStack {
                Text("\(scanResults.count) 条记录")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if !scanResults.isEmpty {
                    Button("清空") { scanResults.removeAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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

    private func openImageFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        if panel.runModal() == .OK { hasImage = panel.url != nil }
    }
}

// MARK: - 扫码结果行
private struct QRResultRow: View {
    let item: QRCodeResultItem
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "qrcode")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.type)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(item.content)
                    .font(.system(size: 12))
                    .lineLimit(2)
                Text(item.time)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isHovered {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.content, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovered ? Color(NSColor.labelColor).opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

#Preview {
    QRCodeView()
        .frame(width: 800, height: 520)
}
