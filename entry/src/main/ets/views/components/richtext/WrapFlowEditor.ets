/**
 * 绕排正文编辑器（10_BUILD_MANUAL.md 2.5b，B1 隐形输入层，M1）。
 *
 * 渲染与阅读态 WrapFlowView 同构（`Text` + `CustomSpan` + graphics.text 段落自绘 +
 * PhotoAnchorCard 叠放），输入由 1px 透明隐形 `RichEditor` 承接 —— **diff 模式**：
 * 系统全权管理组合 / 删除 / 光标 / 撤销 → `onDidChange` 时 `getSpans` 重建全文 →
 * `diffTextEdit` 单点 diff → `RichDocEditor` 同步编辑模型 → 拆回块 → relayout
 * 重排重渲。组合（拼音）逐键即单点 diff，无需自研组合状态机。
 *
 * 锚点保护两道闸：`aboutToDelete` 预判拦截（退格 / 删除键）；diff 兜底恢复
 * （选区删 / 撤销等一切导致锚点字符丢失的路径，把被删文本塞回隐形层，M2 换
 * 「先选中再删」交互）。光标自绘闪烁，命中查询用
 * `Paragraph.getGlyphPositionAtCoordinate`（API 有此 API，无需自算字形）。
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
import { generateUuid } from '../../../models/Uuid';
import {
  RICH_ANCHOR,
  anchoredBlocksOf,
  blocksWithEditorDocument,
  editorDocumentFromBlocks,
  textBlockRangesOfBlocks,
  TextBlockRange
} from '../../../models/RichDocument';
import { diffTextEdit, RichDocEditor } from '../../../models/RichDocEditor';
import { AppTheme } from '../../../theme/AppTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import { BambooTheme } from '../../../theme/BambooTheme';
import { PhotoPaperIO } from '../../../services/PhotoPaperIO';
import { RichTextAppearance } from './RichTextAppearance';
import { WrapFlowTextAdapter } from './WrapFlowTextAdapter';
import {
  TextPart,
  WrapFlowItem,
  WrapFlowPhotoItem,
  WrapFlowResult,
  WrapFlowTextItem,
  WrappedParagraphRect,
  WrappedPhotoRect,
  photoCardMetrics,
  textPartsOfBlock
} from './WrapFlowModel';
import { WrapFlowEngine, WrapFlowParams } from './WrapFlowEngine';
import { PhotoAnchorCard } from '../photo/PhotoAnchorCard';

const DOMAIN = 0x0000;
const TAG = 'WrapFlowEditor';

/** 照片卡宽 = 正文区宽的 46%（iOS `RichTextView.photoWidthRatio` 同款） */
const PHOTO_WIDTH_RATIO: number = 0.46;

/** 光标闪烁半周期（ms）；系统光标节奏 */
const CARET_BLINK_INTERVAL: number = 530;

/** 自绘光标宽（vp） */
const CARET_WIDTH_VP: number = 2;

/** 已排好版、待绘制的一段（Paragraph + 段顶 y + 模型映射，供光标 / 命中查询） */
class RenderParagraph {
  paragraph: text.Paragraph;
  /** 段顶 y（容器坐标，vp） */
  yVp: number;
  /** 本段文本在编辑模型 doc.text 里的起点（块区间起点 + 行段起点） */
  modelStart: number;
  /** 本段文本长度（UTF-16；光标 / 命中的段内边界） */
  length: number;
  /** 行高（vp，空段光标高度用） */
  lineHeightVp: number;
  /** 首行 headIndent（vp，空段光标 x 用） */
  headIndent0Vp: number;

  constructor(paragraph: text.Paragraph, yVp: number, modelStart: number, length: number,
    lineHeightVp: number, headIndent0Vp: number) {
    this.paragraph = paragraph;
    this.yVp = yVp;
    this.modelStart = modelStart;
    this.length = length;
    this.lineHeightVp = lineHeightVp;
    this.headIndent0Vp = headIndent0Vp;
  }
}

/** 绕排绘制 Span：把 CustomSpan 的测量/绘制回调转给宿主闭包（同 WrapFlowView） */
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

