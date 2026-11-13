/**
 * 翻页阅读器宿主页（10_BUILD_MANUAL.md 3.5）。对应 iOS
 * `Reader/DiaryReaderView.swift` + `PageCurlReaderView.swift`。
 *
 * - 原生 OpenGL 整页曲面：当前页与目标页纹理、主题纸背、透视和阴影
 * - 页中、页缘、上下角共用同一 progress；起手 y 只改变卷轴倾角，
 *   不再区分 Edge / Corner 两套渲染和提交规则
 * - 未翻起正面保持原图，翻起部分使用主题色曲面纸背 + 极淡原文透出，
 *   卷轴、自由边和透出页阴影同步跟随
 * - 首尾页越界只画浅卷轴，松手回弹，不换页、不露空白
 * - 松手动画：displaySync 真实帧驱动 + 临界阻尼弹簧，继承手势末速度，
 *   位置与速度都收敛才收尾；离页 / 重排时停止帧驱动并释放截图
 * - 折叠 / 展开 / 分屏：onAreaChange 防抖重排，按页锚点保持当前篇/页
 * - 几何 / 测量 / 分页共用一份（buildReaderPages + ReaderTextAdapter，
 *   R-READ-05 先算后画）；主题切换实时跟随（素笺 / 皮革 / 肯特 / 极夜）
 * - 翻页成立时轻震一下（vibrator soft，失败静默）；动画期间锁新手势
 * - 悬浮返回按钮（36 圆，安全区顶 + 8、左 16）：占系统导航栏那一条，
 *   与正文（安全区 + 56 起）互不重叠（iOS 2026-09-16 实机反馈教训）
 * - 路由参数：notebookId（'' = 全部日记）+ initialEntryId（目录点的那篇；
 *   空则从头读，R-READ-02）
 */
import { display, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { vibrator } from '@kit.SensorServiceKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import {
  STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP,
  STORAGE_KEY_HIDE_TAB_BAR
} from '../../services/ImmersiveChrome';
import { AppDatabase } from '../../data/Database';
import { EntryRepository } from '../../data/EntryRepository';
import { NotebookRepository } from '../../data/NotebookRepository';
import { bookReadingEntries } from '../../data/BookContentsLogic';
import { JournalEntry } from '../../models/JournalEntry';
import { Notebook } from '../../models/Notebook';
import { ContentBlock } from '../../models/ContentBlock';
import {
  ReaderGeometry,
  ReaderLayout,
  ReaderPage,
  ReaderPageAnchor,
  ReaderPageKind,
  buildReaderPages,
  indexOfPageAnchor,
  pageAnchorOf
} from '../../models/ReaderPages';
import { generateUuid } from '../../models/Uuid';
import { EyeFlipMachine } from '../../models/EyeFlipMachine';
import { EyeFlipTracker } from '../../services/EyeFlipTracker';
import { AppPrefs, PREF_KEY_EYE_INTRO_SHOWN } from '../../services/AppPrefs';
import { RichTextAppearance } from '../components/richtext/RichTextAppearance';
import { ReaderTextAdapter } from './ReaderTextAdapter';
import { NativeBookCurlView, NativeBookController } from './native/NativeBookCurlView';

const DOMAIN = 0x0000;
const TAG = 'DiaryReaderView';

/** 折叠 / 分屏尺寸变化后的重排防抖（ms）：避开折叠动画中间态 */
const RESIZE_DEBOUNCE_MS = 180;

@Builder
export function DiaryReaderBuilder() {
  DiaryReaderView()
}

