/**
 * 语言标签解析（纯函数，无设备依赖，hypium 单测覆盖）。
 *
 * 首启时按系统语言挑一个受支持的语言（R-LANG-02）：
 * - 中文看 script（zh-Hant-TW → 繁）；无 script 看地区（TW/HK/MO → 繁，其余简）
 * - 其余语言在七种名单里就用（en / ja / ko / fr / es，按语言码匹配，地区不限）
 * - 都不在 → 英语（不是中文）
 *
 * 拆成纯函数是为了不依赖 `i18n.System`（设备 API），单测能直接跑解析逻辑。
 */

/** 解析结果：命中的受支持语言，或 null（这条标签不在名单里） */
export function resolveSupportedFromTag(tag: string, supported: string[]): string | null {
  const parts = tag.split('-');
  if (parts.length === 0) {
    return null;
  }
  // BCP 47：第一段是主语言码（zh / en / pt …）
  const language = parts[0].toLowerCase();
  if (language !== 'zh') {
    // 名单里存的是 'en' / 'ja' / 'ko' / 'fr' / 'es' / 'zh-Hans' / 'zh-Hant'
    // 非中文按「语言码在名单里」匹配（'en-US' → 'en'）
    return supported.includes(language) ? language : null;
  }
  // 中文：script 最可信（zh-Hant-TW / zh-Hans-CN）
  const script = parts.length >= 2 && parts[1].length === 4 ? parts[1] : '';
  if (script !== '') {
    return script.toLowerCase() === 'hant' ? 'zh-Hant' : 'zh-Hans';
  }
  // 无 script 看地区：港澳台按繁体，其余简体
  const region = parts.length >= 2 ? parts[1].toUpperCase() : '';
  return ['TW', 'HK', 'MO'].includes(region) ? 'zh-Hant' : 'zh-Hans';
}

/**
 * 按用户在系统里排的偏好顺序，找第一个受支持的语言。
 * 全都不在名单里 → `'en'`（R-LANG-02：一个看不懂中文的用户，
 * 看到满屏中文只会直接删 App）。
 */
export function resolveInitialLanguage(preferredList: string[], supported: string[]): string {
  for (const tag of preferredList) {
    const hit = resolveSupportedFromTag(tag, supported);
    if (hit !== null) {
      return hit;
    }
  }
  return 'en';
}
