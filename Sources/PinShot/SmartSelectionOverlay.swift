import AppKit
import ApplicationServices

@MainActor
final class SmartSelectionOverlayService {
    private var session: SmartSelectionSession?

    func selectRegion() async -> CGRect? {
        if let session {
            session.cancel()
            return nil
        }
        return await withCheckedContinuation { continuation in
            let value = SmartSelectionSession { [weak self] rect in
                self?.session = nil
                continuation.resume(returning: rect)
            }
            session = value
            value.start()
        }
    }
}

@MainActor
private final class SmartSelectionSession {
    private let onFinish: (CGRect?) -> Void
    private let detector = SmartSelectionDetector()
    private var panels: [SmartSelectionPanel] = []
    private var views: [SmartSelectionView] = []
    private var candidates: [CGRect] = []
    private var candidateIndex = 0
    private var activeRect: CGRect?
    private var didFinish = false

    init(onFinish: @escaping (CGRect?) -> Void) { self.onFinish = onFinish }

    func cancel() {
        finish(nil)
    }

    func start() {
        guard !NSScreen.screens.isEmpty else { finish(nil); return }

        for screen in NSScreen.screens {
            let panel = SmartSelectionPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            let view = SmartSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.screenFrame = screen.frame
            view.onHover = { [weak self] in self?.updateHover(at: $0) }
            view.onDrag = { [weak self] in self?.updateManualSelection($0) }
            view.onComplete = { [weak self] in self?.complete($0) }
            view.onCancel = { [weak self] in self?.finish(nil) }
            view.onCycleCandidate = { [weak self] in self?.cycleCandidate() }
            view.onAcceptCandidate = { [weak self] in self?.complete(self?.activeRect) }

            panel.contentView = view
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.acceptsMouseMovedEvents = true
            panels.append(panel)
            views.append(view)
            panel.orderFrontRegardless()
        }

        let mouse = NSEvent.mouseLocation
        (panels.first { $0.frame.contains(mouse) } ?? panels.first)?.makeKey()
        updateHover(at: mouse)
    }

    private func updateHover(at point: CGPoint) {
        candidates = detector.candidates(at: point)
        candidateIndex = 0
        activeRect = candidates.first
        updateViews(isManual: false)
    }

    private func cycleCandidate() {
        guard !candidates.isEmpty else { return }
        candidateIndex = (candidateIndex + 1) % candidates.count
        activeRect = candidates[candidateIndex]
        updateViews(isManual: false)
    }

    private func updateManualSelection(_ rect: CGRect?) {
        activeRect = rect?.nonEmptySelection
        updateViews(isManual: activeRect != nil)
    }

    private func updateViews(isManual: Bool) {
        for view in views {
            view.selectionRect = activeRect
            view.isManualSelection = isManual
            view.needsDisplay = true
        }
    }

    private func complete(_ rect: CGRect?) {
        let desktop = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        guard let value = rect?.intersection(desktop).nonEmptySelection else { return }
        finish(value)
    }

    private func finish(_ rect: CGRect?) {
        guard !didFinish else { return }
        didFinish = true
        panels.forEach { $0.orderOut(nil); $0.close() }
        panels.removeAll()
        views.removeAll()
        onFinish(rect)
    }
}

private final class SmartSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class SmartSelectionView: NSView {
    var screenFrame: CGRect = .zero
    var selectionRect: CGRect?
    var isManualSelection = false
    var onHover: ((CGPoint) -> Void)?
    var onDrag: ((CGRect?) -> Void)?
    var onComplete: ((CGRect?) -> Void)?
    var onCancel: (() -> Void)?
    var onCycleCandidate: (() -> Void)?
    var onAcceptCandidate: (() -> Void)?

