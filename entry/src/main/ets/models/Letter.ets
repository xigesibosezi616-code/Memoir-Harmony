/**
 * 笔友给用户的来信（05_DATA_MODEL.md §6）。对应 iOS `Models/Letter.swift`。
 *
 * - `status` / `triggerKind` **原样存字符串，不过枚举**（导入时可能有不认识的值）
 * - `fromCharacter` / `toName` / `stationery` 都是**寄出那一刻的快照**：
 *   之后改笔友名、改昵称、会员到期都不影响已收到的信
 * - 关联的日记走 `letter_entry` 关联表（多对多）；删日记不删信，读取时滤掉悬空引用
 * - 本地时间字段存毫秒
 */
export enum LetterStatus {
  Pending = 'pending',
  Generating = 'generating',
  Delivered = 'delivered',
  Read = 'read',
  Failed = 'failed'
}

export enum LetterTriggerKind {
  Daily = 'daily',
  Weekly = 'weekly',
  Monthly = 'monthly',
  PerEntry = 'perEntry'
}

/** `stationery` 的取值：火漆封口的信封 + 专属信纸（尺素会员）。undefined = 普通 */
export enum LetterStationeryKind {
  Sealed = 'sealed'
}

/** 寄出时按会员身份定信纸（快照，之后不改） */
export function letterStationery(isMember: boolean): string | undefined {
  return isMember ? LetterStationeryKind.Sealed : undefined;
}

export class Letter {
  readonly id: string;
  /** LetterStatus 的 rawValue，原样存（见文件头） */
  status: string = LetterStatus.Pending;
  /** 回信正文。空 = 还没写好 */
  body: string = '';
  /** 寄出那一刻的笔友名快照，之后改名不影响历史信件 */
  fromCharacter: string = '青鸟';
  /** 寄出那一刻的收信人昵称快照。没昵称时 undefined，抬头只写「致」 */
  toName?: string;
  /** 信纸。寄出那一刻定死，**显示时不实时读会员状态**（R-MEMBER-07） */
  stationery?: string;
  /** LetterTriggerKind 的 rawValue，原样存 */
  triggerKind: string = LetterTriggerKind.Weekly;
  /** 退回原因（仅 failed） */
  errorMessage?: string;
  /** 🔴 **寄出时刻**（点下邮筒那一刻） */
  generatedAt: number;
  /** 🔴 **到达时刻** = 寄出 + [6h, 72h] 均匀随机，寄出时就算好（未来时间）。
   * 老数据可能为空，读取时按 generatedAt 算 */
  deliveredAt?: number;
  readAt?: number;
  updatedAt: number;

  constructor(id: string, generatedAt: number, updatedAt: number) {
    this.id = id;
    this.generatedAt = generatedAt;
    this.updatedAt = updatedAt;
  }

  /** 火漆信：信箱里是一枚封着的信封，第一次打开要拆 */
  get isSealed(): boolean {
    return this.stationery === LetterStationeryKind.Sealed;
  }
}
