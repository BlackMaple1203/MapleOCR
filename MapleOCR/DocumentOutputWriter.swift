//
//  DocumentOutputWriter.swift
//  MapleOCR
//
//  将 OCR 识别结果写入各种输出格式。
//  当前已实现：layered.pdf（双层可搜索 PDF：保留原图 + 透明文字层）
//

import Foundation
import CoreGraphics
import CoreText
import PDFKit
import AppKit

// MARK: - 错误

enum DocumentOutputError: LocalizedError {
    case cannotOpenSource(URL)
    case cannotCreateOutputFile(URL)
    case cannotCreatePDFContext
    case cannotWriteOutputDir(URL)

    var errorDescription: String? {
        switch self {
        case .cannotOpenSource(let u):
            return "无法打开源文件：\(u.lastPathComponent)"
        case .cannotCreateOutputFile(let u):
            return "无法创建输出文件：\(u.path)"
        case .cannotCreatePDFContext:
            return "无法创建 PDF 绘图上下文"
        case .cannotWriteOutputDir(let u):
            return "没有写入权限，请重新选择可写的输出目录。\n路径：\(u.path)"
        }
    }
}

// MARK: - 保存设置（供 DocumentView 传入）

struct SaveSettings {
    /// 用户通过 NSOpenPanel 选择的输出目录 URL（security-scoped）。
    var outputDirURL: URL
    var fileNameFormat: String
    var outputTypes: OutputFileTypes
}

// MARK: - 写入器

enum DocumentOutputWriter {

    // MARK: - 调度入口

    /// 根据 `settings.outputTypes` 选择要生成的文件格式，每种格式写一个文件。
    /// 出错时抛出，调用方负责捕获并展示错误。
    static func writeOutputs(
        sourceURL: URL,
        docItem: DocumentItem,
        pageResults: [(pageIndex: Int, blocks: [OCRTextBlock])],
        settings: SaveSettings
    ) throws {
        guard !pageResults.isEmpty else { return }

        // ── 激活源文件的 security-scoped resource（读取 PDF 页面内容）──────
        let srcAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if srcAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        // ── 确定输出目录 ─────────────────────────────────────────────
        let outputDir = settings.outputDirURL

        // 激活输出目录的 security-scoped resource（沙盒写权限）
        let outAccess = outputDir.startAccessingSecurityScopedResource()
        defer { if outAccess { outputDir.stopAccessingSecurityScopedResource() } }

        try FileManager.default.createDirectory(
            at: outputDir, withIntermediateDirectories: true, attributes: nil
        )

        // ── 生成基础文件名（不含扩展名）────────────────────────────────
        let baseName = resolveBaseName(
            format: settings.fileNameFormat,
            sourceURL: sourceURL,
            rangeStart: docItem.rangeStart,
            rangeEnd: docItem.rangeEnd,
            pageCount: docItem.pageCount
        )

        // ── 按选项写出各格式 ─────────────────────────────────────────
        if settings.outputTypes.pdfLayered && docItem.isPDF {
            let outURL = outputDir.appendingPathComponent(baseName + ".layered.pdf")
            try writeLayeredPDF(
                sourceURL: sourceURL,
                pageResults: pageResults,
                outputURL: outURL
            )
        }

        if settings.outputTypes.pdfOneLayer && docItem.isPDF {
            // TODO: 单层纯文本 PDF（仅文字，无图片）
        }

        if settings.outputTypes.txt {
            let outURL = outputDir.appendingPathComponent(baseName + ".txt")
            try writeTXT(
                pageResults: pageResults,
                sourceName: sourceURL.lastPathComponent,
                outputURL: outURL,
                plain: false
            )
        }

        if settings.outputTypes.txtPlain {
            let outURL = outputDir.appendingPathComponent(baseName + ".p.txt")
            try writeTXT(
                pageResults: pageResults,
                sourceName: sourceURL.lastPathComponent,
                outputURL: outURL,
                plain: true
            )
        }

        if settings.outputTypes.csv {
            let outURL = outputDir.appendingPathComponent(baseName + ".csv")
            try writeCSV(pageResults: pageResults, sourceName: sourceURL.lastPathComponent, outputURL: outURL)
        }

        if settings.outputTypes.jsonl {
            let outURL = outputDir.appendingPathComponent(baseName + ".jsonl")
            try writeJSONL(pageResults: pageResults, sourceName: sourceURL.lastPathComponent, outputURL: outURL)
        }
    }

    // MARK: - Layered PDF（双层可搜索 PDF）

