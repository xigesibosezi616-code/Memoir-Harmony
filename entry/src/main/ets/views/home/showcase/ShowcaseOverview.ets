/**
 * 大屏捏到一屏 16 / 64 篇时的总览：上下滚，按月分组、新的在上（U06
 * R-HOME-08）。对应 iOS `Views/Home/Overview/ShowcaseOverview.swift`。
 *
 * - 月份标题吸顶（34vp 行高，写法同列表模式）；点一格打开那篇
 * - 页首（尺素标题 + 加号）由 HomeView 固定在 List 上方，不随滚动（2026-10-23
 *   用户拍板：滚动时那一块不动、卡片从它下面滚走；iOS 是页首跟滚 + 滚出后
 *   浮现导航栏小标题，记为用户拍板偏差）
 * - 🔴 不卡铁律（U06 R-HOME-10）：List + LazyForEach（IDataSource）按
 *   **月**懒建组（一组 ≤31 格，行内格子的照片仍各自后台异步解）；
 *   格子大小外部算好传布局（相对宽 + 定死宽高比）；文字全用 digest
 *   （算一次记下来），不在画格子时解正文 JSON
 * - 换级进来时把手指底下那篇瞬时滚到原处（`pendingFocusIndex`，转场盖住
 *   跳变——同帧保位的近似：`ScrollAlign.CENTER` 锚点居中近似 iOS anchor）
 */
import { JournalEntry } from '../../../models/JournalEntry';
import { DigestMonth, EntryDigest, SHOWCASE_CELL_ASPECT,
  SHOWCASE_MONTH_HEADER_HEIGHT, overviewMonths, padOverviewRow,
  zoomColumns, zoomSpacing } from '../../../models/ShowcaseDigest';
import { digestOf } from '../../../models/ShowcaseDigest';
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../../services/LanguageManager';
import { OverviewCell } from './OverviewCell';

/** 一个月份段的显示数据（行懒算：getData 时才解 digest） */
class OverviewMonthBundle {
  readonly key: string;
  readonly title: string;
  readonly rows: EntryDigest[][];

  constructor(key: string, title: string, rows: EntryDigest[][]) {
    this.key = key;
    this.title = title;
    this.rows = rows;
  }
}

/** 月份段数据源（LazyForEach 要求 IDataSource；按月懒建，组内行一次成型） */
class OverviewMonthSource implements IDataSource {
  private listener: DataChangeListener | undefined = undefined;
  private months: DigestMonth[] = [];
  private entries: JournalEntry[] = [];
  private appLanguage: string = 'zh-Hans';

  set(months: DigestMonth[], entries: JournalEntry[], appLanguage: string): void {
    this.months = months;
    this.entries = entries;
    this.appLanguage = appLanguage;
    if (this.listener !== undefined) {
      this.listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.months.length;
  }

  getData(index: number): OverviewMonthBundle {
    const month = this.months[index];
    const cols = this.fixedColumns;
    const digests: EntryDigest[] = [];
    for (let i = month.startIndex; i < month.startIndex + month.count
      && i < this.entries.length; i++) {
      digests.push(digestOf(this.entries[i], this.appLanguage));
    }
    const rows: EntryDigest[][] = [];
    for (let i = 0; i < digests.length; i += cols) {
      const end = Math.min(i + cols, digests.length);
      const row: EntryDigest[] = [];
      for (let j = i; j < end; j++) {
        row.push(digests[j]);
      }
      // 尾行补占位格到满列：layoutWeight(1) 会把不满的行拉成全宽大卡
      rows.push(padOverviewRow(row, cols));
    }
    let latest = 0;
    for (let i = month.startIndex; i < month.startIndex + month.count
      && i < this.entries.length; i++) {
      latest = Math.max(latest, this.entries[i].updatedAt);
    }
    return new OverviewMonthBundle(
      `${month.month}#${month.count}#${latest}`, month.title, rows);
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listener = listener;
  }

  unregisterDataChangeListener(_listener: DataChangeListener): void {
    this.listener = undefined;
  }

  /** 由组件注入的固定列数（getData 建行时用） */
  fixedColumns: number = 4;
}

@Component
export struct ShowcaseOverview {
  /** 日记重查 / 换语言后重建月份数据（@Link 引用替换触发） */
  @Link @Watch('onDataChange') entries: JournalEntry[];
  /** 2 = 十六篇、3 = 六十四篇（分支按 zoom 拆，每级新建实例） */
  zoom: number = 2;
  /** 外部注入（HomeView 捏合时要读滚动位置） */
  scroller: ListScroller = new ListScroller();
  /** 换级进来时手指底下那篇（-1 = 无，滚到顶） */
  pendingFocusIndex: number = -1;
  onOpen: (id: string) => void = (_id: string): void => {};
  /** 调试行（脚手架，6.x 统一删） */
  @BuilderParam debugRow: () => void = emptyOverviewSlot;
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) @Watch('onDataChange')
  appLanguage: string = 'zh-Hans';

