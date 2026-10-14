/**
 * 记录 tab 占位页（10_BUILD_MANUAL.md 1.5 起为主界面占位，1.6 起挂进 MainTabsView
 * 的记录 tab；2.1/2.2 落真实记录页后整个替换，不要往这里堆功能）。
 *
 * 默认数据（12 心情 + 4 日记本）在 aboutToAppear 触发 —— 对齐 iOS 在主界面
 * `onAppear` 里做的三件事（`ContentView.swift`）。本组件引导走完才挂载，
 * 天然保证「同意 → 引导 → 写库」的顺序（R-APP-01/07）；
 * 幂等：每次启动重算缺口，只补缺的，失败只记日志下次启动重试。
 *
 * 调试入口（英文调试文案，不进翻译索引）：1.6 增 ToastDebug 触发全局 toast，
 * 验收「调试入口触发错误 → toast 出现 / 消失」；Theme/Language 调试页 6.x 删。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { DefaultDataService } from '../../data/DefaultData';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { ErrorToastKind } from '../../environment/ErrorPresenter';
import { STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';

@Component
export struct MainPlaceholderView {
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

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

      // 调试入口（脚手架；真实页面卡片上线后删）
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
        Button('ToastDebug')
          .fontSize(this.theme.bodyFont.size)
          .fontColor(this.theme.accent)
          .backgroundColor(this.theme.accentBackground)
          .borderRadius(10)
          .onClick((): void => {
            // 触发一条 error toast（现成文案「同步异常」），验收 1.6 顶部提示链路
            const context = this.getUIContext().getHostContext();
            if (context !== undefined) {
              const message: string =
                context.resourceManager.getStringSync($r('app.string.s_d60bcc29e2').id);
              this.env.errors.present(message, ErrorToastKind.Error, 3000);
            }
          })
      }
      .padding({ bottom: 24 })
    }
    .constraintSize({ maxWidth: 840 })
    .width('100%')
    .height('100%')
    .padding({ bottom: this.safeAreaBottomVp + 96 })
    .backgroundColor(this.theme.background)
  }
}
