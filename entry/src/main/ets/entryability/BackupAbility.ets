/**
 * 系统备份恢复扩展（09_OPEN_QUESTIONS.md Q3 结论「可选保底」项，6.6 主线端云协同之外的互补小卡）。
 *
 * 接入 BackupExtensionAbility 后：
 * - 「换机克隆 / 数据克隆」可带走应用数据（未接入时仅迁移安装包）
 * - 系统云备份（设置-云空间-云备份）可带走应用数据——隐私政策
 *   「可随系统"云备份"功能保存于您本人华为账号下的华为云空间」的承诺由此成立
 *
 * 备份范围由 resources/base/profile/backup_config.json 声明：
 * allowToBackupRestore=true，includes/excludes 不配走框架默认清单——
 * el2/database（memoir.db）、el2/base/preferences（memoir_prefs）、
 * el2/base/files（journal_photos、audio）全覆盖；cacheDir 不在默认清单内，
 * 导出 staging / 小图缓存天然不进备份，故无需 excludes。
 *
 * onBackup/onRestore 空实现即可：本应用无备份前后数据加工需求，恢复走
 * 框架默认（fullBackupOnly=false，以 / 为根解压覆盖同名文件），
 * 对库 / 偏好 / 媒体文件均正确。应用本身无法触发备份恢复，
 * 由系统备份恢复框架在克隆 / 云备份 / 设备迁移时调度本扩展。
 */
import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'BackupAbility';

export default class BackupAbility extends BackupExtensionAbility {
  async onBackup(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'onBackup ok');
  }

  async onRestore(bundleVersion: BundleVersion): Promise<void> {
    hilog.info(DOMAIN, TAG, 'onRestore end');
  }
}
