/**
 * 翻页阅读器的一页（10_BUILD_MANUAL.md 3.5）。对应 iOS
 * `Reader/ContentPageView.swift` + `EndingPageView.swift` +
 * `Views/Components/PhotoPaper/ContentBlockRenderer.swift` 的单组渲染。
 *
 * - 首页：页眉（DiaryPageHeaderView）+ 正文；续页：居中小标题 + 正文；
 *   底部页码（每篇各自「i+1 / 共 N 页」）
 * - 正文组：全宽文本 / 文字环绕照片（beside 15/11 + below 16/8，照片宽 45%）
 *   / 独立照片 / 录音卡 / 痕迹行；末页附无位置录音（不占分页预算，iOS 同款）
 * - 文本段落由 ReaderTextAdapter 用 graphics.text 排好（与分页测量同一路径，
 *   R-READ-05），经 CustomSpan 画进 Text；行数、行高与分页预算天然一致
 * - 版式尺寸全部取自 models/ReaderPages 的 ReaderLayout / ReaderHeaderMetrics
 */
import { drawing, text } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../services/LanguageManager';
import { inkDay } from '../../services/AppDateFormatters';
import { JournalEntry } from '../../models/JournalEntry';
import {
  ContentBlock,
  ContentBlockType,
  PaperStyle,
  PhotoPosition,
  effectivePaperStyle
} from '../../models/ContentBlock';
import {
  ReaderGeometry,
  ReaderGroupKind,
  ReaderLayout,
  ReaderPage,
  ReaderPageKind,
  ReaderRenderGroup
} from '../../models/ReaderPages';
import { PhotoPaperIO } from '../../services/PhotoPaperIO';import { ReaderTextAdapter } from './ReaderTextAdapter';
import { DiaryPageHeaderView } from './DiaryPageHeaderView';
import { PhotoPaperCard } from '../components/photo/PhotoPapers';
import { AudioPlayerCard } from '../components/audio/AudioPlayerCard';

const DOMAIN = 0x0000;
const TAG = 'ReaderPageView';

/** 痕迹文案（iOS InkText.traceLine 同款）*/
function traceLabelOf(block: ContentBlock, appLanguage: string,
  resourceOf: (audio: boolean) => string): string {
  const day = inkDay(new Date((block.removedAt ?? 0) * 1000), appLanguage);
  const audio = block.traceOf === (ContentBlockType.Audio as string);
  try {
    return resourceOf(audio).replace('%s', day);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'trace label failed: %{public}s', JSON.stringify(err));
    return '';
  }
}

/** 画段 Span：CustomSpan 的测量 / 绘制转给宿主闭包（WrapFlowView 同款模式） */
class ReaderPaintedSpan extends CustomSpan {
  private readonly measureFn: () => CustomSpanMetrics;
  private readonly drawFn: (canvas: drawing.Canvas) => void;

  constructor(measureFn: () => CustomSpanMetrics, drawFn: (canvas: drawing.Canvas) => void) {
    super();
    this.measureFn = measureFn;
    this.drawFn = drawFn;
  }

  onMeasure(_measureInfo: CustomSpanMeasureInfo): CustomSpanMetrics {
    return this.measureFn();
  }

  onDraw(context: DrawContext, _drawInfo: CustomSpanDrawInfo): void {
    this.drawFn(context.canvas);
  }
}

/** 排好的段落画进 Text（测量 = 段高，绘制 = paragraph.paint） */
@Component
struct ReaderPaintedText {
  paragraph: text.Paragraph | undefined = undefined;
  widthVp: number = 0;
  density: number = 3.0;
  private textController: TextController = new TextController();

  aboutToAppear(): void {
    const span = new ReaderPaintedSpan((): CustomSpanMetrics => this.spanMeasure(),
      (canvas: drawing.Canvas): void => this.spanDraw(canvas));
    this.textController.setStyledString(new MutableStyledString(span));
  }

