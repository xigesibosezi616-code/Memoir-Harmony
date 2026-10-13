/**
 * LanguageManager 纯逻辑单测（10_BUILD_MANUAL.md 1.2）。
 *
 * 只测纯静态逻辑：七种语言顺序固定（R-LANG-01）、id 归一 / 判定。
 * 不碰偏好读写与 setAppPreferredLanguage（需要 UIAbility 环境，真机 ohosTest 再覆盖）；
 * 不调 supportedOptions()（$r 资源解析，UI 侧验）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { LanguageManager } from '../../main/ets/services/LanguageManager';

export default function languageManagerTest() {
  describe('LanguageManagerTest', () => {
    // R-LANG-01：七种语言，顺序固定
    it('supportedIdsKeepFixedOrder', 0, () => {
      expect(LanguageManager.SUPPORTED_IDS.length).assertEqual(7);
      expect(LanguageManager.SUPPORTED_IDS[0]).assertEqual('zh-Hans');
      expect(LanguageManager.SUPPORTED_IDS[1]).assertEqual('zh-Hant');
      expect(LanguageManager.SUPPORTED_IDS[2]).assertEqual('en');
      expect(LanguageManager.SUPPORTED_IDS[3]).assertEqual('ja');
      expect(LanguageManager.SUPPORTED_IDS[4]).assertEqual('ko');
      expect(LanguageManager.SUPPORTED_IDS[5]).assertEqual('fr');
      expect(LanguageManager.SUPPORTED_IDS[6]).assertEqual('es');
    })

    // 「跟随系统」不是语言：名单里没有，isSupported 为 false（R-LANG-02）
    it('doesNotSupportFollowSystem', 0, () => {
      expect(LanguageManager.isSupported('default')).assertFalse();
      expect(LanguageManager.isSupported('system')).assertFalse();
      expect(LanguageManager.isSupported('auto')).assertFalse();
    })

    it('canonicalizesSupportedIdsCaseInsensitively', 0, () => {
      expect(LanguageManager.canonicalLanguageId('zh-Hans')).assertEqual('zh-Hans');
      expect(LanguageManager.canonicalLanguageId('ZH-HANS')).assertEqual('zh-Hans');
      expect(LanguageManager.canonicalLanguageId('En')).assertEqual('en');
      expect(LanguageManager.canonicalLanguageId('JA')).assertEqual('ja');
    })

    it('rejectsUnsupportedIds', 0, () => {
      expect(LanguageManager.canonicalLanguageId('de')).assertUndefined();
      expect(LanguageManager.canonicalLanguageId('pt-BR')).assertUndefined();
      expect(LanguageManager.canonicalLanguageId('')).assertUndefined();
      expect(LanguageManager.isSupported('de')).assertFalse();
      expect(LanguageManager.isSupported('')).assertFalse();
    })

    it('isSupportedMatchesAllSeven', 0, () => {
      for (const id of LanguageManager.SUPPORTED_IDS) {
        expect(LanguageManager.isSupported(id)).assertTrue();
      }
    })
  })
}
