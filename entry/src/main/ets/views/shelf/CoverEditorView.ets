/**
 * 封面编辑器（10_BUILD_MANUAL.md 3.4，R-BOOK-12~16）。对应 iOS
 * `BookCustomizerView.swift`（编辑器本体）+ `CreateTagSheet`（新建入口）+
 * `CoverChangeSheet`（日记本页「…」入口），鸿蒙侧合并为一个路由页双模式。
 *
 * 从上到下：预览 → 封面照片 → 版式（有照片时）→ 颜色（没照片、或版式是
 * 「贴照片」时）→ 副标题；新建模式顶上多一个名称输入（撞名当场红字）。
 * 照片在前、颜色在后：把用户引向「用自己的照片做封面」，颜色只是退路。
 *
 * 落盘时机（用户拍板，与 iOS 的偏差记 PROGRESS 3.4）：**构图完成即落盘**
 * 成正式文件（`cover_<UUID>.jpg`，q85），预览走文件加载链路（BookCoverView
 * 直接读文件）；取消编辑删掉这次会话产生的文件；「清理残留文件」兜底。
 * 点「创建 / 应用」时写库 + 删旧文件（R-BOOK-16 本地部分；云端副本 Q3）。
 *
 * 会员钩子（R-MEMBER-06）：`needsMembershipCoverLayout` 照搬 iOS
 * `MembershipRules.swift`；`isMember()` 占位 true（7.2 接会员状态，
 * 届时会员版式角标显示、保存前拉 paywall）。
 */
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BOOK_COLOR_ORDER,
  BookColor,
  CoverLayout,
  Notebook,
  bookColorHex,
  cleanedName,
  isNameTaken,
  nextSortOrder
} from '../../models/Notebook';
import {
  CoverCropRect,
  CoverPhotoDraftKind,
  cleanSubtitle,
  isMemberOnlyCoverLayout,
  needsMembershipCoverLayout,
  truncateSubtitle
} from '../../models/CoverEdit';
import { generateUuid } from '../../models/Uuid';
import { NotebookRepository } from '../../data/NotebookRepository';
import { AppDatabase } from '../../data/Database';
import { STORAGE_KEY_HOME_RELOAD_TICK } from '../../data/HomeLogic';
import { PhotoLibraryPicker, PickedCoverSource } from '../../services/PhotoLibraryPicker';
import { NotebookCoverStore } from '../../services/NotebookCoverStore';
import {
  STORAGE_KEY_HIDE_TAB_BAR,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP,
  STORAGE_KEY_SAFE_AREA_TOP_VP
} from '../../services/ImmersiveChrome';
import { AppEnvironment } from '../../environment/AppEnvironment';
import { ErrorToastKind } from '../../environment/ErrorPresenter';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { BookCoverView } from './BookCoverView';
import { CoverCropOverlay } from './CoverCropOverlay';

const DOMAIN = 0x0000;
const TAG = 'CoverEditorView';

/** 路由参数：'create' = 新建模式，其余 = 日记本 id（编辑模式） */
export const COVER_EDITOR_CREATE_PARAM: string = 'create';

/** 顶栏一行的高（返回 / 标题 / 创建|应用） */
const TOP_BAR_ROW_HEIGHT_VP: number = 44;

@Builder
export function CoverEditorBuilder() {
  CoverEditorView()
}

/** 预览封面宽（vp）。iOS frame(width: 150)；2026-10-21 真机反馈 150 时
 * 页尾副标题区被压出屏，缩到 120 让整页一屏内显示完（记 iOS 偏差） */
const PREVIEW_WIDTH_VP: number = 120;

/** 版式缩略图宽（vp，iOS frame(width: 66)） */
const LAYOUT_THUMB_WIDTH_VP: number = 66;

/** 颜色圆点直径（vp，iOS frame 36） */
const COLOR_DOT_SIZE_VP: number = 36;

@Component
export struct CoverEditorView {
  @Consume env: AppEnvironment;
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @StorageProp(STORAGE_KEY_HOME_RELOAD_TICK) homeReloadTick: number = 0;

