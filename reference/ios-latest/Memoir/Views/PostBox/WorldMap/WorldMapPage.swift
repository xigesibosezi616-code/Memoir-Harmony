import SwiftUI
import UIKit
import MapKit
import CoreLocation

/// 世界笔友地图（2026-10，从邮筒页打开：左上角「笔友」，或那叠日记信纸抬头的「寄给」）。
///
/// 上面是一张摊开的地图（系统标准地图，四周晕进纸色，像参考图），下面是一叠名片：
/// - 滑名片 = 翻到下一位，地图上他的墨点变大、写出姓；他不在视野里时地图才平移过去（不来回飞）
/// - 点地图上的墨点 = 名片翻到他
/// - 名片上「寄给他」= 加进收件人：墨点换成邮戳色，从你这里画一条航线过去
/// - 已经寄出、还在路上的信，是航线上的小信封
/// - 最下面一条写着这次寄给谁、要贴几张邮票；「好了」回到邮筒
///
/// 自己起名的那一位没有住址，不在地图上：他的名片排第一张，翻到他时地图回到「你」。
///
/// **地图跟着你这里的白天黑夜走**（`MapDaylight`，三套主题一样）：天黑了是深色地图，天亮了是浅色。
struct WorldMapPage: View {
    let roster: [PenPal]
    /// 自己起名的那一位的名字
    let ownPenPalName: String
    /// 你大概在哪（只在本机用）
    let location: ApproximateLocation
    let isMember: Bool
    /// 现在能寄的世界笔友（放开了、服务端也备好了人设的）；不在里面的名片写「即将开放」
    let sendable: Set<String>
    /// 这次寄给谁：笔友 id；自己那位是 `WorldMapPage.ownID`
    @Binding var recipients: Set<String>
    /// 寄出了、还在路上的信
    let inTransit: [InTransitLetter]
    /// 一打开先翻到哪一位（比如从信箱里点「他在哪」）；nil = 第一张（自己那位）
    let initialFocus: String?

    static let ownID = "own"

    struct InTransitLetter: Identifiable {
        let id: UUID
        let penPalID: String
        /// 0…1：信在航线上走到哪儿了
        let progress: Double
    }

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var focusedID: String?
    @State private var position: MapCameraPosition
    @State private var visibleRect: MKMapRect = .world
    @State private var cameraDistance: Double = 30_000_000
    /// 打开时翻到的那一位，还没确认他在不在视野里
    @State private var initialRevealPending = true
    /// 你这里天黑了没有 —— 决定地图是深色还是浅色
    @State private var isNight: Bool
    @State private var showPaywall = false

