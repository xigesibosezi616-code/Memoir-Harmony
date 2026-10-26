/**
 * 主框架（10_BUILD_MANUAL.md 1.6）：四 tab + 全局 toast 顶部层。
 * 对应 iOS `ContentView.swift` 的 TabView + toast overlay。
 *
 * - 四 tab（记录 / 日记本 / 邮筒 / 设置）用 HDS `HdsTabs`（`@kit.UIDesignKit`）：
 *   barPosition End + barOverlap 悬浮胶囊 + barFloatingStyle
 *   （barBottomMargin 适配安全区、adaptToHandedness 智感握姿跟随交互手、
 *   systemMaterialEffect 沉浸光感材质，对齐官方「沉浸光感/智感握姿」最佳实践）
 * - toast 顶部层：`ErrorToastView` 挂载 / 摘除驱动滑入滑出（0.35s 弹簧）
 * - 一多：断点（sm/md/lg）测宽发布 AppStorage，占位内容限宽 840vp 居中
 * - 记录 tab 本步仍是占位页（2.1/2.2 换真实记录页），其余三 tab 用现有资源名占位
 */
import { curves, window } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { tintMatrix } from '../../theme/IconTint';
import { breakpointForWidth, STORAGE_KEY_APP_BREAKPOINT } from '../../theme/Breakpoint';
import { ToastData, STORAGE_KEY_CURRENT_TOAST } from '../../environment/ErrorPresenter';
import { AppEnvironment } from '../../environment/AppEnvironment';
import {
  STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP,
  STORAGE_KEY_HIDE_TAB_BAR
} from '../../services/ImmersiveChrome';
import { HomeView } from '../home/HomeView';
import { BookshelfView } from '../shelf/BookshelfView';
import { PostBoxTabView } from '../postbox/PostBoxTabView';
import { SettingsTabView } from '../settings/SettingsTabView';
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
  /** 照片全屏查看期间藏浮动 Tab 栏（barOverlap 层在 NavDestination 之上，只有透明度能压它） */
  @StorageProp(STORAGE_KEY_HIDE_TAB_BAR) hideTabBar: boolean = false;
  /** 键盘弹出中（2026-10-21 真机反馈：写日记弹键盘时 dock 栏跟着键盘一起
   * 升到键盘顶上——RESIZE_WITH_CARET 压页时悬浮胶囊贴页底随之抬高。
   * iOS 键盘天然盖住 Tab 栏，这里用 barOpacity 归零对齐该观感；
   * 相机页 barOpacity 0 + 底部拍照钮实测可点，命中安全有先例） */
  @State private keyboardUp: boolean = false;
  /** 主窗口句柄（键盘高度监听用；aboutToDisappear 注销） */
  private mainWindow: window.Window | undefined = undefined;
  @State currentTab: number = 0;
  @State containerWidthVp: number = 0;

  private readonly tabs: TabSpec[] = [
    new TabSpec(0, $r('app.string.s_9058a1c2c5'), $r('app.media.tab_notebook')),
    new TabSpec(1, $r('app.string.s_a3b90b392b'), $r('app.media.tab_books')),
    new TabSpec(2, $r('app.string.s_11ab7804df'), $r('app.media.tab_mail')),
    new TabSpec(3, $r('app.string.s_7debf9cb03'), $r('app.media.tab_settings'))
  ];

  private readonly tabsController: HdsTabsController = new HdsTabsController();

  aboutToAppear(): void {
    // 键盘高度监听（官方 window.on('keyboardHeightChange') 配方，
    // 与 RichFormatToolbar 同款）：键盘弹起 → keyboardUp，Tab 栏透明归位
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      window.getLastWindow(context).then((win: window.Window): void => {
        this.mainWindow = win;
        win.on('keyboardHeightChange', (height: number): void => {
          this.keyboardUp = height > 0;
        });
      }).catch((): void => {
        // 取不到窗口（极端场景）：Tab 栏保持常显，不阻塞功能
      });
    }
  }

  aboutToDisappear(): void {
    if (this.mainWindow !== undefined) {
      this.mainWindow.off('keyboardHeightChange');
      this.mainWindow = undefined;
    }
  }

  build() {
    Stack() {
      HdsTabs({
        barPosition: BarPosition.End,
        index: this.currentTab,
        controller: this.tabsController
      }) {
        TabContent() {
          HomeView()
        }
        .tabBar(this.tabBarItem(0))

        TabContent() {
          BookshelfView()
        }
        .tabBar(this.tabBarItem(1))

        TabContent() {
          PostBoxTabView()
        }
        .tabBar(this.tabBarItem(2))

        TabContent() {
          SettingsTabView()
        }
        .tabBar(this.tabBarItem(3))
      }
      .barOverlap(true)
      .vertical(false)
      .scrollable(false)
      .onChange((index: number): void => {
        this.currentTab = index;
      })
      .clip(false)
      .width('100%')
      .height('100%')
      // 悬浮胶囊样式：安全区离底 + 智感握姿跟随交互手 + 沉浸光感材质
      // （官方「沉浸光感」「智感握姿」最佳实践；内容区按钮拿不到系统材质，见 09 OQ）
      // systemMaterialEffect ADAPTIVE：材质跟随系统策略（透明度/强度按用户手机设置走）；
      // gradientMask 透明：HdsTabs 默认在胶囊下方渲染带色调的渐变遮罩，
      // 素笺/肯特浅色页面上呈灰蓝带（2026-10-15 真机反馈「tab bar 下面发灰」）
      .barFloatingStyle({
        barBottomMargin: this.safeAreaBottomVp,
        adaptToHandedness: true,
        gradientMask: { maskColor: Color.Transparent },
        // 划动光感高亮色（官方 HdsTabsFloatingStyle.lightColor）：浅色纸面
        // 主题（素笺/肯特）默认白光融进纸底看不出层次 → 主题补记墨蓝
        // （theme.tabLightColor，2026-10-18 真机反馈后换色；皮革保持白）
        lightColor: this.theme.tabLightColor,
        // 照片全屏浮层开着 → 整条 Tab 栏透明（barOverlap 悬浮胶囊层在
        // NavDestination 之上，页面内浮层盖不住，HdsTabs 又无 hideBar API，
        // 只能用 barOpacity 归零；三页 @Watch 联动，关浮层/页面销毁恢复 1）
        // 键盘弹出（写日记等输入页）同样归零：dock 不随键盘抬高（2026-10-21）
        barOpacity: (this.hideTabBar || this.keyboardUp) ? 0 : 1,
        // materialLevel ADAPTIVE：官方最佳实践推荐绝大多数场景用自适应档，
        // 系统按设备算力/用户系统设置自动选 SMOOTH/GENTLE/EXQUISITE；
        // 浅色主题（素笺/肯特）下动效弱是玻璃材质浅色物理特性 + 系统档位策略，
        // 与 iOS 同款表现，不做强行 EXQUISITE（官方警示：低端设备卡顿发热、
        // 亮色下 EXQUISITE 可能覆盖白色叠层）。
        // materialType 同 ADAPTIVE（明暗风格跟 colorMode 自动切）
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })

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

  /**
   * 未选中前景色用 textSecondary（对齐 iOS：未选中 tab 是系统灰，
   * 对比度约 3.4:1 ≈ 各主题 textSecondary 的对比度；textTertiary 在素笺下仅 1.6:1 几乎不可见）
   */
  private iconTint(index: number): number {
    return index === this.currentTab
      ? this.numberColor(this.theme.accent, 0xFF8B7E6A)
      : this.numberColor(this.theme.textSecondary, 0xFFC8BDA8);
  }

  private labelColor(index: number): ResourceColor {
    return index === this.currentTab ? this.theme.accent : this.theme.textSecondary;
  }

  /** ResourceColor 是数字色值时取数值（三套主题均为数字），否则给主题近似兜底 */
  private numberColor(color: ResourceColor, fallback: number): number {
    return typeof color === 'number' ? color : fallback;
  }
}
