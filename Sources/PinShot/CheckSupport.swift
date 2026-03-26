import AppKit
import CoreGraphics
import Foundation

@MainActor
enum CheckSupport {
    static func makeUserDefaultsSuite(
        prefix: String,
        failureMessage: String,
        failures: inout [String]
    ) -> UserDefaults? {
        let suiteName = "\(prefix).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            failures.append(failureMessage)
            return nil
        }

        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    static func makeFixtureImage(size: CGSize = CGSize(width: 160, height: 100)) -> (image: NSImage, cgImage: CGImage)? {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2))

        context.setFillColor(NSColor.systemGreen.cgColor)
        context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height / 2))

        context.setFillColor(NSColor.systemOrange.cgColor)
        context.fill(CGRect(x: 0, y: size.height / 2, width: size.width / 2, height: size.height / 2))

        context.setFillColor(NSColor.systemPurple.cgColor)
        context.fill(CGRect(x: size.width / 2, y: size.height / 2, width: size.width / 2, height: size.height / 2))

        guard let cgImage = context.makeImage() else {
            return nil
        }

        return (NSImage(cgImage: cgImage, size: size), cgImage)
    }

    static func makeAnnotatedCapture(
        recognizedText: String = "Hello PinShot",
        textOverlay: String = "Demo"
    ) -> CaptureItem? {
        guard let fixture = makeFixtureImage() else {
            return nil
        }

        let item = CaptureItem(
            image: fixture.image,
            cgImage: fixture.cgImage,
            originalRect: CGRect(origin: .zero, size: fixture.image.size),
            recognizedText: recognizedText
        )
        item.isRecognizingText = false
        item.annotations = [
            ImageAnnotation(
                kind: .rectangle(CGRect(x: 0.1, y: 0.12, width: 0.42, height: 0.44)),
                color: .red,
                lineWidth: 4
            ),
            ImageAnnotation(
                kind: .text(content: textOverlay, origin: CGPoint(x: 0.58, y: 0.62)),
                color: .blue,
                lineWidth: 3,
                fontSize: 22
            ),
            ImageAnnotation(
                kind: .mosaic(rect: CGRect(x: 0.56, y: 0.1, width: 0.28, height: 0.34)),
                color: .yellow,
                lineWidth: 4
            )
        ]
        return item
    }

    static func expect(
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

    static func finish(
        failures: [String],
        successMessage: String,
        failureMessage: String
    ) -> Bool {
        if failures.isEmpty {
            print(successMessage)
            return true
        }

        print(failureMessage)
        failures.forEach { print("- \($0)") }
        return false
    }
}