  private spanMeasure(): CustomSpanMetrics {
    const paragraph = this.paragraph;
    if (paragraph === undefined) {
      return { width: 0, height: 0 };
    }
    return { width: this.widthVp, height: Math.ceil(paragraph.getHeight() / this.density) };
  }

  private spanDraw(canvas: drawing.Canvas): void {
    const paragraph = this.paragraph;
    if (paragraph !== undefined) {
      paragraph.paint(canvas, 0, 0);
    }
  }

  build() {
    Text('', { controller: this.textController })
      .width(this.widthVp)
  }
}

/** 相纸照片卡（异步载图；宽 45%，高封顶 280 标称预算 —— R-READ-05） */
@Component
struct ReaderPhotoView {
  block: ContentBlock = new ContentBlock('', ContentBlockType.Photo);
  photoWidthVp: number = 0;
  @State private pixelMap: image.PixelMap | undefined = undefined;
  @State private photoAspect: number = 4 / 3;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const io = PhotoPaperIO.forFilesDir(context.filesDir);
    io.loadImage(this.block.photoFilename).then((loaded: image.PixelMap | undefined): void => {
      if (loaded === undefined) {
        return; // 保持 4:3 占位，不塌陷
      }
      this.pixelMap = loaded;
      const info = loaded.getImageInfoSync();
      if (info.size.width > 0 && info.size.height > 0) {
        this.photoAspect = info.size.width / info.size.height;
      }
    }).catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'photo load failed id=%{public}s: %{public}s',
        this.block.id, JSON.stringify(err));
    });
  }

  build() {
    Column() {
      PhotoPaperCard({
        style: effectivePaperStyle(this.block.paperStyle ?? PaperStyle.Polaroid, true),
        pixelMap: this.pixelMap,
        photoAspect: this.photoAspect
      })
    }
    .width(this.photoWidthVp)
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxHeight: ReaderLayout.photoBlockHeight })
    .clip(true)
  }
}

/** 一个渲染组（文本段落在 aboutToAppear 里排好，与分页测量同构造路径） */
@Component
struct ReaderGroupView {
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = '';
  group: ReaderRenderGroup = ReaderRenderGroup.fullText(
    ContentBlock.makeText('', ''));
  contentWidth: number = 0;
  adapter: ReaderTextAdapter | undefined = undefined;
  private fullParagraph: text.Paragraph | undefined = undefined;
  private besideParagraph: text.Paragraph | undefined = undefined;
  private belowParagraph: text.Paragraph | undefined = undefined;

  aboutToAppear(): void {
    const adapter = this.adapter;
    if (adapter === undefined) {
      return;
    }
    const wrappedW = Math.max(1, this.contentWidth * (1 - ReaderLayout.photoWidthRatio)
      - ReaderLayout.photoTextGap);
    if (this.group.kind === ReaderGroupKind.FullText
      && this.group.textBlock !== undefined) {
      this.fullParagraph = adapter.buildBodyParagraph(this.group.textBlock, this.contentWidth);
    } else if (this.group.kind === ReaderGroupKind.PhotoWithText) {
      if (this.group.besideBlock !== undefined) {
        this.besideParagraph = adapter.buildWrappedParagraph(this.group.besideBlock, wrappedW);
      }
      if (this.group.belowBlock !== undefined) {
        this.belowParagraph = adapter.buildBodyParagraph(this.group.belowBlock, this.contentWidth);
      }
    }
  }

  /** 痕迹行文案（资源 pattern + 取下日期） */
  private traceText(): string {
    const context = this.getUIContext().getHostContext();
    const block = this.group.anchorBlock;
    if (context === undefined || block === undefined) {
      return '';
    }
    return traceLabelOf(block, this.appLanguage, (audio: boolean): string => {
      const res = audio ? $r('app.string.s_16ed8e1cbb') : $r('app.string.s_39074a4234');
      return context.resourceManager.getStringSync(res.id);
    });
  }

