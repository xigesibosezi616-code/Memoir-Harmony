/**
 * 国内合规展示信息（10_BUILD_MANUAL.md 6.7；R-APP-05）。
 * 对应 iOS `Environment/ComplianceInfo.swift`。
 *
 * **为什么单独一个文件**：这些值会被设置页、应用商店元数据反复引用，
 * 而且**改错一个字就是合规问题**（备案号与主办单位必须与工信部备案系统上的
 * 记录逐字一致）。集中一处，改的时候只改一次。
 */
export class ComplianceInfo {
  /** ICP 备案号（工信部备案系统 2026-07-13 审核通过）。⚠️ 与 beian.miit.gov.cn 逐字一致，含「号-1A」后缀 */
  static readonly ICP_LICENSE: string = '陕ICP备2026017943号-1A';

  /** 备案主办单位。注意：这是**备案主体的中文全称**，与 App Store 上的
   * 「Sinara (Xi'an) Technology Co., Ltd.」是同一家公司的中英文名 */
  static readonly COMPANY_NAME: string = '玄纳司（西安）科技有限公司';

  /** 备案审核通过日期（留档用，不展示） */
  static readonly ICP_APPROVED_ON: string = '2026-07-13';
}
