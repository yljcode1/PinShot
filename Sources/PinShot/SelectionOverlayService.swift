import AppKit
import Carbon
import CoreGraphics

struct ScreenSelection {
    let appKitRect: CGRect
    let kind: Kind

    enum Kind {
        case area
        case window(windowID: CGWindowID)
    }
}

enum SelectionOverlayAction {
    case quickEdit
    case pin
    case copy
}

struct ScreenSelectionResult {
    let selection: ScreenSelection
    let action: SelectionOverlayAction
}

@MainActor
final class SelectionOverlayService {
    private var overlayWindow: NSWindow?
    private var continuation: CheckedContinuation<ScreenSelectionResult?, Never>?

    func selectArea() async -> ScreenSelectionResult? {
        cleanup()

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            showOverlayWindow()
        }
    }

    private func showOverlayWindow() {
        let desktopFrame = NSScreen.screens
            .map(\.frame)
            .reduce(CGRect.null) { partial, frame in
                partial.isNull ? frame : partial.union(frame)
            }
        guard !desktopFrame.isNull else {
            finish(with: nil)
            return
        }

        let window = NSWindow(
            contentRect: desktopFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.hasShadow = false

        let overlayView = SelectionOverlayView(
            frame: CGRect(origin: .zero, size: desktopFrame.size),
            desktopFrame: desktopFrame
        )
        overlayView.autoresizingMask = [.width, .height]
        overlayView.onSelection = { [weak self] selection, action in
            self?.finish(with: ScreenSelectionResult(selection: selection, action: action))
        }
        overlayView.onCancel = { [weak self] in
            self?.finish(with: nil)
        }

        window.contentView = overlayView
        overlayWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(with result: ScreenSelectionResult?) {
        continuation?.resume(returning: result)
        cleanup()
    }

    private func cleanup() {
        continuation = nil
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }
}

final class SelectionOverlayView: NSView {
    private enum CaptureMode {
        case area
        case window
    }

    private struct WindowCandidate: Equatable {
        let windowID: CGWindowID
        let appKitRect: CGRect
        let localRect: CGRect
        let title: String?
        let ownerName: String?
    }

    var onSelection: ((ScreenSelection, SelectionOverlayAction) -> Void)?
    var onCancel: (() -> Void)?

    private let desktopFrame: CGRect
    private let mainDisplayHeight: CGFloat
    private let currentProcessID = ProcessInfo.processInfo.processIdentifier
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var committedRect: CGRect?
    private var hoveredWindow: WindowCandidate?
    private var committedWindow: WindowCandidate?
    private var isReselectGesture = false
    private var captureMode: CaptureMode = .area
    private let toolbarContainer = NSVisualEffectView()
    private let toolbarStackView = NSStackView()
    private let actionStackView = NSStackView()
    private let modeContainer = NSVisualEffectView()
    private let modeLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let quickEditButton = NSButton(title: "Quick Edit", target: nil, action: nil)
    private let pinButton = NSButton(title: "Pin", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)

    init(frame frameRect: NSRect, desktopFrame: CGRect) {
        self.desktopFrame = desktopFrame
        self.mainDisplayHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? desktopFrame.height
        super.init(frame: frameRect)
        wantsLayer = true
        setupToolbar()
        setupModeHUD()
        updateModeUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.20).setFill()
        dirtyRect.fill()

        if let rect = highlightedRect {
            NSColor.clear.setFill()
            rect.fill(using: .clear)

            let path = NSBezierPath(rect: rect)
            NSColor.systemBlue.withAlphaComponent(0.95).setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !toolbarContainer.isHidden, toolbarContainer.frame.contains(point) {
            super.mouseDown(with: event)
            return
        }

        isReselectGesture = committedRect != nil || committedWindow != nil
        hideToolbar()
        committedRect = nil
        committedWindow = nil

        switch captureMode {
        case .area:
            startPoint = point
            currentPoint = point
            hoveredWindow = nil
        case .window:
            startPoint = nil
            currentPoint = nil
            hoveredWindow = windowCandidate(at: point)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch captureMode {
        case .area:
            currentPoint = point
        case .window:
            hoveredWindow = windowCandidate(at: point)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        needsDisplay = true

        switch captureMode {
        case .area:
            currentPoint = point

            guard let rect = selectionRect, rect.width > 3, rect.height > 3 else {
                if isReselectGesture {
                    onCancel?()
                }
                committedRect = nil
                hideToolbar()
                startPoint = nil
                currentPoint = nil
                isReselectGesture = false
                return
            }

            committedRect = rect
            startPoint = nil
            currentPoint = nil
            isReselectGesture = false
            showToolbar(for: rect)
        case .window:
            hoveredWindow = windowCandidate(at: point)
            guard let candidate = hoveredWindow else {
                hideToolbar()
                isReselectGesture = false
                return
            }

            committedWindow = candidate
            isReselectGesture = false
            showToolbar(for: candidate.localRect)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard captureMode == .window, committedWindow == nil else { return }
        hoveredWindow = windowCandidate(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }
        if event.keyCode == UInt16(kVK_Space) {
            toggleCaptureMode()
            return
        }
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            commitSelection(action: .quickEdit)
            return
        }
        if event.modifierFlags.contains(.command),
           let characters = event.charactersIgnoringModifiers?.lowercased() {
            switch characters {
            case "c":
                commitSelection(action: .copy)
                return
            case "p":
                commitSelection(action: .pin)
                return
            default:
                break
            }
        }
        if let characters = event.charactersIgnoringModifiers?.lowercased(), characters == "e" {
            commitSelection(action: .quickEdit)
            return
        }
        super.keyDown(with: event)
    }

    private var selectionRect: CGRect? {
        if let committedRect {
            return committedRect
        }
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }

    private var highlightedRect: CGRect? {
        switch captureMode {
        case .area:
            selectionRect
        case .window:
            committedWindow?.localRect ?? hoveredWindow?.localRect
        }
    }

    private func setupToolbar() {
        toolbarContainer.material = .popover
        toolbarContainer.blendingMode = .withinWindow
        toolbarContainer.state = .active
        toolbarContainer.wantsLayer = true
        toolbarContainer.layer?.cornerRadius = 14
        toolbarContainer.layer?.cornerCurve = .continuous
        toolbarContainer.layer?.borderWidth = 1
        toolbarContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        toolbarContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.18).cgColor
        toolbarContainer.layer?.shadowOpacity = 1
        toolbarContainer.layer?.shadowRadius = 18
        toolbarContainer.layer?.shadowOffset = CGSize(width: 0, height: -2)
        toolbarContainer.isHidden = true

        quickEditButton.target = self
        quickEditButton.action = #selector(quickEditTapped)

        configureActionButton(
            quickEditButton,
            title: "Quick Edit",
            symbolName: "slider.horizontal.3",
            bezelColor: .systemOrange,
            contentTintColor: .white,
            toolTip: "Open the selection with toolbar, OCR, and annotation tools (Return / E)"
        )

        pinButton.target = self
        pinButton.action = #selector(pinTapped)

        configureActionButton(
            pinButton,
            title: "Pin",
            symbolName: "pin.fill",
            bezelColor: .systemBlue,
            contentTintColor: .white,
            toolTip: "Pin the selected area to the desktop (Command+P)"
        )

        copyButton.target = self
        copyButton.action = #selector(copyTapped)

        configureActionButton(
            copyButton,
            title: "Copy",
            symbolName: "doc.on.doc",
            bezelColor: .controlAccentColor,
            contentTintColor: .white,
            toolTip: "Copy the selected area to the clipboard"
        )

        actionStackView.orientation = .horizontal
        actionStackView.spacing = 8
        actionStackView.alignment = .centerY
        actionStackView.addArrangedSubview(quickEditButton)
        actionStackView.addArrangedSubview(pinButton)
        actionStackView.addArrangedSubview(copyButton)

        toolbarStackView.orientation = .horizontal
        toolbarStackView.alignment = .centerX
        toolbarStackView.spacing = 0
        toolbarStackView.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        toolbarStackView.addArrangedSubview(actionStackView)

        toolbarContainer.addSubview(toolbarStackView)
        toolbarStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbarStackView.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor),
            toolbarStackView.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor),
            toolbarStackView.topAnchor.constraint(equalTo: toolbarContainer.topAnchor),
            toolbarStackView.bottomAnchor.constraint(equalTo: toolbarContainer.bottomAnchor)
        ])

        addSubview(toolbarContainer)
    }

    private func setupModeHUD() {
        modeContainer.material = .hudWindow
        modeContainer.blendingMode = .withinWindow
        modeContainer.state = .active
        modeContainer.wantsLayer = true
        modeContainer.layer?.cornerRadius = 14
        modeContainer.layer?.cornerCurve = .continuous
        modeContainer.layer?.borderWidth = 1
        modeContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        modeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        modeLabel.textColor = .white

        hintLabel.font = .systemFont(ofSize: 12, weight: .regular)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.82)

        let stack = NSStackView(views: [modeLabel, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        modeContainer.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: modeContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: modeContainer.trailingAnchor),
            stack.topAnchor.constraint(equalTo: modeContainer.topAnchor),
            stack.bottomAnchor.constraint(equalTo: modeContainer.bottomAnchor)
        ])

        addSubview(modeContainer)
    }

    private func showToolbar(for rect: CGRect) {
        toolbarContainer.layoutSubtreeIfNeeded()
        let fittingSize = toolbarContainer.fittingSize
        let toolbarSize = NSSize(
            width: max(96, fittingSize.width),
            height: max(46, fittingSize.height)
        )
        let margin: CGFloat = 12
        let x = min(
            max(rect.midX - toolbarSize.width / 2, margin),
            bounds.width - toolbarSize.width - margin
        )

        let belowY = rect.minY - toolbarSize.height - margin
        let y: CGFloat
        if belowY >= margin {
            y = belowY
        } else {
            y = min(bounds.height - toolbarSize.height - margin, rect.maxY + margin)
        }

        toolbarContainer.frame = NSRect(origin: CGPoint(x: x, y: y), size: toolbarSize)
        toolbarContainer.isHidden = false
        needsDisplay = true
    }

    private func hideToolbar() {
        toolbarContainer.isHidden = true
    }

    override func layout() {
        super.layout()
        let fittingSize = modeContainer.fittingSize
        let width = max(280, fittingSize.width)
        let height = max(52, fittingSize.height)
        modeContainer.frame = NSRect(
            x: 20,
            y: bounds.height - height - 20,
            width: width,
            height: height
        )
    }

    @objc
    private func quickEditTapped() {
        commitSelection(action: .quickEdit)
    }

    @objc
    private func pinTapped() {
        commitSelection(action: .pin)
    }

    @objc
    private func copyTapped() {
        commitSelection(action: .copy)
    }

    private func commitSelection(action: SelectionOverlayAction = .quickEdit) {
        let selection: ScreenSelection?

        switch captureMode {
        case .area:
            if committedRect == nil, let rect = selectionRect {
                committedRect = rect
            }
            guard let rect = committedRect else { return }
            selection = ScreenSelection(appKitRect: globalRect(fromLocalRect: rect), kind: .area)
        case .window:
            if committedWindow == nil {
                committedWindow = hoveredWindow
            }
            guard let candidate = committedWindow else { return }
            selection = ScreenSelection(
                appKitRect: candidate.appKitRect,
                kind: .window(windowID: candidate.windowID)
            )
        }

        guard let selection else { return }
        onSelection?(selection, action)
        hideToolbar()
    }

    private func toggleCaptureMode() {
        captureMode = captureMode == .area ? .window : .area
        startPoint = nil
        currentPoint = nil
        committedRect = nil
        hoveredWindow = nil
        committedWindow = nil
        isReselectGesture = false
        hideToolbar()
        updateModeUI()
        needsDisplay = true
    }

    private func updateModeUI() {
        switch captureMode {
        case .area:
            modeLabel.stringValue = "Area Mode"
            hintLabel.stringValue = "Drag to capture. Press Space for Window Mode."
        case .window:
            modeLabel.stringValue = "Window Mode"
            hintLabel.stringValue = "Move to highlight a window, click to select. Press Space for Area Mode."
        }
        needsLayout = true
    }

    private func globalRect(fromLocalRect rect: CGRect) -> CGRect {
        CGRect(
            x: desktopFrame.minX + rect.minX,
            y: desktopFrame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
    }

    private func windowCandidate(at localPoint: CGPoint) -> WindowCandidate? {
        guard bounds.contains(localPoint),
              let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else {
            return nil
        }

        let globalPoint = CGPoint(
            x: desktopFrame.minX + localPoint.x,
            y: desktopFrame.minY + localPoint.y
        )

        for info in windowList {
            guard let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID != currentProcessID else {
                continue
            }

            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { continue }

            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.01 else { continue }

            let sharing = (info[kCGWindowSharingState as String] as? NSNumber)?.uint32Value ?? 0
            guard sharing != CGWindowSharingType.none.rawValue else { continue }

            guard let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary else {
                continue
            }

            var quartzBounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &quartzBounds) else {
                continue
            }

            let appKitRect = CGRect(
                x: quartzBounds.minX,
                y: mainDisplayHeight - quartzBounds.maxY,
                width: quartzBounds.width,
                height: quartzBounds.height
            )

            guard appKitRect.width > 32,
                  appKitRect.height > 24,
                  appKitRect.contains(globalPoint) else {
                continue
            }

            let localRect = CGRect(
                x: appKitRect.minX - desktopFrame.minX,
                y: appKitRect.minY - desktopFrame.minY,
                width: appKitRect.width,
                height: appKitRect.height
            )

            return WindowCandidate(
                windowID: windowID,
                appKitRect: appKitRect,
                localRect: localRect,
                title: info[kCGWindowName as String] as? String,
                ownerName: info[kCGWindowOwnerName as String] as? String
            )
        }

        return nil
    }

    private func configureActionButton(
        _ button: NSButton,
        title: String,
        symbolName: String,
        bezelColor: NSColor,
        contentTintColor: NSColor,
        toolTip: String
    ) {
        button.title = title
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = contentTintColor
        button.bezelColor = bezelColor
        button.toolTip = toolTip
        button.setButtonType(.momentaryPushIn)
    }
}
