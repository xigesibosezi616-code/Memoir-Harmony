/**
 * 富文本正文编辑器（10_BUILD_MANUAL.md 2.5/2.6/2.7/2.8）。对应 iOS `Views/Components/RichText/RichTextView.swift`。
 *
 * - `RichBodyController`：包一层 RichEditorController —— 文档装载 / 读回、
 *   四盏格式灯（加粗 / 斜体 / 小标题 / 荧光笔）状态、切换（选区逐 span 应用、
 *   无选区改接下来打的字）、选中菜单「荧光笔 / 擦掉荧光笔 / 取消划掉」、
 *   照片 / 录音 / 痕迹锚点注册表（2.6/2.7/2.8）
 * - `RichBodyEditor`：渲染组件。`editable=false`（详情页）只读展示同一套排版
 *
 * 灯的语义与 iOS 一致：选中区间内**全部**有该格式才算亮；toggle 翻转 = 全亮→关，否则→开；
 * 小标题整段生效（getParagraphs）；无选区改 typingStyle（接下来打的字）。
 *
 * 2.6/2.7 锚点（Q23 退化方案：builder span 整行卡片）：
 * - builder span 内容 getSpans 拿不到（官方 FAQ「使用RichEditor实现@用户名效果」），
 *   锚点 ↔ 块本体映射自维护：`photoBlocks` / `audioBlocks` / `traceBlocks`（id → 本体，
 *   页面当 anchored 侧表）+ `anchorOrder`（照片 + 录音 + 痕迹在正文里的混合顺序）
 * - 锚点在 getSpans 里表现为无 value 的 span、占 1 个偏移（同图片 span），
 *   读回时按顺序与 anchorOrder 配对；个数对不上打诊断日志（真机 spike 重点）
 * - 退格两段式（R-RICH-05）：aboutToDelete 拦截 —— 第一次重建该卡带选中态并
 *   return false，第二次自行 deleteSpans（照片删锚点；录音连后随换行一起删，
 *   退到录音后那个换行也归录音管，iOS shouldChangeTextIn 同款）；
 *   范围删除连文字带锚点放行，onDeleteComplete 同步注册表并通知页面清文件
 *
 * 2.8 墨迹会干（R-INK）：writtenAt / struckAt 装不进 RichEditor 样式（Q24），
 * 影子台账 `InkLedger` 与活文本逐字符对齐（onDidChange 单点 diff 同步，新字记
 * `sessionSec`）：
 * - 删除转划掉（R-INK-02）：aboutToDelete 里干字拦截 → `planInkRespectingDelete`
 *   （干字划掉变淡加线、湿字照删、换行 / 锚点 / 已划过的留），光标停划掉字前
 * - 干照片 / 录音不删，取下换痕迹块（R-INK-05，`retireAnchorAt`：文件照旧
 *   通知页面清，原位留「取下了一张照片 · 某月某日」一行小字）
 * - 划掉 <24h 可选区菜单「取消划掉」（R-INK-03，`unstrikeRange`）
 * - 读回 `currentDocument` 用 `overlayInkOntoSpans` 把台账叠回纯视觉 spans，
 *   保存链路从此带上 writtenAt / struckAt（Q24 的解）；`notifyTextChange`
 *   发可见正文（划掉的字不算内容，R-INK-08）
 * - 「补记 · 某月某日」段标不做（RichEditor 画不了段前距，见 09 Q25 记录）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_APP_LANGUAGE } from '../../../services/LanguageManager';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import {
  AUDIO_LIMIT_PER_ENTRY,
  ContentBlock,
  ContentBlockType,
  Ink,
  PHOTO_LIMIT_PER_ENTRY
} from '../../../models/ContentBlock';
import {
  RICH_ANCHOR,
  RichEditorDocument,
  RichFormatFlags,
  RichSpan,
  audioInsertionPlan,
  mergeAdjacentRichSpans,
  photoInsertionPlan
} from '../../../models/RichDocument';
import {
  InkDeleteOpKind,
  InkLedger,
  overlayInkOntoSpans,
  planInkRespectingDelete
} from '../../../models/InkLedger';
import { generateUuid } from '../../../models/Uuid';
import { inkDay } from '../../../services/AppDateFormatters';
import { PhotoAnchorCard } from '../photo/PhotoAnchorCard';
import { AudioPlayerCard } from '../audio/AudioPlayerCard';
import { RichTextAppearance, isTransparentColor } from './RichTextAppearance';

const DOMAIN = 0x0000;
const TAG = 'RichBodyEditor';

/** 四种可切换的格式（工具条 + 选中菜单共用） */
export enum RichFormatKind {
  Bold = 'bold',
  Italic = 'italic',
  Highlight = 'highlight',
  Heading = 'heading'
}

/** 荧光笔菜单项 id（区分系统菜单项用） */
const HIGHLIGHT_MENU_ID: TextMenuItemId = TextMenuItemId.of('memoir.highlight');

/** 「取消划掉」菜单项 id（R-INK-03） */
const UNSTRIKE_MENU_ID: TextMenuItemId = TextMenuItemId.of('memoir.unstrike');

/** 加粗判据：字重 ≥600（FontWeight.Bold = 700） */
function fontWeightIsBold(weight: number | string | FontWeight | undefined): boolean {
  return typeof weight === 'number' && weight >= 600;
}

/** 从编辑器读回的文字样式还原格式组（字号判小标题、背景色判荧光笔） */
function flagsFromTextStyle(appearance: RichTextAppearance,
  textStyle: RichEditorTextStyleResult): RichFormatFlags {
  const flags = new RichFormatFlags();
  flags.bold = fontWeightIsBold(textStyle.fontWeight);
  flags.italic = textStyle.fontStyle === FontStyle.Italic;
  flags.heading = textStyle.fontSize >= (appearance.fontSize + appearance.headingFontSize) / 2;
  flags.highlight = textStyle.textBackgroundStyle !== undefined &&
    !isTransparentColor(textStyle.textBackgroundStyle.color);
  return flags;
}

/** 读格式组里某一盏灯的值 */
function flagValue(flags: RichFormatFlags, kind: RichFormatKind): boolean {
  switch (kind) {
    case RichFormatKind.Bold: return flags.bold;
    case RichFormatKind.Italic: return flags.italic;
    case RichFormatKind.Highlight: return flags.highlight;
    case RichFormatKind.Heading: return flags.heading;
    default: return false;
  }
}

/** 置格式组里某一盏灯（其余不动 —— 选区逐 span 应用时保住各自的其它格式） */
function setFlagValue(flags: RichFormatFlags, kind: RichFormatKind, value: boolean): void {
  switch (kind) {
    case RichFormatKind.Bold:
      flags.bold = value;
      break;
    case RichFormatKind.Italic:
      flags.italic = value;
      break;
    case RichFormatKind.Highlight:
      flags.highlight = value;
      break;
    case RichFormatKind.Heading:
      flags.heading = value;
      break;
    default:
      break;
  }
}

/**
 * 富文本正文控制器。页面持有它，编辑器组件把 RichEditorController 交给它包着用；
 * 灯态变化 / 文本变化经回调通知页面（页面镜像成 @State 驱动工具条）。
 */
export class RichBodyController {
  readonly editor: RichEditorController = new RichEditorController();
  /** 灯态（refreshFlags 后更新；页面在 onFlagsChange 里读取镜像） */
  isBold: boolean = false;
  isItalic: boolean = false;
  isHeading: boolean = false;
  isHighlighted: boolean = false;
  /** 灯态变化（选区变化 / 输入 / 切换后） */
  onFlagsChange: () => void = (): void => {};
  /** 文本变化（给页面同步 bodyText / 字数） */
  onTextChange: (text: string) => void = (): void => {};

