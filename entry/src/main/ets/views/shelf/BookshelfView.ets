/**
 * 书架（10_BUILD_MANUAL.md 3.1 + 3.2，R-BOOK-01~07）。对应 iOS `Views/Home/BookshelfView.swift`
 * + `Shelf/ShelfGridView.swift`（摆书 + 长按拿书拖动换位）+ `Shelf/ShelfDecor.swift`（书架板）。
 *
 * 3.1（R-BOOK-01~05）：
 * - 三列书架板（iOS 参数：列距 18 / 行距 38 / 顶距 20 / 页边 22 / 封面比例 0.73）；
 *   板子画在书底下；第一格「全部日记」固定象牙白亚麻，没有「…」菜单
 * - 顺序 = sortOrder（相同按 createdAt，R-BOOK-05）；末尾永远有「新建」（R-BOOK-02）
 * - 新建弹窗：名称 + 撞名当场提示（R-BOOK-03）；默认色墨绿，一律排书架最后
 * - 点书 → 日记本主页是 3.3 的卡片，本卡留打开钩子不跳转
 * - 入场：书架第一次出现时一本本依次落下（index × 0.06s 错峰）
 *
 * 3.2（R-BOOK-06，动画参数在 iOS `ShelfGridView.swift` 文件头）：
 * 1. 长按 0.35s 拿起：同轴转过去 32° 露出书脊（看得到厚度）、轻轻浮起（略放大 + 影子变深）
 * 2. 拖着走：原位空着（像真的抽走了一本），**其余书一动不动**（不晃、不让位、不出角标）
 * 3. 拖到上下边缘（70vp 带）自动滚，越靠边越快（2~12 / 16ms 拍）
 * 4. 松手：先落进离手最近的那格，**这时**其余书才轻轻挪开让位；只写变了 sortOrder
 * 5. 落定后再同轴转回正面
 *
 * 实现要点（真机实证，详见 09_OPEN_QUESTIONS.md 3.2 条目）：
 * - 书全部绝对定位（ForEach 键 = slot key）：松手重排时组件不重建、只有 position 变，
 *   animateTo 事务里其余书才会平滑让位；入场动画放内层，position 归外层管，互不干扰
 * - 浮书常驻挂载（透明度 0.01 仍参与栅格化）：首次挂载渲染管线要现编译（实测 ~367ms），
 *   页面加载时就挂出来，第一次拿起才不卡；不参与命中测试（Transparent，None 会吞触摸）
 * - 跟手 = 逐帧把**同一条** springMotion 弹簧 retarget 到指位（官方跟手范式）：
 *   渲染服务侧的物理弹簧，中途换别的曲线改写会孤儿化 RS 动画；springMotion 不回调完成，
 *   完成链按动画时长用定时兜底
 * - 转角不交给动画系统：投影矩阵不能插值（插值的是角度，每帧重算，见 ShelfBook3DView），
 *   用 16ms 定时逐帧驱动
 * - LTPO 深闲置（约几十秒不动）触摸不唤醒低功耗链路，第一帧会冻住：触地先 poke 一帧
 * - 松手兜底走格子的 onTouch（Up/Cancel → dropBook）：顺序组合手势里只有最后一个
 *   手势能响应 onActionEnd（官方文档），只长按没拖就松手时谁的 end 都不回调，
 *   书会永远浮着（真机实证）；拖动中的格子用 opacity 0 隐藏而不是 Visibility.Hidden，
 *   免得组件退出命中测试时把进行中的触摸流掐断
 *
 * 数据刷新与 HomeView 同一信号：Index.onPageShow bump `homeReloadTick`
 * （RDB 无观察机制，用显式信号补齐，对应 iOS `@Query` 的自动响应）。
 */
import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vibrator } from '@kit.SensorServiceKit';
import {
  BookColor,
  CoverLayout,
  Notebook,
  cleanedName,
  isNameTaken,
  nextSortOrder
} from '../../models/Notebook';
import { generateUuid } from '../../models/Uuid';
import { bookBoxLiftAngle } from '../../models/BookBoxProjection';
import {
  autoScrollSpeed,
  changedSortOrders,
  clampedScrollOffset,
  easeInOutCubic,
  moveItem,
  nearestIndex
} from '../../models/ShelfDrag';
import { BOOK_DETAIL_ALL_ENTRIES_PARAM } from './BookDetailView';
import { AppDatabase } from '../../data/Database';
import {
  NotebookRepository,
  ShelfEntryCounts
} from '../../data/NotebookRepository';
import {
  STORAGE_KEY_HOME_RELOAD_TICK
} from '../../data/HomeLogic';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { ErrorToastKind } from '../../environment/ErrorPresenter';
import {
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP,
  STORAGE_KEY_SAFE_AREA_TOP_VP
} from '../../services/ImmersiveChrome';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import { ShelfBookView } from './BookCoverView';
import { ShelfBook3DView } from './ShelfBook3DView';
import { BookshelfCreateDialog } from './BookshelfCreateDialog';

const DOMAIN = 0x0000;
const TAG = 'BookshelfView';

/** 布局常量（iOS `ShelfGridView`，pt → vp 1:1） */
/** 列数（R-BOOK-04：书架 3 列） */
const COLUMN_COUNT: number = 3;

