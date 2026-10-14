/**
 * JournalEntry 纯逻辑单测（10_BUILD_MANUAL.md 1.3）。
 *
 * 核心是「唯一写入口」setContentBlocks（R-RICH-10）：content（visibleText 用
 * \n\n 连接）/ wordCount / audioURLs / updatedAt 必须写内容块时同步派生，
 * 绝不分开写。另有旧 content 降级、looseAudio、补记天数、封面照片、标题净化。
 */
import { describe, it, expect } from '@ohos/hypium';
import { JournalEntry } from '../../main/ets/models/JournalEntry';
import { ContentBlock, ContentBlockType, PhotoPosition, PaperStyle,
  TextStyleRun } from '../../main/ets/models/ContentBlock';

function makeEntry(): JournalEntry {
  return new JournalEntry('E1', 1000, 2000, 3000);
}

export default function journalEntryTest() {
  describe('JournalEntryTest', () => {
    it('setContentBlocksDerivesAllFieldsTogether', 0, () => {
      const entry = makeEntry();
      entry.setContentBlocks([
        ContentBlock.makeText('b1', '你好'),
        ContentBlock.makeAudio('b2', 'audio/a.m4a'),
        ContentBlock.makeText('b3', '世界')
      ], 9000);
      expect(entry.content).assertEqual('你好\n\n世界');
      expect(entry.wordCount).assertEqual(6);
      expect(entry.audioURLs.length).assertEqual(1);
      expect(entry.audioURLs[0]).assertEqual('audio/a.m4a');
      expect(entry.updatedAt).assertEqual(9000);
      expect(entry.contentBlocksData !== undefined).assertTrue();
    })

    it('setContentBlocksUsesVisibleText', 0, () => {
      const entry = makeEntry();
      const block = ContentBlock.makeText('b1', '你好世界');
      const run = new TextStyleRun(0, 2);
      run.struckAt = 123;
      block.styles = [run];
      entry.setContentBlocks([block], 1);
      expect(entry.content).assertEqual('世界');
      expect(entry.wordCount).assertEqual(2);
    })

    it('contentBlocksFallsBackToLegacyContent', 0, () => {
      const entry = makeEntry();
      entry.content = '旧正文';
      const blocks = entry.contentBlocks;
      expect(blocks.length).assertEqual(1);
      // 块 id 用 entry.id 保持稳定，否则「长按插入照片」的锚点会失配
      expect(blocks[0].id).assertEqual('E1');
      expect(blocks[0].type).assertEqual(ContentBlockType.Text);
      expect(blocks[0].text).assertEqual('旧正文');
    })

    it('contentBlocksEmptyForFreshEntry', 0, () => {
      expect(makeEntry().contentBlocks.length).assertEqual(0);
    })

    it('looseAudioURLsExcludesPlacedOnes', 0, () => {
      const entry = makeEntry();
      entry.setContentBlocks([ContentBlock.makeAudio('b1', 'audio/a.m4a')], 1);
      entry.audioURLs = ['audio/a.m4a', 'audio/b.m4a'];
      const loose = entry.looseAudioURLs;
      expect(loose.length).assertEqual(1);
      expect(loose[0]).assertEqual('audio/b.m4a');
    })

    it('addendumDaysCountsDistinctCrossDays', 0, () => {
      const createdAtMs = new Date(2026, 9, 10, 12, 0, 0).getTime();
      const entry = new JournalEntry('E1', createdAtMs, createdAtMs, createdAtMs);
      const block = ContentBlock.makeText('b1', 'a');
      block.addedAt = new Date(2026, 9, 12, 8, 0, 0).getTime() / 1000;
      const run = new TextStyleRun(0, 1);
      run.writtenAt = new Date(2026, 9, 12, 10, 0, 0).getTime() / 1000; // 同一天去重
      block.styles = [run];
      entry.setContentBlocks([block], createdAtMs);
      expect(entry.addendumDays.length).assertEqual(1);
    })

    it('addendumDaysEmptyWhenSameDay', 0, () => {
      const createdAtMs = new Date(2026, 9, 10, 12, 0, 0).getTime();
      const entry = new JournalEntry('E1', createdAtMs, createdAtMs, createdAtMs);
      const block = ContentBlock.makeText('b1', 'a');
      block.addedAt = new Date(2026, 9, 10, 18, 0, 0).getTime() / 1000;
      entry.setContentBlocks([block], createdAtMs);
      expect(entry.addendumDays.length).assertEqual(0);
    })

    it('coverPhotoPrefersMarkedThenFirst', 0, () => {
      const entry = makeEntry();
      const p1 = ContentBlock.makePhoto('b1', 'one.jpg', undefined,
        PhotoPosition.Left, PaperStyle.Original);
      const p2 = ContentBlock.makePhoto('b2', 'two.jpg', undefined,
        PhotoPosition.Right, PaperStyle.Polaroid);
      p2.isCover = true;
      entry.setContentBlocks([p1, p2], 1);
      expect(entry.coverPhotoFilename).assertEqual('two.jpg');
      p2.isCover = undefined;
      entry.setContentBlocks([p1, p2], 1);
      expect(entry.coverPhotoFilename).assertEqual('one.jpg');
    })

    it('coverPhotoUndefinedWithoutPhotos', 0, () => {
      const entry = makeEntry();
      entry.setContentBlocks([ContentBlock.makeText('b1', 'x')], 1);
      expect(entry.coverPhotoFilename).assertUndefined();
    })

    it('sanitizedTitleStripsNewlinesAndClampsTo40', 0, () => {
      expect(JournalEntry.sanitizedTitle('标\n题\n')).assertEqual('标题');
      const long = '标题'.repeat(25); // 50 字，超上限
      const sanitized = JournalEntry.sanitizedTitle(long);
      expect(sanitized.length).assertEqual(JournalEntry.titleMaxLength);
      expect(JournalEntry.titleMaxLength).assertEqual(40);
    })

    it('photoCountFilenamesAndTextPreview', 0, () => {
      const entry = makeEntry();
      const photo = ContentBlock.makePhoto('b1', 'one.jpg', undefined,
        PhotoPosition.Left, PaperStyle.Original);
      entry.setContentBlocks([
        ContentBlock.makeText('t1', '开头'),
        photo,
        ContentBlock.makeText('t2', '结尾')
      ], 1);
      expect(entry.photoCount).assertEqual(1);
      expect(entry.photoFilenames.length).assertEqual(1);
      expect(entry.photoFilenames[0]).assertEqual('one.jpg');
      expect(entry.textPreview).assertEqual('开头\n结尾');
    })
  })
}
