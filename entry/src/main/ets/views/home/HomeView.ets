/**
 * 记录页（10_BUILD_MANUAL.md 2.2 + 3.6 + U06/U07）。对应 iOS
 * `Views/Home/HomeView.swift`：展示方式两分支 + 大屏四级捏合。
 *
 * - 列表模式（R-HOME-01~05，原 2.2 全量保留）：大标题 + 问候 + 语录、
 *   按年月分组吸顶、磨砂玻璃片、FAB
 * - 大屏模式（3.6 + U06 R-HOME-08/09/10 + U07 R-HOME-11）：**默认**。
 *   一屏一篇（大卡片）→ 4 篇（2×2 翻页）→ 16 / 64 篇（按月宫格），
 *   双指捏合一次换一级（按次数不按力度），每级一震，换级后手指底下
 *   还是同一篇；点卡片 / 格子进详情
 * - 空状态按模式分两句（U07 R-HOME-05）：大屏指向右上「+」，列表指向
 *   底部浮钮
 * - 展示方式切换（6.1 设置页就绪前的临时入口）：调试行「大屏 / 列表」
 *   （2026-10-23 用户拍板）
 * - 换级转场（U06 R-HOME-09）：0.4s FastOutSlowIn，翻页两级以手指那格
 *   为中心缩放（27% / 73%），宫格以顶边；往密旧层缩 0.6、新层 1.5 落下，
 *   往疏反向。两段式：先排好转场方向（旧层按新方向重画一次，退场动画
 *   才对——iOS 同款坑），下一帧再换级
 */
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vibrator } from '@kit.SensorServiceKit';
import { hdsEffect } from '@kit.UIDesignKit';
import { display } from '@kit.ArkUI';
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
import { DraftRepository } from '../../data/DraftRepository';
import {
  STORAGE_KEY_CONTINUED_DRAFT_JSON,
  STORAGE_KEY_CONTINUE_TO_COMPOSE_TICK,
  decodeDraftFromContinuation
} from '../../services/AppContinuation';
import { MediaStorageService } from '../../services/MediaStorageService';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { ErrorToastKind } from '../../environment/ErrorPresenter';
import { JournalEntry } from '../../models/JournalEntry';
import {
  PINCH_IN_SCALE, PINCH_OUT_SCALE, ShowcaseZoomLevel, quadEntryIndexAtSlot,
  quadPageOf, quadPageStart, quadSlotAnchor, quadSlotAt,
  overviewEntryIndexAt, overviewMonths
} from '../../models/ShowcaseDigest';
import {
  AppPrefs, HOME_DISPLAY_MODE_LIST, HOME_DISPLAY_MODE_SHOWCASE
} from '../../services/AppPrefs';
import { EntryPhotoStore } from '../../services/EntryPhotoStore';
import { EntryRowView } from './EntryRowView';
import { ThemedCard } from '../components/ThemedCard';
import { ShowcasePager } from './showcase/ShowcasePager';
import { ShowcaseQuadPager } from './showcase/ShowcaseQuadPager';
import { ShowcaseOverview } from './showcase/ShowcaseOverview';

const DOMAIN = 0x0000;
const TAG = 'HomeView';

/** 组件在窗口里的位置和大小（捏合换算「手指底下是哪篇」用） */
class RectVp {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;

