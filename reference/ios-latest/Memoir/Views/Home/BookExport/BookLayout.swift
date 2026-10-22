import SwiftUI
import UIKit

/// 精装 PDF 的版式（2026-10-21 产品定：**A5、固定书页配色、正文宋体**，会员专属，见 `Docs/MEMBERSHIP.md`）。
///
/// 一本书从前往后：封面 → 扉页 → 目录 → 正文 → 版权页 → 封底（2026-10-23 去掉了前后两张纯色环衬，正文不再插空白页凑右页）。
/// 尺寸都是 PDF 的点（1/72 英寸）。**分页（`BookPaginator`）和页面（`BookPageView`）共用这一份**，
/// 和阅读器的 `ReaderLayout` 一个道理：两边各写一份数字，改了一边忘了另一边，一页就装不下、字被静默截掉
enum BookLayout {
    /// A5：148 × 210 mm
    static let pageSize = CGSize(width: 419.53, height: 595.28)

    // MARK: 版心

    /// 上下留白
    static let top: CGFloat = 60
    static let bottom: CGFloat = 64
    /// 订口（靠书脊那边）宽一点，装订后不吃字；切口窄一点
    static let inner: CGFloat = 60
    static let outer: CGFloat = 44
    static var textWidth: CGFloat { pageSize.width - inner - outer }
    static var textHeight: CGFloat { pageSize.height - top - bottom }

    /// 页眉（左页书名、右页月份）的基线离纸顶多远；页码离纸底多远
    static let runningHeadY: CGFloat = 34
    static let folioY: CGFloat = 40
    static let runningHeadSize: CGFloat = 7.5
    static let folioSize: CGFloat = 8

    // MARK: 正文

    static let bodySize: CGFloat = 10.5
    static let bodyLineSpacing: CGFloat = 6
    /// 段与段、段与图之间
    static let blockGap: CGFloat = 8
    static let headingSize: CGFloat = 13
    /// 量出来的高度和真正排出来的有一点出入（字体回退、舍入）：宁可页底多空一点，不能挤掉字
    static let safetyMargin: CGFloat = 6

    // MARK: 篇首

    static let dateSize: CGFloat = 8
    static let titleSize: CGFloat = 15
    static let moodSize: CGFloat = 8
    /// 标题下那一道短线
    static let ruleWidth: CGFloat = 28
    static let headerBottomGap: CGFloat = 16
    /// 接着排的时候，两篇之间空多少
    static let entryGap: CGFloat = 30

    // MARK: 照片

    /// 照片占版心宽的 62%，居中，带原来的相纸
    static let figureWidthRatio: CGFloat = 0.62
    /// 一张照片最高占版心高的 58%（竖幅照片太高时整体缩小）
    static let figureMaxHeightRatio: CGFloat = 0.58
    /// 照片按多大解（最长边，像素）：版心宽 × 0.62 ≈ 70 mm，300 dpi 约 830 px；留够竖幅和相纸的余量
    static let figurePixels: CGFloat = 1600

    /// 同一篇里挨着的两张照片并排（2026-10-22 产品定）：两张相纸一样高、等比缩放（长的那张变窄，不拉伸不硬塞），
    /// 加起来占满版心宽，中间空这么多（相纸带一点歪，留够不碰到）
    static let pairGap: CGFloat = 14
    /// 并排时每张至少占版心宽的两成：竖幅配横幅（约 29%）、手机截图配横幅（约 23%）都能并排；
    /// 全景配手机截图这种（约 12%），等比下来一张会窄得看不清 —— 那就不并排，各自单独放
    static let pairMinWidthRatio: CGFloat = 0.2
    /// 页底剩的地方放不下一排照片时，整排等比缩小塞进去，最多缩到原尺寸的六成；再小就挪到下一页
    static let figureMinScale: CGFloat = 0.6

    // MARK: 纸墨（固定，不跟 App 主题 —— 印出来像书，也不费墨）

    static let ink = Color(hex: "#2A2420")
    static let inkSecondary = Color(hex: "#6F665E")
    static let inkTertiary = Color(hex: "#A1988E")
    static let hairline = Color(hex: "#D8D0C4")
}
