/**
 * 一枚火漆印：深红的蜡、边缘不规则地溢开一圈，中间压一个字。
 * 对应 iOS `Views/Components/WaxSeal.swift`，色值逐字一致（跨端视觉契约）。
 *
 * 真的火漆印压的是主人的姓名首字母（2026-10-10 产品定）：投信时压**用户自己
 * 昵称**的第一个字（信是用户封的）；印面取字口径在 `PostingRun.sealMarkOf`。
 * 没有可用的名字时压「素」。
 */
const WAX: string = '#8E2B24';
const WAX_LIGHT: string = '#B54A3E';
/** 溢开的蜡：几个错开的圆叠出不规则的边（角度数组，i/7 × 2π） */
const SPILL_COUNT: number = 7;

@Component
export struct WaxSeal {
  /** 印的直径（vp） */
  sizeVp: number = 64;
  /** 压在中间的字（「素」兜底，取字口径在 PostingRun.sealMarkOf） */
  mark: string = '素';

  build() {
    Stack() {
      // 溢开的蜡：几个错开的圆叠出不规则的边
      ForEach(this.spillIndexes(), (index: number) => {
        Circle()
          .fill(WAX)
          .width(this.sizeVp * 0.42)
          .height(this.sizeVp * 0.42)
          .offset({
            x: Math.cos(index / SPILL_COUNT * 2 * Math.PI) * this.sizeVp * 0.31,
            y: Math.sin(index / SPILL_COUNT * 2 * Math.PI) * this.sizeVp * 0.31
          })
      }, (index: number): string => `spill:${index}`)
      // 主体：径向渐变（iOS 同款：高光偏左上，往边缘压暗成深红）。
      // 🔴 主体不能用 Circle().radialGradient()：Circle 是 shape，默认
      // fill 纯黑盖在背景渐变上面，真机渲染成黑圆盘、只剩溢蜡一圈红边
      //（2026-11-05 用户「火漆印怎么是黑的」，印章区域 47% 纯黑实锤）；
      // 改普通组件铺渐变、borderRadius+clip 裁圆
      Column()
        .radialGradient({
          center: [this.sizeVp * 0.84 * 0.38, this.sizeVp * 0.84 * 0.32],
          radius: this.sizeVp * 0.5,
          colors: [[WAX_LIGHT, 0], [WAX, 1]]
        })
        .width(this.sizeVp * 0.84)
        .height(this.sizeVp * 0.84)
        .borderRadius(this.sizeVp * 0.42)
        .clip(true)
      // 压印的内圈：一深一浅两道，错开半分
      Circle()
        .stroke('#38000000')
        .strokeWidth(this.sizeVp * 0.02)
        .fill(Color.Transparent)
        .width(this.sizeVp * 0.62)
        .height(this.sizeVp * 0.62)
      Circle()
        .stroke('#2EFFFFFF')
        .strokeWidth(this.sizeVp * 0.015)
        .fill(Color.Transparent)
        .width(this.sizeVp * 0.62)
        .height(this.sizeVp * 0.62)
        .offset({ x: this.sizeVp * 0.008, y: this.sizeVp * 0.008 })
      // 压的字：底层黑 28%、上层白 22% 往右下错开 —— 受光在右下（U20 对齐 iOS）
      Text(this.mark)
        .fontSize(`${this.sizeVp * 0.32}vp`) // vp：不跟系统字体大小缩放（ICONS.md 火漆印规格）
        .fontWeight(600) // iOS .semibold
        .fontFamily('serif')
        .fontColor('#47000000')
      Text(this.mark)
        .fontSize(`${this.sizeVp * 0.32}vp`)
        .fontWeight(600)
        .fontFamily('serif')
        .fontColor('#38FFFFFF')
        .offset({ x: this.sizeVp * 0.012, y: this.sizeVp * 0.012 })
    }
    .width(this.sizeVp)
    .height(this.sizeVp)
    .shadow({ radius: 3, color: '#40000000', offsetX: 0, offsetY: 2 })
    // 印本身不念（iOS .accessibilityHidden(true)）；所在行自己念「尺素会员」
    .accessibilityLevel('no')
  }

  private spillIndexes(): number[] {
    const indexes: number[] = [];
    for (let i = 0; i < SPILL_COUNT; i++) {
      indexes.push(i);
    }
    return indexes;
  }
}
