/**
 * 法律文档版本比对与语言回退单测（10_BUILD_MANUAL.md 1.5）。
 * 对应 iOS `Views/Legal/LegalDocument.swift`。
 *
 * - needsLegalConsent：同意记录存版本号不存布尔（R-APP-02）——
 *   没同意过、政策已更新都要重弹同意页
 * - legalCandidates：精确匹配 → 同语族 / 英语 → 简体中文兜底的回退链
 *   （zh 系退简中而不是英语：看得懂优先；非 zh 非 en 先退英语再退简中）
 * - rawfile 当前只内置 zh-Hans（Q12 法务定稿前的占位），其他语言沿回退链
 *   读到中文正文 —— 与 iOS「找不到时退回简体中文」语义一致
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  LegalDocument,
  LEGAL_CURRENT_VERSION,
  needsLegalConsent,
  legalFilePrefix,
  legalCandidates
} from '../../main/ets/views/legal/LegalDocument';

export default function legalDocumentTest() {
  describe('LegalDocumentTest', () => {
    // ---- 版本比对（R-APP-02）----

    it('neverAcceptedNeedsConsent', 0, () => {
      // 空串 = 从没同意过
      expect(needsLegalConsent('')).assertTrue();
    })

    it('acceptedCurrentVersionSkipsConsent', 0, () => {
      expect(needsLegalConsent(LEGAL_CURRENT_VERSION)).assertFalse();
    })

    it('outdatedAcceptedVersionNeedsConsentAgain', 0, () => {
      // 政策更新后老用户重新看到同意页
      expect(needsLegalConsent('2020-01-01')).assertTrue();
    })

    it('currentVersionTracksIos', 0, () => {
      // iOS `LegalDocument.currentVersion` = 2026-10-09
      // （隐私政策第七节注销账号改为 App 内自助）。两边改政策要一起改
      expect(LEGAL_CURRENT_VERSION).assertEqual('2026-10-09');
    })

    // ---- 文件名前缀 ----

    it('filePrefixPerDocument', 0, () => {
      expect(legalFilePrefix(LegalDocument.Privacy)).assertEqual('privacy');
      expect(legalFilePrefix(LegalDocument.Terms)).assertEqual('terms');
    })

    // ---- 语言回退链 ----

    it('exactLanguageComesFirst', 0, () => {
      expect(legalCandidates('fr')[0]).assertEqual('fr');
    })

    it('zhFallsBackToSimplifiedNotEnglish', 0, () => {
      // zh-Hant 找不到退 zh-Hans（看得懂），不退 en
      const chain = legalCandidates('zh-Hant');
      expect(chain.join(',')).assertEqual('zh-Hant,zh-Hans');
    })

    it('nonZhNonEnFallsBackToEnglishThenSimplified', 0, () => {
      // fr → en（比中文更可能读懂）→ zh-Hans 兜底
      expect(legalCandidates('fr').join(',')).assertEqual('fr,en,zh-Hans');
      expect(legalCandidates('ja').join(',')).assertEqual('ja,en,zh-Hans');
    })

    it('englishFallsBackToSimplifiedOnly', 0, () => {
      expect(legalCandidates('en').join(',')).assertEqual('en,zh-Hans');
    })

    it('emptyLanguageGoesStraightToSimplified', 0, () => {
      expect(legalCandidates('').join(',')).assertEqual('zh-Hans');
    })

    it('simplifiedChineseDoesNotDuplicate', 0, () => {
      // 精确命中与兜底是同一个：去重且保序
      expect(legalCandidates('zh-Hans').join(',')).assertEqual('zh-Hans');
    })
  })
}