/** 光标段定位结果（编辑模型偏移 → 段 + 段内偏移） */
class CaretSegment {
  /** 命中的渲染段（undefined = 无法归属） */
  rp: RenderParagraph | undefined;
  /** 段内偏移 */
  local: number;

  constructor(rp: RenderParagraph | undefined, local: number) {
    this.rp = rp;
    this.local = local;
  }
}

/** buildItems 的产物：引擎输入项 + 文本项的行段 sidecar（itemIndex 平行索引） */
class BuiltItems {
  /** 引擎输入（文本行段项 + 照片项，文档序） */
  items: WrapFlowItem[] = [];
  /** 文本项的行段（与 items 平行；照片项 undefined） */
  parts: (TextPart | undefined)[] = [];
  /** 文本项对应块在 textRanges 里的下标（与 items 平行；照片项 -1） */
  blockIdxs: number[] = [];
}

/**
 * 绕排正文编辑器。数据流：编辑源头在组件内（RichDocEditor 持活文档），
 * `initialBlocks` 仅挂载时消费一次；内容变化经 `onBlocksChange` 通知宿主
 * （存草稿 / 保存），宿主不回写。照片 M1 纯预览（轻点 = onPhotoOpen），
 * 照片编辑态联动（插入 / 删除 / 换边 / 功能条）是 M3。
 */
@Component
export struct WrapFlowEditor {
  @StorageProp(STORAGE_KEY_THEME) @Watch('onThemeChanged') theme: AppTheme = new BambooTheme();
  /** 初始内容块（挂载时消费一次） */
  @Prop initialBlocks: ContentBlock[] = [];
  /** 会员判定（相纸降级） */
  isMember: boolean = true;
  /** 内容变化通知（最新块列表；宿主存草稿 / 保存用） */
  onBlocksChange: (blocks: ContentBlock[]) => void = (_blocks: ContentBlock[]): void => {};
  /** 照片轻点（详情语义：开全屏预览） */
  onPhotoOpen: (blockId: string) => void = (_blockId: string): void => {};

  private textController: TextController = new TextController();
  private richController: RichEditorController = new RichEditorController();
  private span: WrapFlowSpan | undefined = undefined;
  private adapter: WrapFlowTextAdapter | undefined = undefined;
  private engine: WrapFlowEngine | undefined = undefined;
  private containerWidth: number = 0;
  private renderParagraphs: RenderParagraph[] = [];
  private readonly loadedPhotoIds: Set<string> = new Set<string>();
  /** 编辑模型（活文档；RichDocEditor 字符级算子） */
  private doc: RichDocEditor | undefined = undefined;
  /** 锚点块本体表（id → 照片 / 录音 / 痕迹块，拆回时复用本体） */
  private anchoredBlocks: Map<string, ContentBlock> = new Map<string, ContentBlock>();
  /** 当前块列表（模型拆回的最新投影；渲染与照片叠放的输入） */
  private currentBlocks: ContentBlock[] = [];
  /** 隐形层镜像文本（= doc.text；diff 基准） */
  private mirrorText: string = '';
  /** 文本块区间表（模型偏移 ↔ 段内偏移的映射，随块重建） */
  private textRanges: TextBlockRange[] = [];
  /** 隐形层内容已注入 */
  private hiddenReady: boolean = false;
  /** 光标（编辑模型偏移） */
  private caretModelOffset: number = 0;
  private blinkTimer: number = -1;
  /** 空态最小高度（3 行正文行高；spanMeasure 下限，空文档可点可输入） */
  private minBodyHeightVp: number = 0;
  /** 空态单行高（空文档光标高度用） */
  private emptyLineHeightVp: number = 24;
  /** 空态占位符段（无可见文字时画；随 relayout 重建） */
  private placeholderParagraph: text.Paragraph | undefined = undefined;
  /** 占位符文案缓存（resourceManager 同步读，仅空态触发一次） */
  private cachedPlaceholderText: string = '';
  /** 隐形层焦点键（每实例唯一） */
  private readonly hiddenKey: string = `wrap_flow_hidden_${Date.now().toString(36)}`;