  // ---- 2.6/2.7 锚点（builder span 注册表，官方最佳实践自维护） ----

  /** 照片块本体（id → block）。页面读它当 `blocksWithEditorDocument` 的照片侧表 */
  photoBlocks: Map<string, ContentBlock> = new Map<string, ContentBlock>();
  /** 录音块本体（id → block），2.7 */
  audioBlocks: Map<string, ContentBlock> = new Map<string, ContentBlock>();
  /** 痕迹块本体（id → block），2.8：干了的照片 / 录音取下后留在原处的记录 */
  traceBlocks: Map<string, ContentBlock> = new Map<string, ContentBlock>();
  /** 正文照片被长按（打开全屏查看；轻点已让位给功能条） */
  onPhotoTap: (blockId: string) => void = (_blockId: string): void => {};
  /** 功能条：放左 / 右侧互换（blockId 定位，双击秒换边同路） */
  onPhotoTogglePosition: (blockId: string) => void = (_blockId: string): void => {};
  /** 功能条：设为 / 取消封面（清旧由页面保证） */
  onPhotoToggleCover: (blockId: string) => void = (_blockId: string): void => {};
  /** 功能条：换相纸（页面重开相纸选择器） */
  onPhotoRestyle: (blockId: string) => void = (_blockId: string): void => {};
  /** 功能条：删除照片（页面负责确认弹窗） */
  onPhotoDelete: (blockId: string) => void = (_blockId: string): void => {};
  /** 照片被移出正文（菜单删除 / 两段式退格 / 范围删除）——页面清落盘文件 */
  onPhotoRemoved: (blockId: string) => void = (_blockId: string): void => {};
  /** 录音被移出正文（卡片 ✕ / 两段式退格 / 范围删除）——页面清落盘文件 */
  onAudioRemoved: (blockId: string) => void = (_blockId: string): void => {};
  /**
   * 照片锚点卡内容工厂（组件 aboutToAppear 注入 —— addBuilderSpan 的 builder
   * 必须在组件上下文里建，controller 是纯类拿不到 @Builder）
   */
  anchorCardBuilderFactory:
    ((block: ContentBlock, armed: boolean) => CustomBuilder) | undefined = undefined;
  /** 录音锚点卡内容工厂（同上，2.7） */
  audioCardBuilderFactory:
    ((block: ContentBlock, armed: boolean) => CustomBuilder) | undefined = undefined;
  /** 痕迹行内容工厂（同上，2.8。「取下了一张照片 · 某月某日」一行小字，不能点不能改） */
  traceCardBuilderFactory:
    ((block: ContentBlock, armed: boolean) => CustomBuilder) | undefined = undefined;

  // ---- 2.8 墨迹会干（影子台账 + 干湿基准 + 编辑会话时刻） ----

  /** 影子墨迹台账：与活文本逐字符对齐的 writtenAt / struckAt（Q24 的解） */
  private inkLedger: InkLedger = new InkLedger();
  /** 台账同步基准：上次同步时的活文本（onDidChange 单点 diff 的 prev 侧） */
  private lastLiveText: string = '';
  /** 本次编辑会话的时刻（Unix 秒）：新打的字记它。undefined = 还在写的新稿（不记） */
  private sessionSec: number | undefined = undefined;
  /** 多步编辑中（insert / strike / retire 会触发 onDidChange）：跳过同步，收尾统一对账 */
  private batching: boolean = false;

  /** 正文里的锚点（照片 + 录音）按出现顺序排的 id（读回时与 getSpans 的无 value span 顺序配对） */
  private anchorOrder: string[] = [];
  /** 第一次退格选中的锚点（R-RICH-05 两段式，照片 / 录音共用） */
  private armedAnchorId: string | undefined = undefined;
  /** 自发的 deleteSpans 不拦（防两段式 / 更新重插时递归触发 aboutToDelete） */
  private selfDeleting: boolean = false;
  /** 范围删除放行后、等 onDeleteComplete 同步出表的锚点 id */
  private pendingRemovedIds: string[] = [];

  private appearance: RichTextAppearance = new RichTextAppearance(14, 8, Color.Transparent,
    Color.Black, 'serif');

  /** 组件 aboutToAppear 时注入排版参数（素笺 17fp / 皮革 / 肯特 14fp 各一套） */
  setAppearance(appearance: RichTextAppearance): void {
    this.appearance = appearance;
  }

  /**
   * 2.8 墨迹上下文（页面在装载文档前注入）：
   * - `baseSec`：日记写下时刻（Unix 秒）—— 干湿 / 补记的判断基准。undefined = 还在写
   *   的新稿（一律不干，05 §3.4）。写进 appearance 供渲染（补记墨色 / 划掉变淡）
   * - `sessionSec`：本次编辑会话时刻 —— 新打的字记它（iOS `sessionDate`）。
   *   undefined = 还在写（新字不记 writtenAt）。编辑页 = Date.now()/1000，详情页只读不传
   */
  setInkContext(baseSec: number | undefined, sessionSec: number | undefined): void {
    this.appearance.inkBaseSec = baseSec;
    this.sessionSec = sessionSec;
  }

  /** 当前时刻（Unix 秒）。干湿判断用真时钟 */
  private nowSec(): number {
    return Date.now() / 1000;
  }

  /** 正文照片张数（上限 5，05 §3.6） */
  photoCount(): number {
    return this.photoBlocks.size;
  }

  /** 正文录音段数（上限 3，R-ENTRY-08） */
  audioCount(): number {
    return this.audioBlocks.size;
  }

  /** 全部锚点本体（照片 + 录音 + 痕迹合并侧表，`blocksWithEditorDocument` 拆块用） */
  anchoredSideTable(): Map<string, ContentBlock> {
    const merged = new Map<string, ContentBlock>();
    this.photoBlocks.forEach((block: ContentBlock, id: string): void => {
      merged.set(id, block);
    });
    this.audioBlocks.forEach((block: ContentBlock, id: string): void => {
      merged.set(id, block);
    });
    this.traceBlocks.forEach((block: ContentBlock, id: string): void => {
      merged.set(id, block);
    });
    return merged;
  }

  /**
   * 装载文档：清空 → 逐 span 注入（照片 / 录音 / 痕迹锚点按侧表建 builder span）→ 重置接下来打的字。
   * `anchored`：照片 / 录音 / 痕迹块本体（id → block）；侧表里没有的锚点不进正文。
   * 墨迹台账随文档建（2.8），活文本基准同步对齐。
   */
  loadDocument(doc: RichEditorDocument,
    anchored: Map<string, ContentBlock> = new Map<string, ContentBlock>()): void {
    this.batching = true;
    this.editor.deleteSpans({});
    this.photoBlocks.clear();
    this.audioBlocks.clear();
    this.traceBlocks.clear();
    this.anchorOrder = [];
    this.armedAnchorId = undefined;
    this.pendingRemovedIds = [];
    this.inkLedger = InkLedger.fromDocument(doc);
    for (const span of doc.spans) {
      if (span.anchorBlockId !== undefined) {
        const block = anchored.get(span.anchorBlockId);
        if (block !== undefined) {
          this.appendAnchor(block);
        }
        continue; // 找不到本体的锚点不画（iOS 同款）
      }
      this.editor.addTextSpan(span.text, { style: this.appearance.textStyleFor(span.flags) });
    }
    this.editor.setTypingStyle(this.appearance.baseTextStyle());
    this.batching = false;
    this.lastLiveText = this.liveText();
    this.refreshFlags();
  }

