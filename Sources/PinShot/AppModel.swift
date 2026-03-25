import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var captures: [CaptureItem] = []
    var selectedCaptureID: UUID?
    var hotKeyConfiguration = HotKeyConfiguration.default
    var launchAtLoginEnabled = true
    var launchAtLoginState = LaunchAtLoginState.unavailable
    var isRecordingHotKey = false
    var statusMessage = "Use the hotkey to start capturing"

    var hasCaptures: Bool {
        !captures.isEmpty
    }

    var latestCapture: CaptureItem? {
        captures.first
    }

    var launchAtLoginDetail: String {
        launchAtLoginState.detailText
    }

    private let screenshotService = ScreenshotService()
    private let ocrService = OCRService()
    private let hotKeyService = HotKeyService()
    private let panelManager = PinPanelManager()
    private let actionChooserService = CaptureActionChooserService()
    private let preferences = AppPreferences()
    private let launchAtLoginService = LaunchAtLoginService()
    private var hotKeyMonitor: Any?
    private var magnifyMonitor: Any?

    private init() {
        hotKeyConfiguration = preferences.loadHotKeyConfiguration()
        launchAtLoginEnabled = preferences.launchAtLoginEnabled
        launchAtLoginState = launchAtLoginService.currentState()
        statusMessage = "Use \(hotKeyConfiguration.display) to start a capture"
    }

    func start() {
        registerHotKeyHandler()
        installMagnifyMonitorIfNeeded()
        applyLaunchAtLoginPreference(userInitiated: false)
    }

    func captureAndChooseAction() async {
        await performCapture(mode: .chooseAction)
    }

    func captureAndPin() async {
        await performCapture(mode: .pin)
    }

    func captureAndCopy() async {
        await performCapture(mode: .copy)
    }

    func reopenLatestCapture() {
        guard let first = captures.first else { return }
        reopenPinnedPanel(for: first)
    }

    func copyRecognizedText(for item: CaptureItem) {
        guard !item.isRecognizingText else {
            statusMessage = "Recognizing text..."
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.recognizedText, forType: .string)
        statusMessage = "Recognized text copied"
    }

    func copyImage(for item: CaptureItem) {
        panelManager.commitEditing(for: item.id)
        let outputImage = AnnotationRenderer.render(item: item) ?? item.image
        let didCopy = copyImageToPasteboard(outputImage)
        statusMessage = didCopy
            ? "Screenshot copied to clipboard"
            : "Copy failed: could not write image to clipboard"
    }

    func saveImage(for item: CaptureItem) {
        panelManager.commitEditing(for: item.id)

        guard let pngData = AnnotationRenderer.pngData(item: item) else {
            statusMessage = "Save failed: cannot export PNG"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "PinShot-\(Int(item.createdAt.timeIntervalSince1970)).png"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try pngData.write(to: url)
                statusMessage = "Image saved"
            } catch {
                statusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    func reopenPinnedPanel(for item: CaptureItem) {
        selectCapture(item)
        panelManager.present(item: item, appModel: self)
    }

    func updateOpacity(for item: CaptureItem) {
        panelManager.updateOpacity(for: item)
    }

    func updateZoom(for item: CaptureItem) {
        panelManager.refresh(item: item, appModel: self)
    }

    func adjustZoom(for item: CaptureItem, deltaY: CGFloat) {
        let step = deltaY > 0 ? 0.06 : -0.06
        item.zoom = min(4, max(0.2, item.zoom + step))
        panelManager.refresh(item: item, appModel: self)
    }

    func magnify(for item: CaptureItem, magnification: CGFloat) {
        // AppKit magnification: outward pinch => positive, inward pinch => negative.
        // Using exp() keeps pinch in/out symmetric and smoother than repeated linear steps.
        let nextZoom = item.zoom * CoreGraphics.exp(magnification)
        item.zoom = min(4, max(0.2, nextZoom))
        panelManager.refresh(item: item, appModel: self)
    }

    func resetZoom(for item: CaptureItem) {
        item.zoom = 1
        panelManager.refresh(item: item, appModel: self)
    }

    func refreshCapture(_ item: CaptureItem) {
        panelManager.refresh(item: item, appModel: self)
    }

    func toggleInspector(for item: CaptureItem) {
        let changedCaptures = applySelection(to: item)
        item.showInspector.toggle()
        item.showToolbar = true
        refreshCaptures(changedCaptures + [item])
    }

    func toggleToolbar(for item: CaptureItem) {
        let changedCaptures = applySelection(to: item)
        item.showToolbar.toggle()
        if !item.showToolbar {
            item.showInspector = false
        }
        refreshCaptures(changedCaptures + [item])
    }

    func selectCapture(_ item: CaptureItem) {
        refreshCaptures(applySelection(to: item))
    }

    func isSelected(_ item: CaptureItem) -> Bool {
        selectedCaptureID == item.id
    }

    func setAnnotationTool(_ tool: AnnotationTool, for item: CaptureItem) {
        let changedCaptures = applySelection(to: item)
        item.annotationTool = tool
        item.showToolbar = true
        if item.showInspector {
            item.showInspector = false
        }
        switch tool {
        case .none:
            statusMessage = "Normal: drag or pinch to zoom"
        case .selectText:
            statusMessage = "Text selection: drag to select text and copy"
        case .pen:
            statusMessage = "Pen: draw directly on the image"
        case .rectangle:
            statusMessage = "Rectangle: drag to highlight area"
        case .arrow:
            statusMessage = "Arrow: drag to point at content"
        case .mosaic:
            statusMessage = "Mosaic: draw to blur, drag to move, drag handle to resize, Delete to remove"
        case .text:
            statusMessage = "Text: click to type, or press Command+V to paste"
        }
        refreshCaptures(changedCaptures + [item])
    }

    func setAnnotationColor(_ color: AnnotationColor, for item: CaptureItem) {
        item.annotationColor = color
        item.showToolbar = true
        refreshCaptures([item])
    }

    func undoLastAnnotation(for item: CaptureItem) {
        guard !item.annotations.isEmpty else { return }
        item.annotations.removeLast()
        refreshCaptures([item])
    }

    func clearAnnotations(for item: CaptureItem) {
        item.annotations.removeAll()
        refreshCaptures([item])
    }

    func removeCapture(_ item: CaptureItem) {
        let wasSelected = selectedCaptureID == item.id
        captures.removeAll { $0.id == item.id }
        if wasSelected {
            selectedCaptureID = captures.first?.id
        }
        panelManager.closePanel(for: item.id)
        if let selectedCapture = capture(with: selectedCaptureID) {
            refreshCaptures([selectedCapture])
        }
    }

    func closeAllPins() {
        captures.removeAll()
        selectedCaptureID = nil
        panelManager.closeAll()
    }

    func beginHotKeyRecording() {
        stopHotKeyRecording()
        isRecordingHotKey = true
        statusMessage = "Press the new shortcut keys now"

        hotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleHotKeyRecording(event)
            }
            return nil
        }
    }

    func stopHotKeyRecording() {
        if let hotKeyMonitor {
            NSEvent.removeMonitor(hotKeyMonitor)
            self.hotKeyMonitor = nil
        }
        isRecordingHotKey = false
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard launchAtLoginEnabled != enabled else { return }

        launchAtLoginEnabled = enabled
        preferences.launchAtLoginEnabled = enabled
        applyLaunchAtLoginPreference(userInitiated: true)
    }

    private func handleHotKeyRecording(_ event: NSEvent) {
        guard let configuration = HotKeyConfiguration.from(event: event) else {
            statusMessage = "Shortcut needs at least one modifier"
            return
        }

        hotKeyConfiguration = configuration
        preferences.saveHotKeyConfiguration(configuration)
        registerHotKeyHandler()
        stopHotKeyRecording()
        statusMessage = "Shortcut updated to \(configuration.display)"
    }

    private func installMagnifyMonitorIfNeeded() {
        guard magnifyMonitor == nil else { return }

        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self else { return event }
            let magnification = event.magnification
            let windowIdentifier = event.window?.identifier?.rawValue
            let mouseLocation = NSEvent.mouseLocation
            let handled = MainActor.assumeIsolated {
                self.handleMagnifyEvent(
                    magnification: magnification,
                    windowIdentifier: windowIdentifier,
                    mouseLocation: mouseLocation
                )
            }
            return handled ? nil : event
        }
    }

    private func handleMagnifyEvent(
        magnification: CGFloat,
        windowIdentifier: String?,
        mouseLocation: CGPoint
    ) -> Bool {
        guard let item = captureForMagnifyEvent(
            windowIdentifier: windowIdentifier,
            mouseLocation: mouseLocation
        ) else {
            return false
        }

        let changedCaptures = applySelection(to: item)
        if !changedCaptures.isEmpty {
            refreshCaptures(changedCaptures.filter { $0.id != item.id })
        }

        magnify(for: item, magnification: magnification)
        return true
    }

    private func captureForMagnifyEvent(
        windowIdentifier: String?,
        mouseLocation: CGPoint
    ) -> CaptureItem? {
        if let id = panelManager.captureID(forWindowIdentifier: windowIdentifier),
           let capture = captures.first(where: { $0.id == id }) {
            return capture
        }

        if let id = panelManager.captureID(containing: mouseLocation),
           let capture = captures.first(where: { $0.id == id }) {
            return capture
        }

        return nil
    }

    private func capture(with id: UUID?) -> CaptureItem? {
        guard let id else { return nil }
        return captures.first(where: { $0.id == id })
    }

    private func applySelection(to item: CaptureItem) -> [CaptureItem] {
        var changedCaptures: [CaptureItem] = []

        if selectedCaptureID != item.id {
            if let previouslySelectedCapture = capture(with: selectedCaptureID) {
                changedCaptures.append(previouslySelectedCapture)
            }
            selectedCaptureID = item.id
            changedCaptures.append(item)
        }

        for capture in captures where capture.id != item.id {
            if capture.showToolbar || capture.showInspector {
                capture.showToolbar = false
                capture.showInspector = false
                changedCaptures.append(capture)
            }
        }

        return changedCaptures
    }

    private func refreshCaptures(_ items: [CaptureItem]) {
        var refreshedIDs = Set<UUID>()

        for item in items where refreshedIDs.insert(item.id).inserted {
            panelManager.refresh(item: item, appModel: self)
        }
    }

    private func performOCR(for item: CaptureItem) {
        let service = ocrService
        Task.detached(priority: .userInitiated) { [weak self] in
            let text = await service.recognizeText(cgImage: item.cgImage)
            await MainActor.run { [weak self] in
                guard let self else { return }
                let value = text.isEmpty ? CaptureText.noTextRecognized : text
                item.recognizedText = value
                item.isRecognizingText = false
                self.statusMessage = "Capture ready"
            }
        }
    }

    private func makeCaptureItem(from capture: CapturedSelection) -> CaptureItem {
        let item = CaptureItem(
            image: capture.image,
            cgImage: capture.cgImage,
            originalRect: capture.appKitRect
        )
        return item
    }

    private func copySelection(_ capture: CapturedSelection) {
        let didCopy = copyImageToPasteboard(capture.image)
        statusMessage = didCopy
            ? "Selection copied to clipboard"
            : "Copy failed: could not write image to clipboard"
    }

    @discardableResult
    private func stageSelectionAsPin(
        _ capture: CapturedSelection,
        showToolbar: Bool = false
    ) -> CaptureItem {
        let item = makeCaptureItem(from: capture)
        item.showToolbar = showToolbar
        captures.insert(item, at: 0)
        selectCapture(item)
        panelManager.present(item: item, appModel: self)
        performOCR(for: item)
        return item
    }

    private func handlePresentedSelectionAction(
        _ action: SelectionOverlayAction,
        for item: CaptureItem
    ) {
        selectCapture(item)

        switch action {
        case .quickEdit:
            item.showToolbar = true
            item.showInspector = false
            panelManager.refresh(item: item, appModel: self)
            statusMessage = "Quick edit opened; OCR is running"
        case .pin:
            item.showToolbar = false
            item.showInspector = false
            panelManager.refresh(item: item, appModel: self)
            statusMessage = "Capture pinned"
        case .copy:
            copyImage(for: item)
        }
    }

    private func chooserAnchorPoint(for item: CaptureItem, fallbackRect: CGRect) -> CGPoint {
        if let panelFrame = panelManager.frame(for: item.id) {
            return CGPoint(x: panelFrame.midX, y: panelFrame.minY)
        }

        return CGPoint(x: fallbackRect.midX, y: fallbackRect.minY)
    }

    private func registerHotKeyHandler() {
        hotKeyService.register(configuration: hotKeyConfiguration) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.captureAndChooseAction()
            }
        }
    }

    private func applyLaunchAtLoginPreference(userInitiated: Bool) {
        do {
            launchAtLoginState = try launchAtLoginService.applyPreference(enabled: launchAtLoginEnabled)

            guard userInitiated else { return }

            switch launchAtLoginState {
            case .enabled:
                statusMessage = "Launch at login enabled"
            case .disabled:
                statusMessage = "Launch at login disabled"
            case .requiresApproval:
                statusMessage = "Allow PinShot in System Settings > General > Login Items"
            case .unavailable:
                statusMessage = "Launch at login will apply when running /Applications/PinShot.app"
            }
        } catch {
            if userInitiated {
                statusMessage = "Launch at login failed: \(error.localizedDescription)"
            }
            launchAtLoginState = launchAtLoginService.currentState()
        }
    }

    private func performCapture(mode: CaptureMode) async {
        statusMessage = mode.initialStatus

        do {
            guard let capture = try await screenshotService.captureUserSelection() else {
                statusMessage = mode.cancelStatus
                return
            }

            switch mode {
            case .chooseAction:
                let item = stageSelectionAsPin(capture)
                statusMessage = "Capture pinned; choose Quick Edit, Pin, or Copy"

                await Task.yield()

                guard let action = await actionChooserService.chooseAction(
                    near: chooserAnchorPoint(for: item, fallbackRect: capture.appKitRect)
                ) else {
                    statusMessage = "Capture pinned"
                    return
                }

                handlePresentedSelectionAction(action, for: item)
            case .pin:
                _ = stageSelectionAsPin(capture)
                statusMessage = "Recognizing text and preparing annotations"
            case .copy:
                copySelection(capture)
            }
        } catch {
            statusMessage = "\(mode.failurePrefix) failed: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func copyImageToPasteboard(_ image: NSImage) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var didWrite = false

        if let pngData = image.pngData {
            didWrite = pasteboard.setData(pngData, forType: .png) || didWrite
        }

        if let tiffData = image.tiffRepresentation {
            didWrite = pasteboard.setData(tiffData, forType: .tiff) || didWrite
        }

        if !didWrite {
            didWrite = pasteboard.writeObjects([image])
        }

        if !didWrite {
            NSSound.beep()
        }

        return didWrite
    }
}

private enum CaptureMode {
    case chooseAction
    case pin
    case copy

    var initialStatus: String {
        "Use the system selection to capture an area"
    }

    var cancelStatus: String {
        switch self {
        case .copy:
            return "Copy cancelled"
        case .chooseAction, .pin:
            return "Capture cancelled"
        }
    }

    var failurePrefix: String {
        switch self {
        case .copy:
            return "Copy"
        case .chooseAction, .pin:
            return "Capture"
        }
    }
}
