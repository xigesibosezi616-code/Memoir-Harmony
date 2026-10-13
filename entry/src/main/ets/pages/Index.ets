/**
 * 首页占位（10_BUILD_MANUAL.md 1.1 / 1.2）：应用名 + 主题 / 语言调试页入口。
 * 真实首页（信箱 / 日记流）在 1.6 主框架卡片落地。
 *
 * `@StorageProp('appLanguage')`：语言切换时 key 整体替换触发重渲染，
 * 页面上的 `$r` 重新按新首选语言解析（R-LANG-03 当场生效）。
 */
import { AppTheme } from '../theme/AppTheme';
import { BambooTheme } from '../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../services/LanguageManager';

@Entry
@Component
struct Index {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'en';

  build() {
    Column({ space: 24 }) {
      Text($r('app.string.app_name'))
        .fontSize(this.theme.titleFont.size)
        .fontFamily(this.theme.titleFont.family)
        .fontColor(this.theme.textPrimary)
      Text($r('app.string.s_f6c9fb2f33'))
        .fontSize(this.theme.bodyFont.size)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textSecondary)
      Button('ThemeDebug')
        .fontSize(this.theme.bodyFont.size)
        .fontColor(this.theme.accent)
        .backgroundColor(this.theme.accentBackground)
        .borderRadius(10)
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/ThemeDebug' });
        })
      Button('LanguageDebug')
        .fontSize(this.theme.bodyFont.size)
        .fontColor(this.theme.accent)
        .backgroundColor(this.theme.accentBackground)
        .borderRadius(10)
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/LanguageDebug' });
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.theme.background)
  }
}
