/**
 * 华为系统相机拍照封装（问题四：拍照方式分流）。走 CameraKit 的 cameraPicker
 * （API 11+）：相机交互界面由系统提供，**无需相机权限**（与尺素相机的
 * CameraKit 自装配互为替代，用户在「设置 → 日记 → 拍照方式」里选）。
 *
 * **不配 saveUri**（动态照片必须如此，2026-11-10 用户要求华为相机也能拍动态照片）：
 * - saveUri 是单个沙箱文件，系统相机拍完只往里覆写**一张静态图**——
 *   动态照片的配对视频无处可去，配了 saveUri 动态必丢
 * - 不配 saveUri 时照片按系统相机原生行为存入公共图库（动态模式开启时
 *   即动态照片资产，PHOTO_SUBTYPE=MOVING_PHOTO）；华为相机拍的照片进
 *   图库本就是用户对「用华为相机」的预期
 * - 拿 resultUri 走 `PhotoLibraryPicker.pickedFromUri`（与相册选图完全同链）：
 *   动态照片 → 原样字节提取（原图 + 视频），普通照片 → ≤2048 解码
 * - `resultCode` 0 成功 / -1 失败（用户取消同按失败收场）：调用方静默收场
 */
import { camera, cameraPicker } from '@kit.CameraKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PickedLibraryPhoto, PhotoLibraryPicker } from './PhotoLibraryPicker';

const DOMAIN = 0x0000;
const TAG = 'SystemCameraPicker';

export class SystemCameraPicker {
  /**
   * 拉起华为系统相机拍一张照片（动态照片按原样字节交回，普通照片按解码交回）。
   * 用户取消 / 拍摄失败 / 提取 / 解码失败 → undefined（调用方静默收场）。
   */
  static async pick(context: common.Context): Promise<PickedLibraryPhoto | undefined> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      };
      const result: cameraPicker.PickerResult = await cameraPicker.pick(context,
        [cameraPicker.PickerMediaType.PHOTO], profile);
      if (result.resultCode !== 0 || result.mediaType !== cameraPicker.PickerMediaType.PHOTO) {
        return undefined; // 取消 / 失败：静默收场，不打扰书写
      }
      return await PhotoLibraryPicker.pickedFromUri(context, result.resultUri);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'pick failed: %{public}s', JSON.stringify(err));
      return undefined;
    }
  }
}
