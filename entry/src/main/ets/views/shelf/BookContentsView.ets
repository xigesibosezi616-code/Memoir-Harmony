/**
 * 日记本的目录（10_BUILD_MANUAL.md 3.3，R-BOOK-10）。对应 iOS
 * `Views/Home/BookHome/BookContentsView.swift`。
 *
 * 日记按**阅读顺序（从早到晚）**排好再传进来，编号就是在这本里的第几篇——
 * 和翻页阅读器往后翻的方向一致。两种版式（偏好由外面传进来）：
 * - **列表**：按月分组，每行「编号 · 标题 · 日期」，标题回退链见 BookContentsLogic
 * - **宫格**：三列小样（有照片的上半照片下面标题，没照片的标题 + 几行正文），
 *   最后一格「写一篇」
 *
 * 点目录里任一篇 / 最后一格由 `onOpen` / `onCompose` 回调交给父组件
 * （3.3 留 TODO 钩子，3.5 翻页阅读器接通）。
 */
import { JournalEntry } from '../../models/JournalEntry';
import { image } from '@kit.ImageKit';
import { LengthMetrics } from '@kit.ArkUI';
import {
  BookContentsItem,
  BookMonthGroup,
  bookMonthGroups,
  contentsTitle
} from '../../data/BookContentsLogic';
import { PhotoPaperIO } from '../../services/PhotoPaperIO';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';

/** 宫格小样的照片：占这页上面六成多的方形（iOS EntryPageThumbnail） */
const GRID_COLUMNS: number = 3;
const GRID_SPACING: number = 14;
const GRID_ROW_SPACING: number = 18;
/** 小样页宽高比（与封面一致 0.73） */
const PAGE_ASPECT: number = 0.73;

/** 宫格里的一个小样：一本篇日记（照片 + 缩略数据，键用 entry id） */
class GridCell {
  readonly entryId: string;
  readonly number: number;
  readonly title: string;
  readonly preview: string;
  readonly coverPhotoFilename: string;
  readonly entry: JournalEntry;

  constructor(item: BookContentsItem) {
    this.entryId = item.entry.id;
    this.number = item.number;
    this.title = item.title;
    this.preview = item.entry.textPreview;
    this.coverPhotoFilename = item.entry.coverPhotoFilename ?? '';
    this.entry = item.entry;
  }
}

/** 宫格里的一页小样（有照片上图下标题，没照片的标题 + 几行正文） */
@Component
struct EntryPageThumbnail {
  @Prop title: string = '';
  @Prop preview: string = '';
  @Prop coverPhotoFilename: string = '';
  /** 目录标题是否为空（空 = 显示「无题」资源） */
  @Prop titleEmpty: boolean = false;
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @State private photoPixelMap: image.PixelMap | undefined = undefined;

  aboutToAppear(): void {
    if (this.coverPhotoFilename.length === 0) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    PhotoPaperIO.forFilesDir(context.filesDir)
      .loadImage(this.coverPhotoFilename)
      .then((pixelMap: image.PixelMap | undefined): void => {
        this.photoPixelMap = pixelMap;
      })
      .catch((): void => {
      });
  }

  build() {
    Column({ space: 4 }) {
      if (this.coverPhotoFilename.length > 0) {
        // 有照片：照片取方形，占这页上面六成多，下面留给标题
        Stack() {
          if (this.photoPixelMap !== undefined) {
            Image(this.photoPixelMap)
              .objectFit(ImageFit.Cover)
              .width('100%')
              .height('100%')
          } else {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('rgba(232,221,201,0.5)')
          }
        }
        .width('100%')
        .aspectRatio(1)
        .clip(true)
      }
      if (this.titleEmpty) {
        Text($r('app.string.s_6a576f3bf9'))
          .fontSize(9)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.theme.titleFont.family)
          .fontColor(this.theme.textPrimary)
          .maxLines(2)
      } else {
        Text(this.title)
          .fontSize(9)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.theme.titleFont.family)
          .fontColor(this.theme.textPrimary)
          .maxLines(2)
      }
      if (this.coverPhotoFilename.length === 0) {
        // 没照片：一页纸，标题下面再垫几行正文
        Text(this.preview)
          .fontSize(7)
          .fontColor(this.theme.textSecondary)
          .lineSpacing(LengthMetrics.vp(1.5))
          .maxLines(9)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(7)
    .backgroundColor(this.theme.cardBackground)
    .aspectRatio(PAGE_ASPECT)
    .clip(true)
    .borderRadius(3)
    .border({ width: 0.5, color: this.theme.border })
    .shadow({
      radius: 3,
      color: 'rgba(0,0,0,0.06)',
      offsetX: 0,
      offsetY: 2
    })
  }
}

