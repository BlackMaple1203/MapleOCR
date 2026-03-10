//
//  ContentView.swift
//  MapleOCR
//
//  Created by 陈冠韬 on 2026/3/4.
//

import SwiftUI

// MARK: - 侧边栏条目枚举
enum SidebarItem: String, CaseIterable, Identifiable {
    case screenshot = "截图识别"
    case batchOCR   = "批量识别"
    case document   = "文档处理"
    case qrcode     = "二维码"
    case settings   = "全局设置"
    case about      = "关于"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .screenshot: return "camera.viewfinder"
        case .batchOCR:   return "photo.stack"
        case .document:   return "doc.text.magnifyingglass"
        case .qrcode:     return "qrcode.viewfinder"
        case .settings:   return "gearshape"
        case .about:      return "info.circle"
        }
    }

    /// 侧边栏短标签（两字以内）
    var shortLabel: String {
        switch self {
        case .screenshot: return "截图"
        case .batchOCR:   return "批量"
        case .document:   return "文档"
        case .qrcode:     return "二维码"
        case .settings:   return "设置"
        case .about:      return "关于"
        }
    }

    var isUtility: Bool {
        self == .settings || self == .about
    }
}

// MARK: - 主视图
struct ContentView: View {
    @State private var selection: SidebarItem = .screenshot
    @Environment(\.colorScheme) private var colorScheme

    /// 引用类型，供事件监听闭包读取当前选中页面
    private final class NavRef { var selection: SidebarItem = .screenshot }
    @State private var navRef = NavRef()
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 0) {

            // ── 侧边栏 ──────────────────────────────────────
            ZStack(alignment: .topLeading) {
                // 侧边栏背景（深色/浅色自适应）
                Rectangle()
                    .fill(sidebarBg)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // 顶部留空（为无标题栏窗口控件留出空间）
                    Color.clear.frame(height: 52)

                    // 应用图标
                    Image("AppLogo")
                        .resizable()
                        .frame(width: 40, height: 40)

                    .padding(.bottom, 20)

                    // 功能导航
                    VStack(spacing: 2) {
                        ForEach(SidebarItem.allCases.filter { !$0.isUtility }) { item in
                            SidebarButton(
                                item: item,
                                isSelected: selection == item
                            ) { selection = item }
                        }
                    }

                    Spacer()

                    // 分隔线
                    Capsule()
                        .fill(Color(NSColor.separatorColor).opacity(0.5))
                        .frame(width: 36, height: 1)
                        .padding(.bottom, 8)

                    // 工具导航
                    VStack(spacing: 2) {
                        ForEach(SidebarItem.allCases.filter { $0.isUtility }) { item in
                            SidebarButton(
                                item: item,
                                isSelected: selection == item
                            ) { selection = item }
                        }
                    }
                    .padding(.bottom, 16)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: 72)

            // 细分割线
            Rectangle()
                .fill(Color(NSColor.separatorColor).opacity(0.4))
                .frame(width: 1)
                .ignoresSafeArea()

            // ── 内容区 ──────────────────────────────────────
            ZStack {
                // 内容区背景
                Color(NSColor.controlBackgroundColor)
                    .ignoresSafeArea()

                // 所有页面始终保持在视图树中，切换时仅改变可见性，确保各页面记录不因切换而丢失
                ScreenshotView()
                    .opacity(selection == .screenshot ? 1 : 0)
                    .allowsHitTesting(selection == .screenshot)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 1)

                BatchOCRView()
                    .opacity(selection == .batchOCR ? 1 : 0)
                    .allowsHitTesting(selection == .batchOCR)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 1)

                DocumentView()
                    .opacity(selection == .document ? 1 : 0)
                    .allowsHitTesting(selection == .document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 1)

                QRCodeView()
                    .opacity(selection == .qrcode ? 1 : 0)
                    .allowsHitTesting(selection == .qrcode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 1)

                GlobalConfigsView()
                    .opacity(selection == .settings ? 1 : 0)
                    .allowsHitTesting(selection == .settings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 1)

                AboutView()
                    .opacity(selection == .about ? 1 : 0)
                    .allowsHitTesting(selection == .about)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 1)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .ignoresSafeArea()
        .onChange(of: selection) { newValue in
            navRef.selection = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateTo)) { notif in
            if let item = notif.userInfo?["target"] as? SidebarItem {
                selection = item
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerSilentScreenshotOCR)) { _ in
            SilentScreenshotHandler.shared.capture()
        }
        .onAppear { installShortcutMonitor() }
    }

    private var sidebarBg: Color {
        colorScheme == .dark
            ? Color(red: 0.105, green: 0.105, blue: 0.114)
            : Color(red: 0.900, green: 0.900, blue: 0.912)
    }

    // MARK: - 安装快捷键事件监听

    private func installShortcutMonitor() {
        let ref = navRef
        let settings = ShortcutSettings.shared
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let sel = ref.selection

            // 全局：打开文件/文件夹
            if settings.openFile.matches(event) {
                switch sel {
                case .batchOCR:
                    NotificationCenter.default.post(name: .triggerOpenFileBatch, object: nil)
                    return nil
                case .document:
                    NotificationCenter.default.post(name: .triggerOpenFileDoc, object: nil)
                    return nil
                default: break
                }
            }

            // 全局：开始截图识别
            if settings.startScreenshot.matches(event) {
                switch sel {
                case .screenshot:
                    NotificationCenter.default.post(name: .triggerScreenshotOCR, object: nil)
                    return nil
                case .qrcode:
                    NotificationCenter.default.post(name: .triggerQRScan, object: nil)
                    return nil
                default: break
                }
            }

            // 截图视图：粘贴识别
            if sel == .screenshot && settings.pasteOCR.matches(event) {
                NotificationCenter.default.post(name: .triggerPasteOCR, object: nil)
                return nil
            }

            // 全局：静默截图识别（直接截图→OCR→复制到剪贴板，不弹出窗口）
            if settings.silentScreenshot.matches(event) {
                NotificationCenter.default.post(name: .triggerSilentScreenshotOCR, object: nil)
                return nil
            }

            // 二维码视图：扫描二维码
            if sel == .qrcode && settings.scanQR.matches(event) {
                NotificationCenter.default.post(name: .triggerQRScan, object: nil)
                return nil
            }

            // 界面切换（可自定义）
            let navItems: [(KeyCombo, SidebarItem)] = [
                (settings.navScreenshot, .screenshot),
                (settings.navBatch,      .batchOCR),
                (settings.navDocument,   .document),
                (settings.navQR,         .qrcode),
            ]
            for (combo, target) in navItems where combo.matches(event) {
                NotificationCenter.default.post(
                    name: .navigateTo,
                    object: nil,
                    userInfo: ["target": target]
                )
                return nil
            }

            // 界面切换（固定：⌘, → 设置，⌘I → 关于）
            let cmdOnly = event.modifierFlags.rawValue & KeyCombo.modMask ==
                NSEvent.ModifierFlags.command.rawValue & KeyCombo.modMask
            if cmdOnly {
                if event.keyCode == 43 { // ⌘,
                    NotificationCenter.default.post(
                        name: .navigateTo, object: nil,
                        userInfo: ["target": SidebarItem.settings]
                    )
                    return nil
                }
                if event.keyCode == 34 { // ⌘I
                    NotificationCenter.default.post(
                        name: .navigateTo, object: nil,
                        userInfo: ["target": SidebarItem.about]
                    )
                    return nil
                }
            }

            return event
        }
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    ContentView()
        .preferredColorScheme(.light)
}
