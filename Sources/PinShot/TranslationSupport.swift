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
        guard !trimmed.isEmpty, trimmed != "没有识别到文字" else {
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
            return "中文简体"
        case .traditionalChinese:
            return "中文繁体"
        case .english:
            return "英文"
        case .japanese:
            return "日文"
        case .korean:
            return "韩文"
        case .none:
            return "自动识别"
        default:
            return language?.rawValue ?? "自动识别"
        }
    }

    private static func languageLabel(for language: Locale.Language?) -> String {
        guard let identifier = language?.minimalIdentifier else {
            return "自动"
        }

        switch identifier {
        case "zh", "zh-Hans":
            return "中文简体"
        case "zh-Hant":
            return "中文繁体"
        case "en":
            return "英文"
        case "ja":
            return "日文"
        case "ko":
            return "韩文"
        default:
            return identifier
        }
    }
}
