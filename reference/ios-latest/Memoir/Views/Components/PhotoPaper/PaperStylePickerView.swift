import SwiftUI
import UIKit

/// 相纸样式选择器：横向滚动展示 5 种相纸的实际预览。
/// 以 sheet 的形式弹出，点击任意一张即选定并回调。
struct PaperStylePickerView: View {
    let image: UIImage
    let theme: any AppTheme
    let onSelect: (PaperStyle) -> Void
    let onCancel: () -> Void

    @Environment(StoreKitManager.self) private var store
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 24) {
            // 顶部标题
            VStack(spacing: 4) {
                Text("选择相纸样式")
                    .font(.custom("Georgia", size: 18))
                    .foregroundStyle(theme.textPrimary)
                Text("点击任意一张插入日记")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.top, 28)

            // 横向滑动的样式预览（所有卡片统一 120×160 外框）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(PaperStyle.allCases, id: \.self) { style in
                        let locked = style.isMemberOnly && !store.isMember
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            // 会员款：预览已经是用户自己的照片了，点了就问要不要开通（尺素会员）
                            if locked { showPaywall = true } else { onSelect(style) }
                        } label: {
                            VStack(spacing: 10) {
                                PaperPreviewCard(uiImage: image, style: style)
                                    .overlay(alignment: .topTrailing) {
                                        if locked { MemberBadge().offset(x: 6, y: -6) }
                                    }

                                Text(style.displayName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            Spacer(minLength: 0)

            // 取消按钮
            Button {
                onCancel()
            } label: {
                Text("取消")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
        .paywallCover(isPresented: $showPaywall)
    }
}

// MARK: - 预览卡片

/// 固定尺寸（120×160）的相纸预览卡。
///
/// 与真实渲染的 `*Paper` 组件区别：
/// - 预览要求横排时视觉一致 → 所有卡片外框固定 120×160；
/// - 照片用 `.scaledToFill()` + 固定 frame + `.clipped()`，保持原始比例、裁剪溢出，不变形；
/// - 每种样式按自身审美设置照片内嵌尺寸（宝丽来正方形 / 胶片竖构图 / 其他略带竖长）。
struct PaperPreviewCard: View {
    let uiImage: UIImage
    let style: PaperStyle

    private let cardWidth: CGFloat = 120
    private let cardHeight: CGFloat = 160

    var body: some View {
        content
            .frame(width: cardWidth, height: cardHeight)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .original:       originalPreview
        case .polaroid:       polaroidPreview
        case .washiSticker:   washiPreview
        case .minimalCard:    minimalPreview
        case .filmFrame:      filmPreview
        case .letterAttached: letterPreview
        }
    }

    /// 原图：仅微圆角，无相框/无阴影/无装饰
    private var originalPreview: some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFill()
            .frame(width: 108, height: 130)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: 各样式预览

    /// 宝丽来：正方形照片 104×104 + 底部 32pt 白边
    private var polaroidPreview: some View {
        VStack(spacing: 0) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 104, height: 104)
                .clipped()
            Color.white.frame(height: 32)
        }
        .padding(8)
        .background(Color.white)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    }

    /// 和风贴纸：米白底 + 棕边 + 四角相角（照片 108×120）
    private var washiPreview: some View {
        let photoW: CGFloat = 108
        let photoH: CGFloat = 120
        return ZStack {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: photoW, height: photoH)
                .clipped()
                .padding(6)
                .background(Color(hex: "#FAF7F2"))
                .overlay(
                    Rectangle().stroke(Color(hex: "#B8AD9C"), lineWidth: 0.8)
                )

            let cornerColor = Color(hex: "#C8A87C").opacity(0.7)
            let cornerSize: CGFloat = 12
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
            .frame(width: photoW + 12, height: photoH + 12)
        }
        .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
    }

    /// 极简卡片：圆角 + 细边，照片 108×130
    private var minimalPreview: some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFill()
            .frame(width: 108, height: 130)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "#D4C9B8"), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }

    /// 胶片帧：两侧齿孔 + 深棕底，照片 76×110
    private var filmPreview: some View {
        HStack(spacing: 4) {
            perforationStrip(height: 110)
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 76, height: 110)
                .clipped()
            perforationStrip(height: 110)
        }
        .padding(6)
        .background(Color(hex: "#2C1F15"))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }

    /// 信纸附照：薄白边 + 左上角胶带，照片 104×128
    private var letterPreview: some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFill()
            .frame(width: 104, height: 128)
            .clipped()
            .padding(4)
            .background(Color.white)
            .shadow(color: .black.opacity(0.20), radius: 6, x: 1, y: 3)
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(hex: "#E8DDC9").opacity(0.55))
                    .frame(width: 42, height: 14)
                    .rotationEffect(.degrees(-20))
                    .offset(x: -6, y: -3)
                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
            }
    }

    // MARK: 辅助

    private func perforationStrip(height: CGFloat) -> some View {
        VStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: "#FAF7F2"))
                    .frame(width: 5, height: 3)
            }
        }
        .frame(width: 12, height: height)
        .background(Color(hex: "#3D3428"))
    }
}
