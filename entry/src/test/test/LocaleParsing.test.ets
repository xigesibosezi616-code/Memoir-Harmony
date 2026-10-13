/**
 * LocaleParsing 纯逻辑单测（10_BUILD_MANUAL.md 1.2，文件是 1.1 会话提前落地的，
 * 本卡片补齐承诺的单测）。
 *
 * 覆盖 R-LANG-02 首启解析的全部规则：
 * - 中文看 script（zh-Hant-TW → 繁）；无 script 看地区（TW/HK/MO → 繁，其余简）
 * - 其余语言在名单里就用（地区不限）
 * - 都不在 → 英语（不是中文）
 */
import { describe, it, expect } from '@ohos/hypium';
import { resolveSupportedFromTag, resolveInitialLanguage } from '../../main/ets/services/LocaleParsing';

const SUPPORTED: string[] = ['zh-Hans', 'zh-Hant', 'en', 'ja', 'ko', 'fr', 'es'];

export default function localeParsingTest() {
  describe('LocaleParsingTest', () => {
    // ---- 单条语言标签 → 受支持语言 ----
    it('resolvesChineseByScript', 0, () => {
      expect(resolveSupportedFromTag('zh-Hans-CN', SUPPORTED)).assertEqual('zh-Hans');
      expect(resolveSupportedFromTag('zh-Hant-TW', SUPPORTED)).assertEqual('zh-Hant');
      expect(resolveSupportedFromTag('zh-Hans', SUPPORTED)).assertEqual('zh-Hans');
      expect(resolveSupportedFromTag('zh-Hant', SUPPORTED)).assertEqual('zh-Hant');
      expect(resolveSupportedFromTag('zh-hant-HK', SUPPORTED)).assertEqual('zh-Hant');
    })

    it('resolvesChineseByRegionWithoutScript', 0, () => {
      expect(resolveSupportedFromTag('zh-TW', SUPPORTED)).assertEqual('zh-Hant');
      expect(resolveSupportedFromTag('zh-HK', SUPPORTED)).assertEqual('zh-Hant');
      expect(resolveSupportedFromTag('zh-MO', SUPPORTED)).assertEqual('zh-Hant');
      expect(resolveSupportedFromTag('zh', SUPPORTED)).assertEqual('zh-Hans');
      expect(resolveSupportedFromTag('zh-CN', SUPPORTED)).assertEqual('zh-Hans');
      expect(resolveSupportedFromTag('zh-SG', SUPPORTED)).assertEqual('zh-Hans');
      expect(resolveSupportedFromTag('zh-US', SUPPORTED)).assertEqual('zh-Hans');
    })

    it('resolvesNonChineseByLanguageCode', 0, () => {
      expect(resolveSupportedFromTag('en', SUPPORTED)).assertEqual('en');
      expect(resolveSupportedFromTag('en-US', SUPPORTED)).assertEqual('en');
      expect(resolveSupportedFromTag('ja-JP', SUPPORTED)).assertEqual('ja');
      expect(resolveSupportedFromTag('ko', SUPPORTED)).assertEqual('ko');
      expect(resolveSupportedFromTag('fr-FR', SUPPORTED)).assertEqual('fr');
      expect(resolveSupportedFromTag('es-MX', SUPPORTED)).assertEqual('es');
    })

    it('returnsNullForUnsupported', 0, () => {
      expect(resolveSupportedFromTag('de', SUPPORTED)).assertNull();
      expect(resolveSupportedFromTag('de-DE', SUPPORTED)).assertNull();
      expect(resolveSupportedFromTag('pt-BR', SUPPORTED)).assertNull();
      expect(resolveSupportedFromTag('ru-RU', SUPPORTED)).assertNull();
    })

    // ---- 系统偏好列表 → 首启语言（R-LANG-02）----
    it('resolvesFirstSupportedInPreferredList', 0, () => {
      expect(resolveInitialLanguage(['zh-Hans-CN', 'en-US'], SUPPORTED)).assertEqual('zh-Hans');
      expect(resolveInitialLanguage(['de-DE', 'en-US'], SUPPORTED)).assertEqual('en');
      expect(resolveInitialLanguage(['de-DE', 'fr-FR'], SUPPORTED)).assertEqual('fr');
      expect(resolveInitialLanguage(['zh-TW', 'zh-Hans-CN'], SUPPORTED)).assertEqual('zh-Hant');
    })

    it('fallsBackToEnglishWhenNothingSupported', 0, () => {
      // 系统语言设成德语首启 → 英语（R-LANG-02 验收）
      expect(resolveInitialLanguage(['de-DE'], SUPPORTED)).assertEqual('en');
      expect(resolveInitialLanguage(['de', 'it', 'pt'], SUPPORTED)).assertEqual('en');
      expect(resolveInitialLanguage([], SUPPORTED)).assertEqual('en');
    })
  })
}
