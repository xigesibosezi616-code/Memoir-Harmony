/**
 * 物理弹簧仿真单测（Q32③：拖书转角 displaySync 帧驱动积分器）。
 * 不变量来自 SwiftUI `spring(response:dampingFraction:)` 的数学定义：
 * - stiffness = (2π/response)²，damping = dampingFraction × 2√k（mass=1）
 * - 临界阻尼（dampingFraction = 1，iOS `.smooth`）从 0 速度出发单调收敛、不过冲
 * - 欠阻尼（0.88，跟手弹簧）允许过冲但最终收敛
 * - dt 夹取：异常大帧间隔不炸飞（切后台回前台兜底）
 */
import { describe, it, expect } from '@ohos/hypium';
import { SpringSimulation, springSettleGuardMs } from '../../main/ets/models/SpringSimulation';

/** 用固定 120Hz 拍长仿真，返回 [落定耗时ms, 峰值]；3000ms 未落定回 -1 */
function simulate(spring: SpringSimulation, from: number, to: number): number[] {
  let value = from;
  let velocity = 0;
  let peak = from;
  const dt = 1 / 120;
  for (let i = 0; i < 360; i++) {
    const next = spring.step(value, to, velocity, dt);
    value = next[0];
    velocity = next[1];
    peak = Math.max(peak, value);
    if (spring.settled(value, to, velocity)) {
      return [i * dt * 1000, peak];
    }
  }
  return [-1, peak];
}

export default function springSimulationTest() {
  describe('SpringSimulation', () => {
    it('stiffness_and_damping_follow_swiftui_definition', 0, () => {
      const s = new SpringSimulation(0.45, 1);
      expect(s.stiffness).assertClose(Math.pow(2 * Math.PI / 0.45, 2), 0.001);
      expect(s.damping).assertClose(2 * Math.sqrt(s.stiffness), 0.001);
    });

    it('critical_damping_settles_without_overshoot', 0, () => {
      // iOS .smooth(0.45)：拿起转角 0 → 32°，临界阻尼不过冲、约 1.2s 内落定
      const s = new SpringSimulation(0.45, 1);
      const result = simulate(s, 0, 0.5585);
      expect(result[0] > 0).assertTrue();
      expect(result[0] < 1200).assertTrue();
      expect(result[1] <= 0.5585 + 0.0005).assertTrue();
    });

    it('underdamped_overshoots_then_settles', 0, () => {
      // 跟手弹簧（0.2, 0.88）允许轻微过冲，但仍在 1s 内落定
      const s = new SpringSimulation(0.2, 0.88);
      const result = simulate(s, 0, 1);
      expect(result[0] > 0).assertTrue();
      expect(result[0] < 1000).assertTrue();
    });

    it('huge_dt_is_clamped_not_explosive', 0, () => {
      const s = new SpringSimulation(0.45, 1);
      // 一帧 10 秒（切后台回来）：夹到 50ms 步长，位置变化有限
      const next = s.step(0.001, 0.5585, 0, 10);
      expect(Math.abs(next[0] - 0.001) < 2).assertTrue();
      expect(Number.isFinite(next[0])).assertTrue();
      expect(Number.isFinite(next[1])).assertTrue();
    });

    it('zero_and_negative_dt_are_noops', 0, () => {
      const s = new SpringSimulation(0.45, 1);
      const next = s.step(0.3, 0.5585, 0.1, 0);
      expect(next[0]).assertEqual(0.3);
      expect(next[1]).assertEqual(0.1);
      const neg = s.step(0.3, 0.5585, 0.1, -5);
      expect(neg[0]).assertEqual(0.3);
    });

    it('guard_time_covers_visual_settle', 0, () => {
      // 兜底定时必须晚于真实落定，否则会出现「弹簧没走完被砍断」
      const s = new SpringSimulation(0.5, 1);
      const result = simulate(s, 0, 0.5585);
      expect(result[0] > 0).assertTrue();
      expect(springSettleGuardMs(0.5) > result[0]).assertTrue();
    });
  });
}
