//
//  AboutView.swift
//  MapleOCR
//

import SwiftUI

struct AboutView: View {
    @State private var showEnvCopied = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private let links: [(String, String, String)] = [
        ("Github", "star.fill", "https://github.com/BlackMaple1203/MapleOCR"),
        ("问题反馈", "exclamationmark.bubble", "https://github.com/BlackMaple1203/MapleOCR/issues"),
        ("更新日志", "clock.arrow.circlepath", "https://github.com/BlackMaple1203/MapleOCR/releases"),
    ]

    var body: some View {
        ZStack {
            Color(NSColor.controlBackgroundColor)

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 32)

                    // ── 应用图标 & 名称 ──
                    VStack(spacing: 10) {
                        Image("AppLogo")
                            .resizable()
                            .frame(width: 100, height: 100)

                        Text("MapleOCR")
                            .font(.system(size: 24, weight: .bold))

                        Text("版本 \(appVersion)")
                            .font(.system(size: 12))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    }

                    Spacer().frame(height: 28)
                    Divider().padding(.horizontal, 48)
                    Spacer().frame(height: 20)

                    // ── 链接 ──
                    VStack(spacing: 8) {
                        ForEach(links, id: \.0) { item in
                            Link(destination: URL(string: item.2)!) {
                                HStack {
                                    Image(systemName: item.1)
                                        .font(.system(size: 14))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 22)
                                    Text(item.0)
                                        .font(.system(size: 13))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color(NSColor.windowBackgroundColor))
                                .cornerRadius(9)
                            }
                        }
                    }
                    .padding(.horizontal, 48)

                    Spacer().frame(height: 20)
                    Divider().padding(.horizontal, 48)
                    Spacer().frame(height: 20)

                    // ── 许可证 ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("许可证")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        Text("MIT License")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 48)

                    Spacer().frame(height: 20)
                    Divider().padding(.horizontal, 48)
                    Spacer().frame(height: 20)

                    // ── 环境信息 ──
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("当前运行环境")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(showEnvCopied ? "已复制 ✓" : "复制") {
                                copyEnvInfo()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(showEnvCopied ? .green : .accentColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            envRow("系统版本", ProcessInfo.processInfo.operatingSystemVersionString)
                            envRow("架构", ProcessInfo.processInfo.processorCount > 0 ?
                                   "\(ProcessInfo.processInfo.processorCount) 核" : "Unknown")
                            envRow("App 版本", appVersion)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                    }
                    .padding(.horizontal, 48)

                    Spacer().frame(height: 40)
                }
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func envRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
        }
    }

    private func copyEnvInfo() {
        let info = """
        App: MapleOCR \(appVersion)
        OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        CPU Cores: \(ProcessInfo.processInfo.processorCount)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
        showEnvCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showEnvCopied = false
        }
    }
}

#Preview {
    AboutView()
        .frame(width: 700, height: 520)
}
