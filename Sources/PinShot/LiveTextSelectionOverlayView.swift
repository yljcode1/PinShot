import AppKit
import ImageIO
import SwiftUI
@preconcurrency import VisionKit

struct LiveTextSelectionOverlayView: NSViewRepresentable {
    let image: NSImage
    let isActive: Bool
    let onActivate: () -> Void
    let onMagnify: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LiveTextSelectableView {
        let view = LiveTextSelectableView()
        view.onActivate = onActivate
        view.onMagnify = onMagnify
        view.update(image: image, isActive: isActive, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: LiveTextSelectableView, context: Context) {
        nsView.onActivate = onActivate
        nsView.onMagnify = onMagnify
        nsView.update(image: image, isActive: isActive, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: LiveTextSelectableView, coordinator: Coordinator) {
        coordinator.analysisTask?.cancel()
    }

    final class Coordinator {
        var analysisTask: Task<Void, Never>?
        weak var analyzedImage: NSImage?
    }
}

final class LiveTextSelectableView: NSView {
    private let imageView = NSImageView()
    private let overlayView = ImageAnalysisOverlayView()
    private var localEventMonitor: Any?
    var onActivate: (() -> Void)?
    var onMagnify: ((CGFloat) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.trackingImageView = imageView
        overlayView.preferredInteractionTypes = []
        overlayView.selectableItemsHighlighted = true
        addSubview(overlayView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeEventMonitor()
        } else {
            installEventMonitorIfNeeded()
        }
        window?.makeFirstResponder(overlayView)
    }

    override func magnify(with event: NSEvent) {
        onMagnify?(event.magnification)
    }

    func update(
        image: NSImage,
        isActive: Bool,
        coordinator: LiveTextSelectionOverlayView.Coordinator
    ) {
        imageView.image = image
        isHidden = !isActive
        overlayView.preferredInteractionTypes = isActive ? .textSelection : []
        overlayView.trackingImageView = imageView
        if isActive {
            window?.makeFirstResponder(overlayView)
        }

        guard coordinator.analyzedImage !== image else { return }

        coordinator.analysisTask?.cancel()
        coordinator.analyzedImage = image
        overlayView.analysis = nil

        coordinator.analysisTask = Task { [weak self] in
            let analyzer = ImageAnalyzer()
            let configuration = ImageAnalyzer.Configuration([.text])

            do {
                let analysis = try await analyzer.analyze(
                    image,
                    orientation: .up,
                    configuration: configuration
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.overlayView.analysis = analysis
                    self?.overlayView.preferredInteractionTypes = isActive ? .textSelection : []
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.overlayView.analysis = nil
                }
            }
        }
    }

    private func installEventMonitorIfNeeded() {
        guard localEventMonitor == nil else { return }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self,
                  let window,
                  event.window === window else {
                return event
            }

            let point = convert(event.locationInWindow, from: nil)
            if bounds.contains(point) {
                onActivate?()
            }

            return event
        }
    }

    private func removeEventMonitor() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }
}
