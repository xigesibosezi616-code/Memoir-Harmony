/**
 * 相机链路毫秒计时日志：快门→出资产→入库→静图→出纸→视频各段落程，
 * 逐条写 `files/camera_timing.log`（JS hilog 真机不可见，只能落文件 hdc 拉）。
 * 超 128KB 截断重写，防无限增长；自身失败静默，绝不影响拍照主链路。
 */
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

const MAX_LOG_BYTES = 131072;

export class CameraPerfLog {
  static mark(context: common.UIAbilityContext | undefined, line: string): void {
    if (context === undefined) {
      return;
    }
    try {
      const path = `${context.filesDir}/camera_timing.log`;
      try {
        if (fileIo.statSync(path).size > MAX_LOG_BYTES) {
          fileIo.unlinkSync(path);
        }
      } catch (err) {
        // 首次写入还没有该文件
      }
      const file = fileIo.openSync(path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.APPEND);
      try {
        fileIo.writeSync(file.fd, `${Date.now()} ${line}\n`);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (err) {
      // 计时日志自身失败不影响拍照主链路
    }
  }
}
