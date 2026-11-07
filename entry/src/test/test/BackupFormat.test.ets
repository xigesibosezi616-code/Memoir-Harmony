/**
 * 备份包格式解析单测（6.4 / 6.5；08_backup_package.md §3、EXPORT_FORMAT.md）。
 *
 * 覆盖：ISO8601 日期往返（无毫秒、带毫秒、坏串）、manifest 全字段与缺省兜底、
 * entries 逐条容错（坏条目只丢那一条）、letters / taxonomy 解析。
 * manifest 夹具取自 iOS 真机导出的样本包（2026-08-12），跨端字段名以此为准。
 */
import { describe, it, expect } from '@ohos/hypium';
import { toBackupIso8601, parseBackupIso8601,
  BackupManifest, BackupEntriesFile, BackupLetterDto, BackupTagDto,
  parseBackupManifest, parseBackupEntries, parseBackupLetters,
  parseBackupTaxonomy } from '../../main/ets/services/backup/BackupFormat';

export default function backupFormatTest() {
  describe('BackupFormatTest', () => {
    // ---- 日期：包里一律 ISO8601 无毫秒；解析放宽两种都认 ----

    it('toBackupIso8601StripsMilliseconds', 0, () => {
      expect(toBackupIso8601(Date.UTC(2026, 7, 12, 9, 30, 6)))
        .assertEqual('2026-08-12T09:30:06Z');
      expect(toBackupIso8601(Date.UTC(2026, 7, 12, 9, 30, 6, 123)))
        .assertEqual('2026-08-12T09:30:06Z');
    })

    it('parseBackupIso8601AcceptsBothForms', 0, () => {
      expect(parseBackupIso8601('2026-08-12T09:30:06Z'))
        .assertEqual(Date.UTC(2026, 7, 12, 9, 30, 6));
      expect(parseBackupIso8601('2026-08-12T09:30:06.123Z'))
        .assertEqual(Date.UTC(2026, 7, 12, 9, 30, 6, 123));
    })

    it('parseBackupIso8601RejectsGarbage', 0, () => {
      expect(parseBackupIso8601('not-a-date') === undefined).assertTrue();
      expect(parseBackupIso8601('') === undefined).assertTrue();
    })

    it('dateRoundtripPreservesSecondAlignedTimestamp', 0, () => {
      const ms = Date.UTC(2026, 0, 2, 3, 4, 5);
      expect(parseBackupIso8601(toBackupIso8601(ms))).assertEqual(ms);
    })

    // ---- manifest.json：除 formatVersion 外全部缺省兜底 ----

    it('parseManifestReadsRealIosSample', 0, () => {
      const json = '{"app":"memoir","appVersion":"1.0","counts":{"entries":2,"letters":0,"media":2},'
        + '"encrypted":false,"exportedAt":"2026-08-12T09:30:06Z","formatVersion":1,'
        + '"includesMedia":true,"mediaTotalBytes":3620611,"platform":"ios"}';
      const parsed = parseBackupManifest(json);
      expect(parsed === undefined).assertFalse();
      const manifest = parsed as BackupManifest;
      expect(manifest.formatVersion).assertEqual(1);
      expect(manifest.app).assertEqual('memoir');
      expect(manifest.appVersion).assertEqual('1.0');
      expect(manifest.platform).assertEqual('ios');
      expect(manifest.exportedAtMs).assertEqual(Date.UTC(2026, 7, 12, 9, 30, 6));
      expect(manifest.counts.entries).assertEqual(2);
      expect(manifest.counts.letters).assertEqual(0);
      expect(manifest.counts.media).assertEqual(2);
      expect(manifest.includesMedia).assertTrue();
      expect(manifest.mediaTotalBytes).assertEqual(3620611);
      expect(manifest.encrypted).assertFalse();
    })

    it('parseManifestFillsDefaultsWhenFieldsMissing', 0, () => {
      const manifest = parseBackupManifest('{}') as BackupManifest;
      expect(manifest === undefined).assertFalse();
      expect(manifest.formatVersion).assertEqual(1); // 缺失按 1（iOS 同款兜底）
      expect(manifest.platform).assertEqual('unknown');
      expect(manifest.exportedAtMs).assertEqual(0);
      expect(manifest.includesMedia).assertTrue();
      expect(manifest.encrypted).assertFalse();
      expect(manifest.counts.entries).assertEqual(0);
    })

    it('parseManifestRejectsBadJson', 0, () => {
      expect(parseBackupManifest('{oops') === undefined).assertTrue();
      expect(parseBackupManifest('[]') === undefined).assertTrue();
    })

    it('parseManifestKeepsFutureVersionForServiceToReject', 0, () => {
      const manifest = parseBackupManifest('{"formatVersion":2}') as BackupManifest;
      expect(manifest === undefined).assertFalse();
      expect(manifest.formatVersion).assertEqual(2); // 拒收 v2 是服务层的活
    })

    // ---- entries.json：坏条目只丢那一条，entries 字段坏了才整包拒收 ----

    const ENTRIES_JSON = '{"entries":['
      + '{"id":"E1","title":"海边","date":"2026-08-12T09:30:06Z",'
      + '"createdAt":"2026-08-12T09:31:00Z","updatedAt":"2026-08-12T10:00:00Z",'
      + '"mood":"calm","tags":["Travel"],"isFavorite":true,"moodValence":0.6,'
      + '"moodLabels":["平静"],"audio":["audio_1.m4a"],'
      + '"blocks":['
      + '{"type":"text","text":"浪打过来","styles":[{"location":0,"length":3,"bold":true}]},'
      + '{"type":"photo","file":"photo_1.jpg","position":"center","isCover":true},'
      + '{"text":"缺 type 的块"}]},'
      + '{"title":"没有 id 的坏条目"}],'
      + '"writingStats":{"bestStreakDays":7}}';

    it('parseEntriesReadsFullEntry', 0, () => {
      const parsed = parseBackupEntries(ENTRIES_JSON);
      expect(parsed === undefined).assertFalse();
      const file = parsed as BackupEntriesFile;
      expect(file.entries.length).assertEqual(1); // 坏条目只丢那一条
      const entry = file.entries[0];
      expect(entry.id).assertEqual('E1');
      expect(entry.title).assertEqual('海边');
      expect(entry.dateMs).assertEqual(Date.UTC(2026, 7, 12, 9, 30, 6));
      expect(entry.mood).assertEqual('calm');
      expect(entry.tags.length).assertEqual(1);
      expect(entry.tags[0]).assertEqual('Travel');
      expect(entry.isFavorite).assertTrue();
      expect(entry.moodValence).assertEqual(0.6);
      expect((entry.moodLabels ?? [''])[0] === '平静').assertTrue();
      expect(entry.audio[0]).assertEqual('audio_1.m4a');
      expect(entry.blocks.length).assertEqual(2); // 缺 type 的块被丢
      expect(entry.blocks[0].type).assertEqual('text');
      expect(entry.blocks[0].text).assertEqual('浪打过来');
      const run = (entry.blocks[0].styles ?? [])[0];
      expect(run.location).assertEqual(0);
      expect(run.length).assertEqual(3);
      expect(run.bold).assertTrue();
      expect(entry.blocks[1].type).assertEqual('photo');
      expect(entry.blocks[1].file === 'photo_1.jpg').assertTrue();
      expect(entry.blocks[1].isCover === true).assertTrue();
      expect(file.bestStreakDays).assertEqual(7); // U16：顶层 writingStats
    })

    it('parseEntriesRejectsWhenEntriesFieldBroken', 0, () => {
      expect(parseBackupEntries('{"entries":"nope"}') === undefined).assertTrue();
      expect(parseBackupEntries('{"entries":123}') === undefined).assertTrue();
      expect(parseBackupEntries('{oops') === undefined).assertTrue();
    })

    it('parseEntriesIgnoresInvalidStreakValue', 0, () => {
      const file = parseBackupEntries('{"entries":[],"writingStats":{"bestStreakDays":-3}}') as BackupEntriesFile;
      expect(file === undefined).assertFalse();
      expect(file.bestStreakDays === undefined).assertTrue(); // 负数当没有
      const file2 = parseBackupEntries('{"entries":[],"writingStats":{"bestStreakDays":2.5}}') as BackupEntriesFile;
      expect(file2.bestStreakDays === undefined).assertTrue(); // 非整数当没有
    })

    it('parseEntriesKeepsLegacyRequiredFields', 0, () => {
      // 老版本 iOS 必填的作废字段（mood / blocks）缺失也能导入
      const file = parseBackupEntries('{"entries":[{"id":"E2","title":"t",'
        + '"date":"2026-01-01T00:00:00Z","createdAt":"2026-01-01T00:00:00Z",'
        + '"updatedAt":"2026-01-01T00:00:00Z"}]}') as BackupEntriesFile;
      expect(file === undefined).assertFalse();
      expect(file.entries.length).assertEqual(1);
      expect(file.entries[0].mood).assertEqual(''); // 兜底空串
      expect(file.entries[0].blocks.length).assertEqual(0);
    })

    // ---- letters.json：缺 letters 字段按空算（老包兼容） ----

    it('parseLettersReturnsEmptyWhenFieldMissing', 0, () => {
      const letters = parseBackupLetters('{}') as BackupLetterDto[];
      expect(letters === undefined).assertFalse();
      expect(letters.length).assertEqual(0);
    })

    it('parseLettersDropsEntryWithoutGeneratedAt', 0, () => {
      const json = '{"letters":['
        + '{"id":"L1","body":"见信好","fromCharacter":"青鸟","status":"delivered",'
        + '"triggerKind":"weekly","generatedAt":"2026-08-01T08:00:00Z",'
        + '"deliveredAt":"2026-08-03T08:00:00Z","readAt":"2026-08-03T09:00:00Z",'
        + '"relatedEntryIDs":["E1","E9"]},'
        + '{"id":"L2","body":"没有寄出时间的信"}]}';
      const parsed = parseBackupLetters(json);
      expect(parsed === undefined).assertFalse();
      const letters = parsed as BackupLetterDto[];
      expect(letters.length).assertEqual(1); // L2 被丢
      const letter = letters[0];
      expect(letter.id).assertEqual('L1');
      expect(letter.fromCharacter).assertEqual('青鸟');
      expect(letter.status).assertEqual('delivered');
      expect(letter.generatedAtMs).assertEqual(Date.UTC(2026, 7, 1, 8, 0, 0));
      expect(letter.deliveredAtMs).assertEqual(Date.UTC(2026, 7, 3, 8, 0, 0));
      expect(letter.readAtMs).assertEqual(Date.UTC(2026, 7, 3, 9, 0, 0));
      expect(letter.relatedEntryIDs.length).assertEqual(2);
    })

    // ---- taxonomy.json：只取 tags（moods 已作废） ----

    it('parseTaxonomyDropsTagWithoutName', 0, () => {
      const json = '{"tags":['
        + '{"id":"T1","name":"Travel","colorID":"DeepBlue","textureID":"Linen",'
        + '"createdAt":"2026-01-01T00:00:00Z","coverFile":"cover_1.jpg",'
        + '"coverLayout":"Framed","subtitle":"在路上"},'
        + '{"id":"T2"}],'
        + '"moods":[{"id":"M1","name":"calm"}]}';
      const parsed = parseBackupTaxonomy(json);
      expect(parsed === undefined).assertFalse();
      const tags = parsed as BackupTagDto[];
      expect(tags.length).assertEqual(1); // 缺 name 的 T2 被丢；moods 忽略
      const tag = tags[0];
      expect(tag.id).assertEqual('T1');
      expect(tag.name).assertEqual('Travel');
      expect(tag.colorID).assertEqual('DeepBlue');
      expect(tag.textureID).assertEqual('Linen');
      expect(tag.createdAtMs).assertEqual(Date.UTC(2026, 0, 1));
      expect(tag.coverFile === 'cover_1.jpg').assertTrue();
      expect(tag.coverLayout === 'Framed').assertTrue();
      expect(tag.subtitle === '在路上').assertTrue();
    })
  })
}
