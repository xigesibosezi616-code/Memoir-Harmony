/**
 * 主题 token 调试页（10_BUILD_MANUAL.md 1.1 验收用，临时脚手架）。
 *
 * - 一页列全 15 个颜色 token、5 档字体 token、行距 / 宽字距、邮筒插画、
 *   系统弹窗样例 —— 三套主题逐个切，当场变（验收①②）
 * - 切到皮革（深色主题）后弹 AlertDialog：遮罩 / 按钮 / 文字全深（验收③，
 *   状态栏明暗同样由应用级 COLOR_MODE_DARK 驱动，需真机观察）
 * - 页面自身不写死色值，全部从当前主题 token 取；标签用英文调试文案
 *   （6.2 的真实主题选择器上线后本页删除，不进产品文案体系）
 */
import { LengthMetrics } from '@kit.ArkUI';
import { AppTheme } from '../theme/AppTheme';
import { BambooTheme } from '../theme/BambooTheme';
import {
  ThemeManager,
  STORAGE_KEY_THEME,
  STORAGE_KEY_THEME_ID,
  STORAGE_KEY_THEME_MANAGER
} from '../theme/ThemeManager';
import { STORAGE_KEY_SAFE_AREA_TOP_VP } from '../services/ImmersiveChrome';

/** ResourceColor → 调试用十六进制展示（主题色值都是 0xAARRGGBB 数字，typeof 收窄） */
function colorToHex(color: ResourceColor): string {
  if (typeof color === 'number') {
    return '#' + color.toString(16).toUpperCase();
  }
  if (typeof color === 'string') {
    return color;
  }
  return 'resource';
}

/** 单个颜色 token 行：色块 + token 名 + 色值 */
@Component
struct ColorTokenRow {
  @Prop label: string = '';
  @Prop color: ResourceColor = Color.Transparent;
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    Row({ space: 12 }) {
      Row()
        .width(36)
        .height(36)
        .borderRadius(8)
        .backgroundColor(this.color)
        .border({ width: 1, color: this.theme.border })
      Text(this.label)
        .fontSize(this.theme.bodyFont.size)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      Text(colorToHex(this.color))
        .fontSize(this.theme.captionFont.size)
        .fontColor(this.theme.textTertiary)
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
  }
}

/** 单个字体 token 行：token 名 + 字样 + 字号（fontValue 避开内置属性名 size） */
@Component
struct FontSampleRow {
  @Prop label: string = '';
  @Prop fontValue: number = 14;
  @Prop family: string = '';
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    Row({ space: 12 }) {
      Text(this.label)
        .fontSize(this.theme.captionFont.size)
        .fontColor(this.theme.textTertiary)
        .width(104)
      Text('Aa Bb 123')
        .fontSize(this.fontValue)
        .fontFamily(this.family)
        .fontColor(this.theme.textPrimary)
        .layoutWeight(1)
      Text(`${this.fontValue}fp`)
        .fontSize(this.theme.captionFont.size)
        .fontColor(this.theme.textTertiary)
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
  }
}

