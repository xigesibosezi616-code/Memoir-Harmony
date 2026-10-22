import Foundation

/// 国内合规展示信息。
///
/// **为什么单独一个文件**：这些值会被设置页、隐私政策页、官网、应用商店元数据反复引用，
/// 而且**改错一个字就是合规问题**（备案号与主办单位必须与工信部备案系统上的记录逐字一致）。
/// 集中一处，改的时候只改一次。
enum ComplianceInfo {
    /// ICP 备案号（工信部备案系统 2026-07-13 审核通过）。
    /// ⚠️ 必须与 https://beian.miit.gov.cn 上的记录**逐字一致**，包括「号-1A」这个后缀。
    static let icpLicense = "陕ICP备2026017943号-1A"

    /// 备案主办单位。注意：这是**备案主体的中文全称**，与 App Store 上的
    /// 「Sinara (Xi'an) Technology Co., Ltd.」是同一家公司的中英文名。
    static let companyName = "玄纳司（西安）科技有限公司"

    /// 备案审核通过日期（留档用，不展示）
    static let icpApprovedOn = "2026-07-13"
}
