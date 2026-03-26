import Foundation
import NaturalLanguage

struct TranslationPlan {
    let sourceLanguageIdentifier: String?
    let targetLanguageIdentifier: String
    let label: String
}

enum TranslationSupport {
    static var isRuntimeSupported: Bool {
        if #available(macOS 15, *) {
            return true
        }

        return false
    }

    static let unavailableMessage = "Translation requires macOS 15 or later"

    static func plan(for text: String) -> TranslationPlan? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != CaptureText.noTextRecognized else {
            return nil
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let detectedLanguage = recognizer.dominantLanguage

        let sourceLanguage = localeLanguage(from: detectedLanguage)
        let targetLanguage = targetLanguage(for: detectedLanguage)

        return TranslationPlan(
            sourceLanguageIdentifier: sourceLanguage,
            targetLanguageIdentifier: targetLanguage,
            label: "\(languageLabel(for: detectedLanguage)) -> \(languageLabel(for: targetLanguage))"
        )
    }

    private static func localeLanguage(from language: NLLanguage?) -> String? {
        guard let language else { return nil }

        switch language {
        case .simplifiedChinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        case .english:
            return "en"
        case .japanese:
            return "ja"
        case .korean:
            return "ko"
        default:
            return language.rawValue
        }
    }

    private static func targetLanguage(for language: NLLanguage?) -> String {
        switch language {
        case .simplifiedChinese, .traditionalChinese:
            return "en"
        default:
            return "zh-Hans"
        }
    }

    private static func languageLabel(for language: NLLanguage?) -> String {
        switch language {
        case .simplifiedChinese:
            return "Chinese (Simplified)"
        case .traditionalChinese:
            return "Chinese (Traditional)"
        case .english:
            return "English"
        case .japanese:
            return "Japanese"
        case .korean:
            return "Korean"
        case .none:
            return "Auto-detect"
        default:
            return language?.rawValue ?? "Auto-detect"
        }
    }

    private static func languageLabel(for languageIdentifier: String?) -> String {
        guard let languageIdentifier else {
            return "Auto"
        }

        switch languageIdentifier {
        case "zh", "zh-Hans":
            return "Chinese (Simplified)"
        case "zh-Hant":
            return "Chinese (Traditional)"
        case "en":
            return "English"
        case "ja":
            return "Japanese"
        case "ko":
            return "Korean"
        default:
            return languageIdentifier
        }
    }
}
