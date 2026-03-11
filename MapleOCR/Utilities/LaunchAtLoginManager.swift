//
//  LaunchAtLoginManager.swift
//  MapleOCR
//

import ServiceManagement
import SwiftUI
import Combine

/// 管理「开机自动启动」状态，使用 macOS 13+ 的 SMAppService API。
final class LaunchAtLoginManager: ObservableObject {

    static let shared = LaunchAtLoginManager()

    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            do {
                if isEnabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                isEnabled = oldValue
                showToast("开机启动设置失败", isSuccess: false)
            }
        }
    }

    private init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
