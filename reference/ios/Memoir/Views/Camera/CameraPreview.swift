import SwiftUI
import AVFoundation

/// `AVCaptureVideoPreviewLayer` 的 SwiftUI 包装。
///
/// 用 `layerClass` 直接把 view 的 backing layer 指定为预览层，省去手动同步 frame。
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // layerClass 已指定，强转安全
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
