import SwiftUI

struct ContentView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MenuHeaderView(appModel: appModel)

                if appModel.isShowingSetupGuide {
                    SetupGuideSection(appModel: appModel)
                }

                MenuQuickActionsView(appModel: appModel)
                HotKeySection(appModel: appModel)
                PreferencesSection(appModel: appModel)
                HistorySection(appModel: appModel)
                FooterSection(appModel: appModel)
            }
            .padding(20)
        }
        .frame(width: 356, height: 650)
        .background(
            LinearGradient(
                colors: [
                    PinShotPalette.warmBackgroundTop.opacity(0.98),
                    PinShotPalette.warmBackgroundBottom.opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct MenuHeaderView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("PinShot")
                        .font(.title2.bold())

                    Text(appModel.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if let latestCapture = appModel.latestCapture {
                    VStack(spacing: 4) {
                        Image(nsImage: latestCapture.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
                            }
                        Text(latestCapture.createdAt.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                StatChip(title: "Pins", value: "\(appModel.captures.count)", systemImage: "pin.fill")
                StatChip(title: "OCR", value: "\(appModel.recognizedCaptureCount)", systemImage: "text.viewfinder")
                StatChip(title: "Translated", value: "\(appModel.translatedCaptureCount)", systemImage: "globe")
                StatChip(title: "Marked", value: "\(appModel.annotatedCaptureCount)", systemImage: "pencil.tip")
            }

            Label(
                appModel.isShowingSetupGuide
                    ? "Finish the setup guide or skip it below. You can reopen it later from Preferences."
                    : (appModel.hasCaptures
                        ? "Pinned captures are ready to reopen, export, or continue editing."
                        : "Use the hotkey or quick actions below to capture your first pin."),
                systemImage: appModel.isShowingSetupGuide ? "sparkles.rectangle.stack" : "wand.and.stars"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .pinShotGlassCard()
    }
}

private struct SetupGuideSection: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Getting Started",
                subtitle: "Grant the basics once, then PinShot can stay out of your way."
            )

            SetupStepCard(
                index: 1,
                title: "Allow Screen Recording",
                detail: "PinShot uses the system screenshot flow, so screen recording access is required before capturing."
            ) {
                Button("Open Settings") {
                    appModel.openSystemSettings(.screenRecording)
                }
                .buttonStyle(PinCapsuleButtonStyle(prominence: .primary))
            }

            SetupStepCard(
                index: 2,
                title: "Allow Accessibility",
                detail: "Some environments need Accessibility access so the global shortcut works reliably across apps."
            ) {
                Button("Open Settings") {
                    appModel.openSystemSettings(.accessibility)
                }
                .buttonStyle(PinCapsuleButtonStyle(prominence: .secondary))
            }

            SetupStepCard(
                index: 3,
                title: "Tune Startup & Shortcut",
                detail: "Choose whether PinShot starts automatically, and optionally change the default capture shortcut."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { appModel.launchAtLoginEnabled },
                        set: { appModel.setLaunchAtLoginEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Launch at Login")
                                .font(.subheadline.weight(.semibold))
                            Text(appModel.launchAtLoginDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current shortcut")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(appModel.isRecordingHotKey ? "Waiting for keys..." : appModel.hotKeyConfiguration.display)
                                .font(.subheadline.weight(.semibold))
                        }

                        Spacer()

                        Button(appModel.isRecordingHotKey ? "Finish" : "Change") {
                            if appModel.isRecordingHotKey {
                                appModel.stopHotKeyRecording()
                            } else {
                                appModel.beginHotKeyRecording()
                            }
                        }
                        .buttonStyle(PinCapsuleButtonStyle(prominence: appModel.isRecordingHotKey ? .primary : .secondary))
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Skip for Now") {
                    appModel.skipSetupGuide()
                }
                .buttonStyle(PinCapsuleButtonStyle(prominence: .secondary))

                Button("Done") {
                    appModel.completeSetupGuide()
                }
                .buttonStyle(PinCapsuleButtonStyle(prominence: .primary))
            }
        }
        .pinShotGlassCard()
    }
}

private struct MenuQuickActionsView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Quick Actions",
                subtitle: "Jump straight into the capture flow you need."
            )

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    QuickActionButton(
                        title: "Capture Selection",
                        systemImage: "camera.viewfinder",
                        tint: PinShotPalette.selectionBlue
                    ) {
                        Task {
                            await appModel.captureAndChooseAction()
                        }
                    }
                    .help("Capture an area, then choose Quick Edit, Pin, or Copy")

                    QuickActionButton(
                        title: "Copy Selection",
                        systemImage: "doc.on.doc",
                        tint: .teal.opacity(0.9)
                    ) {
                        Task {
                            await appModel.captureAndCopy()
                        }
                    }
                    .help("Capture an area and send it straight to the clipboard")
                }

                HStack(spacing: 12) {
                    QuickActionButton(
                        title: "Reopen Latest",
                        systemImage: "rectangle.on.rectangle.angled",
                        tint: .purple.opacity(0.85)
                    ) {
                        appModel.reopenLatestCapture()
                    }
                    .disabled(!appModel.hasCaptures)

                    QuickActionButton(
                        title: "Clear All Pins",
                        systemImage: "trash",
                        tint: .pink.opacity(0.85)
                    ) {
                        appModel.closeAllPins()
                    }
                    .disabled(!appModel.hasCaptures)
                }
            }
        }
        .pinShotGlassCard()
    }
}

