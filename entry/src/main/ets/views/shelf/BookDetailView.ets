/**
 * 日记本主页（10_BUILD_MANUAL.md 3.3，R-BOOK-08~11）。对应 iOS
 * `Views/Home/BookDetailView.swift`。
 *
 * 从上往下：
 * 1. **封面大图**（BookHeroView）：照片铺满 / 白框 / 贴照片 / 这本的布面；
 *    高度 = 滚动区可视高的 62%（最少 360）
 * 2. **目录**（BookContentsView）：按阅读顺序编号、按月分组；可切宫格小样
 *    （偏好全局共用，AppPrefs 记住）；空本子显示「这本还是空的」
 * 3. 底部常驻：「开始阅读」（3.5 翻页阅读器接通，本卡留钩子）+「写一篇」
 *    （带入这本的名字预选写日记页的日记本）
 *
 * 顶栏：贴在大图上（滚过大图才出底色和标题）；深色大图上图标用浅色
 * （iOS `toolbarColorScheme(.dark)` 的对应）。右上「…」只有真本子才有
 * （「全部日记」不是库记录）：编辑封面（3.4 接通）/ 重命名 / 删除。
 *
 * 删除语义（iOS 源码，> 规则文档措辞）：只删本子行 + 封面文件，
 * **不动 journal_entry.tags**——tags 是独立存的字符串数组，名字原样留下；
 * 同名重建一本时那些日记按「名字就是身份」重新归入。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { JournalEntry } from '../../models/JournalEntry';
import {
  BookColor,
  CoverLayout,
  Notebook,
  isLightBookColor
} from '../../models/Notebook';
import {
  bookReadingEntries,
  heroSubtitle
} from '../../data/BookContentsLogic';
import {
  NotebookRepository,
  NotebookRenameResult
} from '../../data/NotebookRepository';
import { EntryRepository } from '../../data/EntryRepository';
import { AppDatabase } from '../../data/Database';
import { STORAGE_KEY_HOME_RELOAD_TICK } from '../../data/HomeLogic';
import {
  AppPrefs,
  BOOK_CONTENTS_LAYOUT_GRID,
  BOOK_CONTENTS_LAYOUT_LIST
} from '../../services/AppPrefs';
import { MediaStorageService } from '../../services/MediaStorageService';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import {
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP,
  STORAGE_KEY_SAFE_AREA_TOP_VP
} from '../../services/ImmersiveChrome';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { ErrorToastKind } from '../../environment/ErrorPresenter';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { BookHeroView } from './BookHeroView';
import { CircleIconButton } from '../compose/CircleIconButton';
import { BookContentsView } from './BookContentsView';
import { RenameNotebookDialog } from './RenameNotebookDialog';

const DOMAIN = 0x0000;
const TAG = 'BookDetailView';

/** 大图最少这么高（iOS heroHeight 的 max(360, …)） */
const HERO_MIN_HEIGHT_VP: number = 360;
/** 还没量到滚动区高时先按这么高画（iOS 同款兜底值） */
const HERO_FALLBACK_HEIGHT_VP: number = 470;
/** 大图占滚动区可视高的比例。iOS 原版 0.62；真机验收（2026-10-21 用户定稿）
 *  降到 0.48：底部浮条 + 胶囊清让吃掉太多竖向空间，0.62 时目录只能露出
 *  一行标题，0.48 恰好露出三行完整题目（用户验收口径） */
const HERO_HEIGHT_RATIO: number = 0.48;
/** 滚过这个线（大图底部往上 110）顶栏才出底色和标题（iOS onScrollGeometryChange） */
const HERO_TITLE_CLEARANCE_VP: number = 110;

/** 底部「开始阅读 / 写一篇」条**坐实在底部 Tab 胶囊上沿**（iOS safeAreaInset
 *  底条直接坐在系统 tab bar 上，无间隙）。胶囊顶 = 屏底上方 87vp（2026-10-21
 *  真机实测 2178px@3x；旧值 90 会在底条和胶囊之间留出 36vp 不透明死带，
 *  用户验收指出与 iOS 不一致）。margin = 安全区 + 54 */
