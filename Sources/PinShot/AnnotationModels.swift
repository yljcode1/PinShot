import AppKit
import CoreGraphics

enum AnnotationTool: String {
    case none
    case selectText
    case pen
    case rectangle
    case arrow
    case text

    var systemImage: String {
        switch self {
        case .none:
            return "cursorarrow"
        case .selectText:
            return "text.cursor"
        case .pen:
            return "pencil.tip"
        case .rectangle:
            return "rectangle"
        case .arrow:
            return "arrow.up.right"
        case .text:
            return "character.textbox"
        }
    }
}

struct AnnotationColor: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let red = AnnotationColor(red: 0.93, green: 0.20, blue: 0.19, alpha: 1)
    static let blue = AnnotationColor(red: 0.20, green: 0.54, blue: 1.0, alpha: 1)
    static let yellow = AnnotationColor(red: 0.98, green: 0.78, blue: 0.10, alpha: 1)
    static let green = AnnotationColor(red: 0.17, green: 0.72, blue: 0.36, alpha: 1)

    static let presets: [AnnotationColor] = [.red, .blue]
}

struct ImageAnnotation: Identifiable, Equatable {
    enum Kind: Equatable {
        case freehand(points: [CGPoint])
        case rectangle(CGRect)
        case arrow(start: CGPoint, end: CGPoint)
        case text(content: String, origin: CGPoint)
    }

    let id = UUID()
    var kind: Kind
    var color: AnnotationColor
    var lineWidth: CGFloat
    var fontSize: CGFloat = 22
}
