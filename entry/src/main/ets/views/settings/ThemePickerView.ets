/**
 * 设置 → 外观 →「主题选择」页（10_BUILD_MANUAL.md 6.2）。对应 iOS `Views/Settings/ThemePickerView.swift`。
 *
 * 主题选择页 —— 「挑一种纸」，不是「选一个配色」：
 * - 点主题**不再立刻生效**：先弹 `ThemeIntroSheet` 讲这种纸的来历（目标主题配色渲染），
 *   用户在弹窗底部选「一并更换图标」还是「仅更换主题」，下滑关闭什么都不做
 * - 已经选中的主题再点一次同样弹窗（用户可能想重读）
 * - 列表行：色块（48×48，各主题 background/accent，iOS ThemeSwatch 同值）+
 *   主题名 + 一句纸史副标题（两行不截断）+ 选中打勾
 * - 图标切换走 AGC 图标管理服务（R-THEME-06；开发期未上架服务不可用，失败只提示不回滚主题）
 *
 * 路由：系统路由表（router_map.json → name `ThemePicker`）。
 */
import { TOP_BAR_CONTENT_GAP_VP, TOP_BAR_ROW_HEIGHT_VP } from '../components/PageChrome';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME, STORAGE_KEY_THEME_ID, STORAGE_KEY_THEME_MANAGER,
  ThemeManager } from '../../theme/ThemeManager';
import { ThemePaper } from '../../theme/ThemePaper';
import { STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP } from '../../services/ImmersiveChrome';
import { ThemeIntroSheet } from './ThemeIntroSheet';

@Builder
export function ThemePickerBuilder() {
  ThemePickerView()
}

