@MainActor
enum SelectionLifecycleChecks {
    static func run(failures: inout [String]) {
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        let slot = CaptureActionCompletionSlot()
        var oldResults: [SelectionOverlayAction?] = []
        var newResults: [SelectionOverlayAction?] = []
        slot.register { oldResults.append($0) }
        slot.register { newResults.append($0) }
        expect(oldResults.count == 1 && oldResults.first! == nil,
               "Replacing a chooser completes its previous request with nil exactly once")
        expect(newResults.isEmpty, "Replacement leaves the new chooser request pending")
        slot.complete(with: .copy)
        slot.complete(with: .pin)
        slot.cancel()
        expect(newResults.count == 1 && newResults.first! == .copy,
               "Chooser completion delivers its action once despite repeated finish/cancel")
        expect(oldResults.count == 1, "Finishing a replacement does not resume its predecessor again")

        var cancelledResults: [SelectionOverlayAction?] = []
        slot.register { cancelledResults.append($0) }
        slot.cancel()
        slot.cancel()
        slot.complete(with: .quickEdit)
        expect(cancelledResults.count == 1 && cancelledResults.first! == nil,
               "Chooser cancellation returns nil once and ignores later completion")

        var reentrantCalls = 0
        var successorResults: [SelectionOverlayAction?] = []
        slot.register { _ in
            reentrantCalls += 1
            if reentrantCalls == 1 {
                slot.cancel()
                slot.register { successorResults.append($0) }
            }
        }
        slot.complete(with: .pin)
        expect(reentrantCalls == 1, "Completion clears its slot before invoking a reentrant callback")
        slot.complete(with: .quickEdit)
        expect(successorResults.count == 1 && successorResults.first! == .quickEdit,
               "A request registered from completion remains available")

        var replacementCalls = 0
        var supersededResults: [SelectionOverlayAction?] = []
        var latestResults: [SelectionOverlayAction?] = []
        slot.register { _ in
            replacementCalls += 1
            slot.register { latestResults.append($0) }
        }
        slot.register { supersededResults.append($0) }
        slot.complete(with: .pin)
        expect(replacementCalls == 1 && supersededResults.count == 1 && supersededResults.first! == nil,
               "Reentrant replacement cancels the superseded request once")
        expect(latestResults.count == 1 && latestResults.first! == .pin,
               "Reentrant replacement retains the latest request")
    }
}
