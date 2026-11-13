/**
 * 世界笔友地图页的纯逻辑（U01 决策 14–17、21；iOS `WorldMapPage.swift`）。
 *
 * - 自己起名的那一位：id 恒为 `own`，名片第一张、不在地图上、也算一张邮票
 * - 名片顺序：自己那位在前；世界笔友按离你从近到远（不知道你在哪按名册顺序）
 * - 收件人的名字按名片顺序、用 App 语言的列举方式连起来（「阿远、天野和 McRae」）
 *   —— 鸿蒙没有现成的 CLDR 列举格式，各语言的连接词手写（见 `joinedNames`）
 * - 距离取整到十公里（精确到一公里是假精确），数字与单位跟 App 语言的习惯
 * - 页面本身（地图、墨点、名片）在 `views/postbox/worldmap/`；这里只放能单测的算法
 */
import { PenPal, PenPalCoordinate, penPalLanguageKey } from './PenPal';
import { distanceKilometers } from './PenPalTravel';

/** 自己起名的那一位在收件人集合 / 名片次序里的 id（iOS `WorldMapPage.ownID`） */
export const OWN_PEN_PAL_ID: string = 'own';

/** AppStorage key：这次寄给谁（笔友 id 逗号分隔，自己那位是 own；iOS `@AppStorage("postRecipients")`） */
export const STORAGE_KEY_POST_RECIPIENTS: string = 'postRecipients';

/**
 * 现在有效的收件人：寄不了的世界笔友（不是会员、服务端没备好）去掉，
 * 一位都不剩时退回自己那位（iOS `PostBoxView.recipients` 同款）。
 * `stored` 是 AppStorage 里的原始串（id 逗号分隔，默认 own）。
 */
export function filterRecipients(stored: string, isMember: boolean,
  sendable: Set<string>): Set<string> {
  const ids = new Set<string>();
  for (const id of stored.split(',')) {
    if (id.length === 0) {
      continue;
    }
    if (id === OWN_PEN_PAL_ID || (isMember && sendable.has(id))) {
      ids.add(id);
    }
  }
  if (ids.size === 0) {
    ids.add(OWN_PEN_PAL_ID);
  }
  return ids;
}

/**
 * 现在能寄的世界笔友 id。测试包里开通了测试会员（`TEST_UNLOCK` 假会员）就把
 * 名册里的笔友全算能寄，不等 `GET /penpals` 点头——假会员不交服务器，服务端
 * 名单对不上本机的测试会员（2026-11-12 工单第二项：测试会员一开，世界笔友
 * 跟着开，方便测试）。正式包 `TEST_UNLOCK=false`、`isTestMember` 恒 false，
 * 自动回到只认服务端名单（决策 18 原样）。
 */
export function sendablePenPalIds(roster: PenPal[], isTestMember: boolean,
  serverAvailable: Set<string>): Set<string> {
  if (isTestMember) {
    const ids = new Set<string>();
    for (const penPal of roster) {
      ids.add(penPal.id);
    }
    return ids;
  }
  return serverAvailable;
}

/** 寄出了、还在路上的信：画在航线上，是一个小信封 */
export class InTransitLetter {
  readonly id: string;
  readonly penPalId: string;
  /** 0…1：信在航线上走到哪儿了 */
  readonly progress: number;

  constructor(id: string, penPalId: string, progress: number) {
    this.id = id;
    this.penPalId = penPalId;
    this.progress = Math.min(Math.max(progress, 0), 1);
  }
}

/** 要画航线的一位：收件人（邮戳色、实一点），或正在看、还没选的那位（淡淡一条） */
export class RouteTarget {
  readonly penPal: PenPal;
  readonly isRecipient: boolean;

  constructor(penPal: PenPal, isRecipient: boolean) {
    this.penPal = penPal;
    this.isRecipient = isRecipient;
  }
}

/** 按 id 找一位；找不到返回 null（老信里的笔友可能已不在名册） */
function penPalById(id: string, roster: PenPal[]): PenPal | null {
  for (const penPal of roster) {
    if (penPal.id === id) {
      return penPal;
    }
  }
  return null;
}

/** 名片顺序的世界笔友：按离你从近到远；不知道你在哪按名册顺序（决策 16） */
export function orderedRoster(roster: PenPal[], user: PenPalCoordinate | null): PenPal[] {
  const out = roster.slice();
  if (user === null) {
    return out;
  }
  out.sort((a: PenPal, b: PenPal) =>
    distanceKilometers(user, a.coordinate) - distanceKilometers(user, b.coordinate));
  return out;
}

/** 名片的完整次序（id）：自己那位第一张，然后世界笔友（自己那位不在地图上） */
export function cardIds(roster: PenPal[], user: PenPalCoordinate | null): string[] {
  const ids: string[] = [OWN_PEN_PAL_ID];
  for (const penPal of orderedRoster(roster, user)) {
    ids.push(penPal.id);
  }
  return ids;
}

