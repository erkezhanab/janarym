import SwiftUI
import AVFoundation
import UIKit

// MARK: - Camera Preview (layerClass тәсілі — ең сенімді)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let isActive: Bool

    func makeUIView(context: Context) -> CameraLayerView {
        let view = CameraLayerView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraLayerView, context: Context) {
        // Session байланысын жаңарт
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }

        // Connection-ды қос/өшір
        uiView.videoPreviewLayer.connection?.isEnabled = isActive
    }
}

// MARK: - Preview UIView (layer = AVCaptureVideoPreviewLayer)

final class CameraLayerView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // bounds пайдалан — landscape/portrait кезінде автоматты жаңарады
        videoPreviewLayer.frame = bounds
        updateVideoOrientation()
    }

    private func updateVideoOrientation() {
        guard let connection = videoPreviewLayer.connection,
              connection.isVideoOrientationSupported else { return }
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            switch scene.interfaceOrientation {
            case .landscapeLeft:      connection.videoOrientation = .landscapeLeft
            case .landscapeRight:     connection.videoOrientation = .landscapeRight
            case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
            default:                  connection.videoOrientation = .portrait
            }
        } else {
            connection.videoOrientation = .portrait
        }
    }
}

// MARK: - ESP32 Snapshot Preview

struct SnapshotPreviewView: View {
    let imageData: Data?
    let isConnected: Bool
    let title: String
    let subtitle: String
    var statusText: String? = nil
    var showStaleOverlay: Bool = false

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            if let imageData,
               let image = UIImage(data: imageData) {
                GeometryReader { geo in
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .blur(radius: 26)
                            .overlay(Color.black.opacity(0.24))
                            .clipped()

                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.05, blue: 0.08),
                        Color(red: 0.01, green: 0.01, blue: 0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 20) {
                    // Pulsing wifi icon
                    ZStack {
                        Circle()
                            .fill((isConnected ? Color.cyan : Color.white).opacity(0.08))
                            .frame(width: 80, height: 80)
                            .scaleEffect(pulseScale)
                            .animation(
                                .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                                value: pulseScale
                            )
                        Image(systemName: isConnected ? "wifi" : "wifi.slash")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(isConnected ? .cyan : .white.opacity(0.72))
                    }
                    .onAppear { pulseScale = 1.25 }

                    VStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                }
            }

            if let statusText {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(showStaleOverlay ? Color.orange : (isConnected ? Color.cyan : Color.white.opacity(0.75)))
                                .frame(width: 8, height: 8)
                            Text(statusText)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.56))
                        .clipShape(Capsule())
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 18)

                    Spacer()
                }
                .allowsHitTesting(false)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.08), Color.black.opacity(0.30)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            if showStaleOverlay, imageData != nil {
                VStack(spacing: 10) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.orange)
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background(Color.black.opacity(0.66))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 28)
                .allowsHitTesting(false)
            }
        }
        .background(Color.black)
    }
}
