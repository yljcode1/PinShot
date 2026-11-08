import AppKit
import Foundation

struct CapturedSelection {
    let image: NSImage
    let cgImage: CGImage
    let appKitRect: CGRect
}

enum ScreenshotError: LocalizedError {
    case permissionMissing
    case captureFailed(String)
    case imageLoadFailed

    var errorDescription: String? {
        switch self {
        case .permissionMissing:
            return "系统未识别当前 PinShot 的录屏授权。请在系统设置中允许此版本录制屏幕，再退出并重新打开 PinShot。"
        case .captureFailed(let detail):
            return "截图失败：" + detail
        case .imageLoadFailed:
            return "Failed to load captured image"
        }
    }
}

@MainActor
final class ScreenshotService {
    private let selectionService = SmartSelectionOverlayService()

    func captureUserSelection() async throws -> CapturedSelection? {
        guard let appKitRect = await selectionService.selectRegion() else {
            return nil
        }
        return try await capture(rect: appKitRect)
    }

    private func capture(rect appKitRect: CGRect) async throws -> CapturedSelection {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinShot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        try? await Task.sleep(for: .milliseconds(80))
        let quartzRect = ScreenCoordinateConverter.appKitToQuartz(appKitRect).integral
        let (status, detail) = try await runRegionCapture(rect: quartzRect, to: temporaryURL)

        guard status == 0, FileManager.default.fileExists(atPath: temporaryURL.path) else {
            if !CGPreflightScreenCaptureAccess() {
                if !CGRequestScreenCaptureAccess() { throw ScreenshotError.permissionMissing }
            }
            throw ScreenshotError.captureFailed(detail.isEmpty
                ? "系统没有生成图片（退出码 \(status)），请在单个显示器内重新框选。"
                : detail)
        }
        guard let image = NSImage(contentsOf: temporaryURL), let cgImage = image.cgImage else {
            throw ScreenshotError.imageLoadFailed
        }

        return CapturedSelection(
            image: NSImage(cgImage: cgImage, size: appKitRect.size),
            cgImage: cgImage,
            appKitRect: appKitRect
        )
    }

    private func runRegionCapture(rect: CGRect, to url: URL) async throws -> (Int32, String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = [
                "-x",
                "-R\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))",
                url.path
            ]
            let errors = Pipe()
            process.standardError = errors
            process.terminationHandler = {
                let data = errors.fileHandleForReading.readDataToEndOfFile()
                let detail = String(decoding: data.prefix(512), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: ($0.terminationStatus, detail))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum ScreenCoordinateConverter {
    static var primaryScreenTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    static func appKitToQuartz(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenTop - rect.maxY, width: rect.width, height: rect.height)
    }

    static func quartzToAppKit(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenTop - rect.maxY, width: rect.width, height: rect.height)
    }
}

extension CGRect {
    var nonEmptySelection: CGRect? {
        let value = standardized
        guard value.width > 1, value.height > 1 else { return nil }
        return value
    }
}