  constructor(x: number, y: number, width: number, height: number) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }
}

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
  /** 应用接续信号：EntryAbility 收到 CONTINUATION 想要 +1，@Watch 恢复草稿并进写日记页 */
  @StorageProp(STORAGE_KEY_CONTINUE_TO_COMPOSE_TICK) @Watch('onContinueToComposeTick')
  continueToComposeTick: number = 0;
  @State entries: JournalEntry[] = [];
  /** 接续恢复进行中（防重入；@Watch 与 aboutToAppear 可能先后各触发一次） */
  private continueRestoreInFlight: boolean = false;

  // ---- 大屏模式状态（U06 / U07） ----

  /** 展示方式：没选过默认大屏（U07 R-HOME-11）；调试行临时切换 */
  @State displayMode: string = HOME_DISPLAY_MODE_SHOWCASE;
  /** 一屏放几篇（0–3，U06 R-HOME-09 记住上次的级别） */
  @State zoom: number = ShowcaseZoomLevel.One;
  /** 第 0 / 1 级翻到了哪（捏小时以它为准，张开回来停在手指底下那篇） */
  @State singleIndex: number = 0;
  @State quadIndex: number = 0;
  /** 换到第 2 / 3 级时手指底下那篇：新宫格出现后瞬时滚到原处 */
  @State pendingFocusIndex: number = -1;
  /** 换级转场的方向（往密）和缩放中心（翻页两级以手指那一格为中心） */
  @State private zoomToDenser: boolean = true;
  @State private anchorPercentX: number = 50;
  @State private anchorPercentY: number = 50;

  /** 捏合中间态（不驱动 UI，不用 @State） */
  private pinchFocusIndex: number = -1;
  private pinchStepped: boolean = false;
  /** 最近一次捏合活动时刻（ms）：捏合中/松手后短时间内点卡片不算点击（防误触打开） */
  private lastPinchAt: number = 0;
  /** 捏合后点击冷却窗：松手瞬间单指先抬、另一指快速离屏会被判成 tap（实锤误触来源） */
  private static readonly pinchClickCooldownMs: number = 400;

  /** 宫格的滚动控制器（捏合时要读滚动位置） */
  private overviewScroller: ListScroller = new ListScroller();

  // ---- 列表模式状态（原 2.2） ----

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
      // 大屏照片缓存就位（cacheDir / 原图目录注入；幂等）
      EntryPhotoStore.shared().configure(context);
      this.displayMode = AppPrefs.currentHomeDisplayMode();
      this.zoom = AppPrefs.currentShowcaseZoom();
      this.loadEntries(context);
      // 应用接续（对端冷启动）：合规层走完后首页才挂载，此刻恢复接续草稿
      this.restoreContinuedDraftIfNeeded();
    }
  }

  /** 应用接续（对端热启动）：应用活着收到 CONTINUATION 时信号 +1 走这里 */
  private onContinueToComposeTick(): void {
    this.restoreContinuedDraftIfNeeded();
  }

  /**
   * 消费接续草稿：解码 → 覆盖本机草稿表 → 路由进写日记页（ComposeView
   * 从草稿表自动恢复）。本机已有**另一份**草稿时，接续的这份是用户此刻
   * 正在写的，让它接管：本机那份连媒体一起清（「不保存」同款路径）。
   * 已在写日记页时不重复推（避免叠两层编辑页）。
   */
  private async restoreContinuedDraftIfNeeded(): Promise<void> {
    if (this.continueRestoreInFlight) {
      return;
    }
    if ((AppStorage.get<number>(STORAGE_KEY_CONTINUE_TO_COMPOSE_TICK) ?? 0) <= 0) {
      return;
    }
    const payload: string = AppStorage.get<string>(STORAGE_KEY_CONTINUED_DRAFT_JSON) ?? '';
    AppStorage.setOrCreate(STORAGE_KEY_CONTINUE_TO_COMPOSE_TICK, 0);
    if (payload.length === 0) {
      return;
    }
    this.continueRestoreInFlight = true;
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.continueRestoreInFlight = false;
      return;
    }
    try {
      const draft = decodeDraftFromContinuation(payload);
      if (draft === null) {
        hilog.warn(DOMAIN, TAG, 'continued draft decode failed, ignored');
        AppStorage.setOrCreate(STORAGE_KEY_CONTINUED_DRAFT_JSON, '');
        return;
      }
      let store = this.store;
      if (store === undefined) {
        store = await AppDatabase.open(context);
        this.store = store;
      }
      const localDraft = await DraftRepository.loadCurrentDraft(store);
      if (localDraft !== null && localDraft.id !== draft.id) {
        MediaStorageService.create(context, store).deleteDraftMedia(localDraft);
        await DraftRepository.deleteDraftRecord(store, localDraft.id);
        hilog.info(DOMAIN, TAG, 'local draft %{public}s replaced by continued draft', localDraft.id);
      }
      await DraftRepository.saveDraft(store, draft);
      AppStorage.setOrCreate(STORAGE_KEY_CONTINUED_DRAFT_JSON, '');
      if (this.getUIContext().getRouter().getState().path !== 'pages/Compose') {
        this.getUIContext().getRouter().pushUrl({ url: 'pages/Compose' });
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'restore continued draft failed: %{public}s', JSON.stringify(err));
    } finally {
      this.continueRestoreInFlight = false;
    }
  }

  build() {
    Navigation(this.navPathStack) {
      if (this.displayMode === HOME_DISPLAY_MODE_LIST) {
        this.listContent()
      } else {
        this.showcaseContent()
      }
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
  }

  // ---- 列表模式（原 2.2 全量保留） ----

  @Builder
  private listContent() {
    Stack({ alignContent: Alignment.Bottom }) {
      List({ space: 12, scroller: this.scroller }) {
        // 头部：大标题「MEMOIR · 尺素」+ 时段问候 + 本月记录 + 每日语录
        ListItem() {
          Column({ space: 6 }) {
            Text($r('app.string.s_f29761cd03'))
              .fontSize(26)
              .fontWeight(FontWeight.Normal)
              .fontFamily(this.theme.titleFont.family)
              .fontColor(this.theme.textPrimary)
              .letterSpacing(1)
            Text(GreetingManager.timeBasedGreeting(new Date().getHours()))
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

        // 空状态（R-HOME-05 列表句）：底部浮钮仍在，引导第一次书写
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

        // 分组列表（R-HOME-02 列表分支）：组头吸顶、组内倒序、卡片式
        ForEach(this.groups(), (group: EntryGroup) => {
          ListItemGroup({
            header: (): void => { this.groupHeader(group) },
            space: 12
          }) {
            ForEach(group.entries, (entry: JournalEntry) => {
              ListItem() {
                Column() {
                  EntryRowView({
                    entry: entry,
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
          let latest = 0;
          for (const entry of group.entries) {
            if (entry.updatedAt > latest) {
              latest = entry.updatedAt;
            }
          }
          return group.key + '#' + group.entries.length + '#' + latest;
        })

        // 底部留白：给浮钮 / Tab 栏
        ListItem() {
          Column()
            .height(120)
            .width('100%')
        }

        // 调试入口（脚手架，6.x 统一删）：含展示方式临时切换（6.1 设置页迁走）
        ListItem() {
          Column() {
            this.debugRow()
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }
      }
      .sticky(StickyStyle.Header)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .onDidScroll((): void => {
        const y = Number(this.scroller.currentOffset().yOffset);
        this.glassOpacity = HomeView.clamp01(y / 80);
        this.smallTitleOpacity = HomeView.clamp01((y - 80) / 40);
      })
      .width('100%')
      .height('100%')

      // 顶部磨砂玻璃片：随滚动渐显，浮在穿过的文字上方，不参与命中
      Column()
        .width('100%')
        .height(this.safeAreaTopVp + 56)
        .backgroundColor(this.frostedBarColor())
        .backgroundBlurStyle(BlurStyle.Thin)
        .opacity(this.glassOpacity)
        .hitTestBehavior(HitTestMode.None)
        .position({ x: 0, y: 0 })

      // 玻璃上的小标题：大标题滚尽后才渐显
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

      // 底部浮钮（R-HOME-04 列表模式）→ 写日记页
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

  // ---- 大屏模式（3.6 + U06） ----

  @Builder
  private showcaseContent() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.entries.length === 0) {
        this.showcaseEmpty()
      } else if (this.zoom <= ShowcaseZoomLevel.Four) {
        // 第 0 / 1 级：页首不动（整页上下锁死），卡片区左右翻
        Column() {
          this.showcaseHeaderRow()
          if (this.zoom === ShowcaseZoomLevel.One) {
            ShowcasePager({
              entries: this.entries,
              singleIndex: this.singleIndex,
              onOpen: (id: string): void => {
                this.openEntry(id);
              }
            })
              .layoutWeight(1)
              .transition(this.pagerTransition())
          } else {
            ShowcaseQuadPager({
              entries: this.entries,
              quadIndex: this.quadIndex,
              onOpen: (id: string): void => {
                this.openEntry(id);
              }
            })
              .layoutWeight(1)
              .transition(this.pagerTransition())
          }
          Column() {
            this.debugRow()
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
        }
        .width('100%')
        .height('100%')
        .transition(this.pagerTransition())
      } else if (this.zoom === ShowcaseZoomLevel.Sixteen) {
        // 第 2 / 3 级（16 / 64 网格）：页首同样固定不动，卡片从它下面滚走
        // （2026-10-23 用户拍板，与第 0 / 1 级同构；iOS 是页首跟滚 + 小标题浮现，记偏差）。
        // 分支按 zoom 拆：换级必须销毁重建（aboutToAppear 里 pendingFocus 定位）
        Column() {
          this.showcaseHeaderRow()
          ShowcaseOverview({
            entries: this.entries,
            zoom: ShowcaseZoomLevel.Sixteen,
            scroller: this.overviewScroller,
            pendingFocusIndex: this.pendingFocusIndex,
            onOpen: (id: string): void => {
              this.openEntry(id);
            },
            debugRow: (): void => {
              this.debugRow()
            }
          })
            .layoutWeight(1)
            .transition(this.gridTransition())
        }
        .width('100%')
        .height('100%')
      } else {
        Column() {
          this.showcaseHeaderRow()
          ShowcaseOverview({
            entries: this.entries,
            zoom: ShowcaseZoomLevel.SixtyFour,
            scroller: this.overviewScroller,
            pendingFocusIndex: this.pendingFocusIndex,
            onOpen: (id: string): void => {
              this.openEntry(id);
            },
            debugRow: (): void => {
              this.debugRow()
            }
          })
            .layoutWeight(1)
            .transition(this.gridTransition())
        }
        .width('100%')
        .height('100%')
      }
    }
    // 双指捏合（U06 R-HOME-09）：parallelGesture 与翻页 / 滚动并存
    .parallelGesture(
      PinchGesture({ fingers: 2 })
        .onActionStart((event: GestureEvent): void => {
          this.lastPinchAt = Date.now();
          if (this.entries.length === 0) {
            this.pinchFocusIndex = -1;
            return;
          }
          this.pinchStepped = false;
          this.pinchFocusIndex = this.focusIndexAt(
            this.pinchCenterX(event), this.pinchCenterY(event));
        })
        .onActionUpdate((event: GestureEvent): void => {
          this.lastPinchAt = Date.now();
          if (this.pinchStepped || this.entries.length === 0 || this.pinchFocusIndex < 0) {
            return;
          }
          if (event.scale < PINCH_OUT_SCALE) {
            // 往里捏一次 = 密一级（一次捏合只换一级，换完不再换）
            this.pinchStepped = true;
            if (this.zoom < ShowcaseZoomLevel.SixtyFour) {
              this.setZoom(this.zoom + 1, this.pinchFocusIndex);
            }
          } else if (event.scale > PINCH_IN_SCALE) {
            this.pinchStepped = true;
            if (this.zoom > ShowcaseZoomLevel.One) {
              this.setZoom(this.zoom - 1, this.pinchFocusIndex);
            }
          }
        })
        .onActionEnd((): void => {
          this.lastPinchAt = Date.now();
          this.pinchStepped = false;
          this.pinchFocusIndex = -1;
        })
    )
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }

  /** 大屏页首（压缩版）：大标题 + 问候 + 本月记录 + 右上「+」 */
  @Builder
  private showcaseHeaderRow() {
    Row() {
      Column({ space: 2 }) {
        Text($r('app.string.s_f29761cd03'))
          .fontSize(22)
          .fontWeight(FontWeight.Normal)
          .fontFamily(this.theme.titleFont.family)
          .fontColor(this.theme.textPrimary)
          .letterSpacing(1.4)
        Text(GreetingManager.timeBasedGreeting(new Date().getHours()))
          .fontSize(14)
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
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 大屏模式写日记入口收进右上角，版面全留给卡片（U07 R-HOME-05）
      Button() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(18)
          .fontColor([this.theme.cardBackground])
      }
      .width(36)
      .height(36)
      .backgroundColor(this.theme.accent)
      .borderRadius(18)
      .onClick((): void => {
        this.getUIContext().getRouter().pushUrl({ url: 'pages/Compose' });
      })
    }
    .alignItems(VerticalAlign.Top)
    .padding({ left: 20, right: 20, top: this.safeAreaTopVp + 28, bottom: 8 })
    .width('100%')
  }

  /** 大屏空状态（U07 R-HOME-05）：提示指向右上角的「+」 */
  @Builder
  private showcaseEmpty() {
    Column() {
      this.showcaseHeaderRow()
      Column() {
        ThemedCard({ minHeightVp: EntryRowView.cardHeightVp }) {
          Column({ space: 8 }) {
            Text($r('app.string.s_09873b1938'))
              .fontSize(this.theme.headingFont.size)
              .fontWeight(this.theme.headingFont.weight)
              .fontFamily(this.theme.headingFont.family)
              .fontColor(this.theme.textPrimary)
            Text($r('app.string.s_02519f32e9'))
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.theme.textTertiary)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
      }
      .padding({ left: 16, right: 16 })
      .width('100%')

      Column()
        .layoutWeight(1)

      Column() {
        this.debugRow()
      }
      .width('100%')
      .padding({ top: 4, bottom: this.safeAreaBottomVp + 8 })
    }
    .width('100%')
    .height('100%')
  }

  /** 调试行（脚手架，6.x 统一删）：展示方式临时切换 + 原四个调试入口 */
  @Builder
  private debugRow() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button($r('app.string.s_1ab35f0df8')) // 大屏
          .fontSize(this.theme.bodyFont.size)
          .fontColor(this.displayMode === HOME_DISPLAY_MODE_SHOWCASE
            ? this.theme.cardBackground : this.theme.accent)
          .backgroundColor(this.displayMode === HOME_DISPLAY_MODE_SHOWCASE
            ? this.theme.accent : this.theme.accentBackground)
          .borderRadius(10)
          .onClick((): void => {
            this.setDisplayMode(HOME_DISPLAY_MODE_SHOWCASE);
          })
        Button($r('app.string.s_d46f82fdf0')) // 列表
          .fontSize(this.theme.bodyFont.size)
          .fontColor(this.displayMode === HOME_DISPLAY_MODE_LIST
            ? this.theme.cardBackground : this.theme.accent)
          .backgroundColor(this.displayMode === HOME_DISPLAY_MODE_LIST
            ? this.theme.accent : this.theme.accentBackground)
          .borderRadius(10)
          .onClick((): void => {
            this.setDisplayMode(HOME_DISPLAY_MODE_LIST);
          })
      }
      .justifyContent(FlexAlign.Center)

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
            this.getUIContext().getRouter().pushUrl({ url: 'pages/LocationDebug' });
          })
      }
      .justifyContent(FlexAlign.Center)

      Row({ space: 12 }) {
        Button('LetterDebug')
          .fontSize(this.theme.bodyFont.size)
          .fontColor(this.theme.accent)
          .backgroundColor(this.theme.accentBackground)
          .borderRadius(10)
          .onClick((): void => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/LetterDebug' });
          })
        Button('ToastDebug')
          .fontSize(this.theme.bodyFont.size)
          .fontColor(this.theme.accent)
          .backgroundColor(this.theme.accentBackground)
          .borderRadius(10)
          .onClick((): void => {
            const context = this.getUIContext().getHostContext();
            if (context !== undefined) {
              const message: string =
                context.resourceManager.getStringSync($r('app.string.s_d60bcc29e2').id);
              this.env.errors.present(message, ErrorToastKind.Error, 3000);
            }
          })
      }
      .justifyContent(FlexAlign.Center)

      // ③⑥ 换级定位 / 懒加载验证造数（脚手架，6.x 统一删）
      Row({ space: 12 }) {
        Button('Seed15')
          .fontSize(this.theme.bodyFont.size)
          .fontColor(this.theme.accent)
          .backgroundColor(this.theme.accentBackground)
          .borderRadius(10)
          .onClick((): void => {
            this.seedTestEntries();
          })
        Button('Clear15')
          .fontSize(this.theme.bodyFont.size)
          .fontColor(this.theme.accent)
          .backgroundColor(this.theme.accentBackground)
          .borderRadius(10)
          .onClick((): void => {
            this.clearTestEntries();
          })
      }
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  // ---- 换级（U06 R-HOME-09） ----

  /**
   * 换到 `next` 那一级，换完手指底下还是 `focusIndex` 那篇。
   * 两段式（iOS 同款坑）：先排好转场方向和缩放中心——要走的那一层得先按
   * 新方向重画一次，它的退场动画才对；下一帧再换级 + 定位（0.4s）。
   */
  private setZoom(next: number, focusIndex: number): void {
    if (next === this.zoom || next < ShowcaseZoomLevel.One
      || next > ShowcaseZoomLevel.SixtyFour) {
      return;
    }
    this.haptic();
    this.zoomToDenser = next > this.zoom;
    const anchor = quadSlotAnchor(focusIndex);
    this.anchorPercentX = Math.round(anchor[0] * 100);
    this.anchorPercentY = Math.round(anchor[1] * 100);
    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: 400, curve: Curve.FastOutSlowIn }, (): void => {
        if (next === ShowcaseZoomLevel.One) {
          this.singleIndex = Math.max(0, focusIndex);
        } else if (next === ShowcaseZoomLevel.Four) {
          this.quadIndex = Math.max(0, quadPageOf(focusIndex));
        } else {
          this.pendingFocusIndex = focusIndex;
        }
        this.zoom = next;
        AppPrefs.setShowcaseZoom(next);
      });
    }, 0);
  }

  /** 换级的转场：翻页两级以手指那一格为中心缩放进出（U06 R-HOME-09） */
  private pagerTransition(): TransitionEffect {
    const centerX = `${this.anchorPercentX}%`;
    const centerY = `${this.anchorPercentY}%`;
    const appearScale = this.zoomToDenser ? 1.5 : 0.6;
    const disappearScale = this.zoomToDenser ? 0.6 : 1.5;
    const appear = TransitionEffect.scale({
      x: appearScale, y: appearScale, centerX: centerX, centerY: centerY
    }).combine(TransitionEffect.OPACITY)
      .animation({ duration: 400, curve: Curve.FastOutSlowIn });
    const disappear = TransitionEffect.scale({
      x: disappearScale, y: disappearScale, centerX: centerX, centerY: centerY
    }).combine(TransitionEffect.OPACITY)
      .animation({ duration: 400, curve: Curve.FastOutSlowIn });
    return TransitionEffect.asymmetric(appear, disappear);
  }

  /** 宫格两级（16 ↔ 64）以顶边为中心缩放（宫格很长，从顶上缩放） */
  private gridTransition(): TransitionEffect {
    const appearScale = this.zoomToDenser ? 1.5 : 0.6;
    const disappearScale = this.zoomToDenser ? 0.6 : 1.5;
    const appear = TransitionEffect.scale({
      x: appearScale, y: appearScale, centerX: '50%', centerY: '0%'
    }).combine(TransitionEffect.OPACITY)
      .animation({ duration: 400, curve: Curve.FastOutSlowIn });
    const disappear = TransitionEffect.scale({
      x: disappearScale, y: disappearScale, centerX: '50%', centerY: '0%'
    }).combine(TransitionEffect.OPACITY)
      .animation({ duration: 400, curve: Curve.FastOutSlowIn });
    return TransitionEffect.asymmetric(appear, disappear);
  }

  /** 捏合中心（双指均值，窗口坐标系——与 componentUtils.windowOffset 一致） */
  private pinchCenterX(event: GestureEvent): number {
    const list = event.fingerList;
    if (list.length === 0) {
      return 0;
    }
    if (list.length === 1) {
      return list[0].globalX;
    }
    return (list[0].globalX + list[1].globalX) / 2;
  }

  private pinchCenterY(event: GestureEvent): number {
    const list = event.fingerList;
    if (list.length === 0) {
      return 0;
    }
    if (list.length === 1) {
      return list[0].globalY;
    }
    return (list[0].globalY + list[1].globalY) / 2;
  }

  /** 手指底下是哪篇：第 0 级是翻到的那篇；第 1 级看手指落在这一页的哪一格；第 2 / 3 级按版式算 */
  private focusIndexAt(globalX: number, globalY: number): number {
    const count = this.entries.length;
    if (count === 0) {
      return -1;
    }
    if (this.zoom === ShowcaseZoomLevel.One) {
      return Math.min(Math.max(0, this.singleIndex), count - 1);
    }
    if (this.zoom === ShowcaseZoomLevel.Four) {
      const rect = this.componentRect('showcaseQuadPager');
      if (rect === undefined) {
        return Math.min(quadPageStart(Math.max(0, this.quadIndex)), count - 1);
      }
      const slot = quadSlotAt(globalX - rect.x, globalY - rect.y, rect.width, rect.height);
      return quadEntryIndexAtSlot(quadPageStart(Math.max(0, this.quadIndex)), slot, count);
    }
    const rect = this.componentRect('showcaseOverviewList');
    if (rect === undefined) {
      return 0;
    }
    const months = overviewMonths(this.entries, this.appLanguage);
    const scrollOffset = Number(this.overviewScroller.currentOffset().yOffset);
    const localX = globalX - rect.x;
    // List 从页首下方开始（页首固定在外面），rect 内坐标 + 滚动量即内容坐标
    const contentY = (globalY - rect.y) + scrollOffset;
    const index = overviewEntryIndexAt(months, this.zoom, rect.width, localX, contentY);
    return index < 0 ? 0 : index;
  }

  /** 按组件 id 取它在窗口里的位置和大小（componentUtils）。
   * 实测（X6）getRectangleById 的 windowOffset/size 返回 px（与 uitest
   * dumpLayout 一致），手势坐标（fingerList）和 currentOffset 都是 vp，
   * 这里统一除 density 折成 vp，再进捏合换算 */
  private componentRect(id: string): RectVp | undefined {
    try {
      const density = Math.max(1, display.getDefaultDisplaySync().densityPixels);
      const info = this.getUIContext().getComponentUtils().getRectangleById(id);
      return new RectVp(
        Number(info.windowOffset.x) / density, Number(info.windowOffset.y) / density,
        Number(info.size.width) / density, Number(info.size.height) / density);
    } catch (err) {
      return undefined;
    }
  }

  /** 点卡片 / 格子：打开那篇（详情以 NavDestination 推入本 Tab 栈）。
   * 捏合中/刚松手 400ms 内不算点击——双指先抬一只、剩下那只快速离屏会被
   * 判成 tap（真机实锤的误触来源） */
  private openEntry(id: string): void {
    if (Date.now() - this.lastPinchAt < HomeView.pinchClickCooldownMs) {
      return;
    }
    this.navPathStack.pushPathByName('EntryDetail', id);
  }

  /** 展示方式切换（6.1 设置页就绪前的临时入口） */
  private setDisplayMode(mode: string): void {
    if (this.displayMode === mode) {
      return;
    }
    this.displayMode = mode;
    AppPrefs.setHomeDisplayMode(mode);
  }

  /**
   * 调试探造数（脚手架，6.x 统一删，③⑥ 验证用）：15 篇测试日记——
   * 本月往前 0~9 天 10 篇 + 上月 30~34 天 5 篇，16 列总览跨两个月份组、
   * 超屏可滚。id 定死（seed-test-01~15），已存在就跳过（幂等），
   * Clear15 负责删。
   */
  private async seedTestEntries(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const store = await AppDatabase.open(context);
      const existing = new Set<string>();
      for (const entry of await EntryRepository.fetchAllEntries(store)) {
        existing.add(entry.id);
      }
      const now = new Date();
      let inserted = 0;
      for (let i = 0; i < 15; i++) {
        // 0~9 = 本月今天往前；10~14 = 上月对应天（ getDate() 自动借位 ）
        const dayShift = i < 10 ? -i : -(20 + i);
        const id = `seed-test-${i < 9 ? '0' : ''}${i + 1}`;
        if (existing.has(id)) {
          continue;
        }
        const at = new Date(now.getFullYear(), now.getMonth(),
          now.getDate() + dayShift, 12, 0, 0).getTime();
        const entry = new JournalEntry(id, at, at, at);
        const day = new Date(at);
        const month = day.getMonth() + 1;
        entry.title = `测试日记 ${month}月${day.getDate()}日`;
        entry.content = '自动验证用测试日记（换级定位 / 懒加载），验完由 Clear15 删除。';
        entry.wordCount = entry.content.length;
        await EntryRepository.insertEntry(store, entry);
        inserted++;
      }
      hilog.info(DOMAIN, TAG, 'seed15 done, inserted: %{public}d', inserted);
      await this.loadEntries(context);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'seed15 failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 调试探清数（脚手架，6.x 统一删）：删掉 Seed15 那 15 篇测试日记 */
  private async clearTestEntries(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const store = await AppDatabase.open(context);
      for (let i = 1; i <= 15; i++) {
        const id = `seed-test-${i < 10 ? '0' : ''}${i}`;
        await EntryRepository.deleteEntry(store, id);
      }
      hilog.info(DOMAIN, TAG, 'clear15 done');
      await this.loadEntries(context);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'clear15 failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 换级一震（U06 R-HOME-09：soft 预设；强度档鸿蒙 vibrator 没有，记偏差） */
  private haptic(): void {
    const preset: vibrator.VibratePreset = { type: 'preset', effectId: 'haptic.effect.soft', count: 1 };
    vibrator.startVibration(preset, { usage: 'touch' }).catch((): void => {
      const fallback: vibrator.VibrateTime = { type: 'time', duration: 12 };
      vibrator.startVibration(fallback, { usage: 'touch' }).catch((): void => {
      });
    });
  }

  // ---- 共用 ----

  /** 组头：年月 + 吸顶背景（列表模式） */
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

  /** FAB 投影色：accent 30% 透明 */
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

  /** 磨砂玻璃片叠色：主题背景色 40% 半透明 */
  private frostedBarColor(): ResourceColor {
    const bg = this.theme.background;
    if (typeof bg === 'number') {
      return (bg & 0x00FFFFFF) | 0x66000000;
    }
    return bg;
  }
}
