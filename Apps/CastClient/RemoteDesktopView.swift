import CoreVideo
import SwiftUI
import UIKit

enum ThreeFingerSwipeDirection {
    case up
    case down
    case left
    case right
}

struct RemoteDesktopView: View {
    let macName: String
    let frame: CVPixelBuffer?
    let disconnect: () -> Void
    let movePointer: (Double, Double) -> Void
    let setPrimaryButton: (Bool, Double, Double) -> Void
    let click: (Double, Double) -> Void
    let rightClick: (Double, Double) -> Void
    let scroll: (Double, Double) -> Void
    let sendText: (String) -> Void
    let sendKey: (UInt16, Bool) -> Void
    let performThreeFingerSwipe: (ThreeFingerSwipeDirection) -> Void

    @State private var keyboardIsActive = false
    @State private var controlsVisible = true
    @State private var controlsHideGeneration = UUID()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let frame {
                    MetalVideoView(pixelBuffer: frame)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .overlay {
                        RemoteInputOverlay(
                            videoSize: CGSize(
                                width: CVPixelBufferGetWidth(frame),
                                height: CVPixelBufferGetHeight(frame)
                            ),
                            movePointer: movePointer,
                            setPrimaryButton: setPrimaryButton,
                            click: click,
                            rightClick: rightClick,
                            scroll: scroll,
                            sendText: sendText,
                            sendKey: sendKey,
                            performThreeFingerSwipe: performThreeFingerSwipe,
                            keyboardIsActive: keyboardIsActive,
                            controlsVisible: controlsVisible,
                            cornerActivity: revealControls
                        )
                    }
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(.white)
                        Text("Waiting for video from \(macName)")
                            .foregroundStyle(.white)
                    }
                }

                if controlsVisible {
                    VStack {
                        HStack {
                            Label(macName, systemImage: "lock.fill")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                keyboardIsActive.toggle()
                                revealControls()
                            } label: {
                                Label(
                                    keyboardIsActive ? "Hide Keyboard" : "Keyboard",
                                    systemImage: "keyboard"
                                )
                            }
                            .buttonStyle(.bordered)
                            Button("Disconnect", role: .destructive, action: disconnect)
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .onHover { hovering in
                            if hovering {
                                revealControls()
                            }
                        }

                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: revealControls) {
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.bold))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .background(.ultraThinMaterial, in: Circle())
                            .accessibilityLabel("Show remote controls")
                        }
                        Spacer()
                    }
                    .padding(6)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        .onAppear(perform: revealControls)
        .accessibilityAction(named: Text("Show remote controls")) {
            revealControls()
        }
        .persistentSystemOverlays(.hidden)
    }

    private func revealControls() {
        controlsVisible = true
        let generation = UUID()
        controlsHideGeneration = generation
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard controlsHideGeneration == generation,
                  !keyboardIsActive else {
                return
            }
            controlsVisible = false
        }
    }
}

