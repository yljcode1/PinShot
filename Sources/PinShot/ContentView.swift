import SwiftUI

struct ContentView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MenuHeaderView(
                    statusMessage: appModel.statusMessage,
                    latestCapture: appModel.latestCapture,
                    captureCount: appModel.captures.count
                )

                MenuQuickActionsView(appModel: appModel)

                HotKeySection(appModel: appModel)

                HistorySection(appModel: appModel)

                FooterSection(appModel: appModel)
            }
            .padding(20)
        }
        .frame(width: 320)
    }
}

// MARK: - Sections

private struct MenuHeaderView: View {
    let statusMessage: String
    let latestCapture: CaptureItem?
    let captureCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PinShot")
                        .font(.title2.bold())
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if let latestCapture {
                    VStack(spacing: 4) {
                        Image(nsImage: latestCapture.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                            }
                        Text(latestCapture.createdAt.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Label(
                captureCount == 0 ? "使用快捷键或下方按钮开始截图" : "最近 \(captureCount) 张贴图可重新打开",
                systemImage: captureCount == 0 ? "sparkles" : "pin.fill"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .pinShotGlassCard()
    }
}

private struct MenuQuickActionsView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快速操作")
                .font(.headline)

            HStack(spacing: 12) {
                QuickActionButton(
                    title: "开始截图",
                    systemImage: "camera.viewfinder",
                    tint: PinShotPalette.selectionBlue
                ) {
                    Task {
                        await appModel.captureAndPin()
                    }
                }

                QuickActionButton(
                    title: "最近贴图",
                    systemImage: "rectangle.on.rectangle.angled",
                    tint: .purple.opacity(0.85)
                ) {
                    appModel.reopenLatestCapture()
                }
                .disabled(!appModel.hasCaptures)
                .help("把最近一张贴图重新显示到桌面上")

                QuickActionButton(
                    title: "清空",
                    systemImage: "trash",
                    tint: .pink.opacity(0.85)
                ) {
                    appModel.closeAllPins()
                }
                .disabled(!appModel.hasCaptures)
                .help("关闭桌面上所有贴图，并清空当前历史记录")
            }
        }
        .pinShotGlassCard()
    }
}

private struct HotKeySection: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("全局快捷键", systemImage: "keyboard")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appModel.isRecordingHotKey ? "等待新的组合..." : appModel.hotKeyConfiguration.display)
                        .font(.title3.weight(.semibold))
                    Text(appModel.isRecordingHotKey ? "请直接按下想要的组合键" : "可在任何界面使用该快捷键开始截图")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(appModel.isRecordingHotKey ? "完成" : "更改") {
                    if appModel.isRecordingHotKey {
                        appModel.stopHotKeyRecording()
                    } else {
                        appModel.beginHotKeyRecording()
                    }
                }
                .buttonStyle(PinCapsuleButtonStyle(prominence: appModel.isRecordingHotKey ? .primary : .secondary))
                .help(appModel.isRecordingHotKey ? "停止录制新的快捷键组合" : "点击后直接按下新的截图快捷键")
            }
        }
        .pinShotGlassCard()
    }
}

private struct HistorySection: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("历史贴图", systemImage: "clock")
                .font(.headline)

            if appModel.hasCaptures {
                VStack(spacing: 8) {
                    ForEach(appModel.captures.prefix(6)) { item in
                        HistoryRow(item: item) {
                            appModel.reopenPinnedPanel(for: item)
                        }
                    }
                }
            } else {
                Text("还没有截图记录，先来一张吧～")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .pinShotGlassCard()
    }
}

private struct FooterSection: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("提示")
                .font(.headline)
            Text("快捷键后先框选，松手后点钉住；贴图支持触控板捏合、拖动和标注工具。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出 PinShot", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PinSidebarActionButtonStyle(isPrimary: true))
            .help("退出 PinShot")
        }
        .pinShotGlassCard()
    }
}

// MARK: - Reusable pieces

private struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(QuickActionButtonStyle(tint: tint))
    }
}

private struct QuickActionButtonStyle: ButtonStyle {
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(configuration.isPressed ? 0.85 : 1),
                                tint.opacity(0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                }
            }
            .opacity((configuration.isPressed ? 0.9 : 1) * (isEnabled ? 1 : 0.35))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct HistoryRow: View {
    @Bindable var item: CaptureItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: item.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(item.createdAt.formatted(date: .omitted, time: .standard))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var titleText: String {
        let snippet = item.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if snippet.isEmpty || snippet == "没有识别到文字" {
            return "截图 \(item.createdAt.formatted(date: .omitted, time: .shortened))"
        }
        return String(snippet.prefix(26))
    }
}
