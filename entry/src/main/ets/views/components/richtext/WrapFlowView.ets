/**
 * 绕排正文视图（10_BUILD_MANUAL.md 2.7，R-RICH-02）——详情页阅读态。
 *
 * 结构：`Text` + `TextController.setStyledString(一个 WrapFlowSpan)` 承载全部
 * 文字排版（`@ohos.graphics.text` Paragraph 逐段画到 CustomSpan 的 drawing.Canvas），
 * 照片卡（PhotoAnchorCard 纯预览模式）按引擎输出的占位矩形用 `position()` 叠在
 * 同一个 Stack 上——文字绕排 + 照片原生交互（轻点全屏）两者兼得。
 *
 * 布局管线：宽度/照片比例/主题任一变化 → `relayout()`（WrapFlowEngine 一次顺序
 * 扫描）→ 渲染层用同一适配器重建各段 Paragraph（测量与绘制同构造路径，几何一致）
 * → `span.invalidate()` 重渲。
 */
import { drawing, text } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ContentBlock,
  ContentBlockType,
  PaperStyle,
  PhotoPosition,
  effectivePaperStyle
} from '../../../models/ContentBlock';
import { AppTheme } from '../../../theme/AppTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import { BambooTheme } from '../../../theme/BambooTheme';
import { PhotoPaperIO } from '../../../services/PhotoPaperIO';
import { RichTextAppearance } from './RichTextAppearance';
import { WrapFlowTextAdapter } from './WrapFlowTextAdapter';
import {
  WrapFlowItem,
  WrapFlowPhotoItem,
  WrapFlowResult,
  WrapFlowTextItem,
  WrappedPhotoRect,
  photoCardMetrics,
  textPartsOfBlock
} from './WrapFlowModel';
import { WrapFlowEngine, WrapFlowParams } from './WrapFlowEngine';
import { PhotoAnchorCard } from '../photo/PhotoAnchorCard';

const DOMAIN = 0x0000;
const TAG = 'WrapFlowView';

/** 照片卡宽 = 正文区宽的 46%（iOS `RichTextView.photoWidthRatio` 同款） */
const PHOTO_WIDTH_RATIO: number = 0.46;

/** 已排好版、待绘制的一段（Paragraph + 段顶 y，vp） */
class RenderParagraph {
  paragraph: text.Paragraph;
  yVp: number;

  constructor(paragraph: text.Paragraph, yVp: number) {
    this.paragraph = paragraph;
    this.yVp = yVp;
  }
}

/**
 * 绕排绘制 Span：把 CustomSpan 的测量/绘制回调转给宿主闭包。
 * onMeasure 单位 vp；onDraw 的 DrawContext.canvas 单位 px（段 y × density 换算）。
 */
class WrapFlowSpan extends CustomSpan {
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

/**
 * 绕排正文视图（只读）。照片走 PhotoAnchorCard 纯预览：轻点 = onPhotoOpen
 * （详情页开全屏）；编辑态绕排（写/编页）阶段二另行接线。
 */
@Component
export struct WrapFlowView {
  @StorageProp(STORAGE_KEY_THEME) @Watch('onThemeChanged') theme: AppTheme = new BambooTheme();
  /** 正文内容块（文本段 + 照片块，文档序） */
  @Prop @Watch('onBlocksChanged') blocks: ContentBlock[] = [];
  /** 会员判定（相纸降级；7.2 接上，当前与全 app 一致全放开） */
  isMember: boolean = true;
  /** 照片轻点（详情页语义：开全屏预览） */
  onPhotoOpen: (blockId: string) => void = (_blockId: string): void => {};

  private textController: TextController = new TextController();
  private span: WrapFlowSpan | undefined = undefined;
  private adapter: WrapFlowTextAdapter | undefined = undefined;
  private engine: WrapFlowEngine | undefined = undefined;
  private containerWidth: number = 0;
  private renderParagraphs: RenderParagraph[] = [];
  private readonly loadedPhotoIds: Set<string> = new Set<string>();
  /** 照片比例（id → 宽/高；未加载完按 4:3 占位，加载完重排） */
  @State private photoAspects: Map<string, number> = new Map<string, number>();
  @State private flowResult: WrapFlowResult | undefined = undefined;

  aboutToAppear(): void {
    this.rebuildEngine();
    this.span = new WrapFlowSpan((): CustomSpanMetrics => this.spanMeasure(),
      (canvas: drawing.Canvas): void => this.spanDraw(canvas));
    this.textController.setStyledString(new MutableStyledString(this.span));
    this.loadPhotoAspects();
  }

  // ---- 宿主回调（CustomSpan） ----

  private spanMeasure(): CustomSpanMetrics {
    const result = this.flowResult;
    if (result === undefined || this.containerWidth <= 0) {
      return { width: 0, height: 0 };
    }
    return { width: this.containerWidth, height: result.totalHeight };
  }

  private spanDraw(canvas: drawing.Canvas): void {
    const adapter = this.adapter;
    if (adapter === undefined) {
      return;
    }
    const density = adapter.density;
    for (const rp of this.renderParagraphs) {
      rp.paragraph.paint(canvas, 0, rp.yVp * density);
    }
  }

  // ---- 布局管线 ----