/**
 * 把几个名字连成一句。单名原样；各语言的连接词手写、贴近 CLDR 的列举格式：
 * - zh：「阿远、天野和 McRae」（两位：「阿远和 McRae」）
 * - en：「Ayu, Amano and McRae」/ ja：「あゆ、天野、マクレイ」（全「、」）
 * - ko：「아유, 아마노 및 맥레이」/ fr：「Ayu, Amano et McRae」/ es：「Ayu, Amano y McRae」
 */
export function joinedNames(names: string[], appLanguage: string): string {
  if (names.length === 0) {
    return '';
  }
  if (names.length === 1) {
    return names[0];
  }
  let separator = ', ';
  let lastJoiner = ' and ';
  switch (appLanguage) {
    case 'zh-Hans':
    case 'zh-Hant':
      separator = '、';
      lastJoiner = '和';
      break;
    case 'ja':
      separator = '、';
      lastJoiner = '、';
      break;
    case 'ko':
      separator = ', ';
      lastJoiner = ' 및 ';
      break;
    case 'fr':
      separator = ', ';
      lastJoiner = ' et ';
      break;
    case 'es':
      separator = ', ';
      lastJoiner = ' y ';
      break;
    default:
      break;
  }
  const head = names.slice(0, names.length - 1).join(separator);
  return `${head}${lastJoiner}${names[names.length - 1]}`;
}

/** 这次寄给谁的名字，按名片顺序（自己那位在前）连成一句（iOS `names(of:)`） */
export function recipientNames(recipients: Set<string>, ownPenPalName: string,
  roster: PenPal[], user: PenPalCoordinate | null, appLanguage: string): string {
  const languageKey = penPalLanguageKey(appLanguage);
  const names: string[] = [];
  for (const id of cardIds(roster, user)) {
    if (!recipients.has(id)) {
      continue;
    }
    if (id === OWN_PEN_PAL_ID) {
      names.push(ownPenPalName);
      continue;
    }
    const penPal = penPalById(id, roster);
    names.push(penPal !== null ? penPal.surname.resolved(languageKey) : id);
  }
  return joinedNames(names, appLanguage);
}

/** 这次要贴几张邮票：一位一张、南极两张，自己那位也算一张（决策 5 / 21） */
export function stampCount(recipients: Set<string>, roster: PenPal[]): number {
  let total = 0;
  for (const id of recipients) {
    if (id === OWN_PEN_PAL_ID) {
      total += 1;
      continue;
    }
    const penPal = penPalById(id, roster);
    total += penPal !== null ? penPal.postage : 1;
  }
  return total;
}

/** 要画航线的：收件人（按名册顺序），加上正在看、还没选的那位（iOS `routeTargets`） */
export function routeTargets(recipients: Set<string>, focusedId: string | null,
  roster: PenPal[]): RouteTarget[] {
  const targets: RouteTarget[] = [];
  for (const penPal of roster) {
    if (recipients.has(penPal.id)) {
      targets.push(new RouteTarget(penPal, true));
    }
  }
  if (focusedId !== null && !recipients.has(focusedId)) {
    const focused = penPalById(focusedId, roster);
    if (focused !== null) {
      targets.push(new RouteTarget(focused, false));
    }
  }
  return targets;
}

/** 一打开地图的中心：你所在的经度、纬度 10°（不知道位置：东经 110°） */
export function startCenter(user: PenPalCoordinate | null): PenPalCoordinate {
  return new PenPalCoordinate(10, user !== null ? user.lon : 110);
}

/** 地图高度占窗高的比例（用户反馈：地图弄小一点，整页不挤） */
export const MAP_HEIGHT_RATIO: number = 0.34;
/** 地图高度的下限 / 上限（vp）：太小看不清地图，太大又回到满屏挤 */
export const MAP_HEIGHT_MIN_VP: number = 140;
export const MAP_HEIGHT_MAX_VP: number = 320;

/** 地图固定高（vp）：窗高的 `MAP_HEIGHT_RATIO`，夹在上下限里（窗高未知按 782.65 兜底） */
export function mapHeightForWindow(windowHeightVp: number): number {
  const height = windowHeightVp > 0 ? windowHeightVp : 782.65;
  return Math.max(MAP_HEIGHT_MIN_VP, Math.min(MAP_HEIGHT_MAX_VP,
    Math.round(MAP_HEIGHT_RATIO * height)));
}

/** 离你多远（公里），取整到十公里（iOS `distanceText` 同款：精确到一公里是假精确） */
export function roundedDistanceKm(user: PenPalCoordinate, target: PenPalCoordinate): number {
  return Math.round(distanceKilometers(user, target) / 10) * 10;
}

/**
 * 「10,790公里」/「10,790 km」—— 数字分组与单位跟 App 语言的习惯
 * （iOS `Measurement.formatted` 同款）。`Intl.NumberFormat` 的单位格式
 * 出问题时退手动拼法，界面不断字。
 */
export function distanceText(km: number, appLanguage: string): string {
  try {
    return new Intl.NumberFormat(appLanguage, {
      style: 'unit',
      unit: 'kilometer',
      unitDisplay: 'short',
      maximumFractionDigits: 0
    }).format(km);
  } catch (err) {
    if (appLanguage === 'zh-Hans' || appLanguage === 'zh-Hant') {
      return `${km}公里`;
    }
    return `${km} km`;
  }
}
