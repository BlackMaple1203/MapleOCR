//
//  SidebarButton.swift
//  MapleOCR
//

import SwiftUI

// MARK: - AlDente 风格侧边栏按钮（图标在上，文字在下，橙色药丸高亮）
struct SidebarButton: View {
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            isSelected
                                ? Color.ocr_orange
                                : (isHovered
                                    ? Color(NSColor.labelColor).opacity(0.09)
                                    : Color.clear)
                        )
                        .frame(width: 44, height: 36)
                        .animation(.easeInOut(duration: 0.18), value: isSelected)
                        .animation(.easeInOut(duration: 0.12), value: isHovered)

                    Image(systemName: item.icon)
                        .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : Color(NSColor.labelColor).opacity(0.7))
                        .animation(.easeInOut(duration: 0.15), value: isSelected)
                }

                Text(item.shortLabel)
                    .font(.system(size: 9.5, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(
                        isSelected
                            ? Color.ocr_orange
                            : Color(NSColor.labelColor).opacity(0.55)
                    )
                    .lineLimit(1)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
            .frame(width: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - 颜色扩展
extension Color {
    // AlDente 橙色 #F97316
    static let ocr_orange = Color(red: 0.976, green: 0.451, blue: 0.086)
    // 侧边栏背景
    static let ocr_sidebar  = Color(red: 0.118, green: 0.118, blue: 0.129)
    static let ocr_sidebar_light = Color(red: 0.922, green: 0.922, blue: 0.934)
}
