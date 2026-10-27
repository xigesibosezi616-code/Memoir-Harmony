import SwiftUI
import UIKit

/// 一个官方账号：平台的小 logo + 怎么打开。
///
/// 装了那个 App 就直接打开到我们的主页，没装就用网页打开：
/// 先试 `appURL`（平台自己的 URL scheme，打不开会回 false，不会弹窗），再开 `webURL`。
/// `webURL` 尽量用平台的分享短链 —— 那是平台自己的域名，装了 App 时系统会直接交给 App（通用链接），
/// 而且小红书的网页主页要带分享链接里的令牌才看得到
struct OfficialAccount: Identifiable {
    let id: String
    /// Assets 里的 logo（单色 SVG，按模板着色。来自 Simple Icons，CC0；商标归各平台）
    let logo: String
    /// logo 在小方块里显示多高。字标（小红书）是扁的，按宽度铺满就够了
    let height: CGFloat
    /// 读屏念的名字，也是长按时的提示
    let name: LocalizedStringKey
    let appURL: URL?
    let webURL: URL
}

/// 官方账号名单，按版本分（`AppEdition`）
enum OfficialAccounts {
    static var current: [OfficialAccount] {
        switch AppEdition.current {
        case .mainland: mainland
        case .global: global
        }
    }

    /// 中国大陆版：小红书、抖音、微博（2026-10-24 用户给的官方账号）
    static let mainland: [OfficialAccount] = [
        OfficialAccount(
            id: "xiaohongshu", logo: "BrandXiaohongshu", height: 8.5, name: "小红书",
            appURL: URL(string: "xhsdiscover://user/5a0af5e94eacab4314599675"),
            webURL: URL(string: "https://xhslink.cn/o/4zXwDZk0tsn")!),
        OfficialAccount(
            // 抖音的主页只拿得到 sec_uid，App 的 scheme 要数字 uid —— 只用分享短链（装了抖音会直接打开）
            id: "douyin", logo: "BrandDouyin", height: 18, name: "抖音",
            appURL: nil,
            webURL: URL(string: "https://v.douyin.com/hs0l7Jku-5M/")!),
        OfficialAccount(
            id: "weibo", logo: "BrandWeibo", height: 15, name: "微博",
            appURL: URL(string: "sinaweibo://userinfo?uid=7934302970"),
            webURL: URL(string: "https://weibo.com/u/7934302970")!),
    ]

    /// 🔴 全球版：X、Instagram、Facebook、YouTube —— 账号还没给，提交全球版之前补上（logo 同样从 Simple Icons 取）
    static let global: [OfficialAccount] = []

    @MainActor
    static func open(_ account: OfficialAccount) {
        guard let app = account.appURL else {
            UIApplication.shared.open(account.webURL)
            return
        }
        UIApplication.shared.open(app) { opened in
            if !opened { UIApplication.shared.open(account.webURL) }
        }
    }
}

/// 设置页最底下一组「关注我们」：一行一个平台，前面是细线小方框里放平台的小 logo，后面是外跳箭头（2026-10-26，照苹果设置的排法）。
///
/// 第一版是「关注我们 ｜ 三个 logo」排成一行，用户嫌丑，改成和上面各组一样的行。
/// logo 用平台自己的单色小标（不用方块 App 图标），和上面各行图标同一个颜色，不给平台配色。
/// 评分不在这里：上面「给我们评分」那一行就是。名单为空（全球版还没给账号）时整组不出现
struct OfficialAccountsSection: View {
    let theme: any AppTheme
    let themeID: String

    var body: some View {
        if !OfficialAccounts.current.isEmpty {
            Section {
                ForEach(OfficialAccounts.current) { account in
                    Button { OfficialAccounts.open(account) } label: {
                        HStack(spacing: 14) {
                            SettingsTile(theme: theme) {
                                Image(account.logo)
                                    .resizable()
                                    .renderingMode(.template)
                                    .scaledToFit()
                                    .frame(width: 22, height: account.height)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Text(account.name)
                                .font(.body)
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(SettingsPalette.card(themeID))
                    .accessibilityLabel(Text(account.name))
                }
            } header: {
                Text("关注我们")
            }
        }
    }
}

/// 账户卡上的头像：尺素的手写 m.（桌面图标同一份字形），圆底是主题的纸色、字是主题的字色。
/// 苹果不给 App 读 Apple 账户的头像；用户定不让人另选照片，统一用这个（2026-10-26）
struct MarkAvatar: View {
    let size: CGFloat
    let themeID: String

    var body: some View {
        let colors = ThemeSwatch.colors(for: themeID)
        Circle()
            .fill(colors.background)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .overlay {
                HandwritingView(ink: colors.ink, start: .distantPast, animated: false)
                    .frame(width: size * 0.6)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
