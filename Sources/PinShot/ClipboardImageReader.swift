import AppKit

enum ClipboardImageReader {
    static func read(from pasteboard: NSPasteboard) -> NSImage? {
        // Read image representations only; never fetch URLs from clipboard text.
        guard let image = NSImage(pasteboard: pasteboard),
              image.size.width > 0, image.size.height > 0,
              image.cgImage != nil else { return nil }
        return image
    }
}