const BOTTOM_BAR_CAPSULE_CLEARANCE_VP: number = 54;
/** 底条自身高度（上留白 10 + 按钮 48 + 下留白 8），滚动内容的底部清让由它推 */
const BOTTOM_BAR_HEIGHT_VP: number = 66;

/** 「…」菜单（参考 iOS Menu）一行的高 */
const MENU_ROW_HEIGHT_VP: number = 44;

/** 顶栏（返回 / 标题 /「…」）一行的高；状态栏下沿的透明磨砂也按它铺 */
const TOP_BAR_ROW_HEIGHT_VP: number = 44;

/** 书架推「全部日记」时传的路由参数（占位标记，不是库 id；onReady 归一成 ''） */
export const BOOK_DETAIL_ALL_ENTRIES_PARAM: string = 'all';

@Builder
export function BookDetailBuilder() {
  BookDetailView()
}

@Component
export struct BookDetailView {
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  /** 主页重查信号（与 HomeView / 书架共用）：从写日记页回来、改名后 +1 重查 */
  @StorageProp(STORAGE_KEY_HOME_RELOAD_TICK) @Watch('onReloadTickChange')
  homeReloadTick: number = 0;
  /** undefined = 「全部日记」（不是库记录，没有「…」菜单） */
  @State private notebook: Notebook | undefined = undefined;
  @State private allEntries: JournalEntry[] = [];
  /** 目录版式：列表 / 宫格（全局共用偏好，AppPrefs 记住上次选的） */
  @State private layout: string = BOOK_CONTENTS_LAYOUT_LIST;
  /** 滚动区可视高（vp）：大图高度由它推 */
  @State private containerHeightVp: number = 0;
  /** 根容器宽（vp）：「…」下拉菜单的定位用 */
  @State private containerWidthVp: number = 0;
  /** 滚过大图（顶栏出底色和标题） */
  @State private scrolledPastHero: boolean = false;
  @State private showMenu: boolean = false;
  @State private showRename: boolean = false;
  @State private showDeleteConfirm: boolean = false;
  /** 全部日记本（重命名弹窗的撞名快照 + 库端判重兜底都用它） */
  @State private otherNotebooks: Notebook[] = [];

  private navPathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();
  /** 路由参数里的日记本 id；'' = 全部日记 */
  private notebookId: string = '';
  /** 目录版式只从偏好读一次（切换后内存态为准，退出重进再读偏好） */
  private layoutLoaded: boolean = false;

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        this.scrollBody()

        // 顶栏：贴在大图上；滚过大图才出磨砂底、细线和标题（iOS 系统导航栏
        // 同款行为：静止时完全透明沉浸，滚动后 frosted glass 接管）
        this.topBar()

        // 底部常驻条（浮在 Tab 胶囊上方）
        this.bottomBar()

        // 「…」下拉菜单（遮罩先挂、菜单压上）
        if (this.showMenu) {
          this.menuScrim()
          this.menuDropdown()
        }

        // 重命名弹窗（撞名当场红字提示）
        if (this.showRename) {
          RenameNotebookDialog({
            existingNames: this.notebookNames(),
            currentName: this.notebook !== undefined ? this.notebook.name : '',
            onCancel: (): void => {
              this.showRename = false;
            },
            onRename: (name: string): void => {
              this.commitRename(name);
            }
          })
        }