  @State private photoAspects: Map<string, number> = new Map<string, number>();
  @State private flowResult: WrapFlowResult | undefined = undefined;
  /** 自绘光标（容器坐标 vp；caretX < 0 = 隐藏） */
  @State private caretX: number = -1;
  @State private caretY: number = 0;
  @State private caretH: number = 0;
  @State private caretBlinkOn: boolean = true;

  aboutToAppear(): void {
    this.currentBlocks = this.initialBlocks;
    this.anchoredBlocks = anchoredBlocksOf(this.initialBlocks);
    const doc = editorDocumentFromBlocks(this.initialBlocks);
    this.doc = new RichDocEditor(doc);
    this.mirrorText = doc.text;
    this.textRanges = textBlockRangesOfBlocks(this.initialBlocks);
    this.rebuildEngine();
    this.span = new WrapFlowSpan((): CustomSpanMetrics => this.spanMeasure(),
      (canvas: drawing.Canvas): void => this.spanDraw(canvas));
    this.textController.setStyledString(new MutableStyledString(this.span));
    this.loadPhotoAspects();
  }

  aboutToDisappear(): void {
    this.stopBlink();
  }

  // ---- CustomSpan 宿主回调 ----

  private spanMeasure(): CustomSpanMetrics {
    const result = this.flowResult;
    if (result === undefined || this.containerWidth <= 0) {
      return { width: 0, height: 0 };
    }
    return {
      width: this.containerWidth,
      height: Math.max(result.totalHeight, this.minBodyHeightVp)
    };
  }

