/**
 * 写日记页按返回时的确认弹窗（10_BUILD_MANUAL.md 2.1，R-ENTRY-02/03）。
 * 对应 iOS `Views/Compose/DraftExitDialog.swift`。
 *
 * - 官方 @CustomDialog 容器（CustomDialogController：模态遮罩 / 弹出动画，
 *   autoCancel 点遮罩 = 取消，回到编辑——返回键难免误触，不该逼用户在
 *   「丢弃」和「保存」之间二选一）
 * - 沉浸光感：Thin 毛玻璃 + 主题卡色半透明叠色玻璃卡（与主页磨砂玻璃片
 *   同一套材质语言）
 * - 按钮颜色由主题 token 决定——系统 AlertDialog 做不出「浅色次要动作 +
 *   主题色主要动作」的分量差别，接不上三套主题
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';

@CustomDialog
export struct DraftExitDialog {
  controller?: CustomDialogController;
  onDiscard: () => void = (): void => {};
  onSave: () => void = (): void => {};
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    Column({ space: 22 }) {
      Column({ space: 8 }) {
        Text($r('app.string.s_654040bb31'))
          .fontSize(this.theme.headingFont.size)
          .fontWeight(this.theme.headingFont.weight)
          .fontFamily(this.theme.headingFont.family)
          .fontColor(this.theme.textPrimary)
        Text($r('app.string.s_4306623202'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textTertiary)
          .textAlign(TextAlign.Center)
      }
      .alignItems(HorizontalAlign.Center)

      Row({ space: 12 }) {
        // 次要动作：浅色，不抢视线
        Button({ stateEffect: true }) {
          Text($r('app.string.s_95a2fe4ab7'))
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.theme.textSecondary)
        }
        .layoutWeight(1)
        .padding({ top: 13, bottom: 13 })
        .backgroundColor(this.theme.surfaceBackground)
        .borderRadius(12)
        .border({ width: 0.5, color: this.theme.border })
        .onClick((): void => {
          this.controller?.close();
          this.onDiscard();
        })

        // 主要动作：主题对比色
        Button({ stateEffect: true }) {
          Text($r('app.string.s_4cd30ef91e'))
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(this.theme.cardBackground)
        }
        .layoutWeight(1)
        .padding({ top: 13, bottom: 13 })
        .backgroundColor(this.theme.accent)
        .borderRadius(12)
        .onClick((): void => {
          this.controller?.close();
          this.onSave();
        })
      }
    }
    .padding({ left: 22, right: 22, top: 26, bottom: 26 })
    .constraintSize({ maxWidth: 320 })
    .backgroundColor(this.frostedCardColor())
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(20)
  }

  /** 玻璃卡叠色：主题卡色 85% + Thin 毛玻璃（沉浸光感材质语言） */
  private frostedCardColor(): ResourceColor {
    const bg = this.theme.cardBackground;
    if (typeof bg === 'number') {
      return (bg & 0x00FFFFFF) | 0xD9000000;
    }
    return bg;
  }
}
