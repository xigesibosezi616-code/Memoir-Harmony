/**
 * 地图下面的一张名片（U01 决策 16）。对应 iOS `Views/PostBox/WorldMap/PenPalCard.swift`。
 *
 * 一位笔友是谁、住哪儿、他那里此刻几点、回信要多久，以及「寄给他」。
 * - 纸是「纸」，不跟主题明暗走（LetterPalette）——皮革主题的深色桌面上也是一张米白的名片
 * - 自己起名的那位没有地区码：贴尺素自己的 m. 邮票（和领邮票卡片同一张，2026-10-27 用户定）
 * - 世界笔友贴邮票占位：齿孔边框 + 地区码
 * - 「他那里此刻几点」每分钟滴答一次：时间戳由父组件传入（nowMs）
 */
import { i18n } from '@kit.LocalizationKit';
import { LengthMetrics } from '@kit.ArkUI';
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../../services/LanguageManager';
import { PenPal, PenPalCoordinate, penPalLanguageKey } from '../../../models/PenPal';
import { ReplyTime, replyTimeTo } from '../../../models/PenPalTravel';
import { localCalendar, isDaytimeAt, seasonAt, PenPalSeason } from '../../../models/PenPalLocalTime';
import { roundedDistanceKm, distanceText } from '../../../models/WorldMapLogic';
import { LetterPalette } from '../LetterPalette';
import { MarkStamp } from '../StampPackCard';

/** 名片高度（iOS 同款；宽由父组件给，Swiper 里是 270） */
export const PEN_PAL_CARD_HEIGHT: number = 196;

/** '#RRGGBB' + 透明度 → '#AARRGGBB'（名片上的墨都是半透明的） */
function inkWithAlpha(hex: string, alpha01: number): string {
  const a = Math.round(Math.max(0, Math.min(1, alpha01)) * 255);
  const s = a.toString(16);
  return `#${s.length < 2 ? '0' : ''}${s}${hex.substring(1)}`;
}

@Component
export struct PenPalCard {
  /** 世界笔友；null = 自己起名的那一位（用 ownName） */
  penPal: PenPal | null = null;
  /** 自己起名的那位的名字（penPal 为 null 时用） */
  ownName: string = '';
  userLocation: PenPalCoordinate | null = null;
  @Prop isRecipient: boolean = false;
  isMember: boolean = false;
  /** 这位世界笔友现在能不能寄（总开关开着、且服务端备好了他的人设） */
  canSend: boolean = true;
  palette: LetterPalette = LetterPalette.bamboo;
  /** 邮戳墨色（postmarkInkHex(themeId) 的 '#RRGGBB'） */
  postInk: string = '#B5473A';
  /** 名片上「此刻」的时间戳（父组件每分钟滴答一次） */
  @Prop nowMs: number = 0;
  onToggle: () => void = (): void => {};
  onBecomeMember: () => void = (): void => {};
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = '';
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  private isOwn(): boolean {
    return this.penPal === null;
  }

  private languageKey(): string {
    return penPalLanguageKey(this.appLanguage);
  }

  private title(): string {
    const penPal = this.penPal;
    if (penPal === null) {
      return this.ownName;
    }
    const key = this.languageKey();
    return `${penPal.place.resolved(key)} · ${penPal.surname.resolved(key)}`;
  }

  private shortName(): string {
    const penPal = this.penPal;
    if (penPal === null) {
      return this.ownName;
    }
    return penPal.surname.resolved(this.languageKey());
  }

  /** 国名（按 App 语言）；不认识的地码退原码 */
  private countryName(region: string): string {
    try {
      const name = i18n.System.getDisplayCountry(region, this.appLanguage);
      if (name.length > 0) {
        return name;
      }
    } catch (err) {
      // 不认识的地码：退原码
    }
    return region;
  }

  private subtitle(): Resource | string {
    const penPal = this.penPal;
    if (penPal === null) {
      return $r('app.string.s_514c04d14d');
    }
    const country = this.countryName(penPal.region);
    const place = penPal.place.resolved(this.languageKey());
    // 新加坡、南极：地名就是国名，不重复写
    const where = (penPal.isAntarctic() || country === place) ? '' : country;
    const user = this.userLocation;
    if (user !== null) {
      // 取整到十公里：精确到一公里是假精确（iOS 同款）
      const dist = distanceText(roundedDistanceKm(user, penPal.coordinate), this.appLanguage);
      if (where.length > 0) {
        return $r('app.string.s_aa6bbe90c2', where, dist);
      }
      return $r('app.string.s_74fd338158', dist);
    }
    return where.length > 0 ? where : place;
  }

  private line(): Resource | string {
    const penPal = this.penPal;
    if (penPal === null) {
      return $r('app.string.s_b9c6b284ee');
    }
    return penPal.card.resolved(this.languageKey());
  }

