import AppKit

@MainActor
enum AsyncLifecycleChecks {
    static func run() async -> Bool {
        var failures: [String] = []
        await ChooserLifecycleChecks.run(failures: &failures)
        PanelLifecycleChecks.run(failures: &failures)
        let panelsPassed = failures.isEmpty
        CheckSupport.expect(panelsPassed, "Real overlapping panels pass hide, restore and close checks",
                            failures: &failures)
        guard let fixture = CheckSupport.makeFixtureImage() else { return false }
        let service = OCRService()
        let textImage = NSImage(size: NSSize(width: 800, height: 180))
        textImage.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 800, height: 180).fill()
        ("HELLO WORLD" as NSString).draw(
            at: NSPoint(x: 30, y: 60),
            withAttributes: [.font: NSFont.systemFont(ofSize: 60),
                             .foregroundColor: NSColor.black])
        textImage.unlockFocus()
        guard let textCGImage = textImage.cgImage else { return false }
        let recognized = await service.recognizeText(cgImage: textCGImage)
        CheckSupport.expect(recognized.uppercased().contains("HELLO WORLD"),
                            "Real Vision recognizes known English fixture", failures: &failures)
        let text = await service.recognizeText(cgImage: fixture.cgImage)
        CheckSupport.expect(text.isEmpty, "Vision returns no text for geometric fixture", failures: &failures)

        let cancelled = Task {
            await service.recognizeText(cgImage: fixture.cgImage)
        }
        cancelled.cancel()
        let cancelledText = await cancelled.value
        CheckSupport.expect(cancelledText.isEmpty, "Pre-cancelled OCR completes without text", failures: &failures)

        let scheduled = Task {
            await service.recognizeText(cgImage: fixture.cgImage)
        }
        await Task.yield()
        scheduled.cancel()
        _ = await scheduled.value
        print("PASS - Scheduled OCR returns after cancellation request")
        return CheckSupport.finish(failures: failures, successMessage: "ASYNC LIFECYCLE CHECKS PASSED",
                                   failureMessage: "ASYNC LIFECYCLE CHECKS FAILED")
    }
}
