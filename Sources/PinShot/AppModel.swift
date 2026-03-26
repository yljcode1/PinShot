import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    private enum ZoomLimits {
        static let minimum = 0.2
        static let maximum = 4.0
    }

    static let shared = AppModel()

    var captures: [CaptureItem] = []
    var selectedCaptureID: UUID?
    var hotKeyConfiguration = HotKeyConfiguration.default
    var launchAtLoginEnabled = true
    var launchAtLoginState = LaunchAtLoginState.unavailable
    var isRecordingHotKey = false
    var isShowingSetupGuide = false
    var historySearchText = ""
    var historyFilter = CaptureHistoryFilter.all
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

    var filteredCaptures: [CaptureItem] {
        captures.filter { item in
            historyFilter.includes(item) && matchesHistorySearch(item)
        }
    }

    var recognizedCaptureCount: Int {
        captures.filter(\.hasRecognizedText).count
    }

    var translatedCaptureCount: Int {
        captures.filter(\.hasTranslatedText).count
    }

    var annotatedCaptureCount: Int {
        captures.filter(\.hasAnnotations).count
    }

    private let screenshotService = ScreenshotService()
    private let ocrService = OCRService()
    private let sensitiveContentRedactionService = SensitiveContentRedactionService()
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
        isShowingSetupGuide = preferences.showSetupGuideOnLaunch
        if isShowingSetupGuide {
            statusMessage = "Welcome to PinShot — finish the setup guide or skip it anytime"
        }
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

        copyText(
            item.recognizedText,
            emptyMessage: "No recognized text to copy",
            successMessage: "Recognized text copied"
        )
    }

    func copyTranslatedText(for item: CaptureItem) {
        copyText(
            item.translatedText,
            emptyMessage: "No translated text to copy",
            successMessage: "Translated text copied"
        )
    }

    func copyImage(for item: CaptureItem) {
        panelManager.commitEditing(for: item.id)
        let outputImage = AnnotationRenderer.render(item: item) ?? item.image
        updateCopyStatus(copyImageToPasteboard(outputImage), successMessage: "Screenshot copied to clipboard")
    }

    func saveImage(for item: CaptureItem) {
        saveImage(for: item, format: .png)
    }

    func saveImage(for item: CaptureItem, format: CaptureExportFormat) {
        panelManager.commitEditing(for: item.id)

        guard let imageData = renderedImageData(for: item, format: format) else {
            statusMessage = "Save failed: cannot export \(format.title)"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(CaptureHistoryFormatter.suggestedFileStem(for: item)).\(format.fileExtension)"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try imageData.write(to: url)
                statusMessage = "\(format.title) saved"
            } catch {
                statusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    func saveText(for item: CaptureItem, kind: CaptureTextExportKind) {
        let text = kind.text(from: item).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != CaptureText.noTextRecognized else {
            statusMessage = "No \(kind.title.lowercased()) to export"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(CaptureHistoryFormatter.suggestedFileStem(for: item))-\(kind.title.replacingOccurrences(of: " ", with: "-").lowercased()).txt"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                statusMessage = "\(kind.title) saved"
            } catch {
                statusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    func exportCapturePackage(for item: CaptureItem) {
        panelManager.commitEditing(for: item.id)

        guard let pngData = renderedImageData(for: item, format: .png) else {
            statusMessage = "Export failed: cannot build image package"
            return
        }

        let panel = NSOpenPanel()
        panel.prompt = "Export"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let directoryURL = panel.url else {
            return
        }

        let packageURL = uniqueExportDirectoryURL(
            for: directoryURL.appendingPathComponent(
                "\(CaptureHistoryFormatter.suggestedFileStem(for: item))-Package",
                isDirectory: true
            )
        )

        do {
            try FileManager.default.createDirectory(
                at: packageURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try pngData.write(to: packageURL.appendingPathComponent("capture.png"))

            if item.hasRecognizedText {
                try item.recognizedText.write(
                    to: packageURL.appendingPathComponent("ocr.txt"),
                    atomically: true,
                    encoding: .utf8
                )
            }

            if item.hasTranslatedText {
                try item.translatedText.write(
                    to: packageURL.appendingPathComponent("translation.txt"),
                    atomically: true,
                    encoding: .utf8
                )
            }

            let metadata = CapturePackageMetadata(
                createdAt: item.createdAt,
                title: CaptureHistoryFormatter.title(for: item.recognizedText, createdAt: item.createdAt),
                recognizedTextAvailable: item.hasRecognizedText,
                translatedTextAvailable: item.hasTranslatedText,
                annotationCount: item.annotations.count,
                zoom: item.zoom,
                opacity: item.opacity
            )
            let metadataURL = packageURL.appendingPathComponent("metadata.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(metadata).write(to: metadataURL)

            statusMessage = "Capture package exported"
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
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
        item.zoom = clampedZoom(item.zoom)
        refreshCapture(item)
    }

    func adjustZoom(for item: CaptureItem, deltaY: CGFloat) {
        let step = deltaY > 0 ? 0.06 : -0.06
        setZoom(item.zoom + step, for: item)
    }

    func magnify(for item: CaptureItem, magnification: CGFloat) {
        // AppKit magnification: outward pinch => positive, inward pinch => negative.
        // Using exp() keeps pinch in/out symmetric and smoother than repeated linear steps.
        setZoom(item.zoom * CoreGraphics.exp(magnification), for: item)
    }

    func resetZoom(for item: CaptureItem) {
        setZoom(1, for: item)
    }

    func refreshCapture(_ item: CaptureItem) {
        panelManager.refresh(item: item, appModel: self)
    }

    func toggleInspector(for item: CaptureItem) {
        updateSelectedCapture(item) { currentItem in
            currentItem.showInspector.toggle()
            currentItem.showToolbar = true
        }
    }

    func toggleToolbar(for item: CaptureItem) {
        updateSelectedCapture(item) { currentItem in
            currentItem.showToolbar.toggle()
            if !currentItem.showToolbar {
                currentItem.showInspector = false
            }
        }
    }

    func selectCapture(_ item: CaptureItem) {
        refreshCaptures(applySelection(to: item))
    }

    func activateCaptureForInteraction(_ item: CaptureItem) {
        selectCapture(item)
    }

    func isSelected(_ item: CaptureItem) -> Bool {
        selectedCaptureID == item.id
    }

    func setAnnotationTool(_ tool: AnnotationTool, for item: CaptureItem) {
        updateSelectedCapture(item) { currentItem in
            currentItem.annotationTool = tool
            currentItem.showToolbar = true
            if currentItem.showInspector {
                currentItem.showInspector = false
            }
        }
        statusMessage = annotationToolStatusMessage(for: tool)
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

    func applySmartRedaction(for item: CaptureItem) {
        guard !item.isDetectingSensitiveContent else {
            statusMessage = "Smart redaction is already running"
            return
        }

        updateSelectedCapture(item) { currentItem in
            currentItem.isDetectingSensitiveContent = true
            currentItem.showToolbar = true
        }
        statusMessage = "Scanning for phone numbers, emails, links, IDs, and QR codes"

        let service = sensitiveContentRedactionService
        let cgImage = item.cgImage

        Task { [weak self] in
            let result = await service.detectRegions(in: cgImage)

            await MainActor.run { [weak self] in
                guard let self,
                      self.captures.contains(where: { $0.id == item.id }) else {
                    return
                }

                item.isDetectingSensitiveContent = false
                item.annotations.removeAll { $0.source == .smartRedaction }

                let masks = result.regions.map { rect in
                    ImageAnnotation(
                        kind: .mosaic(rect: rect),
                        color: .yellow,
                        lineWidth: 4,
                        source: .smartRedaction
                    )
                }
                item.annotations.append(contentsOf: masks)

                refreshCapture(item)
                statusMessage = smartRedactionStatusMessage(
                    kinds: result.kinds,
                    maskCount: masks.count
                )
            }
        }
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

    func reopenSetupGuide() {
        isShowingSetupGuide = true
        statusMessage = "Setup guide reopened"
    }

    func completeSetupGuide() {
        isShowingSetupGuide = false
        preferences.markSetupGuideDismissed()
        statusMessage = "Setup guide completed"
    }

    func skipSetupGuide() {
        isShowingSetupGuide = false
        preferences.markSetupGuideDismissed()
        statusMessage = "Setup guide skipped — you can reopen it anytime"
    }

    func openSystemSettings(_ destination: SetupGuideDestination) {
        guard let url = destination.url else {
            statusMessage = "Cannot open \(destination.title)"
            return
        }

        if NSWorkspace.shared.open(url) {
            statusMessage = "Opened \(destination.title) settings"
        } else {
            statusMessage = "Could not open \(destination.title) settings"
        }
    }

    func zoomIn(for item: CaptureItem) {
        setZoom(item.zoom + 0.12, for: item)
    }

    func zoomOut(for item: CaptureItem) {
        setZoom(item.zoom - 0.12, for: item)
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

    private func matchesHistorySearch(_ item: CaptureItem) -> Bool {
        let query = historySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return CaptureHistoryFormatter.searchableText(for: item).contains(query)
    }

    private func clampedZoom(_ zoom: Double) -> Double {
        min(ZoomLimits.maximum, max(ZoomLimits.minimum, zoom))
    }

    private func setZoom(_ zoom: Double, for item: CaptureItem) {
        item.zoom = clampedZoom(zoom)
        refreshCapture(item)
    }

    private func updateSelectedCapture(
        _ item: CaptureItem,
        updates: (CaptureItem) -> Void
    ) {
        let changedCaptures = applySelection(to: item)
        updates(item)
        refreshCaptures(changedCaptures + [item])
    }

    private func annotationToolStatusMessage(for tool: AnnotationTool) -> String {
        switch tool {
        case .none:
            return "Normal: drag or pinch to zoom"
        case .selectText:
            return "Text selection: drag to select text and copy"
        case .pen:
            return "Pen: draw directly on the image"
        case .rectangle:
            return "Rectangle: drag to highlight area"
        case .arrow:
            return "Arrow: drag to point at content"
        case .mosaic:
            return "Mosaic: draw to blur, drag to move, drag handle to resize, Delete to remove"
        case .text:
            return "Text: click to type, or press Command+V to paste"
        }
    }

    private func applySelection(to item: CaptureItem) -> [CaptureItem] {
        var changedCaptures: [CaptureItem] = []

        panelManager.bringToFront(for: item.id)

        if selectedCaptureID != item.id {
            if let previouslySelectedCapture = capture(with: selectedCaptureID) {
                changedCaptures.append(previouslySelectedCapture)
            }
            selectedCaptureID = item.id
            changedCaptures.append(item)
        }

        for capture in captures where capture.id != item.id {
            if capture.showToolbar || capture.showInspector || capture.annotationTool != .none {
                capture.showToolbar = false
                capture.showInspector = false
                capture.annotationTool = .none
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
        CaptureItem(
            image: capture.image,
            cgImage: capture.cgImage,
            originalRect: capture.appKitRect
        )
    }

    private func copySelection(_ capture: CapturedSelection) {
        updateCopyStatus(copyImageToPasteboard(capture.image), successMessage: "Selection copied to clipboard")
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
            updatePresentedSelection(item, showToolbar: true, status: "Quick edit opened; OCR is running")
        case .pin:
            updatePresentedSelection(item, showToolbar: false, status: "Capture pinned")
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

    private func updatePresentedSelection(
        _ item: CaptureItem,
        showToolbar: Bool,
        status: String
    ) {
        item.showToolbar = showToolbar
        item.showInspector = false
        refreshCapture(item)
        statusMessage = status
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

    private func copyText(
        _ text: String,
        emptyMessage: String,
        successMessage: String
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != CaptureText.noTextRecognized else {
            statusMessage = emptyMessage
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if pasteboard.setString(value, forType: .string) {
            statusMessage = successMessage
        } else {
            statusMessage = "Copy failed: could not write text to clipboard"
        }
    }

    private func renderedImageData(for item: CaptureItem, format: CaptureExportFormat) -> Data? {
        let outputImage = AnnotationRenderer.render(item: item) ?? item.image

        switch format {
        case .png:
            return outputImage.pngData
        case .jpeg:
            return outputImage.jpegData
        }
    }

    private func uniqueExportDirectoryURL(for proposedURL: URL) -> URL {
        guard FileManager.default.fileExists(atPath: proposedURL.path) else {
            return proposedURL
        }

        let directory = proposedURL.deletingLastPathComponent()
        let name = proposedURL.lastPathComponent
        var counter = 2

        while true {
            let candidate = directory.appendingPathComponent("\(name)-\(counter)", isDirectory: true)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    private func updateCopyStatus(_ didCopy: Bool, successMessage: String) {
        statusMessage = didCopy
            ? successMessage
            : "Copy failed: could not write image to clipboard"
    }

    private func smartRedactionStatusMessage(
        kinds: Set<SensitiveContentKind>,
        maskCount: Int
    ) -> String {
        guard maskCount > 0 else {
            return "No sensitive content found"
        }

        let summary = kinds
            .map(\.title)
            .sorted()
            .prefix(3)
            .joined(separator: ", ")

        if summary.isEmpty {
            return "Smart redaction added \(maskCount) mask\(maskCount == 1 ? "" : "s")"
        }

        return "Smart redaction added \(maskCount) mask\(maskCount == 1 ? "" : "s") for \(summary)"
    }
}

private struct CapturePackageMetadata: Encodable {
    let createdAt: Date
    let title: String
    let recognizedTextAvailable: Bool
    let translatedTextAvailable: Bool
    let annotationCount: Int
    let zoom: Double
    let opacity: Double
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
