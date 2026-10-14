/**
 * 首启引导页（10_BUILD_MANUAL.md 1.5）。对应 iOS `Views/Onboarding/OnboardingView.swift`。
 *
 * 选纸张 → 给笔友起名（可跳过，默认「青鸟」）→「开始书写」进主界面。
 *
 * - 引导只在首启出现一次：`hasCompletedOnboarding` 落盘后不再来。
 *   协议版本更新只重弹同意页、**不重弹引导** —— 两页生命周期不同，别合并。
 * - 纸卡颜色取主题实例的 background / accent：三套主题的这两枚 token
 *   恰好等于 iOS 纸卡写死的六组色值，不重复抄数字，改主题这里自动跟上。
 * - 「开始书写」才落盘（iOS 同款）：笔友名 trim、空恢复「青鸟」、
 *   切主题、置完成标记。中途杀进程什么都没写，下次启动从头再来，无脏状态。
 */
import { LengthMetrics } from '@kit.ArkUI';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import {
  STORAGE_KEY_THEME,
  STORAGE_KEY_THEME_MANAGER,
  ThemeManager
} from '../../theme/ThemeManager';
import {
  AppPrefs,
  PREF_KEY_HAS_COMPLETED_ONBOARDING,
  PREF_KEY_PEN_PAL_NAME,
  STORAGE_KEY_HAS_COMPLETED_ONBOARDING
} from '../../services/AppPrefs';

/** 笔友名兜底（iOS `penPalName` 默认值「青鸟」） */
const DEFAULT_PEN_PAL_NAME = '青鸟';

@Component
export struct OnboardingView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  /** 选中态从「素笺」起（iOS 同款 @State 初值；引导是首启，本就没有已存主题可预选） */
  @State selectedTheme: string = 'bamboo';
  @State penPalName: string = DEFAULT_PEN_PAL_NAME;
  /** 走完引导写 true：偏好落盘 + AppStorage 镜像，Index 观察镜像切走本页 */
  @StorageLink(STORAGE_KEY_HAS_COMPLETED_ONBOARDING) hasCompleted: boolean = false;
  /** 三张纸卡对应的主题实例（aboutToAppear 算一次，build 里不再 new） */
  @State optionThemes: AppTheme[] = [];

  private themeManager: ThemeManager | undefined = undefined;

  aboutToAppear(): void {
    this.penPalName = AppPrefs.getString(PREF_KEY_PEN_PAL_NAME, DEFAULT_PEN_PAL_NAME);
    this.optionThemes = [
      ThemeManager.themeFor('bamboo'),
      ThemeManager.themeFor('leather'),
      ThemeManager.themeFor('kent')
    ];
    const mgr = AppStorage.get<ThemeManager>(STORAGE_KEY_THEME_MANAGER);
    if (mgr !== undefined) {
      this.themeManager = mgr;
    }
  }

  /** 「开始书写」：trim、空恢复默认、切主题、落盘完成标记（iOS CTA 同款顺序） */
  private completeOnboarding(): void {
    const trimmed: string = this.penPalName.trim();
    const finalName: string = trimmed.length === 0 ? DEFAULT_PEN_PAL_NAME : trimmed;
    AppPrefs.putString(PREF_KEY_PEN_PAL_NAME, finalName);
    if (this.themeManager !== undefined) {
      this.themeManager.setTheme(this.selectedTheme);
    }
    AppPrefs.putBool(PREF_KEY_HAS_COMPLETED_ONBOARDING, true);
    // StorageLink 镜像放最后：一写 Index 就切走本页，前面的落盘必须先完成
    this.hasCompleted = true;
  }

  private selectTheme(id: string): void {
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.selectedTheme = id;
    });
  }

  build() {
    Column() {
      Blank()

      // 品牌
      Column({ space: 12 }) {
        Text($r('app.string.s_5d701678ab'))
          .fontSize(this.theme.titleFont.size)
          .fontWeight(this.theme.titleFont.weight)
          .fontFamily(this.theme.titleFont.family)
          .fontColor(this.theme.textPrimary)
        Text($r('app.string.s_e775910242'))
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textSecondary)
          .lineSpacing(LengthMetrics.vp(this.theme.bodyLineSpacing))
      }

      Blank().height(48)

      // 选纸张
      Column({ space: 12 }) {
        Text($r('app.string.s_61af9a4751'))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textTertiary)
          .letterSpacing(this.theme.letterSpacingWide)
        Row({ space: 16 }) {
          ForEach(this.optionThemes, (optionTheme: AppTheme) => {
            this.themeOptionBuilder(optionTheme)
          }, (optionTheme: AppTheme) => optionTheme.id)
        }
      }

      Blank().height(40)

      // 笔友起名（可跳过 → 默认「青鸟」）
      Column({ space: 10 }) {
        Text($r('app.string.s_c36573f3f7'))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textTertiary)
          .letterSpacing(this.theme.letterSpacingWide)

        TextInput({
          text: this.penPalName,
          placeholder: $r('app.string.s_db0abd6cdb')
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
          .margin({ left: 60, right: 60 })
          .enterKeyType(EnterKeyType.Done)
          .onChange((value: string) => {
            this.penPalName = value;
          })
          .onSubmit(() => {
            // 回车收起键盘（iOS `submitLabel(.done)` + `onSubmit` 收焦点）
            this.getUIContext().getFocusController().clearFocus();
          })

        Text($r('app.string.s_36179dc44d'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textTertiary)
      }

      Blank()

      // CTA
      Text($r('app.string.s_80a37cf380'))
        .fontSize(this.theme.headingFont.size)
        .fontWeight(this.theme.headingFont.weight)
        .fontFamily(this.theme.headingFont.family)
        .fontColor(this.theme.cardBackground)
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ top: 16, bottom: 16 })
        .backgroundColor(this.theme.accent)
        .borderRadius(12)
        .margin({ left: 40, right: 40, bottom: 48 })
        .onClick(() => {
          this.completeOnboarding();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }

  /** 一张纸卡：预览底色 + 「文」字 + 名称 + 选中描边（iOS `themeOption`） */
  @Builder
  private themeOptionBuilder(optionTheme: AppTheme) {
    Column({ space: 8 }) {
      Column() {
        Text($r('app.string.s_1d56b27a5e'))
          .fontSize(24)
          .fontWeight(FontWeight.Lighter)
          .fontFamily('serif')
          .fontColor(optionTheme.accent)
      }
      .width(72)
      .height(96)
      .borderRadius(10)
      .backgroundColor(optionTheme.background)
      .justifyContent(FlexAlign.Center)
      .border({
        width: this.selectedTheme === optionTheme.id ? 2 : 0.5,
        color: this.selectedTheme === optionTheme.id ? this.theme.accent : this.theme.border
      })

      Text(optionTheme.nameRes)
        .fontSize(this.theme.labelFont.size)
        .fontWeight(this.theme.labelFont.weight)
        .fontFamily(this.theme.labelFont.family)
        .fontColor(this.selectedTheme === optionTheme.id ? this.theme.textPrimary : this.theme.textTertiary)
    }
    .onClick(() => {
      this.selectTheme(optionTheme.id);
    })
  }
}
