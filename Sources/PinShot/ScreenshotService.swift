import AppKit
import Foundation

struct CapturedSelection {
    let image: NSImage
    let cgImage: CGImage
    let appKitRect: CGRect
}

enum ScreenshotError: LocalizedError {
    case captureFailed
    case imageLoadFailed

    var errorDescription: String? {
        switch self {
        case .captureFailed:
            return "Screenshot failed, please check Screen Recording permission"
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
        let status = try await runRegionCapture(rect: quartzRect, to: temporaryURL)

        guard status == 0, FileManager.default.fileExists(atPath: temporaryURL.path) else {
            throw ScreenshotError.captureFailed
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

    private func runRegionCapture(rect: CGRect, to url: URL) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = [
                "-x",
                "-R\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))",
                url.path
            ]
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
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
