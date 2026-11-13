/**
 * 世界笔友名册（U01「世界笔友」）。对应 iOS `Services/PenPals/PenPalRoster.swift`。
 *
 * - 名册是打进包里的 `resources/rawfile/penpals.json` —— **iOS 与鸿蒙用同一份文件**，
 *   两端读同一份数据，不靠文字转述；人设与提示词只在服务端，这里只有
 *   客户端显示和算路程要用的东西
 * - `LocalizedText` 按 App 语言取（`zh-Hans / zh-Hant / en / ja / ko / fr / es`），
 *   没有这种语言退英文，再退 `default`（iOS `resolved(for:)` 同款）
 * - 姓、地名、名片都是「一位笔友一份多语言文字」，解析后字段固定，
 *   不留动态键（ArkTS 禁 Record 动态取值）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'PenPalModel';

/** 名册里的一位世界笔友 */
export class PenPal {
  /** 稳定 id，和服务端人设、letter.pen_pal_id、备份包一致。定了就不改 */
  readonly id: string;
  /** 只有姓，按 App 语言取（如朴 / 박、陈 / Tan） */
  readonly surname: LocalizedText;
  /** ISO 3166 地区码；`AQ` 是南极 */
  readonly region: string;
  readonly coordinate: PenPalCoordinate;
  /** IANA 时区，名片上「他那里此刻几点」用 */
  readonly timeZone: string;
  /** 他写信用的语言（BCP 47，如 en / ja / zh-Hans） */
  readonly nativeLanguage: string;
  /** 寄给他要贴几张邮票（南极 2 张，其余 1 张） */
  readonly postage: number;
  /** 名片上的地名（「斯图尔特岛」） */
  readonly place: LocalizedText;
  /** 名片上的一句话 */
  readonly card: LocalizedText;

  constructor(id: string, surname: LocalizedText, region: string,
    coordinate: PenPalCoordinate, timeZone: string, nativeLanguage: string,
    postage: number, place: LocalizedText, card: LocalizedText) {
    this.id = id;
    this.surname = surname;
    this.region = region;
    this.coordinate = coordinate;
    this.timeZone = timeZone;
    this.nativeLanguage = nativeLanguage;
    this.postage = postage;
    this.place = place;
    this.card = card;
  }

  /** 南极那位：回信固定 72–120 小时、邮票 2 张 */
  isAntarctic(): boolean {
    return this.region === 'AQ';
  }
}

export class PenPalCoordinate {
  readonly lat: number;
  readonly lon: number;

  constructor(lat: number, lon: number) {
    this.lat = lat;
    this.lon = lon;
  }
}

/**
 * 名册里的多语言文字：`{"zh-Hans": "…", "en": "…", "default": "…"}`。
 * 解析时摊平成固定字段（七种语言 + default），`resolved` 按语言取，
 * 没有退英文，再退 default，都空返回 ''。
 */
export class LocalizedText {
  readonly default: string;
  readonly zhHans: string;
  readonly zhHant: string;
  readonly en: string;
  readonly ja: string;
  readonly ko: string;
  readonly fr: string;
  readonly es: string;

  constructor(defaultText: string, zhHans: string, zhHant: string, en: string,
    ja: string, ko: string, fr: string, es: string) {
    this.default = defaultText;
    this.zhHans = zhHans;
    this.zhHant = zhHant;
    this.en = en;
    this.ja = ja;
    this.ko = ko;
    this.fr = fr;
    this.es = es;
  }

  /** 按语言键取：语言 → 英文 → default → 第一个非空 → ''（iOS resolved(for:) 同款链） */
  resolved(languageKey: string): string {
    const primary = this.valueFor(languageKey);
    if (primary.length > 0) {
      return primary;
    }
    if (this.en.length > 0) {
      return this.en;
    }
    if (this.default.length > 0) {
      return this.default;
    }
    return this.firstNonEmpty();
  }

  private valueFor(languageKey: string): string {
    switch (languageKey) {
      case 'zh-Hans':
        return this.zhHans;
      case 'zh-Hant':
        return this.zhHant;
      case 'en':
        return this.en;
      case 'ja':
        return this.ja;
      case 'ko':
        return this.ko;
      case 'fr':
        return this.fr;
      case 'es':
        return this.es;
      default:
        return '';
    }
  }

  private firstNonEmpty(): string {
    const candidates: string[] = [this.default, this.zhHans, this.zhHant,
      this.en, this.ja, this.ko, this.fr, this.es];
    for (const text of candidates) {
      if (text.length > 0) {
        return text;
      }
    }
    return '';
  }
}