    /// 生成「双层可搜索 PDF」：原页面内容不变，叠加一层不可见文字。
    ///
    /// 实现原理：
    ///   1. 用 `CGPDFDocument` 逐页取出原始 PDF 页面
    ///   2. 通过 `CGContext.drawPDFPage(_:)` 将原页面原样渲染到新 PDF
    ///   3. 将 CGTextDrawingMode 设为 `.invisible`（PDF 文字渲染模式 3：
    ///      文字在视觉上不可见，但写入 PDF 流，支持搜索/选择/复制）
    ///   4. 用 CoreText 按 OCR 识别的位置和字号绘制各文字块
    ///
    /// 坐标系说明：
    ///   - PDF CGContext 与 CGPDFPage 同为左下角原点，单位 pt
    ///   - OCRTextBlock.rect 来自 PDFKit，也是左下角原点——两者一致
    ///   - 注：此实现对页面 rotation ≠ 0 的 PDF 文字定位可能有偏差（不影响搜索）
    static func writeLayeredPDF(
        sourceURL: URL,
        pageResults: [(pageIndex: Int, blocks: [OCRTextBlock])],
        outputURL: URL
    ) throws {
        // 打开原始 PDF（CGPDFDocument 用于取页面内容，保持原始质量）
        guard let sourceCGPDF = CGPDFDocument(sourceURL as CFURL) else {
            throw DocumentOutputError.cannotOpenSource(sourceURL)
        }

        // 先渲染到内存，避免 CGDataConsumer(url:) 在沙盒 / 特殊字符路径下的权限问题
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw DocumentOutputError.cannotCreatePDFContext
        }

