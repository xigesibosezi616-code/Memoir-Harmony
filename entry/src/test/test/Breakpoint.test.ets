/**
 * 一多断点单测（10_BUILD_MANUAL.md 1.6）。
 * 官方阈值：<600 sm、600~839 md、>=840 lg。
 */
import { describe, it, expect } from '@ohos/hypium';
import { breakpointForWidth } from '../../main/ets/theme/Breakpoint';

export default function breakpointTest() {
  describe('BreakpointTest', () => {
    it('narrowPhonesAreSm', 0, () => {
      expect(breakpointForWidth(0)).assertEqual('sm');
      expect(breakpointForWidth(360)).assertEqual('sm');
      expect(breakpointForWidth(599.9)).assertEqual('sm');
    })

    it('sixHundredIsMdBoundary', 0, () => {
      expect(breakpointForWidth(600)).assertEqual('md');
      expect(breakpointForWidth(839.9)).assertEqual('md');
    })

    it('eightHundredFortyIsLgBoundary', 0, () => {
      expect(breakpointForWidth(840)).assertEqual('lg');
      expect(breakpointForWidth(1280)).assertEqual('lg');
    })
  })
}
