/**
 * 富文本正文编辑器（10_BUILD_MANUAL.md 2.5）。对应 iOS `Views/Components/RichText/RichTextView.swift`。
 *
 * - `RichBodyController`：包一层 RichEditorController —— 文档装载 / 读回、
 *   四盏格式灯（加粗 / 斜体 / 小标题 / 荧光笔）状态、切换（选区逐 span 应用、
 *   无选区改接下来打的字）、选中菜单「荧光笔 / 擦掉荧光笔」
 * - `RichBodyEditor`：渲染组件。`editable=false`（详情页）只读展示同一套排版
 *
 * 灯的语义与 iOS 一致：选中区间内**全部**有该格式才算亮；toggle 翻转 = 全亮→关，否则→开；
 * 小标题整段生效（getParagraphs）；无选区改 typingStyle（接下来打的字）。
 */
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import {
  RichEditorDocument,
  RichFormatFlags,
  RichSpan,
  mergeAdjacentRichSpans
} from '../../../models/RichDocument';
import { RichTextAppearance, isTransparentColor } from './RichTextAppearance';

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

  private appearance: RichTextAppearance = new RichTextAppearance(14, 8, Color.Transparent,
    Color.Black, 'serif');

  /** 组件 aboutToAppear 时注入排版参数（素笺 17fp / 皮革 / 肯特 14fp 各一套） */
  setAppearance(appearance: RichTextAppearance): void {
    this.appearance = appearance;
  }

  /** 装载文档：清空 → 逐 span 注入样式 → 重置接下来打的字为基础样式 */
  loadDocument(doc: RichEditorDocument): void {
    this.editor.deleteSpans({});
    for (const span of doc.spans) {
      if (span.anchorBlockId !== undefined) {
        // 2.5 页面只装纯文本文档；锚点由 2.6（照片）/2.7（录音）接自定义块时处理
        continue;
      }
      this.editor.addTextSpan(span.text, { style: this.appearance.textStyleFor(span.flags) });
    }
    this.editor.setTypingStyle(this.appearance.baseTextStyle());
    this.refreshFlags();
  }

  /**
   * 读回文档。**限制**：RichEditor 样式装不下墨迹时刻（writtenAt / struckAt），
   * 读回恒为空 —— 2.5 页面只有纯文本，2.8 接墨迹交互时在调用侧把锚点 / 墨迹合并回去。
   */
  currentDocument(): RichEditorDocument {
    const doc = new RichEditorDocument();
    const spans: RichSpan[] = [];
    for (const raw of this.editor.getSpans({})) {
      // getSpans 返回 Image|Text 联合：图片 span 没有 value / textStyle（运行时 undefined）
      const span = raw as RichEditorTextSpanResult;
      if (span.value === undefined || span.textStyle === undefined) {
        continue;
      }
      spans.push(new RichSpan(span.value, flagsFromTextStyle(this.appearance, span.textStyle)));
    }
    doc.spans = mergeAdjacentRichSpans(spans);
    let text = '';
    for (const span of doc.spans) {
      text += span.text;
    }
    doc.text = text;
    return doc;
  }

  /** 光标处（光标左一字符）的格式组；文档开头 = 全灭 */
  cursorFlags(): RichFormatFlags {
    const selection = this.editor.getSelection();
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

  /** 文本变化：读全文通知页面（bodyText / 字数 / ✓ 判定） */
  notifyTextChange(): void {
    this.onTextChange(this.editor.toStyledString({}).getString());
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
      .editMenuOptions({
        onCreateMenu: (menuItems: Array<TextMenuItem>): Array<TextMenuItem> =>
          this.controller.createHighlightMenu(menuItems),
        onMenuItemClick: (menuItem: TextMenuItem, range: TextRange): boolean =>
          this.controller.onMenuClick(menuItem, range)
      })
  }
}