    private var trackingAreaReference: NSTrackingArea?
    private var dragStart: CGPoint?
    private var latestPoint: CGPoint?
    private var didDrag = false

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let value = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(value)
        trackingAreaReference = value
    }

    override func mouseMoved(with event: NSEvent) {
        guard dragStart == nil else { return }
        onHover?(globalPoint(for: event))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = globalPoint(for: event)
        dragStart = point
        latestPoint = point
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = globalPoint(for: event)
        latestPoint = point
        let rect = selection(from: dragStart, to: point)
        if rect.width > 3 || rect.height > 3 {
            didDrag = true
            onDrag?(rect)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; latestPoint = nil; didDrag = false }
        if didDrag, let dragStart {
            onComplete?(selection(from: dragStart, to: latestPoint ?? globalPoint(for: event)))
        } else {
            onComplete?(selectionRect)
        }
    }

    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48: onCycleCandidate?()
        case 36, 76: onAcceptCandidate?()
        case 53: onCancel?()
        default: super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.26).setFill()
        dirtyRect.fill()

        guard let globalRect = selectionRect else {
            drawHint("移动识别 · 拖拽框选 · Esc 或再次按快捷键取消", at: CGPoint(x: 24, y: 24))
            return
        }
        let localRect = CGRect(
            x: globalRect.minX - screenFrame.minX,
            y: globalRect.minY - screenFrame.minY,
            width: globalRect.width,
            height: globalRect.height
        ).intersection(bounds)
        guard !localRect.isNull, localRect.width > 0, localRect.height > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .copy
        NSColor.clear.setFill()
        localRect.fill()
        NSGraphicsContext.restoreGraphicsState()

        let border = NSBezierPath(rect: localRect.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        NSColor.systemBlue.setStroke()
        border.stroke()

        let size = "\(Int(globalRect.width)) × \(Int(globalRect.height))"
        let hint = isManualSelection
            ? "\(size) · 松开鼠标截图"
            : "\(size) · 单击截图 · Tab 切换父级 · 拖拽自由框选 · Esc 取消"
        drawHint(hint, at: CGPoint(x: localRect.minX, y: max(10, localRect.minY - 28)))
    }

    private func selection(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    private func drawHint(_ text: String, at point: CGPoint) {
        NSAttributedString(
            string: "  \(text)  ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.72)
            ]
        ).draw(at: point)
    }

    private func globalPoint(for event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
}

@MainActor
private final class SmartSelectionDetector {
    private struct WindowMatch {
        let pid: pid_t
        let rect: CGRect
    }

    func candidates(at point: CGPoint) -> [CGRect] {
        let windows = windowMatches(at: point)
        var values: [CGRect] = []
        if AXIsProcessTrusted(), let frontmostWindow = windows.first {
            values.append(contentsOf: accessibilityCandidates(at: point, pid: frontmostWindow.pid))
        }
        values.append(contentsOf: windows.map(\.rect))

        let standardized = values.map { $0.standardized }
        let containing = standardized.filter { rect in
            rect.width >= 6 && rect.height >= 6 && rect.contains(point)
        }
        let sorted = containing.sorted { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        }

        var unique: [CGRect] = []
        for rect in sorted {
            if !unique.contains(where: { approximatelyEqual($0, rect) }) { unique.append(rect) }
        }
        return unique
    }

    private func accessibilityCandidates(at point: CGPoint, pid: pid_t) -> [CGRect] {
        let quartz = ScreenCoordinateConverter.appKitToQuartz(CGRect(origin: point, size: .zero)).origin
        let application = AXUIElementCreateApplication(pid)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(application, Float(quartz.x), Float(quartz.y), &hit) == .success,
              let hit else { return [] }

        var elements = [hit]
        var current = hit
        for _ in 0..<8 {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &value) == .success,
                  let value,
                  CFGetTypeID(value) == AXUIElementGetTypeID() else { break }
            let parent = unsafeDowncast(value, to: AXUIElement.self)
            elements.append(parent)
            current = parent
        }
        return elements.compactMap(frame(for:))
    }

    private func frame(for element: AXUIElement) -> CGRect? {
        var positionReference: CFTypeRef?
        var sizeReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionReference) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeReference) == .success,
              let positionReference, let sizeReference,
              CFGetTypeID(positionReference) == AXValueGetTypeID(),
              CFGetTypeID(sizeReference) == AXValueGetTypeID() else { return nil }

        let positionValue = unsafeDowncast(positionReference, to: AXValue.self)
        let sizeValue = unsafeDowncast(sizeReference, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return ScreenCoordinateConverter.quartzToAppKit(CGRect(origin: position, size: size))
    }

    private func windowMatches(at point: CGPoint) -> [WindowMatch] {
        guard let values = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        return values.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int, pid != ownPID,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let quartzRect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            let rect = ScreenCoordinateConverter.quartzToAppKit(quartzRect)
            return rect.contains(point) ? WindowMatch(pid: pid_t(pid), rect: rect) : nil
        }
    }

    private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 2 && abs(lhs.minY - rhs.minY) < 2 &&
        abs(lhs.width - rhs.width) < 2 && abs(lhs.height - rhs.height) < 2
    }
}
