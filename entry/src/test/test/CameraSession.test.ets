/**
 * 相机纯逻辑单测（10_BUILD_MANUAL.md 2.9）：
 * 闪光三态循环 / 闪光模式映射 / 变焦夹取。
 * 对应 iOS `CameraSession.swift` 的 `FlashSetting` 同款语义。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  FlashSetting,
  nextFlashSetting,
  flashModeOf,
  clampZoomRatio,
  CameraShot,
  MAX_ZOOM_RATIO
} from '../../main/ets/services/CameraSession';
import { camera } from '@kit.CameraKit';

export default function cameraSessionTest() {
  describe('CameraSessionTest', () => {
    it('nextFlashSettingCyclesAutoOnOff', 0, () => {
      expect(nextFlashSetting(FlashSetting.Auto) === FlashSetting.On).assertTrue();
      expect(nextFlashSetting(FlashSetting.On) === FlashSetting.Off).assertTrue();
      expect(nextFlashSetting(FlashSetting.Off) === FlashSetting.Auto).assertTrue();
    })

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

    it('maxZoomRatioCapIsFive', 0, () => {
      expect(MAX_ZOOM_RATIO).assertEqual(5);
    })

    it('cameraShotIsMovingPhotoOnlyWithVideo', 0, () => {
      const still = new CameraShot(new ArrayBuffer(8), undefined);
      expect(still.isMovingPhoto).assertFalse();
      const moving = new CameraShot(new ArrayBuffer(8), new ArrayBuffer(8));
      expect(moving.isMovingPhoto).assertTrue();
    })
  })
}
