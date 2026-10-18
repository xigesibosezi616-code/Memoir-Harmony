/**
 * 相机纯逻辑单测（10_BUILD_MANUAL.md 2.9）：
 * 闪光模式映射 / 变焦夹取 / 预览·拍照档位匹配。
 * 对应 iOS `CameraSession.swift` 的 `FlashSetting` 同款语义。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  FlashSetting,
  flashModeOf,
  clampZoomRatio,
  nearestZoomPreset,
  formatZoomLabel,
  zoomPresetsForRange,
  indexesOfPosition,
  bestPreviewProfile,
  bestPhotoProfile,
  CameraShot,
  MAX_ZOOM_RATIO,
  defaultCameraIndex
} from '../../main/ets/services/CameraSession';
import { camera } from '@kit.CameraKit';

export default function cameraSessionTest() {
  describe('CameraSessionTest', () => {
    it('flashModeOfMapsThreeStates', 0, () => {
      expect(flashModeOf(FlashSetting.Auto) === camera.FlashMode.FLASH_MODE_AUTO).assertTrue();
      expect(flashModeOf(FlashSetting.On) === camera.FlashMode.FLASH_MODE_OPEN).assertTrue();
      expect(flashModeOf(FlashSetting.Off) === camera.FlashMode.FLASH_MODE_CLOSE).assertTrue();
    })

    it('clampZoomRatioClampsToRange', 0, () => {
      expect(clampZoomRatio(1, [1, 5])).assertEqual(1);
      expect(clampZoomRatio(3.5, [1, 5])).assertEqual(3.5);
      expect(clampZoomRatio(10, [1, 5])).assertEqual(5);
      expect(clampZoomRatio(0.5, [1, 5])).assertEqual(1);
    })

    it('clampZoomRatioHandlesReversedOrShortRange', 0, () => {
      // 范围倒着给也能夹对（min/max 内部排序）
      expect(clampZoomRatio(10, [5, 1])).assertEqual(5);
      // 范围不足两位：原样退回（兜底）
      expect(clampZoomRatio(7, [])).assertEqual(7);
      expect(clampZoomRatio(7, [1])).assertEqual(7);
    })

    it('maxZoomRatioFallbackIsFive', 0, () => {
      // 机型范围未知 / 会话异常时的兜底；正常上限走设备 getZoomRatioRange 上沿
      expect(MAX_ZOOM_RATIO).assertEqual(5);
    })

    it('nearestZoomPresetPicksClosest', 0, () => {
      expect(nearestZoomPreset(1.2, [1, 1.5, 3, 5])).assertEqual(1);
      expect(nearestZoomPreset(2.6, [1, 1.5, 3, 5])).assertEqual(3);
      expect(nearestZoomPreset(4.9, [1, 1.5, 3, 5])).assertEqual(5);
      // 正好骑在两档中间偏后：取后一档（严格小于才换档）
      expect(nearestZoomPreset(2.25, [1, 1.5, 3, 5])).assertEqual(3);
    })

    it('nearestZoomPresetHandlesEmptyAndSingle', 0, () => {
      // 空列表退 1×（兜底），单档列表取那一档
      expect(nearestZoomPreset(2.6, [])).assertEqual(1);
      expect(nearestZoomPreset(2.6, [3])).assertEqual(3);
    })

    it('formatZoomLabelTrimsToOneDecimalBelowTen', 0, () => {
      expect(formatZoomLabel(1)).assertEqual('1.0');
      expect(formatZoomLabel(2.64)).assertEqual('2.6');
      expect(formatZoomLabel(9.94)).assertEqual('9.9');
    })

    it('formatZoomLabelRoundsToIntegerAboveTen', 0, () => {
      expect(formatZoomLabel(10.4)).assertEqual('10');
      expect(formatZoomLabel(11.3)).assertEqual('11');
    })

    it('zoomPresetsForRangeAdaptsHuaweiStyle', 0, () => {
      // 全能后摄（超广角到长焦）：0.5 / 1 / 3.5 / 5 / 10
      expect(zoomPresetsForRange(0.5, 11.2)).assertDeepEquals([0.5, 1, 3.5, 5, 10]);
      // 无超广角、上限 5.3：1 / 3.5 / 5
      expect(zoomPresetsForRange(1, 5.3)).assertDeepEquals([1, 3.5, 5]);
      // 前摄这种弱范围：只剩 1×
      expect(zoomPresetsForRange(1, 1)).assertDeepEquals([1]);
      // 有超广角但没长焦：0.5 / 1
      expect(zoomPresetsForRange(0.5, 1)).assertDeepEquals([0.5, 1]);
    })

    it('cameraShotIsMovingPhotoOnlyWithVideo', 0, () => {
      const still = new CameraShot(new ArrayBuffer(8), undefined);
      expect(still.isMovingPhoto).assertFalse();
      const moving = new CameraShot(new ArrayBuffer(8), new ArrayBuffer(8));
      expect(moving.isMovingPhoto).assertTrue();
    })

    it('defaultCameraIndexPrefersBackCamera', 0, () => {
      // 后摄在前：直接选它
      expect(defaultCameraIndex(
        [camera.CameraPosition.CAMERA_POSITION_BACK, camera.CameraPosition.CAMERA_POSITION_FRONT])
      ).assertEqual(0);
      // 后摄在后：跳过前摄找后摄
      expect(defaultCameraIndex(
        [camera.CameraPosition.CAMERA_POSITION_FRONT, camera.CameraPosition.CAMERA_POSITION_BACK])
      ).assertEqual(1);
    })

    it('defaultCameraIndexFallsBackToFirstWithoutBack', 0, () => {
      expect(defaultCameraIndex([camera.CameraPosition.CAMERA_POSITION_FRONT]))
        .assertEqual(0);
    })

    it('defaultCameraIndexReturnsMinusOneWhenEmpty', 0, () => {
      expect(defaultCameraIndex([])).assertEqual(-1);
    })

    it('indexesOfPositionCollectsAllMatching', 0, () => {
      // 同位姿镜头组下标：多输入会话整组挂载用
      const idx = indexesOfPosition(
        [camera.CameraPosition.CAMERA_POSITION_BACK, camera.CameraPosition.CAMERA_POSITION_FRONT,
          camera.CameraPosition.CAMERA_POSITION_BACK],
        camera.CameraPosition.CAMERA_POSITION_BACK);
      expect(idx.length).assertEqual(2);
      expect(idx[0]).assertEqual(0);
      expect(idx[1]).assertEqual(2);
    })

    it('indexesOfPositionEmptyWhenNoMatch', 0, () => {
      expect(indexesOfPosition([camera.CameraPosition.CAMERA_POSITION_FRONT],
        camera.CameraPosition.CAMERA_POSITION_BACK).length).assertEqual(0);
    })

    it('bestPreviewProfileMatchesDisplayShortSide', 0, () => {
      // 官方 faqs-camera-7/12：挑短边最接近显示区的档位（过大合成负担重）
      const small: camera.Profile = {
        format: camera.CameraFormat.CAMERA_FORMAT_YUV_420_SP,
        size: { width: 960, height: 720 }
      };
      const medium: camera.Profile = {
        format: camera.CameraFormat.CAMERA_FORMAT_YUV_420_SP,
        size: { width: 1440, height: 1080 }
      };
      const huge: camera.Profile = {
        format: camera.CameraFormat.CAMERA_FORMAT_YUV_420_SP,
        size: { width: 4000, height: 3000 }
      };
      const picked = bestPreviewProfile([small, medium, huge], 1000);
      if (picked === undefined) {
        expect(false).assertTrue();
      } else {
        // 目标 1000px：720 偏 280、1080 偏 80、3000 偏 2000 → 选 1080
        expect(picked.size.width).assertEqual(1440);
        expect(picked.size.height).assertEqual(1080);
      }
    })

    it('bestPreviewProfileReturnsUndefinedWhenEmpty', 0, () => {
      expect(bestPreviewProfile([], 1000) === undefined).assertTrue();
    })

    it('bestPhotoProfilePicksLargestArea', 0, () => {
      // 实测踩坑：photoProfiles[0] 是列表最小档（Mate X6 上 480×480），
      // 必须挑像素面积最大的一档才是全分辨率出图
      const tiny: camera.Profile = {
        format: camera.CameraFormat.CAMERA_FORMAT_JPEG,
        size: { width: 480, height: 480 }
      };
      const mid: camera.Profile = {
        format: camera.CameraFormat.CAMERA_FORMAT_JPEG,
        size: { width: 4096, height: 3072 }
      };
      const full: camera.Profile = {
        format: camera.CameraFormat.CAMERA_FORMAT_JPEG,
        size: { width: 8192, height: 6144 }
      };
      const picked = bestPhotoProfile([tiny, mid, full]);
      if (picked === undefined) {
        expect(false).assertTrue();
      } else {
        expect(picked.size.width).assertEqual(8192);
        expect(picked.size.height).assertEqual(6144);
      }
    })

    it('bestPhotoProfileReturnsUndefinedWhenEmpty', 0, () => {
      expect(bestPhotoProfile([]) === undefined).assertTrue();
    })
  })
}
