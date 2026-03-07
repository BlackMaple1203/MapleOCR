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

                Group {
                    switch selection {
                    case .screenshot: ScreenshotView()
                    case .batchOCR:   BatchOCRView()
                    case .document:   DocumentView()
                    case .qrcode:     QRCodeView()
                    case .settings:   GlobalConfigsView()
                    case .about:      AboutView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 顶部为无标题栏留出安全区域
                .padding(.top, 1)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .ignoresSafeArea()
    }

    private var sidebarBg: Color {
        colorScheme == .dark
            ? Color(red: 0.105, green: 0.105, blue: 0.114)
            : Color(red: 0.900, green: 0.900, blue: 0.912)
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
