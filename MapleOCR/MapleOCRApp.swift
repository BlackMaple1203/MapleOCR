//
//  MapleOCRApp.swift
//  MapleOCR
//
//  Created by 陈冠韬 on 2026/3/4.
//

import SwiftUI

@main
struct MapleOCRApp: App {
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
    }
}
