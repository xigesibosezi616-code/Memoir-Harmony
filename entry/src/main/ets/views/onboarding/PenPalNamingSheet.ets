/**
 * 老用户补起名（对应 iOS `PenPalNamingSheet.swift`）。
 *
 * 首启时起名还能跳过（2026-10-24 之前），那时没起名的人现在笔友还没有名字 ——
 * 打开 App 时弹这一页请他起一次，起好才能关（Index 里按
 * `PenPalName.needsNaming` 挂这层）。新用户在首启页（OnboardingView）
 * 就必须起名，走不到这里。
 *
 * - iOS 是 medium 高度的 sheet + `interactiveDismissDisabled`；这里做成
 *   底部对齐的圆角面板 + 全屏遮罩，遮罩不响应点击 = 关不掉，起好名字
 *   （镜像写进 AppStorage）这层才随 Index 的条件摘除
 * - 「好了」：没起好（空 / 全空白 / 还是「青鸟」）置灰点不了（iOS 同款）
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import {
  AppPrefs,
  PREF_KEY_PEN_PAL_NAME,
  STORAGE_KEY_PEN_PAL_NAME
} from '../../services/AppPrefs';
import {
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP
} from '../../services/ImmersiveChrome';
import { PenPalName } from '../../models/PenPalName';

@Component
export struct PenPalNamingSheet {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  /** 正在起的名字。不直接绑存储：起好才写 */
  @State private draft: string = '';

  build() {
    Column() {
      // 全屏遮罩：把底下的主界面压暗；不挂 onClick = 点不动，关不掉（iOS interactiveDismissDisabled）
      Column()
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#66000000')

      // 面板（iOS presentationDetents(.medium) 的观感）
      Column({ space: 18 }) {
        Text($r('app.string.s_c36573f3f7'))
          .fontSize(this.theme.headingFont.size)
          .fontWeight(this.theme.headingFont.weight)
          .fontFamily(this.theme.headingFont.family)
          .fontColor(this.theme.textPrimary)

        TextInput({
          text: this.draft,
          placeholder: $r('app.string.s_960e2f7361')
        })
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24, top: 12, bottom: 12 })
          .backgroundColor(this.theme.cardBackground)
          .borderRadius(10)
          .border({ width: 0.5, color: this.theme.border })
          .margin({ left: 40, right: 40 })
          .maxLength(PenPalName.MAX_LENGTH)
          .defaultFocus(true)
          .enterKeyType(EnterKeyType.Done)
          .onChange((value: string) => {
            this.draft = PenPalName.truncated(value);
          })
          .onSubmit((): void => {
            // 回车收起键盘再试存（iOS onSubmit(save) 同款）
            this.getUIContext().getFocusController().clearFocus();
            this.save();
          })

        Text($r('app.string.s_14f2f7ca94'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textTertiary)
          .textAlign(TextAlign.Center)
          .padding({ left: 32, right: 32 })

        // 「好了」：没起好置灰点不了
        Text($r('app.string.s_fac14ac621'))
          .fontSize(this.theme.headingFont.size)
          .fontWeight(this.theme.headingFont.weight)
          .fontFamily(this.theme.headingFont.family)
          .fontColor(this.theme.cardBackground)
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ top: 14, bottom: 14 })
          .backgroundColor(this.theme.accent)
          .borderRadius(12)
          .opacity(PenPalName.needsNaming(this.draft) ? 0.4 : 1)
          .margin({ left: 40, right: 40, top: 6 })
          .enabled(!PenPalName.needsNaming(this.draft))
          .onClick((): void => {
            this.save();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 28, bottom: this.safeAreaBottomVp + 28 })
      .backgroundColor(this.theme.background)
      .borderRadius({ topLeft: 24, topRight: 24 })
    }
    .width('100%')
    .height('100%')
  }

  /** 存偏好 + 写 AppStorage 镜像：`needsNaming` 变 false，Index 那层的条件随之把这页摘掉 */
  private save(): void {
    const name = PenPalName.normalized(this.draft);
    if (PenPalName.needsNaming(name)) {
      return;
    }
    AppPrefs.putString(PREF_KEY_PEN_PAL_NAME, name);
    AppStorage.setOrCreate(STORAGE_KEY_PEN_PAL_NAME, name);
  }
}
