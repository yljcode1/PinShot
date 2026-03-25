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
            return "Screenshot failed, please check Screen Recording permission"
        case .imageLoadFailed:
            return "Failed to load captured image"
        }
    }
}

@MainActor
final class ScreenshotService {
    func captureUserSelection(action: SelectionOverlayAction) async throws -> CapturedSelectionResult? {
        guard let capture = try await captureUsingSystemSelection() else {
            return nil
        }
        return CapturedSelectionResult(capture: capture, action: action)
    }

    private func captureUsingSystemSelection() async throws -> CapturedSelection? {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinShot-\(UUID().uuidString).png")
        let initialMouseLocation = NSEvent.mouseLocation
        let initialScreen = NSScreen.screens.first(where: { $0.frame.contains(initialMouseLocation) }) ?? NSScreen.main

        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-x", temporaryURL.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: temporaryURL.path) else {
            return nil
        }

        guard let image = NSImage(contentsOf: temporaryURL),
              let cgImage = image.cgImage else {
            throw ScreenshotError.imageLoadFailed
        }

        let inferredRect = inferCaptureRect(
            image: cgImage,
            initialMouseLocation: initialMouseLocation,
            screen: initialScreen
        )
        let sizedImage = NSImage(cgImage: cgImage, size: inferredRect.size)
        return CapturedSelection(image: sizedImage, cgImage: cgImage, appKitRect: inferredRect)
    }

    private func captureArea(_ rect: CGRect, content: SCShareableContent) async throws -> CGImage {
        let segments = displaySegments(intersecting: rect, content: content)
        guard !segments.isEmpty else {
            throw ScreenshotError.captureFailed
        }

        let outputScale = max(segments.map(\.scale).max() ?? 1, 1)
        let outputWidth = max(Int((rect.width * outputScale).rounded()), 1)
        let outputHeight = max(Int((rect.height * outputScale).rounded()), 1)

        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw ScreenshotError.imageLoadFailed
        }

        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

        for segment in segments {
            let intersection = segment.frame.intersection(rect)
            guard intersection.width > 0, intersection.height > 0 else { continue }

            let localRect = CGRect(
                x: intersection.minX - segment.frame.minX,
                y: segment.frame.height - (intersection.maxY - segment.frame.minY),
                width: intersection.width,
                height: intersection.height
            )

            let configuration = SCStreamConfiguration()
            configuration.sourceRect = localRect
            configuration.width = max(1, Int((intersection.width * segment.scale).rounded()))
            configuration.height = max(1, Int((intersection.height * segment.scale).rounded()))
            configuration.showsCursor = false
            configuration.ignoreGlobalClipDisplay = true

            let filter = SCContentFilter(display: segment.display, excludingApplications: [], exceptingWindows: [])
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            let destinationRect = CGRect(
                x: (intersection.minX - rect.minX) * outputScale,
                y: (intersection.minY - rect.minY) * outputScale,
                width: intersection.width * outputScale,
                height: intersection.height * outputScale
            )
            context.draw(image, in: destinationRect)
        }

        if let image = context.makeImage() {
            return image
        }

        throw ScreenshotError.imageLoadFailed
    }

    private func displaySegments(intersecting rect: CGRect, content: SCShareableContent) -> [DisplaySegment] {
        content.displays.compactMap { display in
            let frame = screenFrame(for: display.displayID) ?? display.frame
            let intersection = frame.intersection(rect)
            guard intersection.width > 0, intersection.height > 0 else {
                return nil
            }
            return DisplaySegment(
                display: display,
                frame: frame,
                scale: max(pointPixelScale(for: display), 1)
            )
        }
    }

    private func screenFrame(for displayID: CGDirectDisplayID) -> CGRect? {
        NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }?.frame
    }

    private func pointPixelScale(for display: SCDisplay) -> CGFloat {
        if let mode = CGDisplayCopyDisplayMode(display.displayID) {
            return CGFloat(mode.pixelWidth) / max(CGFloat(display.width), 1)
        }
        if let screen = NSScreen.screens.first(where: {
            ( $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
        }) {
            return screen.backingScaleFactor
        }
        return 1
    }

    private func pointPixelScale(for rect: CGRect, displays: [DisplaySegment]) -> CGFloat {
        displays
            .max(by: { $0.frame.intersection(rect).area < $1.frame.intersection(rect).area })?
            .scale ?? 1
    }

    private func inferCaptureRect(
        image: CGImage,
        initialMouseLocation: CGPoint,
        screen: NSScreen?
    ) -> CGRect {
        let resolvedScreen = screen ?? NSScreen.main
        let scale = max(resolvedScreen?.backingScaleFactor ?? 1, 1)
        let size = CGSize(
            width: CGFloat(image.width) / scale,
            height: CGFloat(image.height) / scale
        )

        let layoutFrame = resolvedScreen?.visibleFrame
            ?? CGRect(origin: .zero, size: size)
        var origin = CGPoint(
            x: initialMouseLocation.x - size.width / 2,
            y: initialMouseLocation.y - size.height / 2
        )

        origin.x = min(max(origin.x, layoutFrame.minX), max(layoutFrame.maxX - size.width, layoutFrame.minX))
        origin.y = min(max(origin.y, layoutFrame.minY), max(layoutFrame.maxY - size.height, layoutFrame.minY))

        return CGRect(origin: origin, size: size)
    }

}

private struct DisplaySegment {
    let display: SCDisplay
    let frame: CGRect
    let scale: CGFloat
}

private extension CGRect {
    var area: CGFloat {
        width * height
    }
}
