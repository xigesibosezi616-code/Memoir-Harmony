/**
 * 法律文本：隐私政策 / 用户协议（10_BUILD_MANUAL.md 1.5）。
 * 对应 iOS `Views/Legal/LegalDocument.swift`。
 *
 * 正文放在 `resources/rawfile/legal/<prefix>_<lang>.md`，**不联网也能读**
 * （R-APP-04：审核时网络不通也一定打得开）。
 *
 * 🔴 **改了政策内容就要改 LEGAL_CURRENT_VERSION** —— 用户的同意记录存的是
 * 版本号，版本一变，老用户下次启动会重新看到告知与同意页（R-APP-02）。
 * 不改的话，等于用户从没同意过新版本，而你以为他同意了。
 *
 * ⚠️ **占位说明（Q12）**：当前 rawfile 里是 iOS 版骨架的逐字拷贝
 * （含 Apple / iCloud / Apple 支付等表述，公司注册地址仍是「待填」占位）。
 * 鸿蒙版必须由法务改成鸿蒙实际情况再用，agent 不改写法律文本。
 */
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

export enum LegalDocument {
  Privacy = 'privacy',
  Terms = 'terms'
}

/**
 * 当前生效的政策版本，与两份 md 顶部的「更新日期」一致（R-APP-02）。
 * iOS 当前版本 2026-10-09（隐私政策第七节注销账号改为 App 内自助）。
 */
export const LEGAL_CURRENT_VERSION = '2026-10-09';

/**
 * 是否需要重新征求同意：没同意过（空串）、或政策已更新（存的版本号 ≠ 当前版本）。
 * 存版本号而不是布尔值，政策更新后才能重新弹同意页（R-APP-02）。
 */
export function needsLegalConsent(acceptedVersion: string): boolean {
  return acceptedVersion !== LEGAL_CURRENT_VERSION;
}

/** 文件名前缀，对应 `rawfile/legal/<prefix>_<lang>.md` */
export function legalFilePrefix(doc: LegalDocument): string {
  return doc === LegalDocument.Terms ? 'terms' : 'privacy';
}

/** 导航栏标题资源：「隐私政策」/「用户协议」（iOS `navigationTitle`，译文取自 xcstrings） */
export function legalNavigationTitleRes(doc: LegalDocument): Resource {
  return doc === LegalDocument.Terms
    ? $r('app.string.s_0399ad7167')
    : $r('app.string.s_8c276c1fea');
}

/**
 * 语言回退链：精确匹配 → 同语族 / 英语 → 简体中文兜底（纯函数，单测覆盖）。
 *
 * 例：`zh-Hant` 找不到时退到 `zh-Hans`（看得懂）而不是 `en`；
 * `fr` 找不到时退到 `en`（比中文更可能读懂）再退 `zh-Hans`。
 */
export function legalCandidates(language: string): string[] {
  const chain: string[] = [];
  if (language.length > 0) {
    chain.push(language);
  }
  if (language.startsWith('zh')) {
    chain.push('zh-Hans');
  } else if (language !== 'en') {
    chain.push('en');
  }
  chain.push('zh-Hans');
  // 去重且保序
  const seen: Set<string> = new Set<string>();
  const result: string[] = [];
  for (const candidate of chain) {
    if (!seen.has(candidate)) {
      seen.add(candidate);
      result.push(candidate);
    }
  }
  return result;
}

/**
 * 读取当前 App 语言对应的正文。
 *
 * 找不到时沿回退链退 —— 法律文本一片空白是合规事故，
 * 显示一份看得懂但语言不对的文档，比什么都没有强得多。
 * 全链都没有返回空串（与 iOS `loadMarkdown` 一致；正常不会走到，zh-Hans 恒在包里）。
 */
export async function loadLegalMarkdown(context: Context, doc: LegalDocument, language: string): Promise<string> {
  const prefix: string = legalFilePrefix(doc);
  const candidates: string[] = legalCandidates(language);
  for (const candidate of candidates) {
    const text: string | undefined = await readRawText(context, `legal/${prefix}_${candidate}.md`);
    if (text !== undefined && text.length > 0) {
      return text;
    }
  }
  hilog.error(0x0000, 'LegalDocument', 'loadLegalMarkdown empty: doc=%{public}s lang=%{public}s',
    prefix, language);
  return '';
}

/** 读 rawfile 文本；文件不存在 / 读失败返回 undefined（调用方试下一个候选语言） */
async function readRawText(context: Context, path: string): Promise<string | undefined> {
  try {
    const content: Uint8Array = await context.resourceManager.getRawFileContent(path);
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(content);
  } catch (err) {
    return undefined;
  }
}
