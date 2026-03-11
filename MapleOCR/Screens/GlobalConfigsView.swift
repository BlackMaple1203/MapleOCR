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

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ocr:      return "cpu"
        case .window:   return "macwindow"
        case .shortcut: return "command.square"
        }
    }
}

// MARK: - 全局设置主视图
struct GlobalConfigsView: View {
    @State private var selectedGroup: ConfigGroup = .ocr
    @ObservedObject private var shortcutSettings = ShortcutSettings.shared
    @ObservedObject private var launchAtLoginManager = LaunchAtLoginManager.shared

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
        .onAppear {
            applyAppTheme(theme)
        }
        .onChange(of: theme) { newValue in
            applyAppTheme(newValue)
        }
    }

    // MARK: - 主题应用

    private func applyAppTheme(_ theme: String) {
        switch theme {
        case "浅色":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "深色":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }

    // MARK: - 各分组内容

    @ViewBuilder
    private func configContent(for group: ConfigGroup) -> some View {
        switch group {
        case .ocr:      ocrConfigSection
        case .window:   windowConfigSection
        case .shortcut: shortcutConfigSection
        }
    }

    // MARK: OCR 引擎
    @State private var ocrEngine = "Apple Vision"
    @State private var ocrLanguage = "中文 + English"

    private var ocrConfigSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            formSection("识别引擎") {
                formPicker("引擎", selection: $ocrEngine, options: [
                    "Apple Vision"
                ])
                formPicker("主要语言", selection: $ocrLanguage, options: [
                    "中文 + English"
                ])
            }
        }
    }

    // MARK: 窗口与界面
    @AppStorage("appTheme") private var theme = "跟随系统"
    @State private var alwaysOnTop = false
    @State private var showInDock = true
    @State private var showInMenuBar = true
    @State private var hideOnClose = true

    private var windowConfigSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            formSection("外观") {
                formPicker("主题", selection: $theme, options: ["跟随系统", "浅色", "深色"])
            }

            formSection("启动") {
                formToggle("开机自动启动", icon: "power", isOn: $launchAtLoginManager.isEnabled)
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
