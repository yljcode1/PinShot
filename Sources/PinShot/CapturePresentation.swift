import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum CaptureText {
    static let recognizing = "Recognizing text..."
    static let noTextRecognized = "No text recognized"
}

enum CaptureHistoryFormatter {
    static func title(for recognizedText: String, createdAt: Date) -> String {
        let snippet = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snippet.isEmpty, snippet != CaptureText.noTextRecognized else {
            return "Capture \(createdAt.formatted(date: .omitted, time: .shortened))"
        }

        return String(snippet.prefix(26))
    }

    @MainActor
    static func detail(for item: CaptureItem) -> String {
        var badges: [String] = []

        if item.hasRecognizedText {
            badges.append("OCR")
        }

        if item.hasTranslatedText {
            badges.append("Translated")
        }

        if item.hasAnnotations {
            badges.append("Annotated")
        }

        if badges.isEmpty {
            return "Fresh capture"
        }

        return badges.joined(separator: " · ")
    }

    @MainActor
    static func searchableText(for item: CaptureItem) -> String {
        [
            title(for: item.recognizedText, createdAt: item.createdAt),
            item.recognizedText,
            item.translatedText
        ]
        .joined(separator: "\n")
        .lowercased()
    }

    @MainActor
    static func suggestedFileStem(for item: CaptureItem) -> String {
        let title = title(for: item.recognizedText, createdAt: item.createdAt)
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            return "PinShot-\(Int(item.createdAt.timeIntervalSince1970))"
        }

        return String(cleaned.prefix(42)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CaptureHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case translated
    case annotated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .text:
            return "Text"
        case .translated:
            return "Translated"
        case .annotated:
            return "Annotated"
        }
    }

    @MainActor
    func includes(_ item: CaptureItem) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            return item.hasRecognizedText
        case .translated:
            return item.hasTranslatedText
        case .annotated:
            return item.hasAnnotations
        }
    }
}

enum CaptureExportFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png:
            return "PNG"
        case .jpeg:
            return "JPEG"
        }
    }

    var fileExtension: String {
        switch self {
        case .png:
            return "png"
        case .jpeg:
            return "jpg"
        }
    }

    var contentType: UTType {
        switch self {
        case .png:
            return .png
        case .jpeg:
            return .jpeg
        }
    }
}

enum CaptureTextExportKind {
    case recognized
    case translated

    var title: String {
        switch self {
        case .recognized:
            return "OCR Text"
        case .translated:
            return "Translated Text"
        }
    }

    @MainActor
    func text(from item: CaptureItem) -> String {
        switch self {
        case .recognized:
            return item.recognizedText
        case .translated:
            return item.translatedText
        }
    }
}

enum SetupGuideDestination {
    case screenRecording
    case accessibility
    case loginItems

    var title: String {
        switch self {
        case .screenRecording:
            return "Screen Recording"
        case .accessibility:
            return "Accessibility"
        case .loginItems:
            return "Login Items"
        }
    }

    var url: URL? {
        switch self {
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .loginItems:
            return URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        }
    }
}

enum CapturePlacementResolver {
    static func inferredRect(
        imagePixelSize: CGSize,
        initialMouseLocation: CGPoint,
        screenVisibleFrame: CGRect?,
        screenScale: CGFloat
    ) -> CGRect {
        let scale = max(screenScale, 1)
        let naturalSize = CGSize(
            width: imagePixelSize.width / scale,
            height: imagePixelSize.height / scale
        )

        let layoutFrame = screenVisibleFrame ?? CGRect(origin: .zero, size: naturalSize)
        let size = CGSize(
            width: min(naturalSize.width, layoutFrame.width),
            height: min(naturalSize.height, layoutFrame.height)
        )
        var origin = CGPoint(
            x: initialMouseLocation.x - size.width / 2,
            y: initialMouseLocation.y - size.height / 2
        )

        origin.x = min(max(origin.x, layoutFrame.minX), max(layoutFrame.maxX - size.width, layoutFrame.minX))
        origin.y = min(max(origin.y, layoutFrame.minY), max(layoutFrame.maxY - size.height, layoutFrame.minY))

        return CGRect(origin: origin, size: size)
    }
}

enum CaptureChooserLayout {
    static let panelSize = CGSize(width: 372, height: 74)
    private static let margin: CGFloat = 14
    private static let verticalSpacing: CGFloat = 18

    static func origin(
        anchorPoint: CGPoint,
        visibleFrame: CGRect,
        panelSize: CGSize = panelSize
    ) -> CGPoint {
        var origin = CGPoint(
            x: anchorPoint.x - panelSize.width / 2,
            y: anchorPoint.y - panelSize.height - verticalSpacing
        )

        if origin.y < visibleFrame.minY + margin {
            origin.y = anchorPoint.y + verticalSpacing
        }

        origin.x = min(
            max(origin.x, visibleFrame.minX + margin),
            max(visibleFrame.maxX - panelSize.width - margin, visibleFrame.minX + margin)
        )
        origin.y = min(
            max(origin.y, visibleFrame.minY + margin),
            max(visibleFrame.maxY - panelSize.height - margin, visibleFrame.minY + margin)
        )

        return origin
    }
}

enum PinPanelLayout {
    static func preferredSize(
        originalRect: CGRect,
        zoom: Double,
        visibleFrame: CGRect,
        showToolbar: Bool,
        showInspector: Bool
    ) -> CGSize {
        let maxWidth: CGFloat = visibleFrame.width * 0.94
        let maxHeight: CGFloat = visibleFrame.height * 0.94
        let minWidth: CGFloat = 40
        let minHeight: CGFloat = 40
        let toolbarHeight: CGFloat = showToolbar ? 58 : 0
        let inspectorHeight: CGFloat = showInspector ? 210 : 0
        let inspectorSpacing: CGFloat = showInspector ? 12 : 0

        let requestedWidth = originalRect.width * zoom
        let requestedHeight = originalRect.height * zoom
        let availableImageHeight = max(40, maxHeight - toolbarHeight - inspectorHeight - inspectorSpacing)

        let widthRatio = maxWidth / max(requestedWidth, 1)
        let heightRatio = availableImageHeight / max(requestedHeight, 1)
        let fitScale = min(1, widthRatio, heightRatio)

        let width = max(minWidth, requestedWidth * fitScale)
        let height = max(
            minHeight,
            requestedHeight * fitScale + toolbarHeight + inspectorHeight + inspectorSpacing
        )

        return CGSize(width: width, height: height)
    }
}
