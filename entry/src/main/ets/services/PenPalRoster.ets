/**
 * 名册装载（U01 世界笔友）：从 `resources/rawfile/penpals.json` 读进内存，
 * 进程内缓存一份。对应 iOS `PenPalRoster.all` / `penPal(id:)`（静态 let 的等价物）。
 *
 * - 文件与 iOS 共用同一份（两端读同一份数据；改名 / 审校只改一处）
 * - 读不出 / 解析失败按空名册：界面照常渲染，只是没有世界笔友（记日志，不崩）
 * - 服务端没部署 / 查不到 `GET /penpals` 时一位都不能寄 —— 与这里无关，
 *   真正能寄哪几位由服务端说了算（U01 决策 18）
 */
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PenPal, parsePenPalRoster } from '../models/PenPal';

const DOMAIN = 0x0000;
const TAG = 'PenPalRoster';

const RAWFILE_NAME = 'penpals.json';

export class PenPalRoster {
  /** 进程内缓存（名册打进包里，内容不会变） */
  private static cached: PenPal[] | null = null;

  /** 读原始 JSON 文本（rawfile 里的 penpals.json）；文件不存在 / 读失败抛错 */
  private static async readRawJson(context: common.Context): Promise<string> {
    const bytes: Uint8Array = await context.resourceManager.getRawFileContent(RAWFILE_NAME);
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }

  /** 全部世界笔友，按名册里的顺序。读不出按空名册（记日志，界面照常） */
  static async all(context: common.Context): Promise<PenPal[]> {
    if (PenPalRoster.cached !== null) {
      return PenPalRoster.cached;
    }
    try {
      const json = await PenPalRoster.readRawJson(context);
      PenPalRoster.cached = parsePenPalRoster(json);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'load penpals.json failed: %{public}s', JSON.stringify(err));
      PenPalRoster.cached = [];
    }
    return PenPalRoster.cached;
  }

  /** 按 id 找一位；找不到返回 null（老信里的笔友可能已不在名册） */
  static async penPal(id: string, context: common.Context): Promise<PenPal | null> {
    const roster = await PenPalRoster.all(context);
    for (const penPal of roster) {
      if (penPal.id === id) {
        return penPal;
      }
    }
    return null;
  }

  /** 只给单测用：清缓存（名册内容不会变，正常流程不需要） */
  static resetCacheForTest(): void {
    PenPalRoster.cached = null;
  }
}
