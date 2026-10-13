import SwiftUI

/// 和风贴纸：米白底 + 棕色细边 + 四角老相册相角装饰
struct WashiStickerPaper: View {
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
        ZStack {
            // 照片 + 米白底 + 棕边（按照片原始比例）
            // 格子尺寸只认「宽 × 比例」，里面再怎么撑也撑不大（见 `PhotoPaperImageArea`）
            PhotoPaperImageArea(uiImage: uiImage, livePhotoContent: livePhotoContent, aspect: photoAspect)
            .padding(6)
            .background(Color(hex: "#FAF7F2"))
            .overlay(
                Rectangle().stroke(Color(hex: "#B8AD9C"), lineWidth: 0.8)
            )

            // 四角相角装饰
            let cornerColor = Color(hex: "#C8A87C").opacity(0.7)
            let cornerSize: CGFloat = 14
            VStack {
                HStack {
                    CornerTriangle(corner: .topLeft).fill(cornerColor).frame(width: cornerSize, height: cornerSize)
                    Spacer()
                    CornerTriangle(corner: .topRight).fill(cornerColor).frame(width: cornerSize, height: cornerSize)
                }
                Spacer()
                HStack {
                    CornerTriangle(corner: .bottomLeft).fill(cornerColor).frame(width: cornerSize, height: cornerSize)
                    Spacer()
                    CornerTriangle(corner: .bottomRight).fill(cornerColor).frame(width: cornerSize, height: cornerSize)
                }
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
    }
}