@Component
export struct DiaryReaderView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeBottomVp: number = 0;
  @State private pages: ReaderPage[] = [];
  @State private currentIndex: number = 0;

  private navPathStack: NavPathStack = new NavPathStack();
  /** 藏栏前的安全区顶：藏栏后 avoidArea 归零、safeTopVp 变 0，
   * 悬浮返回 / 眼动按钮要用藏前值（aboutToAppear 在藏栏前缓存） */
  private preHideSafeTopVp: number = 0;
  /** 路由参数：'' = 全部日记 */
  private notebookId: string = '';
  /** 路由参数：目录点的那篇（空 = 从头读） */
  private initialEntryId: string = '';
  /** 屏幕几何（load 前用窄屏兜底值，pages 为空不渲染） */
  private geometry: ReaderGeometry = new ReaderGeometry(390, 844, 47, 34);
  private adapter: ReaderTextAdapter | undefined = undefined;
  private nativeBookController: NativeBookController = new NativeBookController();
  private density: number = 3.0;
  /** 这本书的日记（重排时按同一份数据重新分页，不再回库） */
  private bookEntries: JournalEntry[] = [];
  /** 容器实测尺寸（vp；0 = 还没量到，用 display 兜底） */
  private containerWidthVp: number = 0;
  private containerHeightVp: number = 0;
  private resizeTimer: number = -1;
  /** 末页无位置录音缓存（entryId → 块） */
  private looseAudioCache: Map<string, ContentBlock[]> = new Map<string, ContentBlock[]>();
  /** 眼动翻页：开关（会话级不持久化）、姿态状态机、前摄追踪器、预览 surface */
  @State private eyeModeOn: boolean = false;
  /** 引导提示页（首次开启时弹一次，华为阅读同款半模态） */
  @State private eyeIntroShow: boolean = false;
  private eyeMachine: EyeFlipMachine = new EyeFlipMachine();
  private eyeTracker: EyeFlipTracker | undefined = undefined;
  private eyeSurfaceController: XComponentController = new XComponentController();
  /** 姿态遥测计数（每 ~10 帧打一条 hilog） */
  private eyePitchFrameCount: number = 0;

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 翻页主体（居中页槽：大屏页宽封顶 420）
        Stack() {
          // 眼动翻页隐藏取景 surface：被上层不透明纸面整页盖住、不显示画面，
          // 但相机帧照常供给 faceDetector（PaperCameraView「相纸盖住取景器仍可抓帧」同款先例）
          if (this.eyeModeOn) {
            XComponent({ type: XComponentType.SURFACE, controller: this.eyeSurfaceController })
              .onLoad((): void => {
                this.onEyeSurfaceReady();
              })
              .width(160)
              .height(120)
              .position({ x: 0, y: 0 })
              .zIndex(99)
            // 只留 (0,0) 1×1 参与合成：surface 完全透明 / 被完全盖住会停止出帧；
            // 1px 肉眼不可见，但足以让相机预览持续产帧（pitch 实测有效）
            // 留左侧 1px 竖条可见（1×120）：surface 必须有一块真实可见区域才持续出帧
            // （实测：完全盖住/只留1px角点都会停帧）；竖条贴屏幕最左缘，肉眼不可见
            Column()
              .width(159)
              .height(120)
              .position({ x: 1, y: 0 })
              .zIndex(100)
              .backgroundColor(this.theme.background)
          }

          NativeBookCurlView({
            pages: this.pages,
            currentIndex: this.currentIndex,
            geometry: this.geometry,
            adapter: this.adapter,
            looseAudioBlocks: this.looseAudioBlocksAt(this.currentIndex),
            theme: this.theme,
            controller: this.nativeBookController,
            onPageCommit: (nextIndex: number): void => {
              this.currentIndex = nextIndex;
              this.haptic();
            }
          })
        }
        .width(this.pageWidthVp())
        .height(this.pageHeightVp())

        // 悬浮返回按钮：贴安全区顶 + 8、左 16（iOS 同款位置教训）
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textPrimary])
        }
        .width(36)
        .height(36)
        .padding(0)
        .backgroundColor(this.theme.accentBackground)
        .shadow({ radius: 3, color: 0x1F000000, offsetX: 0, offsetY: 1 })
        .margin({ top: this.chromeButtonTopVp() + 8, left: 16 })
        .onClick((): void => {
          this.navPathStack.pop();
        })

        // 眼动翻页开关（右上，与悬浮返回键同款 36 圆；华为阅读同款眼动翻页入口）
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph(this.eyeModeOn ? $r('sys.symbol.eye') : $r('sys.symbol.eye_slash'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textPrimary])
        }
        .width(36)
        .height(36)
        .padding(0)
        .backgroundColor(this.theme.accentBackground)
        .shadow({ radius: 3, color: 0x1F000000, offsetX: 0, offsetY: 1 })
        .position({ x: this.geometry.pageWidth - 52, y: this.chromeButtonTopVp() + 8 })
        .onClick((): void => {
          this.toggleEyeMode();
        })

        if (this.eyeModeOn) {
          // 底部提示（页码下方、安全区里，不与正文页码打架）
          Text($r('app.string.eye_flip_hint'))
            .fontSize(11)
            .fontColor(this.theme.textTertiary)
            .maxLines(1)
            .position({ x: '50%', y: '100%' })
            .markAnchor({ x: '50%', y: '100%' })
            .offset({ y: -Math.max(this.safeBottomVp - 6, 8) })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.background)
      // 折叠 / 展开 / 分屏：容器尺寸变了要重排（只量到就重分页，防止旧页宽错位）
      .onAreaChange((_oldArea: Area, area: Area): void => {
        if (typeof area.width === 'number' && typeof area.height === 'number') {
          this.onReaderAreaChanged(area.width, area.height);
        }
      })
      // 眼动翻页引导页（官方半模态组件）：首次开启时展示一次
      .bindSheet($$this.eyeIntroShow, this.eyeIntroSheetBuilder(), {
        height: SheetSize.FIT_CONTENT,
        showClose: false
      })
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.background)
    // 拦截系统侧滑返回：右缘手势区（实测 x ≥ ~1008）会吃掉真·屏角抓取
    // （角卷触点永远到不了 app）并误退阅读器；退出走悬浮返回键（R-READ-07），
    // navPathStack.pop() 不受本拦截影响（faqs-arkui-1117）
    .onBackPressed((): boolean => true)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      const raw = ctx.pathInfo.param as Record<string, Object> | undefined;
      if (raw !== undefined) {
        const notebookId = raw['notebookId'];
        if (typeof notebookId === 'string') {
          this.notebookId = notebookId;
        }
        const initialEntryId = raw['initialEntryId'];
        if (typeof initialEntryId === 'string') {
          this.initialEntryId = initialEntryId;
        }
      }
      this.load();
    })
  }

  aboutToAppear(): void {
    // 阅读器是沉浸整页：藏起悬浮胶囊 Tab 栏（barOverlap 层在
    // NavDestination 之上，居中页码会被胶囊盖住；CoverEditorView 同款先例）
    AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, true);
    // 藏系统状态栏：顶部角落划动曾被系统状态栏手势区拦截拉下控制中心
    // （oc1-3 实证）；华为阅读同款藏栏，藏后触摸直达 app。
    // 先缓存藏栏前的安全区顶（藏后 avoidArea 归零，悬浮按钮定位用藏前值）
    if (this.safeTopVp > 0) {
      this.preHideSafeTopVp = this.safeTopVp;
    }
    this.setReaderSystemBars(false);
  }

  aboutToDisappear(): void {
    AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, false);
    this.setReaderSystemBars(true);
    this.nativeBookController.cancel();
    if (this.resizeTimer >= 0) {
      clearTimeout(this.resizeTimer);
      this.resizeTimer = -1;
    }
    // 眼动追踪：停轮询 + 释放前摄（相机独占资源，页面消失必须放）
    this.stopEyeTracking();
  }

  /** 藏 / 还原系统状态栏（PaperCameraView.setSystemBarsForCamera 同款窗口接口） */
  private setReaderSystemBars(showStatus: boolean): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    window.getLastWindow(context).then((win: window.Window): void => {
      const names: Array<'status' | 'navigation'> =
        showStatus ? ['status', 'navigation'] : ['navigation'];
      win.setWindowSystemBarEnable(names).catch((): void => {
        // 设不上：不拦阅读
      });
    }).catch((): void => {
      // 取不到窗口：不拦阅读
    });
  }

  /** 悬浮按钮（返回 / 眼动）的顶部安全区：藏栏后 safeTopVp 归零，
   * 用藏栏前缓存；缓存与实时值都异常时兜底 47（真机典型状态栏高） */
  private chromeButtonTopVp(): number {
    if (this.preHideSafeTopVp > 0) {
      return this.preHideSafeTopVp;
    }
    if (this.safeTopVp > 0) {
      return this.safeTopVp;
    }
    return 47;
  }

  // ---- 装载 ----

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.density = ReaderTextAdapter.screenDensity();
    let screenW = 1080;
    let screenH = 2340;
    try {
      const screen = display.getDefaultDisplaySync();
      screenW = screen.width;
      screenH = screen.height;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getDisplaySync failed: %{public}s', JSON.stringify(err));
    }
    const ui = this.getUIContext();
    const screenWVp = this.containerWidthVp > 0 ? this.containerWidthVp : ui.px2vp(screenW);
    const screenHVp = this.containerHeightVp > 0 ? this.containerHeightVp : ui.px2vp(screenH);
    this.applyLayoutMetrics(screenWVp, screenHVp);

    try {
      const store = await AppDatabase.open(context);
      const allEntries = await EntryRepository.fetchAllEntries(store);
      let bookEntries: JournalEntry[];
      if (this.notebookId.length > 0) {
        const notebooks = await NotebookRepository.fetchAllNotebooks(store);
        const notebook = notebooks.find((nb: Notebook): boolean => nb.id === this.notebookId);
        bookEntries = bookReadingEntries(allEntries, notebook !== undefined ? notebook.name : '');
      } else {
        bookEntries = bookReadingEntries(allEntries, '');
      }
      if (bookEntries.length === 0) {
        this.navPathStack.pop(); // 空本子不进阅读器
        return;
      }
      this.bookEntries = bookEntries;
      this.prepareLooseAudio(bookEntries);
      // 取数期间可能已经量到真实容器尺寸（折叠机首帧），重建前再对齐一次
      this.applyLayoutMetrics(
        this.containerWidthVp > 0 ? this.containerWidthVp : screenWVp,
        this.containerHeightVp > 0 ? this.containerHeightVp : screenHVp);
      const anchor = this.initialEntryId.length > 0
        ? new ReaderPageAnchor(this.initialEntryId, 0, ReaderPageKind.Content)
        : undefined;
      this.rebuildPages(anchor);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'load reader failed: %{public}s', JSON.stringify(err));
      this.navPathStack.pop();
    }
  }

  /** 版式尺寸落地：几何、测量器、页槽像素宽高一次算好（load / 重排共用） */
  private applyLayoutMetrics(widthVp: number, heightVp: number): void {
    this.geometry = new ReaderGeometry(widthVp, heightVp, this.safeTopVp, this.safeBottomVp);
    this.adapter = new ReaderTextAdapter(RichTextAppearance.forTheme(this.theme), this.density);
  }

  /** 用当前几何重新分页；anchor 存在时保持原篇/页位置，重排后不断读 */
  private rebuildPages(anchor: ReaderPageAnchor | undefined): void {
    const adapter = this.adapter;
    if (adapter === undefined || this.bookEntries.length === 0) {
      return;
    }
    const pages = buildReaderPages(this.bookEntries, this.geometry, adapter, generateUuid);
    if (pages.length === 0) {
      return;
    }
    this.pages = pages;
    this.currentIndex = anchor !== undefined ? indexOfPageAnchor(pages, anchor) : 0;
  }

  /** 容器尺寸变化（折叠 / 展开 / 分屏）：防抖后重排，避开折叠动画中间态 */
  private onReaderAreaChanged(widthVp: number, heightVp: number): void {
    if (Math.abs(widthVp - this.containerWidthVp) < 1
      && Math.abs(heightVp - this.containerHeightVp) < 1) {
      return;
    }
    this.containerWidthVp = widthVp;
    this.containerHeightVp = heightVp;
    if (this.pages.length === 0) {
      return; // 首次量到尺寸：load 直接用它
    }
    if (this.resizeTimer >= 0) {
      clearTimeout(this.resizeTimer);
    }
    this.resizeTimer = setTimeout((): void => {
      this.resizeTimer = -1;
      this.relayoutForSize();
    }, RESIZE_DEBOUNCE_MS);
  }

  /** 按容器新尺寸重新分页，并尽量停回原来那一篇/那一页 */
  private relayoutForSize(): void {
    if (this.bookEntries.length === 0
      || this.containerWidthVp <= 0 || this.containerHeightVp <= 0) {
      return;
    }
    this.cancelFlipForRelayout();
    const anchor = pageAnchorOf(this.pages, this.currentIndex);
    this.applyLayoutMetrics(this.containerWidthVp, this.containerHeightVp);
    this.rebuildPages(anchor);
  }

  /** 重排前把翻页中状态收干净：定时器、画布、截图都释放，避免旧几何的帧继续画 */
  private cancelFlipForRelayout(): void {
    this.nativeBookController.cancel();
  }

  /** 每篇的末页录音（不占分页预算，iOS 同款）预建缓存 */
  private prepareLooseAudio(entries: JournalEntry[]): void {
    for (const entry of entries) {
      const loose = entry.looseAudioURLs;
      if (loose.length === 0) {
        continue;
      }
      const blocks: ContentBlock[] = [];
      for (const url of loose) {
        blocks.push(ContentBlock.makeAudio(generateUuid(), url));
      }
      this.looseAudioCache.set(entry.id, blocks);
    }
  }

  // ---- 页槽 ----

  private pageWidthVp(): number {
    return Math.min(this.geometry.pageWidth, ReaderLayout.maxPageWidth);
  }

  private pageHeightVp(): number {
    return this.geometry.pageHeight;
  }

  /** ForEach 槽位（单元素数组；key 带页号，页变了子树重建、成员跟着换新） */
  /** 某页要挂的末页录音：只在「本篇最后一页」出现（避免每页重复） */
  private looseAudioBlocksAt(idx: number): ContentBlock[] {
    if (idx < 0 || idx >= this.pages.length) {
      return [];
    }
    const page = this.pages[idx];
    if (page.pageIndex !== page.totalPages - 1) {
      return [];
    }
    const blocks = this.looseAudioCache.get(page.entry.id);
    return blocks !== undefined ? blocks : [];
  }

  /** 翻页成立时的轻震（vibrator 预设；机型没有该预设退 12ms 短震，再失败静默） */
  private haptic(): void {
    const preset: vibrator.VibratePreset = { type: 'preset', effectId: 'haptic.effect.soft', count: 1 };
    vibrator.startVibration(preset, { usage: 'touch' }).catch((): void => {
      const fallback: vibrator.VibrateTime = { type: 'time', duration: 12 };
      vibrator.startVibration(fallback, { usage: 'touch' }).catch((): void => {
      });
    });
  }

  // ---- 眼动翻页 ----

  /** 引导提示页（官方 bindSheet 半模态，华为阅读同款）：图标 + 标题 + 用法 + 隐私声明 + 双按钮 */
  @Builder
  private eyeIntroSheetBuilder() {
    Column() {
      SymbolGlyph($r('sys.symbol.eye'))
        .fontSize(32)
        .fontColor([this.theme.accent])
        .margin({ top: 30 })

      Text($r('app.string.eye_flip_intro_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.textPrimary)
        .margin({ top: 12 })

      Text($r('app.string.eye_flip_intro_usage'))
        .fontSize(14)
        .fontColor(this.theme.textSecondary)
        .textAlign(TextAlign.Center)
        .lineHeight(21)
        .margin({ top: 10, left: 32, right: 32 })

      Column({ space: 5 }) {
        Text($r('app.string.eye_flip_note_title'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.textSecondary)
        Text($r('app.string.eye_flip_note_1'))
          .fontSize(12)
          .fontColor(this.theme.textTertiary)
        Text($r('app.string.eye_flip_note_2'))
          .fontSize(12)
          .fontColor(this.theme.textTertiary)
        Text($r('app.string.eye_flip_note_3'))
          .fontSize(12)
          .fontColor(this.theme.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 32, right: 32 })
      .margin({ top: 14 })

      Text($r('app.string.eye_flip_intro_privacy'))
        .fontSize(12)
        .fontColor(this.theme.textTertiary)
        .textAlign(TextAlign.Center)
        .lineHeight(18)
        .margin({ top: 12, left: 32, right: 32 })

      Row({ space: 12 }) {
        Button($r('app.string.s_4d0b4688c7'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.textPrimary)
          .backgroundColor(this.theme.accentBackground)
          .layoutWeight(1)
          .height(44)
          .borderRadius(22)
          .onClick((): void => {
            this.eyeIntroShow = false;
          })

        Button($r('app.string.eye_flip_intro_enable'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(this.theme.accent)
          .layoutWeight(1)
          .height(44)
          .borderRadius(22)
          .onClick((): void => {
            this.enableEyeMode();
          })
      }
      .width('100%')
      .margin({ top: 24, bottom: 30, left: 24, right: 24 })
    }
    .width('100%')
    .backgroundColor(this.theme.background)
    .borderRadius({ topLeft: 24, topRight: 24 })
  }

  /** 开关：开 →（首次先弹引导页）申请相机权限后挂隐藏取景 surface（onLoad 起追踪器）；关 = 停追踪 */
  private async toggleEyeMode(): Promise<void> {
    if (this.eyeModeOn) {
      await this.stopEyeTracking();
      return;
    }
    if (!AppPrefs.getBool(PREF_KEY_EYE_INTRO_SHOWN, false)) {
      this.eyeIntroShow = true;
      return;
    }
    await this.enableEyeMode();
  }

  /** 引导页「开启」/ 非首次直接开启：申请权限 → 挂隐藏 surface */
  private async enableEyeMode(): Promise<void> {
    this.eyeIntroShow = false;
    AppPrefs.putBool(PREF_KEY_EYE_INTRO_SHOWN, true);
    const granted = await this.requestCameraPermission();
    if (!granted) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.s_6210f62fdd') });
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'toast failed: %{public}s', JSON.stringify(err));
      }
      return;
    }
    this.eyeMachine.reset();
    this.eyeModeOn = true;
  }

  private async stopEyeTracking(): Promise<void> {
    this.eyeModeOn = false;
    this.eyeMachine.reset();
    const tracker = this.eyeTracker;
    this.eyeTracker = undefined;
    if (tracker !== undefined) {
      await tracker.stop();
    }
  }

  /** 相机权限（PaperCameraView.requestCameraPermissions 同款，只提 CAMERA） */
  private async requestCameraPermission(): Promise<boolean> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) {
      return false;
    }
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context,
        ['ohos.permission.CAMERA']);
      for (let i = 0; i < result.permissions.length; i++) {
        if (result.permissions[i] === 'ohos.permission.CAMERA' && result.authResults[i] === 0) {
          return true;
        }
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'request camera permission failed: %{public}s', JSON.stringify(err));
    }
    return false;
  }

  /** 预览泡 surface 就绪（XComponent onLoad）：装配前摄会话 + 起轮询 */
  private onEyeSurfaceReady(): void {
    if (!this.eyeModeOn || this.eyeTracker !== undefined) {
      return;
    }
    const surfaceId = this.eyeSurfaceController.getXComponentSurfaceId();
    if (surfaceId.length === 0) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) {
      return;
    }
    const tracker = new EyeFlipTracker(context, (pitch: number | undefined): void => {
      this.onEyePitch(pitch);
    });
    tracker.start(surfaceId).then((ok: boolean): void => {
      if (ok && this.eyeModeOn) {
        this.eyeTracker = tracker;
        hilog.info(DOMAIN, TAG, 'eye tracking started');
      } else {
        // 前摄起不来 / 期间被关：回滚开关 + 用户可见失败提示
        tracker.stop();
        this.eyeModeOn = false;
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.eye_flip_unavailable')
        });
      }
    });
  }

  /** 每帧检测结果：页面忙（手势 / 补帧 / 已是末页）只清计时不触发 */
  private onEyePitch(pitch: number | undefined): void {
    if (!this.eyeModeOn) {
      return;
    }
    // 姿态遥测（每 ~10 帧一条 ≈ 3.5s）：装机核对 faceDetector 真在出数
    this.eyePitchFrameCount++;
    if (this.eyePitchFrameCount % 10 === 0) {
      hilog.info(DOMAIN, TAG, 'eye pitch: %{public}s, baseline: %{public}s',
        pitch === undefined ? 'none' : pitch.toFixed(1),
        this.eyeMachine.baseline === undefined ? 'none' : this.eyeMachine.baseline.toFixed(1));
    }
    const busy = this.nativeBookController.isAnimating()
      || this.currentIndex + 1 >= this.pages.length;
    if (busy) {
      this.eyeMachine.pause();
      return;
    }
    if (this.eyeMachine.feed(pitch, Date.now())) {
      hilog.info(DOMAIN, TAG, 'eye flip trigger: index %{public}d -> %{public}d',
        this.currentIndex, this.currentIndex + 1);
      this.flipForwardByEye();
    }
  }

  /** 程序化前向翻页：页缘虚拟抓取（折缝从平出发），与手势同一套 Edge 管线 */
  private flipForwardByEye(): void {
    if (this.currentIndex + 1 >= this.pages.length) {
      return;
    }
    this.nativeBookController.forward();
  }
}