  /**
   * 读回文档。照片 / 录音 / 痕迹锚点 = getSpans 里的无 value span（builder span 内容拿不到，
   * 官方 FAQ 配方：按出现顺序与 anchorOrder 配对），个数对不上打诊断日志。
   * 文字 span 是纯视觉的（RichEditor 装不下墨迹时间戳，Q24）—— 墨迹从影子台账
   * `overlayInkOntoSpans` 叠回来，保存链路从此带上 writtenAt / struckAt（2.8）。
   */
  currentDocument(): RichEditorDocument {
    const doc = new RichEditorDocument();
    const spans: RichSpan[] = [];
    let anchorCursor = 0;
    for (const raw of this.editor.getSpans({})) {
      // getSpans 返回 Image|Text 联合：锚点 span 没有 value / textStyle（运行时 undefined）
      const span = raw as RichEditorTextSpanResult;
      if (span.value === undefined || span.textStyle === undefined) {
        if (anchorCursor < this.anchorOrder.length) {
          const blockId = this.anchorOrder[anchorCursor];
          const block = this.photoBlocks.get(blockId) ?? this.audioBlocks.get(blockId) ??
            this.traceBlocks.get(blockId);
          if (block !== undefined) {
            spans.push(new RichSpan(RICH_ANCHOR, new RichFormatFlags(), blockId, block.type));
          } else {
            hilog.warn(DOMAIN, TAG, 'anchor #%d id %s missing body', anchorCursor, blockId);
          }
        } else {
          hilog.warn(DOMAIN, TAG, 'anchor span #%d exceeds registry', anchorCursor);
        }
        anchorCursor++;
        continue;
      }
      spans.push(new RichSpan(span.value, flagsFromTextStyle(this.appearance, span.textStyle)));
    }
    if (anchorCursor !== this.anchorOrder.length) {
      hilog.warn(DOMAIN, TAG, 'anchor/registry mismatch: spans=%{public}d registry=%{public}d',
        anchorCursor, this.anchorOrder.length);
    }
    doc.spans = mergeAdjacentRichSpans(overlayInkOntoSpans(spans, this.inkLedger));
    let text = '';
    for (const span of doc.spans) {
      text += span.text;
    }
    doc.text = text;
    return doc;
  }

  // ---- 2.6 照片锚点操作（插入 / 更新 / 删除 / 两段式退格） ----

  /**
   * 在光标处插照片（R-RICH-03 三分支由 `photoInsertionPlan` 纯函数算好）。
   * 返回 false = 超上限 5 张或组件还没注入内容工厂（兜底，页面正常不该走到）。
   */
  insertPhoto(block: ContentBlock): boolean {
    if (this.photoBlocks.size >= PHOTO_LIMIT_PER_ENTRY ||
      this.anchorCardBuilderFactory === undefined) {
      return false;
    }
    const prevLive = this.liveText();
    this.batching = true;
    const plan = photoInsertionPlan(this.liveText(), this.editor.getCaretOffset());
    let anchorOffset = plan.insertOffset;
    if (plan.needsNewlineBefore) {
      // 段中：先断成两段（基础样式），照片挂后一段开头
      this.editor.addTextSpan('\n', {
        offset: plan.insertOffset,
        style: this.appearance.baseTextStyle()
      });
      anchorOffset += 1;
    }
    this.photoBlocks.set(block.id, block);
    this.anchorOrder.splice(this.anchorIndexAt(anchorOffset), 0, block.id);
    this.editor.addBuilderSpan(this.anchorCardBuilderFactory(block, false), { offset: anchorOffset });
    this.editor.setCaretOffset(plan.caretAfter);
    this.batching = false;
    this.inkLedger.syncText(prevLive, this.liveText(), this.sessionSec);
    this.lastLiveText = this.liveText();
    hilog.info(DOMAIN, TAG, 'insertPhoto id=%{public}s file=%{public}s anchorOffset=%{public}d',
      block.id, block.photoFilename ?? 'nil', anchorOffset);
    this.refreshFlags(); // 工具条照片键置灰镜像靠 onFlagsChange
    this.notifyTextChange();
    return true;
  }

  /**
   * 在光标所在段下面插录音（R-RICH-04 `audioInsertionPlan`：锚点 + 后随换行自成一段）。
   * 返回 false = 超上限 3 段（R-ENTRY-08）或组件还没注入内容工厂。
   */
  insertAudio(block: ContentBlock): boolean {
    if (this.audioBlocks.size >= AUDIO_LIMIT_PER_ENTRY ||
      this.audioCardBuilderFactory === undefined) {
      return false;
    }
    const prevLive = this.liveText();
    this.batching = true;
    const plan = audioInsertionPlan(this.liveText(), this.editor.getCaretOffset());
    let anchorOffset = plan.insertOffset;
    if (plan.needsNewlineBefore) {
      // 录在文末且最后一段没换行：先补一个换行隔开这段话
      this.editor.addTextSpan('\n', {
        offset: plan.insertOffset,
        style: this.appearance.baseTextStyle()
      });
      anchorOffset += 1;
    }
    this.audioBlocks.set(block.id, block);
    this.anchorOrder.splice(this.anchorIndexAt(anchorOffset), 0, block.id);
    this.editor.addBuilderSpan(this.audioCardBuilderFactory(block, false), { offset: anchorOffset });
    // 后随换行：录音自成一段（iOS AudioAnchorAttachment 同款）
    this.editor.addTextSpan('\n', {
      offset: anchorOffset + 1,
      style: this.appearance.baseTextStyle()
    });
    this.editor.setCaretOffset(plan.caretAfter);
    this.batching = false;
    this.inkLedger.syncText(prevLive, this.liveText(), this.sessionSec);
    this.lastLiveText = this.liveText();
    hilog.info(DOMAIN, TAG, 'insertAudio id=%{public}s file=%{public}s anchorOffset=%{public}d',
      block.id, block.audioFilename ?? 'nil', anchorOffset);
    this.refreshFlags(); // 工具条 mic 键置灰镜像靠 onFlagsChange
    this.notifyTextChange();
    return true;
  }

  /** 照片块更新（换相纸 / 换边 / 设为封面）：替换注册表本体，同偏移删旧卡重插新卡 */
  updatePhoto(block: ContentBlock): void {
    const index = this.anchorOrder.indexOf(block.id);
    if (index < 0 || this.anchorCardBuilderFactory === undefined) {
      return;
    }
    const offsets = this.anchorOffsets();
    if (index >= offsets.length) {
      hilog.warn(DOMAIN, TAG, 'updatePhoto offset missing, id=%{public}s', block.id);
      return;
    }
    this.batching = true;
    this.photoBlocks.set(block.id, block);
    this.deleteRangeSelf(offsets[index], offsets[index] + 1);
    this.editor.addBuilderSpan(this.anchorCardBuilderFactory(block, false), { offset: offsets[index] });
    this.batching = false;
    this.lastLiveText = this.liveText();
    this.armedAnchorId = undefined;
    this.refreshFlags();
  }

  /**
   * 从正文删除指定照片（全屏菜单「删除照片」），出表 + 通知页面清文件。
   * 墨迹干了的照片不删，取下换痕迹（R-INK-05，iOS `removePhoto` 同款）。
   */
  deletePhoto(blockId: string): void {
    const index = this.anchorOrder.indexOf(blockId);
    if (index < 0) {
      return;
    }
    if (this.isAnchorDry(blockId)) {
      this.retireAnchorAt(index);
      return;
    }
    const offsets = this.anchorOffsets();
    if (index >= offsets.length) {
      hilog.warn(DOMAIN, TAG, 'deletePhoto offset missing, id=%{public}s', blockId);
      return;
    }
    this.removeAnchorAt(index, offsets[index] + 1);
  }

