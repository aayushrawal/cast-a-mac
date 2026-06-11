import CoreImage
import CoreVideo
import MetalKit
import SwiftUI

struct MetalVideoView: UIViewRepresentable {
    let pixelBuffer: CVPixelBuffer

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.framebufferOnly = false
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.autoResizeDrawable = true
        view.contentMode = .scaleAspectFit
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.pixelBuffer = pixelBuffer
        view.setNeedsDisplay()
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        var pixelBuffer: CVPixelBuffer?
        private var commandQueue: MTLCommandQueue?
        private var context: CIContext?

        func attach(to view: MTKView) {
            guard let device = view.device else { return }
            commandQueue = device.makeCommandQueue()
            context = CIContext(mtlDevice: device)
            view.delegate = self
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let pixelBuffer,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue?.makeCommandBuffer(),
                  let context else {
                return
            }

            let image = CIImage(cvPixelBuffer: pixelBuffer)
            let source = image.extent
            let destination = CGRect(origin: .zero, size: view.drawableSize)
            let scale = min(
                destination.width / source.width,
                destination.height / source.height
            )
            let scaledSize = CGSize(
                width: source.width * scale,
                height: source.height * scale
            )
            let offset = CGPoint(
                x: (destination.width - scaledSize.width) / 2,
                y: (destination.height - scaledSize.height) / 2
            )
            let transform = CGAffineTransform(
                translationX: offset.x,
                y: offset.y
            ).scaledBy(x: scale, y: scale)

            context.render(
                image.transformed(by: transform),
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: destination,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
