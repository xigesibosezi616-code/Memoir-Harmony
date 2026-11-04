/**
 * 投信动画的几何（纯计算，单测覆盖）。
 * 对应 iOS `Posting/LetterPostingFlight.swift` 里内联的几何，以及
 * `Posting/PostBoxPage.swift` 的 `slotInImage`。
 *
 * - 所有坐标都是**页面（窗口）坐标 vp**（本页沉浸式满窗，两者一致）
 * - `computeFrame`：t 时刻动画要用到的全部位置/大小/透明度，一帧算一次，
 *   渲染层（LetterPostingFlight）只照着摆，不再自己算 —— 手感数值集中在
 *   这里被单测钉死（R-POST-08：约 3 秒、平滑不回弹）
 */
import { OutgoingItem } from './PostBoxLogic';
import { LetterPostingTimeline } from './LetterPostingTimeline';

/** 页面坐标里的矩形（vp） */
export interface RectF {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** 邮筒插画（三主题同一张线稿）的宽高比，588×1410 */
export const MAILBOX_IMAGE_ASPECT: number = 588 / 1410;

/**
 * 投信口的开口在邮筒图上的位置（按图的宽高取比例）。三个主题的邮筒是
 * 同一张线稿，位置一样（iOS PostBoxPage.slotInImage 同值）。
 */
export const SLOT_IN_IMAGE_X: number = 0.317;
export const SLOT_IN_IMAGE_Y: number = 0.19;
export const SLOT_IN_IMAGE_W: number = 0.367;
export const SLOT_IN_IMAGE_H: number = 0.024;

/** 信封宽高比（接近常见的西式信封，iOS SealedEnvelope.aspect 同值） */
export const ENVELOPE_ASPECT: number = 1.56;

/**
 * 正在投的这一封：投信动画要用的全部东西（值快照，点下邮筒那一刻定下；
 * iOS PostingRun）。t 不在里面——那是逐帧推进的状态，归页面持有。
 */
export class PostingRun {
  /** 那叠日记收拢之前的样子 */
  readonly items: OutgoingItem[];
  /** 收拢时取消勾选的那几篇（快照，投出后 excluded 清空，动画里还要画灰） */
  readonly excludedIds: string[];
  /** 会员才盖火漆，印面是自己昵称的首字 */
  readonly hasSeal: boolean;
  /** 火漆上压的字（「素」兜底） */
  readonly sealMark: string;

  constructor(items: OutgoingItem[], excludedIds: string[], hasSeal: boolean, sealMark: string) {
    this.items = items;
    this.excludedIds = excludedIds;
    this.hasSeal = hasSeal;
    this.sealMark = sealMark;
  }