  /**
   * 从正文删除指定录音（卡片 ✕ / 两段式退格第二下），出表 + 通知页面清文件。
   * 连锚点后随的换行一起删（iOS `removeAudio` 同款，录音自成一段）。
   * 墨迹干了的录音不删，取下换痕迹（R-INK-05）。
   */
  deleteAudio(blockId: string): void {
    const index = this.anchorOrder.indexOf(blockId);
    if (index < 0) {
      return;
    }
    if (this.isAnchorDry(blockId)) {
      this.retireAnchorAt(index);
      return;
    }
    const offsets = this.anchorOffsets();
    if (index >= offsets.length) {
      hilog.warn(DOMAIN, TAG, 'deleteAudio offset missing, id=%{public}s', blockId);
      return;
    }
    const end = this.audioDeleteEnd(this.liveText(), offsets[index]);
    this.removeAnchorAt(index, end);
  }

  /** 正文照片被长按（锚点卡 → 组件注入的 builder → 这里转给页面开全屏） */
  requestOpenPhoto(blockId: string): void {
    this.onPhotoTap(blockId);
  }

  /** 功能条动作转发（锚点卡 → 页面；blockId 定位，不依赖全屏态） */
  requestTogglePosition(blockId: string): void {
    this.onPhotoTogglePosition(blockId);
  }

  requestToggleCover(blockId: string): void {
    this.onPhotoToggleCover(blockId);
  }

  requestRestyle(blockId: string): void {
    this.onPhotoRestyle(blockId);
  }

  requestDelete(blockId: string): void {
    this.onPhotoDelete(blockId);
  }

  /**
   * 退格 / 删除拦截（R-RICH-05 两段式 + R-INK-02 删除转划掉）：
   * - 删除范围恰好盖住一个锚点：第一次选中（重建该卡带高亮）并拦下，第二次才删
   *   —— 痕迹锚点例外（iOS 无两段式，单击照删）；干的照片 / 录音不删，取下换痕迹
   * - 退到录音后随的换行也归录音管（iOS `shouldChangeTextIn` 同款）：进两段式，
   *   第二下连锚点带换行删 2 字符（干的换痕迹，换行留下）
   * - 删 / 改的范围里有干了的字（`containsDryText`）：不能悄悄删，转划掉
   *   （`strikeDryRange`：干字划掉变淡加线、湿字照删、换行 / 锚点 / 已划过的留，
   *   光标停在划掉的字前面）
   * - 范围删除连文字带锚点：放行（返回 true），onDeleteComplete 里同步注册表
   * - 自发的 deleteSpans（两段式第二下 / 更新重插）不进这
   */
  handleAboutToDelete(value: RichEditorDeleteValue): boolean {
    if (this.selfDeleting) {
      return true;
    }
    const start0 = value.direction === RichEditorDeleteDirection.BACKWARD
      ? value.offset - value.length : value.offset;
    hilog.info(DOMAIN, TAG, 'delete req dir=%{public}d offset=%{public}d len=%{public}d calcStart=%{public}d armed=%{public}s',
      value.direction, value.offset, value.length, start0, this.armedAnchorId ?? '-');
    // ARM 后 caret 可能停在武装 span 起点（offset=0）：此时编辑器报的是
    // 「删除 [0, len)」而非「caret-len」，BACKWARD 差值下溢为负会导致 hits
    // 落空、放行裸删 span 绕过出表 —— 夹到 0 与编辑器实际删除区间对齐
    const start = value.direction === RichEditorDeleteDirection.BACKWARD
      ? Math.max(0, value.offset - value.length) : value.offset;
    const end = start + value.length;
    // ARM 后引擎的退格判定停在锚点起点：第二下报的是「删锚点前一个字符」
    // （range = [锚点offset-1, 锚点offset)）。解释成对武装卡的第二次退格：
    // 干的取下换痕迹、湿的照删锚点 —— 锚点前的字符不动（拦下返回 false）。
    // 走尾随换行路径 ARM 的不受影响（那种第二下正好删中锚点，走下面的单锚点分支）。
    if (this.armedAnchorId !== undefined && value.direction === RichEditorDeleteDirection.BACKWARD &&
      value.length === 1) {
      const armedIndex = this.anchorOrder.indexOf(this.armedAnchorId);
      if (armedIndex >= 0 && end === this.anchorOffsets()[armedIndex]) {
        hilog.info(DOMAIN, TAG, 'armed second BS: index=%{public}d range=[%{public}d,%{public}d)',
          armedIndex, start, end);
        if (this.isAnchorDry(this.armedAnchorId)) {
          this.retireAnchorAt(armedIndex);
        } else {
          const text = this.liveText();
          const anchorOffset = this.anchorOffsets()[armedIndex];
          this.removeAnchorAt(armedIndex, this.audioBlocks.has(this.armedAnchorId)
            ? this.audioDeleteEnd(text, anchorOffset) : anchorOffset + 1);
        }
        return false;
      }
    }
    const offsets = this.anchorOffsets();
    const hits: number[] = [];
    for (let i = 0; i < offsets.length; i++) {
      if (offsets[i] >= start && offsets[i] < end) {
        hits.push(i);
      }
    }
    // 单锚点精确命中：两段式（痕迹例外，单击照删 —— iOS 痕迹不进两段式分支）
    if (hits.length === 1 && start === offsets[hits[0]] && end === offsets[hits[0]] + 1) {
      const blockId = this.anchorOrder[hits[0]];
      if (this.traceBlocks.has(blockId)) {
        this.pendingRemovedIds.push(blockId);
        return true; // 痕迹行：放行直删，完成回调出表（无文件要清）
      }
      const isAudio = this.audioBlocks.has(blockId);
      if (this.armedAnchorId !== blockId) {
        this.armAnchorAt(hits[0], offsets[hits[0]]);
        return false; // 第一次：选中，拦下
      }
      // 第二下：墨迹干了的照片 / 录音不删，取下换痕迹（R-INK-05）
      if (this.isAnchorDry(blockId)) {
        this.retireAnchorAt(hits[0]);
        return false;
      }
      const text = this.liveText();
      this.removeAnchorAt(hits[0], isAudio
        ? this.audioDeleteEnd(text, offsets[hits[0]]) : offsets[hits[0]] + 1);
      return false;
    }
    // 退格删的恰好是录音锚点后随的换行：整个录音块进两段式
    if (hits.length === 0 && value.direction === RichEditorDeleteDirection.BACKWARD &&
      value.length === 1) {
      for (let i = 0; i < offsets.length; i++) {
        if (start === offsets[i] + 1 && this.audioBlocks.has(this.anchorOrder[i])) {
          const text = this.liveText();
          if (start < text.length && text.charCodeAt(start) === 0x0A) {
            const blockId = this.anchorOrder[i];
            if (this.armedAnchorId !== blockId) {
              this.armAnchorAt(i, offsets[i]);
              return false; // 第一次：选中，拦下
            }
            if (this.isAnchorDry(blockId)) {
              this.retireAnchorAt(i); // 干录音：锚点换痕迹，换行留下
              return false;
            }
            this.removeAnchorAt(i, this.audioDeleteEnd(text, offsets[i]));
            return false; // 第二下：连锚点带换行删
          }
        }
      }
    }
    this.armedAnchorId = undefined;
    // 删 / 改的范围里有干了的字：不能悄悄删，转划掉（R-INK-02）
    if (this.containsDryText(start, end)) {
      this.strikeDryRange(start, end);
      return false;
    }
    // 范围删除含锚点：放行，完成回调里按 pending 列表出表
    for (const hit of hits) {
      this.pendingRemovedIds.push(this.anchorOrder[hit]);
    }
    return true;
  }

