//
//  DocumentOCREngine.swift
//  MapleOCR
//
//  混合 OCR / 原文本 处理引擎
//  策略：
//    1. PDFKit 提取原生矢量文字块（含 rect）→ 标记 source = .native
//    2. 将整页渲染为高分辨率 CGImage
//    3. 对图像跑 Vision OCR，结果坐标映射回 PDF 页面坐标系
//    4. 过滤掉与原生文字块 IoU > 阈值的 Vision 结果（避免重复）
//    5. 合并两类结果，按阅读顺序（上→下，左→右）排序
//

import PDFKit
import Vision
import CoreGraphics
import AppKit

// MARK: - OCR 文本块

struct OCRTextBlock {
    enum Source { case native, vision }

    /// 识别出的文字
    let text: String
    /// 在 PDF 页面坐标系中的包围盒（原点在页面左下角，单位：points）
    let rect: CGRect
    /// 来源
    let source: Source
}

// MARK: - 引擎错误

enum DocumentOCRError: LocalizedError {
    case cannotOpenFile(URL)
    case pageRenderFailed(Int)
    case visionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .cannotOpenFile(let url):
            return "无法打开文件：\(url.lastPathComponent)"
        case .pageRenderFailed(let n):
            return "第 \(n + 1) 页渲染失败"
        case .visionFailed(let e):
            return "Vision OCR 失败：\(e.localizedDescription)"
        }
    }
}

// MARK: - 引擎主体

enum DocumentOCREngine {

    /// 原生文字与 Vision 框发生"重叠"的 IoU 阈值，超过则丢弃 Vision 结果
    static let overlapIoUThreshold: CGFloat = 0.3

    /// 渲染图像时短边最小像素数（过小会降低 Vision 识别准确率）
    static let minRenderEdge: CGFloat = 1080

    /// 处理单个 `PDFPage`，返回按阅读顺序排列的文本块列表及页面坐标系范围。
    /// 可安全在非主线程调用（Vision OCR 本身是同步调用，包装在 async 方法里）。
    static func processPage(
        _ pdfPage: PDFPage,
        mode: ExtractionMode
    ) async throws -> (blocks: [OCRTextBlock], pageRect: CGRect) {

        let pageRect = pdfPage.bounds(for: .mediaBox)

        // ── Step 1: 提取原生文字 ──────────────────────────────────────────
        var native: [OCRTextBlock] = []
        if mode == .mixed || mode == .textOnly {
            native = extractNativeText(page: pdfPage, pageRect: pageRect)
        }

        // 纯文本模式直接返回
        if mode == .textOnly {
            return (blocks: readingOrder(native), pageRect: pageRect)
        }

        // ── Step 2: 渲染页面为图像 ────────────────────────────────────────
        guard let cgImage = renderPage(pdfPage, pageRect: pageRect) else {
            throw DocumentOCRError.pageRenderFailed(0)
        }

        // ── Step 3: Vision OCR ────────────────────────────────────────────
        let vision: [OCRTextBlock]
        do {
            vision = try await runVision(on: cgImage, pageRect: pageRect)
        } catch {
            throw DocumentOCRError.visionFailed(error)
        }

        // 整页强制 OCR
        if mode == .fullPage {
            return (blocks: readingOrder(vision), pageRect: pageRect)
        }

        // 仅 OCR 图片（不含原生文字）
        if mode == .imageOnly {
            return (blocks: readingOrder(vision), pageRect: pageRect)
        }

        // ── Step 4 & 5: 混合模式 —— 过滤重叠，合并排序 ───────────────────
        let filtered = vision.filter { vb in
            !native.contains { nb in iou(vb.rect, nb.rect) > overlapIoUThreshold }
        }
        return (blocks: readingOrder(native + filtered), pageRect: pageRect)
    }

    // MARK: - 处理单张图片文件

