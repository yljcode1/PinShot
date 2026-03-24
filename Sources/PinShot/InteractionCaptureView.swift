import AppKit
import SwiftUI

struct InteractionCaptureView: NSViewRepresentable {
    let onMagnify: (CGFloat) -> Void
    let onPrimaryClick: () -> Void
    let onDoubleClick: () -> Void
    let onSecondaryClick: () -> Void

    func makeNSView(context: Context) -> InteractionNSView {
        let view = InteractionNSView()
        view.onMagnify = onMagnify
        view.onPrimaryClick = onPrimaryClick
        view.onDoubleClick = onDoubleClick
        view.onSecondaryClick = onSecondaryClick
        return view
    }

    func updateNSView(_ nsView: InteractionNSView, context: Context) {
        nsView.onMagnify = onMagnify
        nsView.onPrimaryClick = onPrimaryClick
        nsView.onDoubleClick = onDoubleClick
        nsView.onSecondaryClick = onSecondaryClick
    }
}

final class InteractionNSView: NSView {
    var onMagnify: ((CGFloat) -> Void)?
    var onPrimaryClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?

    private var mouseDownScreenPoint: CGPoint?
    private var mouseDownWindowOrigin: CGPoint?
    private var didDragWindow = false

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
        if abs(deltaX) > 1 || abs(deltaY) > 1 {
            didDragWindow = true
        }

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
}
