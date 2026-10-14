/**
 * 一多断点（10_BUILD_MANUAL.md 1.6，「一端开发多端部署」）。
 *
 * 官方推荐阈值：宽 <600vp 为 sm（手机竖屏）、600~839 md（手机横屏 / 折叠屏展开）、
 * >=840 lg（平板 / 二合一）。MainTabsView 测量根容器后发布进 AppStorage，
 * 后续大屏卡片（3.6 等）按此分流布局。纯函数，单测覆盖（`Breakpoint.test.ets`）。
 */

/** AppStorage key：当前断点 'sm' | 'md' | 'lg' */
export const STORAGE_KEY_APP_BREAKPOINT = 'appBreakpoint';

/** 按宽度（vp）取断点：'sm'（<600）、'md'（600~839）、'lg'（>=840） */
export function breakpointForWidth(widthVp: number): string {
  if (widthVp < 600) {
    return 'sm';
  }
  if (widthVp < 840) {
    return 'md';
  }
  return 'lg';
}
