import SwiftUI

/// 极简卡片：圆角 + 细边 0.5px，无额外修饰
struct MinimalCardPaper: View {
    let uiImage: UIImage?
    var livePhotoContent: AnyView? = nil

    /// 照片原始宽高比（无图时退化为 4:3）
    private var photoAspect: CGFloat {
        guard let img = uiImage, img.size.width > 0, img.size.height > 0 else {
            return 4.0 / 3.0
        }
        return img.size.width / img.size.height
    }

    var body: some View {
        // 格子尺寸只认「宽 × 比例」，里面再怎么撑也撑不大（见 `PhotoPaperImageArea`）
        PhotoPaperImageArea(uiImage: uiImage, livePhotoContent: livePhotoContent, aspect: photoAspect)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: "#D4C9B8"), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}
