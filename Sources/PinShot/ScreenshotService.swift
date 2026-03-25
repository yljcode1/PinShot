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
    func captureUserSelection() async throws -> CapturedSelection? {
        try await captureUsingSystemSelection()
    }

    private func captureUsingSystemSelection() async throws -> CapturedSelection? {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinShot-\(UUID().uuidString).png")
        let selectionTracker = SelectionGeometryTracker()
        let initialMouseLocation = NSEvent.mouseLocation
        let initialScreen = NSScreen.screens.first(where: { $0.frame.contains(initialMouseLocation) }) ?? NSScreen.main

        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        selectionTracker.start()
        let terminationStatus = try await runSystemSelectionCapture(to: temporaryURL)
        let trackedRect = selectionTracker.finish()

        guard terminationStatus == 0,
              FileManager.default.fileExists(atPath: temporaryURL.path) else {
            return nil
        }

        guard let image = NSImage(contentsOf: temporaryURL),
              let cgImage = image.cgImage else {
            throw ScreenshotError.imageLoadFailed
        }

        let resolvedRect = trackedRect ?? CapturePlacementResolver.inferredRect(
            imagePixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            initialMouseLocation: initialMouseLocation,
            screenVisibleFrame: initialScreen?.visibleFrame,
            screenScale: initialScreen?.backingScaleFactor ?? 1
        )
        let sizedImage = NSImage(cgImage: cgImage, size: resolvedRect.size)
        return CapturedSelection(image: sizedImage, cgImage: cgImage, appKitRect: resolvedRect)
    }

    private func runSystemSelectionCapture(to temporaryURL: URL) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-s", "-x", temporaryURL.path]
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

@MainActor
private final class SelectionGeometryTracker {
    private var pollingTask: Task<Void, Never>?
    private var dragStartPoint: CGPoint?
    private var trackedRect: CGRect?
    private var didFinishDrag = false

    func start() {
        finish()
        didFinishDrag = false

        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                sampleMouseState()
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    @discardableResult
    func finish() -> CGRect? {
        pollingTask?.cancel()
        pollingTask = nil

        defer {
            dragStartPoint = nil
            trackedRect = nil
            didFinishDrag = false
        }

        return trackedRect?.standardized.nonEmpty
    }

    private func sampleMouseState() {
        guard !didFinishDrag else { return }

        let point = NSEvent.mouseLocation
        let isLeftMouseDown = CGEventSource.buttonState(.combinedSessionState, button: .left)

        if isLeftMouseDown {
            if dragStartPoint == nil {
                dragStartPoint = point
                trackedRect = CGRect(origin: point, size: .zero)
            }
            updateTrackedRect(with: point)
            return
        }

        guard dragStartPoint != nil else { return }
        updateTrackedRect(with: point)
        didFinishDrag = true
    }

    private func updateTrackedRect(with point: CGPoint) {
        guard let dragStartPoint else { return }
        trackedRect = CGRect(
            x: min(dragStartPoint.x, point.x),
            y: min(dragStartPoint.y, point.y),
            width: abs(point.x - dragStartPoint.x),
            height: abs(point.y - dragStartPoint.y)
        )
    }
}

private extension CGRect {
    var nonEmpty: CGRect? {
        guard width > 1, height > 1 else { return nil }
        return self
    }
}
