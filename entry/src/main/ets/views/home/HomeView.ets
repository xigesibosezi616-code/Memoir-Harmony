/**
 * 记录页（列表模式，10_BUILD_MANUAL.md 2.2，R-HOME-01~05）。对应 iOS
 * `Views/Home/HomeView.swift` 的列表分支（大屏模式是后面的卡片，本卡不做）。
 *
 * - 头部：大标题「MEMOIR · 尺素」（Regular，与 iOS Georgia 常规体一致）
 *   + 时段问候（同一小时固定）+「本月记录 N 天」（N>0 才显示）
 *   + 每日语录（同一天固定；常规体——iOS 无斜体，斜体还致左缘不齐）
 * - 列表：按年月分组倒序、组头吸顶（List + ListItemGroup + sticky）
 * - 空状态：「暂无日记」卡片；底部浮钮「写下今天的故事」→ 写日记页
 * - 点行进详情（Tab 内 Navigation 栈，底部 Tab 栏保留可见，对齐 iOS push）
 * - 数据刷新：Index.onPageShow（路由返回 / 回前台）bump `homeReloadTick`
 *   （AppStorage），这里 @Watch 重新查库 —— 对应 iOS `@Query` 对 SwiftData
 *   的自动响应（RDB 无观察机制，用显式信号补齐；2.3 详情删除同样走这里）。
 *   另外分组 ForEach 的 key 带内容签名（条数 + 最新更新时间）：
 *   ForEach 同 key 不重建子树，只写 group.key 时增删日记不会刷新 UI
 * - 顶部磨砂玻璃片 + 玻璃上小标题（iOS 材质导航栏手感，用户定稿）：
 *   26fp 大标题「MEMOIR · 尺素」随列表动态滚动（非固定），磨砂玻璃片
 *   浮在文字上方、由 Scroller 真实偏移驱动渐显（回弹不误触发）；
 *   大标题滚尽后 16fp 小标题渐显、「印」在玻璃上（错峰 + 位置错位，
 *   无大小标题重叠）；内容不满一屏时 alwaysEnabled 保果冻回弹（滑不动）
 * - 占位页职责迁入：默认数据 ensureDefaultData + 调试入口（Theme/Language/Toast，
 *   6.x 统一删）；原 MainPlaceholderView 随本卡替换删除
 */
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { hdsEffect } from '@kit.UIDesignKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import {
  STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP
} from '../../services/ImmersiveChrome';
import { GreetingManager } from '../../services/GreetingManager';
import { AppDatabase } from '../../data/Database';
import { EntryRepository } from '../../data/EntryRepository';
import {
  EntryGroup,
  STORAGE_KEY_HOME_RELOAD_TICK,
  groupedEntries,
  monthRecordDays
} from '../../data/HomeLogic';
import { DefaultDataService } from '../../data/DefaultData';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { ErrorToastKind } from '../../environment/ErrorPresenter';
import { JournalEntry } from '../../models/JournalEntry';
import { EntryRowView } from './EntryRowView';
import { ThemedCard } from '../components/ThemedCard';

const DOMAIN = 0x0000;
const TAG = 'HomeView';

@Component
export struct HomeView {
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  /** 主页重查信号：Index.onPageShow（页面重新可见）+1，@Watch 重查库 */
  @StorageProp(STORAGE_KEY_HOME_RELOAD_TICK) @Watch('onReloadTickChange')
  homeReloadTick: number = 0;
  @State entries: JournalEntry[] = [];

  /** 顶部磨砂玻璃片透明度：List 真实滚动偏移驱动（0 沉浸式 → 1 全显磨砂） */
  @State private glassOpacity: number = 0;
  /** 玻璃上小标题透明度：大标题滚尽（80vp）后才开始渐显，错峰防重叠 */
  @State private smallTitleOpacity: number = 0;
  /** FAB 按压光效（官方 pressShadow 状态驱动）：按下 BLEND_WHITE、抬起 NONE */
  @State private fabPressShadow: hdsEffect.PressShadowType = hdsEffect.PressShadowType.NONE;
  private scroller: Scroller = new Scroller();
  /** 记录 Tab 内导航栈：详情页（NavDestination）推入后底部 Tab 栏保留可见，
   * 对齐 iOS TabView > NavigationStack 的 push 呈现 */
  private navPathStack: NavPathStack = new NavPathStack();