  /** 主题变化：排版参数（字号/行高/荧光色）随之重建 */
  private onThemeChanged(): void {
    this.rebuildEngine();
    this.relayout();
  }

  private onBlocksChanged(): void {
    this.loadPhotoAspects();
    this.relayout();
  }

  private rebuildEngine(): void {
    const appearance = RichTextAppearance.forTheme(this.theme);
    this.adapter = new WrapFlowTextAdapter(appearance);
    this.engine = new WrapFlowEngine(new WrapFlowParams(appearance.bodyLineHeight,
      appearance.headingLineHeight), this.adapter);
  }

  /** 引擎输入：内容块 → 文本行段项（\n 拆分，heading=行段语义）+ 照片项 */
  private buildItems(): WrapFlowItem[] {
    const items: WrapFlowItem[] = [];
    if (this.containerWidth <= 0) {
      return items;
    }
    const cardWidth = this.containerWidth * PHOTO_WIDTH_RATIO;
    for (const block of this.blocks) {
      if (block.type === ContentBlockType.Photo) {
        const style = effectivePaperStyle(block.paperStyle ?? PaperStyle.Polaroid, this.isMember);
        const aspect = this.photoAspects.get(block.id);
        items.push(new WrapFlowPhotoItem(block.id, block.position ?? PhotoPosition.Right,
          photoCardMetrics(cardWidth, aspect ?? 4 / 3, style)));
      } else if (block.type === ContentBlockType.Text && block.text !== undefined) {
        for (const part of textPartsOfBlock(block.text, block.styles ?? [])) {
          items.push(new WrapFlowTextItem(part.text, part.isHeading, part.runs));
        }
      }
    }
    return items;
  }

  /** 一次完整重排：引擎几何 + 渲染层重建各段 Paragraph + 通知重渲 */
  private relayout(): void {
    const engine = this.engine;
    const adapter = this.adapter;
    if (engine === undefined || adapter === undefined || this.containerWidth <= 0) {
      return;
    }
    const items = this.buildItems();
    const result = engine.layout(items, this.containerWidth);
    const nextParagraphs: RenderParagraph[] = [];
    for (const para of result.paragraphs) {
      const item = items[para.itemIndex];
      if (item instanceof WrapFlowTextItem) {
        nextParagraphs.push(new RenderParagraph(
          adapter.buildParagraph(item, para.headIndents, para.tailIndents, this.containerWidth),
          para.y));
      }
    }
    this.renderParagraphs = nextParagraphs;
    this.flowResult = result;
    // 真机（API 26）实测：span.invalidate() 只触发重绘、不会让 Text 重新调用
    // onMeasure —— 尺寸变化必须换新 span 走 setStyledString 才会重测。
    const nextSpan = new WrapFlowSpan((): CustomSpanMetrics => this.spanMeasure(),
      (canvas: drawing.Canvas): void => this.spanDraw(canvas));
    this.span = nextSpan;
    this.textController.setStyledString(new MutableStyledString(nextSpan));
  }

  // ---- 照片比例加载（比例决定相纸卡高；加载完重排一次） ----

  private loadPhotoAspects(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const io = PhotoPaperIO.forFilesDir(context.filesDir);
    for (const block of this.blocks) {
      if (block.type !== ContentBlockType.Photo || this.loadedPhotoIds.has(block.id)) {
        continue;
      }
      this.loadedPhotoIds.add(block.id);
      io.loadImage(block.photoFilename).then((loaded: image.PixelMap | undefined): void => {
        if (loaded === undefined) {
          return; // 保持 4:3 占位（与 PhotoAnchorCard 占位一致，不塌陷）
        }
        const info = loaded.getImageInfoSync();
        if (info.size.width <= 0 || info.size.height <= 0) {
          return;
        }
        const next = new Map<string, number>(this.photoAspects);
        next.set(block.id, info.size.width / info.size.height);
        this.photoAspects = next;
        this.relayout();
      }).catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'aspect load failed id=%{public}s: %{public}s',
          block.id, JSON.stringify(err));
      });
    }
  }

  private photoBlockOf(blockId: string): ContentBlock {
    for (const block of this.blocks) {
      if (block.id === blockId && block.type === ContentBlockType.Photo) {
        return block;
      }
    }
    return new ContentBlock(blockId, ContentBlockType.Photo);
  }

  // ---- 视图 ----

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Text('', { controller: this.textController })
        .width('100%')
        .onAreaChange((_old: Area, newArea: Area): void => {
          const widthVp = typeof newArea.width === 'number' ? newArea.width : 0;
          if (widthVp > 0 && Math.abs(widthVp - this.containerWidth) > 0.5) {
            this.containerWidth = widthVp;
            this.relayout();
          }
        })
      if (this.flowResult !== undefined) {
        ForEach(this.flowResult.photos, (rect: WrappedPhotoRect) => {
          PhotoAnchorCard({
            block: this.photoBlockOf(rect.blockId),
            isMember: this.isMember,
            onOpen: this.onPhotoOpen
          })
            .position({ x: rect.x, y: rect.y })
        }, (rect: WrappedPhotoRect): string =>
          `${rect.blockId}@${rect.x.toFixed(1)},${rect.y.toFixed(1)}`)
      }
    }
    .width('100%')
  }
}
