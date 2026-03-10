//
//  ScreenshotEngine.swift
//  MapleOCR
//
//  截图 OCR 引擎：屏幕截取、剪贴板读取、Vision OCR
//

import AppKit
import Combine
import CoreGraphics
import ScreenCaptureKit
import UniformTypeIdentifiers
import Vision
import SwiftUI

// MARK: - OCR 结果

struct ScreenshotOCRResult: Identifiable {
    let id = UUID()
    let text: String
    let confidence: Double
    let boxes: [TextBox]
    let duration: Double
    let timestamp: Date
    let sourceImage: NSImage?

    /// 状态码：100 = 成功，101 = 无文字，其他 = 错误
    let code: Int

    struct TextBox: Identifiable {
        let id = UUID()
        let text: String
        let confidence: Float
        /// 归一化坐标（左下角原点，0~1）
        let boundingBox: CGRect
    }
}

// MARK: - 段落合并策略

enum ParagraphStrategy: String, CaseIterable, Identifiable {
    case multiPara   = "多栏-自然段"
    case multiLine   = "多栏-逐行"
    case multiNone   = "多栏-无换行"
    case singlePara  = "单栏-自然段"
    case singleLine  = "单栏-逐行"
    case singleNone  = "单栏-无换行"
    case none        = "不做处理"

    var id: String { rawValue }

    var separator: String {
        switch self {
        case .multiPara, .singlePara: return "\n\n"
        case .multiLine, .singleLine: return "\n"
        case .multiNone, .singleNone, .none: return " "
        }
    }
}

// MARK: - 剪贴板内容类型

enum ClipboardContent {
    case image(NSImage)
    case filePaths([URL])
    case text(String)
    case empty
    case error(String)
}

// MARK: - 截图引擎

@MainActor
final class ScreenshotEngine: ObservableObject {
    static let shared = ScreenshotEngine()

    /// 上一次截图区域（屏幕坐标）
    @Published var lastCaptureRect: CGRect?

    // MARK: 截取全屏（使用 ScreenCaptureKit）

