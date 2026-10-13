import SwiftUI

/// 一个主题背后的那张纸 —— 名字、副标题、介绍正文、史料出处。
///
/// 主题选择页从「选一个配色」改成「挑一种纸」：点主题不再立刻生效，先弹出介绍，
/// 用户每次换主题都会读到一段真实的纸史。**这是产品的文化表达，不是装饰性文案**，
/// 所以正文按阅读体验排版（行距放宽），不要当成 UI 提示文字处理。
///
/// ## 两个约定
///
/// 1. **`id` 是存进 UserDefaults 的值**，与 `ThemeManager.currentThemeID`、
///    `AppIconOption.themeID` 是同一套。2026-09-16 随显示名一起改成了
///    `bamboo` / `leather` / `kent`（内测期，只有两台设备装着旧值）。
///    旧值由 `ThemeManager.canonicalThemeID` 一次性归一。
///    **今后再改 id 就必须同样配一次迁移** —— 直接改会让用户的主题掉回默认。
/// 2. 所有文案必须是 `LocalizedStringKey` 而不是 `String`：`Text(String)` 不查本地化表，
///    写成 `String` 的话这一页在任何语言下都显示中文（见 `Memoir/CLAUDE.md` 多语言第 6 条）。
///
/// ## 外语版本不是直译
///
/// 「杀青」直译成 kill green 是灾难；肯特纸对英语读者更是不存在的词
/// （他们叫 drawing paper 或 Bristol board）—— 英文版把「这名字其实是日本人起的」
/// 当主线来讲，日文版则反过来点出「ケント」这个叫法是日本自己造的。
/// 各语言按各自语境重写过，改文案时请连带重看 catalog 里的七种译文，不要只改中文。
struct ThemePaper: Identifiable, Sendable {
    /// 与 `ThemeManager.currentThemeID` 同一套值，**不随显示名变化**
    let id: String
    let name: LocalizedStringKey
    /// 列表页副标题，占原来「免费」的位置。允许两行，**不要截断成省略号**
    let subtitle: LocalizedStringKey
    /// 介绍弹窗的正文
    let story: LocalizedStringKey
    /// 史料出处，弹窗里默认收起
    let source: LocalizedStringKey

    /// 这套主题对应的 App 图标
    var icon: AppIconOption { AppIconOption.forTheme(id) }

    static let all: [ThemePaper] = [
        ThemePaper(
            id: "bamboo",
            name: "素笺",
            subtitle: "斩竹漂塘，纸上还留着竹的青气",
            story: "唐人斩竹入塘，沤足百日褪去青皮，这道工序叫「杀青」。竹料成纸，色微黄而质绵韧——宋人用它印书，明人用它写信。《天工开物》记下的五道工序，至今仍在用。",
            source: "唐·李肇《唐国史补》：「纸则有韶之竹笺」；明·宋应星《天工开物·杀青》载斩竹漂塘、煮篁足火、荡料入帘、覆帘压纸、透火焙干五道工序。四川夹江竹纸与宣纸并称，张大千誉为「国之二宝」。"
        ),
        ThemePaper(
            id: "leather",
            name: "皮革",
            subtitle: "摩洛哥山羊皮，烫金最衬的底子",
            story: "十六世纪起，欧洲最好的书用摩洛哥山羊皮装帧，细密的粒面是烫金最衬的底子。十九世纪的英国书房里，小牛皮包住书脊，金箔压出书名——一本书先是器物，然后才是读物。",
            source: "摩洛哥革（morocco）为山羊皮，细粒面，最宜显金；小牛革（calf）光滑少纹，为十七至十九世纪英国精装主流。"
        ),
        ThemePaper(
            id: "kent",
            name: "肯特",
            subtitle: "断、舍、离，现代极简主义无即为有",
            story: "十九世纪英国肯特郡的手漉纸，纯白、硬挺、平滑，橡皮擦过不起毛，为制图而生。有趣的是「肯特纸」这名字其实是日本人取的，英国本地并无此称。",
            source: "日本印刷产业连合会印刷用语集、武藏野美术大学造形档案；「肯特纸为日本所命名」一说见《特种制纸五十年史》。"
        ),
    ]
}

/// 介绍弹窗里用户做的选择。关联值是目标主题的 id
enum ThemeSwitchChoice {
    /// 一并更换图标 —— 回到「跟随主题」，图标跟着新主题走
    case themeAndIcon(String)
    /// 仅更换主题 —— 图标保持不动
    case themeOnly(String)
}
