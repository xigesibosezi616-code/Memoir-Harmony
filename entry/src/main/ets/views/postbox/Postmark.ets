/**
 * 一枚邮戳（日戳）：两道圆圈，中间一条横带压着寄出日期，上沿一圈是寄出的地点
 * （iOS Postmark.swift 权威，逐字 ArcText 弧排）。没有地点的只盖日期。
 * 油墨颜色跟着主题走（素笺朱红 / 肯特灰蓝 / 皮革浅棕），盖歪一点（−9°）、
 * 油墨不那么实——像真盖上去的。
 */
import { postmarkDateText } from '../../models/PostBoxLogic';

/** 弧排上的一个字 + 它转到的角度（度） */
class ArcChar {
  readonly char: string;
  readonly angleDeg: number;

  constructor(char: string, angleDeg: number) {
    this.char = char;
    this.angleDeg = angleDeg;
  }
}

@Component
export struct Postmark {
  /** 寄出时刻（毫秒） */
  @Prop dateMs: number = 0;
  /** 寄出地点（PostBoxLogic.postmarkPlace 的产物）；空串只盖日期 */
  @Prop place: string = '';
  /** 油墨色（PostBoxLogic.postmarkInkHex 的产物，形如 '#B5473A'） */
  @Prop ink: string = '#B5473A';
  /** 直径（vp）；iOS InTransitNote 用 86 */
  @Prop stampSizeVp: number = 84;

  private lineWidthVp(): number {
    return Math.max(1, this.stampSizeVp * 0.02);
  }

  private arcFontSizeVp(): number {
    return this.stampSizeVp * 0.12;
  }

  private arcRadiusVp(): number {
    return this.stampSizeVp / 2 * 0.64;
  }

  /** 上沿地名弧排（iOS ArcText 同款）：字宽按方块字 / 拉丁字母估算，逐字摆角度 */
  private arcChars(): ArcChar[] {
    const chars = Array.from(this.place);
    const fontSize = this.arcFontSizeVp();
    const radius = this.arcRadiusVp();
    const advances: number[] = [];
    for (const ch of chars) {
      advances.push(ch.charCodeAt(0) >= 0x2E80 ? fontSize * 1.05 : fontSize * 0.62);
    }
    let total = 0;
    for (const advance of advances) {
      total += advance;
    }
    const placed: ArcChar[] = [];
    let before = 0;
    for (let i = 0; i < chars.length; i++) {
      const center = before + advances[i] / 2;
      before += advances[i];
      const angleRad = (center - total / 2) / radius;
      placed.push(new ArcChar(chars[i], angleRad * 180 / Math.PI));
    }
    return placed;
  }

  build() {
    Stack() {
      // 外圈
      Circle()
        .strokeWidth(this.lineWidthVp())
        .stroke(this.ink)
        .fill(Color.Transparent)
      // 内圈（细一点，缩进 7%）
      Circle()
        .strokeWidth(this.lineWidthVp() * 0.6)
        .stroke(this.ink)
        .fill(Color.Transparent)
        .width(this.stampSizeVp * 0.86)
        .height(this.stampSizeVp * 0.86)
      // 中间的横带：上下两道线，夹着日期
      Column({ space: this.stampSizeVp * 0.2 }) {
        Divider().strokeWidth(this.lineWidthVp() * 0.7).color(this.ink)
        Divider().strokeWidth(this.lineWidthVp() * 0.7).color(this.ink)
      }
      .width(this.stampSizeVp * 0.86)
      .alignItems(HorizontalAlign.Center)
      Text(postmarkDateText(this.dateMs))
        .fontSize(this.stampSizeVp * 0.125)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.ink)
        .maxLines(1)
        .width(this.stampSizeVp * 0.78)
        .textAlign(TextAlign.Center)
      // 上沿一圈寄出的地点
      if (this.place.length > 0) {
        ForEach(this.arcChars(), (item: ArcChar) => {
          Stack() {
            Text(item.char)
              .fontSize(this.arcFontSizeVp())
              .fontWeight(FontWeight.Bold)
              .fontColor(this.ink)
              .offset({ y: -this.arcRadiusVp() })
          }
          .width(this.stampSizeVp)
          .height(this.stampSizeVp)
          .rotate({ angle: item.angleDeg })
        }, (item: ArcChar, index: number) => `${item.char}-${index}`)
      }
      // 下沿一颗小星，邮戳都有个记号
      Text('★')
        .fontSize(this.stampSizeVp * 0.08)
        .fontColor(this.ink)
        .offset({ y: this.stampSizeVp * 0.3 })
    }
    .width(this.stampSizeVp)
    .height(this.stampSizeVp)
    // 盖歪一点，油墨不那么实
    .rotate({ angle: -9 })
    .opacity(0.82)
  }
}