        // 删除确认（先退回书架再删，iOS 同款顺序）
        if (this.showDeleteConfirm) {
          this.deleteConfirmDialog()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.background)
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        const w: Length = newArea.width;
        const h: Length = newArea.height;
        if (typeof w === 'number') {
          this.containerWidthVp = w;
        }
        if (typeof h === 'number') {
          this.containerHeightVp = h;
          this.updateScrolledPastHero();
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.background)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      // 边界一次断言：pushPathByName 传的是 string（书架），Record 分支兼容
      const raw = ctx.pathInfo.param as Record<string, Object> | string | undefined;
      if (typeof raw === 'string') {
        // 「全部日记」是占位标记不是库 id：归一成 '' 走全部日记模式，
        // 否则查不到本子会当「已删」立刻 pop（真机验收抓到：点击无反应）
        this.notebookId = raw === BOOK_DETAIL_ALL_ENTRIES_PARAM ? '' : raw;
      } else if (raw !== undefined) {
        const id = raw['id'];
        if (typeof id === 'string') {
          this.notebookId = id;
        }
      }
      this.load();
    })
  }

  // ---- 滚动区：大图 → 目录抬头 → 目录 / 空本子 ----

  @Builder
  private scrollBody() {
    Scroll(this.scroller) {
      Column() {
        BookHeroView({
          title: this.navigationTitle(),
          subtitle: this.heroSubtitleText(),
          color: this.notebook !== undefined ? this.notebook.bookColor : BookColor.Ivory,
          coverPhotoFilename: this.notebook?.coverPhotoFilename ?? '',
          layout: this.notebook !== undefined ? this.notebook.coverLayout : CoverLayout.FullBleed
        })
          .width('100%')
          .height(this.heroHeightVp())

        this.contentsHeader()

        if (this.readingEntries().length === 0) {
          this.emptyState()
        } else {
          BookContentsView({
            entries: this.readingEntries(),
            layout: this.layout,
            onOpen: (entry: JournalEntry): void => {
              this.openReader(entry);
            },
            onCompose: (): void => {
              this.openCompose();
            }
          })
        }

        // 底部清让：滚到头时最后一行距底条顶 24（iOS padding(.bottom, 24)）。
        // 视口本身已经裁在底条上沿（scrollViewportHeight），底条 / 胶囊
        // 占的底段不用在这里再让
        Column()
          .width('100%')
          .height(24)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      // Scroll 受限高度时内容不满一屏默认居中（faqs-arkui-725），大图顶上
      // 会顶出一段死区——内容至少撑到视口高，钉回顶部对齐
      .constraintSize({ minHeight: this.scrollViewportHeightVp() })
    }
    .width('100%')
    // 视口裁在底条上沿：滚动内容不出现在底条底下，更不许从 Tab 胶囊
    // （半透明磨砂）里透视出来（2026-10-21 用户验收指出）。根 Stack 是
    // 底对齐，视口变矮后要显式钉回顶部
    .height(this.scrollViewportHeight())
    .position({ x: 0, y: 0 })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onDidScroll((): void => {
      this.updateScrolledPastHero();
    })
  }

  /** 目录抬头：「目录」……「N 篇」+ 列表 / 宫格切换（参考图 ④） */
  @Builder
  private contentsHeader() {
    Row() {
      Text($r('app.string.s_41e5243e2d'))
        .fontSize(this.theme.labelFont.size)
        .fontWeight(this.theme.labelFont.weight)
        .fontFamily(this.theme.labelFont.family)
        .fontColor(this.theme.textSecondary)
        .letterSpacing(this.theme.letterSpacingWide * 1.5)
      Blank()
      if (this.readingEntries().length > 0) {
        Text($r('app.string.s_54c43eaca1', this.readingEntries().length))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textTertiary)
          .letterSpacing(this.theme.letterSpacingWide)
        this.layoutToggle()
      }
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 6, bottom: 2 })
  }

  /** 列表 / 宫格切换（图标画出来，不依赖设备符号表；选中深、未选中淡） */
  @Builder
  private layoutToggle() {
    Row({ space: 2 }) {
      // 列表：三道横线
      Column({ space: 3 }) {
        Row().width(12).height(1.4).borderRadius(0.7)
          .backgroundColor(this.layoutToggleColor(this.layout === BOOK_CONTENTS_LAYOUT_LIST))
        Row().width(12).height(1.4).borderRadius(0.7)
          .backgroundColor(this.layoutToggleColor(this.layout === BOOK_CONTENTS_LAYOUT_LIST))
        Row().width(12).height(1.4).borderRadius(0.7)
          .backgroundColor(this.layoutToggleColor(this.layout === BOOK_CONTENTS_LAYOUT_LIST))
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width(30)
      .height(26)
      .onClick((): void => {
        this.setLayout(BOOK_CONTENTS_LAYOUT_LIST);
      })

      // 宫格：四格
      Column({ space: 3 }) {
        Row({ space: 3 }) {
          Row().width(4.6).height(4.6)
            .backgroundColor(this.layoutToggleColor(this.layout === BOOK_CONTENTS_LAYOUT_GRID))
          Row().width(4.6).height(4.6)
            .backgroundColor(this.layoutToggleColor(this.layout === BOOK_CONTENTS_LAYOUT_GRID))
        }
        Row({ space: 3 }) {
          Row().width(4.6).height(4.6)
            .backgroundColor(this.layoutToggleColor(this.layout === BOOK_CONTENTS_LAYOUT_GRID))
          Row().width(4.6).height(4.6)
            .backgroundColor(this.layoutToggleColor(this.layout === BOOK_CONTENTS_LAYOUT_GRID))
        }
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width(30)
      .height(26)
      .onClick((): void => {
        this.setLayout(BOOK_CONTENTS_LAYOUT_GRID);
      })
    }
    .margin({ left: 6 })
  }

  /** 空本子：「这本还是空的」+「写下第一篇」 */
  @Builder
  private emptyState() {
    Column({ space: 14 }) {
      Text($r('app.string.s_69b55bf474'))
        .fontSize(this.theme.bodyFont.size)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(this.theme.textTertiary)
      Text($r('app.string.s_a612e01da7'))
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.accent)
        .padding({ top: 6, bottom: 6, left: 12, right: 12 })
        .onClick((): void => {
          this.openCompose();
        })
    }
    .width('100%')
    .padding({ top: 48 })
    .alignItems(HorizontalAlign.Center)
  }

  // ---- 顶栏 ----

  @Builder
  private topBar() {
    Stack() {
      // 磨砂底 + 底缘细线（滚过大图渐显；大图上透明）。iOS 系统导航栏
      // 同款：Thin 毛玻璃 + 主题背景色 40% 叠色（记录主页顶栏同配方），
      // 盖在滚过的内容上读得出 frosted glass
      Column()
        .width('100%')
        .height(this.safeAreaTopVp + TOP_BAR_ROW_HEIGHT_VP)
        .backgroundColor(this.frostedBarColor())
        .backgroundBlurStyle(BlurStyle.Thin)
        .opacity(this.scrolledPastHero ? 1 : 0)
        .animation({ duration: 250, curve: Curve.EaseOut })
      Row()
        .width('100%')
        .height(0.5)
        .backgroundColor(this.theme.border)
        .opacity(this.scrolledPastHero ? 1 : 0)
        .animation({ duration: 250, curve: Curve.EaseOut })
        .position({ x: 0, y: this.safeAreaTopVp + TOP_BAR_ROW_HEIGHT_VP - 0.5 })

      // 左返回 / 右「…」（真本子才有）。官方 Button 圆钮（CircleIconButton，
      // 详情页 / 书写页同款全 app 统一）；顶栏画在内容区、系统标题栏隐藏
      // （全面屏 hero），官方沉浸光感材质在内容区不生效（官方《沉浸光感》
      // 生效范围）——正好取「官方组件不带沉浸感」形态：透明底 + stateEffect
      // 按压反馈。图标色随 hero 亮暗自适应（iOS toolbarColorScheme 同款）
      Row() {
        CircleIconButton({
          iconRes: $r('sys.symbol.chevron_left'),
          iconSize: 14,
          iconColor: this.topBarIconColor(),
          onTap: (): void => {
            this.navPathStack.pop();
          }
        })
        Blank()
        if (this.notebook !== undefined) {
          CircleIconButton({
            iconRes: $r('sys.symbol.more'),
            iconSize: 14,
            iconColor: this.topBarIconColor(),
            onTap: (): void => {
              this.showMenu = true;
            }
          })
        }
      }
      .width('100%')
      .height(TOP_BAR_ROW_HEIGHT_VP)
      .margin({ top: this.safeAreaTopVp })
      .padding({ left: 6, right: 6 })

      // 居中标题（滚过大图才显）。坑：Stack 里不定位的子项居中在整块
      // （状态栏 + 44 行）上，标题会压进状态栏（真机滚动后才发现）——
      // 显式钉在状态栏下面那行里居中
      Row() {
        Text(this.navigationTitle())
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textSecondary)
          .letterSpacing(this.theme.letterSpacingWide)
          .maxLines(1)
      }
      .width('100%')
      .height(TOP_BAR_ROW_HEIGHT_VP)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      // 🔴 全宽行盖在图标行上面（Stack 后声明 = z 更高），吞掉返回 /「…」
      // 的触摸（真机用户实测返回无反应；此前标题是不定宽 Text、两侧空隙
      // 能透传才没暴露）。纯展示层，触摸必须穿透给下面的图标行
      .hitTestBehavior(HitTestMode.None)
      .opacity(this.scrolledPastHero ? 1 : 0)
      .animation({ duration: 250, curve: Curve.EaseOut })
      .position({ x: 0, y: this.safeAreaTopVp })
    }
    .width('100%')
    .height(this.safeAreaTopVp + TOP_BAR_ROW_HEIGHT_VP)
    .position({ x: 0, y: 0 })
  }

  // ---- 「…」菜单：编辑封面 / 重命名 / 删除 ----

  @Builder
  private menuScrim() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .onClick((): void => {
        this.showMenu = false;
      })
  }

  @Builder
  private menuDropdown() {
    Column() {
      this.menuRow($r('app.string.s_ce3e4010fe'), $r('sys.symbol.picture_on_square'),
        this.theme.textPrimary, (): void => {
          this.showMenu = false;
          // TODO 3.4：换封面（CoverChangeSheet）
        })
      this.menuRow($r('app.string.s_1cd80fd7a8'), $r('sys.symbol.square_and_pencil'),
        this.theme.textPrimary, (): void => {
          this.showMenu = false;
          this.showRename = true;
        })
      this.menuRow($r('app.string.s_3755f56f2f'), $r('sys.symbol.trash'),
        this.theme.destructive, (): void => {
          this.showMenu = false;
          this.showDeleteConfirm = true;
        })
    }
    .width(158)
    .borderRadius(14)
    .backgroundColor(this.theme.cardBackground)
    .shadow({
      radius: 22,
      color: '#33000000',
      offsetX: 0,
      offsetY: 8
    })
    .position({
      x: Math.max(8, this.containerWidthVp - 12 - 158),
      y: this.safeAreaTopVp + 48
    })
  }

  @Builder
  private menuRow(labelRes: Resource, iconRes: Resource, labelColor: ResourceColor,
    onTap: () => void) {
    Row({ space: 11 }) {
      SymbolGlyph(iconRes)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor([labelColor])
      Text(labelRes)
        .fontSize(this.theme.bodyFont.size)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(labelColor)
    }
    .width('100%')
    .height(MENU_ROW_HEIGHT_VP)
    .padding({ left: 15, right: 15 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      onTap();
    })
  }

  // ---- 删除确认 ----

  @Builder
  private deleteConfirmDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.showDeleteConfirm = false;
        })

      Column({ space: 18 }) {
        Text($r('app.string.s_b0068cfb4a'))
          .fontSize(this.theme.headingFont.size)
          .fontWeight(this.theme.headingFont.weight)
          .fontFamily(this.theme.headingFont.family)
          .fontColor(this.theme.textPrimary)

        Text($r('app.string.s_c33c1e2c83'))
          .fontSize(13)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textSecondary)
          .textAlign(TextAlign.Center)

        Row({ space: 12 }) {
          Button({ stateEffect: true }) {
            Text($r('app.string.s_4d0b4688c7'))
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.theme.textSecondary)
          }
          .layoutWeight(1)
          .padding({ top: 11, bottom: 11 })
          .backgroundColor(this.theme.surfaceBackground)
          .borderRadius(12)
          .border({ width: 0.5, color: this.theme.border })
          .onClick((): void => {
            this.showDeleteConfirm = false;
          })

          Button({ stateEffect: true }) {
            Text($r('app.string.s_3755f56f2f'))
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(this.theme.cardBackground)
          }
          .layoutWeight(1)
          .padding({ top: 11, bottom: 11 })
          .backgroundColor(this.theme.destructive)
          .borderRadius(12)
          .onClick((): void => {
            this.deleteNotebook();
          })
        }
      }
      .padding({ left: 22, right: 22, top: 24, bottom: 24 })
      .constraintSize({ maxWidth: 320 })
      .backgroundColor(this.theme.cardBackground)
      .borderRadius(20)
    }
    .width('100%')
    .height('100%')
    .margin({ bottom: BOTTOM_BAR_CAPSULE_CLEARANCE_VP })
  }

  // ---- 底部常驻条：「开始阅读」+「写一篇」 ----

  @Builder
  private bottomBar() {
    Column() {
      Row({ space: 12 }) {
        // 开始阅读：没日记时置灰（iOS disabled 由 textTertiary + border 表达）
        Text($r('app.string.s_f3be3e4b09'))
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .letterSpacing(2)
          .fontColor(this.hasEntries() ? this.theme.textPrimary : this.theme.textTertiary)
          .height(48)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .borderRadius(8)
          .border({
            width: 1,
            color: this.hasEntries() ? this.primaryColor75() : this.theme.border
          })
          .onClick((): void => {
            this.openReader(this.firstEntry());
          })

        // 写一篇（带入这本）
        Stack() {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.theme.textPrimary])
        }
        .width(48)
        .height(48)
        .borderRadius(8)
        .border({
          width: 1,
          color: this.primaryColor75()
        })
        .onClick((): void => {
          this.openCompose();
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 10, bottom: 8 })
    .backgroundColor(this.theme.background)
    .border({ width: { top: 0.5 }, color: this.theme.border })
    .margin({ bottom: this.safeAreaBottomVp + BOTTOM_BAR_CAPSULE_CLEARANCE_VP })
  }

  // ---- 数据 ----

  /** 这本里的日记，按阅读顺序（从早到晚）；「全部日记」= 所有 */
  private readingEntries(): JournalEntry[] {
    return bookReadingEntries(this.allEntries, this.notebook !== undefined ? this.notebook.name : '');
  }

  private hasEntries(): boolean {
    return this.readingEntries().length > 0;
  }

  private firstEntry(): JournalEntry | undefined {
    const entries = this.readingEntries();
    return entries.length > 0 ? entries[0] : undefined;
  }

  private heroSubtitleText(): string {
    return heroSubtitle(this.notebook?.subtitle, this.readingEntries(), this.appLanguage);
  }

  /** 大图高度：滚动区可视高的 48%（最少 360）；还没量到先按 470 */
  private heroHeightVp(): number {
    return this.containerHeightVp > 0
      ? Math.max(HERO_MIN_HEIGHT_VP, this.containerHeightVp * HERO_HEIGHT_RATIO)
      : HERO_FALLBACK_HEIGHT_VP;
  }

  /** 底条顶到屏底的距离（安全区 + 胶囊清让 + 底条高） */
  private bottomBarTopFromBottomVp(): number {
    return this.safeAreaBottomVp + BOTTOM_BAR_CAPSULE_CLEARANCE_VP + BOTTOM_BAR_HEIGHT_VP;
  }

  /** 滚动视口高：全容高减掉底条占的底段——内容裁在底条上沿，到不了
   *  底条和 Tab 胶囊底下（不许透视过 tab bar）；还没量到先铺满 */
  private scrollViewportHeight(): Length {
    const h: number = this.scrollViewportHeightVp();
    return h > 0 ? h : '100%';
  }

  /** 滚动视口高的 vp 数值（0 = 还没量到）：滚动内容 minHeight 顶齐用 */
  private scrollViewportHeightVp(): number {
    if (this.containerHeightVp <= 0) {
      return 0;
    }
    const h: number = this.containerHeightVp - this.bottomBarTopFromBottomVp();
    return h > 0 ? h : 0;
  }

  /** 日记本名是用户数据，原样显示；「全部日记」走本地化（切语言当场变） */
  private navigationTitle(): string {
    if (this.notebook !== undefined) {
      return this.notebook.name;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    try {
      return context.resourceManager.getStringSync($r('app.string.s_4e1393a65c').id);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read all-entries title failed: %{public}s', JSON.stringify(err));
      return '';
    }
  }

  /**
   * 大图是深色的吗（iOS heroIsDark）：满版照片按深（顶上压了一层暗）；
   * 白框是浅纸面；贴照片和纯色看布面颜色；「全部日记」象牙白 = 浅。
   * 滚过大图后顶栏落回页面底色，图标一律回主题深色。
   */
  private heroIsDark(): boolean {
    const notebook = this.notebook;
    if (notebook === undefined) {
      return false;
    }
    const photo = notebook.coverPhotoFilename ?? '';
    if (photo.length > 0) {
      if (notebook.coverLayout === CoverLayout.FullBleed) {
        return true;
      }
      if (notebook.coverLayout === CoverLayout.Framed) {
        return false;
      }
    }
    return !isLightBookColor(notebook.bookColor);
  }

  private topBarIconColor(): ResourceColor {
    return this.heroIsDark() && !this.scrolledPastHero
      ? Color.White
      : this.theme.textPrimary;
  }

  /** 主题 textPrimary 的 75% 透明（iOS border 里 opacity(0.75)；三主题均为数字色值） */
  private primaryColor75(): ResourceColor {
    const color = this.theme.textPrimary;
    return typeof color === 'number' ? (color & 0x00FFFFFF) | 0xBF000000 : color;
  }

  private layoutToggleColor(active: boolean): ResourceColor {
    return active ? this.theme.textPrimary : this.theme.textTertiary;
  }

  /** 重命名弹窗的撞名快照：全部日记本名（弹窗自己把「现名」排除掉再判） */
  private notebookNames(): string[] {
    const names: string[] = [];
    for (const notebook of this.otherNotebooks) {
      names.push(notebook.name);
    }
    return names;
  }

  /** 滚过线了（大图底部往上 110）→ 顶栏出底色和标题（iOS 同款阈值，0.25s 渐变） */
  private updateScrolledPastHero(): void {
    const past = this.scroller.currentOffset().yOffset > this.heroHeightVp() - HERO_TITLE_CLEARANCE_VP;
    if (past !== this.scrolledPastHero) {
      this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseOut }, (): void => {
        this.scrolledPastHero = past;
      });
    }
  }

  // ---- 动作 ----

  private setLayout(layout: string): void {
    if (layout !== this.layout) {
      this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut }, (): void => {
        this.layout = layout;
      });
      AppPrefs.setBookContentsLayout(layout);
    }
  }

  /** 点目录里某一篇 → 翻页阅读器从那一篇开始（3.5 接通，本卡留钩子不跳转） */
  private openReader(_entry: JournalEntry | undefined): void {
    // TODO 3.5：DiaryReaderView(initialDiary, entries)
  }

  /** 写一篇（带入这本的名字，写日记页预选；「全部日记」不带） */
  private openCompose(): void {
    const notebook = this.notebook;
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/Compose',
      params: {
        'initialNotebookName': notebook !== undefined ? notebook.name : ''
      } as Record<string, Object>
    });
  }

  /** 重命名（挂在这本上的日记 tags 一起改过去；三态对齐 iOS Tag.rename） */
  private async commitRename(rawName: string): Promise<void> {
    const notebook = this.notebook;
    const context = this.getUIContext().getHostContext();
    if (notebook === undefined || context === undefined) {
      return;
    }
    try {
      const store = await AppDatabase.open(context);
      const result = await NotebookRepository.renameNotebook(store, notebook, rawName,
        this.otherNotebookNames());
      if (result === NotebookRenameResult.Renamed) {
        this.showRename = false;
        this.bumpReloadTick();
      } else if (result === NotebookRenameResult.NameTaken) {
        // 撞名要说出来（弹窗内也有红字提示，这里兜底）
        this.presentInfo($r('app.string.s_b477b8791b'));
      } else {
        this.showRename = false;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'rename notebook failed: %{public}s', JSON.stringify(err));
      this.presentSaveFailed();
    }
  }

  /** 除这本外的日记本名（rename 判重用；弹窗自己的快照不含它，这里给库端兜底） */
  private otherNotebookNames(): string[] {
    const names: string[] = [];
    const current = this.notebook;
    for (const other of this.otherNotebooks) {
      if (current === undefined || other.id !== current.id) {
        names.push(other.name);
      }
    }
    return names;
  }

  /**
   * 删除（iOS deleteNotebook 同款顺序）：先退回书架，600ms 后再删——
   * 本页退场动画里不再读已删的数据。只删本子行 + 封面文件，不动日记 tags。
   */
  private deleteNotebook(): void {
    const notebook = this.notebook;
    const context = this.getUIContext().getHostContext();
    if (notebook === undefined || context === undefined) {
      return;
    }
    this.showDeleteConfirm = false;
    this.navPathStack.pop();
    setTimeout((): void => {
      this.deleteNotebookAfterDismiss(notebook, context);
    }, 600);
  }

  private async deleteNotebookAfterDismiss(notebook: Notebook,
    context: common.Context): Promise<void> {
    try {
      const store = await AppDatabase.open(context);
      await NotebookRepository.deleteNotebook(store, notebook.id);
      // 照片封面文件一起删（不然成了没人认领的文件白占地方）
      MediaStorageService.create(context, store).deleteCoverFile(notebook.coverPhotoFilename ?? '');
      this.bumpReloadTick();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'delete notebook failed id=%{public}s: %{public}s',
        notebook.id, JSON.stringify(err));
      this.presentSaveFailed();
    }
  }

  /** 通知底下各页重查（改了库但不会触发 Index.onPageShow 的场景） */
  private bumpReloadTick(): void {
    AppStorage.setOrCreate(STORAGE_KEY_HOME_RELOAD_TICK, this.homeReloadTick + 1);
  }

  private presentInfo(messageRes: Resource): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const message: string = context.resourceManager.getStringSync(messageRes.id);
      this.env.errors.present(message, ErrorToastKind.Info, 3000);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read info string failed: %{public}s', JSON.stringify(err));
    }
  }

  private presentSaveFailed(): void {
    this.presentInfo($r('app.string.s_40525a7328'));
  }

  // ---- 加载 ----

  /** 磨砂顶栏叠色：主题背景色 40% 半透明（与记录主页 frostedBarColor 同配方） */
  private frostedBarColor(): ResourceColor {
    const bg = this.theme.background;
    if (typeof bg === 'number') {
      return (bg & 0x00FFFFFF) | 0x66000000;
    }
    return bg;
  }

  private onReloadTickChange(): void {
    this.load();
  }

  private load(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.loadFromContext(context);
  }

  private async loadFromContext(context: common.Context): Promise<void> {
    try {
      const store = await AppDatabase.open(context);
      const entries = await EntryRepository.fetchAllEntries(store);
      const notebooks = await NotebookRepository.fetchAllNotebooks(store);
      this.allEntries = entries;
      this.otherNotebooks = notebooks;
      if (this.notebookId.length > 0) {
        // 真本子：按路由 id 找；找不到（已删）退回书架
        let found: Notebook | undefined = undefined;
        for (const notebook of notebooks) {
          if (notebook.id === this.notebookId) {
            found = notebook;
            break;
          }
        }
        if (found === undefined) {
          this.navPathStack.pop();
          return;
        }
        this.notebook = found;
        // 每次进这本刷新 lastOpenedAt（「全部日记」无本，不调）
        NotebookRepository.touchLastOpenedAt(store, found.id, Date.now());
      }
      if (!this.layoutLoaded) {
        this.layout = AppPrefs.currentBookContentsLayout();
        this.layoutLoaded = true;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'load book detail failed: %{public}s', JSON.stringify(err));
      this.presentSaveFailed();
    }
  }
}
