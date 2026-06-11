import CoreVideo
import SwiftUI

struct RemoteDesktopView: View {
    let macName: String
    let frame: CVPixelBuffer?
    let disconnect: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let frame {
                MetalVideoView(pixelBuffer: frame)
                    .ignoresSafeArea()
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
                Button("Disconnect", role: .destructive, action: disconnect)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .persistentSystemOverlays(.hidden)
    }
}
