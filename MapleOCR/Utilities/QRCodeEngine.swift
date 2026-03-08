//
//  QRCodeEngine.swift
//  MapleOCR
//
//  二维码/条码引擎：扫码（Vision）+ 生成（CIFilter）
//  参照 Umi-OCR 的 mission_qrcode.py 实现
//

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

// MARK: - 扫码结果

struct QRScanResult: Identifiable {
    let id = UUID()
    let text: String
    let format: String          // QRCode / Aztec / EAN-13 / ...
    let boundingBox: CGRect     // 归一化坐标（左下原点）
    let confidence: Float
}

// MARK: - 扫码批量结果

struct QRCodeScanOutput: Identifiable {
    let id = UUID()
    let codes: [QRScanResult]
    let sourceImage: NSImage?
    let duration: Double
    let timestamp: Date
    /// 100 = 成功, 101 = 无码, 200+ = 错误
    let code: Int
}

// MARK: - 条码格式（生成用）

enum BarcodeGenerateFormat: String, CaseIterable, Identifiable {
    case qrCode      = "QR Code"
    case aztec        = "Aztec"
    case pdf417       = "PDF417"
    case code128      = "Code128"

    var id: String { rawValue }

    /// 对应的 CIFilter 名称
    var ciFilterName: String {
        switch self {
        case .qrCode:  return "CIQRCodeGenerator"
        case .aztec:   return "CIAztecCodeGenerator"
        case .pdf417:  return "CIPDF417BarcodeGenerator"
        case .code128: return "CICode128BarcodeGenerator"
        }
    }
}

// MARK: - 纠错等级

enum QRErrorCorrection: String, CaseIterable, Identifiable {
    case L = "L"    // 7%
    case M = "M"    // 15%
    case Q = "Q"    // 25%
    case H = "H"    // 30%

    var id: String { rawValue }
}

// MARK: - 二维码引擎

@MainActor
final class QRCodeEngine {
    static let shared = QRCodeEngine()

    private let ciContext = CIContext()

    // MARK: 扫码 - Vision

    /// 对 NSImage 执行条码/二维码扫描
    func scanImage(_ image: NSImage) async -> QRCodeScanOutput {
        let startTime = Date()

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return QRCodeScanOutput(
                codes: [], sourceImage: image, duration: 0,
                timestamp: startTime, code: 201
            )
        }

        do {
            let results = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<[QRScanResult], Error>) in

                let request = VNDetectBarcodesRequest { req, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    let observations = (req.results as? [VNBarcodeObservation]) ?? []
                    let items: [QRScanResult] = observations.compactMap { obs in
                        guard let payload = obs.payloadStringValue, !payload.isEmpty else { return nil }
                        return QRScanResult(
                            text: payload,
                            format: Self.symbologyName(obs.symbology),
                            boundingBox: obs.boundingBox,
                            confidence: obs.confidence
                        )
                    }
                    continuation.resume(returning: items)
                }

                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            let duration = Date().timeIntervalSince(startTime)

            if results.isEmpty {
                return QRCodeScanOutput(
                    codes: [], sourceImage: image,
                    duration: duration, timestamp: startTime, code: 101
                )
            }

            return QRCodeScanOutput(
                codes: results, sourceImage: image,
                duration: duration, timestamp: startTime, code: 100
            )
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return QRCodeScanOutput(
                codes: [], sourceImage: image,
                duration: duration, timestamp: startTime, code: 200
            )
        }
    }

    /// 对文件路径扫码
    func scanFile(_ url: URL) async -> QRCodeScanOutput {
        guard let image = NSImage(contentsOf: url) else {
            return QRCodeScanOutput(
                codes: [], sourceImage: nil, duration: 0,
                timestamp: Date(), code: 202
            )
        }
        return await scanImage(image)
    }

    // MARK: 生成条码

    /// 生成条码/二维码图片
    func generateBarcode(
        text: String,
        format: BarcodeGenerateFormat = .qrCode,
        width: Int = 0,
        height: Int = 0,
        ecLevel: QRErrorCorrection = .M
    ) -> NSImage? {
        guard !text.isEmpty else { return nil }
        guard let data = text.data(using: .utf8) ?? text.data(using: .ascii) else { return nil }

        let filter: CIFilter?

        switch format {
        case .qrCode:
            let qr = CIFilter.qrCodeGenerator()
            qr.message = data
            qr.correctionLevel = ecLevel.rawValue
            filter = qr

        case .aztec:
            let aztec = CIFilter.aztecCodeGenerator()
            aztec.message = data
            filter = aztec

        case .pdf417:
            let pdf = CIFilter.pdf417BarcodeGenerator()
            pdf.message = data
            filter = pdf

        case .code128:
            let code128 = CIFilter.code128BarcodeGenerator()
            code128.message = data
            filter = code128
        }

        guard let ciImage = filter?.outputImage else { return nil }

        // 根据目标尺寸缩放
        let targetW = width > 0 ? CGFloat(width) : 300
        let targetH = height > 0 ? CGFloat(height) : 300
        let scaleX = targetW / ciImage.extent.width
        let scaleY = targetH / ciImage.extent.height
        let scale = min(scaleX, scaleY)

        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }

    // MARK: - 辅助

    /// 将 VNBarcodeSymbology 转为可读名称
    private static func symbologyName(_ symbology: VNBarcodeSymbology) -> String {
        switch symbology {
        case .qr:            return "QR Code"
        case .aztec:         return "Aztec"
        case .pdf417:        return "PDF417"
        case .code128:       return "Code128"
        case .code39:        return "Code39"
        case .code39Checksum:return "Code39"
        case .code39FullASCII: return "Code39"
        case .code39FullASCIIChecksum: return "Code39"
        case .code93:        return "Code93"
        case .code93i:       return "Code93"
        case .ean8:          return "EAN-8"
        case .ean13:         return "EAN-13"
        case .upce:          return "UPC-E"
        case .dataMatrix:    return "DataMatrix"
        case .itf14:         return "ITF-14"
        case .i2of5:         return "I2of5"
        case .i2of5Checksum: return "I2of5"
        default:             return symbology.rawValue
        }
    }
}