// 宽屏（折叠展开态 md 断点 ≥600vp）列数：书尺寸回到接近外屏密度，
// 对齐 Apple Books iPad 大屏增列心智（而非 3 列巨书铺满全宽）
const COLUMN_COUNT_WIDE: number = 6;

// 官方断点 sm/md 分界（vp）：窗口宽 ≥600 触发宽屏布局
const BREAKPOINT_MD_VP: number = 600;
/** 列间距 */
const COLUMN_SPACING: number = 18;
/** 行距（书底到下一排书顶；含书架板前沿） */
const ROW_SPACING: number = 38;
/** 书架板在书底下探出的部分（书底压在板面中间偏后） */
const PLANK_DROP: number = 14;
/** 页边距 */
const SHELF_MARGIN: number = 22;
/** 首排离标题的距离 */
const TOP_INSET: number = 20;
/** 封面宽高比 */
const COVER_ASPECT: number = 0.73;
/** 书口宽度（与 ShelfBookView 一致） */
const PAGE_EDGE: number = 5;

// ---- 拿书 / 拖动（iOS `ShelfGridView` 文件头，pt/ms → vp/ms 1:1） ----

/** 拿起时转过去的角度：32° 露出书脊又不至于转得太夸张 */
const LIFT_DEGREES: number = 32;
/** 长按多久拿起：比系统默认略长，滑动浏览不误触 */
const PRESS_DURATION_MS: number = 350;
/** 拿起（转过去 + 浮起），iOS liftAnimation .smooth(0.45) */
const LIFT_DURATION_MS: number = 450;
/** 落位（其余书让开），iOS settleAnimation .smooth(0.42) */
const SETTLE_DURATION_MS: number = 420;
/** 转回正面，iOS turnBackAnimation .smooth(0.5) */
const TURN_BACK_DURATION_MS: number = 500;
/** 落位 420ms 定长走完 + 余量后接着转回（springMotion / onFinish 不可靠，定时兜底） */
const SETTLE_CHAIN_DELAY_MS: number = 450;
/** 转回帧动画走完的余量，之后才收摊换回格子里的书 */
const TURN_DONE_EXTRA_MS: number = 50;
/** 自动滚 16ms 一拍（iOS Task.sleep 16ms） */
const AUTO_SCROLL_TICK_MS: number = 16;
/** 转角帧动画的拍长 */
const ANGLE_TICK_MS: number = 16;

/** 跟手弹簧：很短的平滑，拖起来不生硬，又不至于明显拖在手指后面
 * （iOS interactiveSpring(response: 0.2, dampingFraction: 0.88)）。
 * 拖动全程（跟手 + 自动滚）用**同一个实例**逐帧 retarget —— 渲染服务侧的物理弹簧，
 * 换实例 / 换曲线改写会孤儿化之前的动画（松手落位改定长曲线是例外：跟随已结束） */
const FOLLOW_SPRING = curves.springMotion(0.2, 0.88);

/** 一个格子：全部日记 / 某本书 / 新建 */
class ShelfSlot {
  readonly kind: string;
  readonly notebook: Notebook | undefined;
  readonly key: string;

  constructor(kind: string, notebook: Notebook | undefined, key: string) {
    this.kind = kind;
    this.notebook = notebook;
    this.key = key;
  }
}

@Component
export struct BookshelfView {
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  /** 主页重查信号（与 HomeView 共用）：页面重新可见时 +1 */
  @StorageProp(STORAGE_KEY_HOME_RELOAD_TICK) @Watch('onReloadTickChange')
  homeReloadTick: number = 0;
  @State private notebooks: Notebook[] = [];
  @State private counts: ShelfEntryCounts | undefined = undefined;
  @State private showCreate: boolean = false;
  /** 内容区宽（vp），格子和板子的几何全由它推 */
  @State private contentWidthVp: number = 0;
  /** Scroll 视口高（vp）：内容撑到视口高，短内容才不会被 Scroll 默认居中（faqs-arkui-725） */
  @State private viewportHeightVp: number = 0;
  /** 滚动内容总高（vp）：自动滚的 maxScroll 用 */
  @State private contentHeightVp: number = 0;
  /** 入场动画开关（首帧 false，下一拍翻 true 触发逐本落下） */
  @State private appeared: boolean = false;
  // ---- 3.2 拿书 / 拖动状态 ----
  /** 本地顺序（notebook id）。拖动过程中不变，松手那一刻才改（其余书这时才动） */
  @State private order: string[] = [];
  /** 拿着的书（含落位 / 转回中）；'' = 没拿书 */
  @State private dragId: string = '';
  /** 已松手，正在落位 / 转回（这时不再跟手） */
  @State private settling: boolean = false;
  /** 浮书中心（书架内容坐标，随内容一起滚） */
  @State private dragX: number = 0;
  @State private dragY: number = 0;
  /** 浮起（略放大 1.04 + 影子变深） */
  @State private lifted: boolean = false;
  /** 浮书转角（弧度）：16ms 定时逐帧驱动（投影矩阵不能插值） */
  @State private bookAngleRad: number = 0;
  /** LTPO poke 用：触地抖一下透明度里一个看不见的小数，强制出一帧真实渲染 */
  @State private pokeTick: number = 0;

