import AppKit
import SwiftUI

struct AnnotationOverlayView: NSViewRepresentable {
    @Bindable var appModel: AppModel
    @Bindable var item: CaptureItem
    let onMagnify: (CGFloat) -> Void

    func makeNSView(context: Context) -> AnnotationDrawingView {
        let view = AnnotationDrawingView()
        view.onAppendAnnotation = { annotation in
            item.annotations.append(annotation)
            appModel.refreshCapture(item)
        }
        view.onDeleteAnnotation = { annotationID in
            item.annotations.removeAll { $0.id == annotationID }
            appModel.refreshCapture(item)
        }
        view.onUpdateAnnotation = { annotation in
            guard let index = item.annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
            item.annotations[index] = annotation
            appModel.refreshCapture(item)
        }
        view.onRequestTextTool = {
            item.annotationTool = .text
            item.showToolbar = true
            appModel.refreshCapture(item)
        }
        view.onStatusMessage = { message in
            appModel.statusMessage = message
        }
        view.onMagnify = onMagnify
        view.baseImageSize = item.originalRect.size
        view.baseCGImage = item.cgImage
        return view
    }

    func updateNSView(_ nsView: AnnotationDrawingView, context: Context) {
        nsView.annotations = item.annotations
        nsView.baseImageSize = item.originalRect.size
        nsView.baseCGImage = item.cgImage
        nsView.tool = item.annotationTool
        nsView.annotationColor = item.annotationColor
        nsView.lineWidth = item.annotationLineWidth
        nsView.onAppendAnnotation = { annotation in
            item.annotations.append(annotation)
            appModel.refreshCapture(item)
        }
        nsView.onDeleteAnnotation = { annotationID in
            item.annotations.removeAll { $0.id == annotationID }
            appModel.refreshCapture(item)
        }
        nsView.onUpdateAnnotation = { annotation in
            guard let index = item.annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
            item.annotations[index] = annotation
            appModel.refreshCapture(item)
        }
        nsView.onRequestTextTool = {
            item.annotationTool = .text
            item.showToolbar = true
            appModel.refreshCapture(item)
        }
        nsView.onStatusMessage = { message in
            appModel.statusMessage = message
        }
        nsView.onMagnify = onMagnify
        nsView.isCaptureSelected = appModel.isSelected(item)
        nsView.syncSelectionState()
        nsView.updateActiveTextEditingLayout()
        nsView.needsDisplay = true
    }
}

final class AnnotationDrawingView: NSView, NSTextFieldDelegate {
    private enum TextEditorMetrics {
        static let minWidth: CGFloat = 120
        static let maxWidth: CGFloat = 480
        static let minFontSize: CGFloat = 14
        static let maxFontSize: CGFloat = 96
        static let verticalPadding: CGFloat = 10
        static let handleSize: CGFloat = 18
    }

    private enum TextInteractionMode {
        case none
        case creating
        case moving
        case resizing
    }

    private enum MosaicInteractionMode {
        case none
        case moving
        case resizing
    }

    var annotations: [ImageAnnotation] = []
    var baseImageSize: CGSize = .zero
    var baseCGImage: CGImage?
    var tool: AnnotationTool = .none {
        didSet {
            resetDraft()
            if tool != .text {
                finishTextEditing(commit: true)
                clearTextSelection()
            }
            if tool != .mosaic {
                clearMosaicSelection()
            }
            needsDisplay = true
        }
    }
    var annotationColor: AnnotationColor = .red
    var lineWidth: CGFloat = 3
    var onAppendAnnotation: ((ImageAnnotation) -> Void)?
    var onDeleteAnnotation: ((UUID) -> Void)?
    var onUpdateAnnotation: ((ImageAnnotation) -> Void)?
    var onRequestTextTool: (() -> Void)?
    var onStatusMessage: ((String) -> Void)?
    var onMagnify: ((CGFloat) -> Void)?
    var isCaptureSelected = false {
        didSet {
            ensureKeyboardFocusIfNeeded()
        }
    }

