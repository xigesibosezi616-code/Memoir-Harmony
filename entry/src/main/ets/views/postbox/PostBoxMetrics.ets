/**
 * 邮筒页跨机型/形态的版式度量（纯计算，单测覆盖）。
 *
 * 「总体观感和 iOS 保持一致」落成**比例**而不是逐点照抄：iOS 直板
 * （PostBoxPage + OutgoingPile，iPhone 15 Pro 实测）叠纸 188pt = 窗高
 * 22%、邮筒墨迹宽 ≈ 屏宽 37.9%、顶上导航区（安全区+44+8）。我们窗口
 * 更矮（Mate X6 折叠态 783vp）、且悬浮胶囊 Tab 栏比 iOS 系统 Tab 栏
 * 多占内容区，逐点照抄 188 会让叠纸占比 24%、邮筒被挤到 35.7%——
 * 所以叠纸随窗高等比（0.22，夹在 iOS 绝对值 132~188 之间），邮筒拿
 * 剩下的全部（iOS MailboxStage 同构），其余让位值也按窗高分档。
 *
 * 各字段是「距窗口顶/底」的绝对 vp——真机实证 NavBar 内容列
 * padding 从窗口顶 y=0 量起（PROGRESS 5.2 排雷 d），调用方直接喂给
 * 整列 padding，别再加安全区。
 *
 * 矮窗（横屏手机、小窗）：iOS 横屏同样放不下（stage 只剩 16pt），
 * 我们按紧凑档夹取——不崩溃、不挡叠纸，横屏整页怎么排是后续
 * 应用级决策，本模块只保证有下限。
 */

/** 三段间距（iOS VStack spacing 14 × 2） */
export const POSTBOX_SPACING_VP: number = 14;

/** 邮筒页版式（全部 vp；由窗口高 + 上下安全区算出） */
export class PostBoxMetrics {
  /** 内容顶（≈ 邮筒 dome 顶，裁边 PNG 的墨迹顶）距窗口顶 */
  readonly topOffsetVp: number;
  /** 内容底（叠纸整叠底）距窗口底 */
  readonly bottomOffsetVp: number;
  /** 状态行最小高（iOS minHeight 40；用户定改小，单行紧凑） */
  readonly statusMinHeightVp: number;
  /** 叠纸整叠高（含垫纸露边；同一形态内恒定，5.3 投信动画依赖） */
  readonly pileHeightVp: number;
  /** 叠纸头行高 */
  readonly pileHeaderHeightVp: number;
  /** 叠纸一行日记的高 */
  readonly pileRowHeightVp: number;
  /** 叠纸底部渐隐高（rowHeight × 0.6，iOS 同式） */
  readonly pileFadeHeightVp: number;
  /** 邮筒插画区高（剩下的全给邮筒；矮窗下限 0） */
  readonly stageHeightVp: number;
  /** 内容列最大宽：宽屏（折叠展开/平板/2in1）缩进布局居中；窄屏自然满宽 */
  readonly contentMaxWidthVp: number;

  private constructor(topOffsetVp: number, bottomOffsetVp: number, statusMinHeightVp: number,
    pileHeightVp: number, pileHeaderHeightVp: number, pileRowHeightVp: number,
    pileFadeHeightVp: number, stageHeightVp: number, contentMaxWidthVp: number) {
    this.topOffsetVp = topOffsetVp;
    this.bottomOffsetVp = bottomOffsetVp;
    this.statusMinHeightVp = statusMinHeightVp;
    this.pileHeightVp = pileHeightVp;
    this.pileHeaderHeightVp = pileHeaderHeightVp;
    this.pileRowHeightVp = pileRowHeightVp;
    this.pileFadeHeightVp = pileFadeHeightVp;
    this.stageHeightVp = stageHeightVp;
    this.contentMaxWidthVp = contentMaxWidthVp;
  }

  /**
   * @param windowHeightVp 窗口高（ImmersiveChrome 经 AppStorage 发布）
   * @param safeTopVp 顶部避让（沉浸式下窗口顶 = 安全区顶之上）
   * @param safeBottomVp 底部避让（手势条）
   */
  static compute(windowHeightVp: number, safeTopVp: number, safeBottomVp: number): PostBoxMetrics {
    // 矮窗走紧凑档：不留导航区、少给底部，叠纸夹下限，至少装得下不裁纸
    const compact = windowHeightVp < 520;
    const topGap = compact ? 8 : 70;
    const bottomGap = compact ? 56 : 102;
    const statusMin = compact ? 26 : 28;
    // 叠纸 ≈ 窗高 22%（iOS 188/852），夹在 iOS 绝对值域内：矮窗 132、高窗封顶 188
    const pile = Math.min(188, Math.max(132, 0.22 * windowHeightVp));
    // 头行/行高按 iOS 34:40 比例随叠纸缩放（188 时逐字等于 iOS：34/40/24）
    const header = Math.round(pile * 34 / 188);
    const row = (pile - header - 14) / 3.5;
    const fade = row * 0.6;
    const topOffset = safeTopVp + topGap;
    const bottomOffset = safeBottomVp + bottomGap;
    const stage = Math.max(0, windowHeightVp - topOffset - bottomOffset
      - POSTBOX_SPACING_VP * 2 - statusMin - pile);
    return new PostBoxMetrics(topOffset, bottomOffset, statusMin, pile, header, row,
      fade, stage, 430);
  }
}