@Entry
@Component
struct ThemeDebug {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_THEME_ID) themeId: string = 'bamboo';
  /** 沉浸式状态栏避让（ImmersiveChrome 发布，全形态机型动态更新） */
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  private themeManager: ThemeManager | undefined = undefined;

  aboutToAppear(): void {
    const mgr = AppStorage.get<ThemeManager>(STORAGE_KEY_THEME_MANAGER);
    if (mgr !== undefined) {
      this.themeManager = mgr;
    }
  }

  private isCurrent(id: string): boolean {
    return ThemeManager.canonicalThemeId(id) === this.themeId;
  }

  private switchTheme(id: string): void {
    if (this.themeManager !== undefined) {
      this.themeManager.setTheme(id);
    }
  }

  /** 小节标题（英文调试文案） */
  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .fontSize(this.theme.captionFont.size)
      .fontColor(this.theme.textSecondary)
      .letterSpacing(this.theme.letterSpacingWide)
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 8 })
  }

  /** 主题切换按钮：当前主题描边强调 */
  @Builder
  private themeButton(id: string) {
    Button(ThemeManager.themeFor(id).nameRes)
      .fontSize(this.theme.bodyFont.size)
      .fontColor(this.isCurrent(id) ? this.theme.accent : this.theme.textSecondary)
      .backgroundColor(this.theme.surfaceBackground)
      .border({
        width: this.isCurrent(id) ? 2 : 1,
        color: this.isCurrent(id) ? this.theme.accent : this.theme.border
      })
      .borderRadius(10)
      .layoutWeight(1)
      .onClick(() => {
        this.switchTheme(id);
      })
  }

  build() {
    Scroll() {
      Column() {
        // ---- 头部：当前主题 id 与明暗模式 ----
        Column({ space: 4 }) {
          Text('ThemeDebug')
            .fontSize(this.theme.titleFont.size)
            .fontFamily(this.theme.titleFont.family)
            .fontColor(this.theme.textPrimary)
        Text(`id: ${this.themeId} · colorMode: ${this.theme.colorMode}`)
          .fontSize(this.theme.captionFont.size)
          .fontColor(this.theme.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      // 状态栏避让：沉浸式下内容从状态栏下沿再留 12（官方避让规范，全形态机型）
      .padding({
        left: 16,
        right: 16,
        top: this.safeAreaTopVp + 12,
        bottom: 12
      })

        // ---- 三套主题切换（验收：切换当场变，不重启）----
        Row({ space: 8 }) {
          this.themeButton('bamboo')
          this.themeButton('leather')
          this.themeButton('kent')
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        // ---- 颜色 token（15 个全量列出）----
        this.sectionTitle('COLORS')
        Column() {
          ColorTokenRow({ label: 'background', color: this.theme.background })
          ColorTokenRow({ label: 'cardBackground', color: this.theme.cardBackground })
          ColorTokenRow({ label: 'surfaceBackground', color: this.theme.surfaceBackground })
          ColorTokenRow({ label: 'sidebarBackground', color: this.theme.sidebarBackground })
          ColorTokenRow({ label: 'textPrimary', color: this.theme.textPrimary })
          ColorTokenRow({ label: 'textSecondary', color: this.theme.textSecondary })
          ColorTokenRow({ label: 'textTertiary', color: this.theme.textTertiary })
          ColorTokenRow({ label: 'border', color: this.theme.border })
          ColorTokenRow({ label: 'borderAccent', color: this.theme.borderAccent })
          ColorTokenRow({ label: 'accent', color: this.theme.accent })
          ColorTokenRow({ label: 'accentBackground', color: this.theme.accentBackground })
          ColorTokenRow({ label: 'moodBackground', color: this.theme.moodBackground })
          ColorTokenRow({ label: 'moodBorder', color: this.theme.moodBorder })
          ColorTokenRow({ label: 'moodText', color: this.theme.moodText })
          ColorTokenRow({ label: 'destructive', color: this.theme.destructive })
        }
        .width('100%')
        .backgroundColor(this.theme.cardBackground)
        .borderRadius(12)
        .margin({ left: 16, right: 16 })
        .padding({ top: 4, bottom: 4 })

        // ---- 字体 token（5 档 + 行距 + 宽字距）----
        this.sectionTitle('TYPOGRAPHY')
        Column() {
          FontSampleRow({ label: 'titleFont', fontValue: this.theme.titleFont.size, family: this.theme.titleFont.family })
          FontSampleRow({ label: 'headingFont', fontValue: this.theme.headingFont.size, family: this.theme.headingFont.family })
          FontSampleRow({ label: 'bodyFont', fontValue: this.theme.bodyFont.size, family: this.theme.bodyFont.family })
          FontSampleRow({ label: 'captionFont', fontValue: this.theme.captionFont.size, family: this.theme.captionFont.family })
          FontSampleRow({ label: 'labelFont', fontValue: this.theme.labelFont.size, family: this.theme.labelFont.family })
          Row({ space: 12 }) {
            Text('bodyLineSpacing')
              .fontSize(this.theme.captionFont.size)
              .fontColor(this.theme.textTertiary)
              .width(104)
            Text('Line one\nLine two\nLine three')
              .fontSize(this.theme.bodyFont.size)
              .fontFamily(this.theme.bodyFont.family)
              .lineSpacing(LengthMetrics.vp(this.theme.bodyLineSpacing))
              .fontColor(this.theme.textPrimary)
              .layoutWeight(1)
            Text(`${this.theme.bodyLineSpacing}vp`)
              .fontSize(this.theme.captionFont.size)
              .fontColor(this.theme.textTertiary)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          Row({ space: 12 }) {
            Text('letterSpacingWide')
              .fontSize(this.theme.captionFont.size)
              .fontColor(this.theme.textTertiary)
              .width(104)
            Text('A B C A B C A B C')
              .fontSize(this.theme.bodyFont.size)
              .fontFamily(this.theme.bodyFont.family)
              .letterSpacing(this.theme.letterSpacingWide)
              .fontColor(this.theme.textPrimary)
              .layoutWeight(1)
            Text(`${this.theme.letterSpacingWide}fp`)
              .fontSize(this.theme.captionFont.size)
              .fontColor(this.theme.textTertiary)
          }
          .width('100%')
          .height(44)
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .backgroundColor(this.theme.cardBackground)
        .borderRadius(12)
        .margin({ left: 16, right: 16 })
        .padding({ top: 4, bottom: 4 })

        // ---- 系统联动：应用级明暗驱动的系统弹窗 + 必配插画 ----
        this.sectionTitle('SYSTEM')
        Column() {
          Row({ space: 12 }) {
            Button('Show system dialog')
              .fontSize(this.theme.bodyFont.size)
              .fontColor(this.theme.accent)
              .backgroundColor(this.theme.accentBackground)
              .borderRadius(10)
              .layoutWeight(1)
              .onClick(() => {
                // 皮革（深色主题）下遮罩 / 标题 / 按钮应全深（R-THEME-03 验收）
                this.getUIContext().showAlertDialog({
                  title: 'Sample dialog',
                  message: 'Dimming, title and buttons follow the app color mode.',
                  confirm: {
                    value: 'OK',
                    action: () => {
                    }
                  }
                });
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })

          Column({ space: 8 }) {
            Image(this.theme.mailboxImage)
              .height(120)
              .objectFit(ImageFit.Contain)
            Text('mailboxImage')
              .fontSize(this.theme.captionFont.size)
              .fontColor(this.theme.textTertiary)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 16 })
        }
        .width('100%')
        .backgroundColor(this.theme.cardBackground)
        .borderRadius(12)
        .margin({ left: 16, right: 16 })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .backgroundColor(this.theme.background)
    .scrollBar(BarState.Off)
  }
}
