import Foundation

/// 这个包是中国大陆版还是全球版。两边用的社交平台、域名都不一样（2026-10-24 产品定：先做大陆版）。
///
/// 🔴 **提交全球版之前改这一行**，并把 `OfficialAccounts.global` 填上（X、Instagram、Facebook、YouTube）——
/// 上架清单里有这一条。目前只有设置页底部的官方账号用它
enum AppEdition {
    case mainland
    case global

    static let current: AppEdition = .mainland
}
