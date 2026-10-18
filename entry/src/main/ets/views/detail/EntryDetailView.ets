/**
 * 日记详情页（10_BUILD_MANUAL.md 2.3）。对应 iOS `Views/Detail/EntryDetailView.swift`。
 *
 * - 挂在记录 Tab 内的 Navigation 栈里（系统路由表 `router_map.json` 注册
 *   `EntryDetail`）：推入后底部 Tab 栏保留可见——对齐 iOS 在 TabView 的
 *   NavigationStack 里 push 详情页的呈现（2026-10-16 真机需求）
 * - 素笺主题 =「和纸版式」（R-ENTRY-15）：月份大写 + 日期数字前小(28)后大(64)
 *   基线对齐 + 心情印章（R-ENTRY-16：中文界面 + 预设心情 + 显示名 ≤ 2 字）
 *   + 星期 + 此时此地 + 短分割线 + 标题 + 和纸色标签药丸 + 全宽分割线 + 正文；
 *   其余主题普通版式：日期星期 + 心情徽标 + 此时此地 + 标题 + 标签 + 分割线 + 正文
 * - 「补记 N 次 · 最近某月某日」行（R-INK-04 / R-ENTRY-14，2.8 接通）：素笺在
 *   星期行与短分割线之间（12fp #8B7E6A），普通版式在此时此地与标题之间；
 *   没补记过不显示
 * - 正文富文本只读展示（2.5 RichBodyEditor editable=false，2026-10-18 回退
 *   备忘录式——绕排连环平台缺陷后产品拍板，见 09 Q23）：照片整行锚点卡
 *   （纯预览，轻点/长按开全屏）+ 文字上下独立段；加粗 / 斜体 / 小标题 /
 *   荧光笔原样渲染（素笺 17fp）；不响应触摸，父级 Scroll 可滚
 * - 照片大图（全屏）带「⋯」编辑菜单：移到左/右侧 / 更换相纸样式 / 删除照片
 *   （iOS 详情页同款，无「设为封面」）；编辑直接改已保存日记并落库
 *   （唯一写入口 setContentBlocks，R-RICH-10）
 * - 右上编辑（push 2.4 编辑页）+ 删除（官方 AlertDialog 确认 + 先媒体后库记录，
 *   R-DATA-07）；从编辑页返回由 Index.onPageShow 广播的 reload tick 驱动重查
 */
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import {
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP,
  STORAGE_KEY_HIDE_TAB_BAR
} from '../../services/ImmersiveChrome';
import { AppDatabase } from '../../data/Database';
import { EntryRepository } from '../../data/EntryRepository';
import { STORAGE_KEY_HOME_RELOAD_TICK } from '../../data/HomeLogic';
import { MediaStorageService } from '../../services/MediaStorageService';
import {
  dayAndWeekday,
  inkDay,
  isChineseLanguage,
  monthYearUppercased,
  weekdayString,
  dayTens,
  dayOnes
} from '../../services/AppDateFormatters';
import { JournalEntry } from '../../models/JournalEntry';
import {
  ContentBlock,
  ContentBlockType,
  PaperStyle,
  PhotoPosition,
  blocksWithLooseAudio
} from '../../models/ContentBlock';
import { isDefaultMoodKey } from '../../models/Mood';
import { generateUuid } from '../../models/Uuid';
import { RichBodyController, RichBodyEditor } from '../components/richtext/RichBodyEditor';
import {
  anchoredBlocksOf,
  editorDocumentFromBlocks
} from '../../models/RichDocument';
import { CircleIconButton } from '../compose/CircleIconButton';
import { PhotoPaperIO } from '../../services/PhotoPaperIO';
import { PaperStylePickerSheet } from '../components/photo/PaperStylePickerSheet';
import { PhotoFullScreenCover } from '../components/photo/PhotoFullScreenCover';
import { MoodBadge, moodLabelRes } from '../components/MoodBadge';
import { TagPill } from '../components/TagPill';
import { StampView } from '../components/StampView';
import {
  WeatherLocationBadge,
  weatherBadgeHasContent
} from '../components/WeatherLocationBadge';

const DOMAIN = 0x0000;
const TAG = 'EntryDetailView';

/** 路由页 Index.onPageShow 广播：从编辑页返回后重查（编辑保存 / ✕ 都触发，重查幂等） */
export const STORAGE_KEY_DETAIL_RELOAD_TICK = 'detail.reloadTick';

