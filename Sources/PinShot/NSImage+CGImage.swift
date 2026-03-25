import AppKit

extension NSImage {
    var cgImage: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    var pngData: Data? {
        if let cgImage {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            bitmap.size = size
            return bitmap.representation(using: .png, properties: [:])
        }

        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        bitmap.size = size
        return bitmap.representation(using: .png, properties: [:])
    }
}
