import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class CaptureItem: Identifiable {
    let id = UUID()
    let image: NSImage
    let cgImage: CGImage
    let originalRect: CGRect
    let createdAt = Date()
    var recognizedText: String
    var translatedText = ""
    var translationLabel = ""
    var isRecognizingText = true
    var isTranslating = false
    var showToolbar = false
    var showInspector = false
    var annotations: [ImageAnnotation] = []
    var annotationTool: AnnotationTool = .none
    var annotationColor: AnnotationColor = .red
    var annotationLineWidth: CGFloat = 3
    var opacity: Double
    var zoom: Double

    init(
        image: NSImage,
        cgImage: CGImage,
        originalRect: CGRect,
        recognizedText: String = CaptureText.recognizing,
        opacity: Double = 0.96,
        zoom: Double = 1
    ) {
        self.image = image
        self.cgImage = cgImage
        self.originalRect = originalRect
        self.recognizedText = recognizedText
        self.opacity = opacity
        self.zoom = zoom
    }
}
