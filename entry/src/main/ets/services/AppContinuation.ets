/**
 * 跨设备应用接续（官方 onContinue / onCreate CONTINUATION 链路）的草稿编解码。
 *
 * 场景：X6 上写到一半 → 用户把应用接续到另一台同账号设备 → 继续写。
 * - 源端 onContinue：优先取 AppStorage 里的**实时快照**（ComposeView 防抖发布，
 *   编辑器里没落库的字也在），没有再退回库里的草稿；编码进 wantParam
 * - 对端 onCreate / onNewWant（LaunchReason.CONTINUATION）：解码 → 覆盖本机
 *   草稿表 → 首页就绪后路由进写日记页（ComposeView 从草稿表自动恢复）
 *
 * 约束与取舍：
 * - 官方约束 wantParam 负载 <100KB：纯文本草稿绰绰有余；超出（约五万汉字以上）
 *   源端 REJECT，不静默截断（用户会以为接续成功了）
 * - 照片 / 录音**文件**不随接续迁移（文件资产迁移是后续项）：块引用原样保留，
 *   对端缺文件按既有缺图占位渲染，正文文字完整接续
 * - 解码把 want 参数当不可信输入：逐字段 typeof 校验，坏了返回 null，
 *   绝不让畸形包把 undefined 写进草稿表
 */
import { DraftEntry } from '../models/Draft';

/** wantParam 里装接续草稿 JSON 的 key（自定义，避开系统预置 version / targetDevice / sessionId） */
export const WANT_PARAM_DRAFT: string = 'memoirDraftJson';
/** ComposeView 防抖发布的实时草稿快照（onContinue 优先取它） */
export const STORAGE_KEY_LIVE_DRAFT_JSON: string = 'liveDraftJson';
/** 对端收到的接续草稿 JSON（EntryAbility 暂存，首页就绪后消费） */
export const STORAGE_KEY_CONTINUED_DRAFT_JSON: string = 'continuedDraftJson';
/** 「有待恢复的接续草稿」信号（+1 计数；首页 @Watch 消费后归零） */
export const STORAGE_KEY_CONTINUE_TO_COMPOSE_TICK: string = 'continueToComposeTick';
/** 官方约束 wantParam <100KB，按 UTF-8 字节留余量 */
export const CONTINUATION_PAYLOAD_LIMIT_BYTES: number = 95 * 1024;

/** 接续包的 JSON 形状（JSON.parse 的目标类型；字段全可选，decode 逐个校验） */
interface DraftContinuationRaw {
  id?: string;
  title?: string;
  /** 与日记同一套内容块 JSON，原样透传（含照片 / 录音块的文件名引用） */
  contentBlocksData?: string;
  mood?: string;
  moodColorHex?: string;
  tags?: string[];
  audioURLs?: string[];
  weatherCode?: string;
  weatherInfo?: string;
  locationInfo?: string;
  placeMode?: string;
  manualPlaceName?: string;
  createdAt?: number;
  updatedAt?: number;
}

/** UTF-8 字节数（wantParam 的 100KB 约束按字节算；string.length 只数字符） */
export function utf8ByteLength(text: string): number {
  let bytes = 0;
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code < 0x80) {
      bytes += 1;
    } else if (code < 0x800) {
      bytes += 2;
    } else if (code >= 0xD800 && code <= 0xDBFF) {
      bytes += 4; // 代理对算一个四字节码点，跳过低代理
      i++;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

/** 接续负载是否在官方 wantParam 约束内 */
export function continuationPayloadFits(payload: string): boolean {
  return utf8ByteLength(payload) <= CONTINUATION_PAYLOAD_LIMIT_BYTES;
}

/** DraftEntry → 接续包 JSON（所有字段原样序列化；undefined 字段 JSON.stringify 自动省略） */
export function encodeDraftForContinuation(draft: DraftEntry): string {
  const raw: DraftContinuationRaw = {
    id: draft.id,
    title: draft.title,
    contentBlocksData: draft.contentBlocksData,
    mood: draft.mood,
    moodColorHex: draft.moodColorHex,
    tags: draft.tags,
    audioURLs: draft.audioURLs,
    weatherCode: draft.weatherCode,
    weatherInfo: draft.weatherInfo,
    locationInfo: draft.locationInfo,
    placeMode: draft.placeMode,
    manualPlaceName: draft.manualPlaceName,
    createdAt: draft.createdAt,
    updatedAt: draft.updatedAt
  };
  return JSON.stringify(raw);
}

/**
 * 接续包 JSON → DraftEntry。畸形包（非法 JSON / 缺 id / 缺时间戳）返回 null，
 * 由调用方决定降级（不接续、留在本机状态）。
 */
export function decodeDraftFromContinuation(payload: string): DraftEntry | null {
  if (typeof payload !== 'string' || payload.length === 0) {
    return null;
  }
  let raw: DraftContinuationRaw;
  try {
    raw = JSON.parse(payload) as DraftContinuationRaw;
  } catch (err) {
    return null;
  }
  // id 与时间戳是草稿的骨血，缺一样就没法安全入库
  if (typeof raw.id !== 'string' || raw.id.length === 0) {
    return null;
  }
  if (typeof raw.createdAt !== 'number' || typeof raw.updatedAt !== 'number') {
    return null;
  }
  const draft = new DraftEntry(raw.id, raw.createdAt, raw.updatedAt);
  if (typeof raw.title === 'string') {
    draft.title = raw.title;
  }
  if (typeof raw.contentBlocksData === 'string') {
    draft.contentBlocksData = raw.contentBlocksData;
  }
  if (typeof raw.mood === 'string') {
    draft.mood = raw.mood;
  }
  if (typeof raw.moodColorHex === 'string') {
    draft.moodColorHex = raw.moodColorHex;
  }
  if (Array.isArray(raw.tags)) {
    const tags: string[] = [];
    for (const tag of raw.tags) {
      if (typeof tag === 'string') {
        tags.push(tag);
      }
    }
    draft.tags = tags;
  }
  if (Array.isArray(raw.audioURLs)) {
    const audioURLs: string[] = [];
    for (const url of raw.audioURLs) {
      if (typeof url === 'string') {
        audioURLs.push(url);
      }
    }
    draft.audioURLs = audioURLs;
  }
  if (typeof raw.weatherCode === 'string') {
    draft.weatherCode = raw.weatherCode;
  }
  if (typeof raw.weatherInfo === 'string') {
    draft.weatherInfo = raw.weatherInfo;
  }
  if (typeof raw.locationInfo === 'string') {
    draft.locationInfo = raw.locationInfo;
  }
  if (typeof raw.placeMode === 'string') {
    draft.placeMode = raw.placeMode;
  }
  if (typeof raw.manualPlaceName === 'string') {
    draft.manualPlaceName = raw.manualPlaceName;
  }
  return draft;
}
