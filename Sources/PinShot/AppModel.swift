import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    private static let hotKeyDefaultsKey = "PinShot.hotKeyConfiguration"

    var captures: [CaptureItem] = []
    var selectedCaptureID: UUID?
    var hotKeyConfiguration = HotKeyConfiguration.default
    var isRecordingHotKey = false
    var statusMessage = "使用快捷键开始截图"

    var hasCaptures: Bool {
        !captures.isEmpty
    }

    var latestCapture: CaptureItem? {
        captures.first
    }

    private let screenshotService = ScreenshotService()
    private let ocrService = OCRService()
    private let hotKeyService = HotKeyService()
    private let panelManager = PinPanelManager()
    private var hotKeyMonitor: Any?
    private var magnifyMonitor: Any?

    private init() {
        hotKeyConfiguration = loadHotKeyConfiguration()
        statusMessage = "使用快捷键 \(hotKeyConfiguration.display) 开始截图"
    }

    func start() {
        hotKeyService.register(configuration: hotKeyConfiguration, handler: { [weak self] in
            Task { @MainActor [weak self] in
                await self?.captureAndPin()
            }
        })
        installMagnifyMonitorIfNeeded()
    }

    func captureAndPin() async {
        statusMessage = "拖拽选择区域，松手后点击钉住"

        do {
            guard let result = try await screenshotService.captureUserSelection() else {
                statusMessage = "截图已取消"
                return
            }

            handleSelectionResult(result)
        } catch {
            statusMessage = "截图失败: \(error.localizedDescription)"
        }
    }

    func captureAndCopy() async {
        statusMessage = "Drag to select an area, then choose Copy"

        do {
            guard let result = try await screenshotService.captureUserSelection() else {
                statusMessage = "Copy cancelled"
                return
            }

            handleSelectionResult(result)
        } catch {
            statusMessage = "Copy failed: \(error.localizedDescription)"
        }
    }

    func reopenLatestCapture() {
        guard let first = captures.first else { return }
        reopenPinnedPanel(for: first)
    }

    func copyRecognizedText(for item: CaptureItem) {
        guard !item.isRecognizingText else {
            statusMessage = "正在识别文字，请稍等"
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.recognizedText, forType: .string)
        statusMessage = "识别文字已复制"
    }

    func copyImage(for item: CaptureItem) {
        panelManager.commitEditing(for: item.id)
        let outputImage = AnnotationRenderer.render(item: item) ?? item.image
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([outputImage])
        statusMessage = "截图已复制到剪贴板"
    }

    func saveImage(for item: CaptureItem) {
        panelManager.commitEditing(for: item.id)

        guard let pngData = AnnotationRenderer.pngData(item: item) else {
            statusMessage = "保存失败：无法导出 PNG"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "PinShot-\(Int(item.createdAt.timeIntervalSince1970)).png"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try pngData.write(to: url)
                statusMessage = "图片已保存"
            } catch {
                statusMessage = "保存失败: \(error.localizedDescription)"
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
            statusMessage = "普通模式：可拖动贴图或手势缩放"
        case .selectText:
            statusMessage = "选文字模式：拖拽选择图片里的文字，然后复制"
        case .pen:
            statusMessage = "画笔模式：直接在图片上绘制"
        case .rectangle:
            statusMessage = "矩形模式：拖拽绘制重点框"
        case .arrow:
            statusMessage = "箭头模式：拖拽指向重点内容"
        case .mosaic:
            statusMessage = "打码模式：框选区域即可自动马赛克"
        case .text:
            statusMessage = "文字模式：点击图片输入，或直接按 Command+V 粘贴文字"
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
        statusMessage = "请在菜单栏窗口中按下新的快捷键"

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

    private func handleHotKeyRecording(_ event: NSEvent) {
        guard let configuration = HotKeyConfiguration.from(event: event) else {
            statusMessage = "快捷键至少需要一个修饰键"
            return
        }

        hotKeyConfiguration = configuration
        saveHotKeyConfiguration(configuration)
        hotKeyService.register(configuration: configuration, handler: { [weak self] in
            Task { @MainActor [weak self] in
                await self?.captureAndPin()
            }
        })
        stopHotKeyRecording()
        statusMessage = "快捷键已更新为 \(configuration.display)"
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

    private func loadHotKeyConfiguration() -> HotKeyConfiguration {
        guard let data = UserDefaults.standard.data(forKey: Self.hotKeyDefaultsKey),
              let configuration = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data) else {
            return .default
        }
        return configuration
    }

    private func saveHotKeyConfiguration(_ configuration: HotKeyConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: Self.hotKeyDefaultsKey)
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

    private func refreshAllCaptures() {
        refreshCaptures(captures)
    }

    private func performOCR(for item: CaptureItem) {
        let service = ocrService
        Task.detached(priority: .userInitiated) { [weak self] in
            let text = await service.recognizeText(cgImage: item.cgImage)
            await MainActor.run { [weak self] in
                guard let self else { return }
                let value = text.isEmpty ? "没有识别到文字" : text
                item.recognizedText = value
                item.isRecognizingText = false
                self.statusMessage = "截图完成，结果已置顶显示"
            }
        }
    }

    private func handleSelectionResult(_ result: CapturedSelectionResult) {
        switch result.action {
        case .pin:
            pinSelection(result.capture)
        case .copy:
            copySelection(result.capture)
        }
    }

    private func pinSelection(_ capture: CapturedSelection) {
        let item = CaptureItem(
            image: capture.image,
            cgImage: capture.cgImage,
            originalRect: capture.appKitRect
        )
        captures.insert(item, at: 0)
        selectCapture(item)
        panelManager.present(item: item, appModel: self)

        statusMessage = "正在识别文字并准备标注"
        performOCR(for: item)
    }

    private func copySelection(_ capture: CapturedSelection) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([capture.image])
        statusMessage = "Selection copied to clipboard"
    }
}
