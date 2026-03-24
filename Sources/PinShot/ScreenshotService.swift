import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit

struct CapturedSelection {
    let image: NSImage
    let appKitRect: CGRect
}

enum ScreenshotError: LocalizedError {
    case captureFailed
    case imageLoadFailed

    var errorDescription: String? {
        switch self {
        case .captureFailed:
            return "截图失败，请检查屏幕录制权限"
        case .imageLoadFailed:
            return "截图文件读取失败"
        }
    }
}

@MainActor
final class ScreenshotService {
    private let selectionOverlayService = SelectionOverlayService()

    func captureUserSelection() async throws -> CapturedSelection? {
        guard let selection = await selectionOverlayService.selectArea() else {
            return nil
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw ScreenshotError.captureFailed
        }

        let localRect = CGRect(
            x: selection.appKitRect.minX - selection.screenFrame.minX,
            y: selection.screenFrame.height - (selection.appKitRect.maxY - selection.screenFrame.minY),
            width: selection.appKitRect.width,
            height: selection.appKitRect.height
        )

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = localRect
        configuration.width = Int(selection.appKitRect.width * selection.displayScale)
        configuration.height = Int(selection.appKitRect.height * selection.displayScale)
        configuration.showsCursor = false

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        let image = NSImage(cgImage: cgImage, size: selection.appKitRect.size)
        return CapturedSelection(image: image, appKitRect: selection.appKitRect)
    }
}
