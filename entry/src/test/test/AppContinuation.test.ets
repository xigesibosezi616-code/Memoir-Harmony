/**
 * 应用接续草稿编解码单测（services/AppContinuation.ets）。
 *
 * 不变量：
 * - 编解码往返无损：全部字段（含可选字段）原样还原，contentBlocksData 透传
 * - want 参数按不可信输入处理：非法 JSON / 缺 id / 缺时间戳 → null，绝不半恢复
 * - tags / audioURLs 混进非字符串元素：过滤掉，不留 undefined 进草稿表
 * - utf8ByteLength 按字节算（官方 wantParam <100KB 约束），代理对按 4 字节码点
 */
import { describe, it, expect } from '@ohos/hypium';
import { DraftEntry, PlaceMode } from '../../main/ets/models/Draft';
import { ContentBlock, PhotoPosition, PaperStyle } from '../../main/ets/models/ContentBlock';
import {
  CONTINUATION_PAYLOAD_LIMIT_BYTES,
  continuationPayloadFits,
  decodeDraftFromContinuation,
  encodeDraftForContinuation,
  utf8ByteLength
} from '../../main/ets/services/AppContinuation';

/** 造一份全字段都有的草稿（往返断言用） */
function fullDraft(): DraftEntry {
  const draft = new DraftEntry('draft-uuid-1', 1000, 2000);
  draft.title = '旅行第二天';
  const photo = ContentBlock.makePhoto('b1', 'photo_ab12.jpg', 'photo_ab12.mp4',
    PhotoPosition.Left, PaperStyle.Polaroid);
  photo.isCover = true;
  draft.setContentBlocks([ContentBlock.makeText('t1', '在洱海边醒来。'), photo], 2000);
  draft.mood = '平静';
  draft.moodColorHex = '#7aa5a0';
  draft.tags = ['旅行日记'];
  draft.audioURLs = ['audio/a1.m4a'];
  draft.weatherCode = 'sunny';
  draft.weatherInfo = '晴 18℃';
  draft.locationInfo = '大理 · 洱海';
  draft.placeMode = PlaceMode.Manual;
  draft.manualPlaceName = '洱海';
  return draft;
}

