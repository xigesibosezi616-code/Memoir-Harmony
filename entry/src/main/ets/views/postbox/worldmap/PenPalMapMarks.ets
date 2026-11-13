/**
 * 地图上的标记（U01 决策 13–16）。对应 iOS `Views/PostBox/WorldMap/PenPalMapMarks.swift`。
 *
 * - 墨色由父组件按白天黑夜取好传入（`mapInkOf`，MapInk 模型）——
 *   跟着地图的昼夜走，不跟主题（决策 15）
 * - 颜色是 `0xAARRGGBB` 数值（MapInk 模型的产物）：ArkUI 的
 *   `ResourceColor` 直接收数值，和 Map Kit 航线一套色
 * - 这些标记画在 MapComponent 之上的 ArkUI 覆盖层里，由
 *   `WorldMapPage` 用 Projection.toScreenLocation 定位（墨点 / 名签 /
 *   在途信封都是普通 ArkUI 组件，点头交互好挂）
 */
import { MapInk, mapInkOf } from '../../../models/MapInk';

/** 点得准：墨点很小，手指点的范围放大到 44vp（iOS 同款） */
const HIT_SIZE_VP: number = 44;

/**
 * 地图上的一位笔友：一个墨点，外面一圈对比色（像参考图那样压在地图上）。
 * - 平常：小墨点
 * - 在收件人里：换成邮戳色，大一点
 * - 正在看的那位（名片翻到他）：再大一点，下面写着姓
 */
@Component
export struct PenPalDot {
  /** 昼夜墨色（父组件 mapInkOf 取好） */
  ink: MapInk = mapInkOf(false, '#B5473A');
  @Prop isRecipient: boolean = false;
  @Prop isFocused: boolean = false;
  /** 名签上写的姓（只在 focused 时显示） */
  name: string = '';
  /** 点墨点 = 名片翻到他 */
  onTap: () => void = (): void => {};

  private sizeVp(): number {
    return this.isFocused ? 16 : (this.isRecipient ? 13 : 10);
  }

  build() {
    Stack() {
      // 墨点 + 外面那一圈对比色（focused / recipient 时变大变色）
      Stack() {
        Circle()
          .fill(this.isRecipient ? this.ink.post : this.ink.dot)
          .width(this.sizeVp())
          .height(this.sizeVp())
        Circle()
          .fill(Color.Transparent)
          .stroke(this.ink.ring)
          .strokeWidth(this.isFocused ? 2.5 : 2)
          .width(this.sizeVp() + (this.isFocused ? 5 : 4))
          .height(this.sizeVp() + (this.isFocused ? 5 : 4))
      }
      .shadow({ radius: 1.5, color: 'rgba(0,0,0,0.22)', offsetX: 0, offsetY: 0.5 })
    }
    // 点得准：44vp 的热区，墨点居中
    .width(HIT_SIZE_VP)
    .height(HIT_SIZE_VP)
    .onClick((): void => {
      this.onTap();
    })
    // 正在看的那位：下面写姓（压在墨点下面，参考图那样）
    .overlay(this.nameTag(), { align: Alignment.Bottom })
  }

  @Builder
  private nameTag() {
    if (this.isFocused) {
      Column() {
        MapNameTag({ text: this.name, ink: this.ink })
      }
      .margin({ bottom: 3 })
    }
  }
}

/** 你在这里：一圈邮戳似的细环，中间一个点，下面写着「你」 */
@Component
export struct YouMark {
  ink: MapInk = mapInkOf(false, '#B5473A');
  onTap: () => void = (): void => {};

  build() {
    Stack() {
      Stack() {
        Circle()
          .fill(this.ink.ring)
          .opacity(0.85)
          .width(22)
          .height(22)
        Circle()
          .fill(Color.Transparent)
          .stroke(this.ink.dot)
          .strokeWidth(1.4)
          .width(22)
          .height(22)
        Circle()
          .fill(this.ink.dot)
          .width(7)
          .height(7)
      }
      .shadow({ radius: 1.5, color: 'rgba(0,0,0,0.18)', offsetX: 0, offsetY: 0.5 })
    }
    .width(HIT_SIZE_VP)
    .height(HIT_SIZE_VP)
    .onClick((): void => {
      this.onTap();
    })
    .overlay(this.nameTag(), { align: Alignment.Bottom })
  }

  @Builder
  private nameTag() {
    Column() {
      MapNameTag({ labelText: $r('app.string.s_5630b886f9'), ink: this.ink })
    }
    .margin({ bottom: 2 })
  }
}

/** 在路上的信：航线上的一个小信封，斜着贴（iOS envelope.fill −8°） */
@Component
export struct TransitEnvelopeMark {
  ink: MapInk = mapInkOf(false, '#B5473A');

  build() {
    Column() {
      SymbolGlyph($r('sys.symbol.envelope'))
        .fontSize(13)
        .fontColor([this.ink.post])
        .padding(3)
        .backgroundColor(this.ink.tagPaper)
        .borderRadius(100)
    }
    .rotate({ angle: -8 })
    .shadow({ radius: 1.5, color: 'rgba(0,0,0,0.2)', offsetX: 0, offsetY: 0.5 })
  }
}

/**
 * 墨点下面的小标签（姓、「你」）。字 11pt medium，胶囊底。
 * 文字两种来源：直接给字（姓，按 App 语言解析好的），或给资源（「你」）。
 */
@Component
export struct MapNameTag {
  ink: MapInk = mapInkOf(false, '#B5473A');
  /** 直接文字（姓） */
  text: string = '';
  /** 资源文字（「你」）；给了资源优先用资源 */
  labelText: Resource | undefined = undefined;

  build() {
    Text(this.labelText !== undefined ? this.labelText : this.text)
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.ink.dot)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor(this.ink.tagPaper)
      .borderRadius(100)
  }
}