@Component
export struct ThemePickerView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  /** 当前主题 id（切换当场生效：key 一变整页重渲染，列表选中态跟着走） */
  @StorageProp(STORAGE_KEY_THEME_ID) themeId: string = 'bamboo';
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;

  /** 介绍弹窗开着吗；开着时 `introPaper` 是正在介绍的那张纸（此时主题尚未切换） */
  @State private introShow: boolean = false;
  @State private introPaper: ThemePaper = ThemePaper.all[0];
  /** 弹窗关闭后要切的主题 id；下滑关闭时它是 '' —— 什么都不做 */
  @State private pendingThemeId: string = '';
  /** 弹窗关闭后是否一并更换图标（一并 = 回「跟随主题」并切图标，R-THEME-06） */
  @State private pendingAlsoIcon: boolean = false;

  private navPathStack: NavPathStack = new NavPathStack();
  /** ThemeManager 实例（EntryAbility 启动时建好放 AppStorage） */
  private manager: ThemeManager | undefined = undefined;

  build() {
    NavDestination() {
      Column() {
        this.topBar()

        Scroll() {
          Column({ space: 16 }) {
            ForEach(ThemePaper.all, (paper: ThemePaper) => {
              this.themeRow(paper)
            })

            Text($r('app.string.s_f4aaa93473'))
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.theme.textTertiary)
              .margin({ top: 8 })

            // 底部：手势条让位
            Column().width('100%').height(this.safeAreaBottomVp + 32)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 20, right: 20, top: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        // 🔴 Scroll 设高度限制后内容小于视口默认居中（官方 FAQ faqs-arkui-725）——必须显式顶对齐
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.safeAreaTopVp })
      // 介绍弹窗：确认先记下、关掉弹窗再切（iOS applyPendingChoice 同款时序）。
      // 🔴 backgroundColor 必须显式设成目标主题底色：sheet 容器默认白底，
      // 深色主题弹窗顶部会露出一块系统默认色（真机反馈，问题三）
      .bindSheet(this.introShow, this.introSheetBuilder(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        showClose: false,
        backgroundColor: ThemeManager.themeFor(this.introPaper.id).background,
        onDisappear: (): void => {
          this.introShow = false;
          this.applyPendingChoice();
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.settingsPageBackground)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      this.manager = AppStorage.get<ThemeManager>(STORAGE_KEY_THEME_MANAGER);
    })
  }

  // ---- 顶栏：返回圆钮 + 居中标题 ----

  @Builder
  private topBar() {
    Stack() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textPrimary])
        }
        .width(34)
        .height(34)
        .padding(0)
        .backgroundColor(this.theme.glassBackground)
        .border({ width: 0.5, color: this.theme.glassBorder })
        .onClick((): void => {
          this.navPathStack.pop();
        })
        Blank()
      }
      .width('100%')
      .height(TOP_BAR_ROW_HEIGHT_VP)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Text($r('app.string.s_ad8012ee9f'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textSecondary)
          .letterSpacing(this.theme.letterSpacingWide)
      }
      .width('100%')
      .height(TOP_BAR_ROW_HEIGHT_VP)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(TOP_BAR_ROW_HEIGHT_VP)
    .margin({ bottom: TOP_BAR_CONTENT_GAP_VP })
  }

  // ---- 单行：色块 + 名 + 副标题 + 选中打勾（iOS themeRow 同款） ----

  @Builder
  private themeRow(paper: ThemePaper) {
    Row({ space: 14 }) {
      this.themePreview(paper.id)

      Column() {
        Text(paper.nameRes)
          .fontSize(this.theme.headingFont.size)
          .fontWeight(this.theme.headingFont.weight)
          .fontFamily(this.theme.headingFont.family)
          .fontColor(this.theme.textPrimary)
        // 允许两行，不要截断成省略号（不设行数上限，让它自己换行）
        Text(paper.subtitleRes)
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.themeId === paper.id) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.theme.accent])
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor(this.theme.settingsCardBackground)
    .border({
      width: this.themeId === paper.id ? 1.5 : 0.5,
      color: this.themeId === paper.id ? this.theme.accent : this.theme.border
    })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      // 已选中的再点一次同样弹窗（用户可能想重读）
      this.introPaper = paper;
      this.introShow = true;
    })
  }

  /** 行首色块：目标主题的 background/accent（iOS ThemeSwatch 同值），48×48 圆角 8，白描边 */
  @Builder
  private themePreview(id: string) {
    Column() {
      Text($r('app.string.s_1d56b27a5e'))
        .fontSize(18)
        .fontWeight(FontWeight.Lighter)
        .fontFamily('serif')
        .fontColor(ThemeManager.themeFor(id).accent)
    }
    .width(48)
    .height(48)
    .borderRadius(8)
    .backgroundColor(ThemeManager.themeFor(id).background)
    .justifyContent(FlexAlign.Center)
    .border({ width: 0.5, color: '#338E8E93' })
  }

  // ---- 介绍弹窗 ----

  @Builder
  private introSheetBuilder() {
    ThemeIntroSheet({
      paperId: this.introPaper.id,
      onChoose: (alsoIcon: boolean): void => {
        this.pendingThemeId = this.introPaper.id;
        this.pendingAlsoIcon = alsoIcon;
        this.introShow = false;
      }
    })
  }

  /** 弹窗关闭后执行切换；下滑关闭（pendingThemeId 为空）什么都不做。
   * 图标没换成不影响主题 —— 主题保持已切换的状态，只提示图标这件事（R-THEME-06） */
  private applyPendingChoice(): void {
    if (this.pendingThemeId === '') {
      return;
    }
    const target = this.pendingThemeId;
    const alsoIcon = this.pendingAlsoIcon;
    this.pendingThemeId = '';
    this.pendingAlsoIcon = false;
    if (this.manager !== undefined) {
      this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
        this.manager?.switchTheme(target, alsoIcon, (error: BusinessError): void => {
          hilog.error(0x0000, 'ThemePicker', 'icon switch failed, code: %{public}d', error.code);
          this.getUIContext().getPromptAction().showToast({
            message: $r('app.string.s_90c36f74f2')
          });
        });
      });
    }
  }
}