  private replyTime(): ReplyTime {
    const penPal = this.penPal;
    if (penPal === null) {
      return ReplyTime.OwnPenPal;
    }
    return replyTimeTo(penPal, this.userLocation);
  }

  /** 名片上的说法。不报具体小时数，像问邮局「大概几天」（iOS ReplyTime.label） */
  private replyLabel(): Resource {
    switch (this.replyTime()) {
      case ReplyTime.OwnPenPal:
        return $r('app.string.s_a9583b5773');
      case ReplyTime.Near:
        return $r('app.string.s_5e8b69140c');
      case ReplyTime.Far:
        return $r('app.string.s_12316406a8');
      case ReplyTime.Antarctic:
        return $r('app.string.s_2ea1523acf');
      default: // middle / unknownDistance
        return $r('app.string.s_e4eb902363');
    }
  }

  /** 他那里此刻几点（按 App 语言的习惯写，12 / 24 小时制跟着语言走） */
  private clockText(): string {
    const penPal = this.penPal;
    if (penPal === null) {
      return '';
    }
    return new Intl.DateTimeFormat(this.appLanguage,
      { hour: 'numeric', minute: '2-digit', timeZone: penPal.timeZone })
      .format(this.nowMs);
  }

  /** 他那里此刻是不是白天（6–18 点，iOS 同款） */
  private isDaytimeNow(): boolean {
    const penPal = this.penPal;
    if (penPal === null) {
      return true;
    }
    const offsetMs = i18n.getTimeZone(penPal.timeZone).getOffset(this.nowMs);
    return isDaytimeAt(localCalendar(this.nowMs, offsetMs).hour);
  }

  private seasonLabel(season: PenPalSeason): Resource {
    switch (season) {
      case PenPalSeason.Spring:
        return $r('app.string.s_f867d672f3');
      case PenPalSeason.Summer:
        return $r('app.string.s_12d09b2cba');
      case PenPalSeason.Autumn:
        return $r('app.string.s_714152477b');
      default: // Winter
        return $r('app.string.s_7dc6ec1c5c');
    }
  }

  /** 他那里的季节；南半球镜像，回归线之间没有四季不写 */
  private season(): PenPalSeason | null {
    const penPal = this.penPal;
    if (penPal === null) {
      return null;
    }
    const offsetMs = i18n.getTimeZone(penPal.timeZone).getOffset(this.nowMs);
    return seasonAt(penPal.coordinate.lat, localCalendar(this.nowMs, offsetMs).month);
  }

  /** 「当地 15:20 · 春天」/「当地 15:20」 */
  private localNowText(): Resource | string {
    const season = this.season();
    const clock = this.clockText();
    if (season !== null) {
      return $r('app.string.s_5017313c4e', clock, this.seasonLabel(season));
    }
    return $r('app.string.s_9c1c6f5d81', clock);
  }