/** 系统路由表入口（router_map.json → name `EntryDetail`）：Navigation 推入用 */
@Builder
export function EntryDetailBuilder() {
  EntryDetailView()
}

@Component
export struct EntryDetailView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @StorageProp(STORAGE_KEY_DETAIL_RELOAD_TICK) @Watch('onReloadTick')
  reloadTick: number = 0;

  @State entry: JournalEntry | undefined = undefined;
  // ---- 2.6 照片全屏（大图「⋯」编辑菜单：换边 / 换相纸 / 删除 —— iOS 详情页同款，
  // 无「设为封面」；编辑直接改已保存的日记并落库） ----
  @State @Watch('onPhotoFullscreenChanged') showPhotoFullscreen: boolean = false;
  @State fullscreenPhoto: ContentBlock | undefined = undefined;
  // 相纸选择（大图「更换相纸样式」用）：半高 sheet
  @State showPaperSheet: boolean = false;
  @State paperSheetPixelMap: image.PixelMap | undefined = undefined;
  private restylePhotoId: string | undefined = undefined;

  /** 正文只读控制器（2.5 RichBodyEditor editable=false，回退备忘录式） */
  private bodyController: RichBodyController = new RichBodyController();
  /** 正文编辑器就绪（onReady；与 entry 加载双信号装载，重查时重装） */
  private bodyEditorReady: boolean = false;

  /** 只读态照片轻点 / 长按 → 开全屏（PhotoAnchorCard 纯预览路径） */
  private wireBodyController(): void {
    this.bodyController.onPhotoTap = (blockId: string): void => {
      this.openPhotoFullscreen(blockId);
    };
  }

  /**
   * 正文装载：entry 就绪 + 编辑器 onReady 双信号；从编辑页返回重查时
   * entry 整篇替换，这里跟着重装（loadDocument 全量重置，幂等）。
   * 散在 audioURLs 里没进过正文的录音补成块挂末尾（R-RICH-09，只读展示层
   * 的兜底，不改库；写回只在编辑页保存时发生）。
   */
  private loadBodyIntoEditor(): void {
    const entry = this.entry;
    if (this.bodyEditorReady && entry !== undefined) {
      // 墨迹干湿基准 = 日记写下时刻（2.8；只读展示，无编辑会话）
      this.bodyController.setInkContext(entry.createdAt / 1000, undefined);
      const blocks = blocksWithLooseAudio(entry.contentBlocks, entry.audioURLs, generateUuid);
      this.bodyController.loadDocument(
        editorDocumentFromBlocks(blocks),
        anchoredBlocksOf(blocks));
    }
  }

  /** 跨过 24 小时补写过吗（补记行渲染判据，R-INK-04） */
  private hasAddendumNote(): boolean {
    return this.entry !== undefined && this.entry.addendumDays.length > 0;
  }

  /** 「补记 N 次 · 最近某月某日」（iOS `addendumNote` 同款） */
  private addendumNoteRes(): Resource {
    const days = this.entry?.addendumDays ?? [];
    return $r('app.string.s_33736fe5a5', days.length,
      inkDay(new Date(days[days.length - 1]), this.appLanguage));
  }

  /** 全屏浮层开/关（@Watch 联动隐藏主框架 Tab 栏，见 MainTabsView barOpacity） */
  private onPhotoFullscreenChanged(): void {
    AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, this.showPhotoFullscreen);
  }

  /** 正文照片轻点 / 长按 → 从正文块里找本体开全屏（R-ENTRY-13 纯预览） */
  private openPhotoFullscreen(blockId: string): void {
    const entry = this.entry;
    if (entry === undefined) {
      return;
    }
    for (const block of entry.contentBlocks) {
      if (block.id === blockId && block.type === ContentBlockType.Photo) {
        this.fullscreenPhoto = block;
        this.showPhotoFullscreen = true;
        return;
      }
    }
  }

  aboutToAppear(): void {
    this.wireBodyController();
  }

  aboutToDisappear(): void {
    // 全屏浮层没关就被路由弹走（边滑返回）时，别把主框架 Tab 栏一直藏着
    AppStorage.setOrCreate(STORAGE_KEY_HIDE_TAB_BAR, false);
  }

  /** 路由参数：日记 id（onReady 从 NavDestinationContext.pathInfo 取） */
  private entryId: string = '';
  /** 导航栈：onReady 时由 NavDestinationContext 注入真栈 */
  private navPathStack: NavPathStack = new NavPathStack();
  private store: relationalStore.RdbStore | undefined = undefined;

  build() {
    // NavDestination 自定义标题栏：沉浸光感 Button 的官方生效范围（API 26：
    // 其他组件仅在 Navigation/NavDestination 标题栏或底部 TabBar 生效，
    // 《沉浸光感常见问题》）。标题栏自动避让状态栏，无需手动 safeAreaTop。
    NavDestination() {
      Stack() {
        if (this.entry !== undefined) {
          Scroll() {
          if (this.theme.id === 'bamboo') {
            // ---- 和纸版式（素笺；用自己的色板，不走 theme token） ----
            Column() {
              // 月份
              Text(monthYearUppercased(new Date(this.entry.date), this.appLanguage))
                .fontSize(11)
                .fontColor('#B8AD9C')
                .letterSpacing(3)
                .padding({ bottom: 4 })

              // 日期大字（前小后大、顶对齐）+ 印章（底对齐）
              Row() {
                Row() {
                  Text(dayTens(new Date(this.entry.date)))
                    .fontSize(28)
                    .fontWeight(300)
                    .fontFamily('serif')
                    .fontColor('#3D3428')
                  Text(dayOnes(new Date(this.entry.date)))
                    .fontSize(64)
                    .fontWeight(300)
                    .fontFamily('serif')
                    .fontColor('#3D3428')
                }
                .alignItems(VerticalAlign.Top)

                Blank()

                // 印章（条件显示，R-ENTRY-16）
                if (this.shouldShowStamp()) {
                  StampView({ moodName: this.moodDisplayName() })
                    .padding({ bottom: 4 })
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Bottom)
              .padding({ bottom: 2 })

              // 星期 + 此时此地
              Row({ space: 8 }) {
                Text(weekdayString(new Date(this.entry.date), this.appLanguage))
                  .fontSize(13)
                  .fontColor('#8B7E6A')
                if (weatherBadgeHasContent(
                  this.entry.weatherCode ?? '', this.entry.weatherInfo ?? '', this.entry.locationInfo ?? '')) {
                  Text('|')
                    .fontSize(10)
                    .fontColor('#D4C9B8')
                  WeatherLocationBadge({
                    weatherCode: this.entry.weatherCode ?? '',
                    weatherInfo: this.entry.weatherInfo ?? '',
                    locationInfo: this.entry.locationInfo ?? '',
                    fontSize: 12,
                    fontColor: '#8B7E6A',
                    iconSize: 10
                  })
                }
              }
              .padding({ bottom: 16 })

              // 补记行（2.8：跨过 24 小时补写过的日子；iOS 素笺 12fp #8B7E6A 同款）
              if (this.hasAddendumNote()) {
                Text(this.addendumNoteRes())
                  .fontSize(12)
                  .fontColor('#8B7E6A')
                  .padding({ bottom: 14 })
              }

              // 短分割线
              Row()
                .width(32)
                .height(1)
                .backgroundColor('#D4C9B8')
                .margin({ bottom: 20 })

              // 标题
              if (this.entry.title.length > 0) {
                Text(this.entry.title)
                  .fontSize(22)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily('serif')
                  .fontColor('#3D3428')
                  .lineHeight(34)
                  .padding({ bottom: 10 })
              }

              // 标签药丸（和纸专用色）
              if (this.entry.tags.length > 0) {
                Row({ space: 6 }) {
                  ForEach(this.entry.tags, (tag: string) => {
                    Text('#' + tag)
                      .fontSize(11)
                      .fontColor('#8B7E6A')
                      .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                      .backgroundColor('#F0EBE1')
                      .borderRadius(12)
                      .border({ width: 0.5, color: '#E0D9CC' })
                  }, (tag: string): string => tag)
                }
                .margin({ bottom: 16 })
              }

              // 心情药丸（印章不显示时才用药丸）
              if (this.entry.mood.length > 0 && !this.shouldShowStamp()) {
                MoodBadge({ name: this.entry.mood, colorHex: this.entry.moodColorHex ?? '' })
                  .margin({ bottom: 16 })
              }

              // 全宽分割线（正文区起点）
              Row()
                .width('100%')
                .height(0.5)
                .backgroundColor(0x80D4C9B8)

              // 正文（富文本只读，2.5 RichBodyEditor：备忘录式整行照片卡 +
              // 文字上下独立段；照片纯预览轻点开全屏；紧接全宽分割线）。
              // 纯录音日记（无文字无照片）也要挂编辑器：录音卡在编辑器里渲染
              if (this.entry.content.length > 0 || this.entry.photoCount > 0 ||
                this.entry.audioURLs.length > 0) {
                RichBodyEditor({
                  controller: this.bodyController,
                  editable: false,
                  onReady: (): void => {
                    this.bodyEditorReady = true;
                    this.loadBodyIntoEditor();
                  }
                })
                  .padding({ top: 6 })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({
              left: 20,
              right: 20,
              top: 16,
              bottom: this.safeAreaBottomVp + 114
            })
          } else {
            // ---- 普通版式（皮革 / 肯特，iOS defaultLayout） ----
            Column({ space: 16 }) {
              // 日期 + 星期 + 心情
              Row() {
                Text(dayAndWeekday(new Date(this.entry.date), this.appLanguage))
                  .fontSize(this.theme.captionFont.size)
                  .fontWeight(this.theme.captionFont.weight)
                  .fontFamily(this.theme.captionFont.family)
                  .fontColor(this.theme.textTertiary)
                  .letterSpacing(this.theme.letterSpacingWide)
                Blank()
                if (this.entry.mood.length > 0) {
                  MoodBadge({ name: this.entry.mood, colorHex: this.entry.moodColorHex ?? '' })
                }
              }
              .width('100%')

              // 此时此地（写作当时的天气与地点）
              WeatherLocationBadge({
                weatherCode: this.entry.weatherCode ?? '',
                weatherInfo: this.entry.weatherInfo ?? '',
                locationInfo: this.entry.locationInfo ?? '',
                fontSize: this.theme.labelFont.size,
                fontColor: this.theme.textTertiary,
                iconSize: 11
              })

              // 补记行（2.8，iOS 普通版式 weather 后同款位置）
              if (this.hasAddendumNote()) {
                Text(this.addendumNoteRes())
                  .fontSize(this.theme.labelFont.size)
                  .fontFamily(this.theme.labelFont.family)
                  .fontColor(this.theme.textTertiary)
              }

              // 标题
              if (this.entry.title.length > 0) {
                Text(this.entry.title)
                  .fontSize(this.theme.titleFont.size)
                  .fontWeight(this.theme.titleFont.weight)
                  .fontFamily(this.theme.titleFont.family)
                  .fontColor(this.theme.textPrimary)
                  .lineHeight(this.theme.titleFont.size * 1.36)
              }

              // 日记本标签
              if (this.entry.tags.length > 0) {
                Row({ space: 4 }) {
                  ForEach(this.entry.tags, (tag: string) => {
                    TagPill({ name: tag })
                  }, (tag: string): string => tag)
                }
              }

              // 分割线
              Divider()
                .strokeWidth(0.5)
                .color(this.theme.border)

              // 正文（富文本只读，2.5 RichBodyEditor：备忘录式整行照片卡 +
              // 文字上下独立段；照片纯预览轻点开全屏）。
              // 纯录音日记（无文字无照片）也要挂编辑器：录音卡在编辑器里渲染
              if (this.entry.content.length > 0 || this.entry.photoCount > 0 ||
                this.entry.audioURLs.length > 0) {
                RichBodyEditor({
                  controller: this.bodyController,
                  editable: false,
                  onReady: (): void => {
                    this.bodyEditorReady = true;
                    this.loadBodyIntoEditor();
                  }
                })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({
              left: 20,
              right: 20,
              top: 16,
              bottom: this.safeAreaBottomVp + 114
            })
          }
        }
        .height('100%')
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        }

        // 照片全屏预览（2.6）：页面内条件浮层（Stack 末位 = 最顶层）。详情页
        // 纯查看；弃用 bindContentCover 理由同写/编页（真机「隐形挂载」吞触摸），
        // 且浮层需与标题栏联动隐藏，避免 112vp 标题栏盖在全屏图上。
        if (this.showPhotoFullscreen) {
          this.PhotoFullscreenBuilder()
        }
      }
      .width('100%')
      .height('100%')
      // 相纸选择（大图「更换相纸样式」）：半高 sheet，iOS medium 同款
      .bindSheet(this.showPaperSheet, this.PaperSheetBuilder(), {
        detents: [SheetSize.MEDIUM],
        showClose: false,
        onDisappear: (): void => {
          this.paperSheetPixelMap = undefined;
          this.restylePhotoId = undefined;
        }
      })
    }
    // 112vp 大标题区（NavDestinationCustomTitle；builder 必须内联在调用点传
    // this 引用——捕获进字段会丢掉 @Builder 作用域装置，渲染时崩溃
    // 「observeComponentCreation2 is not callable」）
    .title({
      builder: this.topBar,
      height: 112
    })
    // 标题栏坍缩根因（2026-10-16 真机 dump 定位）：全屏窗口下页面布局即窗口
    // 坐标（y0 起），系统状态栏遮挡 [0,122]px。旧 56vp 标题栏内容顶部对齐在
    // y0 → 钻进遮挡区（可见仅 14px 条）；且系统返回键把内容区右移 175px →
    // Row('100%') 右溢出屏幕、删除钮被顶出屏外。修复 = 复刻书写页 NavBar 的
    // 大标题结构：112vp 栏 + 内容下移 56vp（遮挡区之下）+ hideBackButton 改用
    // 自带沉浸光感返回钮（与书写页一致）。
    .hideBackButton(true)
    // 照片全屏时隐藏整个自定义标题栏（112vp），黑底照片延伸到顶
    .hideTitleBar(this.showPhotoFullscreen)
    .backgroundColor(this.theme.background)
    // onReady：取真导航栈 + 路由参数（日记 id）并首查；
    // 之后从编辑页返回由 Index.onPageShow 广播的 reload tick 重查
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      // 边界一次断言：pushPathByName 传的是 string id（HomeView），
      // Record 分支兼容历史路由参数形态
      const raw = ctx.pathInfo.param as Record<string, Object> | string | undefined;
      if (typeof raw === 'string') {
        this.entryId = raw;
      } else if (raw !== undefined) {
        const id = raw['id'];
        if (typeof id === 'string') {
          this.entryId = id;
        }
      }
      const context = this.getUIContext().getHostContext();
      if (context !== undefined && this.entryId.length > 0) {
        this.loadEntry(context);
      }
    })
  }

  /** 照片全屏内容：大图「⋯」编辑菜单（换边 / 换相纸 / 删除），iOS 详情页同款 */
  @Builder
  PhotoFullscreenBuilder() {
    if (this.fullscreenPhoto !== undefined) {
      PhotoFullScreenCover({
        photo: this.fullscreenPhoto,
        onDismiss: (): void => {
          this.showPhotoFullscreen = false;
          this.fullscreenPhoto = undefined;
        },
        onTogglePosition: (): void => {
          this.toggleFullscreenPosition();
        },
        onRestyle: (): void => {
          this.startFullscreenRestyle();
        },
        onDelete: (): void => {
          this.deleteFullscreenPhoto();
        }
      })
    }
  }

  /** 相纸选择 sheet 内容（大图「更换相纸样式」专用：无选边分段，iOS openStyleChange 同款） */
  @Builder
  PaperSheetBuilder() {
    if (this.paperSheetPixelMap !== undefined) {
      PaperStylePickerSheet({
        pixelMap: this.paperSheetPixelMap,
        showPositionPicker: false,
        onSelect: (style: PaperStyle, _position: PhotoPosition): void => {
          this.applyFullscreenRestyle(style);
        },
        onCancel: (): void => {
          this.showPaperSheet = false;
        }
      })
    }
  }

  // ---- 大图「⋯」动作（iOS EntryDetailView.togglePhotoPosition / openStyleChange /
  //      applyStyleChange / deletePhoto 同款；落库走唯一写入口 R-RICH-10） ----

  /** 在当前正文块里找这张照片（contentBlocks 每次解码都是新副本，动作前后都用它） */
  private indexOfPhotoBlock(blocks: ContentBlock[], blockId: string): number {
    for (let i = 0; i < blocks.length; i++) {
      if (blocks[i].id === blockId && blocks[i].type === ContentBlockType.Photo) {
        return i;
      }
    }
    return -1;
  }

  /** 照片编辑落库 + 正文重装（失败记日志留在页内，本地库更新几乎不失败） */
  private async persistPhotoBlocks(blocks: ContentBlock[]): Promise<void> {
    const entry = this.entry;
    const store = this.store;
    if (entry === undefined || store === undefined) {
      return;
    }
    entry.setContentBlocks(blocks, Date.now());
    try {
      await EntryRepository.updateEntry(store, entry);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'persist photo edit failed: %{public}s', JSON.stringify(err));
      return;
    }
    this.loadBodyIntoEditor();
  }

  /** 大图「移到左/右侧」：翻 position → 落库 → 正文重装 */
  private async toggleFullscreenPosition(): Promise<void> {
    const block = this.fullscreenPhoto;
    const entry = this.entry;
    if (block === undefined || entry === undefined) {
      return;
    }
    const blocks = entry.contentBlocks;
    const idx = this.indexOfPhotoBlock(blocks, block.id);
    if (idx < 0) {
      return;
    }
    blocks[idx].position = blocks[idx].position === PhotoPosition.Left ?
      PhotoPosition.Right : PhotoPosition.Left;
    await this.persistPhotoBlocks(blocks);
  }

  /** 大图「更换相纸样式」：加载缩略图重开相纸 sheet */
  private async startFullscreenRestyle(): Promise<void> {
    const block = this.fullscreenPhoto;
    if (block === undefined) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const pixelMap = await PhotoPaperIO.forFilesDir(context.filesDir).loadImage(block.photoFilename);
    if (pixelMap === undefined) {
      hilog.warn(DOMAIN, TAG, 'restyle load failed %{public}s', block.photoFilename);
      return;
    }
    this.restylePhotoId = block.id;
    this.paperSheetPixelMap = pixelMap;
    this.showPaperSheet = true;
  }

  /** 相纸选定：改 paperStyle → 落库 → 正文重装（文件不动） */
  private async applyFullscreenRestyle(style: PaperStyle): Promise<void> {
    this.showPaperSheet = false;
    const entry = this.entry;
    const id = this.restylePhotoId;
    this.restylePhotoId = undefined;
    if (entry === undefined || id === undefined) {
      return;
    }
    const blocks = entry.contentBlocks;
    const idx = this.indexOfPhotoBlock(blocks, id);
    if (idx < 0) {
      return;
    }
    blocks[idx].paperStyle = style;
    await this.persistPhotoBlocks(blocks);
  }

  /** 大图「删除照片」（组件内已过确认弹窗）：先出块落库，成功再删文件 */
  private async deleteFullscreenPhoto(): Promise<void> {
    const block = this.fullscreenPhoto;
    const entry = this.entry;
    if (block === undefined || entry === undefined) {
      return;
    }
    const blocks = entry.contentBlocks;
    const idx = this.indexOfPhotoBlock(blocks, block.id);
    if (idx < 0) {
      return;
    }
    const target = blocks[idx];
    const names: string[] = [];
    if (target.photoFilename !== undefined) {
      names.push(target.photoFilename);
    }
    if (target.livePhotoVideoFilename !== undefined) {
      names.push(target.livePhotoVideoFilename);
    }
    if (target.livePhotoStillFilename !== undefined) {
      names.push(target.livePhotoStillFilename);
    }
    blocks.splice(idx, 1);
    await this.persistPhotoBlocks(blocks);
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const io = PhotoPaperIO.forFilesDir(context.filesDir);
    for (const name of names) {
      io.deleteImage(name);
    }
  }

  /** 顶栏（NavDestination 标题栏内）：左返回、右编辑 + 删除
   * （同分量沉浸光感圆钮；破坏性由图标语义表达） */
  @Builder
  topBar() {
    Row() {
      CircleIconButton({
        iconRes: $r('sys.symbol.chevron_left'),
        iconSize: 14,
        onTap: (): void => {
          this.navPathStack.pop();
        }
      })
      Blank()
      if (this.entry !== undefined) {
        Row({ space: 12 }) {
          CircleIconButton({
            // pencil_line（ID 125831649）在本机运行时表缺资源渲染为空白
            // （2026-10-16 真机像素实测 0%）；square_and_pencil 为早期稳定
            // 资源且设备字体含该字形，iOS「编辑」同语义
            iconRes: $r('sys.symbol.square_and_pencil'),
            iconSize: 14,
            onTap: (): void => {
              this.openEdit();
            }
          })
          CircleIconButton({
            iconRes: $r('sys.symbol.trash'),
            iconSize: 14,
            onTap: (): void => {
              this.showDeleteConfirm();
            }
          })
        }
      }
    }
    .width('100%')
    // 112vp 标题栏内下移 56vp：内容落在 [56,99.5]vp（窗口 y175~311px），
    // 状态栏遮挡区之下，与书写页 NavBar 大标题区内容位置一致
    .margin({ top: 56 })
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
  }

  // ---- 印章判定（R-ENTRY-16） ----

  /** 心情印章显示条件：中文界面 + 预设心情 + 显示名 ≤ 2 字 */
  private shouldShowStamp(): boolean {
    const entry = this.entry;
    if (entry === undefined || entry.mood.length === 0) {
      return false;
    }
    if (!isDefaultMoodKey(entry.mood)) {
      return false;
    }
    if (this.moodDisplayName().length > 2) {
      return false;
    }
    return isChineseLanguage(this.appLanguage);
  }

  /** 心情显示名（默认 key 查 mood.* 译文；查不到 / 自定义显示原名） */
  private moodDisplayName(): string {
    const entry = this.entry;
    if (entry === undefined) {
      return '';
    }
    if (isDefaultMoodKey(entry.mood)) {
      const res = moodLabelRes(entry.mood);
      if (res !== undefined) {
        return this.stringFromResource(res);
      }
    }
    return entry.mood;
  }

  // ---- 编辑（2.4） ----

  private openEdit(): void {
    const entry = this.entry;
    if (entry === undefined) {
      return;
    }
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/EditEntry',
      params: { 'id': entry.id } as Record<string, Object>
    });
  }

  // ---- 数据 ----

  private onReloadTick(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined && this.entryId.length > 0) {
      this.loadEntry(context);
    }
  }

  private async loadEntry(context: common.Context): Promise<void> {
    try {
      const store = await AppDatabase.open(context);
      this.store = store;
      const loaded = await EntryRepository.fetchEntryById(store, this.entryId);
      // 整篇替换（entry @State → 版式重渲染）；正文编辑器跟着重装
      //（loadBodyIntoEditor 全量装载，编辑返回 reload tick 重查时同样成立）
      this.entry = loaded ?? undefined;
      this.loadBodyIntoEditor();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'loadEntry failed id=%{public}s: %{public}s', this.entryId, JSON.stringify(err));
    }
  }

  // ---- 删除（R-DATA-07） ----

  /**
   * 删除确认：官方 AlertDialog（操作确认类弹出框，华为备忘录删除同款；
   * 居中标题/正文 + 底部双按钮，系统自动深浅色背板与圆角 32vp）。
   */
  private showDeleteConfirm(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.s_215574245b'),
      message: $r('app.string.s_502b05fb33'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.s_4d0b4688c7'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.s_3755f56f2f'),
        fontColor: this.theme.destructive,
        action: (): void => {
          this.deleteEntryAndClose();
        }
      }
    });
  }

  /**
   * 删除：先媒体（deleteEntryMedia，照片三件套 + 录音）后库记录（05 §2），
   * 成功返回；失败记日志留在页内（本地库删除几乎不失败）。
   */
  private async deleteEntryAndClose(): Promise<void> {
    const store = this.store;
    const entry = this.entry;
    if (store === undefined || entry === undefined) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext();
      if (context !== undefined) {
        MediaStorageService.create(context, store).deleteEntryMedia(entry);
      }
      await EntryRepository.deleteEntry(store, entry.id);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'delete entry failed id=%{public}s: %{public}s', entry.id, JSON.stringify(err));
      return;
    }
    // pop 返回首页不触发 Index.onPageShow（无路由切换），首页列表不会重查——
    // 主动 bump home tick 让挂载中的 HomeView 立即重查（对齐 iOS @Query 自动响应）
    AppStorage.setOrCreate(STORAGE_KEY_HOME_RELOAD_TICK,
      (AppStorage.get<number>(STORAGE_KEY_HOME_RELOAD_TICK) ?? 0) + 1);
    this.navPathStack.pop();
  }

  private stringFromResource(res: Resource): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    try {
      return context.resourceManager.getStringSync(res.id);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read string resource failed: %{public}s', JSON.stringify(err));
      return '';
    }
  }
}
