/**
 * 书架（10_BUILD_MANUAL.md 3.1，R-BOOK-01~05）。对应 iOS `Views/Home/BookshelfView.swift`
 * + `Shelf/ShelfGridView.swift`（摆书部分）+ `Shelf/ShelfDecor.swift`（书架板）。
 *
 * - 三列书架板（iOS 参数：列距 18 / 行距 38 / 顶距 20 / 页边 22 / 封面比例 0.73）；
 *   板子画在书底下，位置由格子实际排出来的位置决定（板面 surfaceBackground、
 *   前沿 border → borderAccent，深色主题下自然是深色木板）
 * - 第一格「全部日记」固定象牙白亚麻（不是库里的一条记录），没有「…」菜单；
 *   各本 = 封面（纯色亚麻 / 照片）+ 书名（每行 4 字折行）+ 篇数
 * - 顺序 = sortOrder（相同按 createdAt，R-BOOK-05）；末尾永远有「新建」（R-BOOK-02）
 * - 新建弹窗：名称 + 撞名当场提示（R-BOOK-03）；新建默认色墨绿（iOS CreateTagSheet），
 *   一律排书架最后（nextSortOrder）
 * - 点书 → 日记本主页是 3.3 的卡片，本卡先留打开钩子不跳转
 * - 入场：书架第一次出现时一本本依次落下（iOS appearing，index × 0.06s 错峰）
 * - 长按拿书 / 拖动换位是 3.2 的卡片，本卡不做
 *
 * 数据刷新与 HomeView 同一信号：Index.onPageShow bump `homeReloadTick`
 * （RDB 无观察机制，用显式信号补齐，对应 iOS `@Query` 的自动响应）。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BookColor,
  CoverLayout,
  Notebook,
  cleanedName,
  isNameTaken,
  nextSortOrder
} from '../../models/Notebook';
import { generateUuid } from '../../models/Uuid';
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
  /** 入场动画开关（首帧 false，下一拍翻 true 触发逐本落下） */
  @State private appeared: boolean = false;

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

  build() {
    Stack() {
      Scroll() {
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

            // 书架格子
            Column({ space: ROW_SPACING - PLANK_DROP }) {
              ForEach(this.rows(), (row: ShelfSlot[], rowIndex: number) => {
                this.shelfRow(row, rowIndex)
              }, (row: ShelfSlot[]): string => {
                // 键 = 整行 slot 键拼接：新书插进某行时该行内容变、键必变，
                // 强制重渲染（只拿 row[0].key 的话，中间插书那行键不变不刷新）
                let key = '';
                for (const slot of row) {
                  key += `${slot.key}|`;
                }
                return key;
              })
            }
            .width(this.contentWidthVp)
            .alignItems(HorizontalAlign.Start)
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
  }

  /** 一排书（最多 3 格）：书架板垫在书底下（板面 7 + 前沿 9，iOS ShelfPlanks）。
   * 板延展到屏幕两端：负偏移抵掉内容列页边距，宽 = 内容宽 + 两侧页边，恰好不越屏 */
  @Builder
  private shelfRow(row: ShelfSlot[], rowIndex: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      // 书架板：板面（surfaceBackground）+ 前沿（border → borderAccent 渐变）
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
      .position({ x: -SHELF_MARGIN, y: this.cellHeight() - 2 })
      .shadow({
        radius: 7,
        color: this.isDarkTheme() ? '#66000000' : '#24000000',
        offsetX: 0,
        offsetY: 6
      })

      // 书（含「全部日记」和「新建」占位）
      Row({ space: COLUMN_SPACING }) {
        ForEach(row, (slot: ShelfSlot, colIndex: number) => {
          this.slotView(slot, rowIndex * this.columnCount() + colIndex)
        }, (slot: ShelfSlot): string => slot.key)
      }
      .height(this.cellHeight())
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .height(this.cellHeight() + PLANK_DROP)
  }

  /** 一个格子。入场动画：一本本依次落下（opacity + 上移 20vp，index × 60ms 错峰） */
  @Builder
  private slotView(slot: ShelfSlot, slotIndex: number) {
    Stack() {
      if (slot.kind === 'all') {
        // 全部日记（R-BOOK-04：固定第一格象牙白，不是库记录）
        ShelfBookView({
          name: this.allEntriesName(),
          entryCount: this.totalCount(),
          color: BookColor.Ivory,
          coverPhotoFilename: '',
          layout: CoverLayout.FullBleed,
          bookWidthVp: this.cellWidth()
        })
        .onClick((): void => {
          this.openAllEntries();
        })
      } else if (slot.kind === 'book' && slot.notebook !== undefined) {
        ShelfBookView({
          name: slot.notebook.name,
          entryCount: this.countFor(slot.notebook),
          color: slot.notebook.bookColor,
          coverPhotoFilename: slot.notebook.coverPhotoFilename ?? '',
          layout: slot.notebook.coverLayout,
          bookWidthVp: this.cellWidth()
        })
        .onClick((): void => {
          this.openNotebook(slot);
        })
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
    .width(this.cellWidth())
    .height(this.cellHeight())
    .opacity(this.appeared ? 1 : 0)
    .translate({ y: this.appeared ? 0 : 20 })
    .animation({
      duration: 400,
      curve: Curve.EaseOut,
      delay: slotIndex * 60
    })
  }

  // ---- 几何（由内容区宽推：格宽 → 封面宽 → 格高） ----

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

  private isDarkTheme(): boolean {
    return this.theme.colorMode === 'dark';
  }

  // ---- 数据 ----

  /** 全部格子：全部日记 + 各本 + 新建 */
  private slots(): ShelfSlot[] {
    const slots: ShelfSlot[] = [new ShelfSlot('all', undefined, 'all')];
    for (const notebook of this.notebooks) {
      slots.push(new ShelfSlot('book', notebook, notebook.id));
    }
    slots.push(new ShelfSlot('new', undefined, 'new'));
    return slots;
  }

  /** 按列数分排（列数随断点变，行内容变键必变，自动重渲染） */
  private rows(): ShelfSlot[][] {
    const slots = this.slots();
    const perRow = this.columnCount();
    const rows: ShelfSlot[][] = [];
    for (let i = 0; i < slots.length; i += perRow) {
      const row: ShelfSlot[] = [];
      for (let j = i; j < i + perRow && j < slots.length; j++) {
        row.push(slots[j]);
      }
      rows.push(row);
    }
    return rows;
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

  // ---- 打开钩子（日记本主页是 3.3 的卡片，本卡只留钩子不跳转） ----

  private openAllEntries(): void {
    // TODO 3.3：pushPathByName('BookDetail', 'all')
  }

  private openNotebook(slot: ShelfSlot): void {
    if (slot.notebook === undefined) {
      return;
    }
    // TODO 3.3：pushPathByName('BookDetail', slot.notebook.id)
  }
}
