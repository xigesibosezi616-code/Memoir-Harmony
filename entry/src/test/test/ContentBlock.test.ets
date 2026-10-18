/**
 * ContentBlock 纯逻辑单测（10_BUILD_MANUAL.md 1.3）。
 *
 * 覆盖：visibleText（划掉删除、区间越界 / 负长度跳过、多段从后往前）、
 * Ink.isDry / isAddendum（24h 边界、跨日、无时间戳）、isSameLocalDay、
 * JSON 编解码逐块容错（认不出的 type、缺 id、坏样式段、非数组、非法 JSON）、
 * blocksAudioPaths / blocksWithLooseAudio、旋转角确定性。
 */
import { describe, it, expect } from '@ohos/hypium';
import { ContentBlock, ContentBlockType, Ink, TextStyleRun, PhotoPosition, PaperStyle,
  PHOTO_LIMIT_PER_ENTRY, AUDIO_LIMIT_PER_ENTRY,
  decodeContentBlocks, encodeContentBlocks, blocksAudioPaths, blocksWithLooseAudio,
  isSameLocalDay, isMemberPaperStyle, effectivePaperStyle } from '../../main/ets/models/ContentBlock';

/** 本地某天正午（Unix 秒）。用本地日历构造，任何时区跑结果一致 */
function localNoonSec(dayOffset: number): number {
  return new Date(2026, 9, 10 + dayOffset, 12, 0, 0).getTime() / 1000;
}

/** 划掉 [loc, loc+len) 的样式段 */
function struckRun(loc: number, len: number): TextStyleRun {
  const run = new TextStyleRun(loc, len);
  run.struckAt = localNoonSec(0);
  return run;
}