  private scroller: Scroller = new Scroller();
  /** Scroll 视口在窗口坐标里的 y（vp）：手指窗口坐标 − 它 = 视口内坐标 */
  private viewportGlobalYVp: number = 0;
  /** 拿起那一刻的顺序（落库判「真变了」用） */
  private orderAtLift: string[] = [];
  /** 拿起那一刻浮书中心（= 原格中心）；拖动目标 = 它 + pan 偏移 + 自动滚累计 */
  private liftBaseX: number = 0;
  private liftBaseY: number = 0;
  private panX: number = 0;
  private panY: number = 0;
  /** 自动滚累计（vp）：手指不动、内容在动，书在内容坐标里要跟着挪才会留在手指下 */
  private scrollAccum: number = 0;
  private autoScrollSpeed: number = 0;
  private autoScrollTimer: number = -1;
  private angleTimer: number = -1;
  private settleTimer: number = -1;
  private turnDoneTimer: number = -1;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      this.load(context);
    }
    // 下一拍再落书：先以隐藏 + 下移 20vp 挂出来，再开始动画
    setTimeout((): void => {
      this.appeared = true;
    }, 50);
  }

  /** 离开书架页立刻收摊，不做动画（iOS onDisappear resetImmediately） */
  aboutToDisappear(): void {
    this.resetDrag();
  }

  /** 点书 → 日记本主页（3.3）：Tab 内 Navigation 栈（系统路由表），
   *  底部 Tab 栏保留可见，对齐 iOS push（HomeView 同款范式） */
  private navPathStack: NavPathStack = new NavPathStack();

  build() {
    Navigation(this.navPathStack) {
    Stack() {
      Scroll(this.scroller) {
        // 量到尺寸才画整棵内容树：短内容首帧会被 Scroll 居中排布（见上），
        // 空白一帧换稳定顶对齐，避免冷启闪「标题悬在屏幕中央」
        if (this.contentWidthVp > 0) {
          Column() {
            // 顶部小标题「日记本」（iOS 工具栏 principal 同款：labelFont / 次要色 / 宽字距）。
            // 沉浸窗口下 Scroll 内容槽原点是窗口顶（y=0，直穿状态栏区），
            // 避让必须自己做：safeAreaTopVp 把标题压回状态栏下方，再留 12vp 小间隙
            Row() {
              Text($r('app.string.s_a3b90b392b'))
                .fontSize(this.theme.labelFont.size)
                .fontWeight(this.theme.labelFont.weight)
                .fontFamily(this.theme.labelFont.family)
                .fontColor(this.theme.textSecondary)
                .letterSpacing(this.theme.letterSpacingWide)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .margin({ top: this.safeAreaTopVp + 12 })

            // 书架：书全部绝对定位（键 = slot key），松手重排时组件不重建、
            // 只有 position 变 —— animateTo 事务里其余书才会平滑让位；
            // 板子垫在书底下；浮书常驻，最后压栈在最上层
            Stack({ alignContent: Alignment.TopStart }) {
              this.planks()
              ForEach(this.displaySlots(), (slot: ShelfSlot, slotIndex: number) => {
                this.slotView(slot, slotIndex)
              }, (slot: ShelfSlot): string => slot.key)
              this.floatingBook()
            }
            .width(this.contentWidthVp)
            .height(this.shelfHeight())
            .margin({ top: TOP_INSET })

            // 底部留白（iOS padding(.bottom, 60)）+ 底部安全区
            Column()
              .height(60 + this.safeAreaBottomVp)
              .width('100%')
          }
          .width('100%')
          .padding({ left: SHELF_MARGIN, right: SHELF_MARGIN })
          .alignItems(HorizontalAlign.Start)
          .constraintSize({ minHeight: this.viewportHeightVp })
          .onAreaChange((_oldArea: Area, newArea: Area): void => {
            const h: Length = newArea.height;
            if (typeof h === 'number') {
              this.contentHeightVp = h;
            }
          })
        }
      }
      .scrollBar(BarState.Off)
      // iOS alwaysBounce：内容不满一屏时也保留弹簧回弹（果冻感），HomeView 同款
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        // 量 Scroll 自身：宽推格子几何，高撑内容防居中；折叠/展开切换时同步重算
        const w: Length = newArea.width;
        const h: Length = newArea.height;
        this.contentWidthVp = (typeof w === 'number' ? w : 0) - 2 * SHELF_MARGIN;
        if (typeof h === 'number') {
          this.viewportHeightVp = h;
        }
        // 视口在窗口里的 y（自动滚边缘带用：手指窗口坐标 − 它 = 视口内坐标）
        const gy: Length | undefined = newArea.globalPosition.y;
        if (typeof gy === 'number') {
          this.viewportGlobalYVp = gy;
        }
        // 拖动中窗口几何变了（折屏/转屏）：格子尺寸全变，就地收摊不做动画，下次再拖
        if (this.dragId !== '' && typeof w === 'number' && typeof _oldArea.width === 'number'
          && Math.abs(_oldArea.width - w) > 0.5) {
          this.resetDrag();
        }
      })

      // 新建日记本弹窗（撞名判定在弹窗内当场提示）
      if (this.showCreate) {
        BookshelfCreateDialog({
          existingNames: this.notebookNames(),
          onCancel: (): void => {
            this.showCreate = false;
          },
          onCreate: (name: string): void => {
            this.createNotebook(name);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
    // LTPO 深闲置时触摸不唤醒低功耗链路（第一帧会冻住），触地先提交一帧真实渲染把它踹醒
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.pokeTick = this.pokeTick > 0.05 ? 0 : 0.1;
      }
    })
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
  }

  // ---- 摆书（3.1 绝对定位版 + 3.2 手势） ----

  /** 书架板：板面（surfaceBackground）+ 前沿（border → borderAccent 渐变）。
   *  一排一块，延展到屏幕两端（负偏移抵掉内容列页边距），位置由格子行推算 */
  @Builder
  private planks() {
    ForEach(this.plankRows(), (rowIndex: number) => {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          Column()
            .width('100%')
            .height(7)
            .backgroundColor(this.theme.surfaceBackground)
          Column()
            .width('100%')
            .height(9)
            .linearGradient({
              angle: 180,
              colors: [[this.theme.border, 0], [this.theme.borderAccent, 1]] as [ResourceColor, number][]
            })
        }
        .width('100%')
        .height('100%')
        .borderRadius(1.5)
        .clip(true)
        // 板面与前沿交界的一道高光（深色主题弱一档）
        Row()
          .width('100%')
          .height(0.5)
          .backgroundColor(Color.White)
          .opacity(this.isDarkTheme() ? 0.08 : 0.6)
          .position({ x: 0, y: 6.5 })
      }
      .width(this.contentWidthVp + SHELF_MARGIN * 2)
      .height(16)
      .position({
        x: -SHELF_MARGIN,
        y: this.slotY(rowIndex * this.columnCount()) + this.cellHeight() - 2
      })
      .shadow({
        radius: 7,
        color: this.isDarkTheme() ? '#66000000' : '#24000000',
        offsetX: 0,
        offsetY: 6
      })
    }, (rowIndex: number): string => `plank-${rowIndex}`)
  }

  /**
   * 一个格子。外层管 position / 原位隐藏 / 手势，内层管入场动画
   * （两层分开：入场 .animation 只认内层属性，落位时外层 position 才能按
   * animateTo 的事务走，不会被入场的 400ms + 错峰延迟劫走）。
   */
  @Builder
  private slotView(slot: ShelfSlot, slotIndex: number) {
    Stack() {
      Stack() {
        if (slot.kind === 'all') {
          // 全部日记（R-BOOK-04：固定第一格象牙白，不是库记录，不能拖）
          ShelfBookView({
            name: this.allEntriesName(),
            entryCount: this.totalCount(),
            color: BookColor.Ivory,
            coverPhotoFilename: '',
            layout: CoverLayout.FullBleed,
            bookWidthVp: this.cellWidth()
          })
          .onClick((): void => {
            if (this.dragId === '') {
              this.openAllEntries();
            }
          })
        } else if (slot.kind === 'book' && slot.notebook !== undefined) {
          Stack() {
            ShelfBookView({
              name: slot.notebook.name,
              entryCount: this.countFor(slot.notebook),
              color: slot.notebook.bookColor,
              coverPhotoFilename: slot.notebook.coverPhotoFilename ?? '',
              layout: slot.notebook.coverLayout,
              bookWidthVp: this.cellWidth()
            })
          }
          .onClick((): void => {
            if (this.dragId === '') {
              this.openNotebook(slot);
            }
          })
          .gesture(
            // 长按拿起、接着拖动（R-BOOK-06 五阶段）：顺序组合 —— 按够 350ms 才解锁
            // 拖动；按不够就挪开 → 组合手势失败，Scroll 的滚动手势接手
            //（体感和相册 / 桌面一致）
            GestureGroup(GestureMode.Sequence,
              LongPressGesture({ repeat: false, duration: PRESS_DURATION_MS })
                .onAction((): void => {
                  this.liftBook(slot);
                })
                .onActionEnd((): void => {
                  // 保险丝：顺序组合手势里这条正常不回调（只有最后一个手势能响应
                  // onActionEnd；松手兜底在格子 onTouch 里）；个别机型若真回调了，
                  // dropBook 幂等，不亏
                  this.dropBook();
                }),
              PanGesture({ fingers: 1, distance: 1 })
                .onActionUpdate((event: GestureEvent): void => {
                  this.moveBook(event);
                })
                .onActionEnd((): void => {
                  this.dropBook();
                })
                .onActionCancel((): void => {
                  this.dropBook();
                })
            )
          )
        } else {
          // 新建（R-BOOK-02：入口永远在；与书同宽同比例，虚线框对齐封面）
          Stack({ alignContent: Alignment.Start }) {
            Column({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(20)
                .fontColor([this.theme.textTertiary])
              Text($r('app.string.s_0cda8d1c71'))
                .fontSize(11)
                .fontColor(this.theme.textTertiary)
            }
            .width(this.cellWidth() - PAGE_EDGE)
            .aspectRatio(COVER_ASPECT)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(4)
            .border({ width: 1, color: this.theme.border, style: BorderStyle.Dashed })
            .onClick((): void => {
              this.showCreate = true;
            })
          }
          .width(this.cellWidth())
          .height(this.cellHeight())
        }
      }
      .opacity(this.appeared ? 1 : 0)
      .translate({ y: this.appeared ? 0 : 20 })
      .animation({
        duration: 400,
        curve: Curve.EaseOut,
        delay: slotIndex * 60
      })
    }
    .width(this.cellWidth())
    .height(this.cellHeight())
    .position({ x: this.slotX(slotIndex), y: this.slotY(slotIndex) })
    // 拿在手里的那本：原位空着（像真的从架子上抽走了一本），书本身画在浮书层。
    // 用 opacity 0 而不是 Visibility.Hidden：Hidden 会让组件退出命中测试，
    // 拿起那一刻正在进行的触摸流有断在半路的风险（pan / onTouch 收不到后续事件，
    // 书卡在浮起状态收不回去）；opacity 0 视觉等效，触摸流全程不断
    .opacity(this.dragId === slot.key ? 0 : 1)
    // 兜底网：顺序组合手势里只有最后一个手势能响应 onActionEnd（官方 GestureGroup
    // 文档明示）。只长按拿起、没拖就松手时 PanGesture 没识别过 → 谁的 end 都不回调
    // （真机实证：书永远浮着）。用自己的 onTouch 盯手指抬起 / 触摸取消补上这条路；
    // 真拖动时 pan.onActionEnd 也会来，dropBook 幂等，先到先放下
    .onTouch((event: TouchEvent): void => {
      if ((event.type === TouchType.Up || event.type === TouchType.Cancel)
        && this.dragId === slot.key && !this.settling) {
        hilog.debug(DOMAIN, TAG, 'DBG slot onTouch %{public}s key=%{public}s',
          event.type === TouchType.Up ? 'Up' : 'Cancel', slot.key);
        this.dropBook();
      }
    })
  }

  /**
   * 拿在手里的书：常驻挂载（idle 透明度 0.01 仍参与栅格化，第一次拿起不现编译
   * 渲染管线）；不参与命中测试（Transparent；None 实测会吞触摸）。
   * 拿起时略放大 + 影子变深（lifted），位置跟手弹簧驱动。
   */
  @Builder
  private floatingBook() {
    Stack() {
      ShelfBook3DView({
        name: this.draggedName(),
        entryCount: this.draggedCount(),
        color: this.draggedColor(),
        coverPhotoFilename: this.draggedPhoto(),
        layout: this.draggedLayout(),
        bookWidthVp: this.cellWidth(),
        angleRad: this.bookAngleRad
      })
    }
    .width(this.cellWidth())
    .height(this.cellHeight())
    .position({
      x: this.dragX - this.cellWidth() / 2,
      y: this.dragY - this.cellHeight() / 2
    })
    .scale({ x: this.lifted ? 1.04 : 1, y: this.lifted ? 1.04 : 1 })
    .shadow({
      radius: this.lifted ? 16 : 0,
      color: '#38000000',
      offsetX: 0,
      offsetY: this.lifted ? 12 : 0
    })
    .opacity(this.dragId !== '' ? 1 : 0.01 + this.pokeTick)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // ---- 拿起 / 拖动 / 放下（R-BOOK-06 五阶段） ----

  /** 长按成立：拿起 —— 同轴转过去（露出书脊见厚度）+ 浮起，原位空着 */
  private liftBook(slot: ShelfSlot): void {
    if (this.dragId !== '' || slot.notebook === undefined) {
      return;
    }
    const orderIndex = this.order.indexOf(slot.key);
    if (orderIndex < 0) {
      return;
    }
    this.orderAtLift = this.order.slice();
    this.liftBaseX = this.slotCenterX(orderIndex + 1);
    this.liftBaseY = this.slotCenterY(orderIndex + 1);
    this.dragX = this.liftBaseX;
    this.dragY = this.liftBaseY;
    this.panX = 0;
    this.panY = 0;
    this.scrollAccum = 0;
    this.settling = false;
    this.dragId = slot.key;
    this.haptic();
    hilog.debug(DOMAIN, TAG,
      'DBG liftBook key=%{public}s base=%{public}s targetAngle=%{public}s',
      slot.key, JSON.stringify([this.liftBaseX, this.liftBaseY]),
      String(Math.round(bookBoxLiftAngle(LIFT_DEGREES) * 1000) / 1000));
    // 浮起（略放大 + 影子变深）与转角同一拍开始；转角不进动画系统，16ms 定时逐帧驱动
    this.getUIContext().animateTo({ duration: LIFT_DURATION_MS, curve: Curve.EaseInOut }, (): void => {
      this.lifted = true;
    });
    this.animateAngle(bookBoxLiftAngle(LIFT_DEGREES), LIFT_DURATION_MS);
  }

  /** 拖着走：其余书一动不动；书跟手（同一条弹簧逐帧 retarget）；边缘带自动滚 */
  private moveBook(event: GestureEvent): void {
    if (this.dragId === '' || this.settling) {
      return;
    }
    hilog.debug(DOMAIN, TAG, 'DBG moveBook off=%{public}s accum=%{public}s',
      JSON.stringify([Math.round(event.offsetX), Math.round(event.offsetY)]),
      String(Math.round(this.scrollAccum)));
    this.panX = event.offsetX;
    this.panY = event.offsetY;
    this.getUIContext().animateTo({ curve: FOLLOW_SPRING }, (): void => {
      this.dragX = this.liftBaseX + this.panX;
      this.dragY = this.liftBaseY + this.panY + this.scrollAccum;
    });
    // GestureEvent 没有 globalY；手指窗口坐标在 fingerList 里（FingerInfo.globalY）
    if (event.fingerList.length > 0) {
      this.updateAutoScroll(event.fingerList[0].globalY - this.viewportGlobalYVp);
    }
  }

  /** 松手：先落位（其余书这时才让开），落定后再同轴转回正面；顺序真变了才落库 */
  private dropBook(): void {
    if (this.dragId === '' || this.settling) {
      hilog.debug(DOMAIN, TAG,
        'DBG dropBook SKIP dragId=%{public}s settling=%{public}s', this.dragId, String(this.settling));
      return;
    }
    this.stopAutoScroll();
    this.settling = true;
    const from = this.order.indexOf(this.dragId);
    const centersX: number[] = [];
    const centersY: number[] = [];
    for (let i = 0; i < this.order.length; i++) {
      centersX.push(this.slotCenterX(i + 1));
      centersY.push(this.slotCenterY(i + 1));
    }
    const to = nearestIndex(centersX, centersY, this.dragX, this.dragY);
    if (from < 0 || to < 0) {
      this.resetDrag();
      return;
    }
    this.haptic();
    // 落位事务（iOS drop 的单个 withAnimation(settleAnimation)）：顺序变了其余书才让位
    // （只有 position 变，组件不重建）；浮书滑向落点用同一条 .smooth(0.42) 平滑曲线，
    // 不再用跟手弹簧——跟随已结束，孤儿化旧 RS 弹簧安全，且定长无过冲，与 iOS 一致
    this.getUIContext().animateTo({ duration: SETTLE_DURATION_MS, curve: Curve.EaseInOut }, (): void => {
      if (to !== from) {
        this.order = moveItem(this.order, from, to);
      }
      this.dragX = this.slotCenterX(to + 1);
      this.dragY = this.slotCenterY(to + 1);
      this.lifted = false;
    });
    // 完成链：落位 420ms 定长走完 → 转回 ~500ms → 收摊换回格子里的书
    // （iOS completion 链；onFinish 被打断不回调，定时兜底）
    this.settleTimer = setTimeout((): void => {
      hilog.debug(DOMAIN, TAG, 'DBG settleTimer fired angle=%{public}s', String(Math.round(this.bookAngleRad * 1000) / 1000));
      this.animateAngle(0, TURN_BACK_DURATION_MS);
      this.turnDoneTimer = setTimeout((): void => {
        hilog.debug(DOMAIN, TAG, 'DBG turnDoneTimer fired angle=%{public}s', String(Math.round(this.bookAngleRad * 1000) / 1000));
        this.finishDrag();
        this.persistOrder();
      }, TURN_BACK_DURATION_MS + TURN_DONE_EXTRA_MS);
    }, SETTLE_CHAIN_DELAY_MS);
  }

  /** 落位 / 转回都走完：浮书收起，格子里的书在新位置亮回来（几何一致，无缝换回） */
  private finishDrag(): void {
    hilog.debug(DOMAIN, TAG, 'DBG finishDrag');
    this.dragId = '';
    this.settling = false;
    this.scrollAccum = 0;
  }

  /** 立刻收摊，不做动画（离开页面 / 窗口几何变了 / 状态异常） */
  private resetDrag(): void {
    hilog.debug(DOMAIN, TAG, 'DBG resetDrag dragId=%{public}s', this.dragId);
    this.stopAutoScroll();
    this.clearAngleTimer();
    if (this.settleTimer >= 0) {
      clearTimeout(this.settleTimer);
      this.settleTimer = -1;
    }
    if (this.turnDoneTimer >= 0) {
      clearTimeout(this.turnDoneTimer);
      this.turnDoneTimer = -1;
    }
    this.dragId = '';
    this.settling = false;
    this.lifted = false;
    this.bookAngleRad = 0;
    this.scrollAccum = 0;
  }

  /** 转角帧动画：投影矩阵不能插值，插值的永远是角度，每帧按角度重算投影 */
  private animateAngle(targetRad: number, durationMs: number): void {
    this.clearAngleTimer();
    const fromRad = this.bookAngleRad;
    hilog.debug(DOMAIN, TAG,
      'DBG animateAngle from=%{public}s to=%{public}s dur=%{public}d',
      String(Math.round(fromRad * 1000) / 1000), String(Math.round(targetRad * 1000) / 1000), durationMs);
    const start = Date.now();
    this.angleTimer = setInterval((): void => {
      const elapsed = Date.now() - start;
      const t = easeInOutCubic(elapsed / durationMs);
      this.bookAngleRad = fromRad + (targetRad - fromRad) * t;
      if (elapsed >= durationMs) {
        this.bookAngleRad = targetRad;
        this.clearAngleTimer();
        hilog.debug(DOMAIN, TAG, 'DBG animateAngle DONE angle=%{public}s', String(Math.round(this.bookAngleRad * 1000) / 1000));
      }
    }, ANGLE_TICK_MS);
  }

  private clearAngleTimer(): void {
    if (this.angleTimer >= 0) {
      clearInterval(this.angleTimer);
      this.angleTimer = -1;
    }
  }

  // ---- 拖到边缘自动滚 ----

  /** 手指进入视口上下 70vp 边缘带就开始滚，越靠边越快（2~12 / 16ms 拍） */
  private updateAutoScroll(fingerGlobalY: number): void {
    this.autoScrollSpeed = autoScrollSpeed(fingerGlobalY, 0, this.viewportHeightVp);
    if (this.autoScrollSpeed === 0) {
      this.stopAutoScroll();
      return;
    }
    if (this.autoScrollTimer < 0) {
      this.autoScrollTimer = setInterval((): void => {
        this.autoScrollTick();
      }, AUTO_SCROLL_TICK_MS);
    }
  }

  private autoScrollTick(): void {
    if (this.dragId === '' || this.settling || this.autoScrollSpeed === 0) {
      this.stopAutoScroll();
      return;
    }
    const current = this.scroller.currentOffset().yOffset;
    const maxScroll = this.contentHeightVp - this.viewportHeightVp;
    const next = clampedScrollOffset(current + this.autoScrollSpeed, maxScroll);
    const delta = next - current;
    if (Math.abs(delta) >= 0.5) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: next, animation: false });
      // 手指没动、内容动了：书在内容坐标里跟着挪（scrollAccum），才会留在手指下
      this.scrollAccum += delta;
      this.getUIContext().animateTo({ curve: FOLLOW_SPRING }, (): void => {
        this.dragY = this.liftBaseY + this.panY + this.scrollAccum;
      });
    }
  }

  private stopAutoScroll(): void {
    this.autoScrollSpeed = 0;
    if (this.autoScrollTimer >= 0) {
      clearInterval(this.autoScrollTimer);
      this.autoScrollTimer = -1;
    }
  }

  // ---- 落库 ----

  /** 顺序真变了才落库；只写变了的那几条 sortOrder（iOS saveOrder：0,1,2…）。
   *  失败提示 + 重查回滚成库里的顺序。 */
  private async persistOrder(): Promise<void> {
    if (this.sameOrder(this.order, this.orderAtLift)) {
      return;
    }
    const current: Record<string, number> = {};
    for (const notebook of this.notebooks) {
      current[notebook.id] = notebook.sortOrder;
    }
    const changes = changedSortOrders(this.order, current);
    if (changes.length === 0) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const store = await AppDatabase.open(context);
      await NotebookRepository.updateSortOrders(store, changes);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'persist shelf order failed: %{public}s', JSON.stringify(err));
      this.presentSaveFailed();
      this.load(context);
      return;
    }
    // 内存同步（下次拖动的 diff 才准；sortOrder 不参与渲染，不用刷界面）
    for (const change of changes) {
      const notebook = this.notebookById(change.id);
      if (notebook !== undefined) {
        notebook.sortOrder = change.sortOrder;
      }
    }
  }

  private sameOrder(a: string[], b: string[]): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

  // ---- 浮书数据（拿在手里 / 上次拿的那本；没拿过给占位值，树先挂出来编译） ----

  private draggedNotebook(): Notebook | undefined {
    if (this.dragId === '') {
      return undefined;
    }
    return this.notebookById(this.dragId);
  }

  private draggedName(): string {
    const notebook = this.draggedNotebook();
    return notebook !== undefined ? notebook.name : '';
  }

  private draggedCount(): number {
    const notebook = this.draggedNotebook();
    return notebook !== undefined ? this.countFor(notebook) : 0;
  }

  private draggedColor(): BookColor {
    const notebook = this.draggedNotebook();
    return notebook !== undefined ? notebook.bookColor : BookColor.Ivory;
  }

  private draggedPhoto(): string {
    const notebook = this.draggedNotebook();
    return notebook !== undefined ? (notebook.coverPhotoFilename ?? '') : '';
  }

  private draggedLayout(): CoverLayout {
    const notebook = this.draggedNotebook();
    return notebook !== undefined ? notebook.coverLayout : CoverLayout.FullBleed;
  }

  private notebookById(id: string): Notebook | undefined {
    for (const notebook of this.notebooks) {
      if (notebook.id === id) {
        return notebook;
      }
    }
    return undefined;
  }

  // ---- 几何（由内容区宽推：格宽 → 封面宽 → 格高 → 行列位置） ----

  /** 列数随窗口宽走断点：≥md（600vp，折叠展开态）6 列，否则 3 列 */
  private columnCount(): number {
    return this.contentWidthVp + 2 * SHELF_MARGIN >= BREAKPOINT_MD_VP ? COLUMN_COUNT_WIDE : COLUMN_COUNT;
  }

  private cellWidth(): number {
    return (this.contentWidthVp - COLUMN_SPACING * (this.columnCount() - 1)) / this.columnCount();
  }

  private cellHeight(): number {
    return (this.cellWidth() - PAGE_EDGE) / COVER_ASPECT;
  }

  /** 第 index 格（0 = 全部日记）左上角在书架 Stack 里的 x / y */
  private slotX(index: number): number {
    return (index % this.columnCount()) * (this.cellWidth() + COLUMN_SPACING);
  }

  private slotY(index: number): number {
    return Math.floor(index / this.columnCount()) * (this.cellHeight() + ROW_SPACING);
  }

  private slotCenterX(index: number): number {
    return this.slotX(index) + this.cellWidth() / 2;
  }

  private slotCenterY(index: number): number {
    return this.slotY(index) + this.cellHeight() / 2;
  }

  /** 书架 Stack 的总高：n 排 × 格高 + (n−1) × 行距 + 板子下探 */
  private shelfHeight(): number {
    const rows = Math.ceil(this.totalSlots() / this.columnCount());
    return rows > 0 ? rows * this.cellHeight() + (rows - 1) * ROW_SPACING + PLANK_DROP : 0;
  }

  /** 板子的行号（一排一块） */
  private plankRows(): number[] {
    const rows = Math.ceil(this.totalSlots() / this.columnCount());
    const indexes: number[] = [];
    for (let i = 0; i < rows; i++) {
      indexes.push(i);
    }
    return indexes;
  }

  private isDarkTheme(): boolean {
    return this.theme.colorMode === 'dark';
  }

  // ---- 数据 ----

  /** 全部格子：全部日记 + 各本（按本地顺序）+ 新建 */
  private displaySlots(): ShelfSlot[] {
    const slots: ShelfSlot[] = [new ShelfSlot('all', undefined, 'all')];
    for (const notebook of this.orderedNotebooks()) {
      slots.push(new ShelfSlot('book', notebook, notebook.id));
    }
    slots.push(new ShelfSlot('new', undefined, 'new'));
    return slots;
  }

  /** 按本地顺序排好的日记本；库里多出来的（拿着书时同步进来的）接在最后（iOS orderedTags） */
  private orderedNotebooks(): Notebook[] {
    const byId = new Map<string, Notebook>();
    for (const notebook of this.notebooks) {
      byId.set(notebook.id, notebook);
    }
    const result: Notebook[] = [];
    for (const id of this.order) {
      const notebook = byId.get(id);
      if (notebook !== undefined) {
        result.push(notebook);
        byId.delete(id);
      }
    }
    byId.forEach((notebook: Notebook): void => {
      result.push(notebook);
    });
    return result;
  }

  private totalSlots(): number {
    return this.displaySlots().length;
  }

  private notebookNames(): string[] {
    const names: string[] = [];
    for (const notebook of this.notebooks) {
      names.push(notebook.name);
    }
    return names;
  }

  private totalCount(): number {
    return this.counts !== undefined ? this.counts.total : 0;
  }

  private countFor(notebook: Notebook): number {
    return this.counts !== undefined ? this.counts.countFor(notebook.name) : 0;
  }

  /** 「全部日记」的封面书名：本地化文案（切语言当场变，appLanguage 变化触发重渲染） */
  private allEntriesName(): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    try {
      return context.resourceManager.getStringSync($r('app.string.s_4e1393a65c').id);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read all-entries name failed: %{public}s', JSON.stringify(err));
      return '';
    }
  }

  private async load(context: common.Context): Promise<void> {
    try {
      const store = await AppDatabase.open(context);
      const notebooks = await NotebookRepository.fetchAllNotebooks(store);
      const counts = await NotebookRepository.fetchShelfEntryCounts(store);
      this.notebooks = notebooks;
      this.counts = counts;
      // 手里拿着书的时候不跟着库改，放下之后自然对齐（iOS onChange 同款 guard）
      if (this.dragId === '') {
        const ids: string[] = [];
        for (const notebook of notebooks) {
          ids.push(notebook.id);
        }
        this.order = ids;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'load shelf failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 主页重查信号（页面重新可见）→ 重查书架 */
  private onReloadTickChange(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      this.load(context);
    }
  }

  /**
   * 新建日记本（R-BOOK-03 / R-BOOK-05）：
   * 撞名弹窗已拦，这里双保险再判一次；默认色墨绿；排书架最后。
   */
  private async createNotebook(rawName: string): Promise<void> {
    const typed = cleanedName(rawName);
    if (typed.length === 0 || isNameTaken(typed, this.notebookNames())) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const now = Date.now();
    const notebook = new Notebook(generateUuid(), typed, now, now);
    notebook.colorId = BookColor.PineGreen;
    notebook.sortOrder = nextSortOrder(this.notebooks.map((n: Notebook): number => n.sortOrder));
    try {
      const store = await AppDatabase.open(context);
      await NotebookRepository.insertNotebook(store, notebook);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'create notebook failed name=%{public}s: %{public}s',
        typed, JSON.stringify(err));
      this.presentSaveFailed();
      return;
    }
    this.showCreate = false;
    this.load(context);
  }

  private presentSaveFailed(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const message: string = context.resourceManager.getStringSync($r('app.string.s_40525a7328').id);
      this.env.errors.present(message, ErrorToastKind.Error, 4000);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read save-failed string failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 轻震（vibrator 预设效果；机型没有该预设退毫秒短震，再失败静默 —— 震动只是手感，不构成功能） */
  private haptic(): void {
    const preset: vibrator.VibratePreset = { type: 'preset', effectId: 'haptic.effect.soft', count: 1 };
    vibrator.startVibration(preset, { usage: 'touch' }).catch((): void => {
      const fallback: vibrator.VibrateTime = { type: 'time', duration: 12 };
      vibrator.startVibration(fallback, { usage: 'touch' }).catch((): void => {
      });
    });
  }

  // ---- 打开钩子（点书 → 日记本主页，Tab 内 Navigation 栈，底部 Tab 栏保留可见） ----

  private openAllEntries(): void {
    this.navPathStack.pushPathByName('BookDetail', BOOK_DETAIL_ALL_ENTRIES_PARAM);
  }

  private openNotebook(slot: ShelfSlot): void {
    if (slot.notebook === undefined) {
      return;
    }
    this.navPathStack.pushPathByName('BookDetail', slot.notebook.id);
  }
}