  /** 新建模式？否则编辑模式（notebook 必有） */
  @State private isCreate: boolean = true;
  @State private notebook: Notebook | undefined = undefined;

  // ---- 编辑中的草稿（点「创建 / 应用」才写库） ----
  @State private nameInput: string = '';
  @State private draftColor: BookColor = BookColor.PineGreen;
  @State private draftLayout: CoverLayout = CoverLayout.FullBleed;
  @State private subtitleInput: string = '';
  /** 照片改动三态（iOS CoverPhotoDraft） */
  @State private photoKind: CoverPhotoDraftKind = CoverPhotoDraftKind.Unchanged;
  /** Replaced 的会话文件名（构图完成即落盘的那个） */
  @State private sessionPhotoFilename: string = '';

  // ---- 进行中状态 ----
  @State private isLoadingPhoto: boolean = false;
  @State private isRendering: boolean = false;
  @State private showCrop: boolean = false;
  @State private cropPixelMap: image.PixelMap | undefined = undefined;

  private navPathStack: NavPathStack = new NavPathStack();
  private notebookId: string = '';
  /** 全部日记本（新建模式撞名判定 + 排序号推算用） */
  private existingNotebooks: Notebook[] = [];
  /** 这次新选照片的原始字节（调整构图从它重裁，不在裁过的图上再裁） */
  private pickedBuffer: ArrayBuffer | undefined = undefined;
  private pickedPreview: image.PixelMap | undefined = undefined;
  /** 构图浮层的重裁来源：会话/已有文件名（'' = 从 pickedBuffer 重裁） */
  private cropSourceFilename: string = '';

