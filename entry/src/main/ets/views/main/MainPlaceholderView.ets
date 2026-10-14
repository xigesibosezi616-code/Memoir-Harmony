/**
 * 主界面占位（10_BUILD_MANUAL.md 1.5）：空状态 + 调试页入口。
 * 1.6 主框架（Tabs 四页）落地时整个替换，不要往这里堆功能。
 *
 * 默认数据（12 心情 + 4 日记本）在 aboutToAppear 触发 —— 对齐 iOS 在主界面
 * `onAppear` 里做的三件事（`ContentView.swift`）。本组件引导走完才挂载，
 * 天然保证「同意 → 引导 → 写库」的顺序（R-APP-01/07）；
 * 幂等：每次启动重算缺口，只补缺的，失败只记日志下次启动重试。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { DefaultDataService } from '../../data/DefaultData';

@Component
export struct MainPlaceholderView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      DefaultDataService.ensureDefaultData(context)
        .catch((err: Object) => {
          hilog.error(0x0000, 'MainPlaceholder', 'ensureDefaultData failed: %{public}s', JSON.stringify(err));
        });
    }
  }

  build() {
    Column() {
      Blank()

      Column({ space: 12 }) {
        Text($r('app.string.s_09873b1938'))
          .fontSize(this.theme.headingFont.size)
          .fontWeight(this.theme.headingFont.weight)
          .fontFamily(this.theme.headingFont.family)
          .fontColor(this.theme.textPrimary)
        Text($r('app.string.s_e488fa1386'))
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textSecondary)
      }

      Blank()

      // 调试入口（1.1/1.2 的脚手架页，1.6 真实底栏上线后删）
      Row({ space: 12 }) {
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
      .padding({ bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }
}