  private store: relationalStore.RdbStore | undefined = undefined;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      // 默认数据（12 心情 + 4 日记本）：幂等补缺，占位页迁入的职责（R-APP-01/07）
      DefaultDataService.ensureDefaultData(context)
        .catch((err: Object) => {
          hilog.error(DOMAIN, TAG, 'ensureDefaultData failed: %{public}s', JSON.stringify(err));
        });
      this.loadEntries(context);
    }
  }

  build() {
    // 记录 Tab 内 Navigation（系统路由表）：首页 = 原主页 Stack（列表 + 磨砂
    // 玻璃片 + FAB），详情页以 NavDestination 推入（`router_map.json`）。
    // 强制 Stack 模式：展开大屏（Mate X6 内屏近似方屏）时 Auto 模式会切
    // 分栏，手机形态一律整页推入，与 iOS 手机形态一致。
    Navigation(this.navPathStack) {
      Stack({ alignContent: Alignment.Bottom }) {
      List({ space: 12, scroller: this.scroller }) {
        // 头部：大标题「MEMOIR · 尺素」+ 时段问候 + 本月记录 + 每日语录
        // （R-HOME-01；大标题随列表滚动，动态非固定）
        ListItem() {
          Column({ space: 6 }) {
            Text($r('app.string.s_f29761cd03'))
              // 26fp：华为官方大标题字号（系统「设置」首页实测同值）；
              // Regular 不加粗——iOS 源码 `.custom("Georgia", 30)` 即常规体
              .fontSize(26)
              .fontWeight(FontWeight.Normal)
              .fontFamily(this.theme.titleFont.family)
              .fontColor(this.theme.textPrimary)
              .letterSpacing(1)
            Text(GreetingManager.timeBasedGreeting(new Date().getHours()))
              // 16fp：官方正文基准字号（iOS 17pt 按鸿蒙字阶收敛）
              .fontSize(16)
              .fontWeight(FontWeight.Normal)
              .fontFamily(this.theme.titleFont.family)
              .fontColor(this.theme.textPrimary)
            if (monthRecordDays(this.entries, new Date()) > 0) {
              Text($r('app.string.s_2a91ea5068', monthRecordDays(this.entries, new Date())))
                .fontSize(this.theme.captionFont.size)
                .fontWeight(this.theme.captionFont.weight)
                .fontFamily(this.theme.captionFont.family)
                .fontColor(this.theme.textTertiary)
            }
            Text(GreetingManager.dailyQuote(GreetingManager.dayOfYear(new Date())))
              // 12fp：官方辅助文字字号（iOS 13pt 收敛）；不用斜体——
              // iOS 源码即常规体，且斜体首字视觉缩进导致左缘与上文不齐
              .fontSize(12)
              .fontWeight(FontWeight.Normal)
              .fontFamily(this.theme.titleFont.family)
              .fontColor(this.theme.textSecondary)
              .padding({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: this.safeAreaTopVp + 12,
            bottom: 16
          })
        }

        // 空状态（R-HOME-05）：底部浮钮仍在，引导第一次书写；
        // 卡高与有日记时的标准卡同款（118vp，EntryRowView.cardHeightVp），
        // 空态与内容态切换无高度跳变（2026-10-20 用户拍板）；
        // 两行文案卡内水平+垂直居中（2026-10-20 用户拍板，iOS 为左上对齐，
        // 以用户要求为准）；layoutWeight(1) 撑满卡内区（118-32=86vp）供居中
        // 注：不能在 ThemedCard 尾随闭包后链 .constraintSize（ets 编译
        // 限制，"Declaration or statement expected"），改经 minHeightVp 传入
        if (this.entries.length === 0) {
          ListItem() {
            Column() {
              ThemedCard({ minHeightVp: EntryRowView.cardHeightVp }) {
                Column({ space: 8 }) {
                  Text($r('app.string.s_09873b1938'))
                    .fontSize(this.theme.headingFont.size)
                    .fontWeight(this.theme.headingFont.weight)
                    .fontFamily(this.theme.headingFont.family)
                    .fontColor(this.theme.textPrimary)
                  Text($r('app.string.s_e488fa1386'))
                    .fontSize(this.theme.captionFont.size)
                    .fontWeight(this.theme.captionFont.weight)
                    .fontFamily(this.theme.captionFont.family)
                    .fontColor(this.theme.textTertiary)
                }
                .alignItems(HorizontalAlign.Center)
                .justifyContent(FlexAlign.Center)
                .layoutWeight(1)
                .width('100%')
              }
            }
            .padding({ left: 16, right: 16 })
            .width('100%')
            .justifyContent(FlexAlign.Start)
            .alignItems(HorizontalAlign.Start)
          }
        }

        // 分组列表（R-HOME-02 列表分支）：组头吸顶、组内倒序；
        // 卡片式（华为备忘录，2026-10-16 真机实测）：
        // 卡距 12vp、圆角 16vp、页边距 16vp（EntryRowView 内成型）
        ForEach(this.groups(), (group: EntryGroup) => {
          // 备忘录卡片式（真机实测）：组内卡距 12vp，组头吸顶；无 divider
          // （卡间留白即分隔，线式 divider 为历史方案）
          ListItemGroup({
            header: (): void => { this.groupHeader(group) },
            space: 12
          }) {
            ForEach(group.entries, (entry: JournalEntry) => {
              // 页边距 16vp（备忘录规格）：卡外留白，包一层 padding——
              // width('100%') 直接配 margin 会溢出父容器
              ListItem() {
                Column() {
                  EntryRowView({
                    entry: entry,
                    // 点卡进详情（2.3）：推入 Tab 内 Navigation 栈，
                    // 底部 Tab 栏保留可见（对齐 iOS push 详情页）
                    onTap: (): void => {
                      this.navPathStack.pushPathByName('EntryDetail', entry.id);
                    }
                  })
                }
                .padding({ left: 16, right: 16 })
                .width('100%')
              }
            }, (entry: JournalEntry): string => entry.id)
          }
        }, (group: EntryGroup): string => {
          // key 带内容签名：ForEach 同 key 不重建子树，只写 group.key 时
          // 增删日记 UI 不刷新（真机踩坑）；签名 = 年月 + 条数 + 最新更新时间
          let latest = 0;
          for (const entry of group.entries) {
            if (entry.updatedAt > latest) {
              latest = entry.updatedAt;
            }
          }
          return group.key + '#' + group.entries.length + '#' + latest;
        })

        // 底部留白：给浮钮 / Tab 栏（iOS Spacer 100）
        ListItem() {
          Column()
            .height(120)
            .width('100%')
        }

        // 调试入口（脚手架，6.x 统一删；从占位页迁入）
        ListItem() {
          Row({ space: 12 }) {
            Button('ThemeDebug')
              .fontSize(this.theme.bodyFont.size)
              .fontColor(this.theme.accent)
              .backgroundColor(this.theme.accentBackground)
              .borderRadius(10)
              .onClick((): void => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/ThemeDebug' });
              })
            Button('LanguageDebug')
              .fontSize(this.theme.bodyFont.size)
              .fontColor(this.theme.accent)
              .backgroundColor(this.theme.accentBackground)
              .borderRadius(10)
              .onClick((): void => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/LanguageDebug' });
              })
            Button('LocationDebug')
              .fontSize(this.theme.bodyFont.size)
              .fontColor(this.theme.accent)
              .backgroundColor(this.theme.accentBackground)
              .borderRadius(10)
              .onClick((): void => {
                // 2.10 此时此地偏好（记录位置开关 + 精度三档）；6.1 设置页就绪后删
                this.getUIContext().getRouter().pushUrl({ url: 'pages/LocationDebug' });
              })
            Button('ToastDebug')
              .fontSize(this.theme.bodyFont.size)
              .fontColor(this.theme.accent)
              .backgroundColor(this.theme.accentBackground)
              .borderRadius(10)
              .onClick((): void => {
                // 触发一条 error toast（现成文案「同步异常」），验收顶部提示链路
                const context = this.getUIContext().getHostContext();
                if (context !== undefined) {
                  const message: string =
                    context.resourceManager.getStringSync($r('app.string.s_d60bcc29e2').id);
                  this.env.errors.present(message, ErrorToastKind.Error, 3000);
                }
              })
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }
      }
      .sticky(StickyStyle.Header)
      .scrollBar(BarState.Off)
      // iOS alwaysBounce：内容不满一屏时也保留弹簧回弹（果冻感），
      // alwaysEnabled 默认 false → 满一屏前拖动无响应，与 iOS 手感不符
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      // 玻璃片 / 小标题透明度：Scroller 真实偏移驱动——用 currentOffset
      // 读真值而非 onWillScroll 偏移累加，弹簧回弹时偏移归零不会误触发；
      // 小标题晚 80vp 起步（大标题滚尽才出现），错峰 + 位置错位防重叠
      .onDidScroll((): void => {
        const y = Number(this.scroller.currentOffset().yOffset);
        this.glassOpacity = HomeView.clamp01(y / 80);
        this.smallTitleOpacity = HomeView.clamp01((y - 80) / 40);
      })
      .width('100%')
      .height('100%')

      // 顶部磨砂玻璃片（iOS 材质导航栏手感）：随滚动渐显（静止全透明保
      // 沉浸式），Thin 毛玻璃 + 主题色半透明叠色，浮在穿过的文字上方；
      // 不参与命中（玻璃上拖动透传给列表照常滚）
      Column()
        .width('100%')
        .height(this.safeAreaTopVp + 56)
        .backgroundColor(this.frostedBarColor())
        .backgroundBlurStyle(BlurStyle.Thin)
        .opacity(this.glassOpacity)
        .hitTestBehavior(HitTestMode.None)
        .position({ x: 0, y: 0 })

      // 玻璃上的小标题：主题衬线体（与大标题同族 'serif'，品牌气质一致；
      // 不加粗——Normal 字重小字号下更雅致），12fp 居中「印」在毛玻璃上
      // （56vp 标题栏区水平垂直居中），大标题滚尽后才渐显，错峰防重叠
      Row() {
        Text($r('app.string.s_f29761cd03'))
          .fontSize(12)
          .fontWeight(FontWeight.Normal)
          .fontFamily(this.theme.titleFont.family)
          .fontColor(this.theme.textPrimary)
          .letterSpacing(0.5)
      }
      .width('100%')
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .opacity(this.smallTitleOpacity)
      .hitTestBehavior(HitTestMode.None)
      .position({ x: 0, y: this.safeAreaTopVp })

      // 底部浮钮（R-HOME-04 列表模式）：备忘录同款实色胶囊 + 柔和投影
      // → 写日记页。官方沉浸光感材质限制内容区组件不可用（仅标题栏 /
      // 底部 TabBar 生效），参考华为备忘录 FAB 观感：实色 accent + 阴影；
      // 按压光效走官方 hdsEffect pressShadow（Button 专属按压光效，
      // 不受材质生效范围限制）。官方《按压阴影》要求状态驱动：
      // 按下置 BLEND_WHITE、抬起/取消回 NONE——静态常驻渐变会把
      // 实色底抹成白色渐变团、白字不可读（2026-10-16 真机实测）
      Button($r('app.string.s_f6c9fb2f33'))
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.cardBackground)
        .backgroundColor(this.theme.accent)
        .borderRadius(22)
        .padding({ left: 24, right: 24, top: 14, bottom: 14 })
        .shadow({ radius: 16, color: this.accentShadowColor(), offsetX: 0, offsetY: 6 })
        .margin({ bottom: this.safeAreaBottomVp + 90 })
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pressShadow(this.fabPressShadow)
          .buildEffect())
        .onTouch((event: TouchEvent): void => {
          if (event.type === TouchType.Down) {
            this.fabPressShadow = hdsEffect.PressShadowType.BLEND_WHITE;
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.fabPressShadow = hdsEffect.PressShadowType.NONE;
          }
        })
        .onClick((): void => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/Compose' });
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.background)
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
  }

  /** 组头：年月 + 吸顶背景（R-HOME-02）；左右 16 = 华为官方列表边界，背景全宽遮内容 */
  @Builder
  private groupHeader(group: EntryGroup) {
    Row() {
      Text(group.key)
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
        .letterSpacing(this.theme.letterSpacingWide)
    }
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .width('100%')
    .backgroundColor(this.theme.background)
  }

  /** 当前分组（build 时算；语言 / 库变化触发重渲染自动重算） */
  private groups(): EntryGroup[] {
    return groupedEntries(this.entries, this.appLanguage);
  }

  /** 主页重查信号（页面重新可见）→ 重查列表 */
  private onReloadTickChange(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      this.loadEntries(context);
    }
  }

  private async loadEntries(context: common.Context): Promise<void> {
    try {
      const store = await AppDatabase.open(context);
      this.store = store;
      const entries = await EntryRepository.fetchAllEntries(store);
      this.entries = entries;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'loadEntries failed: %{public}s', JSON.stringify(err));
    }
  }

  /** FAB 投影色：accent 30% 透明（iOS `.shadow(color: accent.opacity(0.3))`） */
  private accentShadowColor(): ResourceColor {
    const accent = this.theme.accent;
    if (typeof accent === 'number') {
      return 0x4D000000 + (accent & 0x00FFFFFF);
    }
    return 0x4D000000;
  }

  /** 0~1 钳制（滚动偏移 → 透明度） */
  private static clamp01(value: number): number {
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
  }

  /**
   * 磨砂玻璃片叠色：主题背景色 40% 半透明（Thin 毛玻璃打底，上面叠主题色
   * → 各主题都是自己的 frosted 质感；叠色压低到 40% 保玻璃通透感
   * （用户手感定稿），深浅主题下状态栏内容色都对得住对比）
   */
  private frostedBarColor(): ResourceColor {
    const bg = this.theme.background;
    if (typeof bg === 'number') {
      return (bg & 0x00FFFFFF) | 0x66000000;
    }
    return bg;
  }
}