  build() {
    if (this.group.kind === ReaderGroupKind.FullText) {
      ReaderPaintedText({
        paragraph: this.fullParagraph,
        widthVp: this.contentWidth,
        density: this.adapter !== undefined ? this.adapter.density : 3.0
      })
    } else if (this.group.kind === ReaderGroupKind.PhotoWithText) {
      this.photoWithTextBody()
    } else if (this.group.kind === ReaderGroupKind.StandalonePhoto
      && this.group.photoBlock !== undefined) {
      Row() {
        if (this.group.photoBlock.position === PhotoPosition.Left) {
          ReaderPhotoView({
            block: this.group.photoBlock,
            photoWidthVp: this.photoWidth()
          })
          Blank()
        } else {
          Blank()
          ReaderPhotoView({
            block: this.group.photoBlock,
            photoWidthVp: this.photoWidth()
          })
        }
      }
      .width('100%')
    } else if (this.group.kind === ReaderGroupKind.Audio
      && this.group.anchorBlock !== undefined) {
      AudioPlayerCard({ block: this.group.anchorBlock })
    } else if (this.group.kind === ReaderGroupKind.Trace) {
      Text(this.traceText())
        .fontSize(12)
        .width('100%')
        .padding({ top: 2, bottom: 6 })
    }
  }

  /** 文字环绕照片：beside（照片旁）+ below（照片下方，可无） */
  @Builder
  photoWithTextBody() {
    Column({ space: 8 }) {
      Row({ space: ReaderLayout.photoTextGap }) {
        if (this.group.photoBlock !== undefined
          && this.group.photoBlock.position === PhotoPosition.Left) {
          ReaderPhotoView({
            block: this.group.photoBlock,
            photoWidthVp: this.photoWidth()
          })
          ReaderPaintedText({
            paragraph: this.besideParagraph,
            widthVp: this.wrappedWidth(),
            density: this.adapter !== undefined ? this.adapter.density : 3.0
          })
        } else {
          ReaderPaintedText({
            paragraph: this.besideParagraph,
            widthVp: this.wrappedWidth(),
            density: this.adapter !== undefined ? this.adapter.density : 3.0
          })
          if (this.group.photoBlock !== undefined) {
            ReaderPhotoView({
              block: this.group.photoBlock,
              photoWidthVp: this.photoWidth()
            })
          }
        }
      }
      .alignItems(VerticalAlign.Top)

      if (this.group.belowBlock !== undefined) {
        ReaderPaintedText({
          paragraph: this.belowParagraph,
          widthVp: this.contentWidth,
          density: this.adapter !== undefined ? this.adapter.density : 3.0
        })
      }
    }
  }

  private photoWidth(): number {
    return this.contentWidth * ReaderLayout.photoWidthRatio;
  }

  private wrappedWidth(): number {
    return Math.max(1, this.contentWidth * (1 - ReaderLayout.photoWidthRatio)
      - ReaderLayout.photoTextGap);
  }
}

/** 一页（正文页 / 结尾页）。宿主按 geometry 定好尺寸后整页画进来 */
@Component
export struct ReaderPageView {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  page: ReaderPage = new ReaderPage(ReaderPageKind.Content,
    new JournalEntry('', 0, 0, 0), 0, 1, []);
  geometry: ReaderGeometry = new ReaderGeometry(390, 844, 47, 34);
  adapter: ReaderTextAdapter | undefined = undefined;
  /** 末页附的无位置录音（宿主按 entry.looseAudioURLs 建好传入） */
  looseAudioBlocks: ContentBlock[] = [];

  /** 本页纸宽（vp）：大屏封顶 420（ReaderGeometry.contentWidth 同一口径） */
  private pageWidthVp(): number {
    return Math.min(this.geometry.pageWidth, ReaderLayout.maxPageWidth);
  }

  private contentWidthVp(): number {
    return this.geometry.contentWidth();
  }

