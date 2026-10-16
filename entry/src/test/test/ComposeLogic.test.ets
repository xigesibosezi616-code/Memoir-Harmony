/**
 * 写日记页纯逻辑单测（10_BUILD_MANUAL.md 2.1）。
 * 对应 iOS `ComposeView` 的 hasContent / cleanedBlocks / totalCharCount、
 * 草稿恢复的日记本选择优先级（R-ENTRY-05）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { ContentBlock, ContentBlockType, PaperStyle, PhotoPosition } from '../../main/ets/models/ContentBlock';
import { nameKey } from '../../main/ets/models/Notebook';
import {
  composeCharCount,
  composeCleanedBlocks,
  composeHasContent,
  restoredNotebookSelection
} from '../../main/ets/data/ComposeLogic';

let idCounter = 0;
function makeId(): string {
  idCounter++;
  return `compose-test-${idCounter}`;
}

function textBlock(text: string): ContentBlock {
  return ContentBlock.makeText(makeId(), text);
}

export default function composeLogicTest() {
  describe('ComposeLogicTest', () => {
    // ---- hasContent（✓ 能不能点，R-ENTRY-01） ----

    it('emptyTextHasNoContent', 0, () => {
      expect(composeHasContent([textBlock('')])).assertFalse();
      expect(composeHasContent([textBlock('   \n  ')])).assertFalse();
      expect(composeHasContent([])).assertFalse();
    })

    it('nonWhitespaceTextHasContent', 0, () => {
      expect(composeHasContent([textBlock('今天')])).assertTrue();
      expect(composeHasContent([textBlock(' a ')])).assertTrue();
    })

    it('struckTextStillCountsAsContent', 0, () => {
      // 划掉的字也算「有内容」：那是在纸上留着的痕迹（iOS hasContent 不看样式）
      const block = textBlock('abc');
      expect(composeHasContent([block])).assertTrue();
    })

    it('photoBlockCountsAsContent', 0, () => {
      // 非文本块（照片 / 录音）都算有内容（iOS hasContent）
      const photo = ContentBlock.makePhoto(makeId(), 'p.jpg', undefined,
        PhotoPosition.Left, PaperStyle.Original);
      expect(composeHasContent([photo])).assertTrue();
      // 混着空文本块也一样
      expect(composeHasContent([textBlock('  '), photo])).assertTrue();
    })

    // ---- charCount（顶部字数，R-ENTRY-06） ----

    it('charCountSumsTextBlocks', 0, () => {
      expect(composeCharCount([])).assertEqual(0);
      expect(composeCharCount([textBlock('')])).assertEqual(0);
      expect(composeCharCount([textBlock('今天')])).assertEqual(2);
      expect(composeCharCount([textBlock('ab'), textBlock('cde')])).assertEqual(5);
    })

    // ---- cleanedBlocks（存盘前清理） ----

    it('cleanedBlocksKeepsNonEmptyTextAndDropsWhitespace', 0, () => {
      const kept = textBlock('正 文');
      const dropped = textBlock('  \n\t ');
      const cleaned = composeCleanedBlocks([dropped, kept], makeId);
      expect(cleaned.length).assertEqual(1);
      expect(cleaned[0].text).assertEqual('正 文');
    })

    it('cleanedBlocksAllEmptyFallsBackToSingleEmptyText', 0, () => {
      const cleaned = composeCleanedBlocks([textBlock(''), textBlock(' \n ')], makeId);
      expect(cleaned.length).assertEqual(1);
      expect(cleaned[0].type).assertEqual(ContentBlockType.Text);
      expect(cleaned[0].text).assertEqual('');
    })

    it('cleanedBlocksKeepsEmptyArrayFallback', 0, () => {
      const cleaned = composeCleanedBlocks([], makeId);
      expect(cleaned.length).assertEqual(1);
      expect(cleaned[0].text).assertEqual('');
    })

    // ---- 草稿恢复的日记本选择（R-ENTRY-05） ----

    it('draftNotebookWinsOverInitial', 0, () => {
      const restored = restoredNotebookSelection(['草稿本'], ['入口本']);
      expect(restored.length).assertEqual(1);
      expect(restored[0]).assertEqual('草稿本');
    })

    it('noDraftNotebookFallsBackToInitial', 0, () => {
      const restored = restoredNotebookSelection([], ['入口本']);
      expect(restored[0]).assertEqual('入口本');
    })

    it('multiNotebookDraftTreatedAsNone', 0, () => {
      // 草稿里存了多本的（单本规则之前存的）视同没选，不猜「主要是哪本」
      const restored = restoredNotebookSelection(['本一', '本二'], ['入口本']);
      expect(restored[0]).assertEqual('入口本');
    })

    it('bothEmptySelectsNothing', 0, () => {
      expect(restoredNotebookSelection([], []).length).assertEqual(0);
    })

    it('nameKeyFoldsCaseAndWidth', 0, () => {
      // R-ENTRY-10 撞名判定：忽略大小写与全半角
      expect(nameKey('Travel')).assertEqual(nameKey('travel'));
      expect(nameKey('Ｔｒａｖｅｌ')).assertEqual(nameKey('travel'));
      expect(nameKey(' 旅行 ')).assertEqual(nameKey('旅行'));
    })
  })
}
