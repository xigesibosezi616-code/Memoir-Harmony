import SwiftUI

/// 信纸附照：薄白边 + 较深阴影 + 左上角"胶带"效果
struct LetterAttachedPaper: View {
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
        .padding(4)
        .background(Color.white)
        .shadow(color: .black.opacity(0.20), radius: 6, x: 1, y: 3)
        // 左上角模拟胶带
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(Color(hex: "#E8DDC9").opacity(0.55))
                .frame(width: 50, height: 16)
                .rotationEffect(.degrees(-20))
                .offset(x: -8, y: -4)
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
    }
}
