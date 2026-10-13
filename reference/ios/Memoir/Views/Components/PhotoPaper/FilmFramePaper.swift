import SwiftUI

/// 胶片帧：两侧胶卷齿孔 + 深棕底色
struct FilmFramePaper: View {
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
        HStack(spacing: 4) {
            perforationStrip
            // 照片本体（按原始比例）
            // 格子尺寸只认「宽 × 比例」，里面再怎么撑也撑不大（见 `PhotoPaperImageArea`）
            PhotoPaperImageArea(uiImage: uiImage, livePhotoContent: livePhotoContent, aspect: photoAspect)
            perforationStrip
        }
        .padding(6)
        .background(Color(hex: "#2C1F15"))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }

    private var perforationStrip: some View {
        VStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: "#FAF7F2"))
                    .frame(width: 6, height: 4)
            }
        }
        .frame(width: 14)
        .frame(maxHeight: .infinity)
        .background(Color(hex: "#3D3428"))
    }
}