    init(
        roster: [PenPal],
        ownPenPalName: String,
        location: ApproximateLocation,
        isMember: Bool,
        sendable: Set<String>,
        recipients: Binding<Set<String>>,
        inTransit: [InTransitLetter] = [],
        initialFocus: String? = nil
    ) {
        self.roster = roster
        self.ownPenPalName = ownPenPalName
        self.location = location
        self.isMember = isMember
        self.sendable = sendable
        _recipients = recipients
        self.inTransit = inTransit
        self.initialFocus = initialFocus
        // 🔴 相机的起点必须在这里给，不能等 onAppear 再设：那时地图已经按默认（库比蒂诺、最近距离）摆好了，
        // 设进去的位置被吞掉，接着「翻到 McRae」把地图放大到了城市级（2026-10-15 模拟器日志）
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: Self.startCenter(location.coordinate),
            span: MKCoordinateSpan(latitudeDelta: 150, longitudeDelta: 359)
        )))
        _isNight = State(initialValue: MapDaylight.isNight(at: .now, location: location.coordinate))
    }

    private var userLocation: CLLocationCoordinate2D? { location.coordinate }

    var body: some View {
        let theme = themeManager.current
        let palette = LetterPalette.of(themeID: themeManager.currentThemeID)
        let postInk = Postmark.ink(themeID: themeManager.currentThemeID)

        VStack(spacing: 0) {
            header(theme)
            if userLocation == nil {
                locationNote(theme)
            }
            map(theme: theme, ink: MapInk.of(night: isNight, postInk: postInk))
            cards(palette: palette, postInk: postInk)
                .padding(.top, 4)
            recipientsBar(theme: theme)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(theme.preferredColorScheme == .dark ? .dark : .light, for: .navigationBar)
        .paywallCover(isPresented: $showPaywall)
        .onAppear {
            if focusedID == nil { focusedID = initialFocus ?? cardIDs.first }
            location.refresh()
        }
        // 打开时翻到的第一位，等地图摆好再看要不要平移（见 onMapCameraChange）。
        // 🔴 这时地图还没排好版，报上来的是默认相机（库比蒂诺、拉到最近），拿它判断「看不看得见」
        // 会把地图一下子放大到城市级（2026-10-15 模拟器日志）
        .onChange(of: focusedID) { old, id in
            guard old != nil else { return }
            reveal(id)
        }
        // 天黑天亮：每分钟看一眼；定位到了也重新算（按太阳算比按钟点准）
        .task(id: userLocation.map { "\($0.latitude),\($0.longitude)" }) {
            while !Task.isCancelled {
                let night = MapDaylight.isNight(at: .now, location: userLocation)
                if night != isNight {
                    withAnimation(.easeInOut(duration: 1.2)) { isNight = night }
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    // MARK: - 页眉

    private func header(_ theme: any AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("世界笔友")
                .font(theme.titleFont)
                .foregroundStyle(theme.textPrimary)
            Text("\(roster.count) 位笔友，住在世界各地")
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    /// 不知道你在哪：说一句为什么要定位，用户点了才问（不一进来就弹权限框）
    private func locationNote(_ theme: any AppTheme) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "location")
            if location.isDenied {
                Text("定位没开，世界笔友的回信都按一两天算")
            } else {
                Text("打开定位，就能算出信要走多远")
            }
            Spacer(minLength: 4)
            Button {
                if location.isDenied {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } else {
                    location.requestPermission()
                }
            } label: {
                if location.isDenied {
                    Text("去设置")
                } else {
                    Text("打开")
                }
            }
            .font(theme.captionFont.weight(.medium))
            .foregroundStyle(theme.textPrimary)
        }
        .font(theme.captionFont)
        .foregroundStyle(theme.textSecondary)
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
    }

    // MARK: - 地图

    private func map(theme: any AppTheme, ink: MapInk) -> some View {
        Map(
            position: $position,
            bounds: MapCameraBounds(minimumDistance: Self.closestDistance),
            interactionModes: [.pan, .zoom]
        ) {
            if let me = userLocation {
                // 航线：收件人用邮戳色；正在看、还没选的那位淡淡一条，看得出有多远
                ForEach(routeTargets, id: \.penPal.id) { target in
                    MapPolyline(coordinates: [me, target.penPal.location], contourStyle: .geodesic)
                        .stroke(
                            target.isRecipient ? ink.post.opacity(0.85) : ink.route,
                            style: StrokeStyle(lineWidth: target.isRecipient ? 1.6 : 1.1, lineCap: .round, dash: [1.5, 5])
                        )
                }
                ForEach(inTransit) { letter in
                    if let penPal = roster.first(where: { $0.id == letter.penPalID }) {
                        Annotation(penPal.surname.resolved(for: locale),
                                   coordinate: PenPalTravel.point(from: me, to: penPal.location, fraction: letter.progress),
                                   anchor: .center) {
                            TransitEnvelopeMark(ink: ink)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                Annotation(NSLocalizedString("你", bundle: .appLanguage, comment: "世界笔友地图上标出你自己的位置"),
                           coordinate: me, anchor: .center) {
                    Button { focus(Self.ownID) } label: {
                        YouMark(ink: ink)
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
            // 正在看的那位最后画，压在别人上面（京都和东京挨得很近）
            ForEach(dotOrder) { penPal in
                Annotation(penPal.surname.resolved(for: locale), coordinate: penPal.location, anchor: .center) {
                    Button { focus(penPal.id) } label: {
                        PenPalDot(
                            ink: ink,
                            isRecipient: recipients.contains(penPal.id),
                            isFocused: focusedID == penPal.id,
                            name: penPal.surname.resolved(for: locale)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: "\(penPal.place.resolved(for: locale)) · \(penPal.surname.resolved(for: locale))"))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        // 地图自己的「地图」标志和「法律信息」要露在晕边外面（不能被盖住）
        .safeAreaPadding(.bottom, 26)
        .safeAreaPadding(.horizontal, 14)
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRect = context.rect
            cameraDistance = context.camera.distance
            // 系统地图最远只能拉到大约三分之一个地球：打开时翻到的那位可能不在视野里。
            // 等地图真的摆到起点（不是排版前那个默认相机）再判断，看不见就平移过去
            if initialRevealPending, Self.isNear(context.camera.centerCoordinate, Self.startCenter(userLocation)) {
                initialRevealPending = false
                // 打开时只要露在视野里就不动（哪怕贴着边）：以「你」为中心的那一面世界优先
                reveal(focusedID, margin: 0)
            }
        }
        // 白天浅色、夜里深色 —— 跟你这里的天色，不跟主题、也不跟手机的深色模式
        .environment(\.colorScheme, isNight ? .dark : .light)
        .overlay { EdgeFade(color: theme.background) }
        .frame(maxHeight: .infinity)
    }

    /// 最多放大到多近（相机离地面的距离，米）。
    ///
    /// 🔴 **2026-10-16 产品定：最多放大到比例尺「0 · 125 · 250 公里」那一档**，再近就能看清笔友在哪个镇、哪条街 ——
    /// 笔友是虚构的，可那附近住着真人（斯图尔特岛常住只有几百人），正好有用户住在那儿就不好了。缩小不限，照系统的。
    /// 模拟器 iPhone 17 Pro 实测：相机 1000 km 时比例尺是 0–50–100–150 公里，1500 km 是 0–125–250 公里，
    /// 3000 km 起是 0–250–500 公里（先定过 500 公里那档，看着太小，改成 125）。
    /// 原来是 400 km，能放大到 0–25–50 公里、看得清市区的路
    private static let closestDistance: Double = 1_500_000

    /// 一打开地图的中心：你所在的经度、略偏北的纬度（在中国看，就是太平洋在中间的那种世界地图）
    private static func startCenter(_ user: CLLocationCoordinate2D?) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 10, longitude: user?.longitude ?? 110)
    }

    private static func isNear(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < 1 && abs(a.longitude - b.longitude) < 1
    }

    private var dotOrder: [PenPal] {
        roster.sorted { a, _ in a.id != focusedID }
    }

    private struct RouteTarget {
        let penPal: PenPal
        let isRecipient: Bool
    }

    private var routeTargets: [RouteTarget] {
        var targets = roster.filter { recipients.contains($0.id) }.map { RouteTarget(penPal: $0, isRecipient: true) }
        if let focusedID, !recipients.contains(focusedID), let penPal = roster.first(where: { $0.id == focusedID }) {
            targets.append(RouteTarget(penPal: penPal, isRecipient: false))
        }
        return targets
    }

    // MARK: - 名片

    /// 名片的顺序：自己那位在最前；世界笔友按离你从近到远（不知道你在哪就按名册顺序）
    private var cardIDs: [String] {
        [Self.ownID] + orderedRoster.map(\.id)
    }

    private var orderedRoster: [PenPal] {
        guard let me = userLocation else { return roster }
        return roster.sorted {
            PenPalTravel.distanceKilometers(me, $0.location) < PenPalTravel.distanceKilometers(me, $1.location)
        }
    }

    private func cards(palette: LetterPalette, postInk: Color) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                card(.own(name: ownPenPalName), id: Self.ownID, palette: palette, postInk: postInk)
                ForEach(orderedRoster) { penPal in
                    card(.world(penPal), id: penPal.id, palette: palette, postInk: postInk)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 8)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $focusedID, anchor: .center)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 28, for: .scrollContent)
        .frame(height: PenPalCard.height + 16)
    }

    private func card(_ subject: PenPalCard.Subject, id: String, palette: LetterPalette, postInk: Color) -> some View {
        PenPalCard(
            subject: subject,
            userLocation: userLocation,
            isRecipient: recipients.contains(id),
            isMember: isMember,
            canSend: id == Self.ownID || sendable.contains(id),
            palette: palette,
            postInk: postInk,
            onToggle: { toggle(id) },
            onBecomeMember: { showPaywall = true }
        )
        // 名片和滚动区一样宽（两边各留 28pt）：一打开「居中」和滑完「贴左对齐」落在同一个位置，
        // 左右各露出邻居的一条边，看得出还有
        .containerRelativeFrame(.horizontal)
        .id(id)
    }

    // MARK: - 收件人

    private func recipientsBar(theme: any AppTheme) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("这次寄给")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
                Text(verbatim: recipientNames.isEmpty ? "—" : recipientNames)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if stampCount > 0 {
                Text("贴 \(stampCount) 张邮票")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize()
            }
            Button { dismiss() } label: {
                Text("好了")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.background)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(theme.textPrimary))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.border).frame(height: 0.5)
        }
    }

    private var recipientNames: String {
        WorldMapPage.names(of: recipients, ownPenPalName: ownPenPalName, roster: orderedRoster, locale: locale)
    }

    /// 收件人的名字，按名片的顺序（自己那位在前），用这种语言的列举方式连起来（「青鸟、天野和 McRae」）
    static func names(of recipients: Set<String>, ownPenPalName: String, roster: [PenPal], locale: Locale) -> String {
        ([ownID] + roster.map(\.id)).filter { recipients.contains($0) }.map { id in
            id == ownID ? ownPenPalName : (roster.first { $0.id == id }?.surname.resolved(for: locale) ?? id)
        }
        .formatted(.list(type: .and, width: .narrow).locale(locale))
    }

    /// 一位一张，南极两张；自己那位也算一张
    private var stampCount: Int {
        recipients.reduce(0) { sum, id in
            sum + (id == Self.ownID ? 1 : (roster.first { $0.id == id }?.postage ?? 1))
        }
    }

    // MARK: - 动作

    private func focus(_ id: String) {
        if reduceMotion {
            focusedID = id
        } else {
            withAnimation(.easeInOut(duration: 0.35)) { focusedID = id }
        }
    }

    private func toggle(_ id: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if recipients.contains(id) {
                // 至少寄给一位：最后一位划不掉
                guard recipients.count > 1 else { return }
                recipients.remove(id)
            } else {
                recipients.insert(id)
            }
        }
    }

    /// 翻到的那位不在视野里，才把地图平移过去（保持远近不变）；在视野里就不动 —— 不让地图跟着名片来回飞。
    /// `margin`：离边多近就算「看不清」（占视野的比例）；贴边的墨点下面写着姓，会被晕边吃掉
    private func reveal(_ id: String?, margin: Double = 0.1) {
        guard let id else { return }
        let coordinate: CLLocationCoordinate2D?
        if id == Self.ownID {
            coordinate = userLocation
        } else {
            coordinate = roster.first { $0.id == id }?.location
        }
        guard let coordinate else { return }
        let inner = visibleRect.insetBy(dx: visibleRect.size.width * margin, dy: visibleRect.size.height * margin * 1.2)
        guard !inner.contains(MKMapPoint(coordinate)) else { return }
        let camera = MapCamera(centerCoordinate: coordinate, distance: cameraDistance)
        if reduceMotion {
            position = .camera(camera)
        } else {
            withAnimation(.easeInOut(duration: 0.9)) { position = .camera(camera) }
        }
    }
}

/// 地图四周晕进页面的纸色（参考图那样），不挡手势
private struct EdgeFade: View {
    let color: Color

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [color, color.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 34)
                Spacer(minLength: 0)
                LinearGradient(colors: [color.opacity(0), color], startPoint: .top, endPoint: .bottom)
                    .frame(height: 22)
            }
            HStack(spacing: 0) {
                LinearGradient(colors: [color, color.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 18)
                Spacer(minLength: 0)
                LinearGradient(colors: [color.opacity(0), color], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 18)
            }
        }
        .allowsHitTesting(false)
    }
}
