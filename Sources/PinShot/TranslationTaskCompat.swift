import SwiftUI

#if canImport(Translation) && canImport(_Translation_SwiftUI)
@preconcurrency import Translation
@preconcurrency import _Translation_SwiftUI

@available(macOS 15, *)
private extension TranslationPlan {
    var configuration: TranslationSession.Configuration {
        TranslationSession.Configuration(
            source: sourceLanguageIdentifier.map(Locale.Language.init(identifier:)),
            target: Locale.Language(identifier: targetLanguageIdentifier)
        )
    }
}

@available(macOS 15, *)
private struct PinShotTranslationTaskModifier: ViewModifier {
    let plan: TranslationPlan
    let text: String
    let onSuccess: @MainActor (String) -> Void
    let onFailure: @MainActor (String) -> Void

    func body(content: Content) -> some View {
        content.translationTask(plan.configuration) { session in
            do {
                let response = try await session.translate(text)
                await MainActor.run {
                    onSuccess(response.targetText)
                }
            } catch {
                await MainActor.run {
                    onFailure(error.localizedDescription)
                }
            }
        }
    }
}
#endif

extension View {
    @ViewBuilder
    func pinShotTranslationTask(
        plan: TranslationPlan?,
        text: String,
        onSuccess: @escaping @MainActor (String) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) -> some View {
#if canImport(Translation) && canImport(_Translation_SwiftUI)
        if #available(macOS 15, *), let plan {
            modifier(
                PinShotTranslationTaskModifier(
                    plan: plan,
                    text: text,
                    onSuccess: onSuccess,
                    onFailure: onFailure
                )
            )
        } else {
            self
        }
#else
        self
#endif
    }
}
