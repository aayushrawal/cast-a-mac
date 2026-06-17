import CoreVideo
import CastCore
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
    let sendKey: (UInt16, Bool, KeyModifiers) -> Void
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
            .background {
                SystemGestureDeferringView()
                    .allowsHitTesting(false)
            }
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
    let sendKey: (UInt16, Bool, KeyModifiers) -> Void
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
        view.onSpecialKey = { [weak coordinator = context.coordinator] keyCode, isPressed, modifiers in
            coordinator?.parent.sendKey(keyCode, isPressed, modifiers)
        }

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.tap(_:))
        )
        tap.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        let drag = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.drag(_:))
        )
        drag.minimumNumberOfTouches = 1
        drag.maximumNumberOfTouches = 1
        drag.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        let scrollGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.scroll(_:))
        )
        scrollGesture.minimumNumberOfTouches = 2
        scrollGesture.maximumNumberOfTouches = 2
        scrollGesture.requiresExclusiveTouchType = true
        scrollGesture.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        let threeFingerSwipe = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.threeFingerSwipe(_:))
        )
        threeFingerSwipe.minimumNumberOfTouches = 3
        threeFingerSwipe.maximumNumberOfTouches = 3
        threeFingerSwipe.requiresExclusiveTouchType = true
        threeFingerSwipe.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        let rightClick = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.rightClick(_:))
        )
        rightClick.minimumPressDuration = 0.45
        rightClick.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        let pointerClick = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.tap(_:))
        )
        pointerClick.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        ]
        pointerClick.buttonMaskRequired = .primary
        let pointerRightClick = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.pointerRightClick(_:))
        )
        pointerRightClick.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        ]
        pointerRightClick.buttonMaskRequired = .secondary
        let pointerDrag = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.drag(_:))
        )
        pointerDrag.minimumNumberOfTouches = 1
        pointerDrag.maximumNumberOfTouches = 1
        pointerDrag.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        ]
        let trackpadScroll = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.trackpadScroll(_:))
        )
        trackpadScroll.allowedScrollTypesMask = [.continuous, .discrete]
        let hover = UIHoverGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.hover(_:))
        )

        tap.require(toFail: drag)
        pointerClick.require(toFail: pointerDrag)
        tap.delegate = context.coordinator
        drag.delegate = context.coordinator
        scrollGesture.delegate = context.coordinator
        threeFingerSwipe.delegate = context.coordinator
        rightClick.delegate = context.coordinator
        pointerClick.delegate = context.coordinator
        pointerRightClick.delegate = context.coordinator
        pointerDrag.delegate = context.coordinator
        trackpadScroll.delegate = context.coordinator
        context.coordinator.setGestureView(view)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(drag)
        view.addGestureRecognizer(scrollGesture)
        view.addGestureRecognizer(threeFingerSwipe)
        view.addGestureRecognizer(rightClick)
        view.addGestureRecognizer(pointerClick)
        view.addGestureRecognizer(pointerRightClick)
        view.addGestureRecognizer(pointerDrag)
        view.addGestureRecognizer(trackpadScroll)
        view.addGestureRecognizer(hover)
        return view
    }

    func updateUIView(_ view: RemoteInputView, context: Context) {
        context.coordinator.parent = self
        view.showsSoftwareKeyboard = keyboardIsActive
        if !view.isFirstResponder {
            DispatchQueue.main.async {
                view.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: RemoteInputOverlay
        private var threeFingerSwipeTriggered = false

        init(parent: RemoteInputOverlay) {
            self.parent = parent
        }

        func sendKeyPress(keyCode: UInt16) {
            parent.sendKey(keyCode, true, [])
            parent.sendKey(keyCode, false, [])
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

        @objc func trackpadScroll(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .changed else {
                return
            }
            let delta = recognizer.translation(in: recognizer.view)
            recognizer.setTranslation(.zero, in: recognizer.view)
            parent.scroll(delta.x, delta.y)
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

        @objc func pointerRightClick(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let point = normalizedPoint(
                      recognizer.location(in: recognizer.view)
                  ) else {
                return
            }
            parent.rightClick(point.x, point.y)
        }

        @objc func hover(_ recognizer: UIHoverGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed else {
                return
            }
            let location = recognizer.location(in: recognizer.view)
            if reportCornerActivity(at: location) {
                return
            }
            guard let point = normalizedPoint(location) else {
                return
            }
            parent.movePointer(point.x, point.y)
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
            false
        }

        fileprivate func setGestureView(_ view: UIView) {
            gestureView = view
        }
    }
}

private struct SystemGestureDeferringView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SystemGestureDeferringController {
        SystemGestureDeferringController()
    }

    func updateUIViewController(
        _ uiViewController: SystemGestureDeferringController,
        context: Context
    ) {}
}

private final class SystemGestureDeferringController: UIViewController {
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        .all
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        self.view = view
    }
}

private final class RemoteInputView: UIView, UIKeyInput {
    var onInsertText: ((String) -> Void)?
    var onDeleteBackward: (() -> Void)?
    var onSpecialKey: ((UInt16, Bool, KeyModifiers) -> Void)?
    var showsSoftwareKeyboard = false {
        didSet {
            guard oldValue != showsSoftwareKeyboard else { return }
            reloadInputViews()
        }
    }
    private let hiddenInputView = UIView(frame: .zero)

    override var canBecomeFirstResponder: Bool {
        true
    }

    var hasText: Bool {
        true
    }

    override var inputView: UIView? {
        showsSoftwareKeyboard ? nil : hiddenInputView
    }

    func insertText(_ text: String) {
        if text == "\n" || text == "\r" {
            sendKeyPress(keyCode: 36)
        } else if text == "\t" {
            sendKeyPress(keyCode: 48)
        } else {
            onInsertText?(text)
        }
    }

    func deleteBackward() {
        onDeleteBackward?()
    }

    override func pressesBegan(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?
    ) {
        var handled = false
        for press in presses {
            guard let key = press.key,
                  let keyCode = key.macVirtualKeyCode else {
                continue
            }
            handled = true
            onSpecialKey?(keyCode, true, key.modifierFlags.castModifiers)
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?
    ) {
        var handled = false
        for press in presses {
            guard let key = press.key,
                  let keyCode = key.macVirtualKeyCode else {
                continue
            }
            handled = true
            onSpecialKey?(keyCode, false, key.modifierFlags.castModifiers)
        }
        if !handled {
            super.pressesEnded(presses, with: event)
        }
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

    private func sendKeyPress(keyCode: UInt16) {
        onSpecialKey?(keyCode, true, [])
        onSpecialKey?(keyCode, false, [])
    }
}

private extension UIKey {
    var macVirtualKeyCode: UInt16? {
        if let specialKeyCode = keyCode.macVirtualKeyCode {
            return specialKeyCode
        }
        let shortcutModifiers: UIKeyModifierFlags = [
            .command,
            .control,
            .alternate
        ]
        guard !modifierFlags.intersection(shortcutModifiers).isEmpty else {
            return nil
        }
        return charactersIgnoringModifiers.lowercased().first?.macVirtualKeyCode
    }
}

private extension Character {
    var macVirtualKeyCode: UInt16? {
        switch self {
        case "a": 0
        case "s": 1
        case "d": 2
        case "f": 3
        case "h": 4
        case "g": 5
        case "z": 6
        case "x": 7
        case "c": 8
        case "v": 9
        case "b": 11
        case "q": 12
        case "w": 13
        case "e": 14
        case "r": 15
        case "y": 16
        case "t": 17
        case "1": 18
        case "2": 19
        case "3": 20
        case "4": 21
        case "6": 22
        case "5": 23
        case "=": 24
        case "9": 25
        case "7": 26
        case "-": 27
        case "8": 28
        case "0": 29
        case "]": 30
        case "o": 31
        case "u": 32
        case "[": 33
        case "i": 34
        case "p": 35
        case "l": 37
        case "j": 38
        case "'": 39
        case "k": 40
        case ";": 41
        case "\\": 42
        case ",": 43
        case "/": 44
        case "n": 45
        case "m": 46
        case ".": 47
        case "`": 50
        default: nil
        }
    }
}

private extension UIKeyboardHIDUsage {
    var macVirtualKeyCode: UInt16? {
        switch self {
        case .keyboardReturnOrEnter: 36
        case .keyboardEscape: 53
        case .keyboardDeleteOrBackspace: 51
        case .keyboardDeleteForward: 117
        case .keyboardTab: 48
        case .keyboardSpacebar: 49
        case .keyboardLeftArrow: 123
        case .keyboardRightArrow: 124
        case .keyboardDownArrow: 125
        case .keyboardUpArrow: 126
        case .keyboardHome: 115
        case .keyboardEnd: 119
        case .keyboardPageUp: 116
        case .keyboardPageDown: 121
        default: nil
        }
    }
}

private extension UIKeyModifierFlags {
    var castModifiers: KeyModifiers {
        var modifiers: KeyModifiers = []
        if contains(.shift) { modifiers.insert(.shift) }
        if contains(.control) { modifiers.insert(.control) }
        if contains(.alternate) { modifiers.insert(.option) }
        if contains(.command) { modifiers.insert(.command) }
        if contains(.alphaShift) { modifiers.insert(.capsLock) }
        return modifiers
    }
}
