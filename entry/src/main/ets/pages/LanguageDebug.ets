/**
 * 多语言调试页（10_BUILD_MANUAL.md 1.2 验收用，临时脚手架）。
 *
 * - 七种语言列表（自称显示，永远不翻译），点击切换，当场生效：
 *   `setLanguage` 会设 App 首选语言（`$r` 立即按新语言解析）并替换
 *   AppStorage `appLanguage` —— 本页挂 `@StorageProp`，key 一变整页重渲染
 * - 资源文字样例 + 日期格式样例全部当场变（R-LANG-03/08 的验收）
 * - **没有「跟随系统」这一项**（R-LANG-02，列表只有七种）
 * - 标签用英文调试文案（6.1 真实设置页上线后本页删除，不进产品文案体系）
 */
import { AppTheme } from '../theme/AppTheme';
import { BambooTheme } from '../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../theme/ThemeManager';
import {
  LanguageManager,
  LanguageOption,
  STORAGE_KEY_APP_LANGUAGE,
  STORAGE_KEY_LANGUAGE_MANAGER
} from '../services/LanguageManager';
import {
  yearMonthKey,
  dayAndWeekday,
  shortDate,
  weekdayString
} from '../services/AppDateFormatters';

@Entry
@Component
struct LanguageDebug {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'en';
  private languageManager: LanguageManager | undefined = undefined;

  aboutToAppear(): void {
    const mgr = AppStorage.get<LanguageManager>(STORAGE_KEY_LANGUAGE_MANAGER);
    if (mgr !== undefined) {
      this.languageManager = mgr;
    }
  }

  private switchLanguage(id: string): void {
    if (this.languageManager !== undefined) {
      this.languageManager.setLanguage(id);
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

  build() {
    Scroll() {
      Column() {
        this.debugHeader()
        this.languageList()
        this.stringSamples()
        this.dateSamples()
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .backgroundColor(this.theme.background)
    .scrollBar(BarState.Off)
  }

  /** 头部：当前语言 id */
  @Builder
  private debugHeader() {
    Column({ space: 4 }) {
      Text('LanguageDebug')
        .fontSize(this.theme.titleFont.size)
        .fontFamily(this.theme.titleFont.family)
        .fontColor(this.theme.textPrimary)
      Text(`appLanguage: ${this.appLanguage}`)
        .fontSize(this.theme.captionFont.size)
        .fontColor(this.theme.textTertiary)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  /** 七种语言（顺序固定 R-LANG-01；没有「跟随系统」） */
  @Builder
  private languageList() {
    Column() {
      this.sectionTitle('LANGUAGES')
      Column() {
        ForEach(LanguageManager.supportedOptions(), (option: LanguageOption) => {
          Row({ space: 12 }) {
            Text(option.id)
              .fontSize(this.theme.captionFont.size)
              .fontColor(this.theme.textTertiary)
              .width(64)
            Text(option.nameResource)
              .fontSize(this.theme.bodyFont.size)
              .fontFamily(this.theme.bodyFont.family)
              .fontColor(this.appLanguage === option.id ? this.theme.accent : this.theme.textPrimary)
              .layoutWeight(1)
            if (this.appLanguage === option.id) {
              Text('✓')
                .fontSize(this.theme.bodyFont.size)
                .fontColor(this.theme.accent)
            }
          }
          .width('100%')
          .height(44)
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            this.switchLanguage(option.id);
          })
        }, (option: LanguageOption) => option.id)
      }
      .width('100%')
      .backgroundColor(this.theme.cardBackground)
      .borderRadius(12)
      .padding({ top: 4, bottom: 4 })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  /** 资源文字样例：$r 按首选语言解析，切换后重渲染即变（R-LANG-03 验收） */
  @Builder
  private stringSamples() {
    Column() {
      this.sectionTitle('STRINGS ($r)')
      Column({ space: 8 }) {
        Text($r('app.string.s_f6c9fb2f33'))
          .fontSize(this.theme.bodyFont.size)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
        Text($r('app.string.s_09873b1938'))
          .fontSize(this.theme.bodyFont.size)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
        Text($r('app.string.s_e7dca6ac80'))
          .fontSize(this.theme.bodyFont.size)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    }
    .width('100%')
    .backgroundColor(this.theme.cardBackground)
    .borderRadius(12)
    .margin({ top: 12 })
    .padding({ left: 16, right: 16 })
  }

  /** 日期格式样例：全部接受 App 语言，切换当场变（R-LANG-08 验收） */
  @Builder
  private dateSamples() {
    Column() {
      this.sectionTitle('DATES (App language, R-LANG-08)')
      Column({ space: 8 }) {
        Text(dayAndWeekday(new Date(), this.appLanguage))
          .fontSize(this.theme.bodyFont.size)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
        Text(shortDate(new Date(), this.appLanguage))
          .fontSize(this.theme.bodyFont.size)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
        Text(yearMonthKey(new Date(), this.appLanguage))
          .fontSize(this.theme.bodyFont.size)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
        Text(weekdayString(new Date(), this.appLanguage))
          .fontSize(this.theme.bodyFont.size)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    }
    .width('100%')
    .backgroundColor(this.theme.cardBackground)
    .borderRadius(12)
    .margin({ top: 12, bottom: 24 })
    .padding({ left: 16, right: 16 })
  }
}