  private spanDraw(canvas: drawing.Canvas): void {
    const adapter = this.adapter;
    if (adapter === undefined) {
      return;
    }
    const density = adapter.density;
    hilog.info(DOMAIN, TAG, 'DRAW canvas %{public}sx%{public}s paras=%{public}s',
      `${canvas.getWidth()}`, `${canvas.getHeight()}`, this.renderParagraphs.length);
    const placeholder = this.placeholderParagraph;
    if (placeholder !== undefined) {
      placeholder.paint(canvas, 0, 0);
    }
    for (const rp of this.renderParagraphs) {
      try {
        rp.paragraph.paint(canvas, 0, rp.yVp * density);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'DRAW para failed y=%{public}s: %{public}s',
          `${rp.yVp}`, JSON.stringify(err));
      }
    }
  }

  // ---- 布局管线 ----

  private onThemeChanged(): void {
    this.rebuildEngine();
    this.relayout();
  }

  private rebuildEngine(): void {
    const appearance = RichTextAppearance.forTheme(this.theme);
    this.minBodyHeightVp = appearance.bodyLineHeight * 3;
    this.emptyLineHeightVp = appearance.bodyLineHeight;
    this.adapter = new WrapFlowTextAdapter(appearance);
    this.engine = new WrapFlowEngine(new WrapFlowParams(appearance.bodyLineHeight,
      appearance.headingLineHeight), this.adapter);
  }

  /** 引擎输入：当前块列表 → 文本行段项（\n 拆分，heading=行段语义）+ 照片项 */
  private buildItems(): BuiltItems {
    const built = new BuiltItems();
    if (this.containerWidth <= 0) {
      return built;
    }
    const cardWidth = this.containerWidth * PHOTO_WIDTH_RATIO;
    let textBlockIdx = 0; // 文本块序 = textRanges 序（同为文本块子序列）
    for (const block of this.currentBlocks) {
      if (block.type === ContentBlockType.Photo) {
        const style = effectivePaperStyle(block.paperStyle ?? PaperStyle.Polaroid, this.isMember);
        const aspect = this.photoAspects.get(block.id);
        built.items.push(new WrapFlowPhotoItem(block.id, block.position ?? PhotoPosition.Right,
          photoCardMetrics(cardWidth, aspect ?? 4 / 3, style)));
        built.parts.push(undefined);
        built.blockIdxs.push(-1);
      } else if (block.type === ContentBlockType.Text && block.text !== undefined) {
        for (const part of textPartsOfBlock(block.text, block.styles ?? [])) {
          built.items.push(new WrapFlowTextItem(part.text, part.isHeading, part.runs));
          built.parts.push(part);
          built.blockIdxs.push(textBlockIdx);
        }
        textBlockIdx++;
      }
    }
    return built;
  }

  /**
   * 一次完整重排：模型 → 拆回块（同步宿主）→ 引擎几何 → 渲染层重建各段
   * Paragraph（带模型映射）→ 换新 span 重测重渲（API 26 实测：尺寸变化必须换
   * 新 span 走 setStyledString，invalidate 只重绘不重测）→ 光标矩形刷新。
   */
  private relayout(): void {
    const engine = this.engine;
    const adapter = this.adapter;
    if (engine === undefined || adapter === undefined || this.containerWidth <= 0) {
      return;
    }
    const built = this.buildItems();
    const items = built.items;
    const result = engine.layout(items, this.containerWidth);
    const nextParagraphs: RenderParagraph[] = [];
    for (const para of result.paragraphs) {
      const itemIndex = para.itemIndex;
      const item = items[itemIndex];
      if (item instanceof WrapFlowTextItem) {
        const part = built.parts[itemIndex];
        const blockIdx = built.blockIdxs[itemIndex];
        const range = blockIdx >= 0 && blockIdx < this.textRanges.length
          ? this.textRanges[blockIdx] : undefined;
        const modelStart = range !== undefined && part !== undefined
          ? range.start + part.localStart : 0;
        nextParagraphs.push(new RenderParagraph(
          adapter.buildParagraph(item, para.headIndents, para.tailIndents, this.containerWidth),
          para.y,
          modelStart,
          part !== undefined ? part.text.length : item.text.length,
          para.lineHeight,
          para.headIndents.length > 0 ? para.headIndents[0] : 0));
      }
    }
    this.renderParagraphs = nextParagraphs;
    this.flowResult = result;
    this.debugLogLayout(items, result, nextParagraphs);
    const doc = this.doc;
    this.placeholderParagraph = doc !== undefined && doc.text.length === 0
      ? adapter.buildPlaceholderParagraph(this.placeholderText(), this.theme.textTertiary, this.containerWidth)
      : undefined;
    const nextSpan = new WrapFlowSpan((): CustomSpanMetrics => this.spanMeasure(),
      (canvas: drawing.Canvas): void => this.spanDraw(canvas));
    this.span = nextSpan;
    this.textController.setStyledString(new MutableStyledString(nextSpan));
    this.refreshCaretRect();
  }

  /** 诊断：一次 relayout 的完整几何（items/段落/照片/实测高度），对不上像素时排查用 */
  private debugLogLayout(items: WrapFlowItem[], result: WrapFlowResult,
    paragraphs: RenderParagraph[]): void {
    const adapter = this.adapter;
    if (adapter === undefined) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'LAYOUT-ITEMS %{public}s', items.map((it: WrapFlowItem): string =>
      it instanceof WrapFlowPhotoItem ? `P${it.card.width.toFixed(0)}x${it.card.height.toFixed(0)}`
        : `T"${(it as WrapFlowTextItem).text.substring(0, 6)}"${(it as WrapFlowTextItem).isHeading ? 'H' : 'B'}`).join(','));
    hilog.info(DOMAIN, TAG, 'LAYOUT-PARAS %{public}s', result.paragraphs.map((p: WrappedParagraphRect): string =>
      `#${p.itemIndex}@${p.y.toFixed(1)}x${p.lineCount}lh${p.lineHeight}h${p.headIndents[0].toFixed(0)}`).join(','));
    hilog.info(DOMAIN, TAG, 'LAYOUT-PHOTOS %{public}s', result.photos.map((r: WrappedPhotoRect): string =>
      `${r.blockId.substring(0, 4)}@${r.x.toFixed(0)},${r.y.toFixed(1)} ${r.width.toFixed(0)}x${r.height.toFixed(1)}`).join(','));
    hilog.info(DOMAIN, TAG, 'LAYOUT-ACT %{public}s', paragraphs.map((rp: RenderParagraph): string =>
      `${(rp.paragraph.getHeight() / adapter.density).toFixed(1)}`).join(','));
    hilog.info(DOMAIN, TAG, 'LAYOUT-RANGES %{public}s', this.textRanges.map((r: TextBlockRange): string =>
      `${r.start}+${r.length}`).join(','));
  }

  /** 编辑模型变化 → 拆回块 + 区间表 + 通知宿主 + 重排 */
  private syncFromModel(): void {    const doc = this.doc;
    if (doc === undefined) {
      return;
    }
    this.currentBlocks = blocksWithEditorDocument(doc.document, this.anchoredBlocks,
      (): string => generateUuid());
    this.textRanges = textBlockRangesOfBlocks(this.currentBlocks);
    hilog.info(DOMAIN, TAG, 'BLOCKS %{public}s', this.currentBlocks.map((b: ContentBlock): string =>
      b.type === ContentBlockType.Photo ? 'P' :
        `T"${b.text !== undefined ? b.text.substring(0, 6) : ''}"${b.text !== undefined ? b.text.length : 0}`).join(','));
    this.loadPhotoAspects();
    this.onBlocksChange(this.currentBlocks);
    this.relayout();
  }

  // ---- 隐形输入层（diff 模式） ----

  /** 隐形层全文（纯文本 span，U+FFFC 锚点占位；getSpans 一次拼出） */
  private hiddenText(): string {
    let full = '';
    for (const raw of this.richController.getSpans({})) {
      const span = raw as RichEditorTextSpanResult;
      if (span.value !== undefined) {
        full += span.value;
      }
    }
    return full;
  }

  /** onDidChange：隐形层内容已变 → diff → 同步编辑模型 → 重排 */
  private onHiddenTextChange(): void {
    const doc = this.doc;
    if (doc === undefined || !this.hiddenReady) {
      return;
    }
    const next = this.hiddenText();
    const diff = diffTextEdit(this.mirrorText, next);
    if (diff.kind !== 'none') {
      hilog.info(DOMAIN, TAG, 'diff kind=%{public}s offset=%{public}d len=%{public}d val=%{public}s',
        diff.kind, diff.offset, diff.length, diff.value);
    }
    if (diff.kind === 'none') {
      return; // 锚点恢复后的收敛轮
    }
    if (diff.kind === 'insert') {
      doc.insert(diff.offset, diff.value);
      this.mirrorText = next;
      this.syncFromModel();
      this.resetBlink();
      return;
    }
    // delete / complex：先删（锚点保护检查），complex 再补插入
    const result = doc.deleteRange(diff.offset, diff.length);
    if (result === 'anchor') {
      this.restoreHiddenRange(diff.offset, diff.length);
      return;
    }
    if (diff.kind === 'complex' && diff.value.length > 0) {
      doc.insert(diff.offset, diff.value);
    }
    this.mirrorText = next;
    this.syncFromModel();
    this.resetBlink();
  }

  /**
   * 锚点兜底恢复：被删文本里有锚点字符 → 整段被删文本塞回隐形层（镜像不动），
   * 光标放回删除点。M2 换「先选中锚点再删」交互。
   */
  private restoreHiddenRange(offset: number, length: number): void {
    const piece = this.mirrorText.substring(offset, offset + length);
    this.richController.addTextSpan(piece, { offset });
    this.richController.setCaretOffset(offset);
    hilog.info(DOMAIN, TAG, 'anchor restored at %{public}d len=%{public}d', offset, length);
  }

  /** aboutToDelete 预判：删除区间覆盖锚点字符 → 拦截（false） */
  private shouldAllowDelete(value: RichEditorDeleteValue): boolean {
    const len = Math.max(value.length, 1);
    const start = Math.max(value.offset - len, 0);
    const end = Math.min(value.offset + len, this.mirrorText.length);
    return this.mirrorText.substring(start, end).indexOf(RICH_ANCHOR) < 0;
  }

  private onSelectionChange(range: RichEditorRange): void {
    hilog.info(DOMAIN, TAG, 'selection start=%{public}s end=%{public}s',
      `${range.start ?? -1}`, `${range.end ?? -1}`);
    if (range.start !== range.end) {
      return; // 选区高亮 / 手柄是 M2
    }
    this.caretModelOffset = range.start ?? 0;
    this.refreshCaretRect();
    this.resetBlink();
  }

  // ---- 光标（自绘 + 命中） ----

  /** 光标矩形刷新：模型偏移 → 段定位 → Paragraph 字形框 → 容器 vp */
  private refreshCaretRect(): void {
    const doc = this.doc;
    const adapter = this.adapter;
    if (doc === undefined || adapter === undefined) {
      this.caretX = -1;
      return;
    }
    const offset = Math.min(Math.max(this.caretModelOffset, 0), doc.text.length);
    if (this.textRanges.length === 0) {
      // 空文档（无任何块）：光标画在占位区左上一行高，空态点击有可见反馈
      this.caretX = 0;
      this.caretY = 0;
      this.caretH = this.emptyLineHeightVp;
      return;
    }
    const seg = this.caretSegmentOf(offset);
    const rp = seg.rp;
    if (rp === undefined) {
      this.caretX = -1;
      return;
    }
    const density = adapter.density;
    const itemLength = rp.length;
    const local = seg.local;
    let xVp: number;
    let yVp: number;
    let hVp: number;
    if (local < itemLength) {
      const rangeValue: text.Range = { start: local, end: local + 1 };
      const boxes = rp.paragraph.getRectsForRange(rangeValue,
        text.RectWidthStyle.TIGHT, text.RectHeightStyle.STRUT);
      if (boxes.length === 0) {
        this.caretX = -1;
        return;
      }
      xVp = boxes[0].rect.left / density;
      yVp = rp.yVp + boxes[0].rect.top / density;
      hVp = (boxes[0].rect.bottom - boxes[0].rect.top) / density;
    } else if (itemLength > 0) {
      // 段尾：取末字形右缘
      const rangeValue: text.Range = { start: local - 1, end: local };
      const boxes = rp.paragraph.getRectsForRange(rangeValue,
        text.RectWidthStyle.TIGHT, text.RectHeightStyle.STRUT);
      if (boxes.length === 0) {
        this.caretX = -1;
        return;
      }
      xVp = boxes[0].rect.right / density;
      yVp = rp.yVp + boxes[0].rect.top / density;
      hVp = (boxes[0].rect.bottom - boxes[0].rect.top) / density;
    } else {
      // 空段：headIndent 处整行高光标
      xVp = rp.headIndent0Vp;
      yVp = rp.yVp;
      hVp = rp.lineHeightVp;
    }
    this.caretX = xVp;
    this.caretY = yVp;
    this.caretH = hVp;
  }

  /**
   * 光标段定位（模型偏移 → 行段 + 段内偏移）。行段覆盖 [modelStart, modelStart+length]，
   * 段末闭区间＝\n 前（TextKit 光标语义：\n 上的光标落在上一行末）；
   * 块间锚点 / 块首 \n 贴下一个文本段段首。
   */
  private caretSegmentOf(offset: number): CaretSegment {
    for (const rp of this.renderParagraphs) {
      if (offset >= rp.modelStart && offset <= rp.modelStart + rp.length) {
        return new CaretSegment(rp, offset - rp.modelStart);
      }
    }
    // 光标在锚点字符 / 补的换行上：贴下一个文本段段首
    for (const rp of this.renderParagraphs) {
      if (rp.modelStart > offset) {
        return new CaretSegment(rp, 0);
      }
    }
    return new CaretSegment(undefined, -1);
  }

  /** 命中查询：容器坐标（vp）→ 编辑模型偏移；-1 = 无法命中 */
  private hitTestOffset(xVp: number, yVp: number): number {
    const doc = this.doc;
    const adapter = this.adapter;
    const result = this.flowResult;
    if (doc === undefined || adapter === undefined || result === undefined) {
      return -1;
    }
    const density = adapter.density;
    for (let i = 0; i < this.renderParagraphs.length && i < result.paragraphs.length; i++) {
      const rp = this.renderParagraphs[i];
      const para = result.paragraphs[i];
      if (yVp < para.y || yVp >= para.y + para.height) {
        continue;
      }
      const pos = rp.paragraph.getGlyphPositionAtCoordinate(
        xVp * density, (yVp - para.y) * density);
      const local = Math.min(Math.max(pos.position, 0), rp.length);
      return rp.modelStart + local;
    }
    // 内容下方空白：光标到文末
    return doc.text.length;
  }

  private resetBlink(): void {
    this.stopBlink();
    this.caretBlinkOn = true;
    this.blinkTimer = setInterval((): void => {
      this.caretBlinkOn = !this.caretBlinkOn;
    }, CARET_BLINK_INTERVAL);
  }

  private stopBlink(): void {
    if (this.blinkTimer >= 0) {
      clearInterval(this.blinkTimer);
      this.blinkTimer = -1;
    }
  }

  private focusHidden(): void {
    try {
      this.getUIContext().getFocusController().requestFocus(this.hiddenKey);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'requestFocus failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 空态占位符文案（复用正文占位资源 s_74bd07ef78；缓存一次） */
  private placeholderText(): string {
    if (this.cachedPlaceholderText.length > 0) {
      return this.cachedPlaceholderText;
    }
    try {
      const context = this.getUIContext().getHostContext();
      if (context !== undefined) {
        this.cachedPlaceholderText = context.resourceManager
          .getStringSync($r('app.string.s_74bd07ef78'));
      }
    } catch (err) {
      // 资源读取失败：占位符留空，仅少一行提示文字
    }
    return this.cachedPlaceholderText;
  }

  // ---- 照片比例加载（同 WrapFlowView：比例决定相纸卡高，加载完重排） ----

  private loadPhotoAspects(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const io = PhotoPaperIO.forFilesDir(context.filesDir);
    for (const block of this.currentBlocks) {
      if (block.type !== ContentBlockType.Photo || this.loadedPhotoIds.has(block.id)) {
        continue;
      }
      this.loadedPhotoIds.add(block.id);
      io.loadImage(block.photoFilename).then((loaded: image.PixelMap | undefined): void => {
        if (loaded === undefined) {
          return;
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
    for (const block of this.currentBlocks) {
      if (block.id === blockId && block.type === ContentBlockType.Photo) {
        return block;
      }
    }
    return new ContentBlock(blockId, ContentBlockType.Photo);
  }

  // ---- 视图 ----

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 隐形输入层：系统全权管理输入 / 组合 / 删除 / 光标，自绘层做美化镜像
      RichEditor({ controller: this.richController })
        .key(this.hiddenKey)
        .focusable(true)
        .opacity(0)
        .width(1)
        .height(1)
        .onAppear((): void => {
          if (this.hiddenReady || this.doc === undefined) {
            return;
          }
          this.hiddenReady = true;
          if (this.mirrorText.length > 0) {
            this.richController.addTextSpan(this.mirrorText);
          }
          hilog.info(DOMAIN, TAG, 'hidden injected len=%{public}d', this.mirrorText.length);
        })
        .aboutToDelete((value: RichEditorDeleteValue): boolean => this.shouldAllowDelete(value))
        .onDidChange((_before: TextRange, _after: TextRange): void => this.onHiddenTextChange())
        .onSelectionChange((range: RichEditorRange): void => this.onSelectionChange(range))
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
      if (this.caretX >= 0 && this.caretBlinkOn) {
        Rect({ width: CARET_WIDTH_VP, height: this.caretH })
          .fill(this.theme.textPrimary)
          .position({ x: this.caretX, y: this.caretY })
          .borderRadius(1)
      }
    }
    .width('100%')
    .onClick((event: ClickEvent) => {
      this.focusHidden();
      if (!this.hiddenReady) {
        hilog.warn(DOMAIN, TAG, 'click before hidden ready');
        return;
      }
      const offset = this.hitTestOffset(event.x, event.y);
      hilog.info(DOMAIN, TAG, 'click x=%{public}s y=%{public}s hit=%{public}d caret=%{public}d',
        `${event.x}`, `${event.y}`, offset, this.caretModelOffset);
      if (offset >= 0) {
        const ok = this.richController.setCaretOffset(offset);
        hilog.info(DOMAIN, TAG, 'setCaretOffset(%{public}d) -> %{public}s', offset, `${ok}`);
      }
    })
  }
}
