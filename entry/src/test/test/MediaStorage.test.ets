/**
 * 媒体存储纯逻辑单测（10_BUILD_MANUAL.md 1.4）。
 *
 * 覆盖卡片验收：
 * - 草稿里引用的照片、日记本封面都不会被当孤儿（R-DATA-08）
 * - 删日记后它的文件都没了
 * 以及：05 §8 命名规则、引用表（照片三件套 + 录音双侧键 + 草稿 + 封面）、
 * 占用对账、孤儿清理安全闸、坏 audio_urls JSON 容错。
 *
 * 文件系统用内存实现注入（MediaFileSystem）；接 RDB 的 MediaStorageService
 * 属设备侧（依赖 relationalStore），不在本套单测里。
 */
import { describe, it, expect } from '@ohos/hypium';
import { JournalEntry } from '../../main/ets/models/JournalEntry';
import { DraftEntry } from '../../main/ets/models/Draft';
import { ContentBlock, PhotoPosition, PaperStyle } from '../../main/ets/models/ContentBlock';
import { MediaFileEntry, MediaDirs, MediaFileSystem, deleteFilesInDir } from
  '../../main/ets/services/MediaFiles';
import { photoFilenameFor, fullPhotoFilenameFor, livePhotoVideoFilenameFor, coverFilenameFor,
  referencedFilenames, classifyMediaFiles, scanMediaUsage, reclaimOrphanFiles,
  isOrphanReclaimAllowed, parseAudioUrls, entryPhotoFilenames, entryAudioFilenames,
  draftPhotoFilenames, draftAudioFilenames } from '../../main/ets/services/MediaStorage';

const NOW: number = 1760000000000;
const PHOTOS_DIR = '/data/app/photos';
const AUDIO_DIR = '/data/app/audio';

/** 内存文件系统：绝对路径 → 字节数 */
class MemoryFs implements MediaFileSystem {
  private files: Map<string, number> = new Map();

  seed(path: string, size: number): void {
    this.files.set(path, size);
  }

  has(path: string): boolean {
    return this.files.has(path);
  }

  listFiles(dirPath: string): MediaFileEntry[] {
    const result: MediaFileEntry[] = [];
    const prefix = `${dirPath}/`;
    this.files.forEach((size: number, path: string): void => {
      if (!path.startsWith(prefix)) {
        return;
      }
      const name = path.substring(prefix.length);
      if (name.length === 0 || name.startsWith('.') || name.includes('/')) {
        return;
      }
      result.push(new MediaFileEntry(name, size));
    });
    return result;
  }

  fileSize(filePath: string): number {
    const size = this.files.get(filePath);
    return size !== undefined ? size : 0;
  }

  deleteFile(filePath: string): boolean {
    return this.files.delete(filePath);
  }

  mkdirs(dirPath: string): void {
    // 内存实现没有目录概念，无需创建
  }
}

function defaultDirs(): MediaDirs {
  return new MediaDirs(PHOTOS_DIR, AUDIO_DIR);
}

/** 一篇带照片 + 录音的日记（setContentBlocks 同步派生 audioURLs，R-RICH-10） */
function makeEntryWithPhotoAndAudio(id: string, photoName: string,
  audioRelative: string): JournalEntry {
  const entry = new JournalEntry(id, NOW, NOW, NOW);
  const text = ContentBlock.makeText(`${id}-text`, '今天');
  const photo = ContentBlock.makePhoto(`${id}-photo`, photoName, undefined,
    PhotoPosition.Left, PaperStyle.Polaroid);
  const audio = ContentBlock.makeAudio(`${id}-audio`, audioRelative);
  entry.setContentBlocks([text, photo, audio], NOW);
  return entry;
}

/** 一篇带动态照片三件套的日记 */
function makeEntryWithLivePhoto(id: string, photoName: string, videoName: string,
  stillName: string): JournalEntry {
  const entry = new JournalEntry(id, NOW, NOW, NOW);
  const photo = ContentBlock.makePhoto(`${id}-photo`, photoName, videoName,
    PhotoPosition.Right, PaperStyle.Original);
  photo.livePhotoStillFilename = stillName;
  entry.setContentBlocks([photo], NOW);
  return entry;
}

/** 一份带照片的草稿 */
function makeDraftWithPhoto(id: string, photoName: string): DraftEntry {
  const draft = new DraftEntry(id, NOW, NOW);
  const photo = ContentBlock.makePhoto(`${id}-photo`, photoName, undefined,
    PhotoPosition.Left, PaperStyle.Polaroid);
  draft.setContentBlocks([photo], NOW);
  return draft;
}

