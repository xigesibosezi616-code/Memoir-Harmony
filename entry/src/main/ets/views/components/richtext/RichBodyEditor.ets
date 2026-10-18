/**
 * 富文本正文编辑器（10_BUILD_MANUAL.md 2.5/2.6/2.7）。对应 iOS `Views/Components/RichText/RichTextView.swift`。
 *
 * - `RichBodyController`：包一层 RichEditorController —— 文档装载 / 读回、
 *   四盏格式灯（加粗 / 斜体 / 小标题 / 荧光笔）状态、切换（选区逐 span 应用、
 *   无选区改接下来打的字）、选中菜单「荧光笔 / 擦掉荧光笔」、
 *   照片 / 录音锚点注册表（2.6/2.7）
 * - `RichBodyEditor`：渲染组件。`editable=false`（详情页）只读展示同一套排版
 *
 * 灯的语义与 iOS 一致：选中区间内**全部**有该格式才算亮；toggle 翻转 = 全亮→关，否则→开；
 * 小标题整段生效（getParagraphs）；无选区改 typingStyle（接下来打的字）。
 *
 * 2.6/2.7 锚点（Q23 退化方案：builder span 整行卡片）：
 * - builder span 内容 getSpans 拿不到（官方 FAQ「使用RichEditor实现@用户名效果」），
 *   锚点 ↔ 块本体映射自维护：`photoBlocks` / `audioBlocks`（id → 本体，页面当
 *   anchored 侧表）+ `anchorOrder`（照片 + 录音在正文里的混合顺序）
 * - 锚点在 getSpans 里表现为无 value 的 span、占 1 个偏移（同图片 span），
 *   读回时按顺序与 anchorOrder 配对；个数对不上打诊断日志（真机 spike 重点）
 * - 退格两段式（R-RICH-05）：aboutToDelete 拦截 —— 第一次重建该卡带选中态并
 *   return false，第二次自行 deleteSpans（照片删锚点；录音连后随换行一起删，
 *   退到录音后那个换行也归录音管，iOS shouldChangeTextIn 同款）；
 *   范围删除连文字带锚点放行，onDeleteComplete 同步注册表并通知页面清文件
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import {
  AUDIO_LIMIT_PER_ENTRY,
  ContentBlock,
  ContentBlockType,
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

  /** 正文照片张数（上限 5，05 §3.6） */
  photoCount(): number {
    return this.photoBlocks.size;
  }

  /** 正文录音段数（上限 3，R-ENTRY-08） */
  audioCount(): number {
    return this.audioBlocks.size;
  }

  /** 全部锚点本体（照片 + 录音合并侧表，`blocksWithEditorDocument` 拆块用） */
  anchoredSideTable(): Map<string, ContentBlock> {
    const merged = new Map<string, ContentBlock>();
    this.photoBlocks.forEach((block: ContentBlock, id: string): void => {
      merged.set(id, block);
    });
    this.audioBlocks.forEach((block: ContentBlock, id: string): void => {
      merged.set(id, block);
    });
    return merged;
  }

  /**
   * 装载文档：清空 → 逐 span 注入（照片 / 录音锚点按侧表建 builder span）→ 重置接下来打的字。
   * `anchored`：照片 / 录音 / 痕迹块本体（id → block）；侧表里没有的锚点不进正文。
   */
  loadDocument(doc: RichEditorDocument,
    anchored: Map<string, ContentBlock> = new Map<string, ContentBlock>()): void {
    this.editor.deleteSpans({});
    this.photoBlocks.clear();
    this.audioBlocks.clear();
    this.anchorOrder = [];
    this.armedAnchorId = undefined;
    this.pendingRemovedIds = [];
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
    this.refreshFlags();
  }

  /**
   * 读回文档。照片 / 录音锚点 = getSpans 里的无 value span（builder span 内容拿不到，
   * 官方 FAQ 配方：按出现顺序与 anchorOrder 配对），个数对不上打诊断日志。
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
          const block = this.photoBlocks.get(blockId) ?? this.audioBlocks.get(blockId);
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
    doc.spans = mergeAdjacentRichSpans(spans);
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
    this.photoBlocks.set(block.id, block);
    this.deleteRangeSelf(offsets[index], offsets[index] + 1);
    this.editor.addBuilderSpan(this.anchorCardBuilderFactory(block, false), { offset: offsets[index] });
    this.armedAnchorId = undefined;
    this.refreshFlags();
  }

  /** 从正文删除指定照片（全屏菜单「删除照片」），出表 + 通知页面清文件 */
  deletePhoto(blockId: string): void {
    const index = this.anchorOrder.indexOf(blockId);
    if (index < 0) {
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
   */
  deleteAudio(blockId: string): void {
    const index = this.anchorOrder.indexOf(blockId);
    if (index < 0) {
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
   * 退格 / 删除拦截（R-RICH-05 两段式）：
   * - 删除范围恰好盖住一个锚点：第一次选中（重建该卡带高亮）并拦下，第二次才删
   * - 退到录音后随的换行也归录音管（iOS `shouldChangeTextIn` 同款）：进两段式，
   *   第二次连锚点带换行删 2 字符
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
    const offsets = this.anchorOffsets();
    const hits: number[] = [];
    for (let i = 0; i < offsets.length; i++) {
      if (offsets[i] >= start && offsets[i] < end) {
        hits.push(i);
      }
    }
    if (hits.length === 0) {
      // 退格删的恰好是录音锚点后随的换行：整个录音块进两段式
      if (value.direction === RichEditorDeleteDirection.BACKWARD && value.length === 1) {
        for (let i = 0; i < offsets.length; i++) {
          if (start === offsets[i] + 1 && this.audioBlocks.has(this.anchorOrder[i])) {
            const text = this.liveText();
            if (start < text.length && text.charCodeAt(start) === 0x0A) {
              const blockId = this.anchorOrder[i];
              if (this.armedAnchorId !== blockId) {
                this.armAnchorAt(i, offsets[i]);
                return false; // 第一次：选中，拦下
              }
              this.removeAnchorAt(i, this.audioDeleteEnd(text, offsets[i]));
              return false; // 第二次：连锚点带换行删
            }
          }
        }
      }
      return true; // 纯文字删除：照常
    }
    if (hits.length === 1 && start === offsets[hits[0]] && end === offsets[hits[0]] + 1) {
      const blockId = this.anchorOrder[hits[0]];
      const isAudio = this.audioBlocks.has(blockId);
      if (this.armedAnchorId !== blockId) {
        this.armAnchorAt(hits[0], offsets[hits[0]]);
        return false; // 第一次：选中，拦下
      }
      // 第二次：删（录音连后随换行一起）
      const text = this.liveText();
      this.removeAnchorAt(hits[0], isAudio
        ? this.audioDeleteEnd(text, offsets[hits[0]]) : offsets[hits[0]] + 1);
      return false;
    }
    // 范围删除含锚点：放行，完成回调里按 pending 列表出表
    for (const hit of hits) {
      this.pendingRemovedIds.push(this.anchorOrder[hit]);
    }
    return true;
  }

  /** 删除完成：放行的范围删除在这同步注册表 + 通知页面清文件 */
  handleDeleteComplete(): void {
    if (this.pendingRemovedIds.length === 0) {
      return;
    }
    for (const blockId of this.pendingRemovedIds) {
      const index = this.anchorOrder.indexOf(blockId);
      if (index >= 0) {
        this.anchorOrder.splice(index, 1);
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
    this.deleteRangeSelf(offset, offset + 1);
    this.editor.addBuilderSpan(factory(block, true), { offset: offset });
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
    this.deleteRangeSelf(start, end);
    this.armedAnchorId = undefined;
    if (isAudio) {
      this.onAudioRemoved(blockId);
    } else {
      this.onPhotoRemoved(blockId);
    }
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

  /** 文档装载路径：锚点 builder span 追加到当前末尾（照片 / 录音按块类型分发） */
  private appendAnchor(block: ContentBlock): void {
    const isAudio = block.type === ContentBlockType.Audio;
    const factory = isAudio ? this.audioCardBuilderFactory : this.anchorCardBuilderFactory;
    if (factory === undefined) {
      hilog.warn(DOMAIN, TAG, 'anchor card factory missing, block %{public}s dropped', block.id);
      return;
    }
    if (isAudio) {
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

  /** 逐 span 应用一盏灯：区间重叠的每个文字 span 各自带原格式翻转这一盏 */
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
      const flags = flagsFromTextStyle(this.appearance, span.textStyle);
      setFlagValue(flags, kind, turnOn);
      this.editor.updateSpanStyle({
        start: overlapStart,
        end: overlapEnd,
        textStyle: this.appearance.textStyleFor(flags)
      });
    }
  }

  // ---- 选中菜单「荧光笔 / 擦掉荧光笔」（R-RICH-08） ----

  /** 菜单项：全划过 →「擦掉荧光笔」，否则「荧光笔」；插在系统菜单最前 */
  createHighlightMenu(menuItems: Array<TextMenuItem>): Array<TextMenuItem> {
    const selection = this.editor.getSelection();
    const allHighlighted = this.selectionAllHas(RichFormatKind.Highlight,
      selection.selection[0], selection.selection[1]);
    const item: TextMenuItem = {
      content: allHighlighted ? $r('app.string.s_6a94ee7065') : $r('app.string.s_67a01a5a15'),
      icon: $r('sys.symbol.highlighter_line'),
      id: HIGHLIGHT_MENU_ID
    };
    return [item].concat(menuItems);
  }

  /** 菜单点击：自己那项吃掉（返回 true），其余交给系统 */
  onMenuClick(menuItem: TextMenuItem, range: TextRange): boolean {
    if (menuItem.id.equals(HIGHLIGHT_MENU_ID)) {
      const start = range.start ?? 0; // TextRange 字段可选，先归一（菜单点按必有选区）
      const end = range.end ?? start;
      const turnOn = !this.selectionAllHas(RichFormatKind.Highlight, start, end);
      this.applyFlagToRange(RichFormatKind.Highlight, turnOn, start, end);
      this.refreshFlags();
      return true;
    }
    return false;
  }

  /** 文本变化：读全文通知页面（bodyText / 字数 / ✓ 判定）——照片锚点不外漏 */
  notifyTextChange(): void {
    // getSpans 读法（与 liveText 同款，真机验证过锚点定位）：builder span 的 value
    // 为 undefined，整段跳过。不能用 toStyledString：builder span 在里面是**占位
    // 空格**（0x20，真机日志证实 split(U+FFFC) 剥离是空操作 → 纯照片正文「1 字」）。
    let text = '';
    for (const rawSpan of this.editor.getSpans({})) {
      const span = rawSpan as RichEditorTextSpanResult;
      if (span.value !== undefined) {
        text += span.value;
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
