import SwiftUI

/// 宝丽来样式：白色厚边框 + 底部留白
struct PolaroidPaper: View {
    let uiImage: UIImage?
    var livePhotoContent: AnyView? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 照片本体（宝丽来传统：正方形区域；用 scaledToFill + clipped 裁剪而非变形）
            // 格子尺寸只认「宽 × 比例」，里面再怎么撑也撑不大（见 `PhotoPaperImageArea`）
            PhotoPaperImageArea(uiImage: uiImage, livePhotoContent: livePhotoContent, aspect: 1.0)

            // 底部留白（宝丽来标志性厚边）
            Color.white
                .frame(height: 28)
        }
        .padding(8) // 四周白边
        .background(Color.white)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    }
}