  /** 删除完成：放行的范围删除在这同步注册表 + 通知页面清文件（痕迹没有文件要清） */
  handleDeleteComplete(): void {
    if (this.pendingRemovedIds.length === 0) {
      return;
    }
    for (const blockId of this.pendingRemovedIds) {
      const index = this.anchorOrder.indexOf(blockId);
      if (index >= 0) {
        this.anchorOrder.splice(index, 1);
      }
      if (this.traceBlocks.has(blockId)) {
        this.traceBlocks.delete(blockId);
        continue;
      }
      if (this.audioBlocks.has(blockId)) {
        this.audioBlocks.delete(blockId);
        this.onAudioRemoved(blockId);
      } else {
        this.photoBlocks.delete(blockId);
        this.onPhotoRemoved(blockId);
      }
    }
    this.pendingRemovedIds = [];
    this.armedAnchorId = undefined;
    this.refreshFlags();
    this.notifyTextChange();
  }

  /** 第一次退格的选中态：同偏移重建该卡（armed 高亮），光标落在卡后（下一次退格再删它） */
  private armAnchorAt(index: number, offset: number): void {
    const blockId = this.anchorOrder[index];
    hilog.info(DOMAIN, TAG, 'ARM index=%{public}d offset=%{public}d id=%{public}s', index, offset, blockId);
    const block = this.photoBlocks.get(blockId) ?? this.audioBlocks.get(blockId);
    const factory = this.audioBlocks.has(blockId)
      ? this.audioCardBuilderFactory : this.anchorCardBuilderFactory;
    if (block === undefined || factory === undefined) {
      return;
    }
    this.armedAnchorId = blockId;
    this.batching = true; // 重建 span 会触发 onDidChange：跳过台账 diff，收尾对账
    this.deleteRangeSelf(offset, offset + 1);
    this.editor.addBuilderSpan(factory(block, true), { offset: offset });
    this.batching = false;
    this.lastLiveText = this.liveText();
    // 可观光标无需手动设置：引擎在 span 重插后自动把它移到卡后（offset+1）。
    // 注意：退格的删除判定用引擎内部记录（aboutToDelete 返回 false 后停在
    // 被取消范围起点 = offset），setCaretOffset 改不了它 —— 第二下退格报的是
    // 「删锚点前一个字符」，由 handleAboutToDelete 的武装分支解释成对武装卡
    // 的第二次退格（真机 2026-10-18 三轮实测 + AceRichText RecordOperation 证实）。
  }

  /** 录音的删除终点：锚点 + 后随换行（有就）一起删 */
  private audioDeleteEnd(text: string, anchorOffset: number): number {
    return text.length > anchorOffset + 1 && text.charCodeAt(anchorOffset + 1) === 0x0A
      ? anchorOffset + 2 : anchorOffset + 1;
  }

  /** 出表 + 定点删除 + 通知页面（照片 / 录音共用；end 是删除终点偏移） */
  private removeAnchorAt(index: number, end: number): void {
    const blockId = this.anchorOrder[index];
    const start = this.anchorOffsets()[index];
    hilog.info(DOMAIN, TAG, 'REMOVE index=%{public}d start=%{public}d end=%{public}d id=%{public}s',
      index, start, end, blockId);
    const isAudio = this.audioBlocks.has(blockId);
    this.anchorOrder.splice(index, 1);
    if (isAudio) {
      this.audioBlocks.delete(blockId);
    } else {
      this.photoBlocks.delete(blockId);
    }
    const prevLive = this.liveText();
    this.batching = true;
    this.deleteRangeSelf(start, end);
    this.batching = false;
    this.inkLedger.syncText(prevLive, this.liveText(), this.sessionSec);
    this.lastLiveText = this.liveText();
    this.armedAnchorId = undefined;
    if (isAudio) {
      this.onAudioRemoved(blockId);
    } else {
      this.onPhotoRemoved(blockId);
    }
    this.refreshFlags();
    this.notifyTextChange();
  }

  // ---- 2.8 墨迹会干（干湿判断 / 删除转划掉 / 取下换痕迹 / 取消划掉） ----

  /** 编辑器文本变了（onDidChange）：单点 diff 同步影子台账，再让页面读可见正文 */
  handleTextChanged(): void {
    if (this.batching) {
      return; // 自发的重建 / 删除：各操作收尾自己对账
    }
    const next = this.liveText();
    this.inkLedger.syncText(this.lastLiveText, next, this.sessionSec);
    this.lastLiveText = next;
  }

  /** 这张照片 / 录音的墨迹干了吗（块级 addedAt 对 baseSec 判断；新稿一律不干） */
  private isAnchorDry(blockId: string): boolean {
    if (this.appearance.inkBaseSec === undefined) {
      return false;
    }
    const block = this.photoBlocks.get(blockId) ?? this.audioBlocks.get(blockId);
    if (block === undefined || block.addedAt === undefined) {
      return false;
    }
    return Ink.isDry(block.addedAt, this.appearance.inkBaseSec, this.nowSec());
  }

  /**
   * 删 / 改的范围里有干了的字吗（R-INK-02 拦截判据；iOS `containsDryText`）。
   * 锚点占位符不算（块级另算）。
   */
  private containsDryText(start: number, end: number): boolean {
    return this.inkLedger.containsDry(this.liveText(), start, end,
      this.appearance.inkBaseSec, this.nowSec());
  }

  /**
   * 删除转划掉（R-INK-02，iOS `replaceRespectingInk`）：按
   * `planInkRespectingDelete` 从后往前执行 —— 干字记 struckAt 并重画（变淡 + 删除线）、
   * 湿字定点删、换行 / 锚点 / 已划过的留 —— 光标停在原来范围起点。
   */
  private strikeDryRange(start: number, end: number): void {
    const text = this.liveText();
    const ops = planInkRespectingDelete(text, this.inkLedger, start, end,
      this.appearance.inkBaseSec, this.nowSec());
    if (ops.length === 0) {
      return;
    }
    const now = this.nowSec();
    this.batching = true;
    for (let i = ops.length - 1; i >= 0; i--) {
      const op = ops[i];
      if (op.kind === InkDeleteOpKind.Strike) {
        this.inkLedger.struckAt[op.offset] = now;
        this.restyleCharAt(op.offset);
      } else if (op.kind === InkDeleteOpKind.Delete) {
        this.inkLedger.writtenAt.splice(op.offset, 1);
        this.inkLedger.struckAt.splice(op.offset, 1);
        this.deleteRangeSelf(op.offset, op.offset + 1);
      }
    }
    this.batching = false;
    this.lastLiveText = this.liveText();
    this.armedAnchorId = undefined;
    this.editor.setCaretOffset(Math.min(start, this.lastLiveText.length));
    hilog.info(DOMAIN, TAG, 'strikeDryRange [%{public}d,%{public}d) ops=%{public}d newLen=%{public}d',
      start, end, ops.length, this.lastLiveText.length);
    this.refreshFlags();
    this.notifyTextChange();
  }

  /** 单字符按台账重画（划掉变淡加线 / 补记换墨色，其余格式保住） */
  private restyleCharAt(offset: number): void {
    const flags = this.charFlagsAt(offset);
    if (offset < this.inkLedger.length) {
      flags.writtenAt = this.inkLedger.writtenAt[offset];
      flags.struckAt = this.inkLedger.struckAt[offset];
    }
    this.editor.updateSpanStyle({
      start: offset,
      end: offset + 1,
      textStyle: this.appearance.textStyleFor(flags)
    });
  }

