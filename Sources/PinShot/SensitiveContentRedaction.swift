import CoreGraphics
import Foundation
@preconcurrency import Vision

enum SensitiveContentKind: String, CaseIterable, Hashable {
    case email
    case phoneNumber
    case link
    case identifier
    case qrCode

    var title: String {
        switch self {
        case .email:
            return "emails"
        case .phoneNumber:
            return "phone numbers"
        case .link:
            return "links"
        case .identifier:
            return "IDs"
        case .qrCode:
            return "QR codes"
        }
    }
}

struct SensitiveTextMatch: Equatable {
    let kind: SensitiveContentKind
    let text: String
    let range: NSRange
}

struct SensitiveRedactionScanResult {
    let regions: [CGRect]
    let kinds: Set<SensitiveContentKind>
}

enum SensitiveContentRedactionSupport {
    private struct MatchCandidate {
        let kind: SensitiveContentKind
        let text: String
        let range: NSRange
        let priority: Int
    }

    private struct PatternDefinition: @unchecked Sendable {
        let kind: SensitiveContentKind
        let regex: NSRegularExpression
        let priority: Int
        let validator: (String) -> Bool
    }

    private static let emailRegex = try! NSRegularExpression(
        pattern: #"\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b"#,
        options: [.caseInsensitive]
    )

    private static let linkRegex = try! NSRegularExpression(
        pattern: #"\b(?:https?://|www\.)[^\s<>()]+(?:/[^\s<>()]*)?"#,
        options: [.caseInsensitive]
    )

