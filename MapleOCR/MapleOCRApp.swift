//
//  MapleOCRApp.swift
//  MapleOCR
//
//  Created by 陈冠韬 on 2026/3/4.
//

import SwiftUI

@main
struct MapleOCRApp: App {
    init() {
        // 启动时恢复保存的主题（此时 NSApp 尚未初始化，需用 NSApplication.shared）
        let theme = UserDefaults.standard.string(forKey: "appTheme") ?? "跟随系统"
        switch theme {
        case "浅色":
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "深色":
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApplication.shared.appearance = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1250, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Navigate") {
                Button("截图识别") {
                    NotificationCenter.default.post(name: .navigateTo, object: nil,
                        userInfo: ["target": SidebarItem.screenshot])
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("批量识别") {
                    NotificationCenter.default.post(name: .navigateTo, object: nil,
                        userInfo: ["target": SidebarItem.batchOCR])
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("文档处理") {
                    NotificationCenter.default.post(name: .navigateTo, object: nil,
                        userInfo: ["target": SidebarItem.document])
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("二维码") {
                    NotificationCenter.default.post(name: .navigateTo, object: nil,
                        userInfo: ["target": SidebarItem.qrcode])
                }
                .keyboardShortcut("4", modifiers: .command)
            }
        }

        // MARK: - 菜单栏图标
        MenuBarExtra("MapleOCR", image: "menubar") {
            Button("打开 MapleOCR") {
                activateApp()
            }
            .keyboardShortcut("o")

            Divider()

            Button("截图识别") {
                activateAndNavigate(to: .screenshot)
            }

            Button("批量识别") {
                activateAndNavigate(to: .batchOCR)
            }

            Button("文档处理") {
                activateAndNavigate(to: .document)
            }

            Button("二维码") {
                activateAndNavigate(to: .qrcode)
            }

            Divider()

            Button("设置") {
                activateAndNavigate(to: .settings)
            }
            .keyboardShortcut(",")

            Divider()

            Button("退出 MapleOCR") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    // MARK: - Helpers

    private func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if NSApplication.shared.windows.filter({ $0.isVisible }).isEmpty {
            // 没有可见窗口时，让系统重新打开主窗口
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    private func activateAndNavigate(to item: SidebarItem) {
        activateApp()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: .navigateTo, object: nil,
                userInfo: ["target": item]
            )
        }
    }
}
