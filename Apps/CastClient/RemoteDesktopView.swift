import CoreVideo
import SwiftUI
import UIKit

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

    @State private var showsKeyboard = false
    @State private var text = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let frame {
                MetalVideoView(pixelBuffer: frame)
                    .ignoresSafeArea()
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
                            scroll: scroll
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
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Label(macName, systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    showsKeyboard = true
                } label: {
                    Label("Keyboard", systemImage: "keyboard")
                }
                .buttonStyle(.bordered)
                Button("Disconnect", role: .destructive, action: disconnect)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showsKeyboard) {
            NavigationStack {
                Form {
                    TextField("Text to type on the Mac", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .navigationTitle("Remote Keyboard")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            showsKeyboard = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            sendText(text)
                            text = ""
                        }
                        .disabled(text.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
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

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

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
        let rightClick = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.rightClick(_:))
        )
        rightClick.minimumPressDuration = 0.45

        tap.require(toFail: drag)
        context.coordinator.setGestureView(view)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(drag)
        view.addGestureRecognizer(scrollGesture)
        view.addGestureRecognizer(rightClick)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject {
        var parent: RemoteInputOverlay

        init(parent: RemoteInputOverlay) {
            self.parent = parent
        }

        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            guard let point = normalizedPoint(recognizer.location(in: recognizer.view)) else {
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
            guard recognizer.state == .changed else { return }
            let delta = recognizer.translation(in: recognizer.view)
            recognizer.setTranslation(.zero, in: recognizer.view)
            parent.scroll(delta.x * 2, delta.y * 2)
        }

        @objc func rightClick(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began,
                  let point = normalizedPoint(recognizer.location(in: recognizer.view)) else {
                return
            }
            parent.rightClick(point.x, point.y)
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
            guard rect.contains(point) else { return nil }
            return (
                Double((point.x - rect.minX) / rect.width),
                Double((point.y - rect.minY) / rect.height)
            )
        }

        private weak var gestureView: UIView?

        fileprivate func setGestureView(_ view: UIView) {
            gestureView = view
        }
    }
}