  build() {
    Stack() {
      // 纸底（整页，跟主题）：显式满幅——Stack 子节点默认内容自适应，
      // 不给尺寸会塌成零高、透出下层页（真机实证 2026-10-22）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme.background)

      if (this.page.kind === ReaderPageKind.Content) {
        this.contentBody()
      } else {
        this.endingBody()
      }
    }
    .width(this.pageWidthVp())
    .height(this.geometry.pageHeight)
    .clip(true)
  }

  /** 正文页：页眉 / 小标题 + 渲染组 + 页码 */
  @Builder
  contentBody() {
    Column() {
      if (this.page.pageIndex === 0) {
        DiaryPageHeaderView({ entry: this.page.entry })
          .margin({ bottom: ReaderLayout.headerBottomGap })
      } else {
        // 续页：居中小标题（避开左上角返回按钮）
        Text(this.page.entry.title.length > 0 ? this.page.entry.title : ' ')
          .fontSize(ReaderLayout.runningTitleFontSize)
          .fontColor(this.theme.textTertiary)
          .maxLines(1)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: ReaderLayout.runningTitleBottomGap })
      }

      Column({ space: ReaderLayout.blockSpacing }) {
        ForEach(this.page.groups, (group: ReaderRenderGroup) => {
          ReaderGroupView({
            group: group,
            contentWidth: this.contentWidthVp(),
            adapter: this.adapter
          })
        }, (group: ReaderRenderGroup): string =>
          `${group.kind}_${this.groupKeySeed(group)}`)

        // 末页才出现录音（避免每页重复）；不占分页预算（iOS 同款）
        ForEach(this.looseAudioBlocks, (block: ContentBlock) => {
          AudioPlayerCard({ block: block })
        }, (block: ContentBlock): string => block.id)
      }
      .margin({ top: ReaderLayout.bodyTopGap })

      Blank()

      // 底部页码（每篇各自编号）
      Text(`${this.page.pageIndex + 1} / ${this.page.totalPages}`)
        .fontSize(ReaderLayout.pageNumberFontSize)
        .fontFamily('serif')
        .fontColor(this.theme.textTertiary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: ReaderLayout.pageNumberTopGap })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: ReaderLayout.hInset,
      right: ReaderLayout.hInset,
      top: this.geometry.safeTop + ReaderLayout.topInset,
      bottom: this.geometry.safeBottom + ReaderLayout.bottomInset
    })
  }

  /** 结尾页：装饰短线 + 「已读完所有日记」+ 底部提示 */
  @Builder
  endingBody() {
    Column({ space: 24 }) {
      Blank()
      Column()
        .width(40)
        .height(1)
        .backgroundColor(this.theme.borderAccent)
      Text($r('app.string.s_e7dca6ac80'))
        .fontSize(16)
        .fontFamily('serif')
        .fontColor(this.theme.textSecondary)
      Column()
        .width(40)
        .height(1)
        .backgroundColor(this.theme.borderAccent)
      Blank()
      Text($r('app.string.s_bd7fc4488b'))
        .fontSize(10)
        .fontColor(this.theme.textTertiary)
        .margin({ bottom: 30 })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: ReaderLayout.hInset,
      right: ReaderLayout.hInset,
      top: this.geometry.safeTop + ReaderLayout.topInset,
      bottom: this.geometry.safeBottom + ReaderLayout.bottomInset
    })
  }

  /** ForEach 键：kind + 组内块的 id（同页同 kind 多组不撞键） */
  private groupKeySeed(group: ReaderRenderGroup): string {
    if (group.textBlock !== undefined) {
      return group.textBlock.id;
    }
    if (group.photoBlock !== undefined) {
      return group.photoBlock.id;
    }
    if (group.anchorBlock !== undefined) {
      return group.anchorBlock.id;
    }
    if (group.besideBlock !== undefined) {
      return group.besideBlock.id;
    }
    return 'group';
  }
}
