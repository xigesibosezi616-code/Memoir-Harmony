/**
 * 开场封面池 —— 按当前主题取一张静态封面（10_BUILD_MANUAL.md 1.5）。
 * 对应 iOS `Views/Splash/SplashCoverPool.swift`。
 *
 * iOS 是运行时扫 bundle 目录（`SplashCovers/splash_<主题>.{png,jpg,heic}`），
 * 「把图片放进目录就生效」；鸿蒙资源是编译期定死的（`$r` 字面量、不能运行时
 * 按名扫描），所以换成「加主题时在 switch 里补一行」。当前三种主题都有图。
 *
 * 某个主题缺图（default 分支返回 undefined）→ 调用方据此跳过开场：
 * 不会崩，也不会白屏一下（EntryAbility 那层就拦掉了，连一帧封面背景都不闪）。
 */
import { ThemeManager } from '../../theme/ThemeManager';

/** 当前主题的封面；没有就是 undefined（调用方据此跳过开场） */
export function splashImageFor(themeId: string): Resource | undefined {
  switch (ThemeManager.canonicalThemeId(themeId)) {
    case 'bamboo':
      return $r('app.media.splash_bamboo');
    case 'leather':
      return $r('app.media.splash_leather');
    case 'kent':
      return $r('app.media.splash_kent');
    default:
      return undefined;
  }
}
