import AppKit
import Carbon
import CoreGraphics
import Foundation

@MainActor
enum QualityCheckRunner {
    enum Suite: CaseIterable {
        case unit
        case integration
        case system
        case acceptance

        var title: String {
            switch self {
            case .unit:
                return "UNIT CHECKS"
            case .integration:
                return "INTEGRATION CHECKS"
            case .system:
                return "SYSTEM CHECKS"
            case .acceptance:
                return "ACCEPTANCE CHECKS"
            }
        }
    }

    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Bool? {
        let suites = requestedSuites(from: arguments)
        guard !suites.isEmpty else { return nil }

        if suites == [.system] {
            return SelfCheckRunner.run()
        }

        if suites == [.acceptance] {
            return AcceptanceCheckRunner.run()
        }

        return run(suites: suites)
    }

    private static func requestedSuites(from arguments: [String]) -> [Suite] {
        if arguments.contains("--all-checks") {
            return Suite.allCases
        }

        var suites: [Suite] = []

        if arguments.contains("--unit-check") {
            suites.append(.unit)
        }

        if arguments.contains("--integration-check") {
            suites.append(.integration)
        }

        if arguments.contains("--system-check") || arguments.contains("--self-check") {
            suites.append(.system)
        }

        if arguments.contains("--acceptance-check") {
            suites.append(.acceptance)
        }

        return suites
    }

    private static func run(suites: [Suite]) -> Bool {
        var failures: [String] = []

        for suite in suites {
            print("== \(suite.title) ==")

            switch suite {
            case .unit:
                runUnitChecks(failures: &failures)
            case .integration:
                runIntegrationChecks(failures: &failures)
            case .system:
                CheckSupport.expect(SelfCheckRunner.run(), "System self-check passes", failures: &failures)
            case .acceptance:
                CheckSupport.expect(AcceptanceCheckRunner.run(), "Acceptance workflow passes", failures: &failures)
            }
        }

        return CheckSupport.finish(
            failures: failures,
            successMessage: "ALL REQUESTED CHECKS PASSED",
            failureMessage: "QUALITY CHECKS FAILED"
        )
    }