    /// 直接对一张图片运行 Vision OCR。
    static func processImage(
        url: URL
    ) async throws -> (blocks: [OCRTextBlock], pageRect: CGRect) {
        guard
            let nsImg = NSImage(contentsOf: url),
            let cgImage = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            throw DocumentOCRError.cannotOpenFile(url)
        }

        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let pageRect = CGRect(x: 0, y: 0, width: w, height: h)
        let blocks = try await runVision(on: cgImage, pageRect: pageRect)
        return (blocks: readingOrder(blocks), pageRect: pageRect)
    }

    // MARK: - 提取 PDFKit 原生文字

    private static func extractNativeText(
        page: PDFPage,
        pageRect: CGRect
    ) -> [OCRTextBlock] {
        guard
            let selection = page.selection(for: pageRect),
            let lines = selection.selectionsByLine() as? [PDFSelection]
        else { return [] }

        return lines.compactMap { line in
            guard
                let text = line.string,
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }

            let rect = line.bounds(for: page)
            return OCRTextBlock(text: text, rect: rect, source: .native)
        }
    }

    // MARK: 渲染 PDF 页面为 CGImage

    private static func renderPage(
        _ page: PDFPage,
        pageRect: CGRect
    ) -> CGImage? {
        let shortEdge = min(pageRect.width, pageRect.height)
        let scale = max(1.0, Self.minRenderEdge / max(shortEdge, 1))
        let imgSize = NSSize(
            width:  ceil(pageRect.width  * scale),
            height: ceil(pageRect.height * scale)
        )

        // PDFPage.thumbnail 正确处理页面旋转、坐标系
        let nsImage = page.thumbnail(of: imgSize, for: .mediaBox)
        var propRect = NSRect(origin: .zero, size: nsImage.size)
        return nsImage.cgImage(forProposedRect: &propRect, context: nil, hints: nil)
    }

    // MARK: - Vision OCR

    /// 对 CGImage 运行 Vision 文字识别，坐标映射到传入的 pageRect空间。
    ///   与 PDF 页面坐标系（原点左下角）一致，因此直接乘以页面宽高即可转换。
    private static func runVision(
        on cgImage: CGImage,
        pageRect: CGRect
    ) async throws -> [OCRTextBlock] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []

                let blocks: [OCRTextBlock] = observations.compactMap { obs in
                    guard
                        let top = obs.topCandidates(1).first,
                        !top.string.isEmpty
                    else { return nil }

                    // 归一化坐标 → PDF 页面坐标（同为左下角原点）
                    let nb = obs.boundingBox
                    let rect = CGRect(
                        x:      nb.minX * pageRect.width,
                        y:      nb.minY * pageRect.height,
                        width:  nb.width  * pageRect.width,
                        height: nb.height * pageRect.height
                    )
                    return OCRTextBlock(text: top.string, rect: rect, source: .vision)
                }

                continuation.resume(returning: blocks)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // 支持中文（简体、繁体）、英文、日文
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja"]

            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - 私有：工具方法

    /// Intersection over Union（两矩形相交面积 / 合并面积）
    private static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull, !inter.isEmpty else { return 0 }
        let ia = inter.width * inter.height
        let ua = a.width * a.height + b.width * b.height - ia
        return ua > 0 ? ia / ua : 0
    }

    /// 按阅读顺序（上→下、左→右）对文本块排序。
    /// PDF 坐标系：Y 值越大越靠上，因此 midY 较大的块排在前面。
    /// 同行容忍度动态计算（与 Umi-OCR 保持一致）：取两块平均高度的 50%，
    /// 且至少为 4pt，避免字号极小时过度合并。
    private static func readingOrder(_ blocks: [OCRTextBlock]) -> [OCRTextBlock] {
        blocks.sorted {
            let avgH = ($0.rect.height + $1.rect.height) * 0.5
            let tolerance = max(4.0, avgH * 0.5)
            if abs($0.rect.midY - $1.rect.midY) > tolerance {
                return $0.rect.midY > $1.rect.midY   // Y 大 → 靠上 → 排前
            }
            return $0.rect.minX < $1.rect.minX       // 同行：X 小 → 靠左 → 排前
        }
    }
}