  /**
   * 干照片 / 干录音不删：取下换痕迹（R-INK-05，iOS `retire`）。
   * 锚点原位换成痕迹块（同样占 1 字符，台账不用动），照片后随不是换行就补一个
   * （痕迹独占一行；录音天然有后随换行），文件照旧通知页面清。
   */
  private retireAnchorAt(index: number): void {
    const blockId = this.anchorOrder[index];
    const original = this.photoBlocks.get(blockId) ?? this.audioBlocks.get(blockId);
    if (original === undefined || this.traceCardBuilderFactory === undefined) {
      return;
    }
    const offsets = this.anchorOffsets();
    if (index >= offsets.length) {
      hilog.warn(DOMAIN, TAG, 'retire offset missing, id=%{public}s', blockId);
      return;
    }
    const offset = offsets[index];
    const isAudio = this.audioBlocks.has(blockId);
    const traceKind = isAudio ? ContentBlockType.Audio : ContentBlockType.Photo;
    const trace = ContentBlock.makeTrace(generateUuid(), traceKind, this.nowSec());
    hilog.info(DOMAIN, TAG, 'RETIRE index=%{public}d offset=%{public}d id=%{public}s trace=%{public}s kind=%{public}s',
      index, offset, blockId, trace.id, traceKind);
    if (isAudio) {
      this.audioBlocks.delete(blockId);
    } else {
      this.photoBlocks.delete(blockId);
    }
    this.traceBlocks.set(trace.id, trace);
    this.anchorOrder[index] = trace.id;
    this.batching = true;
    this.deleteRangeSelf(offset, offset + 1);
    this.editor.addBuilderSpan(this.traceCardBuilderFactory(trace, false), { offset: offset });
    if (!isAudio) {
      const text = this.liveText();
      if (offset + 1 < text.length && text.charCodeAt(offset + 1) !== 0x0A) {
        // 照片痕迹后随不是换行：补一个（iOS retire 同款），台账同步这次插入
        this.editor.addTextSpan('\n', {
          offset: offset + 1,
          style: this.appearance.baseTextStyle()
        });
        this.inkLedger.syncText(text, this.liveText(), undefined);
      }
    }
    this.batching = false;
    this.lastLiveText = this.liveText();
    this.armedAnchorId = undefined;
    if (isAudio) {
      this.onAudioRemoved(blockId);
    } else {
      this.onPhotoRemoved(blockId);
    }
    this.refreshFlags();
    this.notifyTextChange();
  }

  /**
   * 选区菜单「取消划掉」（R-INK-03，iOS `unstrike`）：划掉不到 24 小时的字恢复
   * （struckAt 清掉重画）；划线自己的墨迹会干，干了的取消不了。
   */
  unstrikeRange(start: number, end: number): void {
    const now = this.nowSec();
    const lo = Math.max(0, start);
    const hi = Math.min(end, this.inkLedger.length);
    this.batching = true;
    for (let i = hi - 1; i >= lo; i--) {
      const struck = this.inkLedger.struckAt[i];
      if (struck !== undefined && !Ink.isDry(struck, undefined, now)) {
        this.inkLedger.struckAt[i] = undefined;
        this.restyleCharAt(i);
      }
    }
    this.batching = false;
    this.lastLiveText = this.liveText();
    this.refreshFlags();
    this.notifyTextChange();
  }

  /** 活文本：照片锚点各占 1 个 U+FFFC（与编辑器偏移一一对齐，photoInsertionPlan 用） */
  private liveText(): string {
    let text = '';
    for (const raw of this.editor.getSpans({})) {
      const span = raw as RichEditorTextSpanResult;
      text += span.value === undefined ? RICH_ANCHOR : span.value;
    }
    return text;
  }

  /** 全部照片锚点在活文本里的偏移（升序；下标与 photoOrder 一一对应） */
  private anchorOffsets(): number[] {
    const offsets: number[] = [];
    let cursor = 0;
    for (const raw of this.editor.getSpans({})) {
      const span = raw as RichEditorTextSpanResult;
      if (span.value === undefined) {
        offsets.push(cursor);
        cursor += 1;
      } else {
        cursor += span.value.length;
      }
    }
    return offsets;
  }

  /** 现有锚点里排在 offset 之前的个数（新锚点在 photoOrder 里的插入位） */
  private anchorIndexAt(offset: number): number {
    let index = 0;
    let cursor = 0;
    for (const raw of this.editor.getSpans({})) {
      const span = raw as RichEditorTextSpanResult;
      if (span.value === undefined) {
        if (cursor < offset) {
          index++;
        }
        cursor += 1;
      } else {
        cursor += span.value.length;
      }
    }
    return index;
  }

  /** 文档装载路径：锚点 builder span 追加到当前末尾（照片 / 录音 / 痕迹按块类型分发） */
  private appendAnchor(block: ContentBlock): void {
    const isAudio = block.type === ContentBlockType.Audio;
    const isTrace = block.type === ContentBlockType.Trace;
    // 痕迹块既不是照片也不是录音：2.8 曾漏判落进 photoBlocks，
    // 装载已保存文档时痕迹被按照片卡画成无图占位框（真机 2026-10-18 实测）
    const factory = isTrace ? this.traceCardBuilderFactory
      : (isAudio ? this.audioCardBuilderFactory : this.anchorCardBuilderFactory);
    if (factory === undefined) {
      hilog.warn(DOMAIN, TAG, 'anchor card factory missing, block %{public}s dropped', block.id);
      return;
    }
    if (isTrace) {
      this.traceBlocks.set(block.id, block);
    } else if (isAudio) {
      this.audioBlocks.set(block.id, block);
    } else {
      this.photoBlocks.set(block.id, block);
    }
    this.anchorOrder.push(block.id);
    this.editor.addBuilderSpan(factory(block, false));
  }

  /** 自发的定点删除（不进 aboutToDelete 拦截） */
  private deleteRangeSelf(start: number, end: number): void {
    this.selfDeleting = true;
    this.editor.deleteSpans({ start: start, end: end });
    this.selfDeleting = false;
  }

  /** 光标处（光标左一字符）的格式组；文档开头 = 全灭 */
  cursorFlags(): RichFormatFlags {    const selection = this.editor.getSelection();
    const end = selection.selection[1];
    if (end === 0) {
      return new RichFormatFlags();
    }
    return this.charFlagsAt(end - 1);
  }

  /** 某个字符上的格式组（图片 span 跳过：占一个偏移、无文字格式） */
  private charFlagsAt(offset: number): RichFormatFlags {
    let cursor = 0;
    for (const raw of this.editor.getSpans({})) {
      const span = raw as RichEditorTextSpanResult;
      if (span.value === undefined || span.textStyle === undefined) {
        cursor += 1; // 图片 span 占一个偏移
        continue;
      }
      const spanEnd = cursor + span.value.length;
      if (offset >= cursor && offset < spanEnd) {
        return flagsFromTextStyle(this.appearance, span.textStyle);
      }
      cursor = spanEnd;
    }
    return new RichFormatFlags();
  }

  /**
   * 刷新灯态并通知页面。光标处 = 左一字符的格式（还要让接下来打的字延续它）；
   * 选区内 = 所有文字都亮才亮（iOS currentFlag 同款）。
   */
  refreshFlags(): void {
    const selection = this.editor.getSelection();
    const start = selection.selection[0];
    const end = selection.selection[1];
    if (start === end) {
      const flags = this.cursorFlags();
      this.isBold = flags.bold;
      this.isItalic = flags.italic;
      this.isHeading = flags.heading;
      this.isHighlighted = flags.highlight;
      // 接下来打的字延续光标左侧格式（RichEditor 的 typingStyle 不会自己继承）
      this.editor.setTypingStyle(this.appearance.textStyleFor(flags));
    } else {
      const flags = this.selectionFlags(start, end);
      this.isBold = flags.bold;
      this.isItalic = flags.italic;
      this.isHeading = flags.heading;
      this.isHighlighted = flags.highlight;
    }
    this.onFlagsChange();
  }