    private static func runUnitChecks(failures: inout [String]) {
        if let defaults = CheckSupport.makeUserDefaultsSuite(
            prefix: "PinShotQuality.Unit",
            failureMessage: "Could not create isolated UserDefaults suite for unit checks.",
            failures: &failures
        ) {
            let preferences = AppPreferences(userDefaults: defaults)
            CheckSupport.expect(preferences.launchAtLoginEnabled, "Launch-at-login defaults to enabled", failures: &failures)
            CheckSupport.expect(preferences.showSetupGuideOnLaunch, "Setup guide defaults to shown on first launch", failures: &failures)

            let configuration = HotKeyConfiguration(
                keyCode: 9,
                modifiers: 3,
                display: "Command + Shift + V"
            )
            preferences.saveHotKeyConfiguration(configuration)
            CheckSupport.expect(
                preferences.loadHotKeyConfiguration() == configuration,
                "Hotkey configuration round-trips through preferences",
                failures: &failures
            )

            defaults.set(Data("invalid-json".utf8), forKey: "PinShot.hotKeyConfiguration")
            CheckSupport.expect(
                preferences.loadHotKeyConfiguration() == .default,
                "Invalid hotkey data falls back to the default shortcut",
                failures: &failures
            )

            preferences.markSetupGuideDismissed()
            CheckSupport.expect(!preferences.showSetupGuideOnLaunch, "Setup guide dismissal persists", failures: &failures)

            preferences.resetSetupGuide()
            CheckSupport.expect(preferences.showSetupGuideOnLaunch, "Setup guide can be reset for later display", failures: &failures)
        }

        let historyTitle = CaptureHistoryFormatter.title(
            for: "  Hello from PinShot OCR  ",
            createdAt: Date(timeIntervalSince1970: 1_711_360_000)
        )
        CheckSupport.expect(historyTitle == "Hello from PinShot OCR", "History formatter trims OCR snippets", failures: &failures)

        let fallbackTitle = CaptureHistoryFormatter.title(
            for: CaptureText.noTextRecognized,
            createdAt: Date(timeIntervalSince1970: 1_711_360_000)
        )
        CheckSupport.expect(fallbackTitle.hasPrefix("Capture "), "History formatter falls back for placeholder OCR text", failures: &failures)

        if let item = CheckSupport.makeAnnotatedCapture(recognizedText: "  PinShot release note  ", textOverlay: "Demo") {
            item.translatedText = "已翻译完成"
            CheckSupport.expect(
                CaptureHistoryFormatter.detail(for: item) == "OCR · Translated · Annotated",
                "History formatter summarizes OCR, translation, and annotations",
                failures: &failures
            )
            CheckSupport.expect(
                CaptureHistoryFormatter.searchableText(for: item).contains("release note"),
                "History formatter builds searchable content from OCR text",
                failures: &failures
            )
            CheckSupport.expect(
                CaptureHistoryFormatter.suggestedFileStem(for: item).contains("PinShot release note"),
                "History formatter derives a readable export filename",
                failures: &failures
            )
            CheckSupport.expect(CaptureHistoryFilter.text.includes(item), "Text history filter includes OCR-ready captures", failures: &failures)
            CheckSupport.expect(CaptureHistoryFilter.translated.includes(item), "Translated history filter includes translated captures", failures: &failures)
            CheckSupport.expect(CaptureHistoryFilter.annotated.includes(item), "Annotated history filter includes marked captures", failures: &failures)
            CheckSupport.expect(
                CaptureTextExportKind.recognized.text(from: item) == item.recognizedText,
                "Recognized text export returns OCR content",
                failures: &failures
            )
            CheckSupport.expect(
                CaptureTextExportKind.translated.text(from: item) == item.translatedText,
                "Translated text export returns translated content",
                failures: &failures
            )
        } else {
            failures.append("Could not create annotated capture fixture for history filter checks.")
        }

        let inferredRect = CapturePlacementResolver.inferredRect(
            imagePixelSize: CGSize(width: 600, height: 300),
            initialMouseLocation: CGPoint(x: 20, y: 18),
            screenVisibleFrame: CGRect(x: 0, y: 0, width: 250, height: 180),
            screenScale: 2
        )
        CheckSupport.expect(
            inferredRect.minX >= 0 && inferredRect.minY >= 0 && inferredRect.maxX <= 250 && inferredRect.maxY <= 180,
            "Capture placement clamps into the visible frame",
            failures: &failures
        )

        let chooserOrigin = CaptureChooserLayout.origin(
            anchorPoint: CGPoint(x: 120, y: 10),
            visibleFrame: CGRect(x: 0, y: 0, width: 400, height: 320)
        )
        CheckSupport.expect(chooserOrigin.y > 10, "Capture chooser flips below the anchor near the bottom edge", failures: &failures)

        let panelSize = PinPanelLayout.preferredSize(
            originalRect: CGRect(x: 0, y: 0, width: 640, height: 360),
            zoom: 1.5,
            visibleFrame: CGRect(x: 0, y: 0, width: 1280, height: 800),
            showToolbar: true,
            showInspector: true
        )
        CheckSupport.expect(
            panelSize.width <= 1280 * 0.94 && panelSize.height <= 800 * 0.94 && panelSize.height > 360,
            "Pin panel layout stays within bounds while adding editing chrome",
            failures: &failures
        )

        let modifiers = HotKeyConfiguration.carbonModifiers(from: [.command, .shift, .option, .control])
        CheckSupport.expect(
            modifiers == UInt32(cmdKey | shiftKey | optionKey | controlKey),
            "Carbon modifiers preserve all supported flags",
            failures: &failures
        )

        let display = HotKeyConfiguration.displayString(
            for: UInt16(kVK_ANSI_P),
            modifiers: [.control, .command, .shift]
        )
        CheckSupport.expect(display == "Command + Shift + Control + P", "Hotkey display uses stable modifier ordering", failures: &failures)
        CheckSupport.expect(HotKeyConfiguration.keyName(for: 999) == "KeyCode 999", "Unknown key names use a stable fallback", failures: &failures)

        CheckSupport.expect(TranslationSupport.plan(for: CaptureText.noTextRecognized) == nil, "Placeholder OCR text does not create a translation plan", failures: &failures)
        CheckSupport.expect(
            TranslationSupport.plan(for: "Hello PinShot, this sentence should translate to Chinese.")?.label == "English -> Chinese (Simplified)",
            "English OCR text targets simplified Chinese translation",
            failures: &failures
        )
        CheckSupport.expect(
            TranslationSupport.plan(for: "这是一个用于测试翻译方向的中文句子。")?.label == "Chinese (Simplified) -> English",
            "Chinese OCR text targets English translation",
            failures: &failures
        )
    }

    private static func runIntegrationChecks(failures: inout [String]) {
        guard let fixture = CheckSupport.makeFixtureImage() else {
            failures.append("Could not create image fixture for integration checks.")
            return
        }

        let item = CaptureItem(
            image: fixture.image,
            cgImage: fixture.cgImage,
            originalRect: CGRect(origin: .zero, size: fixture.image.size),
            recognizedText: "Annotated capture"
        )
        item.isRecognizingText = false
        item.annotations = [
            ImageAnnotation(
                kind: .rectangle(CGRect(x: 0.08, y: 0.12, width: 0.42, height: 0.48)),
                color: .red,
                lineWidth: 4
            ),
            ImageAnnotation(
                kind: .text(content: "Pin", origin: CGPoint(x: 0.56, y: 0.58)),
                color: .blue,
                lineWidth: 3,
                fontSize: 24
            )
        ]

        let basePNGData = fixture.image.pngData
        let renderedPNGData = AnnotationRenderer.pngData(item: item)
        CheckSupport.expect(renderedPNGData?.isEmpty == false, "Annotation renderer exports PNG data", failures: &failures)
        CheckSupport.expect(renderedPNGData != basePNGData, "Annotated PNG output differs from the original image", failures: &failures)

        let mosaicImage = MosaicRenderer.makeImage(
            baseCGImage: fixture.cgImage,
            normalizedRect: CGRect(x: 0.72, y: 0.68, width: 0.5, height: 0.5)
        )
        CheckSupport.expect(mosaicImage != nil, "Mosaic renderer produces an image for a clamped selection", failures: &failures)
        CheckSupport.expect((mosaicImage?.width ?? 0) > 0 && (mosaicImage?.height ?? 0) > 0, "Mosaic renderer output has valid dimensions", failures: &failures)

        let jpegData = (AnnotationRenderer.render(item: item) ?? fixture.image).jpegData
        CheckSupport.expect(jpegData?.isEmpty == false, "Rendered captures can be exported as JPEG data", failures: &failures)
    }
}
