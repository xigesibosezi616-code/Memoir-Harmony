/**
 * 相机照片裁切 / 落盘三件套纯逻辑单测（10_BUILD_MANUAL.md 2.9）。
 * 对应 iOS `PaperCameraView.capture` 的 `squareCropped` 与 `PhotoInsertFlow.insert` 命名。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  SquareRegion,
  centerSquareRegion,
  CameraPhotoFiles
} from '../../main/ets/services/CameraPhotoFiles';

export default function cameraPhotoFilesTest() {
  describe('CameraPhotoFilesTest', () => {
    it('centerSquareRegionLandscapeCentersSquare', 0, () => {
      // 横图 4000×3000：边 3000，x 居中 500，y 0
      const region: SquareRegion = centerSquareRegion(4000, 3000);
      expect(region.side).assertEqual(3000);
      expect(region.x).assertEqual(500);
      expect(region.y).assertEqual(0);
    })

    it('centerSquareRegionPortraitCentersSquare', 0, () => {
      // 竖图 3000×4000：边 3000，x 0，y 居中 500
      const region: SquareRegion = centerSquareRegion(3000, 4000);
      expect(region.side).assertEqual(3000);
      expect(region.x).assertEqual(0);
      expect(region.y).assertEqual(500);
    })

    it('centerSquareRegionSquareIsIdentity', 0, () => {
      const region: SquareRegion = centerSquareRegion(3000, 3000);
      expect(region.side).assertEqual(3000);
      expect(region.x).assertEqual(0);
      expect(region.y).assertEqual(0);
    })

    it('centerSquareRegionOddOffsetsFloor', 0, () => {
      // 奇数差：向下取整（解码区域必须整像素）
      const region: SquareRegion = centerSquareRegion(3001, 2000);
      expect(region.side).assertEqual(2000);
      expect(region.x).assertEqual(500);
      expect(region.y).assertEqual(0);
      expect(Number.isInteger(region.x)).assertTrue();
      expect(Number.isInteger(region.y)).assertTrue();
    })

    it('allFilenamesReturnsDisplayOnlyForStillShot', 0, () => {
      const files = new CameraPhotoFiles('photo_abcd1234.jpg', undefined, undefined);
      const names = files.allFilenames();
      expect(names.length).assertEqual(1);
      expect(names[0] === 'photo_abcd1234.jpg').assertTrue();
    })

    it('allFilenamesReturnsTripleForMovingShot', 0, () => {
      const files = new CameraPhotoFiles('photo_abcd1234.jpg',
        'photo_abcd1234_full.jpg', 'photo_abcd1234.mp4');
      const names = files.allFilenames();
      expect(names.length).assertEqual(3);
      expect(names[0] === 'photo_abcd1234.jpg').assertTrue();
      expect(names[1] === 'photo_abcd1234_full.jpg').assertTrue();
      expect(names[2] === 'photo_abcd1234.mp4').assertTrue();
    })
  })
}
