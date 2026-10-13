/**
 * 首页占位（10_BUILD_MANUAL.md 1.1）：只放应用名 + 主题调试页入口。
 * 真实首页（信箱 / 日记流）在 1.6 主框架卡片落地。
 */
import { AppTheme } from '../theme/AppTheme';
import { BambooTheme } from '../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../theme/ThemeManager';

@Entry
@Component
struct Index {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    Column({ space: 24 }) {
      Text($r('app.string.app_name'))
        .fontSize(this.theme.titleFont.size)
        .fontFamily(this.theme.titleFont.family)
        .fontColor(this.theme.textPrimary)
      Button('ThemeDebug')
        .fontSize(this.theme.bodyFont.size)
        .fontColor(this.theme.accent)
        .backgroundColor(this.theme.accentBackground)
        .borderRadius(10)
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/ThemeDebug' });
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.theme.background)
  }
}
