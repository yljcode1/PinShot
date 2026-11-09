import AppKit

@MainActor
enum PanelLifecycleChecks {
    static func run(failures: inout [String]) {
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append("Panel lifecycle: \(message)") }
        }

        let manager = PinPanelManager()
        defer { manager.closeAll() }

        guard let screen = NSScreen.screens.first else {
            failures.append("Panel lifecycle: a screen is required to verify real panels")
            return
        }
        for attachedScreen in NSScreen.screens {
            let overlay = SmartSelectionOverlayService.makePanel(frame: attachedScreen.frame, screen: attachedScreen)
            overlay.isReleasedWhenClosed = false
            expect(overlay.frame == attachedScreen.frame, "overlay matches each attached display")
            overlay.close()
        }
        for frame in [
            CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 100, width: 1920, height: 1080),
            CGRect(x: 0, y: 1080, width: 1920, height: 1080),
            CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        ] {
            let overlay = SmartSelectionOverlayService.makePanel(frame: frame, screen: screen)
            overlay.isReleasedWhenClosed = false
            expect(overlay.frame == frame, "selection overlay preserves global external-display frame")
            overlay.close()
        }
        guard let context = CGContext(
            data: nil, width: 320, height: 240, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            failures.append("Panel lifecycle: could not create synthetic image context")
            return
        }
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        guard let cgImage = context.makeImage() else {
            failures.append("Panel lifecycle: could not create synthetic image")
            return
        }

        let rect = CGRect(x: screen.visibleFrame.midX - 160,
                          y: screen.visibleFrame.midY - 120,
                          width: 320, height: 240)
        let items = (0..<2).map { _ in
            let item = CaptureItem(
                image: NSImage(cgImage: cgImage, size: NSSize(width: 320, height: 240)),
                cgImage: cgImage, originalRect: rect, recognizedText: ""
            )
            item.isRecognizingText = false
            return item
        }
        for item in items {
            manager.present(item: item, appModel: AppModel.shared)
        }

        if let first = manager.frame(for: items[0].id),
           let second = manager.frame(for: items[1].id) {
            expect(!first.intersection(second).isEmpty, "synthetic panels must overlap")
        } else {
            expect(false, "both presented panels must have frames")
        }
        for item in items {
            expect(manager.captureID(forWindowIdentifier: item.id.uuidString) == item.id,
                   "overlapping panel must match its own window ID: \(item.id)")
        }
        expect(manager.captureID(forWindowIdentifier: nil) == nil,
               "missing window ID must be rejected")
        expect(manager.captureID(forWindowIdentifier: "invalid-window-id") == nil,
               "malformed window ID must be rejected")
        expect(manager.captureID(forWindowIdentifier: UUID().uuidString) == nil,
               "unmanaged window ID must be rejected")

        manager.hideAllPanels()
        for item in items {
            expect(manager.captureID(forWindowIdentifier: item.id.uuidString) == nil,
                   "hidden panel must reject its window ID: \(item.id)")
        }
        manager.showAllPanels()
        for item in items {
            expect(manager.captureID(forWindowIdentifier: item.id.uuidString) == item.id,
                   "restored panel must match its window ID: \(item.id)")
        }

        manager.closePanel(for: items[0].id)
        expect(manager.captureID(forWindowIdentifier: items[0].id.uuidString) == nil,
               "closed panel must reject its window ID")
        expect(manager.captureID(forWindowIdentifier: items[1].id.uuidString) == items[1].id,
               "closing one panel must preserve the other panel's hit")
        manager.closePanel(for: items[1].id)
        for item in items {
            expect(manager.captureID(forWindowIdentifier: item.id.uuidString) == nil,
                   "all closed panels must reject their window IDs: \(item.id)")
        }
    }
}
