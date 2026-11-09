import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PinDragPayload {
    let pngData: Data
    let image: NSImage
    let fileName: String
}

struct InteractionCaptureView: NSViewRepresentable {
    let onMagnify: (CGFloat) -> Void
    let onPrimaryClick: () -> Void
    let onDoubleClick: () -> Void
    let onSecondaryClick: () -> Void
    let dragPayload: () -> PinDragPayload?
    let onExternalDragStateChange: (Bool) -> Void

    func makeNSView(context: Context) -> InteractionNSView {
        let view = InteractionNSView()
        view.onMagnify = onMagnify
        view.onPrimaryClick = onPrimaryClick
        view.onDoubleClick = onDoubleClick
        view.onSecondaryClick = onSecondaryClick
        view.dragPayload = dragPayload
        view.onExternalDragStateChange = onExternalDragStateChange
        return view
    }

    func updateNSView(_ nsView: InteractionNSView, context: Context) {
        nsView.onMagnify = onMagnify
        nsView.onPrimaryClick = onPrimaryClick
        nsView.onDoubleClick = onDoubleClick
        nsView.onSecondaryClick = onSecondaryClick
        nsView.dragPayload = dragPayload
        nsView.onExternalDragStateChange = onExternalDragStateChange
    }
}

final class InteractionNSView: NSView, NSDraggingSource {
    var onMagnify: ((CGFloat) -> Void)?
    var onPrimaryClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?
    var dragPayload: (() -> PinDragPayload?)?
    var onExternalDragStateChange: ((Bool) -> Void)?

    private var mouseDownScreenPoint: CGPoint?
    private var mouseDownWindowOrigin: CGPoint?
    private var didDragWindow = false
    private var dragMode: DragMode = .undecided
    private var filePromiseDelegate: PinPNGFilePromiseDelegate?

    private enum DragMode {
        case undecided
        case movingWindow
        case externalImage
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func magnify(with event: NSEvent) {
        onMagnify?(event.magnification)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        mouseDownScreenPoint = NSEvent.mouseLocation
        mouseDownWindowOrigin = window.frame.origin
        didDragWindow = false
        dragMode = .undecided
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let mouseDownScreenPoint,
              let mouseDownWindowOrigin else {
            return
        }

        let currentPoint = NSEvent.mouseLocation
        let deltaX = currentPoint.x - mouseDownScreenPoint.x
        let deltaY = currentPoint.y - mouseDownScreenPoint.y
        let crossedDragThreshold = hypot(deltaX, deltaY) > 3

        if dragMode == .undecided, crossedDragThreshold {
            if event.modifierFlags.contains(.option) {
                dragMode = .externalImage
                didDragWindow = true
                beginExternalImageDrag(with: event)
                return
            }

            dragMode = .movingWindow
        }

        guard dragMode == .movingWindow else {
            return
        }

        didDragWindow = true

        let nextOrigin = CGPoint(
            x: mouseDownWindowOrigin.x + deltaX,
            y: mouseDownWindowOrigin.y + deltaY
        )
        window.setFrameOrigin(nextOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownScreenPoint = nil
            mouseDownWindowOrigin = nil
            didDragWindow = false
            dragMode = .undecided
        }

        guard !didDragWindow else { return }

        if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            onPrimaryClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onSecondaryClick?()
    }

    override func otherMouseDown(with event: NSEvent) {
        onSecondaryClick?()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        filePromiseDelegate = nil
        onExternalDragStateChange?(false)
    }

    private func beginExternalImageDrag(with event: NSEvent) {
        guard let payload = dragPayload?() else {
            NSSound.beep()
            dragMode = .undecided
            didDragWindow = false
            return
        }

        let promiseDelegate = PinPNGFilePromiseDelegate(
            pngData: payload.pngData,
            fileName: payload.fileName
        )
        let provider = PinImageFilePromiseProvider(
            fileType: UTType.png.identifier,
            delegate: promiseDelegate,
            pngData: payload.pngData,
            tiffData: payload.image.tiffRepresentation
        )

        let draggingItem = NSDraggingItem(pasteboardWriter: provider)
        let preview = PinDragPreview.make(for: payload.image)
        let origin = convert(event.locationInWindow, from: nil)
        draggingItem.setDraggingFrame(
            NSRect(
                x: origin.x - preview.size.width / 2,
                y: origin.y - preview.size.height / 2,
                width: preview.size.width,
                height: preview.size.height
            ),
            contents: preview
        )

        filePromiseDelegate = promiseDelegate
        onExternalDragStateChange?(true)

        let session = beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }
}

/// One dragging item that serves both classes of drop targets: direct image
/// consumers (web upload areas, editors) and promised-file consumers (Finder,
/// shelf apps). Keeping these representations on one item prevents duplicate
/// images in destinations that understand both.
private final class PinImageFilePromiseProvider: NSFilePromiseProvider {
    private let pngData: Data
    private let tiffData: Data?

    init(
        fileType: String,
        delegate: NSFilePromiseProviderDelegate,
        pngData: Data,
        tiffData: Data?
    ) {
        self.pngData = pngData
        self.tiffData = tiffData
        super.init(fileType: fileType, delegate: delegate)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        if !types.contains(.png) {
            types.append(.png)
        }
        if tiffData != nil, !types.contains(.tiff) {
            types.append(.tiff)
        }
        return types
    }

    override func pasteboardPropertyList(
        forType type: NSPasteboard.PasteboardType
    ) -> Any? {
        switch type {
        case .png:
            return pngData
        case .tiff:
            return tiffData
        default:
            return super.pasteboardPropertyList(forType: type)
        }
    }
}

final class PinPNGFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    private let pngData: Data
    private let fileName: String

    init(pngData: Data, fileName: String) {
        self.pngData = pngData
        self.fileName = fileName
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        fileName
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            // AppKit supplies the final filename, including any collision rename.
            try pngData.write(to: url, options: .atomic)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}

private enum PinDragPreview {
    static func make(for image: NSImage) -> NSImage {
        let maximumSide: CGFloat = 220
        let imageSize = image.size
        let scale = min(maximumSide / max(imageSize.width, 1), maximumSide / max(imageSize.height, 1), 1)
        let thumbnailSize = NSSize(
            width: max(48, imageSize.width * scale),
            height: max(48, imageSize.height * scale)
        )
        let badgeHeight: CGFloat = 28
        let outputSize = NSSize(width: thumbnailSize.width, height: thumbnailSize.height + badgeHeight)
        let output = NSImage(size: outputSize)

        output.lockFocus()
        defer { output.unlockFocus() }

        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: outputSize), xRadius: 10, yRadius: 10).fill()
        image.draw(
            in: NSRect(x: 0, y: badgeHeight, width: thumbnailSize.width, height: thumbnailSize.height),
            from: .zero,
            operation: .sourceOver,
            fraction: 0.94
        )

        let label = "PNG  ·  拖出"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let labelSize = label.size(withAttributes: attributes)
        label.draw(
            at: NSPoint(
                x: (outputSize.width - labelSize.width) / 2,
                y: (badgeHeight - labelSize.height) / 2
            ),
            withAttributes: attributes
        )

        return output
    }
}
