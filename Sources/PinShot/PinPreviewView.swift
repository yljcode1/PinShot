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

    var body: some View {
        VStack(spacing: 8) {
            captureSurface

            if isSelected && item.showToolbar {
                toolbarView
                    .padding(.top, -4)
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
            if item.showInspector {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissInspector()
                    }
            }
        }
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
            HStack(spacing: 8) {
                Button {
                    appModel.toggleInspector(for: item)
                } label: {
                    Image(systemName: item.showInspector ? "text.bubble.fill" : "text.bubble")
                }
                .help(item.showInspector ? "Hide the text panel" : "Open the text panel to view OCR and translation")

                annotationToolButton(.none, label: "cursorarrow")
                annotationToolButton(.selectText, label: "text.cursor")
                annotationToolButton(.pen, label: "pencil.tip")
                annotationToolButton(.rectangle, label: "rectangle")
                annotationToolButton(.mosaic, label: "checkerboard.rectangle")
                annotationToolButton(.arrow, label: "arrow.up.right")
                annotationToolButton(.text, label: "character.textbox")

                ForEach(0..<AnnotationColor.presets.count, id: \.self) { index in
                    let color = AnnotationColor.presets[index]
                    Button {
                        appModel.setAnnotationColor(color, for: item)
                    } label: {
                        Circle()
                            .fill(Color(color.nsColor))
                            .frame(width: 12, height: 12)
                            .overlay {
                                if item.annotationColor == color {
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: 1.5)
                                        .frame(width: 16, height: 16)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(colorTooltip(for: color))
                }

                Button {
                    appModel.undoLastAnnotation(for: item)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .help("Undo last annotation")

                Button {
                    appModel.clearAnnotations(for: item)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Clear all annotations on this pin")

                Button {
                    appModel.copyImage(for: item)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy this pin including annotations")

                Button {
                    appModel.saveImage(for: item)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Save this pin including annotations")

                Button {
                    appModel.removeCapture(item)
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Close this pin")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func annotationToolButton(_ tool: AnnotationTool, label: String) -> some View {
        Button {
            appModel.setAnnotationTool(tool, for: item)
        } label: {
            Image(systemName: label)
                .foregroundStyle(item.annotationTool == tool ? Color.accentColor : .primary)
        }
        .help(annotationToolTooltip(for: tool))
    }

    nonisolated private func translateText(
        using session: TranslationSession,
        text: String
    ) async throws -> TranslationSession.Response {
        try await session.translate(text)
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
        item.translatedText = "Translating..."
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
            return "Select text in the image, then copy"
        case .pen:
            return "Freehand pen: draw directly on the pin"
        case .rectangle:
            return "Rectangle: draw boxes to highlight"
        case .arrow:
            return "Arrow: drag to point at content"
        case .mosaic:
            return "Mosaic: draw to blur, drag to move, drag handle to resize, Delete to remove"
        case .text:
            return "Text: click to add, double-click to edit, ⌘V to paste"
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

    private var inspectorView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Text Panel")
                        .font(.caption.weight(.bold))
                    Text("View OCR text here and translate if needed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(item.translatedText.isEmpty ? "Translate" : "Translate Again") {
                    beginTranslation()
                }
                .buttonStyle(.plain)
                .disabled(item.isRecognizingText || item.recognizedText.isEmpty || item.recognizedText == CaptureText.noTextRecognized)
                .help("Translate recognized text to another language")
                Button("Copy") {
                    appModel.copyRecognizedText(for: item)
                }
                .buttonStyle(.plain)
                .help("Copy recognized text")
                Button {
                    dismissInspector()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close the text panel")
            }

            ScrollView {
                Text(item.isRecognizingText ? CaptureText.recognizing : (item.recognizedText.isEmpty ? "Recognition result will appear here" : item.recognizedText))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 90)

            if item.isTranslating || !item.translatedText.isEmpty {
                Divider()

                HStack {
                    Text(item.translationLabel.isEmpty ? "Translation" : item.translationLabel)
                        .font(.caption.weight(.bold))
                    Spacer()
                    if item.isTranslating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                ScrollView {
                    Text(item.translatedText.isEmpty ? "Translated text will appear here" : item.translatedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 90)
            }

            HStack(spacing: 12) {
                Text("Opacity")
                    .font(.caption.weight(.bold))
                Slider(value: $item.opacity, in: 0.35...1.0)
                    .onChange(of: item.opacity) { _, _ in
                        appModel.updateOpacity(for: item)
                    }
                    .help("Adjust pin opacity (copy/save stays clear)")
                Text("\(Int(item.opacity * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .pinShotGlassCard()
        .frame(maxWidth: .infinity)
        .help("View recognition and translation results; tap the pin to close")
    }
}