/** App 语言 id（LanguageManager 存的规范写法）→ 名册语言键。不在七种名单里退 'en' */
export function penPalLanguageKey(languageId: string): string {
  const normalized = languageId.toLowerCase();
  if (normalized === 'zh-hans') {
    return 'zh-Hans';
  }
  if (normalized === 'zh-hant') {
    return 'zh-Hant';
  }
  if (normalized === 'en') {
    return 'en';
  }
  if (normalized === 'ja') {
    return 'ja';
  }
  if (normalized === 'ko') {
    return 'ko';
  }
  if (normalized === 'fr') {
    return 'fr';
  }
  if (normalized === 'es') {
    return 'es';
  }
  // zh 主区（zh-CN / zh 等）当简中，其余不认识的退英文
  if (normalized.startsWith('zh')) {
    return normalized.includes('hant') || normalized.includes('tw') ||
      normalized.includes('hk') ? 'zh-Hant' : 'zh-Hans';
  }
  return 'en';
}

// ---- 解析（照 ContentBlock / BackupFormat 的 Record 模式：JSON.parse 一次 cast，逐字段校验）----

/** 从 JSON 对象里取 string 字段，类型不对 / 缺失返回 undefined */
function fieldString(rec: Record<string, Object>, key: string): string | undefined {
  const v: Object | undefined = rec[key];
  return typeof v === 'string' ? v : undefined;
}

/** 从 JSON 对象里取 number 字段，类型不对 / 缺失返回 undefined */
function fieldNumber(rec: Record<string, Object>, key: string): number | undefined {
  const v: Object | undefined = rec[key];
  return typeof v === 'number' ? v : undefined;
}

/** raw → LocalizedText。缺这个字段 / 类型不对当空文字（resolved 返回 ''） */
function localizedTextFromRaw(parent: Record<string, Object>, key: string): LocalizedText {
  const raw: Object | undefined = parent[key];
  if (raw === null || raw === undefined || typeof raw !== 'object') {
    return new LocalizedText('', '', '', '', '', '', '', '');
  }
  const rec = raw as Record<string, Object>;
  return new LocalizedText(
    fieldString(rec, 'default') ?? '',
    fieldString(rec, 'zh-Hans') ?? '',
    fieldString(rec, 'zh-Hant') ?? '',
    fieldString(rec, 'en') ?? '',
    fieldString(rec, 'ja') ?? '',
    fieldString(rec, 'ko') ?? '',
    fieldString(rec, 'fr') ?? '',
    fieldString(rec, 'es') ?? '');
}

function requireString(value: string | undefined, field: string): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`${field} missing or not a string`);
  }
  return value;
}

/**
 * 名册 JSON → 全部世界笔友（按文件里的顺序）。
 * 坏 JSON / 缺必填字段抛错，由调用方记日志、当空名册（界面照常，只是没有世界笔友）。
 */
export function parsePenPalRoster(json: string): PenPal[] {
  const file = JSON.parse(json) as Record<string, Object>;
  if (file === null || typeof file !== 'object' || !Array.isArray(file['penPals'])) {
    throw new Error('penpals.json: penPals missing or not an array');
  }
  const items: Object[] = file['penPals'] as Object[];
  const out: PenPal[] = [];
  for (const item of items) {
    if (item === null || typeof item !== 'object') {
      throw new Error('penpals.json: penPal item is not an object');
    }
    const raw = item as Record<string, Object>;
    const coordRaw: Object | undefined = raw['coordinate'];
    if (coordRaw === null || coordRaw === undefined || typeof coordRaw !== 'object') {
      throw new Error(`penpals.json: ${String(raw['id'])} coordinate invalid`);
    }
    const coord = coordRaw as Record<string, Object>;
    const lat = fieldNumber(coord, 'lat');
    const lon = fieldNumber(coord, 'lon');
    if (lat === undefined || lon === undefined) {
      throw new Error(`penpals.json: ${String(raw['id'])} coordinate invalid`);
    }
    const postage = fieldNumber(raw, 'postage') ?? 1;
    out.push(new PenPal(
      requireString(fieldString(raw, 'id'), 'penPal.id'),
      localizedTextFromRaw(raw, 'surname'),
      requireString(fieldString(raw, 'region'), 'penPal.region'),
      new PenPalCoordinate(lat, lon),
      requireString(fieldString(raw, 'timeZone'), 'penPal.timeZone'),
      requireString(fieldString(raw, 'nativeLanguage'), 'penPal.nativeLanguage'),
      postage,
      localizedTextFromRaw(raw, 'place'),
      localizedTextFromRaw(raw, 'card')));
  }
  return out;
}

/** 解析失败兜底：记日志返回空名册（调 .all 的地方界面照常渲染） */
export function parsePenPalRosterQuietly(json: string): PenPal[] {
  try {
    return parsePenPalRoster(json);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'parse penpals.json failed: %{public}s', JSON.stringify(err));
    return [];
  }
}
