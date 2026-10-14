/**
 * DraftEntry 纯逻辑单测（10_BUILD_MANUAL.md 1.3 / 05_DATA_MODEL.md §7）。
 *
 * 草稿单独一张表、全局一份；referencedMediaNames 是 1.4 孤儿清理「引用表」
 * 的入口 —— 草稿里的照片 / 录音绝不能被当孤儿删掉（R-DATA-08）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { DraftEntry, PlaceMode } from '../../main/ets/models/Draft';
import { ContentBlock, PhotoPosition, PaperStyle } from '../../main/ets/models/ContentBlock';

export default function draftTest() {
  describe('DraftTest', () => {
    it('contentBlocksEmptyForFreshDraft', 0, () => {
      expect(new DraftEntry('D1', 1, 1).contentBlocks.length).assertEqual(0);
    })

    it('setContentBlocksEncodesAndStampsUpdatedAt', 0, () => {
      const draft = new DraftEntry('D1', 1, 1);
      draft.setContentBlocks([ContentBlock.makeText('b1', '草稿内容')], 777);
      expect(draft.contentBlocksData !== undefined).assertTrue();
      expect(draft.updatedAt).assertEqual(777);
      expect(draft.contentBlocks.length).assertEqual(1);
      expect(draft.contentBlocks[0].text).assertEqual('草稿内容');
    })

    it('referencedMediaNamesCoversPhotoTripletAndAudio', 0, () => {
      const draft = new DraftEntry('D1', 1, 1);
      const photo = ContentBlock.makePhoto('b1', 'still.jpg', 'video.mov',
        PhotoPosition.Left, PaperStyle.Original);
      photo.livePhotoStillFilename = 'uncropped.jpg';
      draft.setContentBlocks([ContentBlock.makeText('t', '文字不算引用'), photo], 2);
      draft.audioURLs = ['audio/a.m4a'];
      const names = draft.referencedMediaNames;
      expect(names.length).assertEqual(5);
      expect(names.includes('still.jpg')).assertTrue();
      expect(names.includes('video.mov')).assertTrue();
      expect(names.includes('uncropped.jpg')).assertTrue();
      expect(names.includes('audio/a.m4a')).assertTrue();
      expect(names.includes('a.m4a')).assertTrue();
    })

    it('referencedMediaNamesEmptyForTextOnlyDraft', 0, () => {
      const draft = new DraftEntry('D1', 1, 1);
      draft.setContentBlocks([ContentBlock.makeText('t', '纯文字')], 2);
      expect(draft.referencedMediaNames.length).assertEqual(0);
    })

    it('placeModeDefaultsToAuto', 0, () => {
      expect(new DraftEntry('D1', 1, 1).placeMode).assertEqual(PlaceMode.Auto);
    })
  })
}
