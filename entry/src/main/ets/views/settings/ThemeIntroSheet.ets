/**
 * 主题介绍弹窗 —— 点主题后先读一段纸史，再决定换不换（6.2）。
 * 对应 iOS `Views/Settings/ThemeIntroSheet.swift`。
 *
 * 🔴 **整个弹窗用「即将切换过去的那套主题」的配色渲染，不是当前主题。**
 * 用户在按下确认之前就能看到这套主题长什么样，**弹窗本身就是预览**（R-THEME-04）。
 * 所以 `paperTheme` 一律来自 `ThemeManager.themeFor`，不要图省事用当前主题。
 *
 * 弹窗只负责「读」和「选」，**不直接改主题**：选择通过 `onChoose` 抛给调用方，
 * 由调用方先关掉本弹窗、再执行切换（iOS 同款时序，见 ThemePickerView）。
 *
 * 图标段（R-THEME-05）：图标预览（64×64，让用户理解「图标也会跟着变」的关键视觉，
 * 不能省）+ 底部「这套主题也有一张对应的桌面图标。」+ 主按钮「一并更换图标」
 * （目标图标已生效时置灰「图标已是这一套」）+ 次按钮「仅更换主题」。
 * 🔴 次按钮不是「取消」样式 —— 只换主题是正当选择，两个按钮是平等的两条路。
 */
import { LengthMetrics } from '@kit.ArkUI';
import { AppTheme } from '../../theme/AppTheme';
import { STORAGE_KEY_THEME_MANAGER, ThemeManager } from '../../theme/ThemeManager';
import { ThemePaper } from '../../theme/ThemePaper';

@Component
export struct ThemeIntroSheet {
  /** 正在介绍的纸的 id；换纸时重算目标主题配色（@Watch） */
  @Prop @Watch('onPaperIdChange') paperId: string = 'bamboo';
  /** 选择结果：true = 一并更换图标（回跟随），false = 仅更换主题。切换由调用方在弹窗关闭后执行 */
  onChoose: (alsoIcon: boolean) => void = (_alsoIcon: boolean) => {};

  /** 弹窗渲染用的目标主题配色（🔴 不是当前主题，见文件头） */
  @State private paperTheme: AppTheme = ThemeManager.themeFor('bamboo');
  /** 系统当前实际生效的图标是否已经是这套主题的（主按钮置灰判断，R-THEME-05） */
  @State private iconAlreadyMatches: boolean = false;
  /** 出处默认收起 —— 它是给想深究的人看的，不该占掉正文的位置 */
  @State private showSource: boolean = false;

  aboutToAppear(): void {
    this.refreshForPaper();
  }

  /** 换了介绍的纸：重算目标主题配色与图标匹配态（弹窗重开换纸时 aboutToAppear 不一定再跑） */
  onPaperIdChange(): void {
    this.refreshForPaper();
  }

  private refreshForPaper(): void {
    this.paperTheme = ThemeManager.themeFor(this.paperId);
    const manager = AppStorage.get<ThemeManager>(STORAGE_KEY_THEME_MANAGER);
    this.iconAlreadyMatches = manager !== undefined && manager.resolvedAppIconId() === this.paperId;
  }

