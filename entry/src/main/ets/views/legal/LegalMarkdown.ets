/**
 * 法律文档用的极简 Markdown 解析（10_BUILD_MANUAL.md 1.5）。
 * 对应 iOS `Views/Legal/LegalMarkdown.swift`。
 *
 * 只支持这几种写法 —— 两份法律文档全部照此书写，翻译时不要引入其他语法：
 * `# 标题` / `## 小节` / `### 子节` / 普通段落 / `- 列表项` / 行内 `**加粗**`。
 *
 * 解析是纯函数（不碰 UI / 资源 / 文件），单测覆盖 LegalMarkdown.test.ets。
 * 块结构渲染由 LegalDocumentView 负责：解析结果按「文档 + 语言」缓存，滚动不掉帧。
 */

/** 块种类。与 iOS `LegalMarkdown.Block` 五个 case 一一对应 */
export enum LegalBlockKind {
  Title = 0,
  Heading = 1,
  Subheading = 2,
  Paragraph = 3,
  Bullet = 4
}

/** 行内片段：`**加粗**` 拆出来的最小单位（不加粗的整段也是一个 span） */
export class LegalInlineSpan {
  readonly text: string;
  readonly bold: boolean;

  constructor(text: string, bold: boolean) {
    this.text = text;
    this.bold = bold;
  }
}

/** 一个块：种类 + 行内片段序列 */
export class LegalBlock {
  readonly kind: LegalBlockKind;
  readonly spans: LegalInlineSpan[];

  constructor(kind: LegalBlockKind, spans: LegalInlineSpan[]) {
    this.kind = kind;
    this.spans = spans;
  }
}

/**
 * 解析整篇文档。
 *
 * ⚠️ 顺序要紧：判断前缀时 `###` 必须排在 `##` 前面，否则三级标题会被当成
 * 二级标题匹配掉，剩下一个 `# ` 留在正文里（iOS 同款坑）。
 * 段落可能跨行（md 里用换行排版但语义上是一段），遇到空行才收束。
 */
export function parseLegalMarkdown(markdown: string): LegalBlock[] {
  const blocks: LegalBlock[] = [];
  const paragraphBuffer: string[] = [];

  const flushParagraph = (): void => {
    if (paragraphBuffer.length === 0) {
      return;
    }
    blocks.push(new LegalBlock(LegalBlockKind.Paragraph, parseInlineBold(paragraphBuffer.join(' '))));
    paragraphBuffer.length = 0;
  };

  const lines: string[] = markdown.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line: string = lines[i].trim();
    if (line.length === 0) {
      flushParagraph();
    } else if (line.startsWith('### ')) {
      flushParagraph();
      blocks.push(new LegalBlock(LegalBlockKind.Subheading, plainSpans(line.substring(4))));
    } else if (line.startsWith('## ')) {
      flushParagraph();
      blocks.push(new LegalBlock(LegalBlockKind.Heading, plainSpans(line.substring(3))));
    } else if (line.startsWith('# ')) {
      flushParagraph();
      blocks.push(new LegalBlock(LegalBlockKind.Title, plainSpans(line.substring(2))));
    } else if (line.startsWith('- ')) {
      flushParagraph();
      blocks.push(new LegalBlock(LegalBlockKind.Bullet, parseInlineBold(line.substring(2))));
    } else {
      paragraphBuffer.push(line);
    }
  }
  flushParagraph();
  return blocks;
}

/** 标题类行不做行内解析（iOS 同款：heading 只取纯文本） */
function plainSpans(text: string): LegalInlineSpan[] {
  return [new LegalInlineSpan(text, false)];
}

/**
 * 行内样式：只处理 `**加粗**`。
 *
 * `**` 不成对时剩余部分当普通文本 —— 法律文本宁可少个加粗，
 * 也不能因为一个语法问题整段消失（iOS 同款兜底语义）。
 */
export function parseInlineBold(text: string): LegalInlineSpan[] {
  const parts: string[] = text.split('**');
  if (parts.length % 2 === 0) {
    // `**` 不成对（出现奇数次）：整段按纯文本，`**` 原样保留
    return [new LegalInlineSpan(text, false)];
  }
  const spans: LegalInlineSpan[] = [];
  for (let i = 0; i < parts.length; i++) {
    if (parts[i].length === 0) {
      continue;
    }
    spans.push(new LegalInlineSpan(parts[i], i % 2 === 1));
  }
  return spans;
}