export default function mediaStorageTest() {
  describe('MediaStorageTest', () => {
    // ---- 05 §8 命名规则 ----

    it('namingRulesFollowDataModelSection8', 0, () => {
      const uuid = '8B1F2C3D-4E5F-4A6B-8C9D-0123456789AB';
      expect(photoFilenameFor(uuid)).assertEqual('photo_8B1F2C3D.jpg');
      expect(fullPhotoFilenameFor(uuid)).assertEqual('photo_8B1F2C3D_full.jpg');
      expect(livePhotoVideoFilenameFor(uuid)).assertEqual('photo_8B1F2C3D.mov');
      expect(coverFilenameFor(uuid)).assertEqual('cover_8B1F2C3D-4E5F-4A6B-8C9D-0123456789AB.jpg');
    })

    // ---- 引用表（R-DATA-08） ----

    it('referencedFilenamesIncludesTripletAudioDraftAndCover', 0, () => {
      const entry = makeEntryWithLivePhoto('E1', 'photo_live.jpg', 'photo_live.mov',
        'photo_live_full.jpg');
      const audioEntry = makeEntryWithPhotoAndAudio('E2', 'photo_a.jpg', 'audio/rec_1.m4a');
      const draft = makeDraftWithPhoto('D1', 'photo_draft.jpg');
      const names = referencedFilenames([entry, audioEntry], [draft], ['cover_X.jpg']);
      // 照片三件套
      expect(names.has('photo_live.jpg')).assertTrue();
      expect(names.has('photo_live.mov')).assertTrue();
      expect(names.has('photo_live_full.jpg')).assertTrue();
      expect(names.has('photo_a.jpg')).assertTrue();
      // 录音：相对路径 + 裸名双侧都在
      expect(names.has('audio/rec_1.m4a')).assertTrue();
      expect(names.has('rec_1.m4a')).assertTrue();
      // 草稿、封面
      expect(names.has('photo_draft.jpg')).assertTrue();
      expect(names.has('cover_X.jpg')).assertTrue();
    })

    it('referencedFilenamesIgnoresEmptyCoverName', 0, () => {
      const names = referencedFilenames([], [], ['', '']);
      expect(names.size).assertEqual(0);
    })

    // ---- 验收：草稿里的照片、日记本封面不会被当孤儿（R-DATA-08） ----

    it('draftPhotoIsNotTreatedAsOrphan', 0, () => {
      const fs = new MemoryFs();
      fs.seed(`${PHOTOS_DIR}/photo_draft.jpg`, 500);
      const draft = makeDraftWithPhoto('D1', 'photo_draft.jpg');
      const referenced = referencedFilenames([], [draft], []);
      const usage = scanMediaUsage(fs, defaultDirs(), referenced);
      expect(usage.referencedCount).assertEqual(1);
      expect(usage.referencedBytes).assertEqual(500);
      expect(usage.orphanCount).assertEqual(0);
      expect(usage.orphanBytes).assertEqual(0);
    })

    it('notebookCoverIsNotTreatedAsOrphan', 0, () => {
      const fs = new MemoryFs();
      fs.seed(`${PHOTOS_DIR}/cover_X.jpg`, 700);
      const referenced = referencedFilenames([], [], ['cover_X.jpg']);
      const usage = scanMediaUsage(fs, defaultDirs(), referenced);
      expect(usage.referencedCount).assertEqual(1);
      expect(usage.referencedBytes).assertEqual(700);
      expect(usage.orphanCount).assertEqual(0);
    })

    // ---- 占用对账 ----

    it('classifyMatchesAudioByRelativeAndBareName', 0, () => {
      const photoFiles: MediaFileEntry[] = [new MediaFileEntry('photo_e1.jpg', 100)];
      const audioFiles: MediaFileEntry[] = [new MediaFileEntry('rec_1.m4a', 50)];
      const byRelative = classifyMediaFiles(photoFiles, audioFiles,
        new Set<string>(['audio/rec_1.m4a', 'photo_e1.jpg']));
      expect(byRelative.referencedCount).assertEqual(2);
      expect(byRelative.referencedBytes).assertEqual(150);
      expect(byRelative.totalBytes).assertEqual(150);

      const byBare = classifyMediaFiles(photoFiles, audioFiles, new Set<string>(['rec_1.m4a']));
      expect(byBare.referencedCount).assertEqual(1);
      expect(byBare.referencedBytes).assertEqual(50);
      expect(byBare.orphanCount).assertEqual(1);
      expect(byBare.orphanBytes).assertEqual(100);
    })

    it('scanUsageCountsReferencedAndOrphansTogether', 0, () => {
      const fs = new MemoryFs();
      fs.seed(`${PHOTOS_DIR}/photo_e1.jpg`, 100);
      fs.seed(`${PHOTOS_DIR}/photo_orphan.jpg`, 999);
      fs.seed(`${AUDIO_DIR}/rec_orphan.m4a`, 123);
      const entry = makeEntryWithPhotoAndAudio('E1', 'photo_e1.jpg', 'audio/rec_1.m4a');
      const referenced = referencedFilenames([entry], [], []);
      const usage = scanMediaUsage(fs, defaultDirs(), referenced);
      expect(usage.referencedCount).assertEqual(1);
      expect(usage.orphanCount).assertEqual(2);
      expect(usage.orphanBytes).assertEqual(1122);
      expect(usage.totalBytes).assertEqual(1222);
    })

    // ---- 孤儿清理 ----

    it('reclaimKeepsDraftCoverAndEntryFilesWhileRemovingTrueOrphans', 0, () => {
      const fs = new MemoryFs();
      const entry = makeEntryWithPhotoAndAudio('E1', 'photo_e1.jpg', 'audio/rec_1.m4a');
      const draft = makeDraftWithPhoto('D1', 'photo_draft.jpg');
      fs.seed(`${PHOTOS_DIR}/photo_e1.jpg`, 100);
      fs.seed(`${AUDIO_DIR}/rec_1.m4a`, 50);
      fs.seed(`${PHOTOS_DIR}/photo_draft.jpg`, 500);
      fs.seed(`${PHOTOS_DIR}/cover_X.jpg`, 700);
      fs.seed(`${PHOTOS_DIR}/photo_orphan.jpg`, 999);
      fs.seed(`${AUDIO_DIR}/rec_orphan.m4a`, 123);

      const referenced = referencedFilenames([entry], [draft], ['cover_X.jpg']);
      const result = reclaimOrphanFiles(fs, defaultDirs(), referenced);

      expect(result.freedBytes).assertEqual(1122);
      expect(result.deletedFiles.length).assertEqual(2);
      expect(result.deletedFiles.includes('photo_orphan.jpg')).assertTrue();
      expect(result.deletedFiles.includes('rec_orphan.m4a')).assertTrue();
      // 在用的一个没少
      expect(fs.has(`${PHOTOS_DIR}/photo_e1.jpg`)).assertTrue();
      expect(fs.has(`${AUDIO_DIR}/rec_1.m4a`)).assertTrue();
      expect(fs.has(`${PHOTOS_DIR}/photo_draft.jpg`)).assertTrue();
      expect(fs.has(`${PHOTOS_DIR}/cover_X.jpg`)).assertTrue();
      // 孤儿真的没了
      expect(fs.has(`${PHOTOS_DIR}/photo_orphan.jpg`)).assertFalse();
      expect(fs.has(`${AUDIO_DIR}/rec_orphan.m4a`)).assertFalse();
    })

    it('orphanReclaimSafetyGate', 0, () => {
      // 引用表非空 → 允许
      expect(isOrphanReclaimAllowed(5, 0, 0, 0)).assertTrue();
      // 引用表为空：日记、草稿、封面全为零才允许
      expect(isOrphanReclaimAllowed(0, 0, 0, 0)).assertTrue();
      expect(isOrphanReclaimAllowed(0, 1, 0, 0)).assertFalse();
      expect(isOrphanReclaimAllowed(0, 0, 1, 0)).assertFalse();
      expect(isOrphanReclaimAllowed(0, 0, 0, 1)).assertFalse();
      // 读库失败计 -1，落进「不允许」一侧
      expect(isOrphanReclaimAllowed(0, -1, -1, -1)).assertFalse();
    })

    // ---- 验收：删日记后它的文件都没了 ----

    it('deletingEntryRemovesAllItsFilesAndOnlyItsFiles', 0, () => {
      const fs = new MemoryFs();
      const entry1 = makeEntryWithPhotoAndAudio('E1', 'photo_e1.jpg', 'audio/rec_1.m4a');
      const entry2 = makeEntryWithPhotoAndAudio('E2', 'photo_e2.jpg', 'audio/rec_2.m4a');
      fs.seed(`${PHOTOS_DIR}/photo_e1.jpg`, 100);
      fs.seed(`${AUDIO_DIR}/rec_1.m4a`, 50);
      fs.seed(`${PHOTOS_DIR}/photo_e2.jpg`, 200);
      fs.seed(`${AUDIO_DIR}/rec_2.m4a`, 60);

      const deleted = deleteFilesInDir(fs, PHOTOS_DIR, entryPhotoFilenames(entry1)) +
        deleteFilesInDir(fs, AUDIO_DIR, entryAudioFilenames(entry1));

      expect(deleted).assertEqual(2);
      expect(fs.has(`${PHOTOS_DIR}/photo_e1.jpg`)).assertFalse();
      expect(fs.has(`${AUDIO_DIR}/rec_1.m4a`)).assertFalse();
      // 另一篇的文件原样保留
      expect(fs.has(`${PHOTOS_DIR}/photo_e2.jpg`)).assertTrue();
      expect(fs.has(`${AUDIO_DIR}/rec_2.m4a`)).assertTrue();
    })

    it('entryMediaFilenamesCoverLivePhotoTripletAndDedupe', 0, () => {
      const entry = makeEntryWithLivePhoto('E1', 'photo_live.jpg', 'photo_live.mov',
        'photo_live_full.jpg');
      const names = entryPhotoFilenames(entry);
      expect(names.length).assertEqual(3);
      expect(names.includes('photo_live.jpg')).assertTrue();
      expect(names.includes('photo_live.mov')).assertTrue();
      expect(names.includes('photo_live_full.jpg')).assertTrue();
      // 同一张照片插两次只清一次
      const duplicated = new JournalEntry('E2', NOW, NOW, NOW);
      const photo1 = ContentBlock.makePhoto('E2-p1', 'photo_dup.jpg', undefined,
        PhotoPosition.Left, PaperStyle.Polaroid);
      const photo2 = ContentBlock.makePhoto('E2-p2', 'photo_dup.jpg', undefined,
        PhotoPosition.Right, PaperStyle.Polaroid);
      duplicated.setContentBlocks([photo1, photo2], NOW);
      expect(entryPhotoFilenames(duplicated).length).assertEqual(1);
    })

    it('entryAudioFilenamesTakeBareNameOfRelativePaths', 0, () => {
      const entry = makeEntryWithPhotoAndAudio('E1', 'photo_e1.jpg', 'audio/rec_1.m4a');
      expect(entryAudioFilenames(entry)).assertEqual(['rec_1.m4a']);
    })

    it('draftMediaFilenamesIncludePhotosAndAudio', 0, () => {
      const draft = new DraftEntry('D1', NOW, NOW);
      const photo = ContentBlock.makePhoto('D1-photo', 'photo_draft.jpg', 'photo_draft.mov',
        PhotoPosition.Left, PaperStyle.FilmFrame);
      photo.livePhotoStillFilename = 'photo_draft_full.jpg';
      draft.setContentBlocks([photo], NOW);
      draft.audioURLs = ['audio/rec_d.m4a'];
      const photos = draftPhotoFilenames(draft);
      expect(photos.length).assertEqual(3);
      expect(photos.includes('photo_draft.jpg')).assertTrue();
      expect(photos.includes('photo_draft.mov')).assertTrue();
      expect(photos.includes('photo_draft_full.jpg')).assertTrue();
      expect(draftAudioFilenames(draft)).assertEqual(['rec_d.m4a']);
    })

    // ---- 库列容错 ----

    it('parseAudioUrlsToleratesBadJson', 0, () => {
      expect(parseAudioUrls('["audio/a.m4a","audio/b.m4a"]').length).assertEqual(2);
      expect(parseAudioUrls('not json').length).assertEqual(0);
      expect(parseAudioUrls('{"x":1}').length).assertEqual(0);
      // 混入非字符串的只丢坏项
      const mixed = parseAudioUrls('[1,"audio/a.m4a",null,true]');
      expect(mixed.length).assertEqual(1);
      expect(mixed[0]).assertEqual('audio/a.m4a');
    })

    it('deleteFilesInDirSkipsEmptyNamesAndCountsDeleted', 0, () => {
      const fs = new MemoryFs();
      fs.seed(`${PHOTOS_DIR}/a.jpg`, 10);
      fs.seed(`${PHOTOS_DIR}/b.jpg`, 20);
      // 空名字跳过；不存在的文件不算删掉
      expect(deleteFilesInDir(fs, PHOTOS_DIR, ['', 'a.jpg', 'b.jpg'])).assertEqual(2);
      expect(deleteFilesInDir(fs, PHOTOS_DIR, ['a.jpg'])).assertEqual(0);
      expect(fs.has(`${PHOTOS_DIR}/a.jpg`)).assertFalse();
      expect(fs.has(`${PHOTOS_DIR}/b.jpg`)).assertFalse();
    })
  })
}
