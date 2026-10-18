/**
 * 墨迹台账单测（10_BUILD_MANUAL.md 2.8「墨迹会干」）。
 *
 * 覆盖：InkLedger.fromDocument 逐字符对齐（锚点占 1 字符）、
 * syncText 单点 diff（插入记 sessionSec / 删除 splice / 复杂先删后插）、
 * containsDry（锚点跳过、无 base 不干）、hasWetStrike（划线自己的 24h）、
 * planInkRespectingDelete 全分支（湿删 / 干划 / 换行留 / 锚点留 / 已划留 /
 * 新稿全删）、overlayInkOntoSpans（台账边界切 span、锚点原样过）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { ContentBlock, ContentBlockType, Ink } from '../../main/ets/models/ContentBlock';
import {
  RICH_ANCHOR,
  RichFormatFlags,
  RichSpan,
  RichEditorDocument
} from '../../main/ets/models/RichDocument';
import {
  InkDeleteOpKind,
  InkLedger,
  overlayInkOntoSpans,
  planInkRespectingDelete
} from '../../main/ets/models/InkLedger';

/** 挂在 now 附近的一个时刻（秒） */
const NOW = 2000000000;
const BASE = NOW - 60; // 日记写下时刻：一分钟前 → 没写时间戳的字还湿着
const SESSION = NOW - 30;
const DAY = Ink.dryingInterval;

/** 文本 span（无墨迹） */
function textSpan(text: string): RichSpan {
  return new RichSpan(text, new RichFormatFlags());
}

/** 文本 span + 墨迹 */
function inkSpan(text: string, writtenAt?: number, struckAt?: number): RichSpan {
  return new RichSpan(text, new RichFormatFlags(false, false, false, false, writtenAt, struckAt));
}

/** 锚点 span（占 1 字符） */
function anchorSpan(blockType: ContentBlockType): RichSpan {
  return new RichSpan(RICH_ANCHOR, new RichFormatFlags(), 'a1', blockType);
}

/** 'ab'/'abc' 文档：各字带已知时刻（无锚点，纯文本） */
function mixedDoc(text: string): RichEditorDocument {
  const doc = new RichEditorDocument();
  if (text === 'ab') {
    doc.spans = [inkSpan('a', 100), inkSpan('b', 100)];
  } else {
    doc.spans = [inkSpan('a', 100), inkSpan('b', 200), inkSpan('c', 300)];
  }
  doc.text = text;
  return doc;
}