private struct HotKeySection: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Global Hotkey",
                subtitle: "Use this anywhere to start a capture."
            )

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appModel.isRecordingHotKey ? "Waiting for new combo..." : appModel.hotKeyConfiguration.display)
                        .font(.title3.weight(.semibold))
                    Text(appModel.isRecordingHotKey ? "Press the keys you want to save." : "Default flow: capture, pin first, then choose what to do.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(appModel.isRecordingHotKey ? "Done" : "Change") {
                    if appModel.isRecordingHotKey {
                        appModel.stopHotKeyRecording()
                    } else {
                        appModel.beginHotKeyRecording()
                    }
                }
                .buttonStyle(PinCapsuleButtonStyle(prominence: appModel.isRecordingHotKey ? .primary : .secondary))
            }
        }
        .pinShotGlassCard()
    }
}

private struct PreferencesSection: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Preferences",
                subtitle: "Small switches that change how PinShot behaves."
            )

            Toggle(isOn: Binding(
                get: { appModel.launchAtLoginEnabled },
                set: { appModel.setLaunchAtLoginEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Launch at Login")
                        .font(.subheadline.weight(.semibold))
                    Text(appModel.launchAtLoginDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            HStack(spacing: 10) {
                Button("Reopen Setup Guide") {
                    appModel.reopenSetupGuide()
                }
                .buttonStyle(PinCapsuleButtonStyle(prominence: .secondary))

                Button("Open Login Items") {
                    appModel.openSystemSettings(.loginItems)
                }
                .buttonStyle(PinCapsuleButtonStyle(prominence: .subtle))
            }
        }
        .pinShotGlassCard()
    }
}

private struct HistorySection: View {
    @Bindable var appModel: AppModel

    private var visibleItems: [CaptureItem] {
        Array(appModel.filteredCaptures.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Pinned History",
                subtitle: "Search, filter, reopen, export, or remove recent captures."
            )

            TextField("Search OCR / translation", text: $appModel.historySearchText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                ForEach(CaptureHistoryFilter.allCases) { filter in
                    Button(filter.title) {
                        appModel.historyFilter = filter
                    }
                    .buttonStyle(FilterChipButtonStyle(isSelected: appModel.historyFilter == filter))
                }
            }

            if appModel.hasCaptures {
                Text("\(appModel.filteredCaptures.count) result\(appModel.filteredCaptures.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if visibleItems.isEmpty {
                    EmptyHistoryState(text: "No captures match the current search or filter.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(visibleItems) { item in
                            HistoryRow(item: item, appModel: appModel)
                        }
                    }
                }
            } else {
                EmptyHistoryState(text: "No captures yet — your next pin will show up here.")
            }
        }
        .pinShotGlassCard()
    }
}

private struct FooterSection: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Tips",
                subtitle: "A couple of quick reminders for the best flow."
            )

            VStack(alignment: .leading, spacing: 8) {
                TipRow(systemImage: "hand.tap", text: "Single-click a pin to show its toolbar, drag the surface to move it.")
                TipRow(systemImage: "arrow.up.left.and.arrow.down.right", text: "Use pinch or the toolbar zoom buttons to scale a pinned capture.")
                TipRow(systemImage: "rectangle.and.text.magnifyingglass", text: "OCR and translation results can be copied or exported as text files.")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit PinShot", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PinSidebarActionButtonStyle(isPrimary: true))
        }
        .pinShotGlassCard()
    }
}

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
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
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
                                tint.opacity(configuration.isPressed ? 0.84 : 1),
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
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                }
            }
            .opacity((configuration.isPressed ? 0.92 : 1) * (isEnabled ? 1 : 0.36))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct HistoryRow: View {
    @Bindable var item: CaptureItem
    @Bindable var appModel: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Button {
                appModel.reopenPinnedPanel(for: item)
            } label: {
                HStack(spacing: 10) {
                    Image(nsImage: item.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(CaptureHistoryFormatter.title(for: item.recognizedText, createdAt: item.createdAt))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(item.createdAt.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(CaptureHistoryFormatter.detail(for: item))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                if item.hasRecognizedText {
                    Button {
                        appModel.copyRecognizedText(for: item)
                    } label: {
                        Image(systemName: "text.badge.plus")
                    }
                    .help("Copy OCR text")
                    .buttonStyle(ToolIconButtonStyle())
                }

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
                }
                .help("Export this capture")
                .buttonStyle(ToolIconButtonStyle())

                Button {
                    appModel.removeCapture(item)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Remove from history")
                .buttonStyle(ToolIconButtonStyle())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

private struct EmptyHistoryState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SetupStepCard<Accessory: View>: View {
    let index: Int
    let title: String
    let detail: String
    let accessory: Accessory

    init(
        index: Int,
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.index = index
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(PinShotPalette.selectionBlue))

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

private struct StatChip: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.14))
        )
    }
}

private struct TipRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PinShotPalette.selectionBlue)
                .frame(width: 14)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FilterChipButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.78))
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isSelected
                            ? PinShotPalette.selectionBlue.opacity(configuration.isPressed ? 0.82 : 0.94)
                            : Color.white.opacity(configuration.isPressed ? 0.22 : 0.12)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ToolIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .frame(width: 28, height: 28)
            .foregroundStyle(.primary.opacity(0.82))
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.24 : 0.14))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