  build() {
    Column() {
      // 顶部：邮票 + 名字 + 副题
      Row({ space: 12 }) {
        if (this.isOwn()) {
          MarkStamp({ ink: this.postInk, paper: this.palette.paper })
        } else {
          StampPlaceholder({
            code: this.penPal !== null ? this.penPal.region : '',
            ink: this.postInk,
            paper: this.palette.paper
          })
        }
        Column({ space: 4 }) {
          Text(this.title())
            .fontSize(this.theme.headingFont.size)
            .fontWeight(this.theme.headingFont.weight)
            .fontFamily(this.theme.headingFont.family)
            .fontColor(this.palette.ink)
            .maxLines(1)
            .minFontSize(this.theme.headingFont.size * 0.8)
            .maxFontSize(this.theme.headingFont.size)
          Text(this.subtitle())
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(inkWithAlpha(this.palette.ink, 0.6))
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Top)
      .width('100%')

      // 一句话名片
      Text(this.line())
        .fontSize(this.theme.bodyFont.size)
        .fontWeight(this.theme.bodyFont.weight)
        .fontFamily(this.theme.bodyFont.family)
        .fontColor(inkWithAlpha(this.palette.ink, 0.85))
        .lineSpacing(LengthMetrics.vp(3))
        .maxLines(2)
        .margin({ top: 10 })

      Blank()

      // 他那里此刻几点 · 回信要多久
      Row({ space: 12 }) {
        if (!this.isOwn()) {
          Row({ space: 4 }) {
            if (this.isDaytimeNow()) {
              SymbolGlyph($r('sys.symbol.sun_max'))
                .fontSize(this.theme.captionFont.size)
                .fontColor([inkWithAlpha(this.palette.ink, 0.6)])
            } else {
              SymbolGlyph($r('sys.symbol.moon'))
                .fontSize(this.theme.captionFont.size)
                .fontColor([inkWithAlpha(this.palette.ink, 0.6)])
            }
            Text(this.localNowText())
              .fontSize(this.theme.captionFont.size)
              .fontWeight(this.theme.captionFont.weight)
              .fontFamily(this.theme.captionFont.family)
              .fontColor(inkWithAlpha(this.palette.ink, 0.6))
              .maxLines(1)
          }
          .alignItems(VerticalAlign.Center)
        }
        Blank()
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.envelope'))
            .fontSize(this.theme.captionFont.size)
            .fontColor([inkWithAlpha(this.palette.ink, 0.6)])
          Text(this.replyLabel())
            .fontSize(this.theme.captionFont.size)
            .fontWeight(this.theme.captionFont.weight)
            .fontFamily(this.theme.captionFont.family)
            .fontColor(inkWithAlpha(this.palette.ink, 0.6))
            .maxLines(1)
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')

      // 寄给他
      if (!this.isOwn() && !this.canSend) {
        Text($r('app.string.s_587b4e19dc'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(inkWithAlpha(this.palette.ink, 0.4))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 9, bottom: 9 })
          .margin({ top: 10 })
          .borderRadius(100)
          .border({ width: 1, color: inkWithAlpha(this.palette.ink, 0.2) })
      } else if (!this.isOwn() && !this.isMember) {
        Button({ type: ButtonType.Capsule, stateEffect: true }) {
          Text($r('app.string.s_b7ebc71b40', this.shortName()))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.postInk)
        }
        .width('100%')
        .padding({ top: 9, bottom: 9 })
        .margin({ top: 10 })
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: inkWithAlpha(this.postInk, 0.8) })
        .onClick((): void => {
          this.onBecomeMember();
        })
      } else {
        Button({ type: ButtonType.Capsule, stateEffect: true }) {
          Row({ space: 6 }) {
            if (this.isRecipient) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(14)
                .fontColor([this.palette.paper])
            }
            Text(this.isRecipient ? $r('app.string.s_36c6be2be0')
              : $r('app.string.s_213a16c5c5', this.shortName()))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isRecipient ? this.palette.paper : this.postInk)
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ top: 9, bottom: 9 })
        .margin({ top: 10 })
        .backgroundColor(this.isRecipient ? this.postInk : Color.Transparent)
        .border({
          width: 1,
          color: this.isRecipient ? Color.Transparent : inkWithAlpha(this.postInk, 0.8)
        })
        .onClick((): void => {
          this.onToggle();
        })
      }
    }
    .padding(16)
    .height(PEN_PAL_CARD_HEIGHT)
    .backgroundColor(this.palette.paper)
    .borderRadius(3)
    .shadow({ radius: 3, color: 'rgba(0,0,0,0.14)', offsetX: 0, offsetY: 1 })
  }
}

/**
 * 邮票占位：齿孔边框 + 地区码（iOS `StampPlaceholder`，第 3 步换成每位笔友的邮票图）。
 * 齿孔画法同 `MarkStamp`：0.1 短划 + 圆头 = 一圈圆点。
 */
@Component
struct StampPlaceholder {
  code: string = '';
  ink: string = '#B5473A';
  paper: string = '#F7F1E3';
  private ctx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));

  build() {
    Stack() {
      Canvas(this.ctx)
        .width(44)
        .height(52)
        .onReady((): void => {
          this.draw();
        })
      Text(this.code)
        .fontSize(13)
        .fontWeight(600)
        .fontFamily('serif')
        .fontColor(inkWithAlpha(this.ink, 0.8))
    }
    .width(44)
    .height(52)
    .shadow({ radius: 1, color: 'rgba(0,0,0,0.1)', offsetX: 0, offsetY: 0.5 })
  }

  private draw(): void {
    const ctx = this.ctx;
    const w = 44;
    const h = 52;
    // 画布坐标对齐 vp（region 是 px）
    const scale = ctx.width / w;
    ctx.scale(scale, scale);
    // 纸底
    ctx.fillStyle = this.paper;
    ctx.fillRect(0, 0, w, h);
    // 齿孔虚线边（0.1 的短划 + 圆头 = 一圈圆点）
    const dashLw = 2.2;
    ctx.strokeStyle = inkWithAlpha(this.ink, 0.55);
    ctx.lineWidth = dashLw;
    ctx.lineCap = 'round';
    ctx.setLineDash([0.1, 4.2]);
    const dashInset = 1 + dashLw / 2;
    ctx.strokeRect(dashInset, dashInset, w - dashInset * 2, h - dashInset * 2);
    // 内框
    const frameLw = 0.8;
    ctx.strokeStyle = inkWithAlpha(this.ink, 0.4);
    ctx.lineWidth = frameLw;
    ctx.setLineDash([]);
    const frameInset = 6 + frameLw / 2;
    ctx.strokeRect(frameInset, frameInset, w - frameInset * 2, h - frameInset * 2);
  }
}