  /**
   * 火漆印面（iOS WaxSeal.initial）：取名字的第一个字，拉丁字母转大写；
   * 没名字、或以符号 / 数字开头的压「素」—— 火漆上压个表情不像样。
   */
  static sealMarkOf(displayName: string | undefined): string {
    const trimmed = displayName !== undefined ? displayName.trim() : '';
    if (trimmed.length === 0) {
      return '素';
    }
    const first = trimmed.charAt(0);
    // Unicode 字母（\p{L}）；符号 / 数字 / emoji 不上印
    if (!/^[\p{L}]/u.test(first)) {
      return '素';
    }
    return first.toUpperCase();
  }
}

/** t 时刻投信动画的一帧（全部页面坐标 vp；渲染层只读） */
export class FlightFrame {
  /** 投信口里翻板露出的黑：口子矩形（不可见时高 0） */
  gapVisible: boolean = false;
  gapX: number = 0;
  gapY: number = 0;
  gapWidth: number = 0;
  gapHeight: number = 0;
  /** 信封 */
  envX: number = 0;
  envY: number = 0;
  envWidth: number = 0;
  envHeight: number = 0;
  envOpacity: number = 0;
  /** 举到跟前时上沿往里倒（绕上沿的 3D 倾角，度） */
  envTiltDeg: number = 0;
  /** 信封拆信进度（1 = 信纸在外 → 0 = 封好） */
  envProgress: number = 1;
  /** 火漆按下去到哪（0 = 还没盖；非会员恒 0） */
  sealPress: number = 0;
  /** 收拢阶段：那叠日记缩成的那页信纸（rect + 透明度） */
  sheetVisible: boolean = false;
  sheetX: number = 0;
  sheetY: number = 0;
  sheetWidth: number = 0;
  sheetHeight: number = 0;
  sheetOpacity: number = 0;
  /** 收拢阶段：那叠日记本身的缩放 / 位移 / 透明度（往 sheetRect 收） */
  pileScaleX: number = 1;
  pileScaleY: number = 1;
  pileOffsetX: number = 0;
  pileOffsetY: number = 0;
  pileOpacity: number = 1;
  /** 下面那块（邮戳 / 在路上）信进了邮筒才淡出来，像刚盖上去略大一点落定 */
  revealOpacity: number = 1;
  revealScale: number = 1;
}

/** aspect = 宽/高 的内容 contain 进 container（居中，不裁切）后的实际绘制矩形 */
export function fitRectInRect(container: RectF, aspect: number): RectF {
  if (container.width <= 0 || container.height <= 0 || aspect <= 0) {
    return { x: container.x, y: container.y, width: 0, height: 0 };
  }
  let w = container.width;
  let h = w / aspect;
  if (h > container.height) {
    h = container.height;
    w = h * aspect;
  }
  return {
    x: container.x + (container.width - w) / 2,
    y: container.y + (container.height - h) / 2,
    width: w,
    height: h
  };
}

/** 邮筒插画绘制矩形 → 投信口的开口矩形（SLOT_IN_IMAGE_* 比例） */
export function slotRectOf(mailboxDrawn: RectF): RectF {
  return {
    x: mailboxDrawn.x + SLOT_IN_IMAGE_X * mailboxDrawn.width,
    y: mailboxDrawn.y + SLOT_IN_IMAGE_Y * mailboxDrawn.height,
    width: SLOT_IN_IMAGE_W * mailboxDrawn.width,
    height: SLOT_IN_IMAGE_H * mailboxDrawn.height
  };
}

/**
 * t 时刻的一帧。pileRect = 那叠日记（OutgoingPile）的窗口矩形，
 * slotRect = 投信口矩形（都点下邮筒那一刻量好，动画期间版式恒定）。
 */
export function computeFlightFrame(t: number, pileRect: RectF, slotRect: RectF,
  hasSeal: boolean): FlightFrame {
  const T = LetterPostingTimeline;
  const frame = new FlightFrame();

  // 信封在原地的大小：底边和那叠日记的底边对齐，抽出来的信纸往上冒
  const homeWidth = Math.min(pileRect.width * 0.6, 220);
  const homeHeight = homeWidth / ENVELOPE_ASPECT;
  const homeX = pileRect.x + pileRect.width / 2 - homeWidth / 2;
  const homeBottomY = pileRect.y + pileRect.height;
  // 到投信口时的大小：比开口窄一圈（往里倒时下沿离人近、看着会变宽）
  const endWidth = slotRect.width * 0.7;
  const endHeight = endWidth / ENVELOPE_ASPECT;

  const rise = T.smooth(t, T.RISE_START, T.RISE_END);
  const insert = T.smooth(t, T.INSERT_START, T.INSERT_END);

  const envWidth = homeWidth + (endWidth - homeWidth) * rise;
  const envHeight = envWidth / ENVELOPE_ASPECT;
  // 路径：原地 → 投信口正下方（上沿贴口子），推入时整封往口子里去
  const homeCenterX = pileRect.x + pileRect.width / 2;
  const homeCenterY = homeBottomY - homeHeight / 2;
  const approachCenterX = slotRect.x + slotRect.width / 2;
  const approachCenterY = slotRect.y + slotRect.height + endHeight / 2;
  const envCenterX = homeCenterX + (approachCenterX - homeCenterX) * rise;
  const envCenterY = homeCenterY + (approachCenterY - homeCenterY) * rise - insert * endHeight * 1.25;

  frame.envWidth = envWidth;
  frame.envHeight = envHeight;
  frame.envX = envCenterX - envWidth / 2;
  frame.envY = envCenterY - envHeight / 2;
  // 信封从下面托上来，接住收拢好的信纸
  const liftIn = T.smooth(t, 0.08, T.GATHER_END);
  frame.envY += (1 - liftIn) * homeHeight * 0.5;
  frame.envOpacity = T.smooth(t, 0.08, 0.26);
  // 举到跟前时上沿开始往里倒，推进去时倒得更多
  frame.envTiltDeg = 25 * T.smooth(t, T.RISE_START + 0.25, T.RISE_END) + 30 * insert;
  frame.envProgress = T.envelopeProgress(t);
  frame.sealPress = hasSeal ? T.linear(t, T.SEAL_START, T.SEAL_END) : 0;

  // 投信口里的翻板：信顶进来时被推开，露出里面的黑；信进去了就落回去
  const open = T.smooth(t, T.INSERT_START, T.INSERT_START + 0.14);
  const fall = T.linear(t, T.FLAP_FALL_START, T.FLAP_FALL_END);
  const amount = open * (1 - fall * fall);
  frame.gapVisible = amount > 0.001;
  frame.gapWidth = slotRect.width;
  frame.gapHeight = slotRect.height * amount;
  frame.gapX = slotRect.x;
  frame.gapY = slotRect.y + slotRect.height - frame.gapHeight;

  // 那叠日记收拢成信封上方那页信纸：字先淡掉，纸缩到信纸的位置和大小
  const g = T.smooth(t, T.GATHER_START, T.GATHER_END);
  // 拆信 progress = 1 时信纸的位置（SealedEnvelope：宽高 0.9，上移 0.8 个信封高）
  const targetX = homeX + homeWidth * 0.05;
  const targetY = homeBottomY - homeHeight + homeHeight * 0.05 - homeHeight * 0.8;
  const targetW = homeWidth * 0.9;
  const targetH = homeHeight * 0.9;
  const sheetWidth = pileRect.width + (targetW - pileRect.width) * g;
  const sheetHeight = pileRect.height + (targetH - pileRect.height) * g;
  const sheetX = pileRect.x + (targetX - pileRect.x) * g;
  const sheetY = pileRect.y + (targetY - pileRect.y) * g;
  frame.sheetVisible = t < T.GATHER_END;
  frame.sheetX = sheetX;
  frame.sheetY = sheetY;
  frame.sheetWidth = sheetWidth;
  frame.sheetHeight = sheetHeight;
  frame.sheetOpacity = T.smooth(t, 0.02, 0.14);
  // 那叠日记：缩到 sheetRect 的大小、跟着挪到 sheetRect 的位置、淡掉
  const pileCenterX = pileRect.x + pileRect.width / 2;
  const pileCenterY = pileRect.y + pileRect.height / 2;
  const sheetCenterX = sheetX + sheetWidth / 2;
  const sheetCenterY = sheetY + sheetHeight / 2;
  frame.pileScaleX = sheetWidth / Math.max(pileRect.width, 1);
  frame.pileScaleY = sheetHeight / Math.max(pileRect.height, 1);
  frame.pileOffsetX = sheetCenterX - pileCenterX;
  frame.pileOffsetY = sheetCenterY - pileCenterY;
  frame.pileOpacity = 1 - T.smooth(t, 0, 0.14);

  // 下面那块：信进了邮筒（翻板落回）才把邮戳盖出来，略大一点落定
  const reveal = T.smooth(t, T.FLAP_FALL_START, T.TOTAL);
  frame.revealOpacity = reveal;
  frame.revealScale = 1 + 0.05 * (1 - reveal);
  return frame;
}
