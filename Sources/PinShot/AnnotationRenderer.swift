import AppKit

@MainActor
enum AnnotationRenderer {
    static func render(item: CaptureItem) -> NSImage? {
        guard let bitmap = renderBitmap(item: item) else {
            return item.image
        }

        let rendered = NSImage(size: item.image.size)
        rendered.addRepresentation(bitmap)
        return rendered
    }

    static func pngData(item: CaptureItem) -> Data? {
        renderBitmap(item: item)?.representation(using: .png, properties: [:])
    }

    private static func renderBitmap(item: CaptureItem) -> NSBitmapImageRep? {
        let pixelSize = pixelSize(for: item.image)
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            return nil
        }

        let width = Int(pixelSize.width.rounded(.up))
        let height = Int(pixelSize.height.rounded(.up))

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
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.current = context
        let drawingRect = CGRect(origin: .zero, size: CGSize(width: width, height: height))
        item.image.draw(
            in: drawingRect,
            from: CGRect(origin: .zero, size: item.image.size),
            operation: .copy,
            fraction: 1
        )

        let exportScale = min(
            CGFloat(width) / max(item.image.size.width, 1),
            CGFloat(height) / max(item.image.size.height, 1)
        )

        for annotation in item.annotations {
            draw(annotation: annotation, inPixelSize: CGSize(width: width, height: height), exportScale: exportScale)
        }

        context.flushGraphics()
        return bitmap
    }

    private static func pixelSize(for image: NSImage) -> CGSize {
        if let cgImage = image.cgImage {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }

        if let bitmapRepresentation = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }) {
            return CGSize(width: bitmapRepresentation.pixelsWide, height: bitmapRepresentation.pixelsHigh)
        }

        return image.size
    }

    private static func draw(annotation: ImageAnnotation, inPixelSize size: CGSize, exportScale: CGFloat) {
        let color = annotation.color.nsColor
        color.setStroke()

        switch annotation.kind {
        case .freehand(let points):
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.lineWidth = annotation.lineWidth * exportScale
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
            path.lineWidth = annotation.lineWidth * exportScale
            path.stroke()

        case .arrow(let start, let end):
            let startPoint = pixelPoint(start, in: size)
            let endPoint = pixelPoint(end, in: size)

            let path = NSBezierPath()
            path.lineWidth = annotation.lineWidth * exportScale
            path.lineCapStyle = .round
            path.move(to: startPoint)
            path.line(to: endPoint)

            let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
            let headLength = max(14 * exportScale, annotation.lineWidth * exportScale * 4)
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
                .font: NSFont.systemFont(ofSize: annotation.fontSize * exportScale, weight: .semibold)
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