export default function contentBlockTest() {
  describe('ContentBlockTest', () => {
    // ---- visibleText（划掉就是收回） ----

    it('visibleTextWithoutStylesReturnsText', 0, () => {
      expect(ContentBlock.makeText('b1', '你好').visibleText()).assertEqual('你好');
    })

    it('visibleTextRemovesStruckRange', 0, () => {
      const block = ContentBlock.makeText('b1', '你好世界');
      block.styles = [struckRun(0, 2)];
      expect(block.visibleText()).assertEqual('世界');
    })

    it('visibleTextRemovesMultipleStruckBackToFront', 0, () => {
      const block = ContentBlock.makeText('b1', 'abcdefgh');
      block.styles = [struckRun(0, 2), struckRun(6, 1)];
      expect(block.visibleText()).assertEqual('cdefh');
    })

    // 边界：越界 / 负值区间一律跳过，不误删
    it('visibleTextSkipsOutOfBoundsAndNegativeRanges', 0, () => {
      const block = ContentBlock.makeText('b1', 'abc');
      block.styles = [struckRun(100, 5), struckRun(0, 100), struckRun(-1, 1), struckRun(1, -1)];
      expect(block.visibleText()).assertEqual('abc');
    })

    it('visibleTextIgnoresUnstruckStyles', 0, () => {
      const block = ContentBlock.makeText('b1', 'abc');
      const bold = new TextStyleRun(0, 1);
      bold.bold = true;
      block.styles = [bold, struckRun(1, 1)];
      expect(block.visibleText()).assertEqual('ac');
    })

    // ---- 墨迹会干 ----

    it('inkIsDryExactlyAt24Hours', 0, () => {
      const written = localNoonSec(0);
      expect(Ink.isDry(written, undefined, written + Ink.dryingInterval)).assertTrue();
      expect(Ink.isDry(written, undefined, written + Ink.dryingInterval - 1)).assertFalse();
    })

    it('inkIsDryFallsBackToBase', 0, () => {
      const base = localNoonSec(0);
      expect(Ink.isDry(undefined, base, base + 25 * 3600)).assertTrue();
      expect(Ink.isDry(undefined, base, base + 23 * 3600)).assertFalse();
    })

    it('inkIsDryFalseWithoutAnyTimestamp', 0, () => {
      expect(Ink.isDry(undefined, undefined, localNoonSec(0))).assertFalse();
    })

    // 边界：跨日才算补记
    it('isAddendumDetectsCrossDayOnly', 0, () => {
      expect(Ink.isAddendum(localNoonSec(1), localNoonSec(0))).assertTrue();
      expect(Ink.isAddendum(localNoonSec(0), localNoonSec(0))).assertFalse();
      expect(Ink.isAddendum(undefined, localNoonSec(0))).assertFalse();
      expect(Ink.isAddendum(localNoonSec(0), undefined)).assertFalse();
    })

    it('isSameLocalDayComparesCalendarDays', 0, () => {
      const morning = new Date(2026, 9, 10, 1, 0, 0).getTime() / 1000;
      const night = new Date(2026, 9, 10, 23, 0, 0).getTime() / 1000;
      const afterMidnight = new Date(2026, 9, 11, 0, 30, 0).getTime() / 1000;
      expect(isSameLocalDay(morning, night)).assertTrue();
      expect(isSameLocalDay(morning, afterMidnight)).assertFalse();
    })

    // ---- JSON 编解码：逐块容错（单块坏了不影响其他块） ----

    it('decodeSkipsUnknownTypeAndMissingId', 0, () => {
      const json = '[{"id":"a","type":"text","text":"hi"},' +
        '{"id":"b","type":"sticker"},' +
        '{"type":"text","text":"没有id"},' +
        '{"id":"c","type":"photo","photoFilename":"p.jpg"}]';
      const blocks = decodeContentBlocks(json);
      expect(blocks.length).assertEqual(2);
      expect(blocks[0].type).assertEqual(ContentBlockType.Text);
      expect(blocks[0].text).assertEqual('hi');
      expect(blocks[1].type).assertEqual(ContentBlockType.Photo);
      expect(blocks[1].photoFilename).assertEqual('p.jpg');
    })

    it('decodeDropsOnlyBrokenStyleRuns', 0, () => {
      const json = '[{"id":"a","type":"text","text":"abcd",' +
        '"styles":[{"location":0,"length":2,"bold":true},{"location":1}]}]';
      const blocks = decodeContentBlocks(json);
      expect(blocks.length).assertEqual(1);
      const styles = blocks[0].styles;
      expect(styles !== undefined).assertTrue();
      expect(styles!.length).assertEqual(1);
      expect(styles![0].location).assertEqual(0);
      expect(styles![0].length).assertEqual(2);
      expect(styles![0].bold).assertEqual(true);
    })

    it('decodeFailsSoftOnNonArrayOrBrokenJson', 0, () => {
      expect(decodeContentBlocks('"just a string"').length).assertEqual(0);
      expect(decodeContentBlocks('null').length).assertEqual(0);
      expect(decodeContentBlocks('{{broken').length).assertEqual(0);
      expect(decodeContentBlocks('').length).assertEqual(0);
    })

    it('encodeDecodeRoundTripsEveryBlockKind', 0, () => {
      const text = ContentBlock.makeText('t1', '正文');
      const run = new TextStyleRun(0, 2);
      run.bold = true;
      text.styles = [run];
      const photo = ContentBlock.makePhoto('p1', 'still.jpg', 'video.mov',
        PhotoPosition.Right, PaperStyle.Polaroid);
      photo.isCover = true;
      const audio = ContentBlock.makeAudio('a1', 'audio/a.m4a');
      const decoded = decodeContentBlocks(encodeContentBlocks([text, photo, audio]));
      expect(decoded.length).assertEqual(3);
      expect(decoded[0].text).assertEqual('正文');
      expect(decoded[0].styles![0].bold).assertEqual(true);
      expect(decoded[1].photoFilename).assertEqual('still.jpg');
      expect(decoded[1].livePhotoVideoFilename).assertEqual('video.mov');
      expect(decoded[1].position).assertEqual(PhotoPosition.Right);
      expect(decoded[1].paperStyle).assertEqual(PaperStyle.Polaroid);
      expect(decoded[1].isCover).assertEqual(true);
      expect(decoded[1].rotationAngle).assertEqual(photo.rotationAngle);
      expect(decoded[2].audioFilename).assertEqual('audio/a.m4a');
    })

    // ---- 录音清单 ----

    it('blocksAudioPathsKeepsOrder', 0, () => {
      const paths = blocksAudioPaths([
        ContentBlock.makeText('t', 'hi'),
        ContentBlock.makeAudio('a1', 'audio/one.m4a'),
        ContentBlock.makeAudio('a2', 'audio/two.m4a')
      ]);
      expect(paths.length).assertEqual(2);
      expect(paths[0]).assertEqual('audio/one.m4a');
      expect(paths[1]).assertEqual('audio/two.m4a');
    })

    it('blocksWithLooseAudioAppendsOnlyMissing', 0, () => {
      const placed = ContentBlock.makeAudio('a1', 'audio/one.m4a');
      const result = blocksWithLooseAudio([placed],
        ['audio/one.m4a', 'audio/two.m4a'], () => 'newId');
      expect(result.length).assertEqual(2);
      expect(result[1].type).assertEqual(ContentBlockType.Audio);
      expect(result[1].audioFilename).assertEqual('audio/two.m4a');
      expect(result[1].id).assertEqual('newId');
    })

    // ---- 每篇上限（05 §3.6 照片 5 张 / R-ENTRY-08 录音 3 段） ----

    it('perEntryLimitsMatchSpec', 0, () => {
      expect(PHOTO_LIMIT_PER_ENTRY).assertEqual(5);
      expect(AUDIO_LIMIT_PER_ENTRY).assertEqual(3);
    })

    // ---- 旋转角：创建时定死，跨启动一致 ----

    it('rotationAngleDeterministicAndInRange', 0, () => {
      const a1 = ContentBlock.rotationAngleFor('same-id');
      const a2 = ContentBlock.rotationAngleFor('same-id');
      expect(a1).assertEqual(a2);
      expect(a1 >= -3.0 && a1 <= 2.9).assertTrue();
    })

    // ---- 相纸会员规则（05 §3.5；会员判定 7.2 接上） ----

    it('memberPaperStylesAreTheFourPaidOnes', 0, () => {
      expect(isMemberPaperStyle(PaperStyle.Original)).assertFalse();
      expect(isMemberPaperStyle(PaperStyle.Polaroid)).assertFalse();
      expect(isMemberPaperStyle(PaperStyle.WashiSticker)).assertTrue();
      expect(isMemberPaperStyle(PaperStyle.MinimalCard)).assertTrue();
      expect(isMemberPaperStyle(PaperStyle.FilmFrame)).assertTrue();
      expect(isMemberPaperStyle(PaperStyle.LetterAttached)).assertTrue();
    })

    it('nonMemberDegradesMemberPaperToPolaroid', 0, () => {
      // 非会员存了会员款 → 实际按宝丽来渲染（存值不改写由调用方保证，这里只管渲染映射）
      expect(effectivePaperStyle(PaperStyle.FilmFrame, false)).assertEqual(PaperStyle.Polaroid);
      expect(effectivePaperStyle(PaperStyle.LetterAttached, false)).assertEqual(PaperStyle.Polaroid);
      // 免费款原样
      expect(effectivePaperStyle(PaperStyle.Original, false)).assertEqual(PaperStyle.Original);
      expect(effectivePaperStyle(PaperStyle.Polaroid, false)).assertEqual(PaperStyle.Polaroid);
      // 会员身份下全部原样
      expect(effectivePaperStyle(PaperStyle.FilmFrame, true)).assertEqual(PaperStyle.FilmFrame);
      expect(effectivePaperStyle(PaperStyle.WashiSticker, true)).assertEqual(PaperStyle.WashiSticker);
    })
  })
}