    /// 使用 ScreenCaptureKit 截取主屏幕
    func captureMainScreen() async -> NSImage? {
        print("[DEBUG][ScreenshotEngine] captureMainScreen() - 开始截取主屏幕")
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return nil }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width * 2
            config.height = display.height * 2
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let nsImage = NSImage(cgImage: image, size: NSSize(
                width: CGFloat(display.width),
                height: CGFloat(display.height)
            ))
            print("[DEBUG][ScreenshotEngine] captureMainScreen() - 截取完成，尺寸: \(nsImage.size)")
            return nsImage
        } catch {
            print("[DEBUG][ScreenshotEngine] captureMainScreen() - 截取失败: \(error)")
            return nil
        }
    }

    /// 重复上次截图区域
    func reCapture() -> NSImage? {
        print("[DEBUG][ScreenshotEngine] reCapture() - 上次截图区域: \(String(describing: lastCaptureRect))")
        guard let rect = lastCaptureRect else {
            print("[DEBUG][ScreenshotEngine] reCapture() - 无上次截图记录，取消")
            return nil
        }
        // 使用低层 API 作为后备
        guard let screen = NSScreen.main else { return nil }
        let screenImage = captureScreenViaWindow(screen: screen)
        guard let full = screenImage else { return nil }
        return ScreenshotEngine.shared.cropImage(full, rect: rect)
    }

    /// 通过 NSWindow 方式截取屏幕（后备方案）
    func captureScreenViaWindow(screen: NSScreen) -> NSImage? {
        print("[DEBUG][ScreenshotEngine] captureScreenViaWindow() - 后备截屏方案，屏幕: \(screen.frame)")
        let rect = screen.frame
        let image = NSImage(size: rect.size)
        image.lockFocus()
        NSColor.clear.set()
        NSBezierPath(rect: NSRect(origin: .zero, size: rect.size)).fill()
        image.unlockFocus()
        return image
    }

    // MARK: 裁剪图片

    /// 从图片中裁剪指定区域
    func cropImage(_ image: NSImage, rect: CGRect) -> NSImage? {
        print("[DEBUG][ScreenshotEngine] cropImage() - 裁剪区域: \(rect)，图片尺寸: \(image.size)")
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        let scaledRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.size.width * scaleX,
            height: rect.size.height * scaleY
        )

        guard let cropped = cgImage.cropping(to: scaledRect) else { return nil }
        return NSImage(cgImage: cropped, size: rect.size)
    }

    // MARK: 剪贴板

    /// 获取剪贴板内容
    func getClipboardContent() -> ClipboardContent {
        print("[DEBUG][ScreenshotEngine] getClipboardContent() - 读取剪贴板内容")
        let pb = NSPasteboard.general

        // 图片
        if let imageData = pb.data(forType: .tiff) ?? pb.data(forType: .png),
           let image = NSImage(data: imageData) {
            return .image(image)
        }

        // 文件路径
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            let imageExts: Set<String> = ["png", "jpg", "jpeg", "bmp", "tiff", "tif", "gif", "webp", "heic"]
            let imagePaths = urls.filter { imageExts.contains($0.pathExtension.lowercased()) }
            if imagePaths.isEmpty {
                return .error("剪贴板中无有效图片文件")
            }
            return .filePaths(imagePaths)
        }

        // 文本
        if let text = pb.string(forType: .string), !text.isEmpty {
            return .text(text)
        }

        return .empty
    }

    // MARK: Vision OCR

    /// 对 NSImage 执行 OCR，返回结果
    func performOCR(
        on image: NSImage,
        languages: [String] = ["zh-Hans", "zh-Hant", "en-US", "ja"],
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    ) async -> ScreenshotOCRResult {
        print("[DEBUG][ScreenshotEngine] performOCR(image:) - 开始 OCR，图片尺寸: \(image.size)，识别语言: \(languages)")
        let startTime = Date()

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ScreenshotOCRResult(
                text: "", confidence: 0, boxes: [], duration: 0,
                timestamp: startTime, sourceImage: image, code: 201
            )
        }

        do {
            let boxes = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ScreenshotOCRResult.TextBox], Error>) in
                let request = VNRecognizeTextRequest { req, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                    let textBoxes: [ScreenshotOCRResult.TextBox] = observations.compactMap { obs in
                        guard let top = obs.topCandidates(1).first, !top.string.isEmpty else { return nil }
                        return ScreenshotOCRResult.TextBox(
                            text: top.string,
                            confidence: top.confidence,
                            boundingBox: obs.boundingBox
                        )
                    }
                    continuation.resume(returning: textBoxes)
                }

                request.recognitionLevel = recognitionLevel
                request.usesLanguageCorrection = true
                request.recognitionLanguages = languages

                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            let duration = Date().timeIntervalSince(startTime)

            if boxes.isEmpty {
                return ScreenshotOCRResult(
                    text: "", confidence: 0, boxes: [],
                    duration: duration, timestamp: startTime,
                    sourceImage: image, code: 101
                )
            }

            // 按阅读顺序排序（上→下，左→右）
            let sorted = sortByReadingOrder(boxes)

            // 合并文本
            let fullText = sorted.map(\.text).joined(separator: "\n")

            // 平均置信度
            let avgConfidence = sorted.reduce(0.0) { $0 + Double($1.confidence) } / Double(sorted.count)

            print("[DEBUG][ScreenshotEngine] performOCR(image:) - OCR 完成，识别到 \(sorted.count) 个文字框，置信度: \(String(format: "%.2f", avgConfidence))，耗时: \(String(format: "%.2fs", duration))")
            return ScreenshotOCRResult(
                text: fullText, confidence: avgConfidence, boxes: sorted,
                duration: duration, timestamp: startTime,
                sourceImage: image, code: 100
            )
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return ScreenshotOCRResult(
                text: "OCR 失败：\(error.localizedDescription)",
                confidence: 0, boxes: [],
                duration: duration, timestamp: startTime,
                sourceImage: image, code: 200
            )
        }
    }

    /// 对文件路径执行 OCR
    func performOCR(on url: URL) async -> ScreenshotOCRResult {
        print("[DEBUG][ScreenshotEngine] performOCR(url:) - 文件: \(url.lastPathComponent)")
        guard let image = NSImage(contentsOf: url) else {
            return ScreenshotOCRResult(
                text: "无法加载图片", confidence: 0, boxes: [],
                duration: 0, timestamp: Date(), sourceImage: nil, code: 202
            )
        }
        return await performOCR(on: image)
    }

    // MARK: 文本后处理

    /// 根据策略合并文本
    func formatText(_ boxes: [ScreenshotOCRResult.TextBox], strategy: ParagraphStrategy) -> String {
        print("[DEBUG][ScreenshotEngine] formatText() - 策略: \(strategy.rawValue)，文字框数: \(boxes.count)")
        let sorted = sortByReadingOrder(boxes)

        switch strategy {
        case .none:
            return sorted.map(\.text).joined(separator: " ")

        case .multiLine, .singleLine:
            return sorted.map(\.text).joined(separator: "\n")

        case .multiNone, .singleNone:
            return sorted.map(\.text).joined(separator: " ")

        case .multiPara, .singlePara:
            return mergeIntoParagraphs(sorted)
        }
    }

    // MARK: - 私有方法



    /// 按阅读顺序排序（归一化坐标：y 大→靠上→排前）
    private func sortByReadingOrder(_ boxes: [ScreenshotOCRResult.TextBox]) -> [ScreenshotOCRResult.TextBox] {
        print("[DEBUG][ScreenshotEngine] sortByReadingOrder() - 排序 \(boxes.count) 个文字框")
        return boxes.sorted { a, b in
            let avgH = (a.boundingBox.height + b.boundingBox.height) * 0.5
            let tolerance = max(0.01, avgH * 0.5)
            if abs(a.boundingBox.midY - b.boundingBox.midY) > tolerance {
                return a.boundingBox.midY > b.boundingBox.midY
            }
            return a.boundingBox.minX < b.boundingBox.minX
        }
    }

    /// 智能段落合并：相邻行间距大于行高阈值则视为新段落
    private func mergeIntoParagraphs(_ boxes: [ScreenshotOCRResult.TextBox]) -> String {
        print("[DEBUG][ScreenshotEngine] mergeIntoParagraphs() - 合并 \(boxes.count) 个文字框为自然段")
        guard !boxes.isEmpty else { return "" }

        var paragraphs: [String] = []
        var currentParagraph = boxes[0].text

        for i in 1..<boxes.count {
            let prev = boxes[i - 1]
            let curr = boxes[i]

            let avgH = (prev.boundingBox.height + curr.boundingBox.height) * 0.5
            let gap = prev.boundingBox.minY - curr.boundingBox.maxY  // 归一化坐标

            if gap > avgH * 1.5 {
                // 段间距较大 → 新段落
                paragraphs.append(currentParagraph)
                currentParagraph = curr.text
            } else {
                currentParagraph += "\n" + curr.text
            }
        }
        paragraphs.append(currentParagraph)
        return paragraphs.joined(separator: "\n\n")
    }
}

// MARK: - 静默截图处理器

/// 触发截图 → OCR → 复制到剪贴板，全程不弹出主窗口
@MainActor
final class SilentScreenshotHandler {
    static let shared = SilentScreenshotHandler()

    private let overlayManager = ScreenshotOverlayManager()
    private var hudPanel: NSPanel?

    func capture(mode: SelectionMode = .drag) {
        overlayManager.startCapture(mode: mode, hideMainWindow: false) { [weak self] image in
            guard let self, let image else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await ScreenshotEngine.shared.performOCR(on: image)
                switch result.code {
                case 100:
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                    self.showHUD("已复制 \(result.text.count) 个字符", isSuccess: true)
                case 101:
                    self.showHUD("未识别到文字", isSuccess: false)
                default:
                    self.showHUD("识别失败", isSuccess: false)
                }
            }
        }
    }

    private func showHUD(_ message: String, isSuccess: Bool) {
        hudPanel?.close()
        hudPanel = nil

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}
