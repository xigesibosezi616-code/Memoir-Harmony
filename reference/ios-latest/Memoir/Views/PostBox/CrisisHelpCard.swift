import SwiftUI

/// 危险的那封信下面固定附的一张求助卡片（2026-10-16）。
///
/// 服务端判出日记里有危险信号时（`Letter.danger`），信里已经写了求助热线；这张卡片把同一条热线放到信纸外面，
/// **点一下就能拨**，不用从信里抄号码。只写事实、不许诺（不写「一定有人接」「会好起来的」）。
///
/// 热线按**这封信是用哪种语言写给你的**来选，和服务端写进信里的那条一致（`Backend/shared/src/penpals/prompt.ts` 的 `crisisLine`）：
/// - 简体中文：北京心理危机研究与干预中心 010-82951332
/// - 英语：美国 988
/// - 每种语言都附 findahelpline.com（按所在国家列出免费的求助热线）
///
/// 各地热线的补全是待办（`Backend/docs/PROMPT_DESIGN.md`），改之前先问产品。
struct CrisisHelpCard: View {
    /// 这封信是用哪种语言写给你的（`LetterLanguage` 的语言代码）
    let language: String
    let palette: LetterPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("如果你现在很难受")
                    .font(.system(size: 17, weight: .semibold))
                Text("请和身边信任的人说一说，或者联系专业的求助热线。")
                    .font(.system(size: 15))
                    .foregroundStyle(palette.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 10) {
                ForEach(HelpLine.lines(for: language)) { line in
                    row(line)
                }
            }
        }
        .foregroundStyle(palette.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // 一张夹在信后面的小卡片：和信纸同一种纸，比信纸小一圈的阴影
            Rectangle()
                .fill(palette.paper)
                .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
        }
    }

    private func row(_ line: HelpLine) -> some View {
        Link(destination: line.url) {
            HStack(spacing: 12) {
                Image(systemName: line.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    line.title
                        .font(.system(size: 16, weight: .medium))
                    line.detail
                        .font(.system(size: 13))
                        .foregroundStyle(palette.ink.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.ink.opacity(0.3), lineWidth: 0.8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 一条求助渠道
private struct HelpLine: Identifiable {
    let id: String
    let title: Text
    let detail: Text
    let symbol: String
    let url: URL

    static func lines(for language: String) -> [HelpLine] {
        // 每种语言都有：按所在国家查当地的免费热线
        let finder = HelpLine(
            id: "findahelpline",
            title: Text("查找你所在地区的求助热线"),
            detail: Text(verbatim: "findahelpline.com"),
            symbol: "globe",
            url: URL(string: "https://findahelpline.com")!
        )
        switch language {
        case "zh-Hans":
            return [
                HelpLine(
                    id: "beijing",
                    title: Text("拨打 \("010-82951332")"),
                    detail: Text("北京心理危机研究与干预中心 · 24 小时"),
                    symbol: "phone",
                    url: URL(string: "tel:01082951332")!
                ),
                finder,
            ]
        case "en":
            return [
                HelpLine(
                    id: "988",
                    title: Text("拨打 \("988")"),
                    detail: Text("美国 · 988 自杀与危机生命线"),
                    symbol: "phone",
                    url: URL(string: "tel:988")!
                ),
                finder,
            ]
        default:
            return [finder]
        }
    }
}
