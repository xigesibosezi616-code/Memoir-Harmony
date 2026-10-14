/**
 * 主框架（10_BUILD_MANUAL.md 1.6）：四 tab + 全局 toast 顶部层。
 * 对应 iOS `ContentView.swift` 的 TabView + toast overlay。
 *
 * - 四 tab（记录 / 日记本 / 邮筒 / 设置）使用 ArkUI Tabs 组件，
 *   barPosition: End + barOverlap + systemMaterial（对齐 iOS `.thinMaterial` 底栏）
 * - toast 顶部层：`ErrorToastView` 挂载 / 摘除驱动滑入滑出（0.35s 弹簧）
 * - 一多：断点（sm/md/lg）测宽发布 AppStorage，占位内容限宽 840vp 居中
 * - 记录 tab 本步仍是占位页（2.1/2.2 换真实记录页），其余三 tab 用现有资源名占位
 */
import { curves, uiMaterial } from '@kit.ArkUI';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { tintMatrix } from '../../theme/IconTint';
import { breakpointForWidth, STORAGE_KEY_APP_BREAKPOINT } from '../../theme/Breakpoint';
import { ToastData, STORAGE_KEY_CURRENT_TOAST } from '../../environment/ErrorPresenter';
import { AppEnvironment } from '../../environment/AppEnvironment';
import {
  STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP
} from '../../services/ImmersiveChrome';
import { MainPlaceholderView } from './MainPlaceholderView';
import { ErrorToastView } from './ErrorToastView';

/** tab 定义（0 记录 / 1 日记本 / 2 邮筒 / 3 设置，顺序与 iOS ContentView 一致） */
class TabSpec {
  readonly index: number;
  readonly titleRes: Resource;
  readonly iconRes: Resource;

  constructor(index: number, titleRes: Resource, iconRes: Resource) {
    this.index = index;
    this.titleRes = titleRes;
    this.iconRes = iconRes;
  }
}

@Component
export struct MainTabsView {
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_CURRENT_TOAST) currentToast: ToastData | null = null;
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @State currentTab: number = 0;
  @State containerWidthVp: number = 0;

  private readonly tabs: TabSpec[] = [
    new TabSpec(0, $r('app.string.s_9058a1c2c5'), $r('app.media.tab_notebook')),
    new TabSpec(1, $r('app.string.s_a3b90b392b'), $r('app.media.tab_books')),
    new TabSpec(2, $r('app.string.s_11ab7804df'), $r('app.media.tab_mail')),
    new TabSpec(3, $r('app.string.s_7debf9cb03'), $r('app.media.tab_settings'))
  ];

  private readonly tabsController: TabsController = new TabsController();

  build() {
    Stack() {
      Tabs({
        barPosition: BarPosition.End,
        index: this.currentTab,
        controller: this.tabsController
      }) {
        TabContent() {
          MainPlaceholderView()
        }
        .tabBar(this.tabBarItem(0))

        TabContent() {
          this.tabBody($r('app.string.s_a3b90b392b'))
        }
        .tabBar(this.tabBarItem(1))

        TabContent() {
          this.tabBody($r('app.string.s_11ab7804df'))
        }
        .tabBar(this.tabBarItem(2))

        TabContent() {
          this.tabBody($r('app.string.s_7debf9cb03'))
        }
        .tabBar(this.tabBarItem(3))
      }
      .barOverlap(true)
      .vertical(false)
      .scrollable(false)
      .onChange((index: number): void => {
        this.currentTab = index;
      })
      .systemMaterial(this.tabBarMaterial())
      .clip(false)
      .width('100%')
      .height('100%')
      .margin({ bottom: this.safeAreaBottomVp })

      // toast 顶部层：有提示时挂载（顶部滑入），无提示摘除（滑出）
      if (this.currentToast !== null) {
        Column() {
          ErrorToastView({
            toast: this.currentToast,
            onDismiss: (): void => {
              this.env.errors.dismiss();
            }
          })
        }
        .padding({ left: 16, right: 16, top: this.safeAreaTopVp + 8 })
        .width('100%')
        .transition(
          TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -80 }))
            .animation({ curve: curves.springMotion(0.35) })
        )
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const w: Length = newArea.width;
      this.containerWidthVp = typeof w === 'number' ? w : 0;
      AppStorage.setOrCreate(STORAGE_KEY_APP_BREAKPOINT, breakpointForWidth(this.containerWidthVp));
    })
  }

  /** 非 records tab 的占位正文（标题 + 限宽居中；后续卡片逐个换成真实页面） */
  @Builder
  private tabBody(titleRes: Resource) {
    Column() {
      Text(titleRes)
        .fontSize(this.theme.headingFont.size)
        .fontWeight(this.theme.headingFont.weight)
        .fontFamily(this.theme.headingFont.family)
        .fontColor(this.theme.textSecondary)
    }
    .constraintSize({ maxWidth: 840 })
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** 每个 tab 的图标 + 文字（带主题着色与选中高亮） */
  @Builder
  private tabBarItem(index: number) {
    Column({ space: 2 }) {
      Image(this.tabs[index].iconRes)
        .width(23)
        .height(23)
        .supportSvg2(true)
        .colorFilter(new ColorFilter(tintMatrix(this.iconTint(index))))
      Text(this.tabs[index].titleRes)
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.labelColor(index))
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 14, right: 14, top: 6, bottom: 6 })
    .width('100%')
    .height('100%')
  }

  /** 底栏材质：对齐 iOS `.toolbarBackground(.thinMaterial, for: .tabBar)` */
  private tabBarMaterial(): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THIN });
  }

  private iconTint(index: number): number {
    return index === this.currentTab
      ? this.numberColor(this.theme.accent, 0xFF8B7E6A)
      : this.numberColor(this.theme.textTertiary, 0xFFC8BDA8);
  }

  private labelColor(index: number): ResourceColor {
    return index === this.currentTab ? this.theme.accent : this.theme.textTertiary;
  }

  /** ResourceColor 是数字色值时取数值（三套主题均为数字），否则给主题近似兜底 */
  private numberColor(color: ResourceColor, fallback: number): number {
    return typeof color === 'number' ? color : fallback;
  }
}