  /** 正在介绍的那张纸（按 id 从名单里取） */
  private paper(): ThemePaper {
    for (const paper of ThemePaper.all) {
      if (paper.id === this.paperId) {
        return paper;
      }
    }
    return ThemePaper.all[0];
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          Text(this.paper().nameRes)
            .fontSize(this.paperTheme.titleFont.size)
            .fontWeight(this.paperTheme.titleFont.weight)
            .fontFamily(this.paperTheme.titleFont.family)
            .fontColor(this.paperTheme.textPrimary)

          // 图标预览（R-THEME-04/05）：让用户理解「图标也会跟着变」的关键视觉，不能省
          Image(this.paper().iconPreviewRes)
            .width(64)
            .height(64)
            .borderRadius(14)
            .border({ width: 0.5, color: this.paperTheme.border })
            .objectFit(ImageFit.Cover)
            .margin({ top: 20 })

          // 这是给人读的内容，不是提示文字 —— 行距按阅读体验放宽（iOS lineSpacing +4）
          Text(this.paper().storyRes)
            .fontSize(this.paperTheme.bodyFont.size)
            .fontWeight(this.paperTheme.bodyFont.weight)
            .fontFamily(this.paperTheme.bodyFont.family)
            .fontColor(this.paperTheme.textPrimary)
            .lineSpacing(LengthMetrics.vp(this.paperTheme.bodyLineSpacing + 4))
            .margin({ top: 20 })

          this.sourceSection()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 24, right: 24, top: 28, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      this.bottomBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.paperTheme.background)
  }

  // ---- 出处（默认收起） ----

  @Builder
  private sourceSection() {
    Column() {
      Row({ space: 4 }) {
        Text($r('app.string.s_5070487278'))
          .fontSize(this.paperTheme.labelFont.size)
          .fontWeight(this.paperTheme.labelFont.weight)
          .fontFamily(this.paperTheme.labelFont.family)
          .fontColor(this.paperTheme.textTertiary)
        SymbolGlyph(this.showSource ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(9)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.paperTheme.textTertiary])
      }
      .onClick(() => {
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
          this.showSource = !this.showSource;
        });
      })

      if (this.showSource) {
        Text(this.paper().sourceRes)
          .fontSize(this.paperTheme.labelFont.size)
          .fontWeight(this.paperTheme.labelFont.weight)
          .fontFamily(this.paperTheme.labelFont.family)
          .fontColor(this.paperTheme.textTertiary)
          .lineSpacing(LengthMetrics.vp(5))
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 20 })
  }

  // ---- 底部：陈述句 + 两条平等的路（R-THEME-05） ----

  @Builder
  private bottomBar() {
    Column() {
      Divider()
        .color(this.paperTheme.border)
        .strokeWidth(0.5)

      // 陈述句，不是问句
      Text($r('app.string.s_ad1e6b0e58'))
        .fontSize(this.paperTheme.captionFont.size)
        .fontWeight(this.paperTheme.captionFont.weight)
        .fontFamily(this.paperTheme.captionFont.family)
        .fontColor(this.paperTheme.textSecondary)
        .width('100%')
        .margin({ top: 6 })
        .textAlign(TextAlign.Start)

      // 主按钮：一并更换图标（目标图标已生效时置灰，文案跟着换成陈述当前状态）
      Text(this.iconAlreadyMatches ? $r('app.string.s_a0a02d4593') : $r('app.string.s_9f9a88b0c8'))
        .fontSize(this.paperTheme.bodyFont.size)
        .fontWeight(this.paperTheme.bodyFont.weight)
        .fontFamily(this.paperTheme.bodyFont.family)
        .fontColor(this.iconAlreadyMatches ? this.paperTheme.textSecondary : this.paperTheme.background)
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ top: 14, bottom: 14 })
        .backgroundColor(this.iconAlreadyMatches
          ? this.paperTheme.accentBackground : this.paperTheme.accent)
        .borderRadius(12)
        .margin({ top: 10 })
        .enabled(!this.iconAlreadyMatches)
        .onClick(() => {
          this.onChoose(true);
        })

      // 🔴 次按钮不要做成「取消」的样式：只换主题是正当选择，两条路平等
      Text($r('app.string.s_4cad1a999a'))
        .fontSize(this.paperTheme.bodyFont.size)
        .fontWeight(this.paperTheme.bodyFont.weight)
        .fontFamily(this.paperTheme.bodyFont.family)
        .fontColor(this.paperTheme.textPrimary)
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ top: 14, bottom: 14 })
        .backgroundColor(this.paperTheme.cardBackground)
        .borderRadius(12)
        .border({ width: 1, color: this.paperTheme.border })
        .margin({ top: 10 })
        .onClick(() => {
          this.onChoose(false);
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, bottom: 20 })
    .backgroundColor(this.paperTheme.background)
  }
}