  private source: OverviewMonthSource = new OverviewMonthSource();

  aboutToAppear(): void {
    this.source.fixedColumns = zoomColumns(this.zoom);
    this.reload();
    if (this.pendingFocusIndex >= 0) {
      // 转场 400ms 盖住这次瞬时定位（布局就绪后再滚）
      const focus = this.pendingFocusIndex;
      setTimeout((): void => {
        this.scrollToFocus(focus);
      }, 66);
    }
  }

  build() {
    List({ scroller: this.scroller }) {
      LazyForEach(this.source, (bundle: OverviewMonthBundle) => {
        ListItemGroup({
          header: (): void => {
            this.monthHeader(bundle.title)
          }
        }) {
          ForEach(bundle.rows, (row: EntryDigest[]) => {
            ListItem() {
              Row({ space: zoomSpacing(this.zoom) }) {
                ForEach(row, (digest: EntryDigest) => {
                  if (digest.id.length === 0) {
                    // 占位格（尾行不满）：占住尺寸、不渲染不命中——相册逻辑
                    Column()
                      .layoutWeight(1)
                      .aspectRatio(SHOWCASE_CELL_ASPECT)
                  } else {
                    OverviewCell({
                      digest: digest,
                      zoom: this.zoom,
                      onOpen: this.onOpen
                    })
                      .layoutWeight(1)
                      .aspectRatio(SHOWCASE_CELL_ASPECT)
                  }
                }, (digest: EntryDigest, index?: number): string =>
                  digest.id.length > 0 ? digest.id : `filler-${index ?? 0}`)
              }
              .width('100%')
              .padding({ left: 18, right: 18 })
              .margin({ bottom: zoomSpacing(this.zoom) })
            }
          }, (row: EntryDigest[], index?: number): string => {
            const first = row.length > 0 ? row[0].id : 'empty';
            return `${index ?? 0}#${first}`;
          })
        }
      }, (bundle: OverviewMonthBundle): string => bundle.key)

      ListItem() {
        Column() {
          this.debugRow()
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }

      // 给 Tab 栏留白（iOS Spacer 96 同款位置）
      ListItem() {
        Column()
          .height(120)
          .width('100%')
      }
    }
    .sticky(StickyStyle.Header)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .id('showcaseOverviewList')
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }

  /** 组头：月份标题（写法同列表模式），吸顶时背景遮内容 */
  @Builder
  private monthHeader(title: string) {
    Row() {
      Text(title)
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
        .letterSpacing(this.theme.letterSpacingWide)
    }
    .padding({ left: 18, right: 18, bottom: 8 })
    .width('100%')
    .height(SHOWCASE_MONTH_HEADER_HEIGHT)
    .alignItems(VerticalAlign.Bottom)
    .backgroundColor(this.theme.background)
  }

  private reload(): void {
    this.source.set(overviewMonths(this.entries, this.appLanguage),
      this.entries, this.appLanguage);
  }

  private onDataChange(): void {
    this.reload();
  }

  /** 手指底下那篇瞬时滚到原处（组下标 = 月份数组下标：List 第 0 个孩子就是月份组） */
  private scrollToFocus(focusIndex: number): void {
    if (focusIndex < 0 || focusIndex >= this.entries.length) {
      return;
    }
    const months = overviewMonths(this.entries, this.appLanguage);
    const columns = zoomColumns(this.zoom);
    for (let g = 0; g < months.length; g++) {
      const month = months[g];
      if (focusIndex >= month.startIndex
        && focusIndex < month.startIndex + month.count) {
        const rowIndex = Math.floor((focusIndex - month.startIndex) / columns);
        try {
          // CENTER 而非 START：iOS scrollTo(id:anchor:) 是锚点对齐，START 会让
          // 尾部月份组置顶时超出 maxOffset 被钳到列表底（走查 ③ 根因）
          this.scroller.scrollToItemInGroup(g, rowIndex, false, ScrollAlign.CENTER);
        } catch (err) {
          // 布局未就绪等：转场盖着，滚不到也不闪（下次进这级滚到顶）
        }
        return;
      }
    }
  }
}

@Builder
function emptyOverviewSlot() {
}