  /** 选区内格式组的 AND（一段文字没亮就全灭） */
  private selectionFlags(start: number, end: number): RichFormatFlags {
    const flags = new RichFormatFlags(true, true, true, true);
    let sawText = false;
    let cursor = 0;
    for (const raw of this.editor.getSpans({})) {
      const span = raw as RichEditorTextSpanResult;
      if (span.value === undefined || span.textStyle === undefined) {
        cursor += 1;
        continue;
      }
      const spanStart = cursor;
      const spanEnd = cursor + span.value.length;
      cursor = spanEnd;
      if (spanEnd <= start) {
        continue;
      }
      if (spanStart >= end) {
        break;
      }
      sawText = true;
      const spanFlags = flagsFromTextStyle(this.appearance, span.textStyle);
      flags.bold = flags.bold && spanFlags.bold;
      flags.italic = flags.italic && spanFlags.italic;
      flags.heading = flags.heading && spanFlags.heading;
      flags.highlight = flags.highlight && spanFlags.highlight;
    }
    if (!sawText) {
      return new RichFormatFlags();
    }
    return flags;
  }

  /** 选中区间里是不是**全部**亮着这盏灯（toggle 的翻转判据） */
  private selectionAllHas(kind: RichFormatKind, start: number, end: number): boolean {
    let all = true;
    let sawText = false;
    let cursor = 0;
    for (const raw of this.editor.getSpans({})) {
      const span = raw as RichEditorTextSpanResult;
      if (span.value === undefined || span.textStyle === undefined) {
        cursor += 1;
        continue;
      }
      const spanStart = cursor;
      const spanEnd = cursor + span.value.length;
      cursor = spanEnd;
      if (spanEnd <= start) {
        continue;
      }
      if (spanStart >= end) {
        break;
      }
      sawText = true;
      const spanFlags = flagsFromTextStyle(this.appearance, span.textStyle);
      if (!flagValue(spanFlags, kind)) {
        all = false;
      }
    }
    return sawText && all;
  }

  /**
   * 切换格式。无选区改接下来打的字；有选区逐 span 应用
   * （各自保住其它格式，updateSpanStyle 按区间替换、自动拆 span）；
   * 小标题整段生效（getParagraphs 扩到段落边界，iOS 同款）。
   */
  toggle(kind: RichFormatKind): void {
    const selection = this.editor.getSelection();
    const start = selection.selection[0];
    const end = selection.selection[1];
    if (start === end) {
      const flags = this.cursorFlags();
      setFlagValue(flags, kind, !flagValue(flags, kind));
      this.editor.setTypingStyle(this.appearance.textStyleFor(flags));
      // 无选区：灯直接反映接下来要打的格式（文档还没变，从文档读回恒灭）
      this.isBold = flags.bold;
      this.isItalic = flags.italic;
      this.isHeading = flags.heading;
      this.isHighlighted = flags.highlight;
      this.onFlagsChange();
      return;
    }
    let rangeStart = start;
    let rangeEnd = end;
    if (kind === RichFormatKind.Heading) {
      // 小标题是整段格式：扩到选区涉及的所有段落
      for (const paragraph of this.editor.getParagraphs({ start, end })) {
        rangeStart = Math.min(rangeStart, paragraph.range[0]);
        rangeEnd = Math.max(rangeEnd, paragraph.range[1]);
      }
    }
    const turnOn = !this.selectionAllHas(kind, rangeStart, rangeEnd);
    this.applyFlagToRange(kind, turnOn, rangeStart, rangeEnd);
    this.refreshFlags();
  }

  /**
   * 逐 span 应用一盏灯：区间重叠的每个文字 span 各自带原格式翻转这一盏。
   * 墨迹感知（2.8）：span 内按台账 writtenAt / struckAt 边界再切开，
   * 格式切换后划掉的变淡 / 补记的墨色不丢（iOS NSAttributedString 重排同款语义）。
   */
  private applyFlagToRange(kind: RichFormatKind, turnOn: boolean, start: number, end: number): void {
    let cursor = 0;
    for (const raw of this.editor.getSpans({})) {
      const span = raw as RichEditorTextSpanResult;
      if (span.value === undefined || span.textStyle === undefined) {
        cursor += 1;
        continue;
      }
      const spanStart = cursor;
      const spanEnd = cursor + span.value.length;
      cursor = spanEnd;
      const overlapStart = Math.max(spanStart, start);
      const overlapEnd = Math.min(spanEnd, end);
      if (overlapEnd <= overlapStart) {
        continue;
      }
      const baseFlags = flagsFromTextStyle(this.appearance, span.textStyle);
      setFlagValue(baseFlags, kind, turnOn);
      let i = overlapStart;
      while (i < overlapEnd) {
        const written = i < this.inkLedger.length ? this.inkLedger.writtenAt[i] : undefined;
        const struck = i < this.inkLedger.length ? this.inkLedger.struckAt[i] : undefined;
        let j = i + 1;
        while (j < overlapEnd && j < this.inkLedger.length &&
          this.inkLedger.writtenAt[j] === written && this.inkLedger.struckAt[j] === struck) {
          j++;
        }
        const flags = new RichFormatFlags(baseFlags.bold, baseFlags.italic, baseFlags.heading,
          baseFlags.highlight, written, struck);
        this.editor.updateSpanStyle({
          start: i,
          end: j,
          textStyle: this.appearance.textStyleFor(flags)
        });
        i = j;
      }
    }
  }

  // ---- 选中菜单「荧光笔 / 擦掉荧光笔」（R-RICH-08） ----

  /**
   * 菜单项（iOS `editMenuForTextIn` 同款排列）：
   * 1.「荧光笔 / 擦掉荧光笔」
   * 2.「取消划掉」—— 选区里有划掉不到 24 小时的字才出现（划线自己的墨迹也会干）
   * 3. 系统菜单
   */
  createHighlightMenu(menuItems: Array<TextMenuItem>): Array<TextMenuItem> {
    const selection = this.editor.getSelection();
    const start = selection.selection[0];
    const end = selection.selection[1];
    const allHighlighted = this.selectionAllHas(RichFormatKind.Highlight, start, end);
    const highlightItem: TextMenuItem = {
      content: allHighlighted ? $r('app.string.s_6a94ee7065') : $r('app.string.s_67a01a5a15'),
      icon: $r('sys.symbol.highlighter_line'),
      id: HIGHLIGHT_MENU_ID
    };
    const items: TextMenuItem[] = [highlightItem];
    if (this.inkLedger.hasWetStrike(start, end, this.nowSec())) {
      // 图标省略：sys.symbol.strikethrough 无法离线验证（09 偏差记录）
      items.push({
        content: $r('app.string.s_086b405189'),
        id: UNSTRIKE_MENU_ID
      });
    }
    return items.concat(menuItems);
  }

  /** 菜单点击：自己那两项吃掉（返回 true），其余交给系统 */
  onMenuClick(menuItem: TextMenuItem, range: TextRange): boolean {
    const start = range.start ?? 0; // TextRange 字段可选，先归一（菜单点按必有选区）
    const end = range.end ?? start;
    if (menuItem.id.equals(HIGHLIGHT_MENU_ID)) {
      const turnOn = !this.selectionAllHas(RichFormatKind.Highlight, start, end);
      this.applyFlagToRange(RichFormatKind.Highlight, turnOn, start, end);
      this.refreshFlags();
      return true;
    }
    if (menuItem.id.equals(UNSTRIKE_MENU_ID)) {
      this.unstrikeRange(start, end);
      return true;
    }
    return false;
  }

