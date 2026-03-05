//
//  BatchOCRView.swift
//  OCR-MacOS
//

import SwiftUI
import UniformTypeIdentifiers

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

// MARK: - 批量 OCR 主视图
struct BatchOCRView: View {

    @State private var images: [BatchImageItem] = []
    @State private var selectedID: UUID?
    @State private var isDraggingOver = false

    @State private var isRunning = false
    @State private var progress: Double = 0
    @State private var processedCount = 0

    @State private var selectedTab: BatchTab = .settings
    @State private var ocrResults: [OCRResultItem] = []

    // 设置
    @State private var outputFormat = "纯文本"
    @State private var recurrence = false
    @State private var saveToFile = false
    @State private var savePath = "与图片同目录"
    @State private var postTaskAction = "无操作"

    enum BatchTab { case settings, results }

    private let supportedImageTypes: [UTType] = [.png, .jpeg, .tiff, .bmp, .heic, .gif]

    var body: some View {
        HStack(spacing: 0) {
            // ── 左侧：文件列表 ────────────────────────────
            VStack(spacing: 0) {
                // 顶部工具栏
                HStack {
                    Text("文件列表")
                        .font(.headline)
                    Spacer()
                    Button {
                        openFilePicker()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("添加图片")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()

                // 文件列表 / 空态
                if images.isEmpty {
                    dropZone
                } else {
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
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Divider()

                    // 进度条（运行时显示）
                    if isRunning {
                        VStack(spacing: 4) {
                            ProgressView(value: progress, total: Double(images.count))
                                .progressViewStyle(.linear)
                                .padding(.horizontal, 12)
                            Text("已处理 \(processedCount) / \(images.count)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    }

                    // 底部按钮
                    HStack(spacing: 6) {
                        Button("添加") { openFilePicker() }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("清空") { clearAll() }
                            .buttonStyle(.bordered)
                            .foregroundColor(.red)
                            .disabled(isRunning)
                        if isRunning {
                            Button("停止") { stopOCR() }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                        } else {
                            Button("开始识别") { startOCR() }
                                .buttonStyle(.borderedProminent)
                                .disabled(images.isEmpty)
                        }
                    }
                    .padding(10)
                }
            }
            .frame(width: 300)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .trailing
            )
            .onDrop(of: supportedImageTypes, isTargeted: $isDraggingOver) { providers in
                handleDrop(providers: providers)
            }

            // ── 右侧：设置 & 记录 ────────────────────────────
            VStack(spacing: 0) {
                // 标签切换
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
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 拖拽空态
    private var dropZone: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: isDraggingOver ? "tray.and.arrow.down.fill" : "photo.stack")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(isDraggingOver ? .accentColor : .secondary)
                .animation(.easeInOut(duration: 0.2), value: isDraggingOver)
            Text("拖入图片或点击添加")
                .font(.callout)
                .foregroundColor(.secondary)
            Button("选择图片") { openFilePicker() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isDraggingOver ? Color.accentColor : Color(NSColor.separatorColor),
                    style: StrokeStyle(lineWidth: isDraggingOver ? 2 : 1, dash: [6])
                )
                .padding(12)
                .animation(.easeInOut(duration: 0.2), value: isDraggingOver)
        )
    }

    // MARK: - 设置面板
    private var batchSettingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                batchSettingsSection("输出格式") {
                    Picker("格式", selection: $outputFormat) {
                        Text("纯文本").tag("纯文本")
                        Text("Markdown").tag("Markdown")
                        Text("自然段落").tag("自然段落")
                        Text("竖排文字").tag("竖排文字")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                batchSettingsSection("任务设置") {
                    batchSettingsToggle("子文件夹递归", icon: "folder.badge.gearshape", isOn: $recurrence)
                    batchSettingsToggle("保存结果到文件", icon: "arrow.down.doc", isOn: $saveToFile)

                    if saveToFile {
                        HStack {
                            Text("保存路径")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(savePath)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("浏览") {}
                                .buttonStyle(.bordered)
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                    }
                }

                batchSettingsSection("任务后续") {
                    Picker("任务完成后", selection: $postTaskAction) {
                        Text("无操作").tag("无操作")
                        Text("睡眠").tag("睡眠")
                        Text("关机").tag("关机")
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                batchSettingsSection("忽略区域") {
                    Button {
                    } label: {
                        Label("编辑忽略区域", systemImage: "rectangle.dashed")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
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
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(ocrResults) { item in
                            OCRResultRow(item: item)
                        }
                    }
                    .padding(8)
                }
            }
            Divider()
            HStack {
                Text("\(ocrResults.count) 条记录")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if !ocrResults.isEmpty {
                    Button("导出…") {}
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                    Button("清空") { ocrResults.removeAll() }
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

    // MARK: - 操作

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = supportedImageTypes
        panel.message = "选择需要识别的图片"
        if panel.runModal() == .OK {
            addURLs(panel.urls)
        }
    }

    private func addURLs(_ urls: [URL]) {
        let existing = Set(images.map(\.url))
        for url in urls where !existing.contains(url) {
            images.append(BatchImageItem(url: url))
        }
    }

    private func clearAll() {
        images.removeAll()
        ocrResults.removeAll()
        progress = 0
        processedCount = 0
    }

    private func startOCR() {
        isRunning = true
        progress = 0
        processedCount = 0
        for i in images.indices {
            images[i].status = .waiting
            images[i].duration = ""
        }
    }

    private func stopOCR() {
        isRunning = false
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url {
                        DispatchQueue.main.async { addURLs([url]) }
                    }
                }
                handled = true
            }
        }
        return handled
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
            Image(systemName: "photo")
                .font(.system(size: 13))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 22)
                .padding(.leading, 8)

            Text(item.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)

            Text(item.duration)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .trailing)

            Text(item.status == .waiting && item.duration.isEmpty ? "" : item.status.label)
                .font(.system(size: 11))
                .foregroundColor(item.status.color)
                .frame(width: 52, alignment: .trailing)
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
}

#Preview {
    BatchOCRView()
        .frame(width: 800, height: 520)
}
