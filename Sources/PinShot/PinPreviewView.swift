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
        VStack(spacing: 0) {
            captureSurface

            if isSelected && item.showToolbar {
                toolbarView
                    .padding(.top, -4)
                    .zIndex(1)
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
                    appModel.statusMessage = "翻译完成"
                }
            } catch {
                await MainActor.run {
                    item.translatedText = "翻译失败: \(error.localizedDescription)"
                    item.isTranslating = false
                    translationConfiguration = nil
                    appModel.statusMessage = "翻译失败"
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
        .overlay(alignment: .bottom) {
            if item.showInspector {
                inspectorView
                    .padding(10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
                .help(item.showInspector ? "收起文字面板" : "打开文字面板，查看 OCR 和翻译结果")

                annotationToolButton(.none, label: "cursorarrow")
                annotationToolButton(.selectText, label: "text.cursor")
                annotationToolButton(.pen, label: "pencil.tip")
                annotationToolButton(.rectangle, label: "rectangle")
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
                .help("撤销上一笔标注")

                Button {
                    appModel.clearAnnotations(for: item)
                } label: {
                    Image(systemName: "trash")
                }
                .help("清空这张贴图上的全部标注")

                Button {
                    appModel.copyImage(for: item)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("复制当前贴图，包含你已经画上的标注")

                Button {
                    appModel.saveImage(for: item)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("保存当前贴图，包含你已经画上的标注")

                Button {
                    appModel.removeCapture(item)
                } label: {
                    Image(systemName: "xmark")
                }
                .help("关闭这张贴图")
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
            appModel.statusMessage = "没有可翻译的文字"
            return
        }

        item.showInspector = true
        item.isTranslating = true
        item.translatedText = "正在翻译..."
        item.translationLabel = plan.label
        pendingTranslationText = item.recognizedText
        translationConfiguration = plan.configuration
        appModel.statusMessage = "正在翻译..."
    }

    private func annotationToolTooltip(for tool: AnnotationTool) -> String {
        switch tool {
        case .none:
            return "回到普通模式，可以拖动贴图和手势缩放"
        case .selectText:
            return "像微信一样直接选择图片里的文字，选中后可复制"
        case .pen:
            return "自由画笔，直接在图片上涂画"
        case .rectangle:
            return "绘制矩形框，适合框重点"
        case .arrow:
            return "绘制箭头，指向重点内容"
        case .text:
            return "添加文字标注；单击可选中和拖动，双击可编辑，也支持 ⌘V 直接粘贴文字"
        }
    }

    private func colorTooltip(for color: AnnotationColor) -> String {
        switch color {
        case .red:
            return "切换标注颜色为红色"
        case .blue:
            return "切换标注颜色为蓝色"
        default:
            return "切换标注颜色"
        }
    }

    private var inspectorView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("文字面板")
                        .font(.caption.weight(.bold))
                    Text("先看识别原文，需要时再在这里翻译")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(item.translatedText.isEmpty ? "翻译" : "重新翻译") {
                    beginTranslation()
                }
                .buttonStyle(.plain)
                .disabled(item.isRecognizingText || item.recognizedText.isEmpty || item.recognizedText == "没有识别到文字")
                .help("把识别到的文字翻译成另一种语言，结果也显示在这里")
                Button("复制") {
                    appModel.copyRecognizedText(for: item)
                }
                .buttonStyle(.plain)
                .help("复制 OCR 识别出的原文")
                Button {
                    dismissInspector()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭文字面板")
            }

            ScrollView {
                Text(item.isRecognizingText ? "正在识别文字..." : (item.recognizedText.isEmpty ? "识别结果会显示在这里" : item.recognizedText))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 90)

            if item.isTranslating || !item.translatedText.isEmpty {
                Divider()

                HStack {
                    Text(item.translationLabel.isEmpty ? "翻译结果" : item.translationLabel)
                        .font(.caption.weight(.bold))
                    Spacer()
                    if item.isTranslating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                ScrollView {
                    Text(item.translatedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 90)
            }

            HStack(spacing: 12) {
                Text("透明度")
                    .font(.caption.weight(.bold))
                Slider(value: $item.opacity, in: 0.35...1.0)
                    .onChange(of: item.opacity) { _, _ in
                        appModel.updateOpacity(for: item)
                    }
                    .help("调整贴图透明度，不影响复制和保存时的清晰度")
                Text("\(Int(item.opacity * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
        .help("这里会显示识别和翻译结果；点贴图空白处可收起这个面板")
    }
}