private struct RemoteInputOverlay: UIViewRepresentable {
    let videoSize: CGSize
    let movePointer: (Double, Double) -> Void
    let setPrimaryButton: (Bool, Double, Double) -> Void
    let click: (Double, Double) -> Void
    let rightClick: (Double, Double) -> Void
    let scroll: (Double, Double) -> Void
    let sendText: (String) -> Void
    let sendKey: (UInt16, Bool) -> Void
    let performThreeFingerSwipe: (ThreeFingerSwipeDirection) -> Void
    let keyboardIsActive: Bool
    let controlsVisible: Bool
    let cornerActivity: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> RemoteInputView {
        let view = RemoteInputView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.onInsertText = { [weak coordinator = context.coordinator] text in
            coordinator?.parent.sendText(text)
        }
        view.onDeleteBackward = { [weak coordinator = context.coordinator] in
            coordinator?.sendKeyPress(keyCode: 51)
        }

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.tap(_:))
        )
        let drag = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.drag(_:))
        )
        drag.minimumNumberOfTouches = 1
        drag.maximumNumberOfTouches = 1
        let scrollGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.scroll(_:))
        )
        scrollGesture.minimumNumberOfTouches = 2
        scrollGesture.maximumNumberOfTouches = 2
        let threeFingerSwipe = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.threeFingerSwipe(_:))
        )
        threeFingerSwipe.minimumNumberOfTouches = 3
        threeFingerSwipe.maximumNumberOfTouches = 3
        let rightClick = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.rightClick(_:))
        )
        rightClick.minimumPressDuration = 0.45
        let hover = UIHoverGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.hover(_:))
        )

        tap.require(toFail: drag)
        tap.delegate = context.coordinator
        drag.delegate = context.coordinator
        scrollGesture.delegate = context.coordinator
        threeFingerSwipe.delegate = context.coordinator
        rightClick.delegate = context.coordinator
        context.coordinator.setGestureView(view)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(drag)
        view.addGestureRecognizer(scrollGesture)
        view.addGestureRecognizer(threeFingerSwipe)
        view.addGestureRecognizer(rightClick)
        view.addGestureRecognizer(hover)
        return view
    }

    func updateUIView(_ view: RemoteInputView, context: Context) {
        context.coordinator.parent = self
        if keyboardIsActive, !view.isFirstResponder {
            DispatchQueue.main.async {
                view.becomeFirstResponder()
            }
        } else if !keyboardIsActive, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: RemoteInputOverlay
        private var threeFingerSwipeTriggered = false

        init(parent: RemoteInputOverlay) {
            self.parent = parent
        }

        func sendKeyPress(keyCode: UInt16) {
            parent.sendKey(keyCode, true)
            parent.sendKey(keyCode, false)
        }

        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            let location = recognizer.location(in: recognizer.view)
            if reportCornerActivity(at: location) {
                return
            }
            guard let point = normalizedPoint(location) else {
                return
            }
            parent.click(point.x, point.y)
        }

        @objc func drag(_ recognizer: UIPanGestureRecognizer) {
            guard let point = normalizedPoint(recognizer.location(in: recognizer.view)) else {
                return
            }
            switch recognizer.state {
            case .began:
                parent.movePointer(point.x, point.y)
                parent.setPrimaryButton(true, point.x, point.y)
            case .changed:
                parent.movePointer(point.x, point.y)
            case .ended, .cancelled, .failed:
                parent.setPrimaryButton(false, point.x, point.y)
            default:
                break
            }
        }

        @objc func scroll(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .changed else {
                return
            }
            let delta = recognizer.translation(in: recognizer.view)
            recognizer.setTranslation(.zero, in: recognizer.view)
            parent.scroll(delta.x * 3, delta.y * 3)
        }

        @objc func threeFingerSwipe(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                threeFingerSwipeTriggered = false
            case .changed:
                guard !threeFingerSwipeTriggered else { return }
                let translation = recognizer.translation(in: recognizer.view)
                let velocity = recognizer.velocity(in: recognizer.view)
                let horizontal = abs(translation.x) > abs(translation.y)
                let distance = horizontal ? abs(translation.x) : abs(translation.y)
                let speed = horizontal ? abs(velocity.x) : abs(velocity.y)
                guard distance >= 44 || speed >= 500 else { return }

                threeFingerSwipeTriggered = true
                if horizontal {
                    parent.performThreeFingerSwipe(
                        translation.x < 0 ? .left : .right
                    )
                } else {
                    parent.performThreeFingerSwipe(
                        translation.y < 0 ? .up : .down
                    )
                }
            case .ended, .cancelled, .failed:
                threeFingerSwipeTriggered = false
            default:
                break
            }
        }

        @objc func rightClick(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began,
                  let point = normalizedPoint(recognizer.location(in: recognizer.view)) else {
                return
            }
            parent.rightClick(point.x, point.y)
        }

        @objc func hover(_ recognizer: UIHoverGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed else {
                return
            }
            _ = reportCornerActivity(at: recognizer.location(in: recognizer.view))
        }

        @discardableResult
        private func reportCornerActivity(at point: CGPoint) -> Bool {
            guard let view = gestureView,
                  !parent.controlsVisible,
                  point.x >= view.bounds.maxX - 64,
                  point.y <= view.bounds.minY + 64 else {
                return false
            }
            parent.cornerActivity()
            return true
        }

        private func normalizedPoint(_ point: CGPoint) -> (x: Double, y: Double)? {
            guard let view = gestureView, parent.videoSize.width > 0,
                  parent.videoSize.height > 0 else {
                return nil
            }
            let scale = min(
                view.bounds.width / parent.videoSize.width,
                view.bounds.height / parent.videoSize.height
            )
            let size = CGSize(
                width: parent.videoSize.width * scale,
                height: parent.videoSize.height * scale
            )
            let rect = CGRect(
                x: (view.bounds.width - size.width) / 2,
                y: (view.bounds.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            guard rect.contains(point) else {
                return nil
            }
            return (
                Double((point.x - rect.minX) / rect.width),
                Double((point.y - rect.minY) / rect.height)
            )
        }

        private weak var gestureView: UIView?

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        fileprivate func setGestureView(_ view: UIView) {
            gestureView = view
        }
    }
}

private final class RemoteInputView: UIView, UIKeyInput {
    var onInsertText: ((String) -> Void)?
    var onDeleteBackward: (() -> Void)?

    override var canBecomeFirstResponder: Bool {
        true
    }

    var hasText: Bool {
        true
    }

    func insertText(_ text: String) {
        onInsertText?(text)
    }

    func deleteBackward() {
        onDeleteBackward?()
    }

    var autocorrectionType: UITextAutocorrectionType {
        get { .no }
        set {}
    }

    var autocapitalizationType: UITextAutocapitalizationType {
        get { .none }
        set {}
    }

    var smartDashesType: UITextSmartDashesType {
        get { .no }
        set {}
    }

    var smartQuotesType: UITextSmartQuotesType {
        get { .no }
        set {}
    }

    var smartInsertDeleteType: UITextSmartInsertDeleteType {
        get { .no }
        set {}
    }
}
