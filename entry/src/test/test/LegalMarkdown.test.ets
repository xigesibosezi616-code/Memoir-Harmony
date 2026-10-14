/**
 * 法律文档 Markdown 解析单测（10_BUILD_MANUAL.md 1.5）。
 * 对应 iOS `Views/Legal/LegalMarkdown.swift` 的解析语义。
 *
 * 覆盖：五种块结构（含「### 必须先于 ## 判断」的顺序坑）、
 * 段落跨行收束与空行 flush、行内加粗（成对拆分 / 不成对兜底 / 空片段跳过）。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  LegalBlockKind,
  parseLegalMarkdown,
  parseInlineBold
} from '../../main/ets/views/legal/LegalMarkdown';

export default function legalMarkdownTest() {
  describe('LegalMarkdownTest', () => {
    // ---- 块结构 ----

    it('parsesAllFiveBlockKinds', 0, () => {
      const md = [
        '# 标题',
        '',
        '## 小节',
        '',
        '### 子节',
        '',
        '普通段落。',
        '',
        '- 列表项',
        ''
      ].join('\n');
      const blocks = parseLegalMarkdown(md);
      expect(blocks.length).assertEqual(5);
      expect(blocks[0].kind).assertEqual(LegalBlockKind.Title);
      expect(blocks[0].spans[0].text).assertEqual('标题');
      expect(blocks[1].kind).assertEqual(LegalBlockKind.Heading);
      expect(blocks[1].spans[0].text).assertEqual('小节');
      expect(blocks[2].kind).assertEqual(LegalBlockKind.Subheading);
      expect(blocks[2].spans[0].text).assertEqual('子节');
      expect(blocks[3].kind).assertEqual(LegalBlockKind.Paragraph);
      expect(blocks[3].spans[0].text).assertEqual('普通段落。');
      expect(blocks[4].kind).assertEqual(LegalBlockKind.Bullet);
      expect(blocks[4].spans[0].text).assertEqual('列表项');
    })

    it('headingOrderMattersTripleBeforeDouble', 0, () => {
      // 🔴 判断前缀时 ### 必须排在 ## 前面，否则三级标题被二级匹配掉，
      // 剩下一个「# 」留在正文里（iOS 同款坑）
      const blocks = parseLegalMarkdown('### 三级标题');
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual(LegalBlockKind.Subheading);
      expect(blocks[0].spans[0].text).assertEqual('三级标题');
    })

    it('paragraphSpansMultipleLinesUntilBlank', 0, () => {
      const blocks = parseLegalMarkdown('第一行\n第二行\n\n下一段');
      expect(blocks.length).assertEqual(2);
      // 段内软换行按空格连接（md 语义），遇到空行才收束
      expect(blocks[0].spans[0].text).assertEqual('第一行 第二行');
      expect(blocks[1].spans[0].text).assertEqual('下一段');
    })

    it('trailingParagraphFlushesWithoutBlankLine', 0, () => {
      const blocks = parseLegalMarkdown('结尾没有空行');
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual(LegalBlockKind.Paragraph);
      expect(blocks[0].spans[0].text).assertEqual('结尾没有空行');
    })

    it('blankLineAfterHeadingFlushesEmptyParagraph', 0, () => {
      // 标题后直接空行：不产生空段落
      const blocks = parseLegalMarkdown('# 标题\n\n正文');
      expect(blocks.length).assertEqual(2);
      expect(blocks[0].kind).assertEqual(LegalBlockKind.Title);
      expect(blocks[1].kind).assertEqual(LegalBlockKind.Paragraph);
    })

    it('emptyInputYieldsNoBlocks', 0, () => {
      expect(parseLegalMarkdown('').length).assertEqual(0);
    })

    it('linesAreTrimmedBeforeMatching', 0, () => {
      const blocks = parseLegalMarkdown('  ## 带空白的小节  ');
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual(LegalBlockKind.Heading);
      expect(blocks[0].spans[0].text).assertEqual('带空白的小节');
    })

    // ---- 行内加粗 ----

    it('inlineBoldSplitsPairedMarkers', 0, () => {
      const spans = parseInlineBold('前缀**加粗**后缀');
      expect(spans.length).assertEqual(3);
      expect(spans[0].text).assertEqual('前缀');
      expect(spans[0].bold).assertFalse();
      expect(spans[1].text).assertEqual('加粗');
      expect(spans[1].bold).assertTrue();
      expect(spans[2].text).assertEqual('后缀');
      expect(spans[2].bold).assertFalse();
    })

    it('plainTextWithoutMarkersIsSingleSpan', 0, () => {
      const spans = parseInlineBold('普通文本');
      expect(spans.length).assertEqual(1);
      expect(spans[0].text).assertEqual('普通文本');
      expect(spans[0].bold).assertFalse();
    })

    it('unpairedMarkersFallBackToVerbatimText', 0, () => {
      // `**` 不成对：整段按纯文本、`**` 原样保留 ——
      // 法律文本宁可少个加粗，也不能因为一个语法问题整段消失（iOS 同款兜底）
      const spans = parseInlineBold('只有**一个标记');
      expect(spans.length).assertEqual(1);
      expect(spans[0].text).assertEqual('只有**一个标记');
      expect(spans[0].bold).assertFalse();
    })

    it('emptyPartsBetweenMarkersAreSkipped', 0, () => {
      // `****` 成对但中间为空：空片段不生成 span
      const spans = parseInlineBold('****');
      expect(spans.length).assertEqual(0);
    })

    it('leadingBoldParagraphFlowsThroughParser', 0, () => {
      const blocks = parseLegalMarkdown('**加粗开头**的段落');
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual(LegalBlockKind.Paragraph);
      expect(blocks[0].spans.length).assertEqual(2);
      expect(blocks[0].spans[0].text).assertEqual('加粗开头');
      expect(blocks[0].spans[0].bold).assertTrue();
      expect(blocks[0].spans[1].text).assertEqual('的段落');
      expect(blocks[0].spans[1].bold).assertFalse();
    })

    it('bulletParsesInlineBoldToo', 0, () => {
      const blocks = parseLegalMarkdown('- **重要**列表项');
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual(LegalBlockKind.Bullet);
      expect(blocks[0].spans.length).assertEqual(2);
      expect(blocks[0].spans[0].bold).assertTrue();
    })
  })
}
