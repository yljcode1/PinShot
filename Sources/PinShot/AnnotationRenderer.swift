import AppKit

@MainActor
enum AnnotationRenderer {
    static func render(item: CaptureItem) -> NSImage? {
        guard let baseCGImage = item.image.cgImage else {
            return item.image
        }

        let width = baseCGImage.width
        let height = baseCGImage.height

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmap.size = item.image.size

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }

        NSGraphicsContext.current = context
        let drawingRect = CGRect(x: 0, y: 0, width: width, height: height)
        NSImage(cgImage: baseCGImage, size: NSSize(width: width, height: height)).draw(in: drawingRect)

        for annotation in item.annotations {
            draw(annotation: annotation, inPixelSize: CGSize(width: width, height: height))
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let rendered = NSImage(size: item.image.size)
        rendered.addRepresentation(bitmap)
        return rendered
    }

    private static func draw(annotation: ImageAnnotation, inPixelSize size: CGSize) {
        let color = annotation.color.nsColor
        color.setStroke()

        switch annotation.kind {
        case .freehand(let points):
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.lineWidth = annotation.lineWidth * (size.width / max(1, size.width))
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.move(to: pixelPoint(first, in: size))
            for point in points.dropFirst() {
                path.line(to: pixelPoint(point, in: size))
            }
            path.stroke()

        case .rectangle(let rect):
            let frame = pixelRect(rect, in: size)
            let path = NSBezierPath(rect: frame)
            path.lineWidth = annotation.lineWidth
            path.stroke()

        case .arrow(let start, let end):
            let startPoint = pixelPoint(start, in: size)
            let endPoint = pixelPoint(end, in: size)

            let path = NSBezierPath()
            path.lineWidth = annotation.lineWidth
            path.lineCapStyle = .round
            path.move(to: startPoint)
            path.line(to: endPoint)

            let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
            let headLength = max(14, annotation.lineWidth * 4)
            path.move(to: endPoint)
            path.line(to: CGPoint(
                x: endPoint.x - headLength * cos(angle - .pi / 6),
                y: endPoint.y - headLength * sin(angle - .pi / 6)
            ))
            path.move(to: endPoint)
            path.line(to: CGPoint(
                x: endPoint.x - headLength * cos(angle + .pi / 6),
                y: endPoint.y - headLength * sin(angle + .pi / 6)
            ))
            path.stroke()

        case .text(let content, let origin):
            let point = pixelPoint(origin, in: size)
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: annotation.color.nsColor,
                .font: NSFont.systemFont(ofSize: annotation.fontSize * (size.width / max(1, size.width)), weight: .semibold)
            ]
            NSAttributedString(string: content, attributes: attributes).draw(at: point)
        }
    }

    private static func pixelPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private static func pixelRect(_ rect: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * size.width,
            y: rect.minY * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }
}