        // mediaBox 在 beginPage 前占位；nil 表示延迟到 beginPage 设置
        guard let ctx = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw DocumentOutputError.cannotCreatePDFContext
        }

        // 按页码顺序处理
        let sorted = pageResults.sorted { $0.pageIndex < $1.pageIndex }

        for (pageIndex, blocks) in sorted {
            // CGPDFDocument 页码从 1 开始
            guard let cgPage = sourceCGPDF.page(at: pageIndex + 1) else { continue }

            // 取该页 MediaBox（坐标系原点左下角）
            var mediaBox = cgPage.getBoxRect(.mediaBox)

            // 开始新页，并设置页面尺寸
            ctx.beginPage(mediaBox: &mediaBox)

            // ── Layer 1: 原始页面内容 ─────────────────────────────
            ctx.drawPDFPage(cgPage)

            // ── Layer 2: 不可见文字层 ─────────────────────────────
            drawInvisibleTextLayer(ctx: ctx, blocks: blocks, mediaBox: mediaBox, cgPage: cgPage)

            ctx.endPage()
        }

        ctx.closePDF()

        // 将内存中的 PDF 数据写入目标路径（Data.write 能正确处理沙盒权限及特殊字符路径）
        try (pdfData as Data).write(to: outputURL, options: .atomic)
    }

    // MARK: - 不可见文字绘制

    private static func drawInvisibleTextLayer(
        ctx: CGContext,
        blocks: [OCRTextBlock],
        mediaBox: CGRect,
        cgPage: CGPDFPage
    ) {
        ctx.saveGState()

        // PDF 坐标系（左下角原点）与 CGContext PDF 输出上下文一致，无需翻转 Y 轴。
        // 对有旋转的页面：drawPDFPage 内部已完成旋转，OCR block 的坐标来自 PDFKit
        // 的旋转后空间。对非 0 旋转做简单补偿（搜索仍有效，文字选中范围可能偏移）。
        let rotation = cgPage.rotationAngle
        if rotation != 0 {
            applyPageRotationTransform(ctx: ctx, rotation: rotation, mediaBox: mediaBox)
        }

        // PDF 文字渲染模式 3：不填充、不描边，但写入内容流、支持搜索/复制
        ctx.setTextDrawingMode(.invisible)

        for block in blocks {
            // 字号：取包围盒高度的 75%，最小 6pt（不可见层字号只影响文字流而非显示）
            let fontSize = max(6.0, block.rect.height * 0.75)

            // 使用系统字体以正确处理中文、英文等多语言字符
            let nsFont = NSFont.systemFont(ofSize: fontSize)
            let ctFont = nsFont as CTFont

            let attrStr = NSAttributedString(
                string: block.text,
                attributes: [.font: ctFont]
            )
            let line = CTLineCreateWithAttributedString(attrStr as CFAttributedString)

            // 文字绘制起点：包围盒左下角（PDF baseline ≈ minY）
            ctx.textPosition = CGPoint(x: block.rect.minX, y: block.rect.minY)
            CTLineDraw(line, ctx)
        }

        ctx.restoreGState()
    }

    /// 为旋转页面补偿坐标变换（顺时针旋转角度）。
    private static func applyPageRotationTransform(
        ctx: CGContext,
        rotation: Int32,
        mediaBox: CGRect
    ) {
        let W = mediaBox.width
        let H = mediaBox.height
        switch rotation {
        case 90:
            // 顺时针 90°：页面视觉宽高变为 (H, W)
            // 原始 MediaBox 坐标 (x, y) → 视觉坐标：(y, W - x)
            ctx.translateBy(x: 0, y: W)
            ctx.rotate(by: -.pi / 2)
        case 180:
            ctx.translateBy(x: W, y: H)
            ctx.rotate(by: .pi)
        case 270:
            ctx.translateBy(x: H, y: 0)
            ctx.rotate(by: .pi / 2)
        default:
            break
        }
    }

    // MARK: - TXT 输出

    private static func writeTXT(
        pageResults: [(pageIndex: Int, blocks: [OCRTextBlock])],
        sourceName: String,
        outputURL: URL,
        plain: Bool    // true = 仅文字；false = 标准格式（含页码）
    ) throws {
        var lines: [String] = []
        for (pageIndex, blocks) in pageResults.sorted(by: { $0.pageIndex < $1.pageIndex }) {
            if !plain {
                lines.append("--- \(sourceName)  第 \(pageIndex + 1) 页 ---")
            }
            lines.append(contentsOf: blocks.map(\.text))
            if !plain { lines.append("") }
        }
        let content = lines.joined(separator: "\n")
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    // MARK: - CSV 输出

    private static func writeCSV(
        pageResults: [(pageIndex: Int, blocks: [OCRTextBlock])],
        sourceName: String,
        outputURL: URL
    ) throws {
        var rows: [String] = ["文件名,页码,来源,文字,x,y,宽,高"]
        for (pageIndex, blocks) in pageResults.sorted(by: { $0.pageIndex < $1.pageIndex }) {
            for block in blocks {
                let source = block.source == .native ? "原文本" : "OCR"
                let text   = block.text.replacingOccurrences(of: "\"", with: "\"\"")
                let r      = block.rect
                rows.append("\"\(sourceName)\",\(pageIndex + 1),\(source),\"\(text)\",\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))")
            }
        }
        try rows.joined(separator: "\n").write(to: outputURL, atomically: true, encoding: .utf8)
    }

    // MARK: - JSONL 输出

    private static func writeJSONL(
        pageResults: [(pageIndex: Int, blocks: [OCRTextBlock])],
        sourceName: String,
        outputURL: URL
    ) throws {
        var lines: [String] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = []

        for (pageIndex, blocks) in pageResults.sorted(by: { $0.pageIndex < $1.pageIndex }) {
            for block in blocks {
                let obj: [String: Any] = [
                    "file":   sourceName,
                    "page":   pageIndex + 1,
                    "source": block.source == .native ? "text" : "ocr",
                    "text":   block.text,
                    "box":    [
                        ["x": block.rect.minX, "y": block.rect.minY],
                        ["x": block.rect.maxX, "y": block.rect.minY],
                        ["x": block.rect.maxX, "y": block.rect.maxY],
                        ["x": block.rect.minX, "y": block.rect.maxY],
                    ]
                ]
                if let data = try? JSONSerialization.data(withJSONObject: obj),
                   let line = String(data: data, encoding: .utf8) {
                    lines.append(line)
                }
            }
        }
        try lines.joined(separator: "\n").write(to: outputURL, atomically: true, encoding: .utf8)
    }

    // MARK: - 文件名生成

    /// 将格式字符串中的占位符替换为实际值，返回不含扩展名的文件名。
    static func resolveBaseName(
        format: String,
        sourceURL: URL,
        rangeStart: Int,
        rangeEnd: Int,
        pageCount: Int
    ) -> String {
        var result = format.isEmpty ? "[OCR]_%name%range_%date" : format

        // %name — 原文件名（不含扩展名）
        let nameWithoutExt = sourceURL.deletingPathExtension().lastPathComponent
        result = result.replacingOccurrences(of: "%name", with: nameWithoutExt)

        // %range — 仅当识别范围小于全文档时显示
        let rangeStr: String
        if rangeStart == 1 && rangeEnd == pageCount {
            rangeStr = ""
        } else {
            rangeStr = "(p\(rangeStart)-\(rangeEnd))"
        }
        result = result.replacingOccurrences(of: "%range", with: rangeStr)

        // %date — 当前日期时间
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmm"
        result = result.replacingOccurrences(of: "%date", with: fmt.string(from: Date()))

        // 移除文件名中的非法字符
        let illegal = CharacterSet(charactersIn: "/\\?%*:|\"<>")
        result = result.components(separatedBy: illegal).joined(separator: "_")

        return result.isEmpty ? "OCR_output" : result
    }
}
