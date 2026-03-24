import SwiftUI

struct ContentView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PinShot")
                .font(.title2.bold())

            Text(appModel.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button("开始截图") {
                Task {
                    await appModel.captureAndPin()
                }
            }
            .help("开始框选截图，松手后可以选择钉住、重选或取消")

            Button("显示最近一次置顶结果") {
                if let first = appModel.captures.first {
                    appModel.reopenPinnedPanel(for: first)
                }
            }
            .disabled(appModel.captures.isEmpty)
            .help("把最近一张贴图重新显示到桌面上")

            Divider()

            Text("快捷键")
                .font(.headline)

            Text(appModel.isRecordingHotKey ? "请直接按下新的快捷键" : "当前: \(appModel.hotKeyConfiguration.display)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(appModel.isRecordingHotKey ? "取消录制快捷键" : "设置快捷键") {
                if appModel.isRecordingHotKey {
                    appModel.stopHotKeyRecording()
                } else {
                    appModel.beginHotKeyRecording()
                }
            }
            .help(appModel.isRecordingHotKey ? "停止录制新的快捷键组合" : "点击后直接按下新的截图快捷键")

            Text("历史截图")
                .font(.headline)

            if appModel.captures.isEmpty {
                Text("还没有截图记录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appModel.captures.prefix(6)) { item in
                            Button {
                                appModel.reopenPinnedPanel(for: item)
                            } label: {
                                HStack {
                                    Image(nsImage: item.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 44, height: 32)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.recognizedText.prefix(24).isEmpty ? "截图 \(item.createdAt.formatted(date: .omitted, time: .standard))" : String(item.recognizedText.prefix(24)))
                                            .lineLimit(1)
                                        Text(item.createdAt.formatted(date: .omitted, time: .standard))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .help("重新打开这张历史贴图")
                        }
                    }
                }
                .frame(maxHeight: 180)

                Button("关闭全部贴图并清空历史") {
                    appModel.closeAllPins()
                }
                .help("关闭桌面上所有贴图，并清空当前历史记录")
            }

            Divider()

            Text("快捷键后先框选，松手后点钉住；贴图支持触控板捏合和标注")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .help("退出 PinShot")
        }
        .padding(16)
        .frame(width: 280)
    }
}
