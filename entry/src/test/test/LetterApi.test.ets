/**
 * 投信 / 补领的 API 形状单测（10_BUILD_MANUAL.md 5.3；02_BACKEND_API L216-277）。
 * - letterRequestBody：mood / dominantMood / language 空串省略；date 毫秒 → ISO8601
 * - parseLetterResponse：body / fromCharacter 必填
 * - parseLetterListResponse：letters 数组逐条校验，generatedAt 必须 ISO8601
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  LetterRequest,
  LetterRequestEntry,
  LetterResponse,
  NotebookItem,
  parseLetterResponse,
  parseLetterListResponse,
  letterRequestBody,
  PenPalLetterRequest,
  parsePenPalsResponse,
  penPalLetterRequestBody,
  parsePenPalLetterResponse
} from '../../main/ets/models/Api';

export default function letterApiTest() {
  describe('LetterApiTest', () => {
    // ---- POST /letter 请求体 ----

    it('letterRequestBodyOmitsEmptyOptionals', 0, () => {
      const entries = [
        new LetterRequestEntry('标题', '正文', 1_700_000_000_000, ''),
        new LetterRequestEntry('', '无题的', 1_700_000_086_400, 'calm')
      ];
      const request = new LetterRequest(entries, 'weekly', '', '青鸟', '', '', []);
      const body = letterRequestBody(request);
      const list = body['entries'] as Record<string, Object>[];
      expect(list.length).assertEqual(2);
      expect(list[0]['mood']).assertUndefined();
      expect(list[1]['mood']).assertEqual('calm');
      expect(list[1]['title']).assertEqual('');
      expect(body['dominantMood']).assertUndefined();
      expect(body['language']).assertUndefined();
      expect(body['triggerKind']).assertEqual('weekly');
      expect(body['penPalName']).assertEqual('青鸟');
      // clientLetterId 空串省略（U01：非幂等重试时服务端按新信算）
      expect(body['clientLetterId']).assertUndefined();
      // R-NOTEBOOK-03：没有手记也带空数组（不带字段 = 老客户端，服务端不改手记）
      const emptyNotebook = body['notebook'] as Object[];
      expect(Array.isArray(emptyNotebook)).assertTrue();
      expect(emptyNotebook.length).assertEqual(0);
      // date 毫秒 → ISO8601
      expect(list[0]['date']).assertEqual(new Date(1_700_000_000_000).toISOString());
    })

    it('letterRequestBodyKeepsNonEmptyOptionals', 0, () => {
      const entries = [new LetterRequestEntry('t', 'c', 0, 'joy')];
      const request = new LetterRequest(entries, 'weekly', 'joy', '青鸟', 'zh-Hans',
        '8C9F1A2B-3D4E-4F5A-9B8C-7D6E5F4A3B2C', []);
      const body = letterRequestBody(request);
      expect(body['dominantMood']).assertEqual('joy');
      expect(body['language']).assertEqual('zh-Hans');
      // clientLetterId 带上（U01：重发不重复扣邮票靠它认出是同一封）
      expect(body['clientLetterId']).assertEqual('8C9F1A2B-3D4E-4F5A-9B8C-7D6E5F4A3B2C');
    })

    it('letterRequestBodySerializesNotebookItems', 0, () => {
      // R-NOTEBOOK-03：画像在前大事在后，date = touched（毫秒 → ISO8601）
      const notebook: NotebookItem[] = [
        new NotebookItem('8C9F1A2B-3D4E-4F5A-9B8C-7D6E5F4A3B2C', 'profile',
          '画像文本', 1_700_000_000_000),
        new NotebookItem('7B8C9D0E-1F2A-3B4C-8D9E-0F1A2B3C4D5E', 'recent',
          '大事文本', 1_700_000_086_400)
      ];
      const entries = [new LetterRequestEntry('t', 'c', 0, '')];
      const request = new LetterRequest(entries, 'weekly', '', '青鸟', '', '', notebook);
      const body = letterRequestBody(request);
      const items = body['notebook'] as Record<string, Object>[];
      expect(items.length).assertEqual(2);
      expect(items[0]['id']).assertEqual('8C9F1A2B-3D4E-4F5A-9B8C-7D6E5F4A3B2C');
      expect(items[0]['kind']).assertEqual('profile');
      expect(items[0]['text']).assertEqual('画像文本');
      expect(items[0]['date']).assertEqual(new Date(1_700_000_000_000).toISOString());
      expect(items[1]['kind']).assertEqual('recent');
      expect(items[1]['date']).assertEqual(new Date(1_700_000_086_400).toISOString());
    })

    // ---- POST /letter 成功响应 ----

    it('parseLetterResponseReadsBodyAndCharacter', 0, () => {
      const r = parseLetterResponse('{"body":"回信","fromCharacter":"青鸟"}');
      expect(r instanceof LetterResponse).assertTrue();
      expect(r.body).assertEqual('回信');
      expect(r.fromCharacter).assertEqual('青鸟');
      // 老回执不带 notebook → null（R-NOTEBOOK-04）
      expect(r.notebook).assertNull();
    })

    it('parseLetterResponseReadsNotebookEdits', 0, () => {
      // R-NOTEBOOK-04：空串 profile → undefined；id 非 UUID 的 update / remove 丢掉
      const raw = '{"body":"回信","fromCharacter":"青鸟","notebook":{' +
        '"profile":"","add":["新大事",""],' +
        '"update":[' +
        '{"id":"8C9F1A2B-3D4E-4F5A-9B8C-7D6E5F4A3B2C","text":"改写后"},' +
        '{"id":"not-a-uuid","text":"丢掉"},' +
        '{"text":"缺 id 也丢"}],' +
        '"remove":["7B8C9D0E-1F2A-3B4C-8D9E-0F1A2B3C4D5E","not-a-uuid"]}}';
      const r = parseLetterResponse(raw);
      const edits = r.notebook;
      expect(edits !== null).assertTrue();
      if (edits === null) {
        return;
      }
      expect(edits.profile).assertUndefined();
      expect(edits.add.length).assertEqual(1);
      expect(edits.add[0]).assertEqual('新大事');
      expect(edits.update.length).assertEqual(1);
      expect(edits.update[0].id).assertEqual('8C9F1A2B-3D4E-4F5A-9B8C-7D6E5F4A3B2C');
      expect(edits.update[0].text).assertEqual('改写后');
      expect(edits.remove.length).assertEqual(1);
      expect(edits.remove[0]).assertEqual('7B8C9D0E-1F2A-3B4C-8D9E-0F1A2B3C4D5E');
      expect(edits.isEmpty()).assertFalse();
    })

    it('parseLetterResponseReadsProfileRewrite', 0, () => {
      const raw = '{"body":"回信","fromCharacter":"青鸟","notebook":' +
        '{"profile":"重写后的画像","add":[],"update":[],"remove":[]}}';
      const r = parseLetterResponse(raw);
      const edits = r.notebook;
      expect(edits !== null).assertTrue();
      if (edits === null) {
        return;
      }
      expect(edits.profile).assertEqual('重写后的画像');
      // 只有画像改、没有别的 → 不算空改法
      expect(edits.isEmpty()).assertFalse();
    })

    it('parseLetterResponseTreatsEmptyNotebookAsEmptyEdits', 0, () => {
      const r = parseLetterResponse('{"body":"回信","fromCharacter":"青鸟",' +
        '"notebook":{"add":[],"update":[],"remove":[]}}');
      const edits = r.notebook;
      expect(edits !== null).assertTrue();
      if (edits !== null) {
        // 字段在但全空 → 空改法（调用方 isEmpty 跳过）
        expect(edits.isEmpty()).assertTrue();
      }
    })

    it('parseLetterResponseRejectsBadShapes', 0, () => {
      const bad: string[] = [
        '{"body":"回信"}',
        '{"fromCharacter":"青鸟"}',
        '[]',
        'not json'
      ];
      for (const raw of bad) {
        let caught = false;
        try {
          parseLetterResponse(raw);
        } catch (e) {
          caught = true;
        }
        expect(caught).assertTrue();
      }
    })

    // ---- GET /letters 列表（补领用）----

    it('parseLetterListResponseNormalizesGeneratedAt', 0, () => {
      const raw = '{"letters":[' +
        '{"body":"回信一","fromCharacter":"青鸟","generatedAt":"2026-10-20T08:00:00.000Z"},' +
        '{"body":"回信二","fromCharacter":"流萤","generatedAt":"2026-10-21T09:30:00.000Z"}]}';
      const list = parseLetterListResponse(raw);
      expect(list.length).assertEqual(2);
      expect(list[0].body).assertEqual('回信一');
      expect(list[0].fromCharacter).assertEqual('青鸟');
      expect(list[0].generatedAtMs).assertEqual(Date.parse('2026-10-20T08:00:00.000Z'));
      expect(list[1].fromCharacter).assertEqual('流萤');
    })

    it('parseLetterListResponseRejectsBadGeneratedAt', 0, () => {
      // generatedAt 缺 / 不是 ISO8601 → 整个折掉（补领静默失败，下次再领）
      const bad: string[] = [
        '{"letters":[{"body":"b","fromCharacter":"f"}]}',
        '{"letters":[{"body":"b","fromCharacter":"f","generatedAt":"not-a-date"}]}',
        '{"letters":"x"}',
        '{}'
      ];
      for (const raw of bad) {
        let caught = false;
        try {
          parseLetterListResponse(raw);
        } catch (e) {
          caught = true;
        }
        expect(caught).assertTrue();
      }
    })

    // ---- U01：GET /letters 每封多 clientLetterId / penPalId / translation / danger ----

    it('parseLetterListResponseReadsWorldPenPalFields', 0, () => {
      const raw = '{"letters":[' +
        '{"body":"原文","fromCharacter":"朴","generatedAt":"2026-10-20T08:00:00.000Z",' +
        '"clientLetterId":"8C9F1A2B-3D4E-4F5A-9B8C-7D6E5F4A3B2C","penPalId":"park",' +
        '"translation":"译文","danger":true},' +
        '{"body":"老回信","fromCharacter":"青鸟","generatedAt":"2026-10-19T08:00:00.000Z"}]}';
      const list = parseLetterListResponse(raw);
      expect(list.length).assertEqual(2);
      expect(list[0].clientLetterId).assertEqual('8C9F1A2B-3D4E-4F5A-9B8C-7D6E5F4A3B2C');
      expect(list[0].penPalId).assertEqual('park');
      expect(list[0].translation).assertEqual('译文');
      expect(list[0].danger).assertTrue();
      // 老信：全空 / false
      expect(list[1].clientLetterId).assertEqual('');
      expect(list[1].penPalId).assertEqual('');
      expect(list[1].translation).assertEqual('');
      expect(list[1].danger).assertFalse();
    })

    // ---- U01：GET /penpals ----

    it('parsePenPalsResponseReadsAvailableIds', 0, () => {
      const ids = parsePenPalsResponse('{"available":["mcrae","amano","park"]}');
      expect(ids.length).assertEqual(3);
      expect(ids[0]).assertEqual('mcrae');
      expect(ids[2]).assertEqual('park');
    })

    it('parsePenPalsResponseDropsBadEntries', 0, () => {
      // 非 string / 空串滤掉；available 缺失 / 非数组折错
      const ids = parsePenPalsResponse('{"available":["mcrae", "", 3, null, "park"]}');
      expect(ids.length).assertEqual(2);
      expect(ids[1]).assertEqual('park');
      const bad: string[] = ['{}', '{"available":"x"}', '[]', 'not json'];
      for (const raw of bad) {
        let caught = false;
        try {
          parsePenPalsResponse(raw);
        } catch (e) {
          caught = true;
        }
        expect(caught).assertTrue();
      }
    })

    // ---- U01：POST /penpal-letter 请求体 ----

    it('penPalLetterRequestBodyMatchesContract', 0, () => {
      const entries = [
        new LetterRequestEntry('标题', '正文', 1_700_000_000_000, ''),
        new LetterRequestEntry('', '无题的', 1_700_000_086_400, 'calm')
      ];
      const request = new PenPalLetterRequest(
        '8C9F1A2B-3D4E-4F5A-9B8C-7D6E5F4A3B2C', 'park', entries, '', 'zh-Hans', []);
      const body = penPalLetterRequestBody(request);
      expect(body['clientLetterId']).assertEqual('8C9F1A2B-3D4E-4F5A-9B8C-7D6E5F4A3B2C');
      expect(body['penPalId']).assertEqual('park');
      expect(body['readerLanguage']).assertEqual('zh-Hans');
      // dominantMood 空串省略；非空带上
      expect(body['dominantMood']).assertUndefined();
      // B3：没有手记也带空数组（R-NOTEBOOK-03：不带 = 老客户端）
      const notebook = body['notebook'] as Object[];
      expect(Array.isArray(notebook)).assertTrue();
      expect(notebook.length).assertEqual(0);
      const list = body['entries'] as Record<string, Object>[];
      expect(list.length).assertEqual(2);
      expect(list[0]['mood']).assertUndefined();
      expect(list[1]['mood']).assertEqual('calm');
      expect(list[0]['date']).assertEqual(new Date(1_700_000_000_000).toISOString());
    })

    it('penPalLetterRequestBodyKeepsDominantMood', 0, () => {
      const entries = [new LetterRequestEntry('t', 'c', 0, 'joy')];
      const request = new PenPalLetterRequest('ID', 'mcrae', entries, 'joy', 'en', []);
      const body = penPalLetterRequestBody(request);
      expect(body['dominantMood']).assertEqual('joy');
    })

    it('penPalLetterRequestBodySerializesNotebook', 0, () => {
      // B3：世界笔友的手记随信带上（R-NOTEBOOK-03）
      const notebook: NotebookItem[] = [
        new NotebookItem('8C9F1A2B-3D4E-4F5A-9B8C-7D6E5F4A3B2C', 'profile',
          '画像', 1_700_000_000_000),
        new NotebookItem('7B8C9D0E-1F2A-3B4C-8D9E-0F1A2B3C4D5E', 'recent',
          '大事', 1_700_000_086_400)
      ];
      const entries = [new LetterRequestEntry('t', 'c', 0, '')];
      const request = new PenPalLetterRequest('ID', 'mcrae', entries, '', 'zh-Hans', notebook);
      const body = penPalLetterRequestBody(request);
      const items = body['notebook'] as Record<string, Object>[];
      expect(items.length).assertEqual(2);
      expect(items[0]['kind']).assertEqual('profile');
      expect(items[0]['text']).assertEqual('画像');
      expect(items[0]['date']).assertEqual(new Date(1_700_000_000_000).toISOString());
      expect(items[1]['kind']).assertEqual('recent');
    })

    // ---- U01：POST /penpal-letter 成功响应 ----

    it('parsePenPalLetterResponseReadsDraft', 0, () => {
      const raw = '{"letter":"原文","translation":"译文","danger":false,' +
        '"postage":1,"generatedAt":"2026-10-20T08:00:00.000Z","balance":18}';
      const r = parsePenPalLetterResponse(raw);
      expect(r.letter).assertEqual('原文');
      expect(r.translation).assertEqual('译文');
      expect(r.danger).assertFalse();
      expect(r.postage).assertEqual(1);
      expect(r.generatedAtMs).assertEqual(Date.parse('2026-10-20T08:00:00.000Z'));
      expect(r.balance).assertEqual(18);
      // 老回执不带 notebook → null（remember 只给老客户端，鸿蒙不读）
      expect(r.notebook).assertNull();
    })

    it('parsePenPalLetterResponseReadsNotebookEdits', 0, () => {
      // 世界笔友的回执改法，改的时刻用 generatedAt（R-NOTEBOOK-04）
      const raw = '{"letter":"原文","translation":"译文","danger":false,' +
        '"postage":1,"generatedAt":"2026-10-20T08:00:00.000Z","balance":18,' +
        '"notebook":{"profile":"画像","add":["新大事"],"update":[],"remove":[]},' +
        '"remember":"老客户端兜底字段"}';
      const r = parsePenPalLetterResponse(raw);
      const edits = r.notebook;
      expect(edits !== null).assertTrue();
      if (edits === null) {
        return;
      }
      expect(edits.profile).assertEqual('画像');
      expect(edits.add.length).assertEqual(1);
      expect(edits.add[0]).assertEqual('新大事');
    })

    it('parsePenPalLetterResponseRejectsBadShapes', 0, () => {
      const bad: string[] = [
        '{"letter":"原文"}',
        '{"translation":"译文"}',
        '{"letter":"l","translation":"t","postage":1}',
        '{"letter":"l","translation":"t","postage":1,"generatedAt":"not-a-date","balance":1}',
        '[]',
        'not json'
      ];
      for (const raw of bad) {
        let caught = false;
        try {
          parsePenPalLetterResponse(raw);
        } catch (e) {
          caught = true;
        }
        expect(caught).assertTrue();
      }
    })
  })
}
