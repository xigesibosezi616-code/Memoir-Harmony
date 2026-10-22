import SwiftUI

/// 原图：无相框、无装饰，仅极小圆角避免硬边。
/// 与其他相纸样式相同的尺寸/比例约束，只是去掉所有相纸装饰元素。
struct OriginalPhotoPaper: View {
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
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