export default function inkLedgerTest() {
  describe('InkLedgerTest', () => {
    // ---- fromDocument 逐字符对齐 ----

    it('fromDocumentAlignsPerCharacterIncludingAnchors', 0, () => {
      const doc = new RichEditorDocument();
      doc.spans = [
        inkSpan('ab', 10, undefined),
        anchorSpan(ContentBlockType.Photo),
        inkSpan('cd', undefined, 20)
      ];
      doc.text = 'ab' + RICH_ANCHOR + 'cd';
      const ledger = InkLedger.fromDocument(doc);
      expect(ledger.length).assertEqual(5);
      expect(ledger.writtenAt[0]).assertEqual(10);
      expect(ledger.writtenAt[1]).assertEqual(10);
      expect(ledger.writtenAt[2]).assertUndefined(); // 锚点占位：干湿块级另算（addedAt）
      expect(ledger.writtenAt[3]).assertUndefined();
      expect(ledger.struckAt[3]).assertEqual(20);
      expect(ledger.struckAt[4]).assertEqual(20);
    })

    // ---- syncText（onDidChange 单点 diff 路径） ----

    it('syncTextInsertStampsSessionSec', 0, () => {
      const ledger = InkLedger.fromDocument(mixedDoc('ab'));
      ledger.syncText('ab', 'axb', SESSION);
      expect(ledger.writtenAt[1]).assertEqual(SESSION);
      expect(ledger.struckAt[1]).assertUndefined();
      expect(ledger.writtenAt[2]).assertEqual(ledger.writtenAt[0]); // 'b' 顺移，墨迹跟着走
    })

    it('syncTextInsertWithoutSessionKeepsUndefined', 0, () => {
      const ledger = InkLedger.fromDocument(mixedDoc('ab'));
      ledger.syncText('ab', 'axb', undefined);
      expect(ledger.writtenAt[1]).assertUndefined();
    })

    it('syncTextDeleteSplicesBothArrays', 0, () => {
      const ledger = InkLedger.fromDocument(mixedDoc('abc'));
      ledger.syncText('abc', 'ac', SESSION);
      expect(ledger.length).assertEqual(2);
      expect(ledger.writtenAt[1]).assertEqual(300); // 'c' 的墨迹没被 'b' 的覆盖
    })

    it('syncTextReplaceDeletesThenInserts', 0, () => {
      const ledger = InkLedger.fromDocument(mixedDoc('abc'));
      ledger.syncText('abc', 'aXc', SESSION); // complex：同点先删后插
      expect(ledger.length).assertEqual(3);
      expect(ledger.writtenAt[1]).assertEqual(SESSION);
      expect(ledger.writtenAt[2]).assertEqual(300);
    })

    it('syncTextNoChangeIsNoop', 0, () => {
      const ledger = InkLedger.fromDocument(mixedDoc('ab'));
      ledger.syncText('ab', 'ab', SESSION);
      expect(ledger.length).assertEqual(2);
      expect(ledger.writtenAt[0]).assertEqual(100);
    })

    // ---- containsDry / hasWetStrike ----

    it('containsDryDetectsOldInk', 0, () => {
      const ledger = new InkLedger();
      ledger.writtenAt = [BASE, NOW - DAY, undefined];
      expect(ledger.containsDry('abc', 0, 3, BASE, NOW)).assertTrue(); // 字 1 干
      expect(ledger.containsDry('abc', 0, 1, BASE, NOW)).assertFalse(); // 只看字 0：湿
      expect(ledger.containsDry('abc', 2, 3, BASE, NOW)).assertFalse(); // 没时间戳：按 base，湿
    })

    it('containsDrySkipsAnchors', 0, () => {
      const ledger = new InkLedger();
      ledger.writtenAt = [NOW - DAY, undefined, NOW - DAY];
      // 中间是锚点占位（干不了）；旁边两个都干
      const text = 'a' + RICH_ANCHOR + 'c';
      expect(ledger.containsDry(text, 1, 2, BASE, NOW)).assertFalse();
      expect(ledger.containsDry(text, 0, 1, BASE, NOW)).assertTrue();
    })

    it('containsDryWithoutBaseNeverDry', 0, () => {
      const ledger = new InkLedger();
      ledger.writtenAt = [undefined, undefined];
      expect(ledger.containsDry('ab', 0, 2, undefined, NOW)).assertFalse();
    })

    it('hasWetStrikeOnlyWithin24h', 0, () => {
      const ledger = new InkLedger();
      ledger.struckAt = [NOW - DAY, NOW - 1, undefined];
      expect(ledger.hasWetStrike(0, 3, NOW)).assertTrue(); // 字 1 湿划线
      expect(ledger.hasWetStrike(0, 1, NOW)).assertFalse(); // 字 0 划线已干
      expect(ledger.hasWetStrike(2, 3, NOW)).assertFalse();
    })

    // ---- planInkRespectingDelete（R-INK-02） ----

    it('planWetCharsDeleteDryCharsStrike', 0, () => {
      const ledger = new InkLedger();
      ledger.writtenAt = [SESSION, NOW - DAY]; // 湿 / 干
      ledger.struckAt = [undefined, undefined];
      const ops = planInkRespectingDelete('ab', ledger, 0, 2, BASE, NOW);
      expect(ops[0].kind).assertEqual(InkDeleteOpKind.Delete);
      expect(ops[0].offset).assertEqual(0);
      expect(ops[1].kind).assertEqual(InkDeleteOpKind.Strike);
      expect(ops[1].offset).assertEqual(1);
    })

    it('planKeepsNewlinesAnchorsAndStruck', 0, () => {
      const text = 'a\n' + RICH_ANCHOR + 'bc'; // a 干、\n 干、锚点、b 干已划、c 湿
      const ledger = new InkLedger();
      ledger.writtenAt = [NOW - DAY, NOW - DAY, NOW - DAY, NOW - DAY, SESSION];
      ledger.struckAt = [undefined, undefined, undefined, NOW - 1, undefined];
      const ops = planInkRespectingDelete(text, ledger, 0, text.length, BASE, NOW);
      expect(ops[0].kind).assertEqual(InkDeleteOpKind.Strike); // a：干 → 划
      expect(ops[1].kind).assertEqual(InkDeleteOpKind.Keep); // \n：留
      expect(ops[2].kind).assertEqual(InkDeleteOpKind.Keep); // 锚点：块级另算
      expect(ops[3].kind).assertEqual(InkDeleteOpKind.Keep); // 已划过的不再重划
      expect(ops[4].kind).assertEqual(InkDeleteOpKind.Delete); // c：湿 → 删
    })

    it('planWithoutBaseDeletesEverything', 0, () => {
      const ledger = new InkLedger();
      ledger.writtenAt = [undefined, undefined];
      const ops = planInkRespectingDelete('ab', ledger, 0, 2, undefined, NOW);
      expect(ops[0].kind).assertEqual(InkDeleteOpKind.Delete);
      expect(ops[1].kind).assertEqual(InkDeleteOpKind.Delete);
    })

    it('planClampsToTextAndLedgerBounds', 0, () => {
      const ledger = new InkLedger();
      ledger.writtenAt = [NOW - DAY];
      const ops = planInkRespectingDelete('ab', ledger, -5, 99, BASE, NOW);
      expect(ops.length).assertEqual(1);
      expect(ops[0].kind).assertEqual(InkDeleteOpKind.Strike);
    })

    // ---- overlayInkOntoSpans（Q24 读回侧） ----

    it('overlaySplitsSpanAtInkBoundaries', 0, () => {
      const ledger = new InkLedger();
      ledger.writtenAt = [100, 100, 200, 200];
      ledger.struckAt = [undefined, 5, undefined, undefined];
      const out = overlayInkOntoSpans([textSpan('abcd')], ledger);
      expect(out.length).assertEqual(3);
      expect(out[0].text).assertEqual('a');
      expect(out[0].flags.writtenAt).assertEqual(100);
      expect(out[0].flags.struckAt).assertUndefined();
      expect(out[1].text).assertEqual('b');
      expect(out[1].flags.struckAt).assertEqual(5);
      expect(out[2].text).assertEqual('cd');
      expect(out[2].flags.writtenAt).assertEqual(200);
    })

    it('overlayKeepsAnchorSpansAndVisualFlags', 0, () => {
      const ledger = new InkLedger();
      ledger.writtenAt = [undefined, 300, 300];
      ledger.struckAt = [undefined, undefined, undefined];
      const bold = new RichFormatFlags(true, false, false, false);
      const out = overlayInkOntoSpans(
        [anchorSpan(ContentBlockType.Photo), new RichSpan('xy', bold)], ledger);
      expect(out.length).assertEqual(2);
      expect(out[0].anchorBlockId).assertEqual('a1');
      expect(out[1].text).assertEqual('xy');
      expect(out[1].flags.bold).assertTrue();
      expect(out[1].flags.writtenAt).assertEqual(300);
    })
  })
}
