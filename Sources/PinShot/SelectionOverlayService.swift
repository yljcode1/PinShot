import AppKit
import Carbon
import CoreGraphics

struct ScreenSelection {
    let appKitRect: CGRect
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
    private var overlayWindows: [NSWindow] = []
    private var continuation: CheckedContinuation<ScreenSelectionResult?, Never>?

    func selectArea() async -> ScreenSelectionResult? {
        cleanup()

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            showOverlayWindows()
        }
    }

    private func showOverlayWindows() {
        guard !NSScreen.screens.isEmpty else {
            finish(with: nil)
            return
        }

        for screen in NSScreen.screens {
            let window = SelectionOverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            window.backgroundColor = .clear
            window.isOpaque = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.hasShadow = false

            let overlayView = SelectionOverlayView(frame: window.contentView?.bounds ?? .zero, screen: screen)
            overlayView.autoresizingMask = [.width, .height]
            overlayView.onSelection = { [weak self] selection, action in
                self?.finish(with: ScreenSelectionResult(selection: selection, action: action))
            }
            overlayView.onCancel = { [weak self] in
                self?.finish(with: nil)
            }

            window.contentView = overlayView
            overlayWindows.append(window)
            window.makeKeyAndOrderFront(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(with result: ScreenSelectionResult?) {
        continuation?.resume(returning: result)
        cleanup()
    }

    private func cleanup() {
        continuation = nil
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }
}

final class SelectionOverlayView: NSView {
    var onSelection: ((ScreenSelection, SelectionOverlayAction) -> Void)?
    var onCancel: (() -> Void)?

    private let screen: NSScreen
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var committedRect: CGRect?
    private var isReselectGesture = false
    private let toolbarContainer = NSVisualEffectView()
    private let toolbarStackView = NSStackView()
    private let actionStackView = NSStackView()
    private let quickEditButton = SelectionActionButton()
    private let pinButton = SelectionActionButton()
    private let copyButton = SelectionActionButton()

    init(frame frameRect: NSRect, screen: NSScreen) {
        self.screen = screen
        super.init(frame: frameRect)
        wantsLayer = true
        setupToolbar()
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

        if let rect = selectionRect {
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

        isReselectGesture = committedRect != nil
        hideToolbar()
        committedRect = nil
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true

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
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
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

    private func setupToolbar() {
        toolbarContainer.translatesAutoresizingMaskIntoConstraints = false
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
            symbolName: "wand.and.stars",
            theme: .quickEdit,
            toolTip: "Open the selection with toolbar, OCR, and annotation tools (Return / E)"
        )

        pinButton.target = self
        pinButton.action = #selector(pinTapped)

        configureActionButton(
            pinButton,
            title: "Pin",
            symbolName: "pin.circle.fill",
            theme: .pin,
            toolTip: "Pin the selected area to the desktop (Command+P)"
        )

        copyButton.target = self
        copyButton.action = #selector(copyTapped)

        configureActionButton(
            copyButton,
            title: "Copy",
            symbolName: "doc.on.doc.fill",
            theme: .copy,
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
        guard let rect = committedRect else { return }

        let globalRect = CGRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )

        let selection = ScreenSelection(appKitRect: globalRect)
        onSelection?(selection, action)
        hideToolbar()
    }

    private func configureActionButton(
        _ button: SelectionActionButton,
        title: String,
        symbolName: String,
        theme: SelectionActionButtonTheme,
        toolTip: String
    ) {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)

        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.97)
            ]
        )
        button.font = font
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(symbolConfiguration)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = toolTip
        button.configure(theme: theme)
    }
}

private final class SelectionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct SelectionActionButtonTheme {
    let backgroundColor: NSColor
    let borderColor: NSColor
    let shadowColor: NSColor

    static let quickEdit = SelectionActionButtonTheme(
        backgroundColor: NSColor(red: 0.93, green: 0.58, blue: 0.29, alpha: 1),
        borderColor: NSColor.white.withAlphaComponent(0.28),
        shadowColor: NSColor(red: 0.45, green: 0.20, blue: 0.06, alpha: 0.22)
    )

    static let pin = SelectionActionButtonTheme(
        backgroundColor: NSColor(red: 0.29, green: 0.51, blue: 0.96, alpha: 1),
        borderColor: NSColor.white.withAlphaComponent(0.30),
        shadowColor: NSColor(red: 0.10, green: 0.20, blue: 0.46, alpha: 0.24)
    )

    static let copy = SelectionActionButtonTheme(
        backgroundColor: NSColor(red: 0.44, green: 0.47, blue: 0.90, alpha: 1),
        borderColor: NSColor.white.withAlphaComponent(0.30),
        shadowColor: NSColor(red: 0.18, green: 0.18, blue: 0.42, alpha: 0.22)
    )
}

private final class SelectionActionButton: NSButton {
    private var theme = SelectionActionButtonTheme.pin
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        imageHugsTitle = true
        contentTintColor = .white
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            updateAppearance()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    func configure(theme: SelectionActionButtonTheme) {
        self.theme = theme
        updateAppearance()
    }

    private func updateAppearance() {
        let alpha: CGFloat
        switch (isHighlighted, isHovered) {
        case (true, _):
            alpha = 0.82
        case (false, true):
            alpha = 0.72
        case (false, false):
            alpha = 0.60
        }

        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = theme.backgroundColor.withAlphaComponent(alpha).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = theme.borderColor.cgColor
        layer?.shadowColor = theme.shadowColor.cgColor
        layer?.shadowOpacity = isHighlighted ? 0.12 : 0.22
        layer?.shadowRadius = isHighlighted ? 4 : 8
        layer?.shadowOffset = CGSize(width: 0, height: -1)
    }
}
