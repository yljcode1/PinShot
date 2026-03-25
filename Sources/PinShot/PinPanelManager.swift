import AppKit
import SwiftUI

@MainActor
final class PinPanelManager {
    private var panels: [UUID: PinPanel] = [:]

    func present(item: CaptureItem, appModel: AppModel) {
        if let panel = panels[item.id],
           panel.contentViewController is NSHostingController<PinPreviewView> {
            updatePanel(panel, with: item, appModel: appModel)
            panel.orderFrontRegardless()
            return
        }

        let contentView = PinPreviewView(appModel: appModel, item: item)
        let hostingController = NSHostingController(rootView: contentView)
        let size = preferredPanelSize(for: item)
        let panel = PinPanel(
            contentRect: NSRect(x: 140, y: 140, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.alphaValue = item.opacity
        panel.hidesOnDeactivate = false
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false

        panels[item.id] = panel
        updatePanel(
            panel,
            with: item,
            appModel: appModel,
            topLeft: CGPoint(x: item.originalRect.minX, y: item.originalRect.maxY)
        )
        panel.orderFrontRegardless()
    }

    func updateOpacity(for item: CaptureItem) {
        panels[item.id]?.alphaValue = item.opacity
    }

    func refresh(item: CaptureItem, appModel: AppModel) {
        guard let panel = panels[item.id] else { return }
        updatePanel(panel, with: item, appModel: appModel)
    }

    func bringToFront(for id: UUID) {
        guard let panel = panels[id] else { return }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func commitEditing(for id: UUID) {
        guard let panel = panels[id] else { return }
        panel.makeFirstResponder(nil)
        panel.endEditing(for: nil)
    }

    func hideAllPanels() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
    }

    func showAllPanels() {
        for panel in panels.values {
            panel.orderFrontRegardless()
        }
    }

    func closePanel(for id: UUID) {
        panels[id]?.close()
        panels[id] = nil
    }

    func closeAll() {
        for panel in panels.values {
            panel.close()
        }
        panels.removeAll()
    }

    func captureID(for window: NSWindow?) -> UUID? {
        guard let window else { return nil }

        if let identifier = window.identifier?.rawValue,
           let id = UUID(uuidString: identifier),
           panels[id] != nil {
            return id
        }

        return panels.first(where: { $0.value === window })?.key
    }

    func captureID(forWindowIdentifier identifier: String?) -> UUID? {
        guard let identifier,
              let id = UUID(uuidString: identifier),
              panels[id] != nil else {
            return nil
        }

        return id
    }

    func captureID(containing screenPoint: CGPoint) -> UUID? {
        panels.first(where: { $0.value.frame.contains(screenPoint) })?.key
    }

    func frame(for id: UUID) -> CGRect? {
        panels[id]?.frame
    }

    private func updatePanel(
        _ panel: NSPanel,
        with item: CaptureItem,
        appModel: AppModel,
        topLeft: CGPoint? = nil
    ) {
        guard let hostingController = panel.contentViewController as? NSHostingController<PinPreviewView> else {
            return
        }

        hostingController.rootView = PinPreviewView(appModel: appModel, item: item)
        panel.alphaValue = item.opacity
        panel.isMovableByWindowBackground = false

        let size = preferredPanelSize(for: item, in: panel)
        let targetTopLeft = topLeft ?? CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        setFrame(panel, size: size, topLeft: targetTopLeft)
    }

    private func preferredPanelSize(for item: CaptureItem, in panel: NSPanel? = nil) -> NSSize {
        let visibleFrame = screenForLayout(of: item, panel: panel)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = PinPanelLayout.preferredSize(
            originalRect: item.originalRect,
            zoom: item.zoom,
            visibleFrame: visibleFrame,
            showToolbar: item.showToolbar,
            showInspector: item.showInspector
        )

        return NSSize(width: size.width, height: size.height)
    }

    private func screenForLayout(of item: CaptureItem, panel: NSPanel?) -> NSScreen? {
        if let panelScreen = panel?.screen {
            return panelScreen
        }

        let midpoint = CGPoint(x: item.originalRect.midX, y: item.originalRect.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) ?? NSScreen.main
    }

    private func setFrame(_ panel: NSPanel, size: NSSize, topLeft: CGPoint) {
        let targetY = topLeft.y - size.height

        let frame = NSRect(x: topLeft.x, y: targetY, width: size.width, height: size.height)
        guard panel.frame.integral != frame.integral else { return }
        panel.setFrame(frame, display: true, animate: false)
    }
}
