import CoreGraphics
import Foundation

@MainActor
enum SelfCheckRunner {
    static func run() -> Bool {
        var failures: [String] = []

        testAppPreferences(failures: &failures)
        testCapturePresentation(failures: &failures)
        testLaunchAtLoginSupport(failures: &failures)

        if failures.isEmpty {
            print("SELF-CHECK PASSED")
            return true
        }

        print("SELF-CHECK FAILED")
        failures.forEach { print("- \($0)") }
        return false
    }

    private static func testAppPreferences(failures: inout [String]) {
        let suiteName = "PinShotSelfCheck.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            failures.append("Could not create isolated UserDefaults suite.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let preferences = AppPreferences(userDefaults: defaults)
        expect(preferences.launchAtLoginEnabled, "Launch-at-login defaults to enabled", failures: &failures)

        let configuration = HotKeyConfiguration(
            keyCode: 12,
            modifiers: 3,
            display: "Command + Shift + Q"
        )
        preferences.saveHotKeyConfiguration(configuration)
        expect(
            preferences.loadHotKeyConfiguration() == configuration,
            "Hotkey configuration round-trips through preferences",
            failures: &failures
        )
    }

    private static func testCapturePresentation(failures: inout [String]) {
        let title = CaptureHistoryFormatter.title(
            for: CaptureText.noTextRecognized,
            createdAt: Date(timeIntervalSince1970: 1_711_360_000)
        )
        expect(title.hasPrefix("Capture "), "History formatter uses fallback title", failures: &failures)

        let chooserOrigin = CaptureChooserLayout.origin(
            anchorPoint: CGPoint(x: 10, y: 12),
            visibleFrame: CGRect(x: 0, y: 0, width: 300, height: 240)
        )
        expect(chooserOrigin.x >= 14 && chooserOrigin.y >= 14, "Chooser origin clamps into visible frame", failures: &failures)

        let inferredRect = CapturePlacementResolver.inferredRect(
            imagePixelSize: CGSize(width: 400, height: 200),
            initialMouseLocation: CGPoint(x: 30, y: 25),
            screenVisibleFrame: CGRect(x: 0, y: 0, width: 500, height: 500),
            screenScale: 2
        )
        expect(abs(inferredRect.width - 200) < 0.001, "Capture placement resolves image width", failures: &failures)
        expect(abs(inferredRect.height - 100) < 0.001, "Capture placement resolves image height", failures: &failures)
        expect(inferredRect.minX >= 0 && inferredRect.minY >= 0, "Capture placement stays inside screen bounds", failures: &failures)

        let compactSize = PinPanelLayout.preferredSize(
            originalRect: CGRect(x: 0, y: 0, width: 240, height: 120),
            zoom: 1,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            showToolbar: false,
            showInspector: false
        )
        let expandedSize = PinPanelLayout.preferredSize(
            originalRect: CGRect(x: 0, y: 0, width: 240, height: 120),
            zoom: 1,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            showToolbar: true,
            showInspector: true
        )
        expect(abs(compactSize.width - 240) < 0.001, "Panel layout preserves natural width", failures: &failures)
        expect(expandedSize.height > compactSize.height, "Panel layout expands for toolbar and inspector", failures: &failures)
    }

    private static func testLaunchAtLoginSupport(failures: inout [String]) {
        let service = LaunchAtLoginService()
        let state = service.currentState()
        expect(
            service.isSupported ? state != .unavailable : state == .unavailable,
            "Launch-at-login support matches bundle environment",
            failures: &failures
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        failures: inout [String]
    ) {
        if condition() {
            print("PASS - \(message)")
        } else {
            failures.append(message)
        }
    }
}
