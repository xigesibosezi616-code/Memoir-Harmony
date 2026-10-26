/**
 * 会员信件的用料：信封、内衬、信纸、格线。跟着主题换（10_BUILD_MANUAL.md 5.2）。
 * 对应 iOS `Views/PostBox/Envelope/LetterPalette.swift`，色值逐字一致（跨端视觉契约）。
 *
 * 信纸是「纸」，不跟主题的明暗走 —— 皮革主题是深色，但摊在皮桌面上的那张信纸还是米白的。
 * 半透明色（rule 的 opacity）已预算成 8 位 ARGB 写死，页面里不再叠透明度。
 */

/** 信件用料（纸 / 墨 / 格线 / 信封 / 内衬） */
export class LetterPalette {
  /** 信纸 */
  readonly paper: string;
  /** 字 */
  readonly ink: string;
  /** 格线（已含透明度） */
  readonly rule: string;
  /** 信封外面 */
  readonly envelope: string;
  /** 信封折边的线和阴影 */
  readonly envelopeEdge: string;
  /** 信封内衬（拆开才看得见的那一层；勾选的对勾也用它——一笔红） */
  readonly liner: string;
  /** 信纸四周有没有一圈细框（八行笺那样） */
  readonly framed: boolean;

  constructor(paper: string, ink: string, rule: string, envelope: string,
    envelopeEdge: string, liner: string, framed: boolean) {
    this.paper = paper;
    this.ink = ink;
    this.rule = rule;
    this.envelope = envelope;
    this.envelopeEdge = envelopeEdge;
    this.liner = liner;
    this.framed = framed;
  }

  static of(themeId: string): LetterPalette {
    switch (themeId) {
      case 'leather':
        return LetterPalette.leather;
      case 'kent':
        return LetterPalette.kent;
      default:
        return LetterPalette.bamboo;
    }
  }

  /** 素笺：米色信封，朱红内衬，红格信笺 */
  static readonly bamboo: LetterPalette = new LetterPalette(
    '#F7F1E3', '#3D3428', '#52B5473A', '#EEE5D3', '#BFAE90', '#B65A45', true);

  /** 皮革：牛皮纸信封，深棕内衬，米白信纸配赭色格线 */
  static readonly leather: LetterPalette = new LetterPalette(
    '#F1E8D4', '#2E241B', '#598A6A45', '#B8935F', '#7E5F38', '#3B2A1E', false);

  /** 肯特：白信封，藏青内衬，白纸灰蓝格线 */
  static readonly kent: LetterPalette = new LetterPalette(
    '#FDFDFB', '#1A1A1A', '#597C8FA6', '#F6F6F3', '#CFCFC8', '#2F4A6B', false);
}