  /** 整页藏浮动 Tab 栏（iOS 是 sheet 天生无 Tab 栏；barOverlap 层压不住，
   * 走 STORAGE_KEY_HIDE_TAB_BAR → barOpacity 0，ComposeView 同款先例）。
   * 全屏归内容后副标题最底行也一页内显示完（2026-10-21 真机反馈） */
  aboutToAppear(): void {
    AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, true);
  }

  aboutToDisappear(): void {
    // 边滑返回也要恢复，别把书架页的 Tab 栏一直藏着
    AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, false);
  }

  build() {
    NavDestination() {
      Stack() {
        Scroll() {
          // iOS 是 sheet（无 Tab 栏）；本页整页藏浮动 Tab 栏
          // （STORAGE_KEY_HIDE_TAB_BAR → barOpacity 0，ComposeView 同款），
          // 全屏都归内容，副标题最底行一页内显示完（2026-10-21 真机反馈）
          Column({ space: 26 }) {
            if (this.isCreate) {
              this.nameSection()
            }
            this.previewSection()
            this.photoSection()
            if (this.previewHasPhoto()) {
              this.layoutSection()
            }
            if (this.showsColors()) {
              this.colorSection()
            }
            this.subtitleSection()
            Column()
              .width('100%')
              .height(this.safeAreaBottomVp + 32)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 22, right: 22 })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .margin({ top: this.safeAreaTopVp + TOP_BAR_ROW_HEIGHT_VP + 8 })

        this.topBar()

        // 调整构图：页面内全屏浮层（相机 / 全屏照片同款挂法，不走路由）
        if (this.showCrop && this.cropPixelMap !== undefined) {
          CoverCropOverlay({
            pixelMap: this.cropPixelMap,
            onDone: (rect: CoverCropRect): void => {
              this.cropDone(rect);
            },
            onCancel: (): void => {
              this.showCrop = false;
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.background)
    }
    .hideTitleBar(true)
    .backgroundColor(this.theme.background)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      // 边界一次断言：pushPathByName 传的是 string（书架/日记本主页）
      const raw = ctx.pathInfo.param as Record<string, Object> | string | undefined;
      if (typeof raw === 'string') {
        this.isCreate = raw === COVER_EDITOR_CREATE_PARAM;
        this.notebookId = this.isCreate ? '' : raw;
      } else {
        this.isCreate = true;
      }
      this.load();
    })
  }

  // ---- 名称（新建模式） ----

  @Builder
  private nameSection() {
    Column({ space: 8 }) {
      Text($r('app.string.s_1be7ae4fc2'))
        .fontSize(13)
        .fontColor(this.theme.textSecondary)
      TextInput({
        placeholder: $r('app.string.s_ae002a8a37'),
        text: this.nameInput
      })
        .fontSize(this.theme.bodyFont.size)
        .fontColor(this.theme.textPrimary)
        .caretColor(this.theme.textSecondary)
        .backgroundColor(this.theme.surfaceBackground)
        .borderRadius(10)
        .padding({ left: 12, right: 12 })
        .height(42)
        .onChange((value: string): void => {
          this.nameInput = value;
        })
      // 当场说明为什么「创建」是灰的（R-BOOK-03）
      if (this.isNameTakenNow()) {
        Text($r('app.string.s_b477b8791b'))
          .fontSize(12)
          .fontColor(this.theme.destructive)
          .opacity(0.8)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ---- 大图预览（实时反映当前选择） ----

  @Builder
  private previewSection() {
    Stack() {
      BookCoverView({
        name: this.previewName(),
        entryCount: 0,
        color: this.draftColor,
        coverPhotoFilename: this.previewPhotoFilename(),
        layout: this.draftLayout,
        coverWidthVp: PREVIEW_WIDTH_VP
      })
      if (this.isLoadingPhoto || this.isRendering) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(this.theme.textSecondary)
      }
    }
    .width('100%')
    .alignContent(Alignment.Center)
  }

  // ---- 封面照片 ----

  @Builder
  private photoSection() {
    Column({ space: 12 }) {
      Text($r('app.string.s_8ee0b6f9eb'))
        .fontSize(13)
        .fontColor(this.theme.textSecondary)

      if (!this.previewHasPhoto()) {
        // 没照片：虚线选图按钮，点了直接进构图（R-BOOK-12）
        Column({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.picture_on_square'))
            .fontSize(22)
            .fontWeight(FontWeight.Lighter)
            .fontColor([this.theme.textPrimary])
          Text($r('app.string.s_518462faa6'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.textPrimary)
          Text($r('app.string.s_0c168f5d2c'))
            .fontSize(12)
            .fontColor(this.theme.textSecondary)
        }
        .width('100%')
        .padding({ top: 18, bottom: 18 })
        .borderRadius(10)
        .border({
          width: 1,
          color: this.theme.border,
          style: BorderStyle.Dashed
        })
        .onClick((): void => {
          this.pickPhoto();
        })
      } else {
        // 有照片：更换 / 调整构图 / 移除（iOS Label 同款三项）
        Row({ space: 24 }) {
          this.photoActionButton($r('app.string.s_0498f1dcc0'),
            $r('sys.symbol.picture'), this.theme.textPrimary, (): void => {
              this.pickPhoto();
            })
          this.photoActionButton($r('app.string.s_c62079d2ba'),
            $r('sys.symbol.crop_rotate'), this.theme.textPrimary, (): void => {
              this.adjustComposition();
            })
          this.photoActionButton($r('app.string.s_2f752c005e'),
            $r('sys.symbol.xmark_circle'), this.theme.destructive, (): void => {
              this.removePhoto();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private photoActionButton(labelRes: Resource, iconRes: Resource,
    labelColor: ResourceColor, onTap: () => void) {
    Row({ space: 5 }) {
      SymbolGlyph(iconRes)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor([labelColor])
      Text(labelRes)
        .fontSize(14)
        .fontColor(labelColor)
    }
    .onClick((): void => {
      onTap();
    })
  }

  // ---- 版式（有照片时；会员版式照样能选，保存时才问 —— R-MEMBER-06） ----

  @Builder
  private layoutSection() {
    Column({ space: 12 }) {
      Text($r('app.string.s_431c606023'))
        .fontSize(13)
        .fontColor(this.theme.textSecondary)
      Row({ space: 18 }) {
        this.layoutThumb(CoverLayout.FullBleed, $r('app.string.s_d3fc6fa5bc'))
        this.layoutThumb(CoverLayout.Framed, $r('app.string.s_333ab56285'))
        this.layoutThumb(CoverLayout.TipIn, $r('app.string.s_9a15479618'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private layoutThumb(layout: CoverLayout, labelRes: Resource) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        BookCoverView({
          name: this.previewName(),
          entryCount: 0,
          color: this.draftColor,
          coverPhotoFilename: this.previewPhotoFilename(),
          layout: layout,
          coverWidthVp: LAYOUT_THUMB_WIDTH_VP
        })
        // 会员角标（7.2 接会员状态后对非会员显示；isMember 占位 true 期间不出现）
        if (isMemberOnlyCoverLayout(layout) && !this.isMember()) {
          Stack() {
            SymbolGlyph($r('sys.symbol.star'))
              .fontSize(9)
              .fontColor([this.theme.cardBackground])
          }
          .width(16)
          .height(16)
          .borderRadius(8)
          .backgroundColor(this.theme.accent)
          .offset({ x: 6, y: -6 })
        }
      }
      Text(labelRes)
        .fontSize(12)
        .fontColor(this.draftLayout === layout ? this.theme.textPrimary : this.theme.textSecondary)
    }
    .onClick((): void => {
      this.setDraftLayout(layout);
    })
  }

  // ---- 颜色（没照片 = 封面本色；贴照片 = 照片底下的布面） ----

  @Builder
  private colorSection() {
    Column({ space: 12 }) {
      Text(this.showsColors() && this.previewHasPhoto()
        ? $r('app.string.s_9f0103656b') : $r('app.string.s_e7ec4d5c09'))
        .fontSize(13)
        .fontColor(this.theme.textSecondary)
      Scroll() {
        Row({ space: 14 }) {
          ForEach(BOOK_COLOR_ORDER, (color: BookColor) => {
            this.colorDot(color)
          }, (color: BookColor): string => color)
        }
        .padding({ top: 6, bottom: 6 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .align(Alignment.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private colorDot(color: BookColor) {
    Stack() {
      Circle({ width: COLOR_DOT_SIZE_VP, height: COLOR_DOT_SIZE_VP })
        .fill(bookColorHex(color))
      // 象牙白本身浅，加细描边让它在浅背景上可见（iOS 同款）
      if (color === BookColor.Ivory) {
        Circle({ width: COLOR_DOT_SIZE_VP, height: COLOR_DOT_SIZE_VP })
          .fill(Color.Transparent)
          .stroke('#D4C9B8')
          .strokeWidth(0.5)
      }
      // 选中态：外凸 2pt 外环
      if (this.draftColor === color) {
        Circle({ width: COLOR_DOT_SIZE_VP + 8, height: COLOR_DOT_SIZE_VP + 8 })
          .fill(Color.Transparent)
          .stroke('#3D3428')
          .strokeWidth(2)
      }
    }
    .width(COLOR_DOT_SIZE_VP + 8)
    .height(COLOR_DOT_SIZE_VP + 8)
    .onClick((): void => {
      this.draftColor = color;
    })
  }

  // ---- 副标题（可选） ----

  @Builder
  private subtitleSection() {
    Column({ space: 8 }) {
      Text($r('app.string.s_9101853a76'))
        .fontSize(13)
        .fontColor(this.theme.textSecondary)
      TextInput({
        placeholder: $r('app.string.s_fe1629f682'),
        text: this.subtitleInput
      })
        .fontSize(this.theme.bodyFont.size)
        .fontColor(this.theme.textPrimary)
        .caretColor(this.theme.textSecondary)
        .backgroundColor(this.theme.surfaceBackground)
        .borderRadius(10)
        .padding({ left: 12, right: 12 })
        .height(42)
        .onChange((value: string): void => {
          this.subtitleInput = truncateSubtitle(value);
        })
      Text($r('app.string.s_111bf28fb7'))
        .fontSize(12)
        .fontColor(this.theme.textSecondary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ---- 顶栏：返回 / 标题 / 创建|应用 ----

  @Builder
  private topBar() {
    Stack() {
      Row() {
        // 返回：官方 Button 圆钮（2026-10-21 真机反馈看不清，逐主题调教）：
        // 主题 glassBackground 半透明玻璃片 + 0.5vp glassBorder 成型、
        // 图标 textPrimary —— 素笺 暖灰片/皮革 金片/肯特 浅灰片对各自
        // 页面底都有一档明度差，图标对玻璃片对比 素笺 9.9 / 皮革 5.1 / 肯特 13.9
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
          this.cancel();
        })
        Blank()
        // 创建/应用：官方 Button 胶囊主行动（2026-10-21 真机反馈：原裸
        // accent 文字看不清）。逐主题调教：主题 accent 实底 + 主题
        // background 字 —— 素笺 墨绿底米白字 / 皮革 金底深棕字 / 肯特
        // 黑底白字，按钮本体对页面底全部 ≥3.5:1 成型清晰；不可用时降
        // surfaceBackground 底 + textTertiary 字（iOS 灰字同语义）
        Button(this.isCreate ? $r('app.string.s_fcbd093292') : $r('app.string.s_4562024dde'),
          { type: ButtonType.Capsule, stateEffect: true })
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.canApply() ? this.theme.background : this.theme.textTertiary)
          .backgroundColor(this.canApply() ? this.theme.accent : this.theme.surfaceBackground)
          .height(32)
          .padding({ left: 16, right: 16 })
          .onClick((): void => {
            this.apply();
          })
      }
      .width('100%')
      .height(TOP_BAR_ROW_HEIGHT_VP)
      .padding({ left: 6, right: 6 })
      .alignItems(VerticalAlign.Center)
      // 坑（BookDetailView 顶栏同款，真机反馈按钮顶进状态栏）：Stack 里
      // 不定位的子项居中在整块（状态栏 + 44 行）上，按钮行会被抬进状态栏
      // 半格 —— margin 顶一下，让 44 行正好落在状态栏下面
      .margin({ top: this.safeAreaTopVp })

      // 居中标题（触摸穿透给两边的按钮）
      Row() {
        Text(this.isCreate ? $r('app.string.s_c7a3044d8f') : $r('app.string.s_ce3e4010fe'))
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
      // 同上：标题也要显式钉在状态栏下面那行里居中，否则压进状态栏
      .position({ x: 0, y: this.safeAreaTopVp })
    }
    .width('100%')
    .height(this.safeAreaTopVp + TOP_BAR_ROW_HEIGHT_VP)
    .position({ x: 0, y: 0 })
  }

  // ---- 草稿读取（预览 / 落盘共用） ----

  /** 预览封面上现在有没有照片（Replaced → 有；Removed → 无；Unchanged → 看原来） */
  private previewHasPhoto(): boolean {
    switch (this.photoKind) {
      case CoverPhotoDraftKind.Replaced:
        return this.sessionPhotoFilename.length > 0;
      case CoverPhotoDraftKind.Removed:
        return false;
      default:
        return this.existingPhotoFilename().length > 0;
    }
  }

  /** 预览用的封面文件名（走 BookCoverView 的文件加载链路） */
  private previewPhotoFilename(): string {
    switch (this.photoKind) {
      case CoverPhotoDraftKind.Replaced:
        return this.sessionPhotoFilename;
      case CoverPhotoDraftKind.Removed:
        return '';
      default:
        return this.existingPhotoFilename();
    }
  }

  /** 这本原来的照片封面文件名（新建模式没有） */
  private existingPhotoFilename(): string {
    const notebook = this.notebook;
    return notebook !== undefined ? (notebook.coverPhotoFilename ?? '') : '';
  }

  /** 预览封面上的书名：新建 = 正在输入的名字（去首尾空白）；编辑 = 原名 */
  private previewName(): string {
    if (this.isCreate) {
      return cleanedName(this.nameInput);
    }
    return this.notebook !== undefined ? this.notebook.name : '';
  }

  /** 颜色栏出现条件：没照片，或版式是「贴照片」（布面透出来可选，R-BOOK-13） */
  private showsColors(): boolean {
    return !this.previewHasPhoto() || this.draftLayout === CoverLayout.TipIn;
  }

  /** 撞名判定（新建模式；判重键 nameKey：忽略大小写 / 全半角） */
  private isNameTakenNow(): boolean {
    return isNameTaken(this.nameInput, this.existingNames());
  }

  private existingNames(): string[] {
    const names: string[] = [];
    for (const notebook of this.existingNotebooks) {
      names.push(notebook.name);
    }
    return names;
  }

  /** 「创建 / 应用」可用：新建要名字非空且不撞名；编辑随时可应用 */
  private canApply(): boolean {
    if (this.isCreate) {
      return cleanedName(this.nameInput).length > 0 && !this.isNameTakenNow();
    }
    return true;
  }

  /** 会员状态占位：7.2 接真状态（R-MEMBER-06 的角标与保存前 paywall 都看它） */
  private isMember(): boolean {
    return true;
  }

  private setDraftLayout(layout: CoverLayout): void {
    if (this.draftLayout !== layout) {
      this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut }, (): void => {
        this.draftLayout = layout;
      });
    }
  }

  // ---- 照片动作 ----

  /** 从相册选一张 → 拿到原始字节 + 预览解码 → 直接进构图（R-BOOK-12） */
  private async pickPhoto(): Promise<void> {
    if (this.isLoadingPhoto || this.isRendering || this.showCrop) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.isLoadingPhoto = true;
    const picked: PickedCoverSource | undefined = await PhotoLibraryPicker.pickCoverSource(context);
    this.isLoadingPhoto = false;
    if (picked === undefined) {
      // 取消 / 失败静默收场（2.6 拍板；与 iOS 的「照片加载失败」toast 偏差记 PROGRESS）
      return;
    }
    this.pickedBuffer = picked.buffer;
    this.pickedPreview = picked.previewPixelMap;
    this.cropPixelMap = picked.previewPixelMap;
    this.cropSourceFilename = '';
    this.showCrop = true;
  }

  /**
   * 调整构图（iOS adjustComposition）：新选的照片从原始字节重裁；
   * 原来就有的封面只能在已裁好的那张里再调（原图没留）。
   */
  private async adjustComposition(): Promise<void> {
    if (this.isLoadingPhoto || this.isRendering || this.showCrop) {
      return;
    }
    if (this.photoKind === CoverPhotoDraftKind.Replaced) {
      if (this.pickedPreview !== undefined && this.pickedBuffer !== undefined) {
        this.cropPixelMap = this.pickedPreview;
        this.cropSourceFilename = '';
        this.showCrop = true;
        return;
      }
      // 没留原始字节（极端情况）：从会话文件全尺寸重解
      if (this.sessionPhotoFilename.length > 0) {
        this.openCropFromFile(this.sessionPhotoFilename);
      }
      return;
    }
    const existing = this.existingPhotoFilename();
    if (existing.length === 0) {
      return;
    }
    this.openCropFromFile(existing);
  }

  private async openCropFromFile(filename: string): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.isLoadingPhoto = true;
    const source = await NotebookCoverStore.forFilesDir(context.filesDir)
      .decodeSourceFromFile(filename);
    this.isLoadingPhoto = false;
    if (source === undefined) {
      this.presentLoadFailure();
      return;
    }
    this.cropPixelMap = source;
    this.cropSourceFilename = filename;
    this.showCrop = true;
  }

  /** 移除照片：原来有 → 标记移除；原来没有（这次新选的）→ 回到「没改」 */
  private removePhoto(): void {
    this.discardSessionFile();
    this.pickedBuffer = undefined;
    this.pickedPreview = undefined;
    this.photoKind = this.existingPhotoFilename().length > 0
      ? CoverPhotoDraftKind.Removed : CoverPhotoDraftKind.Unchanged;
  }

  /** 构图完成：关浮层、按取景框烤盘（构图完成即落盘，用户拍板） */
  private cropDone(rect: CoverCropRect): void {
    this.showCrop = false;
    this.renderCrop(rect);
  }

  private async renderCrop(rect: CoverCropRect): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.isRendering = true;
    const coverStore = NotebookCoverStore.forFilesDir(context.filesDir);
    let filename: string | undefined = undefined;
    if (this.cropSourceFilename.length === 0 && this.pickedBuffer !== undefined) {
      filename = await coverStore.renderCoverFromBuffer(this.pickedBuffer, rect);
    } else if (this.cropSourceFilename.length > 0) {
      filename = await coverStore.renderCoverFromFile(this.cropSourceFilename, rect);
    }
    this.isRendering = false;
    if (filename === undefined) {
      this.presentLoadFailure();
      return;
    }
    // 上一个会话文件作废（连删）
    this.discardSessionFile();
    this.sessionPhotoFilename = filename;
    this.photoKind = CoverPhotoDraftKind.Replaced;
  }

  /** 删掉这次会话产生的封面文件（取消编辑 / 换掉 / 移除时） */
  private discardSessionFile(): void {
    if (this.sessionPhotoFilename.length === 0) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    NotebookCoverStore.forFilesDir(context.filesDir).deleteCover(this.sessionPhotoFilename);
    this.sessionPhotoFilename = '';
  }

  // ---- 创建 / 应用 / 取消 ----

  /** 取消编辑：删掉会话文件再退（会话文件没写库，留着就是孤儿） */
  private cancel(): void {
    if (this.isRendering) {
      return;
    }
    this.discardSessionFile();
    this.navPathStack.pop();
  }

  private async apply(): Promise<void> {
    if (this.isRendering || this.isLoadingPhoto || this.showCrop || !this.canApply()) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    // 会员钩子（R-MEMBER-06）：新选了会员版式且保存后有照片才拦；
    // isMember 占位 true，7.2 接真状态后在这里拉 paywall
    const originalLayout: CoverLayout | undefined = this.originalLayoutForMembership();
    const hasExistingPhoto = this.existingPhotoFilename().length > 0;
    if (needsMembershipCoverLayout(this.draftLayout, originalLayout, this.photoKind,
      hasExistingPhoto) && !this.isMember()) {
      // TODO 7.2：paywall
    }
    if (this.isCreate) {
      await this.applyCreate(context);
    } else {
      await this.applyUpdate(context);
    }
  }

  /** 原来（这本）的版式；没照片版式不起作用 → undefined；新建模式 undefined */
  private originalLayoutForMembership(): CoverLayout | undefined {
    const notebook = this.notebook;
    if (notebook === undefined || (notebook.coverPhotoFilename ?? '').length === 0) {
      return undefined;
    }
    return notebook.coverLayout;
  }

  /** 新建日记本（iOS CreateTagSheet onCreate）：默认墨绿、排书架最后 */
  private async applyCreate(context: common.Context): Promise<void> {
    const name = cleanedName(this.nameInput);
    if (name.length === 0 || isNameTaken(name, this.existingNames())) {
      return;
    }
    const now = Date.now();
    const notebook = new Notebook(generateUuid(), name, now, now);
    notebook.colorId = this.draftColor;
    notebook.sortOrder = nextSortOrder(
      this.existingNotebooks.map((n: Notebook): number => n.sortOrder));
    this.applyDraftToNotebook(notebook);
    try {
      const store = await AppDatabase.open(context);
      await NotebookRepository.insertNotebook(store, notebook);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'create notebook failed name=%{public}s: %{public}s',
        name, JSON.stringify(err));
      this.presentSaveFailed();
      return;
    }
    this.sessionPhotoFilename = ''; // 会话文件已被这本采用
    this.bumpReloadTick();
    this.navPathStack.pop();
  }

  /** 编辑封面（iOS CoverChangeSheet onSave）：写库 + 删旧文件（R-BOOK-16 本地部分） */
  private async applyUpdate(context: common.Context): Promise<void> {
    const notebook = this.notebook;
    if (notebook === undefined) {
      return;
    }
    const hasPhoto = this.previewHasPhoto();
    const newPhoto = this.previewPhotoFilename().length > 0 ? this.previewPhotoFilename() : undefined;
    // 版式只对照片封面有意义；没有照片就清掉（R-BOOK-13）
    const newLayout: CoverLayout | undefined = hasPhoto ? this.draftLayout : undefined;
    const cleanedSub = cleanSubtitle(this.subtitleInput);
    const subtitle: string | undefined = cleanedSub.length > 0
      ? truncateSubtitle(cleanedSub) : undefined;
    try {
      const store = await AppDatabase.open(context);
      await NotebookRepository.updateCover(store, notebook.id, this.draftColor,
        newPhoto, newLayout, subtitle);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'update cover failed id=%{public}s: %{public}s',
        notebook.id, JSON.stringify(err));
      this.presentSaveFailed();
      return;
    }
    // 换掉 / 移除时旧封面文件连删（云端副本等 Q3 云同步）
    const oldPhoto = notebook.coverPhotoFilename ?? '';
    if (oldPhoto.length > 0 && newPhoto !== oldPhoto) {
      NotebookCoverStore.forFilesDir(context.filesDir).deleteCover(oldPhoto);
    }
    this.sessionPhotoFilename = '';
    this.bumpReloadTick();
    this.navPathStack.pop();
  }

  /** 草稿落到 Notebook 实例上（新建用；照片三态在新建模式只会是 Replaced/Unchanged） */
  private applyDraftToNotebook(notebook: Notebook): void {
    const hasPhoto = this.previewHasPhoto();
    if (hasPhoto) {
      notebook.coverPhotoFilename = this.previewPhotoFilename();
      notebook.coverLayoutId = this.draftLayout;
    }
    const cleanedSub = cleanSubtitle(this.subtitleInput);
    if (cleanedSub.length > 0) {
      notebook.subtitle = truncateSubtitle(cleanedSub);
    }
  }

  /** 通知底下各页重查（Index.onPageShow 不会触发的场景） */
  private bumpReloadTick(): void {
    AppStorage.setOrCreate(STORAGE_KEY_HOME_RELOAD_TICK, this.homeReloadTick + 1);
  }

  private presentLoadFailure(): void {
    this.presentMessage($r('app.string.s_6c2b170c04'), ErrorToastKind.Error);
  }

  private presentSaveFailed(): void {
    this.presentMessage($r('app.string.s_40525a7328'), ErrorToastKind.Error);
  }

  private presentMessage(messageRes: Resource, kind: ErrorToastKind): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const message: string = context.resourceManager.getStringSync(messageRes.id);
      this.env.errors.present(message, kind, 4000);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read message string failed: %{public}s', JSON.stringify(err));
    }
  }

  // ---- 加载 ----

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
      const notebooks = await NotebookRepository.fetchAllNotebooks(store);
      this.existingNotebooks = notebooks;
      if (this.isCreate) {
        return;
      }
      let found: Notebook | undefined = undefined;
      for (const notebook of notebooks) {
        if (notebook.id === this.notebookId) {
          found = notebook;
          break;
        }
      }
      if (found === undefined) {
        // 本子没了（别处删掉）：退回
        this.navPathStack.pop();
        return;
      }
      this.notebook = found;
      this.draftColor = found.bookColor;
      this.draftLayout = found.coverLayout;
      this.subtitleInput = found.subtitle ?? '';
      this.photoKind = CoverPhotoDraftKind.Unchanged;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'load cover editor failed: %{public}s', JSON.stringify(err));
      this.presentSaveFailed();
    }
  }
}