    private static let phoneRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Z0-9])(?:\+?\d[\d .\-()]{6,}\d)(?![A-Z0-9])"#,
        options: [.caseInsensitive]
    )

    private static let identifierRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Z0-9])(?:[A-Z]{1,4}[-_])?(?:[A-Z0-9]{8,}|(?:\d[- ]?){8,})(?![A-Z0-9])"#,
        options: [.caseInsensitive]
    )

    private static let patterns: [PatternDefinition] = [
        PatternDefinition(kind: .email, regex: emailRegex, priority: 4) { _ in true },
        PatternDefinition(kind: .link, regex: linkRegex, priority: 3) { _ in true },
        PatternDefinition(kind: .phoneNumber, regex: phoneRegex, priority: 2) { text in
            isLikelyPhoneNumber(text)
        },
        PatternDefinition(kind: .identifier, regex: identifierRegex, priority: 1) { text in
            isLikelyIdentifier(text)
        }
    ]

    static func matches(in text: String) -> [SensitiveTextMatch] {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var candidates: [MatchCandidate] = []

        for pattern in patterns {
            pattern.regex.enumerateMatches(in: text, options: [], range: fullRange) { result, _, _ in
                guard let result,
                      let range = Range(result.range, in: text) else {
                    return
                }

                let matchedText = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !matchedText.isEmpty, pattern.validator(matchedText) else {
                    return
                }

                candidates.append(
                    MatchCandidate(
                        kind: pattern.kind,
                        text: matchedText,
                        range: result.range,
                        priority: pattern.priority
                    )
                )
            }
        }

        return deduplicated(candidates).map {
            SensitiveTextMatch(kind: $0.kind, text: $0.text, range: $0.range)
        }
    }

    static func mergedRegions(from rects: [CGRect]) -> [CGRect] {
        let padding = CGSize(width: 0.014, height: 0.02)
        let proximity = CGSize(width: 0.01, height: 0.016)
        var merged: [CGRect] = []

        for rect in rects {
            var candidate = clamp(rect.insetBy(dx: -padding.width, dy: -padding.height))
            var mergedExisting = true

            while mergedExisting {
                mergedExisting = false

                for index in merged.indices.reversed() {
                    let existing = merged[index]
                    if shouldMerge(existing, candidate, proximity: proximity) {
                        candidate = clamp(existing.union(candidate))
                        merged.remove(at: index)
                        mergedExisting = true
                    }
                }
            }

            merged.append(candidate)
        }

        return merged.sorted {
            if abs($0.minY - $1.minY) > 0.0001 {
                return $0.minY > $1.minY
            }
            return $0.minX < $1.minX
        }
    }

    private static func deduplicated(_ candidates: [MatchCandidate]) -> [MatchCandidate] {
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.range.length > rhs.range.length
        }

        var kept: [MatchCandidate] = []

        for candidate in sorted {
            if let index = kept.firstIndex(where: { NSIntersectionRange($0.range, candidate.range).length > 0 }) {
                let existing = kept[index]
                if candidate.priority > existing.priority ||
                    (candidate.priority == existing.priority && candidate.range.length > existing.range.length) {
                    kept[index] = candidate
                }
                continue
            }

            kept.append(candidate)
        }

        return kept.sorted { $0.range.location < $1.range.location }
    }

    private static func shouldMerge(_ lhs: CGRect, _ rhs: CGRect, proximity: CGSize) -> Bool {
        let expandedLHS = lhs.insetBy(dx: -proximity.width, dy: -proximity.height)
        let expandedRHS = rhs.insetBy(dx: -proximity.width, dy: -proximity.height)
        return expandedLHS.intersects(expandedRHS) || expandedLHS.contains(expandedRHS) || expandedRHS.contains(expandedLHS)
    }

    private static func clamp(_ rect: CGRect) -> CGRect {
        let x = min(1, max(0, rect.minX))
        let y = min(1, max(0, rect.minY))
        let width = max(0, min(1 - x, rect.width))
        let height = max(0, min(1 - y, rect.height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func isLikelyPhoneNumber(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber)
        guard digits.count >= 7, digits.count <= 15 else {
            return false
        }

        let letters = text.filter(\.isLetter)
        return letters.isEmpty
    }

    private static func isLikelyIdentifier(_ text: String) -> Bool {
        guard !isLikelyPhoneNumber(text) else {
            return false
        }

        let compact = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        let digits = compact.filter(\.isNumber)
        let letters = compact.filter(\.isLetter)

        guard compact.count >= 8 else {
            return false
        }

        if letters.count >= 2 && digits.count >= 4 {
            return true
        }

        return digits.count >= 10
    }
}

final class SensitiveContentRedactionService: @unchecked Sendable {
    private struct Detection {
        let kind: SensitiveContentKind
        let rect: CGRect
    }

    func detectRegions(in cgImage: CGImage) async -> SensitiveRedactionScanResult {
        async let textDetections = detectSensitiveText(in: cgImage)
        async let barcodeDetections = detectQRCodes(in: cgImage)

        let allDetections = await textDetections + barcodeDetections
        let mergedRegions = SensitiveContentRedactionSupport.mergedRegions(from: allDetections.map(\.rect))
        return SensitiveRedactionScanResult(
            regions: mergedRegions,
            kinds: Set(allDetections.map(\.kind))
        )
    }

    private func detectSensitiveText(in cgImage: CGImage) async -> [Detection] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                var detections: [Detection] = []

                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else {
                        continue
                    }

                    for match in SensitiveContentRedactionSupport.matches(in: candidate.string) {
                        guard let range = Range(match.range, in: candidate.string),
                              let rectangle = try? candidate.boundingBox(for: range) else {
                            continue
                        }

                        detections.append(Detection(kind: match.kind, rect: rectangle.boundingBox))
                    }
                }

                continuation.resume(returning: detections)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    return
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    private func detectQRCodes(in cgImage: CGImage) async -> [Detection] {
        await withCheckedContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, _ in
                let observations = request.results as? [VNBarcodeObservation] ?? []
                let detections = observations
                    .filter { $0.symbology == .qr }
                    .map { Detection(kind: .qrCode, rect: $0.boundingBox) }
                continuation.resume(returning: detections)
            }

            request.symbologies = [.qr]

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    return
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}
