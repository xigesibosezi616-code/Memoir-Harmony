/**
 * 备份包格式解析单测（6.4 / 6.5；08_backup_package.md §3、EXPORT_FORMAT.md）。
 *
 * 覆盖：ISO8601 日期往返（无毫秒、带毫秒、坏串）、manifest 全字段与缺省兜底、
 * entries 逐条容错（坏条目只丢那一条）、letters / taxonomy 解析。
 * manifest 夹具取自 iOS 真机导出的样本包（2026-08-12），跨端字段名以此为准。
 * letters 覆盖世界笔友四字段的解析 + 导出 wire round-trip（U01）；
 * penPalNotes（笔友手记）覆盖解析容错 + 导出 wire round-trip（U01 B3）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { toBackupIso8601, parseBackupIso8601,
  BackupManifest, BackupEntriesFile, BackupLetterDto, BackupTagDto, LettersWire,
  parseBackupManifest, parseBackupEntries, parseBackupLetters,
  parseBackupTaxonomy, parseBackupPenPalNotes } from '../../main/ets/services/backup/BackupFormat';
import { BackupExportService } from '../../main/ets/services/backup/BackupExportService';
import { Letter } from '../../main/ets/models/Letter';
import { PenPalNote } from '../../main/ets/models/PenPalNote';

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

    it('parseLettersReadsWorldPenPalFields', 0, () => {
      // U01 世界笔友四字段（可选；老包没有 = 自己起名的那位的信）
      const json = '{"letters":['
        + '{"id":"W1","body":"Hello there","fromCharacter":"Aki","status":"delivered",'
        + '"triggerKind":"weekly","generatedAt":"2026-11-01T08:00:00Z",'
        + '"penPalID":"aki","translatedBody":"你好呀","danger":true,"postage":2}]}';
      const parsed = parseBackupLetters(json);
      expect(parsed === undefined).assertFalse();
      const letters = parsed as BackupLetterDto[];
      expect(letters.length).assertEqual(1);
      const letter = letters[0];
      expect(letter.penPalId).assertEqual('aki');
      expect(letter.translatedBody).assertEqual('你好呀');
      expect(letter.danger).assertTrue();
      expect(letter.postage).assertEqual(2);
      // 老包（四字段全缺）照常导入：undefined = 自己起名的那位
      const legacy = parseBackupLetters('{"letters":['
        + '{"id":"W2","body":"见信好","generatedAt":"2026-11-01T08:00:00Z"}]}');
      expect(legacy === undefined).assertFalse();
      const legacyLetter = (legacy as BackupLetterDto[])[0];
      expect(legacyLetter.penPalId).assertUndefined();
      expect(legacyLetter.translatedBody).assertUndefined();
      expect(legacyLetter.danger).assertUndefined();
      expect(legacyLetter.postage).assertUndefined();
    })

    it('makeWireLetterRoundTripsWorldPenPalFields', 0, () => {
      // 导出 wire → JSON.stringify → 再解析，四字段原样回来（penPalID 大写 ID 是 iOS Codable 同名）
      const letter = new Letter('W3', Date.UTC(2026, 10, 1, 8, 0, 0), Date.UTC(2026, 10, 1, 8, 0, 0));
      letter.body = 'Hello!';
      letter.penPalId = 'aki';
      letter.translatedBody = '你好！';
      letter.danger = true;
      letter.postage = 2;
      const wire = BackupExportService.makeWireLetter(letter, ['E1']);
      const file = new LettersWire();
      file.letters.push(wire);
      const parsed = parseBackupLetters(JSON.stringify(file));
      expect(parsed === undefined).assertFalse();
      const back = (parsed as BackupLetterDto[])[0];
      expect(back.id).assertEqual('W3');
      expect(back.penPalId).assertEqual('aki');
      expect(back.translatedBody).assertEqual('你好！');
      expect(back.danger).assertTrue();
      expect(back.postage).assertEqual(2);
      // 普通信（四字段 undefined）序列化时整个键不写——老包导入 iOS 也不认多余键
      const plain = new Letter('W4', 1000, 2000);
      const plainJson = JSON.stringify(BackupExportService.makeWireLetter(plain, []));
      expect(plainJson.includes('penPalID')).assertFalse();
      expect(plainJson.includes('danger')).assertFalse();
    })

    // ---- letters.json 里的 penPalNotes（U01 B3 笔友手记） ----

    it('parsePenPalNotesReadsFullNote', 0, () => {
      const json = '{"letters":[],"penPalNotes":['
        + '{"id":"N1","penPalID":"own","text":"画像","kind":"profile",'
        + '"notedAt":"2026-11-01T08:00:00Z","createdAt":"2026-11-01T08:00:00Z",'
        + '"updatedAt":"2026-11-05T08:00:00Z"},'
        + '{"id":"N2","text":"缺 penPalID 的丢"},'
        + '{"id":"N3","penPalID":"aki","text":"坏日期","notedAt":"oops",'
        + '"createdAt":"2026-11-01T08:00:00Z"},'
        + '{"id":"N4","penPalID":"aki","text":"没有 kind 的按缺省",'
        + '"notedAt":"2026-11-02T08:00:00Z","createdAt":"2026-11-02T08:00:00Z"}]}';
      const notes = parseBackupPenPalNotes(json);
      expect(notes.length).assertEqual(2);
      expect(notes[0].id).assertEqual('N1');
      expect(notes[0].penPalID).assertEqual('own');
      expect(notes[0].text).assertEqual('画像');
      expect(notes[0].kind).assertEqual('profile');
      expect(notes[0].notedAtMs).assertEqual(Date.UTC(2026, 10, 1, 8, 0, 0));
      expect(notes[0].createdAtMs).assertEqual(Date.UTC(2026, 10, 1, 8, 0, 0));
      expect(notes[0].updatedAtMs).assertEqual(Date.UTC(2026, 10, 5, 8, 0, 0));
      expect(notes[1].id).assertEqual('N4');
      expect(notes[1].kind).assertUndefined();
      expect(notes[1].updatedAtMs).assertUndefined();
    })

    it('parsePenPalNotesToleratesMissingPieces', 0, () => {
      // 文件没有 / 字段缺 / 坏 JSON / 字段类型坏：都当没有，不影响信的导入
      expect(parseBackupPenPalNotes(undefined).length).assertEqual(0);
      expect(parseBackupPenPalNotes('{"letters":[]}').length).assertEqual(0);
      expect(parseBackupPenPalNotes('{oops').length).assertEqual(0);
      expect(parseBackupPenPalNotes('{"penPalNotes":"nope"}').length).assertEqual(0);
    })

    it('makeWirePenPalNoteRoundTrips', 0, () => {
      const note = new PenPalNote('aki', '记下的大事', Date.UTC(2026, 10, 2, 8, 0, 0));
      note.id = 'N5';
      note.createdAtMs = Date.UTC(2026, 10, 2, 8, 0, 0);
      note.updatedAtMs = Date.UTC(2026, 10, 6, 8, 0, 0);
      const wire = BackupExportService.makeWirePenPalNote(note);
      const file = new LettersWire();
      file.penPalNotes = [wire];
      const notes = parseBackupPenPalNotes(JSON.stringify(file));
      expect(notes.length).assertEqual(1);
      expect(notes[0].id).assertEqual('N5');
      expect(notes[0].penPalID).assertEqual('aki');
      expect(notes[0].text).assertEqual('记下的大事');
      expect(notes[0].kind).assertEqual('recent');
      expect(notes[0].notedAtMs).assertEqual(Date.UTC(2026, 10, 2, 8, 0, 0));
      expect(notes[0].updatedAtMs).assertEqual(Date.UTC(2026, 10, 6, 8, 0, 0));
      // 没改过的（updatedAtMs undefined）序列化不写 updatedAt 键
      const fresh = new PenPalNote('own', '新记的', 1000);
      expect(JSON.stringify(BackupExportService.makeWirePenPalNote(fresh)).includes('updatedAt'))
        .assertFalse();
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
