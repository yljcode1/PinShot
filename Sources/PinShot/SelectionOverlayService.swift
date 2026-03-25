import AppKit
import Carbon

enum SelectionOverlayAction {
    case quickEdit
    case pin
    case copy
}

@MainActor
final class CaptureActionChooserService {
    private var panel: CaptureActionChooserPanel?
    private var continuation: CheckedContinuation<SelectionOverlayAction?, Never>?
    private var localEventMonitor: Any?
    private var globalMouseMonitor: Any?

    func chooseAction(near anchorPoint: CGPoint) async -> SelectionOverlayAction? {
        cleanup()

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            showPanel(near: anchorPoint)
        }
    }

    private func showPanel(near anchorPoint: CGPoint) {
        let panelSize = NSSize(width: 372, height: 74)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorPoint) || $0.visibleFrame.contains(anchorPoint) })
            ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? CGRect(origin: .zero, size: panelSize)
        let margin: CGFloat = 14

        var origin = CGPoint(
            x: anchorPoint.x - panelSize.width / 2,
            y: anchorPoint.y - panelSize.height - 18
        )

        if origin.y < visibleFrame.minY + margin {
            origin.y = anchorPoint.y + 18
        }

        origin.x = min(max(origin.x, visibleFrame.minX + margin), max(visibleFrame.maxX - panelSize.width - margin, visibleFrame.minX + margin))
        origin.y = min(max(origin.y, visibleFrame.minY + margin), max(visibleFrame.maxY - panelSize.height - margin, visibleFrame.minY + margin))

        let panel = CaptureActionChooserPanel(
            contentRect: NSRect(origin: origin, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false

        let chooserView = CaptureActionChooserView(
            frame: NSRect(origin: .zero, size: panelSize),
            onAction: { [weak self] action in
                self?.finish(with: action)
            },
            onCancel: { [weak self] in
                self?.finish(with: nil)
            }
        )
        chooserView.autoresizingMask = [.width, .height]

        panel.contentView = chooserView
        self.panel = panel

        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        installEventMonitors()
    }

    private func installEventMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape) {
                finish(with: nil)
                return nil
            }

            if (event.type == .leftMouseDown || event.type == .rightMouseDown),
               event.window !== panel {
                finish(with: nil)
            }

            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.finish(with: nil)
        }
    }

    private func finish(with action: SelectionOverlayAction?) {
        continuation?.resume(returning: action)
        cleanup()
    }

    private func cleanup() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }

        continuation = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class CaptureActionChooserView: NSView {
    private let onAction: (SelectionOverlayAction) -> Void
    private let onCancel: () -> Void
    private let containerView = NSVisualEffectView()
    private let stackView = NSStackView()
    private let quickEditButton = SelectionActionButton()
    private let pinButton = SelectionActionButton()
    private let copyButton = SelectionActionButton()

    init(
        frame frameRect: NSRect,
        onAction: @escaping (SelectionOverlayAction) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onAction = onAction
        self.onCancel = onCancel
        super.init(frame: frameRect)
        wantsLayer = true
        setupView()
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

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel()
            return
        }

        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            onAction(.quickEdit)
            return
        }

        if event.modifierFlags.contains(.command),
           let characters = event.charactersIgnoringModifiers?.lowercased() {
            switch characters {
            case "c":
                onAction(.copy)
                return
            case "p":
                onAction(.pin)
                return
            default:
                break
            }
        }

        if let characters = event.charactersIgnoringModifiers?.lowercased(), characters == "e" {
            onAction(.quickEdit)
            return
        }

        super.keyDown(with: event)
    }

    private func setupView() {
        containerView.material = .hudWindow
        containerView.blendingMode = .withinWindow
        containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 16
        containerView.layer?.cornerCurve = .continuous
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        containerView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.18).cgColor
        containerView.layer?.shadowOpacity = 1
        containerView.layer?.shadowRadius = 16
        containerView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        containerView.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .horizontal
        stackView.spacing = 10
        stackView.alignment = .centerY
        stackView.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        configureActionButton(
            quickEditButton,
            title: "Quick Edit",
            symbolName: "wand.and.stars",
            theme: .quickEdit,
            toolTip: "Open the capture with editing tools (Return / E)",
            action: #selector(quickEditTapped)
        )

        configureActionButton(
            pinButton,
            title: "Pin",
            symbolName: "pin.circle.fill",
            theme: .pin,
            toolTip: "Pin the capture to the desktop (Command+P)",
            action: #selector(pinTapped)
        )

        configureActionButton(
            copyButton,
            title: "Copy",
            symbolName: "doc.on.doc.fill",
            theme: .copy,
            toolTip: "Copy the capture to the clipboard (Command+C)",
            action: #selector(copyTapped)
        )

        stackView.addArrangedSubview(quickEditButton)
        stackView.addArrangedSubview(pinButton)
        stackView.addArrangedSubview(copyButton)

        containerView.addSubview(stackView)
        addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            quickEditButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 108),
            pinButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            copyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            quickEditButton.heightAnchor.constraint(equalToConstant: 40),
            pinButton.heightAnchor.constraint(equalToConstant: 40),
            copyButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func configureActionButton(
        _ button: SelectionActionButton,
        title: String,
        symbolName: String,
        theme: SelectionActionButtonTheme,
        toolTip: String,
        action: Selector
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
        button.target = self
        button.action = action
        button.configure(theme: theme)
    }

    @objc
    private func quickEditTapped() {
        onAction(.quickEdit)
    }

    @objc
    private func pinTapped() {
        onAction(.pin)
    }

    @objc
    private func copyTapped() {
        onAction(.copy)
    }
}

private final class CaptureActionChooserPanel: NSPanel {
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
