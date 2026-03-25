import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
enum MosaicRenderer {
    private static let ciContext = CIContext(options: nil)

    static func makeImage(
        baseCGImage: CGImage,
        normalizedRect: CGRect,
        minimumBlockSize: CGFloat = 12
    ) -> CGImage? {
        let clampedX = max(0, min(1, normalizedRect.origin.x))
        let clampedY = max(0, min(1, normalizedRect.origin.y))
        let remainingWidth = max(0, 1 - clampedX)
        let remainingHeight = max(0, 1 - clampedY)
        let clamped = CGRect(
            x: clampedX,
            y: clampedY,
            width: max(0, min(remainingWidth, normalizedRect.width)),
            height: max(0, min(remainingHeight, normalizedRect.height))
        )

        guard clamped.width > 0.0001, clamped.height > 0.0001 else { return nil }

        let cropRect = CGRect(
            x: clamped.minX * CGFloat(baseCGImage.width),
            y: clamped.minY * CGFloat(baseCGImage.height),
            width: clamped.width * CGFloat(baseCGImage.width),
            height: clamped.height * CGFloat(baseCGImage.height)
        ).integral

        guard cropRect.width >= 2, cropRect.height >= 2 else { return nil }

        let ciImage = CIImage(cgImage: baseCGImage).cropped(to: cropRect)
        let filter = CIFilter.pixellate()
        filter.inputImage = ciImage
        let maxSide = max(cropRect.width, cropRect.height)
        let blockSize = max(minimumBlockSize, maxSide / 18)
        filter.scale = Float(blockSize)

        guard let output = filter.outputImage?.cropped(to: ciImage.extent) else {
            return nil
        }

        return ciContext.createCGImage(output, from: ciImage.extent)
    }
}
