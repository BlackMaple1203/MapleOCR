//
//  ScreenshotOverlayWindow.swift
//  MapleOCR
//
//  全屏区域选择覆盖窗口，支持拖动和点击两种模式
//  参考 Umi-OCR 的 ScreenshotWindowComp 实现
//

import AppKit
import ScreenCaptureKit
import SwiftUI

// MARK: - 选择模式

enum SelectionMode: String {
    case drag  = "拖动"
    case click = "点击"
}

// MARK: - 覆盖窗口管理器

@MainActor
final class ScreenshotOverlayManager {

    /// 截图完成回调：传入裁剪后的图片，nil 表示取消
    typealias CompletionHandler = (NSImage?) -> Void

    private var overlayWindows: [ScreenshotOverlayWindow] = []
    private var completion: CompletionHandler?
    private var fullScreenImages: [(displayID: CGDirectDisplayID, image: NSImage)] = []
    /// 截图前保存主窗口引用，orderOut 后 NSApp.mainWindow 会变为 nil
    private weak var savedMainWindow: NSWindow?

    /// 开始截图选择流程
    func startCapture(
        mode: SelectionMode,
        hideMainWindow: Bool = true,
        hideDelay: TimeInterval = 0.2,
        completion: @escaping CompletionHandler
    ) {
        print("[DEBUG][ScreenshotOverlay] startCapture() - 模式: \(mode.rawValue)，隐藏窗口: \(hideMainWindow)，延迟: \(hideDelay)s")
        self.completion = completion

        // 隐藏主窗口（先保存引用，orderOut 后 NSApp.mainWindow 会变 nil）
        savedMainWindow = NSApp.mainWindow
        if hideMainWindow {
            savedMainWindow?.orderOut(nil)
        }

        // 等待窗口隐藏动画完成
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay) { [weak self] in
            self?.captureAndShowOverlays(mode: mode)
        }
    }

    private func captureAndShowOverlays(mode: SelectionMode) {
        print("[DEBUG][ScreenshotOverlay] captureAndShowOverlays() - 开始截取所有屏幕")
        fullScreenImages.removeAll()
        overlayWindows.removeAll()

        // 使用 ScreenCaptureKit 异步截取所有屏幕
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let screens = NSScreen.screens

                for scDisplay in content.displays {
                    // 找到匹配的 NSScreen
                    guard let screen = screens.first(where: {
                        let screenNumber = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
                        return screenNumber == scDisplay.displayID
                    }) else { continue }

                    let displayID = scDisplay.displayID
                    let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    config.width = scDisplay.width * 2
                    config.height = scDisplay.height * 2
                    config.showsCursor = false

                    let cgImage = try await SCScreenshotManager.captureImage(
                        contentFilter: filter,
                        configuration: config
                    )
                    let nsImage = NSImage(cgImage: cgImage, size: screen.frame.size)
                    fullScreenImages.append((displayID: displayID, image: nsImage))

                    // 创建覆盖窗口
                    let window = ScreenshotOverlayWindow(
                        screen: screen,
                        backgroundImage: nsImage,
                        mode: mode,
                        onComplete: { [weak self] rect in
                            self?.handleSelection(rect: rect, screen: screen, displayID: displayID)
                        },
                        onCancel: { [weak self] in
                            self?.cancelCapture()
                        }
                    )
                    overlayWindows.append(window)
                    window.showOverlay()
                }
            } catch {
                print("[DEBUG][ScreenshotOverlay] captureAndShowOverlays() - 截屏失败: \(error)")
                cancelCapture()
            }
        }
    }

    private func handleSelection(rect: CGRect?, screen: NSScreen, displayID: CGDirectDisplayID) {
        print("[DEBUG][ScreenshotOverlay] handleSelection() - 选区: \(String(describing: rect))，屏幕: \(screen.localizedName)")
        // 延迟到下一个 run loop，避免在鼠标事件回调栈中销毁窗口导致崩溃
        DispatchQueue.main.async { [self] in
            self._handleSelectionImpl(rect: rect, screen: screen, displayID: displayID)
        }
    }

    private func _handleSelectionImpl(rect: CGRect?, screen: NSScreen, displayID: CGDirectDisplayID) {
        print("[DEBUG][ScreenshotOverlay] _handleSelectionImpl() - 处理选区: \(String(describing: rect))")

        // 必须在 dismissAll() 之前取出截图数据，否则 fullScreenImages 会被清空
        guard let rect = rect, rect.width > 1, rect.height > 1 else {
            dismissAll()
            completion?(nil)
            showMainWindow()
            return
        }

        // 获取对应屏幕的截图
        guard let pair = fullScreenImages.first(where: { $0.displayID == displayID }) else {
            print("[DEBUG][ScreenshotOverlay] _handleSelectionImpl() - 找不到 displayID=\(displayID) 的截图数据")
            dismissAll()
            completion?(nil)
            showMainWindow()
            return
        }

        dismissAll()

        // 计算裁剪区域（将屏幕坐标转为图片坐标）
        let screenFrame = screen.frame
        let backingScale = screen.backingScaleFactor

        let cropRect = CGRect(
            x: (rect.origin.x - screenFrame.origin.x) * backingScale,
            y: (screenFrame.height - (rect.origin.y - screenFrame.origin.y) - rect.height) * backingScale,
            width: rect.width * backingScale,
            height: rect.height * backingScale
        )

        guard let cgFull = pair.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cgCropped = cgFull.cropping(to: cropRect)
        else {
            completion?(nil)
            showMainWindow()
            return
        }

        let result = NSImage(cgImage: cgCropped, size: rect.size)

        // 保存上次截图区域到引擎
        ScreenshotEngine.shared.lastCaptureRect = CGRect(
            x: rect.origin.x * backingScale,
            y: (screenFrame.height - rect.origin.y - rect.height) * backingScale,
            width: rect.width * backingScale,
            height: rect.height * backingScale
        )

        completion?(result)
        showMainWindow()
    }

    private func cancelCapture() {
        print("[DEBUG][ScreenshotOverlay] cancelCapture() - 用户取消截图")
        DispatchQueue.main.async { [self] in
            self.dismissAll()
            self.completion?(nil)
            self.showMainWindow()
        }
    }

    private func dismissAll() {
        print("[DEBUG][ScreenshotOverlay] dismissAll() - 关闭 \(overlayWindows.count) 个覆盖窗口")
        for window in overlayWindows {
            window.close()
        }
        overlayWindows.removeAll()
        fullScreenImages.removeAll()
    }

    private func showMainWindow() {
        print("[DEBUG][ScreenshotOverlay] showMainWindow() - 恢复主窗口")
        let windowToRestore = savedMainWindow
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            windowToRestore?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - 单个屏幕覆盖窗口

final class ScreenshotOverlayWindow: NSWindow {

    convenience init(
        screen: NSScreen,
        backgroundImage: NSImage,
        mode: SelectionMode,
        onComplete: @escaping (CGRect?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 防止 AppKit 在 close() 时额外 release，避免与 ARC 双重释放导致崩溃
        self.isReleasedWhenClosed = false

        let overlayView = ScreenshotOverlayNSView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            backgroundImage: backgroundImage,
            mode: mode,
            onComplete: onComplete,
            onCancel: onCancel
        )
        self.contentView = overlayView
    }

    func showOverlay() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(contentView)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - 覆盖视图（NSView）

final class ScreenshotOverlayNSView: NSView {
    private let backgroundImage: NSImage
    private let mode: SelectionMode
    private let onComplete: (CGRect?) -> Void
    private let onCancel: () -> Void

    /// 当前选择区域（视图坐标）
    private var selectionRect: CGRect?
    /// 鼠标按下起点
    private var dragStartPoint: CGPoint?
    /// 点击模式第一个点
    private var clickFirstPoint: CGPoint?
    /// 当前鼠标位置
    private var currentMousePoint: CGPoint?
    /// 是否在拖动中
    private var isDragging = false

    // 十字线追踪区
    private var trackingArea: NSTrackingArea?

    // 遮罩颜色
    private let overlayColor = NSColor.black.withAlphaComponent(0.35)
    private let selectionBorderColor = NSColor.white
    private let crosshairColor = NSColor.white.withAlphaComponent(0.6)

    init(
        frame: NSRect,
        backgroundImage: NSImage,
        mode: SelectionMode,
        onComplete: @escaping (CGRect?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.backgroundImage = backgroundImage
        self.mode = mode
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: frame)
        setupTrackingArea()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupTrackingArea() {
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        setupTrackingArea()
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 绘制背景截图
        if let cgImage = backgroundImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.draw(cgImage, in: bounds)
        }

        // 半透明遮罩
        ctx.setFillColor(overlayColor.cgColor)
        ctx.fill(bounds)

        // 选区镂空
        if let sel = selectionRect, sel.width > 0, sel.height > 0 {
            ctx.saveGState()

            // 镂空选区 - 显示原图
            if let cgImage = backgroundImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.clip(to: sel)
                ctx.draw(cgImage, in: bounds)
            }

            ctx.restoreGState()

            // 选区白色边框
            ctx.setStrokeColor(selectionBorderColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(sel)

            // 尺寸标签
            drawSizeLabel(ctx: ctx, in: sel)
        }

        // 十字准星线
        if let point = currentMousePoint {
            drawCrosshair(ctx: ctx, at: point)
        }
    }

    private func drawCrosshair(ctx: CGContext, at point: CGPoint) {
        ctx.saveGState()
        ctx.setStrokeColor(crosshairColor.cgColor)
        ctx.setLineWidth(0.5)
        ctx.setLineDash(phase: 0, lengths: [4, 4])

        // 水平线
        ctx.move(to: CGPoint(x: bounds.minX, y: point.y))
        ctx.addLine(to: CGPoint(x: bounds.maxX, y: point.y))
        ctx.strokePath()

        // 垂直线
        ctx.move(to: CGPoint(x: point.x, y: bounds.minY))
        ctx.addLine(to: CGPoint(x: point.x, y: bounds.maxY))
        ctx.strokePath()

        ctx.restoreGState()
    }

    private func drawSizeLabel(ctx: CGContext, in rect: CGRect) {
        let w = Int(rect.width)
        let h = Int(rect.height)
        let text = "\(w) × \(h)" as NSString
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let labelRect = CGRect(
            x: rect.minX,
            y: rect.minY - size.height - 6,
            width: size.width + 12,
            height: size.height + 4
        )

        // 背景
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        let path = CGPath(roundedRect: labelRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        // 文字
        text.draw(
            at: CGPoint(x: labelRect.minX + 6, y: labelRect.minY + 2),
            withAttributes: attrs
        )
    }

    // MARK: 鼠标事件

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        print("[DEBUG][ScreenshotOverlayNSView] mouseDown() - 位置: \(point)，模式: \(mode.rawValue)")

        switch mode {
        case .drag:
            dragStartPoint = point
            isDragging = true
            selectionRect = CGRect(origin: point, size: .zero)

        case .click:
            if clickFirstPoint == nil {
                clickFirstPoint = point
            } else {
                // 第二次点击完成选择
                let first = clickFirstPoint!
                let sel = rectFromTwoPoints(first, point)
                selectionRect = sel
                clickFirstPoint = nil
                finishSelection()
            }
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .drag, isDragging, let start = dragStartPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        currentMousePoint = current
        selectionRect = rectFromTwoPoints(start, current)
        if let sel = selectionRect {
            print("[DEBUG][ScreenshotOverlayNSView] mouseDragged() - 当前选区: \(Int(sel.width))×\(Int(sel.height))")
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .drag, isDragging else { return }
        isDragging = false

        let current = convert(event.locationInWindow, from: nil)
        if let start = dragStartPoint {
            selectionRect = rectFromTwoPoints(start, current)
        }
        print("[DEBUG][ScreenshotOverlayNSView] mouseUp() - 拖动结束，选区: \(String(describing: selectionRect))")
        finishSelection()
    }

    override func mouseMoved(with event: NSEvent) {
        currentMousePoint = convert(event.locationInWindow, from: nil)

        if mode == .click, let first = clickFirstPoint {
            selectionRect = rectFromTwoPoints(first, currentMousePoint!)
        }

        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        print("[DEBUG][ScreenshotOverlayNSView] rightMouseDown() - 右键取消截图")
        cancelSelection()
    }

    override func keyDown(with event: NSEvent) {
        print("[DEBUG][ScreenshotOverlayNSView] keyDown() - 键码: \(event.keyCode)")
        if event.keyCode == 53 { // ESC
            cancelSelection()
        }
    }

    override var acceptsFirstResponder: Bool { true }

    /// 允许第一次点击直接传递给视图，而不是仅激活窗口
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: 内部

    private func rectFromTwoPoints(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        let x = min(a.x, b.x)
        let y = min(a.y, b.y)
        let w = abs(a.x - b.x)
        let h = abs(a.y - b.y)
        return CGRect(x: x, y: y, width: w, height: h).intersection(bounds)
    }

    private func finishSelection() {
        guard let sel = selectionRect, sel.width > 2, sel.height > 2 else {
            print("[DEBUG][ScreenshotOverlayNSView] finishSelection() - 选区太小，取消")
            cancelSelection()
            return
        }
        // 将视图坐标转换为屏幕坐标
        let screenRect = window?.convertToScreen(sel) ?? sel
        print("[DEBUG][ScreenshotOverlayNSView] finishSelection() - 完成选区: \(Int(screenRect.width))×\(Int(screenRect.height))，位置: \(screenRect.origin)")
        onComplete(screenRect)
    }

    private func cancelSelection() {
        print("[DEBUG][ScreenshotOverlayNSView] cancelSelection() - 取消选择")
        selectionRect = nil
        dragStartPoint = nil
        clickFirstPoint = nil
        isDragging = false
        needsDisplay = true
        onCancel()
    }
}
