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
  parseLetterResponse,
  parseLetterListResponse,
  letterRequestBody
} from '../../main/ets/models/Api';

export default function letterApiTest() {
  describe('LetterApiTest', () => {
    // ---- POST /letter 请求体 ----

    it('letterRequestBodyOmitsEmptyOptionals', 0, () => {
      const entries = [
        new LetterRequestEntry('标题', '正文', 1_700_000_000_000, ''),
        new LetterRequestEntry('', '无题的', 1_700_000_086_400, 'calm')
      ];
      const request = new LetterRequest(entries, 'weekly', '', '青鸟', '');
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
      // date 毫秒 → ISO8601
      expect(list[0]['date']).assertEqual(new Date(1_700_000_000_000).toISOString());
    })

    it('letterRequestBodyKeepsNonEmptyOptionals', 0, () => {
      const entries = [new LetterRequestEntry('t', 'c', 0, 'joy')];
      const request = new LetterRequest(entries, 'weekly', 'joy', '青鸟', 'zh-Hans');
      const body = letterRequestBody(request);
      expect(body['dominantMood']).assertEqual('joy');
      expect(body['language']).assertEqual('zh-Hans');
    })

    // ---- POST /letter 成功响应 ----

    it('parseLetterResponseReadsBodyAndCharacter', 0, () => {
      const r = parseLetterResponse('{"body":"回信","fromCharacter":"青鸟"}');
      expect(r instanceof LetterResponse).assertTrue();
      expect(r.body).assertEqual('回信');
      expect(r.fromCharacter).assertEqual('青鸟');
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
  })
}
