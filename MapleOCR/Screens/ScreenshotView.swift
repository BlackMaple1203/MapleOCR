//
//  ScreenshotView.swift
//  MapleOCR
//

import SwiftUI

// MARK: - OCR 识别记录条目
struct OCRResultItem: Identifiable {
    let id = UUID()
    let imageName: String
    let text: String
    let time: String
    let duration: Double
}

// MARK: - 截图识别主视图
struct ScreenshotView: View {
    @State private var selectedTab: ScreenshotTab = .settings
    @State private var ocrResults: [OCRResultItem] = []
    @State private var isProcessing = false
    @State private var hasImage = false
    @State private var imageScale: Double = 100
    @State private var showTextOverlay = true
    @State private var copyOnRecognize = true
    @State private var autoBringWindow = true
    @State private var screenshotMode = "拖动"
    @State private var outputFormat = "纯文本"
    @State private var isDraggingOver = false

    enum ScreenshotTab { case settings, results }

    var body: some View {
        HStack(spacing: 0) {
            // ── 左侧：图像预览区 ────────────────────────────
            VStack(spacing: 0) {
                // 顶部工具栏
                HStack(spacing: 6) {
                    // 截图模式
                    Menu {
                        Button("拖动截图") { screenshotMode = "拖动" }
                        Button("点击截图") { screenshotMode = "点击" }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "camera.on.rectangle")
                                .font(.system(size: 12))
                            Text(screenshotMode)
                                .font(.system(size: 12))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    actionButton(icon: "camera.viewfinder", title: "截图") {}
                    actionButton(icon: "doc.on.clipboard", title: "粘贴") {}

                    if isProcessing {
                        ProgressView().scaleEffect(0.6)
                        Text("识别中…")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // 文字叠加开关
                    Toggle("文字", isOn: $showTextOverlay)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))

                    // 缩放比例
                    Text("\(Int(imageScale))%")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)

                    HStack(spacing: 2) {
                        toolbarIconButton("arrow.up.left.and.arrow.down.right") {}
                        toolbarIconButton("1.square") {}
                        toolbarIconButton("square.and.arrow.down") {}
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // 图像预览区域
                ZStack {
                    Color(NSColor.underPageBackgroundColor)
                    if hasImage {
                        // 占位：图像加载后显示
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .padding(20)
                            .overlay(
                                Text("图像预览区域\n（识别后显示截图及文字框）")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            )
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
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    isDraggingOver ? Color.accentColor : Color(NSColor.separatorColor),
                                    style: StrokeStyle(lineWidth: isDraggingOver ? 2 : 1, dash: [6])
                                )
                                .padding(24)
                                .animation(.easeInOut(duration: 0.2), value: isDraggingOver)
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: ["public.image", "public.file-url"], isTargeted: $isDraggingOver) { _ in true }
            }
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // ── 右侧：设置 & 记录 ────────────────────────────
            VStack(spacing: 0) {
                // 标签切换
                HStack(spacing: 0) {
                    tabButton("设置", tag: .settings)
                    tabButton("记录 \(ocrResults.isEmpty ? "" : "(\(ocrResults.count))")", tag: .results)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

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
    }

    // MARK: - 设置面板
    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                settingsSection("动作") {
                    settingsToggle("识别后复制到剪贴板", icon: "doc.on.doc", isOn: $copyOnRecognize)
                    settingsToggle("识别后弹出主窗口", icon: "macwindow.badge.plus", isOn: $autoBringWindow)
                }

                settingsSection("输出格式") {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("格式", selection: $outputFormat) {
                            Text("纯文本").tag("纯文本")
                            Text("Markdown").tag("Markdown")
                            Text("自然段落").tag("自然段落")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                settingsSection("快捷键") {
                    shortcutRow("截图识别", key: "⌃ ⌥ C")
                    shortcutRow("粘贴识别", key: "⌃ ⌥ V")
                    shortcutRow("重复截图", key: "⌃ ⌥ R")
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
                Button("清空") { ocrResults.removeAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
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

    private func shortcutRow(_ label: String, key: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            Text(key)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

// MARK: - OCR 结果行
struct OCRResultRow: View {
    let item: OCRResultItem
    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.image")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text.isEmpty ? "（无文字）" : item.text)
                        .font(.system(size: 12))
                        .lineLimit(isExpanded ? nil : 2)
                    HStack(spacing: 6) {
                        Text(item.time)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("\(item.duration, specifier: "%.2f")s")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
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
    }
}

#Preview {
    ScreenshotView()
        .frame(width: 800, height: 520)
}
