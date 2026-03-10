//
//  GlobalConfigsView.swift
//  MapleOCR
//

import SwiftUI

// MARK: - 设置分组
enum ConfigGroup: String, CaseIterable, Identifiable {
    case ocr       = "OCR 引擎"
    case window    = "窗口与界面"
    case shortcut  = "快捷键"
    case output    = "输出设置"
    case notify    = "通知"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ocr:      return "cpu"
        case .window:   return "macwindow"
        case .shortcut: return "command.square"
        case .output:   return "doc.text"
        case .notify:   return "bell"
        }
    }
}

// MARK: - 全局设置主视图
struct GlobalConfigsView: View {
    @State private var selectedGroup: ConfigGroup = .ocr
    @ObservedObject private var shortcutSettings = ShortcutSettings.shared

    var body: some View {
        HStack(spacing: 0) {
            // ── 左侧：分类列表 ────────────────────────────
            VStack(spacing: 0) {
                Text("全局设置")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(ConfigGroup.allCases) { group in
                            ConfigGroupButton(
                                group: group,
                                isSelected: selectedGroup == group
                            ) {
                                selectedGroup = group
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(width: 176)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .trailing
            )

            // ── 右侧：设置内容 ────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 分组标题
                    HStack(spacing: 8) {
                        Image(systemName: selectedGroup.icon)
                            .font(.system(size: 18))
                            .foregroundColor(.accentColor)
                        Text(selectedGroup.rawValue)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                    Divider()
                        .padding(.horizontal, 24)

                    // 动态内容
                    configContent(for: selectedGroup)
                        .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            ToastOverlay()
                .environmentObject(ToastManager.shared)
        }
    }

    // MARK: - 各分组内容

    @ViewBuilder
    private func configContent(for group: ConfigGroup) -> some View {
        switch group {
        case .ocr:      ocrConfigSection
        case .window:   windowConfigSection
        case .shortcut: shortcutConfigSection
        case .output:   outputConfigSection
        case .notify:   notifyConfigSection
        }
    }

    // MARK: OCR 引擎
    @State private var ocrEngine = "Apple Vision"
    @State private var ocrLanguage = "简体中文 + English"
    @State private var ocrAccuracy = "均衡"

    private var ocrConfigSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            formSection("识别引擎") {
                formPicker("引擎", selection: $ocrEngine, options: [
                    "Apple Vision", "Tesseract"
                ])
                formPicker("主要语言", selection: $ocrLanguage, options: [
                    "简体中文 + English", "繁體中文 + English",
                    "English Only", "日本語", "한국어"
                ])
                formPicker("精度模式", selection: $ocrAccuracy, options: [
                    "快速", "均衡", "精准"
                ])
            }
        }
    }

    // MARK: 窗口与界面
    @State private var theme = "跟随系统"
    @State private var language = "简体中文"
    @State private var alwaysOnTop = false
    @State private var showInDock = true
    @State private var showInMenuBar = true
    @State private var launchAtLogin = false
    @State private var hideOnClose = true

    private var windowConfigSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            formSection("外观") {
                formPicker("主题", selection: $theme, options: ["跟随系统", "浅色", "深色"])
                formPicker("语言", selection: $language, options: [
                    "简体中文", "繁體中文", "English", "日本語"
                ])
            }

            formSection("启动") {
                formToggle("开机自动启动", icon: "power", isOn: $launchAtLogin)
            }
        }
    }

    // MARK: 快捷键

    private var shortcutConfigSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            formSection("全局快捷键") {
                shortcutRecorderRow("打开文件/文件夹",
                    combo: $shortcutSettings.openFile)
                shortcutRecorderRow("开始截图识别",
                    description: "触发截图框选并识别，同样适用于截图二维码扫描",
                    combo: $shortcutSettings.startScreenshot)
            }
            formSection("截图识别") {
                shortcutRecorderRow("粘贴识别",
                    description: "直接识别剪贴板中的图片内容，无需截图",
                    combo: $shortcutSettings.pasteOCR)
                shortcutRecorderRow("重复上次截图",
                    description: "对上一次框选区域重新执行 OCR 识别",
                    combo: $shortcutSettings.repeatScreenshot)
                shortcutRecorderRow("捕获屏幕框选文字",
                    description: "直接进入截图界面，识别结果复制到剪贴板，不弹出app窗口",
                    combo: $shortcutSettings.silentScreenshot)
            }
            formSection("二维码") {
                shortcutRecorderRow("扫描二维码",
                    description: "框选屏幕区域，扫描并解码其中的二维码内容",
                    combo: $shortcutSettings.scanQR)
            }
            formSection("界面切换") {
                shortcutRecorderRow("截图识别",
                    combo: $shortcutSettings.navScreenshot)
                shortcutRecorderRow("批量识别",
                    combo: $shortcutSettings.navBatch)
                shortcutRecorderRow("文档处理",
                    combo: $shortcutSettings.navDocument)
                shortcutRecorderRow("二维码",
                    combo: $shortcutSettings.navQR)
                fixedShortcutRow("全局设置",
                    display: "⌘ ,")
                fixedShortcutRow("关于",
                    display: "⌘ I")
            }

            HStack {
                Spacer()
                Button("恢复默认快捷键") {
                    shortcutSettings.resetDefaults()
                    showToast("快捷键已恢复默认", isSuccess: true)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
    }

    // MARK: 输出设置
    @State private var defaultFormat = "纯文本"
    @State private var lineBreak = "保留换行"
    @State private var addTimestamp = false
    @State private var autoSave = false
    @State private var savePath = "~/Documents/OCR Results"
    @State private var saveFormat = "TXT"

    private var outputConfigSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            formSection("文字处理") {
                formPicker("默认输出格式", selection: $defaultFormat, options: [
                    "纯文本", "Markdown", "自然段落", "竖排转横排"
                ])
                formPicker("换行处理", selection: $lineBreak, options: [
                    "保留换行", "删除换行", "智能合并"
                ])
                formToggle("结果加入时间戳", icon: "clock", isOn: $addTimestamp)
            }

            formSection("自动保存") {
                formToggle("自动保存识别结果", icon: "arrow.down.doc", isOn: $autoSave)
                if autoSave {
                    formRow("保存目录") {
                        HStack {
                            Text(savePath)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("浏览") {}
                                .buttonStyle(.bordered)
                                .font(.system(size: 11))
                        }
                    }
                    formPicker("保存格式", selection: $saveFormat, options: ["TXT", "Markdown", "CSV"])
                }
            }
        }
    }

    // MARK: 通知
    @State private var notifyStyle = "系统通知"
    @State private var notifyOnSuccess = true
    @State private var notifyOnEmpty = true
    @State private var notifyOnError = true
    @State private var notifySound = false

    private var notifyConfigSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            formSection("通知样式") {
                formPicker("通知方式", selection: $notifyStyle, options: [
                    "系统通知", "应用内提示", "不通知"
                ])
                formToggle("通知音效", icon: "speaker.wave.2", isOn: $notifySound)
            }

            formSection("通知时机") {
                formToggle("识别成功时通知", icon: "checkmark.circle", isOn: $notifyOnSuccess)
                formToggle("无文字时通知", icon: "text.badge.minus", isOn: $notifyOnEmpty)
                formToggle("识别失败时通知", icon: "exclamationmark.circle", isOn: $notifyOnError)
            }
        }
    }

    // MARK: - 表单构建辅助

    private func formSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 6)
            VStack(spacing: 0) {
                content()
            }
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
            .padding(.horizontal, 20)
        }
    }

    private func formPicker(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { Text($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 180)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(Divider().padding(.leading, 14), alignment: .bottom)
    }

    private func formToggle(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(Divider().padding(.leading, 14), alignment: .bottom)
    }

    private func formRow<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(Divider().padding(.leading, 14), alignment: .bottom)
    }

    private func shortcutFormRow(_ label: String, description: String = "", binding: Binding<String>) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                if !description.isEmpty {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
            }
            Spacer()
            Text(binding.wrappedValue)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(Divider().padding(.leading, 14), alignment: .bottom)
    }

    private func shortcutRecorderRow(_ label: String, description: String = "", combo: Binding<KeyCombo>) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                if !description.isEmpty {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
            }
            Spacer()
            ShortcutRecorderButton(combo: combo)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(Divider().padding(.leading, 14), alignment: .bottom)
    }

    private func fixedShortcutRow(_ label: String, description: String = "", display: String) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                if !description.isEmpty {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
            }
            Spacer()
            Text(display)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(Divider().padding(.leading, 14), alignment: .bottom)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(Divider().padding(.leading, 14), alignment: .bottom)
    }
}

// MARK: - 设置分组按钮
private struct ConfigGroupButton: View {
    let group: ConfigGroup
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: group.icon)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 18)
                Text(group.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.14)
                            : (isHovered ? Color(NSColor.labelColor).opacity(0.06) : Color.clear)
                    )
            )
            .foregroundColor(isSelected ? .accentColor : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

#Preview {
    GlobalConfigsView()
        .frame(width: 800, height: 520)
}
