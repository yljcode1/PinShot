import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit

struct CapturedSelection {
    let image: NSImage
    let cgImage: CGImage
    let appKitRect: CGRect
}

struct CapturedSelectionResult {
    let capture: CapturedSelection
    let action: SelectionOverlayAction
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

    func captureUserSelection() async throws -> CapturedSelectionResult? {
        guard let selectionResult = await selectionOverlayService.selectArea() else {
            return nil
        }
        let selection = selectionResult.selection

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
        let capture = CapturedSelection(image: image, cgImage: cgImage, appKitRect: selection.appKitRect)
        return CapturedSelectionResult(capture: capture, action: selectionResult.action)
    }
}