    private var dragStartPoint: CGPoint?
    private var draftPoints: [CGPoint] = []
    private var draftRect: CGRect?
    private var draftArrow: (CGPoint, CGPoint)?
    private var activeTextField: NSTextField?
    private var activeResizeHandle: ResizeHandleView?
    private var activeTextOrigin: CGPoint?
    private var activeTextBaseWidth: CGFloat = 180
    private var activeTextFontSize: CGFloat = 22
    private var activeTextColor: AnnotationColor = .red
    private var activeEditingAnnotationID: UUID?
    private var selectedTextAnnotationID: UUID?
    private var selectedMosaicAnnotationID: UUID?
    private var suppressTextCreationOnNextClick = false
    private var isFinishingTextEditing = false
    private var isActivatingTextField = false
    private var textInteractionMode: TextInteractionMode = .none
    private var textInteractionStartPoint: CGPoint?
    private var textInteractionStartViewPoint: CGPoint?
    private var textInteractionStartAnnotation: ImageAnnotation?
    private var mosaicInteractionMode: MosaicInteractionMode = .none
    private var mosaicInteractionStartViewPoint: CGPoint?
    private var mosaicInteractionStartAnnotation: ImageAnnotation?

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        ensureKeyboardFocusIfNeeded()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let activeResizeHandle, activeResizeHandle.frame.contains(point) {
            return activeResizeHandle
        }
        if let activeTextField, activeTextField.frame.contains(point) {
            return activeTextField
        }
        return tool == .none ? nil : self
    }

    override func magnify(with event: NSEvent) {
        onMagnify?(event.magnification)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleCommandShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleCommandShortcut(event) {
            return
        }
        if handleDeleteShortcut(event) {
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        ensureKeyboardFocusIfNeeded(force: true)
        let viewPoint = convert(event.locationInWindow, from: nil)

        if tool == .text {
            handleTextMouseDown(with: event, at: viewPoint)
            return
        }

        if tool == .mosaic {
            handleMosaicMouseDown(at: viewPoint)
            return
        }

        guard tool != .none else {
            super.mouseDown(with: event)
            return
        }

        let point = normalizedPoint(viewPoint)
        dragStartPoint = point
        draftPoints = [point]
        draftRect = nil
        draftArrow = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)

        if tool == .text {
            handleTextMouseDragged(at: viewPoint)
            return
        }

        if tool == .mosaic {
            handleMosaicMouseDragged(at: viewPoint)
            return
        }

        guard tool != .none, let start = dragStartPoint else {
            super.mouseDragged(with: event)
            return
        }

        let point = normalizedPoint(viewPoint)

        switch tool {
        case .none:
            break
        case .selectText:
            break
        case .pen:
            draftPoints.append(point)
        case .rectangle:
            draftRect = normalizedRect(from: start, to: point)
        case .arrow:
            draftArrow = (start, point)
        case .mosaic:
            draftRect = normalizedRect(from: start, to: point)
        case .text:
            break
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)

        if tool == .text {
            handleTextMouseUp(at: viewPoint)
            return
        }

        if tool == .mosaic {
            handleMosaicMouseUp(at: viewPoint)
            return
        }

        guard tool != .none, let start = dragStartPoint else {
            super.mouseUp(with: event)
            return
        }

        let point = normalizedPoint(viewPoint)
        let annotation: ImageAnnotation?

        switch tool {
        case .none:
            annotation = nil
        case .selectText:
            annotation = nil
        case .pen:
            annotation = draftPoints.count > 1
                ? ImageAnnotation(kind: .freehand(points: draftPoints), color: annotationColor, lineWidth: lineWidth)
                : nil
        case .rectangle:
            let rect = normalizedRect(from: start, to: point)
            annotation = rect.width > 0.01 && rect.height > 0.01
                ? ImageAnnotation(kind: .rectangle(rect), color: annotationColor, lineWidth: lineWidth)
                : nil
        case .arrow:
            annotation = hypot(point.x - start.x, point.y - start.y) > 0.01
                ? ImageAnnotation(kind: .arrow(start: start, end: point), color: annotationColor, lineWidth: lineWidth)
                : nil
        case .mosaic:
            let rect = normalizedRect(from: start, to: point)
            annotation = rect.width > 0.01 && rect.height > 0.01
                ? ImageAnnotation(kind: .mosaic(rect: rect), color: annotationColor, lineWidth: lineWidth)
                : nil
        case .text:
            annotation = nil
        }

        if let annotation {
            onAppendAnnotation?(annotation)
        }

        resetDraft()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()

        for annotation in annotations {
            draw(annotation: annotation, in: context, bounds: bounds)
        }

        if let draft = currentDraftAnnotation {
            draw(annotation: draft, in: context, bounds: bounds)
        }

        if tool == .text, let selectedTextAnnotation {
            drawTextSelection(for: selectedTextAnnotation, in: context)
        }

        if tool == .mosaic, let selectedMosaicAnnotation {
            drawMosaicSelection(for: selectedMosaicAnnotation, in: context)
        }

        context.restoreGState()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finishTextEditing(commit: true)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishTextEditing(commit: false)
            return true
        }
        return false
    }

    override func resignFirstResponder() -> Bool {
        if activeTextField != nil {
            return super.resignFirstResponder()
        }
        finishTextEditing(commit: true)
        return super.resignFirstResponder()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard !isActivatingTextField else { return }
        guard !isFinishingTextEditing else { return }
        guard let field = notification.object as? NSTextField,
              field === activeTextField else {
            return
        }

        let movement = notification.userInfo?["NSTextMovement"] as? Int ?? NSOtherTextMovement
        suppressTextCreationOnNextClick = movement == NSOtherTextMovement
        finishTextEditing(commit: true)
    }

    fileprivate func syncSelectionState() {
        if let selectedTextAnnotationID,
           !annotations.contains(where: { $0.id == selectedTextAnnotationID && $0.textContent != nil }) {
            clearTextSelection()
        }

        if let selectedMosaicAnnotationID,
           !annotations.contains(where: { $0.id == selectedMosaicAnnotationID && $0.mosaicRect != nil }) {
            clearMosaicSelection()
        }
    }

    fileprivate func updateActiveTextEditingLayout() {
        guard let activeTextField, let activeResizeHandle, let activeTextOrigin else { return }

        let frame = textFieldFrame(for: activeTextOrigin)
        activeTextField.frame = frame
        activeTextField.alignment = .left
        activeTextField.font = NSFont.systemFont(ofSize: activeTextFontSize * annotationScale, weight: .semibold)
        activeResizeHandle.frame = CGRect(
            x: frame.maxX - TextEditorMetrics.handleSize * 0.75,
            y: frame.minY - TextEditorMetrics.handleSize * 0.25,
            width: TextEditorMetrics.handleSize,
            height: TextEditorMetrics.handleSize
        )
        activeResizeHandle.needsDisplay = true
    }

    private var currentDraftAnnotation: ImageAnnotation? {
        switch tool {
        case .none:
            return nil
        case .selectText:
            return nil
        case .pen:
            guard draftPoints.count > 1 else { return nil }
            return ImageAnnotation(kind: .freehand(points: draftPoints), color: annotationColor, lineWidth: lineWidth)
        case .rectangle:
            guard let draftRect else { return nil }
            return ImageAnnotation(kind: .rectangle(draftRect), color: annotationColor, lineWidth: lineWidth)
        case .arrow:
            guard let draftArrow else { return nil }
            return ImageAnnotation(kind: .arrow(start: draftArrow.0, end: draftArrow.1), color: annotationColor, lineWidth: lineWidth)
        case .mosaic:
            guard let draftRect else { return nil }
            return ImageAnnotation(kind: .mosaic(rect: draftRect), color: annotationColor, lineWidth: lineWidth)
        case .text:
            return nil
        }
    }

    private var selectedTextAnnotation: ImageAnnotation? {
        guard let selectedTextAnnotationID else { return nil }
        return annotations.first(where: { $0.id == selectedTextAnnotationID })
    }

    private var selectedMosaicAnnotation: ImageAnnotation? {
        guard let selectedMosaicAnnotationID else { return nil }
        return annotations.first(where: { $0.id == selectedMosaicAnnotationID })
    }

    private func handleTextMouseDown(with event: NSEvent, at viewPoint: CGPoint) {
        if activeTextField != nil {
            suppressTextCreationOnNextClick = false
            finishTextEditing(commit: true)
            clearTextSelection()
            return
        }

        if suppressTextCreationOnNextClick {
            suppressTextCreationOnNextClick = false
            clearTextSelection()
            return
        }

        finishTextEditing(commit: true)

        if let selectedTextAnnotation, let handleFrame = textResizeHandleFrame(for: selectedTextAnnotation), handleFrame.contains(viewPoint) {
            beginTextInteraction(.resizing, annotation: selectedTextAnnotation, at: viewPoint)
            return
        }

        if let annotation = textAnnotation(at: viewPoint) {
            selectedTextAnnotationID = annotation.id
            if event.clickCount >= 2 {
                beginTextEditing(for: annotation)
                onStatusMessage?("Editing text: Enter to commit, Esc to cancel")
                needsDisplay = true
                return
            }
            beginTextInteraction(.moving, annotation: annotation, at: viewPoint)
            onStatusMessage?("Text selected: drag to move, drag bottom-right to resize, double-click to edit")
            needsDisplay = true
            return
        }

        selectedTextAnnotationID = nil
        beginTextEditing(at: normalizedPoint(viewPoint))
        onStatusMessage?("Enter text: Enter to commit, Esc to cancel")
        needsDisplay = true
    }

    private func handleTextMouseDragged(at viewPoint: CGPoint) {
        switch textInteractionMode {
        case .none, .creating:
            return
        case .moving:
            updateMovingText(to: viewPoint)
        case .resizing:
            updateResizedText(to: viewPoint)
        }
    }

    private func handleTextMouseUp(at viewPoint: CGPoint) {
        let mode = textInteractionMode

        switch mode {
        case .creating:
            break
        case .moving, .resizing:
            commitTextInteractionIfNeeded()
        case .none:
            break
        }

        resetTextInteraction()
        needsDisplay = true
    }

    private func handleMosaicMouseDown(at viewPoint: CGPoint) {
        finishTextEditing(commit: true)
        clearTextSelection()

        if let selectedMosaicAnnotation,
           let handleFrame = mosaicResizeHandleFrame(for: selectedMosaicAnnotation),
           handleFrame.contains(viewPoint) {
            beginMosaicInteraction(.resizing, annotation: selectedMosaicAnnotation, at: viewPoint)
            onStatusMessage?("Mosaic selected: drag handle to resize, Delete to remove")
            needsDisplay = true
            return
        }

        if let annotation = mosaicAnnotation(at: viewPoint) {
            selectedMosaicAnnotationID = annotation.id
            beginMosaicInteraction(.moving, annotation: annotation, at: viewPoint)
            onStatusMessage?("Mosaic selected: drag to move, drag handle to resize, Delete to remove")
            needsDisplay = true
            return
        }

        clearMosaicSelection()
        let point = normalizedPoint(viewPoint)
        dragStartPoint = point
        draftPoints = [point]
        draftRect = nil
        draftArrow = nil
        needsDisplay = true
    }

    private func handleMosaicMouseDragged(at viewPoint: CGPoint) {
        switch mosaicInteractionMode {
        case .moving:
            updateMovingMosaic(to: viewPoint)
        case .resizing:
            updateResizingMosaic(to: viewPoint)
        case .none:
            guard let start = dragStartPoint else { return }
            let point = normalizedPoint(viewPoint)
            draftRect = normalizedRect(from: start, to: point)
            needsDisplay = true
        }
    }

    private func handleMosaicMouseUp(at viewPoint: CGPoint) {
        switch mosaicInteractionMode {
        case .moving:
            commitMosaicInteractionIfNeeded()
            resetMosaicInteraction()
            needsDisplay = true
            return
        case .resizing:
            commitMosaicInteractionIfNeeded()
            resetMosaicInteraction()
            needsDisplay = true
            return
        case .none:
            break
        }

        guard let start = dragStartPoint else {
            resetDraft()
            needsDisplay = true
            return
        }

        let point = normalizedPoint(viewPoint)
        let rect = normalizedRect(from: start, to: point)
        let annotation = rect.width > 0.01 && rect.height > 0.01
            ? ImageAnnotation(kind: .mosaic(rect: rect), color: annotationColor, lineWidth: lineWidth)
            : nil

        if let annotation {
            selectedMosaicAnnotationID = annotation.id
            onAppendAnnotation?(annotation)
            onStatusMessage?("Mosaic added: drag to move, drag handle to resize, Delete to remove")
        }

        resetDraft()
        needsDisplay = true
    }

    private func beginTextInteraction(_ mode: TextInteractionMode, annotation: ImageAnnotation?, at viewPoint: CGPoint) {
        textInteractionMode = mode
        textInteractionStartPoint = normalizedPoint(viewPoint)
        textInteractionStartViewPoint = viewPoint
        textInteractionStartAnnotation = annotation
    }

    private func beginMosaicInteraction(_ mode: MosaicInteractionMode, annotation: ImageAnnotation, at viewPoint: CGPoint) {
        mosaicInteractionMode = mode
        mosaicInteractionStartViewPoint = viewPoint
        mosaicInteractionStartAnnotation = annotation
    }

    private func resetTextInteraction() {
        textInteractionMode = .none
        textInteractionStartPoint = nil
        textInteractionStartViewPoint = nil
        textInteractionStartAnnotation = nil
    }

    private func resetMosaicInteraction() {
        mosaicInteractionMode = .none
        mosaicInteractionStartViewPoint = nil
        mosaicInteractionStartAnnotation = nil
    }

    private func commitTextInteractionIfNeeded() {
        guard let original = textInteractionStartAnnotation,
              let current = annotations.first(where: { $0.id == original.id }) else { return }
        guard current != original else { return }
        onUpdateAnnotation?(current)
    }

    private func commitMosaicInteractionIfNeeded() {
        guard let original = mosaicInteractionStartAnnotation,
              let current = annotations.first(where: { $0.id == original.id }) else { return }
        guard current != original else { return }
        onUpdateAnnotation?(current)
    }

    private func updateMovingText(to viewPoint: CGPoint) {
        guard let startViewPoint = textInteractionStartViewPoint,
              let original = textInteractionStartAnnotation,
              let text = original.textContent,
              let origin = original.textOrigin else { return }

        let textSize = renderedTextSize(content: text, fontSize: original.fontSize)
        let originalOrigin = denormalizedPoint(origin, in: bounds)
        let candidate = CGPoint(
            x: originalOrigin.x + (viewPoint.x - startViewPoint.x),
            y: originalOrigin.y + (viewPoint.y - startViewPoint.y)
        )
        let clamped = clampedOrigin(for: text, fontSize: original.fontSize, candidate: candidate)

        var updated = original
        updated.kind = .text(content: text, origin: normalizedPoint(clamped))
        replaceLocal(annotation: updated)
        selectedTextAnnotationID = updated.id
        needsDisplay = true
        _ = textSize
    }

    private func updateResizedText(to viewPoint: CGPoint) {
        guard let startViewPoint = textInteractionStartViewPoint,
              let original = textInteractionStartAnnotation,
              let text = original.textContent,
              let origin = original.textOrigin else { return }

        let deltaWidth = viewPoint.x - startViewPoint.x
        let deltaHeight = startViewPoint.y - viewPoint.y
        let scale = max(annotationScale, 0.001)
        let adjustment = (deltaWidth + deltaHeight) / (2 * scale)

        var updated = original
        updated.fontSize = min(
            TextEditorMetrics.maxFontSize,
            max(TextEditorMetrics.minFontSize, original.fontSize + adjustment)
        )
        updated.kind = .text(content: text, origin: normalizedPoint(clampedOrigin(for: text, fontSize: updated.fontSize, candidate: denormalizedPoint(origin, in: bounds))))
        replaceLocal(annotation: updated)
        selectedTextAnnotationID = updated.id
        needsDisplay = true
    }

    private func updateMovingMosaic(to viewPoint: CGPoint) {
        guard let startViewPoint = mosaicInteractionStartViewPoint,
              let original = mosaicInteractionStartAnnotation,
              let rect = original.mosaicRect else { return }

        let originalFrame = denormalizedRect(rect, in: bounds)
        let candidate = originalFrame.offsetBy(
            dx: viewPoint.x - startViewPoint.x,
            dy: viewPoint.y - startViewPoint.y
        )
        let clampedFrame = clampedMosaicFrame(candidate)

        var updated = original
        updated.kind = .mosaic(rect: normalizedRect(clampedFrame, in: bounds))
        replaceLocal(annotation: updated)
        selectedMosaicAnnotationID = updated.id
        needsDisplay = true
    }

    private func updateResizingMosaic(to viewPoint: CGPoint) {
        guard let original = mosaicInteractionStartAnnotation,
              let rect = original.mosaicRect else { return }

        let originalFrame = denormalizedRect(rect, in: bounds)
        let minSize = max(TextEditorMetrics.handleSize, 18)
        let clampedMaxX = min(max(originalFrame.minX + minSize, viewPoint.x), bounds.width)
        let clampedMinY = min(max(0, viewPoint.y), originalFrame.maxY - minSize)

        var updated = original
        updated.kind = .mosaic(rect: normalizedRect(
            CGRect(
                x: originalFrame.minX,
                y: clampedMinY,
                width: clampedMaxX - originalFrame.minX,
                height: originalFrame.maxY - clampedMinY
            ),
            in: bounds
        ))
        replaceLocal(annotation: updated)
        selectedMosaicAnnotationID = updated.id
        needsDisplay = true
    }

    private func replaceLocal(annotation: ImageAnnotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
    }

    private func draw(annotation: ImageAnnotation, in context: CGContext, bounds: CGRect) {
        context.setStrokeColor(annotation.color.nsColor.cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.kind {
        case .freehand(let points):
            guard let first = points.first else { return }
            context.beginPath()
            context.move(to: denormalizedPoint(first, in: bounds))
            for point in points.dropFirst() {
                context.addLine(to: denormalizedPoint(point, in: bounds))
            }
            context.strokePath()

        case .rectangle(let rect):
            let frame = denormalizedRect(rect, in: bounds)
            context.stroke(frame)

        case .arrow(let start, let end):
            let startPoint = denormalizedPoint(start, in: bounds)
            let endPoint = denormalizedPoint(end, in: bounds)
            context.beginPath()
            context.move(to: startPoint)
            context.addLine(to: endPoint)
            addArrowHead(to: context, start: startPoint, end: endPoint, lineWidth: annotation.lineWidth)
            context.strokePath()

        case .mosaic(let rect):
            let frame = denormalizedRect(rect, in: bounds)
            var drewMosaic = false
            if let baseCGImage,
               let mosaicImage = MosaicRenderer.makeImage(baseCGImage: baseCGImage, normalizedRect: rect) {
                context.saveGState()
                context.interpolationQuality = .none
                context.draw(mosaicImage, in: frame)
                context.restoreGState()
                drewMosaic = true
            }
            if !drewMosaic {
                context.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
                context.fill(frame)
            }
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(1.2)
            context.stroke(frame)

        case .text(let content, let origin):
            let point = denormalizedPoint(origin, in: bounds)
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: annotation.color.nsColor,
                .font: NSFont.systemFont(ofSize: annotation.fontSize * annotationScale, weight: .semibold)
            ]
            NSAttributedString(string: content, attributes: attributes).draw(at: point)
        }
    }

    private func drawTextSelection(for annotation: ImageAnnotation, in context: CGContext) {
        guard let selectionFrame = textSelectionFrame(for: annotation) else { return }

        context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.08).cgColor)
        context.addPath(CGPath(roundedRect: selectionFrame, cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.fillPath()

        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.92).cgColor)
        context.setLineWidth(1.6)
        context.addPath(CGPath(roundedRect: selectionFrame, cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.strokePath()

        guard let handleFrame = textResizeHandleFrame(for: annotation) else { return }
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fillEllipse(in: handleFrame)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: handleFrame.insetBy(dx: 0.5, dy: 0.5))
    }

    private func drawMosaicSelection(for annotation: ImageAnnotation, in context: CGContext) {
        guard let selectionFrame = mosaicSelectionFrame(for: annotation) else { return }

        context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.10).cgColor)
        context.fill(selectionFrame)

        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.95).cgColor)
        context.setLineWidth(2)
        context.stroke(selectionFrame.insetBy(dx: 1, dy: 1))

        guard let handleFrame = mosaicResizeHandleFrame(for: annotation) else { return }
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fillEllipse(in: handleFrame)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: handleFrame.insetBy(dx: 0.5, dy: 0.5))
    }

    private func addArrowHead(to context: CGContext, start: CGPoint, end: CGPoint, lineWidth: CGFloat) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(10, lineWidth * 4)
        let left = CGPoint(
            x: end.x - headLength * cos(angle - .pi / 6),
            y: end.y - headLength * sin(angle - .pi / 6)
        )
        let right = CGPoint(
            x: end.x - headLength * cos(angle + .pi / 6),
            y: end.y - headLength * sin(angle + .pi / 6)
        )
        context.move(to: end)
        context.addLine(to: left)
        context.move(to: end)
        context.addLine(to: right)
    }

    private func normalizedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(1, max(0, point.x / max(bounds.width, 1))),
            y: min(1, max(0, point.y / max(bounds.height, 1)))
        )
    }

    private func denormalizedPoint(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
        CGPoint(x: point.x * bounds.width, y: point.y * bounds.height)
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
    }

    private func denormalizedRect(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * bounds.width,
            y: rect.minY * bounds.height,
            width: rect.width * bounds.width,
            height: rect.height * bounds.height
        )
    }

    private func normalizedRect(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(
            x: min(1, max(0, rect.minX / max(bounds.width, 1))),
            y: min(1, max(0, rect.minY / max(bounds.height, 1))),
            width: min(1, max(0, rect.width / max(bounds.width, 1))),
            height: min(1, max(0, rect.height / max(bounds.height, 1)))
        )
    }

    private func resetDraft() {
        dragStartPoint = nil
        draftPoints.removeAll()
        draftRect = nil
        draftArrow = nil
    }

    private func handleCommandShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch key {
        case "c":
            return copySelectedTextToPasteboard()
        case "v":
            return pasteClipboardText()
        default:
            return false
        }
    }

    private func handleDeleteShortcut(_ event: NSEvent) -> Bool {
        guard activeTextField == nil, isDeleteEvent(event) else {
            return false
        }

        if tool == .text, let selectedTextAnnotationID {
            onDeleteAnnotation?(selectedTextAnnotationID)
            clearTextSelection()
            onStatusMessage?("Text annotation deleted")
            return true
        }

        if tool == .mosaic, let selectedMosaicAnnotationID {
            onDeleteAnnotation?(selectedMosaicAnnotationID)
            clearMosaicSelection()
            onStatusMessage?("Mosaic deleted")
            return true
        }

        return false
    }

    private func isDeleteEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == 51 || event.keyCode == 117 {
            return true
        }

        guard let characters = event.charactersIgnoringModifiers else {
            return false
        }

        return characters.contains("\u{8}") || characters.contains("\u{7F}")
    }

    private func ensureKeyboardFocusIfNeeded(force: Bool = false) {
        guard isCaptureSelected, activeTextField == nil else { return }
        guard force || window?.firstResponder !== self else { return }
        window?.makeFirstResponder(self)
    }

    private func copySelectedTextToPasteboard() -> Bool {
        guard let text = selectedTextAnnotation?.textContent, !text.isEmpty else {
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        onStatusMessage?("Text annotation copied")
        return true
    }

    private func pasteClipboardText() -> Bool {
        guard let pastedText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !pastedText.isEmpty else {
            NSSound.beep()
            onStatusMessage?("Clipboard has no text to paste")
            return true
        }

        finishTextEditing(commit: true)
        onRequestTextTool?()

        let fontSize: CGFloat = 22
        let origin = normalizedPoint(preferredPasteOrigin(for: pastedText, fontSize: fontSize))
        let annotation = ImageAnnotation(
            kind: .text(content: pastedText, origin: origin),
            color: annotationColor,
            lineWidth: lineWidth,
            fontSize: fontSize
        )
        selectedTextAnnotationID = annotation.id
        onAppendAnnotation?(annotation)
        onStatusMessage?("Pasted clipboard text onto the pin")
        ensureKeyboardFocusIfNeeded(force: true)
        return true
    }

    private func clearTextSelection() {
        selectedTextAnnotationID = nil
        resetTextInteraction()
        needsDisplay = true
    }

    private func clearMosaicSelection() {
        selectedMosaicAnnotationID = nil
        resetMosaicInteraction()
        needsDisplay = true
    }

    private func textAnnotation(at viewPoint: CGPoint) -> ImageAnnotation? {
        annotations.reversed().first { annotation in
            guard annotation.textContent != nil, let frame = textSelectionFrame(for: annotation) else { return false }
            return frame.contains(viewPoint)
        }
    }

    private func mosaicAnnotation(at viewPoint: CGPoint) -> ImageAnnotation? {
        annotations.reversed().first { annotation in
            guard let frame = mosaicSelectionFrame(for: annotation) else { return false }
            return frame.contains(viewPoint)
        }
    }

    private func textSelectionFrame(for annotation: ImageAnnotation) -> CGRect? {
        guard let content = annotation.textContent, let origin = annotation.textOrigin else { return nil }
        let point = denormalizedPoint(origin, in: bounds)
        let size = renderedTextSize(content: content, fontSize: annotation.fontSize)
        return CGRect(x: point.x - 6, y: point.y - 4, width: size.width + 12, height: size.height + 8)
    }

    private func textResizeHandleFrame(for annotation: ImageAnnotation) -> CGRect? {
        guard let frame = textSelectionFrame(for: annotation) else { return nil }
        return CGRect(
            x: frame.maxX - TextEditorMetrics.handleSize * 0.5,
            y: frame.minY - TextEditorMetrics.handleSize * 0.35,
            width: TextEditorMetrics.handleSize,
            height: TextEditorMetrics.handleSize
        )
    }

    private func mosaicSelectionFrame(for annotation: ImageAnnotation) -> CGRect? {
        guard let rect = annotation.mosaicRect else { return nil }
        return denormalizedRect(rect, in: bounds)
    }

    private func mosaicResizeHandleFrame(for annotation: ImageAnnotation) -> CGRect? {
        guard let frame = mosaicSelectionFrame(for: annotation) else { return nil }
        return CGRect(
            x: frame.maxX - TextEditorMetrics.handleSize * 0.5,
            y: frame.minY - TextEditorMetrics.handleSize * 0.35,
            width: TextEditorMetrics.handleSize,
            height: TextEditorMetrics.handleSize
        )
    }

    private func renderedTextSize(content: String, fontSize: CGFloat) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize * annotationScale, weight: .semibold)
        ]
        let rawSize = NSAttributedString(string: content, attributes: attributes).size()
        return CGSize(width: ceil(rawSize.width), height: ceil(rawSize.height))
    }

    private func clampedOrigin(for content: String, fontSize: CGFloat, candidate: CGPoint) -> CGPoint {
        let size = renderedTextSize(content: content, fontSize: fontSize)
        let maxX = max(0, bounds.width - size.width)
        let maxY = max(0, bounds.height - size.height)
        return CGPoint(
            x: min(max(0, candidate.x), maxX),
            y: min(max(0, candidate.y), maxY)
        )
    }

    private func preferredPasteOrigin(for content: String, fontSize: CGFloat) -> CGPoint {
        let defaultPoint = CGPoint(x: bounds.midX * 0.72, y: bounds.midY)

        guard let window else {
            return clampedOrigin(for: content, fontSize: fontSize, candidate: defaultPoint)
        }

        let pointer = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let candidate = bounds.contains(pointer) ? pointer : defaultPoint
        return clampedOrigin(for: content, fontSize: fontSize, candidate: candidate)
    }

    private func clampedMosaicFrame(_ rect: CGRect) -> CGRect {
        let width = min(bounds.width, max(1, rect.width))
        let height = min(bounds.height, max(1, rect.height))
        let x = min(max(0, rect.minX), max(0, bounds.width - width))
        let y = min(max(0, rect.minY), max(0, bounds.height - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func beginTextEditing(at point: CGPoint) {
        beginTextEditing(
            content: "",
            origin: point,
            fontSize: 22,
            color: annotationColor,
            editingAnnotationID: nil
        )
    }

    private func beginTextEditing(for annotation: ImageAnnotation) {
        guard let content = annotation.textContent,
              let origin = annotation.textOrigin else {
            return
        }

        beginTextEditing(
            content: content,
            origin: origin,
            fontSize: annotation.fontSize,
            color: annotation.color,
            editingAnnotationID: annotation.id
        )
    }

    private func beginTextEditing(
        content: String,
        origin: CGPoint,
        fontSize: CGFloat,
        color: AnnotationColor,
        editingAnnotationID: UUID?
    ) {
        finishTextEditing(commit: true)

        activeTextBaseWidth = idealTextEditorWidth(for: content, fontSize: fontSize)
        activeTextFontSize = fontSize
        activeTextColor = color
        activeEditingAnnotationID = editingAnnotationID
        selectedTextAnnotationID = editingAnnotationID
        isActivatingTextField = true
        let normalizedOrigin = normalizedPoint(denormalizedPoint(origin, in: bounds))

        let field = NSTextField(frame: textFieldFrame(for: normalizedOrigin))
        field.stringValue = content
        field.placeholderString = "Enter text"
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.white.withAlphaComponent(0.94)
        field.textColor = color.nsColor
        field.font = NSFont.systemFont(ofSize: activeTextFontSize * annotationScale, weight: .semibold)
        field.focusRingType = .none
        field.delegate = self
        field.wantsLayer = true
        field.layer?.cornerRadius = 8
        field.layer?.borderWidth = 1
        field.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.65).cgColor

        let handle = ResizeHandleView(frame: .zero)
        handle.onDrag = { [weak self] delta in
            self?.resizeActiveText(by: delta)
        }
        handle.toolTip = "Drag to resize text box"

        addSubview(field)
        addSubview(handle)
        activeTextField = field
        activeResizeHandle = handle
        activeTextOrigin = normalizedOrigin
        updateActiveTextEditingLayout()
        focusTextField(field)
    }

    private func finishTextEditing(commit: Bool) {
        guard !isFinishingTextEditing,
              let activeTextField,
              let activeTextOrigin else { return }

        isFinishingTextEditing = true

        let content = activeTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let editingAnnotationID = activeEditingAnnotationID
        let activeResizeHandle = activeResizeHandle
        self.activeTextField = nil
        self.activeResizeHandle = nil
        self.activeTextOrigin = nil
        self.activeEditingAnnotationID = nil
        activeTextField.removeFromSuperview()
        activeResizeHandle?.removeFromSuperview()
        defer { isFinishingTextEditing = false }

        guard commit, !content.isEmpty else {
            if !commit {
                selectedTextAnnotationID = editingAnnotationID
            }
            needsDisplay = true
            return
        }

        let annotation = ImageAnnotation(
            id: editingAnnotationID ?? UUID(),
            kind: .text(content: content, origin: activeTextOrigin),
            color: activeTextColor,
            lineWidth: lineWidth,
            fontSize: activeTextFontSize
        )
        selectedTextAnnotationID = annotation.id
        if editingAnnotationID == nil {
            onAppendAnnotation?(annotation)
        } else {
            replaceLocal(annotation: annotation)
            onUpdateAnnotation?(annotation)
        }
    }

    private func textFieldFrame(for point: CGPoint) -> CGRect {
        let anchor = denormalizedPoint(point, in: bounds)
        let width = max(TextEditorMetrics.minWidth, activeTextBaseWidth * annotationScale)
        let height = max(
            34,
            (activeTextFontSize + TextEditorMetrics.verticalPadding * 2) * annotationScale
        )
        let x = min(max(0, anchor.x), max(0, bounds.width - width))
        let y = min(max(0, anchor.y - 10), max(0, bounds.height - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private var annotationScale: CGFloat {
        guard baseImageSize.width > 0, baseImageSize.height > 0 else { return 1 }
        return min(bounds.width / baseImageSize.width, bounds.height / baseImageSize.height)
    }

    private func resizeActiveText(by delta: CGSize) {
        let scale = max(annotationScale, 0.001)
        activeTextBaseWidth = min(
            TextEditorMetrics.maxWidth,
            max(TextEditorMetrics.minWidth, activeTextBaseWidth + delta.width / scale)
        )
        activeTextFontSize = min(
            TextEditorMetrics.maxFontSize,
            max(TextEditorMetrics.minFontSize, activeTextFontSize + delta.height / scale)
        )
        updateActiveTextEditingLayout()
    }

    private func idealTextEditorWidth(for content: String, fontSize: CGFloat) -> CGFloat {
        guard !content.isEmpty else { return 180 }
        let renderedWidth = renderedTextSize(content: content, fontSize: fontSize).width / max(annotationScale, 0.001)
        return min(
            TextEditorMetrics.maxWidth,
            max(TextEditorMetrics.minWidth, renderedWidth + 28)
        )
    }

    private func focusTextField(_ field: NSTextField) {
        field.isEditable = true
        field.isSelectable = true

        DispatchQueue.main.async { [weak self, weak field] in
            guard let self, let field, self.activeTextField === field else { return }
            self.window?.makeKey()
            self.window?.makeFirstResponder(field)
            field.selectText(nil)
            self.isActivatingTextField = false
        }
    }
}

private extension ImageAnnotation {
    var textContent: String? {
        guard case let .text(content, _) = kind else { return nil }
        return content
    }

    var textOrigin: CGPoint? {
        guard case let .text(_, origin) = kind else { return nil }
        return origin
    }

    var mosaicRect: CGRect? {
        guard case let .mosaic(rect) = kind else { return nil }
        return rect
    }
}

final class ResizeHandleView: NSView {
    var onDrag: ((CGSize) -> Void)?
    private var lastLocation: CGPoint?

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSColor.systemBlue.setFill()
        path.fill()

        NSColor.white.setStroke()
        path.lineWidth = 1
        path.stroke()

        let inset = rect.insetBy(dx: 4, dy: 4)
        let grip = NSBezierPath()
        grip.move(to: CGPoint(x: inset.minX, y: inset.minY))
        grip.line(to: CGPoint(x: inset.maxX, y: inset.maxY))
        grip.move(to: CGPoint(x: inset.minX + 3, y: inset.minY))
        grip.line(to: CGPoint(x: inset.maxX, y: inset.maxY - 3))
        grip.lineWidth = 1.2
        grip.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        lastLocation = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let next = convert(event.locationInWindow, from: nil)
        let previous = lastLocation ?? next
        lastLocation = next
        onDrag?(CGSize(width: next.x - previous.x, height: previous.y - next.y))
    }

    override func mouseUp(with event: NSEvent) {
        lastLocation = nil
    }
}