  /** 文本变化：读全文通知页面（bodyText / 字数 / ✓ 判定）——照片锚点不外漏 */
  notifyTextChange(): void {
    // getSpans 读法（与 liveText 同款，真机验证过锚点定位）：builder span 的 value
    // 为 undefined，整段跳过。不能用 toStyledString：builder span 在里面是**占位
    // 空格**（0x20，真机日志证实 split(U+FFFC) 剥离是空操作 → 纯照片正文「1 字」）。
    // 划掉的字不算可见正文（R-INK-08，iOS `visibleText`：字数 / ✓ 判定同款）。
    let text = '';
    let cursor = 0;
    for (const rawSpan of this.editor.getSpans({})) {
      const span = rawSpan as RichEditorTextSpanResult;
      if (span.value === undefined) {
        cursor += 1;
        continue;
      }
      for (let i = 0; i < span.value.length; i++) {
        const struck = cursor < this.inkLedger.length ? this.inkLedger.struckAt[cursor] : undefined;
        if (struck === undefined) {
          text += span.value.charAt(i);
        }
        cursor++;
      }
    }
    // 段落分隔换行不算内容字符：iOS 文本块不含块间 \n（totalCharCount 只算内容），
    // 拆回时补的换行也丢掉（RichDocument 双向规则同款）
    const content = text.split('\n').join('');
    // 诊断（真机）：两种读法对照（短文本才打，避免刷屏）
    if (content.length <= 8) {
      hilog.info(DOMAIN, TAG, 'notify spans=%{public}d styled=%{public}d content=%{public}d',
        text.length, this.editor.toStyledString({}).getString().length, content.length);
    }
    this.onTextChange(content);
  }
}

/**
 * 富文本正文编辑器组件。写日记 / 编辑页 `editable=true`；
 * 详情页 `editable=false`（不响应触摸，同一套排版只读展示，R-ENTRY-12）。
 */
@Component
export struct RichBodyEditor {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  controller: RichBodyController = new RichBodyController();
  editable: boolean = false;
  placeholderRes: Resource = $r('app.string.s_74bd07ef78');
  /** 编辑器 controller 就绪（组件 onReady 后回调；页面在这之后才能 loadDocument） */
  onReady: () => void = (): void => {};

  aboutToAppear(): void {
    this.controller.setAppearance(RichTextAppearance.forTheme(this.theme));
    // 锚点卡内容工厂：builder 闭包必须在组件上下文里建（addBuilderSpan 官方配方），
    // controller 是纯类，拿不到 @Builder —— 页面侧的插照片 / 插录音 / 装载都经它取内容
    this.controller.anchorCardBuilderFactory =
      (block: ContentBlock, armed: boolean): CustomBuilder => {
        return (): void => {
          this.PhotoAnchorCardBuilder(block, armed);
        };
      };
    this.controller.audioCardBuilderFactory =
      (block: ContentBlock, armed: boolean): CustomBuilder => {
        return (): void => {
          this.AudioAnchorCardBuilder(block, armed);
        };
      };
    this.controller.traceCardBuilderFactory =
      (block: ContentBlock, armed: boolean): CustomBuilder => {
        return (): void => {
          this.TraceAnchorCardBuilder(block);
        };
      };
  }

  /**
   * builder span 内容：一行痕迹（2.8）。「取下了一张照片 · 10月12日」——
   * 12fp 小字（theme.labelColor 同款三级色），不能点不能改，
   * 退格一下就删（无两段式，iOS TraceAnchorAttachment 同款）。
   * 剪刀图标省略：sys.symbol.scissors 不存在（编译期资源校验报错，09 偏差记录）。
   */
  @Builder
  TraceAnchorCardBuilder(block: ContentBlock) {
    Text(this.traceLabel(block))
      .fontSize(12)
      .fontColor(this.theme.textTertiary)
      .width('100%')
      .padding({ top: 2, bottom: 6 })
  }

  /** 痕迹行文案：按块种类选「照片 / 录音」词条 + 取下日期（同语言环境） */
  private traceLabel(block: ContentBlock): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    const day = inkDay(new Date((block.removedAt ?? 0) * 1000), this.appLanguage);
    const audio = block.traceOf === (ContentBlockType.Audio as string);
    try {
      const pattern = context.resourceManager.getStringSync(
        (audio ? $r('app.string.s_16ed8e1cbb') : $r('app.string.s_39074a4234')).id);
      return pattern.replace('%s', day);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'trace label resource failed: %{public}s', JSON.stringify(err));
      return '';
    }
  }

  /** builder span 内容：一张录音锚点卡（编辑态 ✕ 可删；只读态（详情页）纯试听卡） */
  @Builder
  AudioAnchorCardBuilder(block: ContentBlock, armed: boolean) {
    AudioPlayerCard({
      block: block,
      armed: armed,
      onDelete: this.editable ? (blockId: string): void => {
        this.controller.deleteAudio(blockId);
      } : undefined
    })
  }

  /** builder span 内容：一张相纸锚点卡（编辑态：轻点弹功能条 / 双击秒换边 /
   *  长按开全屏；只读态（详情页）：四个编辑回调不给 = 纯预览卡，轻点即开全屏） */
  @Builder
  PhotoAnchorCardBuilder(block: ContentBlock, armed: boolean) {
    PhotoAnchorCard({
      block: block,
      armed: armed,
      onOpen: (blockId: string): void => {
        this.controller.requestOpenPhoto(blockId);
      },
      onTogglePosition: this.editable ? (blockId: string): void => {
        this.controller.requestTogglePosition(blockId);
      } : undefined,
      onToggleCover: this.editable ? (blockId: string): void => {
        this.controller.requestToggleCover(blockId);
      } : undefined,
      onRestyle: this.editable ? (blockId: string): void => {
        this.controller.requestRestyle(blockId);
      } : undefined,
      onDelete: this.editable ? (blockId: string): void => {
        this.controller.requestDelete(blockId);
      } : undefined
    })
  }

  build() {
    RichEditor({ controller: this.controller.editor })
      .placeholder(this.placeholderRes, {
        font: {
          size: RichTextAppearance.forTheme(this.theme).fontSize,
          family: this.theme.bodyFont.family
        },
        fontColor: this.theme.textTertiary
      })
      .caretColor(this.theme.accent)
      .backgroundColor(Color.Transparent)
      // 上下内边距：RESIZE_WITH_CARET 只保证光标点进视口，贴边会让末行留在键盘底下；
      // 左右显式 0 防回退组件默认缩进
      .padding({ left: 0, right: 0, top: 2, bottom: 4 })
      // 空文档时高度自适应可能塌陷，保底一行（行高 + 上下内边距）
      .constraintSize({ minHeight: RichTextAppearance.forTheme(this.theme).bodyLineHeight + 8 })
      .width('100%')
      // 只读展示（详情页）：自己不响应触摸，父级 Scroll 还能滚
      .hitTestBehavior(this.editable ? HitTestMode.Default : HitTestMode.None)
      .onReady((): void => {
        this.onReady();
      })
      .onSelectionChange((range: RichEditorRange): void => {
        this.controller.refreshFlags();
      })
      .onDidChange((): void => {
        this.controller.handleTextChanged(); // 影子台账单点 diff（2.8）
        this.controller.refreshFlags();
        this.controller.notifyTextChange();
      })
      // 退格两段式（R-RICH-05）：第一次选中照片拦下，第二次才删；范围删除放行后同步注册表
      .aboutToDelete((value: RichEditorDeleteValue): boolean =>
        this.controller.handleAboutToDelete(value))
      .onDeleteComplete((): void => {
        this.controller.handleDeleteComplete();
      })
      .editMenuOptions({
        onCreateMenu: (menuItems: Array<TextMenuItem>): Array<TextMenuItem> =>
          this.controller.createHighlightMenu(menuItems),
        onMenuItemClick: (menuItem: TextMenuItem, range: TextRange): boolean =>
          this.controller.onMenuClick(menuItem, range)
      })
  }
}
