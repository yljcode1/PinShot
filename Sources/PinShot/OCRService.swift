import CoreGraphics
@preconcurrency import Vision

final class OCRService: @unchecked Sendable {
    func recognizeText(cgImage: CGImage) async -> String {
        guard !Task.isCancelled else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    do {
                        try handler.perform([request])
                        let text = (request.results ?? [])
                            .compactMap { $0.topCandidates(1).first?.string }
                            .joined(separator: "\n")
                        continuation.resume(returning: text)
                    } catch {
                        continuation.resume(returning: "")
                    }
                }
            }
        } onCancel: {
            request.cancel()
        }
    }
}
