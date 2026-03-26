import AppKit
import CoreGraphics
import Foundation

@MainActor
enum AcceptanceCheckRunner {
    static func run() -> Bool {
        var failures: [String] = []

        testShortcutPreferenceWorkflow(failures: &failures)
        testSetupGuidePreferenceWorkflow(failures: &failures)
        testAnnotatedExportWorkflow(failures: &failures)
        testTranslationPlanningWorkflow(failures: &failures)
        testPinnedLayoutWorkflow(failures: &failures)

        return CheckSupport.finish(
            failures: failures,
            successMessage: "ACCEPTANCE CHECK PASSED",
            failureMessage: "ACCEPTANCE CHECK FAILED"
        )
    }

    private static func testShortcutPreferenceWorkflow(failures: inout [String]) {
        guard let defaults = CheckSupport.makeUserDefaultsSuite(
            prefix: "PinShotAcceptance",
            failureMessage: "Could not create isolated UserDefaults suite for acceptance workflow.",
            failures: &failures
        ) else {
            return
        }

        let preferences = AppPreferences(userDefaults: defaults)
        let configuration = HotKeyConfiguration(
            keyCode: 8,
            modifiers: 3,
            display: "Command + Shift + C"
        )

        preferences.saveHotKeyConfiguration(configuration)
        let restored = preferences.loadHotKeyConfiguration()

        CheckSupport.expect(
            restored == configuration,
            "Shortcut preference workflow persists and restores the chosen hotkey",
            failures: &failures
        )
    }

    private static func testSetupGuidePreferenceWorkflow(failures: inout [String]) {
        guard let defaults = CheckSupport.makeUserDefaultsSuite(
            prefix: "PinShotAcceptance.SetupGuide",
            failureMessage: "Could not create isolated UserDefaults suite for setup guide workflow.",
            failures: &failures
        ) else {
            return
        }

        let preferences = AppPreferences(userDefaults: defaults)
        CheckSupport.expect(preferences.showSetupGuideOnLaunch, "Setup guide shows on first launch", failures: &failures)

        preferences.markSetupGuideDismissed()
        CheckSupport.expect(!preferences.showSetupGuideOnLaunch, "Setup guide can be skipped and stays hidden", failures: &failures)
    }

    private static func testAnnotatedExportWorkflow(failures: inout [String]) {
        guard let capture = CheckSupport.makeAnnotatedCapture() else {
            failures.append("Could not create annotated capture fixture.")
            return
        }

        let basePNGData = capture.image.pngData
        let renderedImage = AnnotationRenderer.render(item: capture)
        let renderedPNGData = AnnotationRenderer.pngData(item: capture)

        CheckSupport.expect(renderedImage != nil, "Annotated pin renders a preview image", failures: &failures)
        CheckSupport.expect(renderedPNGData?.isEmpty == false, "Annotated pin exports PNG data", failures: &failures)
        CheckSupport.expect(renderedPNGData != basePNGData, "Annotated export differs from the original capture", failures: &failures)

        guard let renderedPNGData else { return }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinShot-Acceptance-\(UUID().uuidString).png")

        do {
            try renderedPNGData.write(to: outputURL)
            let restoredImage = NSImage(contentsOf: outputURL)
            CheckSupport.expect(restoredImage != nil, "Exported PNG can be read back as an image", failures: &failures)
            try? FileManager.default.removeItem(at: outputURL)
        } catch {
            failures.append("Annotated export could not be written to a temporary PNG file.")
        }
    }

    private static func testTranslationPlanningWorkflow(failures: inout [String]) {
        let englishPlan = TranslationSupport.plan(for: "Hello from PinShot, this is a translation test.")
        CheckSupport.expect(
            englishPlan?.label == "English -> Chinese (Simplified)",
            "English OCR text plans translation into simplified Chinese",
            failures: &failures
        )

        let chinesePlan = TranslationSupport.plan(for: "这是一个用于验收测试的中文句子。")
        CheckSupport.expect(
            chinesePlan?.label == "Chinese (Simplified) -> English",
            "Chinese OCR text plans translation into English",
            failures: &failures
        )
    }

    private static func testPinnedLayoutWorkflow(failures: inout [String]) {
        let size = PinPanelLayout.preferredSize(
            originalRect: CGRect(x: 0, y: 0, width: 640, height: 360),
            zoom: 1.4,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            showToolbar: true,
            showInspector: true
        )

        CheckSupport.expect(size.width <= 1440 * 0.94, "Pinned capture width stays within the visible frame", failures: &failures)
        CheckSupport.expect(size.height <= 900 * 0.94, "Pinned capture height stays within the visible frame", failures: &failures)
        CheckSupport.expect(size.height > 360, "Pinned capture layout reserves room for editing chrome", failures: &failures)
    }
}
