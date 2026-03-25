import Foundation
import NaturalLanguage
@preconcurrency import Translation

struct TranslationPlan {
    let configuration: TranslationSession.Configuration
    let label: String
}

enum TranslationSupport {
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
            configuration: .init(source: sourceLanguage, target: targetLanguage),
            label: "\(languageLabel(for: detectedLanguage)) -> \(languageLabel(for: targetLanguage))"
        )
    }

    private static func localeLanguage(from language: NLLanguage?) -> Locale.Language? {
        guard let language else { return nil }

        switch language {
        case .simplifiedChinese:
            return Locale.Language(identifier: "zh-Hans")
        case .traditionalChinese:
            return Locale.Language(identifier: "zh-Hant")
        case .english:
            return Locale.Language(identifier: "en")
        case .japanese:
            return Locale.Language(identifier: "ja")
        case .korean:
            return Locale.Language(identifier: "ko")
        default:
            return Locale.Language(identifier: language.rawValue)
        }
    }

    private static func targetLanguage(for language: NLLanguage?) -> Locale.Language {
        switch language {
        case .simplifiedChinese, .traditionalChinese:
            return Locale.Language(identifier: "en")
        default:
            return Locale.Language(identifier: "zh-Hans")
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

    private static func languageLabel(for language: Locale.Language?) -> String {
        guard let identifier = language?.minimalIdentifier else {
            return "Auto"
        }

        switch identifier {
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
            return identifier
        }
    }
}