@Component
export struct BookContentsView {
  /** 已按阅读顺序排好 */
  @Prop entries: JournalEntry[] = [];
  /** 列表 / 宫格 */
  @Prop layout: string = 'list';
  /** 点某一篇（3.5 翻页阅读器接通，本卡父组件留钩子） */
  onOpen: (entry: JournalEntry) => void = (_entry: JournalEntry): void => {};
  /** 最后一格「写一篇」 */
  onCompose: () => void = (): void => {};
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';

  build() {
    if (this.layout === 'grid') {
      this.gridView()
    } else {
      this.listView()
    }
  }

  /** 按月分组（build 时算；语言 / 库变化触发重渲染自动重算） */
  private groups(): BookMonthGroup[] {
    return bookMonthGroups(this.entries, this.appLanguage);
  }

  // ---- 列表：按月分组，编号 · 标题 · 日期 ----

  @Builder
  private listView() {
    Column() {
      ForEach(this.groups(), (group: BookMonthGroup) => {
        Text(group.title)
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textTertiary)
          .letterSpacing(this.theme.letterSpacingWide)
          .margin({ top: 22, bottom: 4 })
          .width('100%')
        ForEach(group.items, (item: BookContentsItem) => {
          this.listRow(item)
        }, (item: BookContentsItem): string => item.entry.id)
      }, (group: BookMonthGroup): string => `${group.id}#${group.items.length}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 22, right: 22 })
  }

  @Builder
  private listRow(item: BookContentsItem) {
    Row() {
      Text(`${item.number}`)
        .fontSize(13)
        .fontFamily(this.theme.titleFont.family)
        .fontColor(this.theme.textTertiary)
        .width(36)
      if (item.title.length === 0) {
        Text($r('app.string.s_6a576f3bf9'))
          .fontSize(this.theme.bodyFont.size)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .maxLines(1)
          .layoutWeight(1)
      } else {
        Text(item.title)
          .fontSize(this.theme.bodyFont.size)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      Text(item.dayTitle)
        .fontSize(this.theme.captionFont.size)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
        .margin({ left: 12 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Bottom)
    .padding({ top: 15, bottom: 15 })
    .border({ width: { bottom: 0.5 }, color: this.theme.border })
    .onClick((): void => {
      this.onOpen(item.entry);
    })
  }

  // ---- 宫格：一页页小样 ----

  private gridCells(): GridCell[] {
    const cells: GridCell[] = [];
    let number = 0;
    for (const entry of this.entries) {
      number++;
      const item = new BookContentsItem(number, '', contentsTitle(entry), entry);
      cells.push(new GridCell(item));
    }
    return cells;
  }

  @Builder
  private gridView() {
    GridRow({
      columns: GRID_COLUMNS,
      gutter: { x: GRID_SPACING, y: GRID_ROW_SPACING }
    }) {
      ForEach(this.gridCells(), (cell: GridCell) => {
        GridCol() {
          Column({ space: 6 }) {
            EntryPageThumbnail({
              title: cell.title,
              titleEmpty: cell.title.length === 0,
              preview: cell.preview,
              coverPhotoFilename: cell.coverPhotoFilename
            })
            Text(`${cell.number}`)
              .fontSize(11)
              .fontFamily(this.theme.titleFont.family)
              .fontColor(this.theme.textTertiary)
          }
          .onClick((): void => {
            this.onOpen(cell.entry);
          })
        }
      }, (cell: GridCell): string => cell.entryId)
      // 最后一格：写一篇（参考图 ⑤ 的 Add）
      GridCol() {
        Column({ space: 6 }) {
          Column({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(18)
              .fontWeight(FontWeight.Lighter)
              .fontColor([this.theme.textTertiary])
            Text($r('app.string.s_85f02cfb34'))
              .fontSize(11)
              .fontColor(this.theme.textTertiary)
          }
          .width('100%')
          .aspectRatio(PAGE_ASPECT)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .borderRadius(3)
          .border({
            width: 0.8,
            color: this.theme.border,
            style: BorderStyle.Dashed
          })
        }
        .onClick((): void => {
          this.onCompose();
        })
      }
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 18 })
  }
}
