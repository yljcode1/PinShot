import SwiftUI
@preconcurrency import Translation
@preconcurrency import _Translation_SwiftUI

struct PinPreviewView: View {
    @Bindable var appModel: AppModel
    @Bindable var item: CaptureItem
    @State private var pendingTranslationText = ""
    @State private var translationConfiguration: TranslationSession.Configuration?

    private let selectionColor = Color(red: 0.34, green: 0.63, blue: 1.0)

    private var isSelected: Bool {
        appModel.isSelected(item)
    }

    private var captureAspectRatio: CGFloat {
        max(item.originalRect.width, 1) / max(item.originalRect.height, 1)
    }

    private var inspectorStatusText: String {
        if item.isRecognizingText {
            return "OCR Running"
        }

        if item.hasRecognizedText {
            return "OCR Ready"
        }

        return "No OCR Text"
    }

    var body: some View {
        VStack(spacing: 10) {
            captureSurface

            if isSelected && item.showToolbar {
                toolbarView
                    .zIndex(1)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if item.showInspector {
                inspectorView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .translationTask(translationConfiguration) { session in
            do {
                let response = try await translateText(using: session, text: pendingTranslationText)
                await MainActor.run {
                    item.translatedText = response.targetText
                    item.isTranslating = false
                    translationConfiguration = nil
                    appModel.statusMessage = "Translation complete"
                }
            } catch {
                await MainActor.run {
                    item.translatedText = "Translation failed: \(error.localizedDescription)"
                    item.isTranslating = false
                    translationConfiguration = nil
                    appModel.statusMessage = "Translation failed"
                }
            }
        }
        .animation(.easeInOut(duration: 0.16), value: item.showToolbar)
        .animation(.easeInOut(duration: 0.16), value: item.showInspector)
    }

    private var captureSurface: some View {
        ZStack {
            if item.annotationTool == .selectText {
                LiveTextSelectionOverlayView(
                    image: item.image,
                    isActive: true,
                    onActivate: {
                        appModel.activateCaptureForInteraction(item)
                    },
                    onMagnify: { magnification in
                        appModel.magnify(for: item, magnification: magnification)
                    }
                )
            } else {
                Image(nsImage: item.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            AnnotationOverlayView(
                appModel: appModel,
                item: item,
                onMagnify: { magnification in
                    appModel.magnify(for: item, magnification: magnification)
                }
            )
            .allowsHitTesting(item.annotationTool != .selectText)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? selectionColor : Color.black.opacity(0.18),
                    lineWidth: isSelected ? 2.5 : 1
                )
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectionColor.opacity(0.55), lineWidth: 2)
                    .blur(radius: 2.5)
            }
        }
        .shadow(
            color: isSelected ? .black.opacity(0.16) : .black.opacity(0.10),
            radius: isSelected ? 4 : 6
        )
        .overlay {
            if item.annotationTool == .none {
                InteractionCaptureView(
                    onMagnify: { magnification in
                        appModel.magnify(for: item, magnification: magnification)
                    },
                    onPrimaryClick: {
                        appModel.toggleToolbar(for: item)
                    },
                    onDoubleClick: {
                        appModel.removeCapture(item)
                    },
                    onSecondaryClick: {
                        appModel.toggleToolbar(for: item)
                    }
                )
            }
        }
        .aspectRatio(captureAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private var toolbarView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ToolbarGroupCard(title: "Panels") {
                    Button {
                        appModel.toggleInspector(for: item)
                    } label: {
                        Label("Text", systemImage: item.showInspector ? "text.bubble.fill" : "text.bubble")
                    }
                    .buttonStyle(PinCapsuleButtonStyle(prominence: item.showInspector ? .primary : .secondary))
                    .help(item.showInspector ? "Hide OCR and translation results" : "Open OCR and translation results")
                }

                ToolbarGroupCard(title: "Tools") {
                    HStack(spacing: 6) {
                        annotationToolButton(.none, label: "cursorarrow")
                        annotationToolButton(.selectText, label: "text.cursor")
                        annotationToolButton(.pen, label: "pencil.tip")
                        annotationToolButton(.rectangle, label: "rectangle")
                        annotationToolButton(.mosaic, label: "checkerboard.rectangle")
                        annotationToolButton(.arrow, label: "arrow.up.right")
                        annotationToolButton(.text, label: "character.textbox")
                    }
                }

                ToolbarGroupCard(title: "Colors") {
                    HStack(spacing: 8) {
                        ForEach(0..<AnnotationColor.presets.count, id: \.self) { index in
                            let color = AnnotationColor.presets[index]
                            Button {
                                appModel.setAnnotationColor(color, for: item)
                            } label: {
                                Circle()
                                    .fill(Color(color.nsColor))
                                    .frame(width: 14, height: 14)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(item.annotationColor == color ? Color.white : Color.clear, lineWidth: 1.6)
                                            .frame(width: 18, height: 18)
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(colorTooltip(for: color))
                        }
                    }
                }

                ToolbarGroupCard(title: "Zoom") {
                    HStack(spacing: 6) {
                        Button {
                            appModel.zoomOut(for: item)
                        } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(PinToolbarButtonStyle(isActive: false))
                        .help("Zoom out")

                        Text("\(Int(item.zoom * 100))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 48)

                        Button {
                            appModel.zoomIn(for: item)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(PinToolbarButtonStyle(isActive: false))
                        .help("Zoom in")

                        Button("Reset") {
                            appModel.resetZoom(for: item)
                        }
                        .buttonStyle(PinCapsuleButtonStyle(prominence: .subtle))
                        .help("Reset zoom back to 100%")
                    }
                }

                ToolbarGroupCard(title: "Actions") {
                    HStack(spacing: 6) {
                        Button {
                            appModel.undoLastAnnotation(for: item)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(PinToolbarButtonStyle(isActive: false))
                        .help("Undo last annotation")

                        Button {
                            appModel.clearAnnotations(for: item)
                        } label: {
                            Image(systemName: "trash.slash")
                        }
                        .buttonStyle(PinToolbarButtonStyle(isActive: false))
                        .help("Clear all annotations")

                        Button {
                            appModel.copyImage(for: item)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(PinToolbarButtonStyle(isActive: false))
                        .help("Copy image including annotations")

                        Menu {
                            Button("Save PNG") {
                                appModel.saveImage(for: item, format: .png)
                            }
                            Button("Save JPEG") {
                                appModel.saveImage(for: item, format: .jpeg)
                            }
                            Button("Export Package") {
                                appModel.exportCapturePackage(for: item)
                            }
                            if item.hasRecognizedText {
                                Button("Save OCR Text") {
                                    appModel.saveText(for: item, kind: .recognized)
                                }
                            }
                            if item.hasTranslatedText {
                                Button("Save Translated Text") {
                                    appModel.saveText(for: item, kind: .translated)
                                }
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(PinShotPalette.mutedForeground)
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                        }
                        .help("Export image or text results")

                        Button {
                            appModel.removeCapture(item)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(PinToolbarButtonStyle(isActive: false))
                        .help("Close this pin")
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    private var inspectorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Text Results")
                        .font(.headline)
                    Text("Review OCR, translate it if needed, then copy or export the text.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(item.translatedText.isEmpty ? "Translate" : "Translate Again") {
                    beginTranslation()
                }
                .buttonStyle(PinCapsuleButtonStyle(prominence: .primary))
                .disabled(item.isRecognizingText || item.recognizedText.isEmpty || item.recognizedText == CaptureText.noTextRecognized)
                .help("Translate recognized text")

                Button {
                    dismissInspector()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close the text panel")
            }

            HStack(spacing: 8) {
                PreviewInfoChip(systemImage: "text.viewfinder", text: inspectorStatusText)
                if item.isTranslating {
                    PreviewInfoChip(systemImage: "hourglass", text: "Translating")
                } else if item.hasTranslatedText {
                    PreviewInfoChip(systemImage: "globe", text: item.translationLabel.isEmpty ? "Translated" : item.translationLabel)
                }
                if item.hasAnnotations {
                    PreviewInfoChip(systemImage: "paintbrush.pointed", text: "\(item.annotations.count) mark\(item.annotations.count == 1 ? "" : "s")")
                }
            }

            InspectorResultPanel(
                title: "Recognized Text",
                text: item.isRecognizingText ? CaptureText.recognizing : recognizedTextBody,
                placeholder: "Recognition result will appear here",
                trailingButtons: {
                    HStack(spacing: 8) {
                        Button("Copy") {
                            appModel.copyRecognizedText(for: item)
                        }
                        .buttonStyle(PinCapsuleButtonStyle(prominence: .secondary))
                        .disabled(!item.hasRecognizedText)

                        Button("Save") {
                            appModel.saveText(for: item, kind: .recognized)
                        }
                        .buttonStyle(PinCapsuleButtonStyle(prominence: .subtle))
                        .disabled(!item.hasRecognizedText)
                    }
                }
            )

            InspectorResultPanel(
                title: item.translationLabel.isEmpty ? "Translation" : item.translationLabel,
                text: item.isTranslating ? "Translating..." : item.translatedText,
                placeholder: "Use Translate to generate a translated result",
                trailingButtons: {
                    HStack(spacing: 8) {
                        Button("Copy") {
                            appModel.copyTranslatedText(for: item)
                        }
                        .buttonStyle(PinCapsuleButtonStyle(prominence: .secondary))
                        .disabled(!item.hasTranslatedText)

                        Button("Save") {
                            appModel.saveText(for: item, kind: .translated)
                        }
                        .buttonStyle(PinCapsuleButtonStyle(prominence: .subtle))
                        .disabled(!item.hasTranslatedText)
                    }
                }
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Opacity")
                        .font(.caption.weight(.bold))
                    Spacer()
                    Text("\(Int(item.opacity * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(value: $item.opacity, in: 0.35...1.0)
                    .onChange(of: item.opacity) { _, _ in
                        appModel.updateOpacity(for: item)
                    }
                    .help("Adjust pin opacity")
            }
        }
        .pinShotGlassCard()
        .frame(maxWidth: .infinity)
    }

    private func annotationToolButton(_ tool: AnnotationTool, label: String) -> some View {
        Button {
            appModel.setAnnotationTool(tool, for: item)
        } label: {
            Image(systemName: label)
        }
        .buttonStyle(PinToolbarButtonStyle(isActive: item.annotationTool == tool))
        .help(annotationToolTooltip(for: tool))
    }

    nonisolated private func translateText(
        using session: TranslationSession,
        text: String
    ) async throws -> TranslationSession.Response {
        try await session.translate(text)
    }

    private var recognizedTextBody: String {
        if item.recognizedText.isEmpty {
            return ""
        }

        return item.recognizedText == CaptureText.noTextRecognized ? "" : item.recognizedText
    }

    private func dismissInspector() {
        item.showInspector = false
        appModel.refreshCapture(item)
    }

    private func beginTranslation() {
        guard let plan = TranslationSupport.plan(for: item.recognizedText) else {
            appModel.statusMessage = "No text to translate"
            return
        }

        item.showInspector = true
        item.isTranslating = true
        item.translatedText = ""
        item.translationLabel = plan.label
        pendingTranslationText = item.recognizedText
        translationConfiguration = plan.configuration
        appModel.statusMessage = "Translating..."
    }

    private func annotationToolTooltip(for tool: AnnotationTool) -> String {
        switch tool {
        case .none:
            return "Normal mode: drag pins, pinch to zoom"
        case .selectText:
            return "Select text inside the image"
        case .pen:
            return "Freehand pen"
        case .rectangle:
            return "Draw highlight rectangles"
        case .arrow:
            return "Point at content with an arrow"
        case .mosaic:
            return "Blur a region with mosaic"
        case .text:
            return "Add editable text"
        }
    }

    private func colorTooltip(for color: AnnotationColor) -> String {
        switch color {
        case .red:
            return "Switch annotation color to red"
        case .blue:
            return "Switch annotation color to blue"
        default:
            return "Switch annotation color"
        }
    }

}

private struct ToolbarGroupCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

private struct PreviewInfoChip: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
    }
}

private struct InspectorResultPanel<TrailingButtons: View>: View {
    let title: String
    let text: String
    let placeholder: String
    let trailingButtons: TrailingButtons

    init(
        title: String,
        text: String,
        placeholder: String,
        @ViewBuilder trailingButtons: () -> TrailingButtons
    ) {
        self.title = title
        self.text = text
        self.placeholder = placeholder
        self.trailingButtons = trailingButtons()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                Spacer()
                trailingButtons
            }

            ScrollView {
                Text(displayText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
            }
            .frame(minHeight: 64, maxHeight: 110)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
        }
    }

    private var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? placeholder : text
    }
}
