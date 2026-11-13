/**
 * 物理弹簧仿真（10_BUILD_MANUAL.md 3.2 拖书转角驱动，Q32③）。
 *
 * SwiftUI `.smooth(duration:)` / `spring(response:dampingFraction:)` 的数学本体：
 * response 直接换算刚度 stiffness = (2π/response)²，dampingFraction 换算阻尼
 * damping = dampingFraction × 2√(stiffness·mass)（mass = 1）。dampingFraction = 1
 * 是临界阻尼：最快收敛且不过冲（iOS `.smooth` 的「不弹」）。
 *
 * 为什么不用 animateTo / 定时器：书的投影矩阵不能插值（插值的是角度，每帧要按
 * 角度重算矩阵），所以转角必须逐帧驱动。16ms setInterval 不对齐 vsync（漂移 +
 * 掉帧补不齐 = 观感卡顿）；改 displaySync 帧回调后，每帧用真实帧间隔步进这个
 * 弹簧 —— iOS 的 Animatable 在渲染层插值，这里在帧回调里积分，节奏天然对齐。
 *
 * 纯数学，不依赖 ArkUI —— 单测覆盖（收敛、临界阻尼不过冲、dt 夹取防爆）。
 */

/** 单帧最大步长（秒）：帧回调间隔异常拉大（切后台回来）时夹住，不一步炸飞 */
const MAX_DT_SEC: number = 0.05;

export class SpringSimulation {
  /** 刚度 k = (2π/response)² */
  readonly stiffness: number;
  /** 阻尼 c = dampingFraction × 2√k（mass = 1） */
  readonly damping: number;

  constructor(response: number, dampingFraction: number) {
    const r = Math.max(0.001, response);
    this.stiffness = Math.pow(2 * Math.PI / r, 2);
    this.damping = dampingFraction * 2 * Math.sqrt(this.stiffness);
  }

  /**
   * 半隐式欧拉步进一帧：先更新速度再更新位置（同 dt 下比显式欧拉稳）。
   * 返回 [新值, 新速度]。dt 夹到 [0, MAX_DT_SEC]。
   */
  step(value: number, target: number, velocity: number, dtSec: number): number[] {
    const dt = Math.min(Math.max(dtSec, 0), MAX_DT_SEC);
    const displacement = value - target;
    const accel = -this.stiffness * displacement - this.damping * velocity;
    const newVelocity = velocity + accel * dt;
    return [value + newVelocity * dt, newVelocity];
  }

  /** 已落定：位置够近且速度够慢（弧度/弧度每秒口径，拖书转角用足够） */
  settled(value: number, target: number, velocity: number): boolean {
    return Math.abs(value - target) < 0.0004 && Math.abs(velocity) < 0.02;
  }
}

/**
 * 弹簧落定耗时的保守上界（ms）：给「兜底定时」用（帧回调链路断裂时强制收尾）。
 * 经验值：临界阻尼 spring 在 ~2.2×response 内视觉落定，放宽到 3 倍 + 100ms 余量。
 */
export function springSettleGuardMs(response: number): number {
  return Math.round(Math.max(0.05, response) * 3 * 1000) + 100;
}