export default function appContinuationTest() {
  describe('AppContinuationTest', () => {
    it('roundTripKeepsEveryField', 0, () => {
      const source = fullDraft();
      const decoded = decodeDraftFromContinuation(encodeDraftForContinuation(source));
      expect(decoded === null).assertFalse();
      const draft = decoded as DraftEntry;
      expect(draft.id).assertEqual('draft-uuid-1');
      expect(draft.createdAt).assertEqual(1000);
      expect(draft.updatedAt).assertEqual(2000);
      expect(draft.title).assertEqual('旅行第二天');
      expect(draft.mood).assertEqual('平静');
      expect(draft.moodColorHex).assertEqual('#7aa5a0');
      expect(draft.tags.length).assertEqual(1);
      expect(draft.tags[0]).assertEqual('旅行日记');
      expect(draft.audioURLs.length).assertEqual(1);
      expect(draft.audioURLs[0]).assertEqual('audio/a1.m4a');
      expect(draft.weatherCode).assertEqual('sunny');
      expect(draft.weatherInfo).assertEqual('晴 18℃');
      expect(draft.locationInfo).assertEqual('大理 · 洱海');
      expect(draft.placeMode).assertEqual(PlaceMode.Manual);
      expect(draft.manualPlaceName).assertEqual('洱海');
      // contentBlocksData 透传：照片三件套引用原样还原
      expect(draft.contentBlocks.length).assertEqual(2);
      expect(draft.contentBlocks[1].photoFilename).assertEqual('photo_ab12.jpg');
      expect(draft.contentBlocks[1].livePhotoVideoFilename).assertEqual('photo_ab12.mp4');
      expect(draft.contentBlocks[1].isCover).assertTrue();
    })

    it('roundTripKeepsEmptyOptionalsAbsent', 0, () => {
      const source = new DraftEntry('d2', 10, 20);
      source.setContentBlocks([ContentBlock.makeText('t', '只有文字')], 20);
      const decoded = decodeDraftFromContinuation(encodeDraftForContinuation(source));
      expect(decoded === null).assertFalse();
      const draft = decoded as DraftEntry;
      expect(draft.title).assertEqual('');
      expect(draft.moodColorHex === undefined).assertTrue();
      expect(draft.weatherCode === undefined).assertTrue();
      expect(draft.manualPlaceName === undefined).assertTrue();
      expect(draft.tags.length).assertEqual(0);
      expect(draft.placeMode).assertEqual(PlaceMode.Auto);
    })

    it('decodeRejectsMalformedPayloads', 0, () => {
      expect(decodeDraftFromContinuation('')).assertNull();
      expect(decodeDraftFromContinuation('not json at all')).assertNull();
      expect(decodeDraftFromContinuation('{}')).assertNull(); // 缺 id / 时间戳
      expect(decodeDraftFromContinuation('{"id":"x"}')).assertNull(); // 缺时间戳
      expect(decodeDraftFromContinuation('{"id":"","createdAt":1,"updatedAt":1}')).assertNull(); // 空 id
      expect(decodeDraftFromContinuation('{"id":123,"createdAt":1,"updatedAt":1}')).assertNull(); // id 非字符串
      expect(decodeDraftFromContinuation('{"id":"x","createdAt":"1","updatedAt":1}')).assertNull(); // 时间戳非数字
    })

    it('decodeFiltersNonStringEntriesInArrays', 0, () => {
      const payload = '{"id":"d3","createdAt":1,"updatedAt":1,' +
        '"tags":["旅行",123,null,"工作"],"audioURLs":["audio/a.m4a",false]}';
      const decoded = decodeDraftFromContinuation(payload);
      expect(decoded === null).assertFalse();
      const draft = decoded as DraftEntry;
      expect(draft.tags.length).assertEqual(2);
      expect(draft.tags[0]).assertEqual('旅行');
      expect(draft.tags[1]).assertEqual('工作');
      expect(draft.audioURLs.length).assertEqual(1);
      expect(draft.audioURLs[0]).assertEqual('audio/a.m4a');
    })

    it('utf8ByteLengthCountsBytesNotCharacters', 0, () => {
      expect(utf8ByteLength('')).assertEqual(0);
      expect(utf8ByteLength('abc')).assertEqual(3); // ASCII 1 字节/字符
      expect(utf8ByteLength('汉字')).assertEqual(6); // 常用汉字 3 字节
      expect(utf8ByteLength('é')).assertEqual(2); // 两字节区
      // 表情 = 代理对：charLength 2、UTF-8 四字节
      expect('🎉'.length).assertEqual(2);
      expect(utf8ByteLength('🎉')).assertEqual(4);
    })

    it('payloadFitsHonorsOfficialLimit', 0, () => {
      expect(continuationPayloadFits('{}')).assertTrue();
      // 拼一个恰 95KB 的合法接续包（前缀/后缀字节数动态算，不硬编码）
      const prefix: string = '{"id":"x","createdAt":1,"updatedAt":1,"title":"';
      const atLimit: string = prefix +
        'a'.repeat(CONTINUATION_PAYLOAD_LIMIT_BYTES - utf8ByteLength(prefix) - 2) + '"}';
      expect(utf8ByteLength(atLimit)).assertEqual(CONTINUATION_PAYLOAD_LIMIT_BYTES);
      expect(continuationPayloadFits(atLimit)).assertTrue();
      // 超一字节 → false
      const overLimit: string = prefix +
        'a'.repeat(CONTINUATION_PAYLOAD_LIMIT_BYTES - utf8ByteLength(prefix) - 1) + '"}';
      expect(continuationPayloadFits(overLimit)).assertFalse();
    })

    it('typicalTextDraftStaysWellUnderLimit', 0, () => {
      const draft = new DraftEntry('d4', 1, 1);
      draft.title = '十月的长假';
      draft.setContentBlocks([ContentBlock.makeText('t', '写'.repeat(1000))], 1); // 一千字
      expect(continuationPayloadFits(encodeDraftForContinuation(draft))).assertTrue();
    })

    it('limitConstantMatchesOfficialBudget', 0, () => {
      // 官方约束 wantParam <100KB；留 5KB 余量给系统预置字段与编码开销
      expect(CONTINUATION_PAYLOAD_LIMIT_BYTES).assertEqual(95 * 1024);
    })
  })
}
