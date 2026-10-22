import SwiftUI
import AVFoundation

/// 尺素相机 —— 取景框从灵动岛「长」出来，快门即出相纸。
///
/// **设计意图**：不是做一台拍立得（没人愿意等虚拟显影），而是借拍立得的「手感」——
/// 按下快门、一张相纸落到手里、顺手想写点什么。成像原图直出，零等待。
///
/// **视觉原理**：取景框是一个黑色圆角容器，**四周等厚黑边 = 一整颗灵动岛的高度**。
/// 框顶正好压在岛顶（11.5pt）、画面上缘正好接在岛底（48.17pt）——
/// 岛不多不少嵌满顶边这一条，边框与岛浑然一体、没有接缝。
/// 打开时容器从灵动岛的尺寸插值放大到取景框尺寸，像是那颗药丸自己长开；
/// 同时底部相纸与快门自下而上浮起，两段动画在 0.5s 内合拢。
struct PaperCameraView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(StoreKitManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false
    @AppStorage("defaultPaperStyle") private var defaultPaperStyleRaw: String = PaperStyle.polaroid.rawValue

    /// 拍完点「写下这一刻」回调：图片已居中裁方，相纸样式为用户在下方选中的那张
    /// 回调三样：原始拍摄产物（配对+存相册用）、裁过的方图（显示用）、选中的相纸样式
    let onCapture: (CameraShot, UIImage, PaperStyle) -> Void

    @State private var camera = CameraSession()
    @State private var isAuthorized = false
    @State private var permissionDenied = false
    @State private var sessionFailed = false
    /// 拍到的照片（显示用的小方图，照片一处理完就有）；非 nil 时取景框变为相纸预览
    @State private var shot: UIImage?
    /// 完整的拍摄产物：Live Photo 的那段视频也写完了才有（比 `shot` 晚一秒多）
    @State private var capturedShot: CameraShot?
    /// 存进日记用的原尺寸方图，后台裁好
    @State private var fullSquare: UIImage?
    /// 这一张的编号：点了「重拍」之后，上一张晚到的回调不认
    @State private var captureID = UUID()
    /// 点了「写下这一刻」，但视频 / 原尺寸方图还没好：好了自动接着走
    @State private var commitRequested = false
    @State private var isCapturing = false
    @State private var flashOpacity: Double = 0
    /// 相纸落入时的轻微倾斜，给「递到手里」的手感
    @State private var paperTilt: Double = 0
    /// 选中的相纸样式（初值取设置里的默认相纸）
    @State private var selectedPaper: PaperStyle = .polaroid
    /// 相纸面板是否铺开。收起时底部只有一条工具条，把空间还给取景框。
    @State private var showPaperPicker = false
    /// 闪光灯意向（三态循环：自动 → 开 → 关）
    @State private var flash: FlashSetting = .auto
    /// 开合动画：false = 收成灵动岛大小，true = 完全展开
    @State private var expanded = false
    // 变焦
    @State private var zoom: CGFloat = 1
    @State private var dragStartZoom: CGFloat?
    /// 上一次触发震动的 0.5× 档位，用于「每跨半档响一下」
    @State private var lastHapticStep = 2

    /// 选中那颗镜头钮的深色圆片在钮之间滑
    @Namespace private var zoomNamespace

    /// 预设倍数（2026-10-17 产品定：1.5×、3×、5× 常用，再加回到 1× 的那一颗）
    private static let zoomPresets: [CGFloat] = [1, 1.5, 3, 5]
    /// 镜头钮：没选中的小一圈，选中的大一圈
    private static let lensButtonSize: CGFloat = 34
    private static let lensButtonActiveSize: CGFloat = 42
    /// 钮与钮之间、钮与胶囊边之间的空隙（点按时按它推算点在哪颗钮上，和布局用同一组数）
    private static let lensSpacing: CGFloat = 4
    /// 在胶囊上左右拖多远走完 1×→5×
    private static let zoomDragRange: CGFloat = 200

    // MARK: 灵动岛几何（14 Pro 起各代一致）
    /// 岛顶距屏幕顶端
    private static let islandTopY: CGFloat = 11.5
    /// 岛高
    private static let islandHeight: CGFloat = 36.67
    private static let islandWidth: CGFloat = 126
    private static let islandRadius: CGFloat = islandHeight / 2
    /// 岛底距屏幕顶端
    private static let islandBottomY: CGFloat = islandTopY + islandHeight
    /// 判定为灵动岛机型的安全区阈值（刘海机 ~47-50，灵动岛 ~59+）
    private static let islandSafeAreaThreshold: CGFloat = 55

    /// 取景框顶边。取在岛顶**之上** 2pt —— 只要框沿高过岛沿，岛就不可能凸出来。
    /// **这是唯一需要按真机微调的数字**：岛还凸就调小（更负），框黑带太高就调大。
    private static let frameTopNudge: CGFloat = -2
    private static let frameTopOnIsland: CGFloat = islandTopY + frameTopNudge
    /// 顶部黑边。约束：`≥ islandBottomY - frameTopOnIsland`（= 38.7），否则画面会压到岛上；
    /// 48 在此之上留了约 9pt 余量。
    private static let topBezel: CGFloat = 48
    /// 两侧与底部黑边 = 一颗灵动岛的高度，比顶部略窄。
    private static let sideBezel: CGFloat = islandHeight
    /// 画面圆角；外框圆角 = 它 + bezel（同心）
    private static let innerRadius: CGFloat = 22

    /// 印泥红 —— 呼应 App 里的印章体系，比纯红更沉稳
    private static let shutterRed = Color(red: 0.76, green: 0.24, blue: 0.19)
    /// 相纸预览卡缩放（原卡 120×160，相机里用紧凑版）
    private static let cardScale: CGFloat = 0.62
    /// 拍照前相纸条里的占位图 —— 用品牌形象填充，别让相纸里空着一片灰。
    ///
    /// 优先用工程里的 `BrandLogo` 资源；没有时按品牌色（藏青 + 金）现画一张字标兜底。
    /// 把 logo 图拖进 Assets 并命名 `BrandLogo`，这里会自动切到真图。
    private static let placeholderImage: UIImage = {
        if let asset = UIImage(named: "BrandLogo") { return asset }

        let size = CGSize(width: 240, height: 320)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.051, green: 0.227, blue: 0.361, alpha: 1).setFill()   // 品牌藏青
            ctx.fill(CGRect(origin: .zero, size: size))

            let gold = UIColor(red: 0.710, green: 0.596, blue: 0.369, alpha: 1)
            let text = "Sinara" as NSString
            let font = UIFont(name: "Georgia", size: 40) ?? .systemFont(ofSize: 40)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: gold]
            let textSize = text.size(withAttributes: attrs)
            text.draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: attrs
            )
        }
    }()

    var body: some View {
        GeometryReader { geo in
            let hasIsland = geo.safeAreaInsets.top >= Self.islandSafeAreaThreshold
            let frameTop = hasIsland ? Self.frameTopOnIsland : geo.safeAreaInsets.top + 8
            // 近乎满宽：岛被包得越深，融合越自然
            let frameWidth = geo.size.width - 36

            ZStack(alignment: .top) {
                themeManager.current.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    viewfinder(width: frameWidth)
                        .padding(.top, frameTop)

                    // 品牌 + 镜头钮 + 快门
                    VStack(spacing: 0) {
                        Spacer(minLength: 8)
                        brandMark
                        Spacer(minLength: 14)
                        // 拍完换成「重拍 / 写下这一刻」时镜头钮只是藏起来、位置还占着：下面的按钮不上下跳
                        zoomButtons
                            .opacity(shot == nil ? 1 : 0)
                            .allowsHitTesting(shot == nil)
                            .padding(.bottom, 16)
                        if shot == nil {
                            captureControls
                        } else {
                            reviewControls
                        }
                        Spacer(minLength: 8)
                    }
                    .frame(maxWidth: .infinity)
                    .offset(y: expanded ? 0 : 40)
                    .opacity(expanded ? 1 : 0)

                    bottomBar
                        .offset(y: expanded ? 0 : 60)
                        .opacity(expanded ? 1 : 0)

                    Spacer(minLength: 6)
                }
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)

                // 快门白闪
                Color.white
                    .ignoresSafeArea()
                    .opacity(flashOpacity)
                    .allowsHitTesting(false)
            }
        }
        .task {
            // 默认设成了会员款、但现在不是会员（会员到期）→ 退回宝丽来（尺素会员）
            selectedPaper = PaperStyle.defaultStyle(raw: defaultPaperStyleRaw, isMember: store.isMember)
            // 先展开（视觉立刻有反馈），再并行起相机会话
            withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) { expanded = true }
            await setUpCamera()
        }
        .onDisappear { camera.stop() }
        .paywallCover(isPresented: $showPaywall)
    }

    // MARK: - 取景框（从灵动岛生长）

    private func viewfinder(width: CGFloat) -> some View {
        let inner = width - Self.sideBezel * 2
        // 顶厚侧窄 → 机身比画面高出 (topBezel - sideBezel)
        let fullHeight = Self.topBezel + inner + Self.sideBezel
        // 收起态 = 灵动岛尺寸；展开态 = 满幅取景框
        let boxW = expanded ? width : Self.islandWidth
        let boxH = expanded ? fullHeight : Self.islandHeight
        // 同心圆角：外圆角 = 内圆角 + 侧边厚度（横向决定四角的黑边宽度）
        let radius = expanded ? Self.innerRadius + Self.sideBezel : Self.islandRadius

        return ZStack(alignment: .top) {
            Color.black

            Group {
                if let shot {
                    // 拍完：照片以相纸形态落下（白边 + 底部留白）
                    paperPrint(image: shot, side: inner)
                        .rotationEffect(.degrees(paperTilt))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if isAuthorized {
                    CameraPreview(session: camera.session)
                        .frame(width: inner, height: inner)
                        .clipShape(RoundedRectangle(cornerRadius: Self.innerRadius, style: .continuous))
                } else {
                    placeholder(side: inner)
                }
            }
            .padding(.top, Self.topBezel)   // 画面从灵动岛下缘开始
            // 收起时只剩一颗黑药丸，画面不「挤」在里面
            .opacity(expanded ? 1 : 0)
        }
        .frame(width: boxW, height: boxH)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        // 外层固定占位 + 顶部对齐：动画期间下方元素不跳动
        .frame(width: width, height: fullHeight, alignment: .top)
    }

    /// 变焦：快门上方一枚浅色胶囊，里面四颗镜头钮 1 / 1.5 / 3 / 5（2026-10-17 产品从四版草稿里选的「镜头钮」；
    /// 原来右边竖的拉杆用着反人体工学，后来横的刻度尺不好看）。
    ///
    /// - 点一颗钮：镜头平滑地推到那个倍数（0.3 秒），深色的圆片滑过去
    /// - 在胶囊上左右拖：跟手微调，深色那颗写着此刻的倍数（「2.3×」）；松手时离哪个预设很近就吸过去
    /// - 深色的是「不超过当前倍数的最大那颗」：2.3× 时停在 1.5 那颗上，和原相机一样
    /// - 拖动按**对数**走：1×→1.5× 和 3×→5× 放大的比例差不多，手指走的距离也差不多
    /// - 每跨 0.5× 轻轻一震
    private var zoomButtons: some View {
        let theme = themeManager.current
        let active = activeZoomPreset

        return HStack(spacing: Self.lensSpacing) {
            ForEach(Array(Self.zoomPresets.enumerated()), id: \.offset) { index, preset in
                let isActive = index == active
                let side = isActive ? Self.lensButtonActiveSize : Self.lensButtonSize
                Text(verbatim: isActive ? Self.zoomValueText(zoom) : Self.zoomShortText(preset))
                    .font(.system(size: isActive ? 12 : 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isActive ? theme.background : theme.textSecondary)
                    .frame(width: side, height: side)
                    .background {
                        if isActive {
                            Circle()
                                .fill(theme.textPrimary)
                                .matchedGeometryEffect(id: "activeLens", in: zoomNamespace)
                        }
                    }
            }
        }
        .padding(Self.lensSpacing)
        .background(Capsule().fill(theme.surfaceBackground))
        .overlay(Capsule().strokeBorder(theme.border, lineWidth: 0.8))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        .animation(.smooth(duration: 0.25), value: active)
        .contentShape(Capsule())
        // 点和拖用同一个手势：钮上各挂一个「点」的话，从钮上起手拖完松开，那颗钮的点也会被认（2026-10-17 模拟器日志实测），
        // 刚拖好的倍数又被拉回那颗钮。所以只在整枚胶囊上认一个：动了 4pt 以上 = 拖，没动开就松手 = 点了落点下的那颗
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard dragStartZoom != nil || abs(value.translation.width) > 4 else { return }
                    let start = dragStartZoom ?? zoom
                    if dragStartZoom == nil { dragStartZoom = zoom }
                    let position = Self.zoomPosition(start) + value.translation.width / Self.zoomDragRange
                    setZoomFollowingFinger(Self.zoom(atPosition: position))
                }
                .onEnded { value in
                    guard dragStartZoom != nil else {
                        if let preset = lensPreset(at: value.location.x) { jumpZoom(to: preset) }
                        return
                    }
                    dragStartZoom = nil
                    // 松手时离某个预设很近（对数位置差 4% 以内）就吸过去
                    if let preset = Self.zoomPresets.first(where: { abs(Self.zoomPosition($0) - Self.zoomPosition(zoom)) < 0.04 }),
                       preset != zoom {
                        jumpZoom(to: preset)
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("变焦"))
        .accessibilityValue(Text(verbatim: Self.zoomValueText(zoom)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                if let next = Self.zoomPresets.first(where: { $0 > zoom + 0.01 }) { jumpZoom(to: next) }
            case .decrement:
                if let previous = Self.zoomPresets.last(where: { $0 < zoom - 0.01 }) { jumpZoom(to: previous) }
            @unknown default:
                break
            }
        }
    }

    /// 深色的那颗：不超过当前倍数的最大预设
    private var activeZoomPreset: Int {
        Self.zoomPresets.lastIndex { $0 <= zoom + 0.01 } ?? 0
    }

    /// 点在胶囊里横坐标 `x` 处：是哪颗钮（按布局推算：边上留 `lensSpacing`，选中的那颗大一圈）；点在缝里算旁边那颗
    private func lensPreset(at x: CGFloat) -> CGFloat? {
        let active = activeZoomPreset
        var left = Self.lensSpacing
        for (index, preset) in Self.zoomPresets.enumerated() {
            let width = index == active ? Self.lensButtonActiveSize : Self.lensButtonSize
            if x <= left + width + Self.lensSpacing / 2 { return preset }
            left += width + Self.lensSpacing
        }
        return Self.zoomPresets.last
    }

    /// 倍率的对数位置（0…1）：拖动按它走
    private static func zoomPosition(_ zoom: CGFloat) -> CGFloat {
        log(max(zoom, 1)) / log(CameraSession.maxZoom)
    }

    private static func zoom(atPosition position: CGFloat) -> CGFloat {
        exp(min(max(position, 0), 1) * log(CameraSession.maxZoom))
    }

    /// 没选中的钮上写「1」「1.5」「3」「5」
    private static func zoomShortText(_ zoom: CGFloat) -> String {
        zoom == zoom.rounded() ? String(format: "%.0f", zoom) : String(format: "%.1f", zoom)
    }

    /// 选中的钮上：正好在预设上写「1.5×」「3×」，在两个预设之间写一位小数「2.3×」
    private static func zoomValueText(_ zoom: CGFloat) -> String {
        if let preset = zoomPresets.first(where: { abs($0 - zoom) < 0.01 }) {
            return zoomShortText(preset) + "×"
        }
        return String(format: "%.1f×", zoom)
    }

    /// 拖动：镜头直接跟手；每跨 0.5× 轻轻一震
    private func setZoomFollowingFinger(_ next: CGFloat) {
        zoom = next
        camera.setZoom(next)
        let step = Int((next * 2).rounded())
        if step != lastHapticStep {
            lastHapticStep = step
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
        }
    }

    /// 点钮 / 松手吸附：深色圆片和镜头一起平滑地推过去
    private func jumpZoom(to target: CGFloat) {
        lastHapticStep = Int((target * 2).rounded())
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
        withAnimation(.smooth(duration: 0.3)) { zoom = target }
        camera.rampZoom(to: target)
    }

    /// 相纸：白框包裹方形照片，底部留白更厚
    private func paperPrint(image: UIImage, side: CGFloat) -> some View {
        let photoSide = side - 16
        return VStack(spacing: 0) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: photoSide, height: photoSide * 0.82)
                .clipped()
                .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .frame(width: side, height: side)
        .background(Color(white: 0.98))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    private func placeholder(side: CGFloat) -> some View {
        let theme = themeManager.current
        return RoundedRectangle(cornerRadius: Self.innerRadius, style: .continuous)
            .fill(Color(white: 0.12))
            .frame(width: side, height: side)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: permissionDenied ? "camera.badge.ellipsis" : "camera")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.white.opacity(0.55))
                    if permissionDenied {
                        Text("需要相机权限")
                            .font(theme.labelFont)
                            .foregroundStyle(.white.opacity(0.55))
                        Button("去设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(theme.labelFont)
                        .foregroundStyle(.white.opacity(0.9))
                    } else if sessionFailed {
                        Text("相机不可用")
                            .font(theme.labelFont)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
    }

    // MARK: - 品牌字样

    private var brandMark: some View {
        let theme = themeManager.current
        return VStack(spacing: 3) {
            Text("尺素")
                .font(theme.titleFont)
                .tracking(theme.letterSpacingWide)
                .foregroundStyle(theme.textPrimary)
            Text(shot == nil ? "记录此刻" : "这一刻已经落在纸上")
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
                .contentTransition(.opacity)
        }
    }

    // MARK: - 底部工具条（二级菜单）

    /// 底部区域 = 一条常驻工具条 +（按需铺开的）相纸面板。
    ///
    /// 改版前这里是一条**常驻的横向相纸卡片**，160pt 高，一直占着屏幕下缘三分之一。
    /// 但「换相纸」是低频动作 —— 多数人选一次就不再改，却要为它一直付出这块空间。
    /// 现在收成一个按钮，把地方还给取景框，同时腾出位置放真正属于相机的设定（闪光灯）。
    private var bottomBar: some View {
        VStack(spacing: 0) {
            toolRow

            if showPaperPicker {
                paperStrip
                    // 从工具条底下「推」出来，而不是淡入 —— 有方向感才像抽屉
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
            }
        }
        .clipped()   // 面板收起时不该有内容溢到工具条上方
    }

    /// 常驻工具条：闪光灯 + 相纸入口。**只放两个** —— 再多就不简约了。
    private var toolRow: some View {
        HStack(spacing: 10) {
            if camera.isFlashAvailable {
                toolChip(
                    icon: flash.icon,
                    label: flash.displayName,
                    highlighted: flash != .off
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        flash = flash.next
                    }
                    camera.setFlash(flash.avMode)
                }
            }

            toolChip(
                icon: "square.stack",
                label: selectedPaper.displayName,
                highlighted: showPaperPicker,
                trailingChevron: true
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    showPaperPicker.toggle()
                }
            }
        }
        .padding(.vertical, 10)
    }

    /// 工具条上的胶囊按钮。图标 + 文字，选中态用主题强调色反白。
    private func toolChip(
        icon: String,
        label: LocalizedStringKey,
        highlighted: Bool,
        trailingChevron: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let theme = themeManager.current
        return Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(theme.labelFont)
                if trailingChevron {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                        // 铺开时箭头转向下方，指示「再点一下收起」
                        .rotationEffect(.degrees(showPaperPicker ? 180 : 0))
                }
            }
            .foregroundStyle(highlighted ? theme.background : theme.textSecondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(highlighted ? theme.accent : theme.cardBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 相纸选择条（铺开后才出现）

    private var paperStrip: some View {
        let theme = themeManager.current
        let cardW = 120 * Self.cardScale
        let cardH = 160 * Self.cardScale

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(PaperStyle.allCases, id: \.self) { style in
                    let isSelected = style == selectedPaper
                    let locked = style.isMemberOnly && !store.isMember
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        // 会员款：不选中，直接问要不要开通（尺素会员）
                        if locked { showPaywall = true; return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            selectedPaper = style
                        }
                        // 选完就收起：选中即完成，不该逼用户再点一次「关」。
                        // 稍延后一点，让选中态的高亮先被看见，再收抽屉。
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                showPaperPicker = false
                            }
                        }
                    } label: {
                        VStack(spacing: 6) {
                            PaperPreviewCard(
                                uiImage: shot ?? Self.placeholderImage,
                                style: style
                            )
                            .scaleEffect(Self.cardScale)
                            .frame(width: cardW, height: cardH)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(theme.accent, lineWidth: isSelected ? 2 : 0)
                                    .padding(-4)
                            }
                            .scaleEffect(isSelected ? 1.06 : 1)
                            .opacity(isSelected ? 1 : 0.55)
                            .overlay(alignment: .topTrailing) {
                                if locked { MemberBadge(size: 16).offset(x: 4, y: -4) }
                            }

                            Text(style.displayName)
                                .font(theme.labelFont)
                                .foregroundStyle(isSelected ? theme.textSecondary : theme.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 控件

    private var captureControls: some View {
        HStack(spacing: 26) {
            circleButton(icon: "xmark") { close() }
            shutterButton
            circleButton(icon: "arrow.triangle.2.circlepath") {
                camera.flip()
                // 换了镜头从 1× 开始（另一颗镜头可能还停在上次的倍数）
                camera.setZoom(1)
                lastHapticStep = 2
                withAnimation(.smooth(duration: 0.25)) { zoom = 1 }
            }
        }
    }

    private var shutterButton: some View {
        Button {
            capture()
        } label: {
            ZStack {
                Circle()
                    .fill(Self.shutterRed)
                    .frame(width: 74, height: 74)
                    .shadow(color: Self.shutterRed.opacity(0.45), radius: 10, y: 4)
                Circle()
                    .strokeBorder(.white.opacity(0.35), lineWidth: 2)
                    .frame(width: 62, height: 62)
            }
            .scaleEffect(isCapturing ? 0.9 : 1)
        }
        .disabled(!isAuthorized || isCapturing)
        .opacity(isAuthorized ? 1 : 0.4)
    }

    private var reviewControls: some View {
        let theme = themeManager.current
        return HStack(spacing: 14) {
            Button {
                retake()
            } label: {
                Text("重拍")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 96, height: 48)
                    .background(theme.cardBackground, in: Capsule())
            }

            Button {
                commitRequested = true
                commitIfReady()
            } label: {
                // 点得比 Live Photo 的视频写完还快（拍完一秒内）：等一下，好了自动接着走
                ZStack {
                    Text("写下这一刻")
                        .opacity(commitRequested ? 0 : 1)
                    if commitRequested {
                        ProgressView()
                            .tint(theme.background)
                    }
                }
                .font(theme.captionFont)
                .foregroundStyle(theme.background)
                .frame(width: 152, height: 48)
                .background(theme.accent, in: Capsule())
            }
            .disabled(commitRequested)
        }
    }

    private func circleButton(icon: String, action: @escaping () -> Void) -> some View {
        let theme = themeManager.current
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 52, height: 52)
                .background(theme.cardBackground, in: Circle())
        }
    }

    // MARK: - 动作

    /// 关闭：先收回灵动岛，再退场（取消动作值得一个「收回去」的收尾）
    private func close() {
        camera.stop()
        withAnimation(.easeIn(duration: 0.22)) { expanded = false }
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            dismiss()
        }
    }

    private func setUpCamera() async {
        let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            camera.requestAccess { cont.resume(returning: $0) }
        }
        guard granted else {
            permissionDenied = true
            return
        }
        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            camera.start { cont.resume(returning: $0) }
        }
        isAuthorized = ok
        sessionFailed = !ok
    }

    /// 按快门。照片一处理完就落到相纸上（显示用的小方图）；存进日记的原尺寸方图在后台裁，
    /// Live Photo 的视频接着写 —— 都好了「写下这一刻」才真的交出去（`commitIfReady`）。
    ///
    /// 2026-10-17 之前要等视频写完、再在主线程上解码裁剪原图才出图，拍完干等一两秒（产品真机反馈）
    private func capture() {
        let id = UUID()
        captureID = id
        capturedShot = nil
        fullSquare = nil
        commitRequested = false
        isCapturing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // 快门白闪
        withAnimation(.easeIn(duration: 0.06)) { flashOpacity = 0.85 }
        withAnimation(.easeOut(duration: 0.28).delay(0.06)) { flashOpacity = 0 }

        camera.capture(
            onPhoto: { photo in
                guard captureID == id else { return }
                isCapturing = false
                guard let photo else { return }
                // 存进日记的那张要原尺寸：后台裁，裁不出来就用显示的这张顶上
                Task.detached(priority: .userInitiated) {
                    let full = ShotImage.squareFull(from: photo.stillData)
                    await MainActor.run {
                        guard captureID == id else { return }
                        fullSquare = full ?? photo.preview
                        commitIfReady()
                    }
                }
                // 相纸「落到手里」：轻微过冲 + 随机小角度，避免每次都一模一样
                paperTilt = Double.random(in: -2.5...2.5)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                    shot = photo.preview
                }
            },
            onFinished: { captured in
                guard captureID == id else {
                    // 已经点了重拍：这一张的 Live Photo 视频没人要了
                    if let url = captured?.movieURL { try? FileManager.default.removeItem(at: url) }
                    return
                }
                capturedShot = captured
                commitIfReady()
            }
        )
    }

    /// 重拍：回到取景；上一张还没到的回调作废（`captureID`），已经写好的视频删掉
    private func retake() {
        captureID = UUID()
        if let url = capturedShot?.movieURL { try? FileManager.default.removeItem(at: url) }
        capturedShot = nil
        fullSquare = nil
        commitRequested = false
        withAnimation(.easeOut(duration: 0.2)) { shot = nil }
    }

    /// 点过「写下这一刻」、视频和原尺寸方图也都好了 → 交出去
    private func commitIfReady() {
        guard commitRequested, let capturedShot, let fullSquare else { return }
        commitRequested = false
        onCapture(capturedShot, fullSquare, selectedPaper)
        dismiss()
    }
}

// MARK: - 闪光灯三态

/// 闪光灯设定。**自成一个类型而不是直接用 `AVCaptureDevice.FlashMode`**：
/// 那个枚举没有稳定的循环顺序，也不带图标和译名，UI 层用起来会到处 switch。
enum FlashSetting: String, CaseIterable {
    case auto, on, off

    /// 点一下走到下一个状态。顺序按使用频率排：自动最常用，关闭最少用。
    var next: FlashSetting {
        switch self {
        case .auto: .on
        case .on:   .off
        case .off:  .auto
        }
    }

    var icon: String {
        switch self {
        case .auto: "bolt.badge.a"
        case .on:   "bolt.fill"
        case .off:  "bolt.slash"
        }
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .auto: "自动"
        case .on:   "闪光开"
        case .off:  "闪光关"
        }
    }

    var avMode: AVCaptureDevice.FlashMode {
        switch self {
        case .auto: .auto
        case .on:   .on
        case .off:  .off
        }
    }
}
