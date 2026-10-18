/**
 * RichDocEditor（2.5b B1 隐形输入层）单元测试。
 * 纯逻辑：插入继承 / 删除锚点保护 / 样式整段替换 / 与 RichDocument 双向幂等。
 */
import { describe, it, expect } from '@ohos/hypium';
import { ContentBlock, ContentBlockType, PaperStyle, PhotoPosition, TextStyleRun } from '../../main/ets/models/ContentBlock';
import {
  RICH_ANCHOR,
  RichFormatFlags,
  anchoredBlocksOf,
  blocksWithEditorDocument,
  editorDocumentFromBlocks,
  photoInsertionPlan
} from '../../main/ets/models/RichDocument';
import { RichDocEditor, diffTextEdit } from '../../main/ets/models/RichDocEditor';

let idCounter: number = 0;
function nextId(): string {
  idCounter++;
  return `ID-${idCounter}`;
}

export default function richDocEditorTest(): void {
  describe('RichDocEditor', () => {
    it('empty_insert_plain', 0, () => {
      const doc = editorDocumentFromBlocks([ContentBlock.makeText('a', '')]);
      const editor = new RichDocEditor(doc);
      editor.insert(0, '你好');
      expect(editor.text).assertEqual('你好');
      expect(editor.spans.length).assertEqual(1);
      expect(editor.spans[0].flags.sameAs(new RichFormatFlags())).assertTrue();
    });

    it('insert_mid_inherits_left_flags', 0, () => {
      const run = new TextStyleRun(0, 3);
      run.bold = true;
      const block = ContentBlock.makeText('a', 'ABCDEF');
      block.styles = [run];
      const editor = new RichDocEditor(editorDocumentFromBlocks([block]));
      editor.insert(2, 'x'); // 光标在 B 和 C 之间（bold 区间内）→ 继承 bold
      expect(editor.text).assertEqual('ABxCDEF');
      expect(editor.flagsAt(2).bold).assertTrue();
      expect(editor.flagsAt(3).bold).assertTrue(); // x 本身
      expect(editor.flagsAt(5).bold).assertFalse(); // D 仍平文
    });

    it('insert_at_end_inherits_last_char', 0, () => {
      const run = new TextStyleRun(2, 2);
      run.italic = true;
      const block = ContentBlock.makeText('a', 'ABCD');
      block.styles = [run];
      const editor = new RichDocEditor(editorDocumentFromBlocks([block]));
      editor.insert(4, 'E'); // 文末插入 → 继承末字符 D 的 italic
      expect(editor.flagsAt(4).italic).assertTrue();
    });

    it('insert_after_anchor_is_plain_and_same_paragraph', 0, () => {
      const photo = ContentBlock.makePhoto('P1', 'p.jpg', undefined, PhotoPosition.Left, PaperStyle.Polaroid);
      const editor = new RichDocEditor(editorDocumentFromBlocks([photo, ContentBlock.makeText('t', '后文')]));
      editor.insert(1, '新'); // 锚点后插入：与锚点同段、平文
      expect(editor.text.startsWith(RICH_ANCHOR + '新后文')).assertTrue();
      expect(editor.flagsAt(1).sameAs(new RichFormatFlags())).assertTrue();
    });

    it('delete_single_span', 0, () => {
      const editor = new RichDocEditor(editorDocumentFromBlocks([ContentBlock.makeText('a', 'ABCDEF')]));
      expect(editor.deleteRange(2, 2)).assertEqual('ok');
      expect(editor.text).assertEqual('ABEF');
    });

    it('delete_across_style_spans_merges', 0, () => {
      const run = new TextStyleRun(0, 3);
      run.bold = true;
      const block = ContentBlock.makeText('a', 'ABCDEF');
      block.styles = [run];
      const editor = new RichDocEditor(editorDocumentFromBlocks([block]));
      editor.deleteRange(1, 4); // 删 BCDE → 剩 A F，两侧 bold/plain 不相邻不合并
      expect(editor.text).assertEqual('AF');
      expect(editor.spans.length).assertEqual(2);
      expect(editor.deleteRange(0, 2)).assertEqual('ok');
      expect(editor.text).assertEqual('');
    });

    it('delete_covering_anchor_rejected', 0, () => {
      const photo = ContentBlock.makePhoto('P1', 'p.jpg', undefined, PhotoPosition.Left, PaperStyle.Polaroid);
      const t1 = ContentBlock.makeText('t1', '前文');
      const t2 = ContentBlock.makeText('t2', '后文');
      const editor = new RichDocEditor(editorDocumentFromBlocks([t1, photo, t2]));
      const before = editor.text;
      expect(editor.deleteRange(2, 3)).assertEqual('anchor'); // 覆盖锚点字符
      expect(editor.text).assertEqual(before);
    });

    it('delete_adjacent_to_anchor_ok', 0, () => {
      const photo = ContentBlock.makePhoto('P1', 'p.jpg', undefined, PhotoPosition.Left, PaperStyle.Polaroid);
      const t1 = ContentBlock.makeText('t1', '前文');
      const t2 = ContentBlock.makeText('t2', '后文');
      const editor = new RichDocEditor(editorDocumentFromBlocks([t1, photo, t2]));
      expect(editor.deleteRange(2, 1)).assertEqual('ok'); // 只删锚点前换行
      expect(editor.text.includes(RICH_ANCHOR)).assertTrue();
    });

    it('delete_empty_and_clamped', 0, () => {
      const editor = new RichDocEditor(editorDocumentFromBlocks([ContentBlock.makeText('a', 'ABC')]));
      expect(editor.deleteRange(1, 0)).assertEqual('empty');
      expect(editor.deleteRange(2, 100)).assertEqual('ok'); // 越界钳到末尾
      expect(editor.text).assertEqual('AB');
    });

    it('apply_flags_splits_and_replaces', 0, () => {
      const editor = new RichDocEditor(editorDocumentFromBlocks([ContentBlock.makeText('a', 'ABCDEF')]));
      editor.applyFlags(1, 3, new RichFormatFlags(true)); // BCD 加粗
      expect(editor.flagsAt(0).bold).assertFalse();
      expect(editor.flagsAt(1).bold).assertTrue();
      expect(editor.flagsAt(3).bold).assertTrue();
      expect(editor.flagsAt(4).bold).assertFalse();
      expect(editor.spans.length).assertEqual(3);
    });

    it('apply_flags_skips_anchor', 0, () => {
      const photo = ContentBlock.makePhoto('P1', 'p.jpg', undefined, PhotoPosition.Left, PaperStyle.Polaroid);
      const editor = new RichDocEditor(editorDocumentFromBlocks([photo, ContentBlock.makeText('t', 'AB')]));
      const anchorOffset = editor.text.indexOf(RICH_ANCHOR);
      editor.applyFlags(0, editor.text.length, new RichFormatFlags(true));
      expect(editor.flagsAt(anchorOffset).sameAs(new RichFormatFlags())).assertTrue(); // 锚点本体不吃样式
      expect(editor.flagsAt(anchorOffset + 1).bold).assertTrue();
    });

    it('apply_flags_merges_adjacent', 0, () => {
      const editor = new RichDocEditor(editorDocumentFromBlocks([ContentBlock.makeText('a', 'ABCDEF')]));
      editor.applyFlags(0, 2, new RichFormatFlags(true));
      editor.applyFlags(2, 2, new RichFormatFlags(true)); // 与前一段同格式 → 合并
      expect(editor.spans.length).assertEqual(2); // ABCD 合一 + EF
    });

    it('flags_at_boundaries', 0, () => {
      const run = new TextStyleRun(0, 1);
      run.highlight = true;
      const block = ContentBlock.makeText('a', 'AB');
      block.styles = [run];
      const editor = new RichDocEditor(editorDocumentFromBlocks([block]));
      expect(editor.flagsAt(0).highlight).assertTrue();
      expect(editor.flagsAt(1).highlight).assertFalse();
      expect(editor.flagsAt(-5).highlight).assertTrue(); // 钳到 0
      expect(editor.flagsAt(99).highlight).assertFalse(); // 钳到末字符
    });

    it('roundtrip_blocks_editor_blocks_stable', 0, () => {
      const run = new TextStyleRun(0, 2);
      run.bold = true;
      const t1 = ContentBlock.makeText('T1', '第一段');
      t1.styles = [run];
      const photo = ContentBlock.makePhoto('P1', 'p.jpg', undefined, PhotoPosition.Right, PaperStyle.Polaroid);
      const t2 = ContentBlock.makeText('T2', '第二段');
      const blocks = [t1, photo, t2];
      const editor = new RichDocEditor(editorDocumentFromBlocks(blocks));
      editor.insert(4, '插入');
      editor.deleteRange(7, 2);
      editor.applyFlags(0, 2, new RichFormatFlags(false, false, false, true));
      const out = blocksWithEditorDocument(editor.document, anchoredBlocksOf(blocks), nextId);
      // 块流是不动点：out 再往返一次，块序/类型/文本/photo id 稳定
      // （editor.text 里锚点前同段的字，拆回后 fromBlocks 会把照片重新分段，text 不逐字相等是既有语义）
      const againDoc = editorDocumentFromBlocks(out);
      const out2 = blocksWithEditorDocument(againDoc, anchoredBlocksOf(out), nextId);
      expect(out2.length).assertEqual(out.length);
      for (let i = 0; i < out.length; i++) {
        expect(out2[i].type === out[i].type).assertTrue();
        expect(out2[i].text ?? '').assertEqual(out[i].text ?? '');
      }
      // 字符内容不丢：剥掉锚点与换行后的文字流一致
      const strip = (s: string): string => s.split(RICH_ANCHOR).join('').split('\n').join('');
      expect(strip(againDoc.text)).assertEqual(strip(editor.text));
      let anchorCount = 0;
      for (let i = 0; i < editor.text.length; i++) {
        if (editor.text[i] === RICH_ANCHOR) {
          anchorCount++;
        }
      }
      expect(anchorCount).assertEqual(1);
    });

    it('photo_insertion_plan_flow', 0, () => {
      const editor = new RichDocEditor(editorDocumentFromBlocks([ContentBlock.makeText('a', '一二三四五六')]));
      const plan = photoInsertionPlan(editor.text, 3); // 段中：先断段再插锚点
      expect(plan.needsNewlineBefore).assertTrue();
      if (plan.needsNewlineBefore) {
        editor.insert(plan.insertOffset, '\n');
      }
      editor.insertAnchor(plan.insertOffset + (plan.needsNewlineBefore ? 1 : 0), 'P1', ContentBlockType.Photo);
      expect(editor.text).assertEqual('一二三\n' + RICH_ANCHOR + '四五六');
      expect(editor.text.indexOf(RICH_ANCHOR)).assertEqual(4);
    });
  });

  describe('diffTextEdit', () => {
    it('same_text_is_none', 0, () => {
      const diff = diffTextEdit('ABC', 'ABC');
      expect(diff.kind).assertEqual('none');
    });

    it('pure_insert', 0, () => {
      const diff = diffTextEdit('ABC', 'ABxC');
      expect(diff.kind).assertEqual('insert');
      expect(diff.offset).assertEqual(2);
      expect(diff.value).assertEqual('x');
    });

    it('pure_delete', 0, () => {
      const diff = diffTextEdit('ABxC', 'ABC');
      expect(diff.kind).assertEqual('delete');
      expect(diff.offset).assertEqual(2);
      expect(diff.length).assertEqual(1);
    });

    it('insert_at_ends', 0, () => {
      const head = diffTextEdit('BC', 'ABC');
      expect(head.kind).assertEqual('insert');
      expect(head.offset).assertEqual(0);
      expect(head.value).assertEqual('A');
      const tail = diffTextEdit('AB', 'ABC');
      expect(tail.kind).assertEqual('insert');
      expect(tail.offset).assertEqual(2);
      expect(tail.value).assertEqual('C');
    });

    it('delete_to_empty_and_from_empty', 0, () => {
      const gone = diffTextEdit('AB', '');
      expect(gone.kind).assertEqual('delete');
      expect(gone.offset).assertEqual(0);
      expect(gone.length).assertEqual(2);
      const born = diffTextEdit('', 'AB');
      expect(born.kind).assertEqual('insert');
      expect(born.offset).assertEqual(0);
      expect(born.value).assertEqual('AB');
    });

    it('pinyin_composing_two_steps', 0, () => {
      // 拼音组合逐键：最小编辑即单点插入（保留公共前后缀）
      const step1 = diffTextEdit('ni好', 'nihao好');
      expect(step1.kind).assertEqual('insert');
      expect(step1.offset).assertEqual(2); // 「ni」之后插「hao」
      expect(step1.value).assertEqual('hao');
      const step2 = diffTextEdit('nihao好', 'ni好');
      expect(step2.kind).assertEqual('delete');
      expect(step2.offset).assertEqual(2); // 公共前缀「ni」后删「hao」（公共后缀「好」前）
      expect(step2.length).assertEqual(3);
    });

    it('replacement_is_complex', 0, () => {
      const diff = diffTextEdit('ABC', 'AXC');
      expect(diff.kind).assertEqual('complex');
    });

    it('edit_diff_matches_editor_ops', 0, () => {
      // diff 出的插入/删除直接喂 RichDocEditor，镜像文本应与隐形层最终一致
      const editor = new RichDocEditor(editorDocumentFromBlocks([ContentBlock.makeText('a', '正文内容')]));
      const prev = editor.text;
      const next = prev.substring(0, 2) + '插入' + prev.substring(2);
      const diff = diffTextEdit(prev, next);
      expect(diff.kind).assertEqual('insert');
      editor.insert(diff.offset, diff.value);
      expect(editor.text).assertEqual(next);
    });
  });
}
