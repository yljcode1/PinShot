import AppKit

@MainActor
enum ChooserLifecycleChecks {
    static func run(failures: inout [String]) async {
        let service = CaptureActionChooserService()
        defer { service.cancel() }
        let anchor = NSScreen.main?.visibleFrame.origin ?? .zero
        let first = Task { await service.chooseAction(near: anchor) }
        guard await waitForPanel(service) else {
            first.cancel()
            failures.append("First real chooser did not open")
            return
        }
        let firstWindows = visibleChoosers()
        CheckSupport.expect(!firstWindows.isEmpty, "Real chooser window is visible", failures: &failures)

        let second = Task {
            first.cancel()
            return await service.chooseAction(near: anchor)
        }
        let firstResult = await first.value
        CheckSupport.expect(firstResult == nil, "Replacing a real chooser completes its predecessor", failures: &failures)
        CheckSupport.expect(firstWindows.allSatisfy { !$0.isVisible },
                            "Replacement removes the old chooser window", failures: &failures)
        CheckSupport.expect(service.isChoosingAction, "Replacement keeps its own chooser open", failures: &failures)
        await Task.yield()
        CheckSupport.expect(service.isChoosingAction, "Queued cancellation from an old task preserves the replacement",
                            failures: &failures)
        let preCancelled = Task { await service.chooseAction(near: anchor) }
        preCancelled.cancel()
        let preCancelledResult = await preCancelled.value
        CheckSupport.expect(preCancelledResult == nil && service.isChoosingAction,
                            "Pre-cancelled requests preserve an existing chooser", failures: &failures)
        let secondWindows = visibleChoosers()
        service.cancel()
        let secondResult = await second.value
        CheckSupport.expect(secondResult == nil && !service.isChoosingAction
                            && secondWindows.allSatisfy { !$0.isVisible },
                            "Explicit cancellation completes the real chooser and hides its window",
                            failures: &failures)

        let cancelled = Task { await service.chooseAction(near: anchor) }
        guard await waitForPanel(service) else {
            cancelled.cancel()
            failures.append("Cancellation fixture chooser did not open")
            return
        }
        let cancelledWindows = visibleChoosers()
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        CheckSupport.expect(cancelledResult == nil && !service.isChoosingAction
                            && cancelledWindows.allSatisfy { !$0.isVisible },
                            "Task cancellation cleans up the real chooser", failures: &failures)
    }

    private static func waitForPanel(_ service: CaptureActionChooserService) async -> Bool {
        for _ in 0..<100 {
            if service.isChoosingAction { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private static func visibleChoosers() -> [NSWindow] {
        NSApp.windows.filter {
            $0.isVisible && String(describing: type(of: $0)) == "CaptureActionChooserPanel"
        }
    }
}
