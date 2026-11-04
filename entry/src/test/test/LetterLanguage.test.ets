/**
 * LetterLanguage 单测（10_BUILD_MANUAL.md 5.5；R-LETTERLANG-01~07）。
 *
 * 验收样例：中英混写（→ 中文）、纯日文、日文含汉字、繁体、简繁同形（→ App 语言）、
 * 法语、西语、韩文、少于 12 字（→ App 语言）。
 * 简繁 / en-fr-es 细分是启发式（平台无 NLLanguageRecognizer）：专用字表 + 虚词 + 重音字符。
 */
import { describe, it, expect } from '@ohos/hypium';
import { LetterLanguage, SIMP_ONLY, TRAD_ONLY } from '../../main/ets/models/LetterLanguage';

export default function letterLanguageTest() {
  describe('LetterLanguageTest', () => {
    // ---- 字表完整性：同序对照表手写，先自证没写歪 ----

    it('simpTradTablesAlignedAndDisjoint', 0, () => {
      expect(SIMP_ONLY.length).assertEqual(TRAD_ONLY.length);
      const simpSeen = new Set<string>();
      for (let i = 0; i < SIMP_ONLY.length; i++) {
        const ch = SIMP_ONLY.charAt(i);
        expect(simpSeen.has(ch)).assertFalse();
        simpSeen.add(ch);
      }
      const tradSeen = new Set<string>();
      for (let i = 0; i < TRAD_ONLY.length; i++) {
        const ch = TRAD_ONLY.charAt(i);
        expect(tradSeen.has(ch)).assertFalse();
        tradSeen.add(ch);
        expect(simpSeen.has(ch)).assertFalse(); // 简繁字表不交叉
      }
    });

    // ---- 验收样例：中英混写 → 中文（App 语言中文时） ----
    // 汉字全是简繁同形字（今天/好多/提前/真的…），启发式分不出简繁 → 退 App 语言
    it('mixedChineseEnglishFallsBackToAppLanguage', 0, () => {
      const text = '今天 meeting 好多，deadline 又提前了，真的 so tired';
      expect(LetterLanguage.detect(text)).assertNull();
      expect(LetterLanguage.forLetter([text], 'zh-Hans')).assertEqual('zh-Hans');
      expect(LetterLanguage.forLetter([text], 'en')).assertEqual('en');
    });

    // ---- 纯日文 / 日文含汉字（假名数票达到阈值） ----

    it('pureJapaneseDetected', 0, () => {
      expect(LetterLanguage.detect('今日はとても良い天気でした。公園を散歩して、犬と遊びました。'))
        .assertEqual('ja');
    });

    it('japaneseWithKanjiDetected', 0, () => {
      expect(LetterLanguage.detect('東京駅から新幹線に乗って京都まで行った。とても快適な旅だった。'))
        .assertEqual('ja');
    });

    it('kanaBelowThresholdNotJapanese', 0, () => {
      // 一个假名够不着 max(2, …)，剩下的汉字又全是同形字 → 认不出
      expect(LetterLanguage.detect('一二三四五六七八九十は')).assertNull();
    });

    // ---- 简繁细分（专用字表数票） ----

    it('simplifiedChineseDetected', 0, () => {
      expect(LetterLanguage.detect('今天天气很好，我和朋友一起去爬山，山上的风景真的很美丽。'))
        .assertEqual('zh-Hans');
    });

    it('traditionalChineseDetected', 0, () => {
      expect(LetterLanguage.detect('今天天氣很好，我和朋友一起去爬山，山上的風景真的很美麗。'))
        .assertEqual('zh-Hant');
    });

    it('sameFormHanFallsBackToAppLanguage', 0, () => {
      // 简繁同形：每个字两边写法一样，分不出来 → App 语言（iOS 同款兜底）
      const text = '他一直都在山下等我，我也在等他';
      expect(LetterLanguage.detect(text)).assertNull();
      expect(LetterLanguage.forLetter([text], 'fr')).assertEqual('fr');
    });

    it('mixedSimpTradBelowConfidenceIsNull', 0, () => {
      // 2 : 2 → 置信 0.5 < 0.6，认不出
      expect(LetterLanguage.detect('他一直都在山下等说说話話')).assertNull();
      // 3 : 2 → 置信 0.6，取多数
      expect(LetterLanguage.detect('他一直都在山下等说说说話話')).assertEqual('zh-Hans');
    });

    // ---- en / fr / es（虚词 + 重音字符） ----

    it('englishDetected', 0, () => {
      expect(LetterLanguage.detect('I had a really good day today, and I am grateful for the small things in life.'))
        .assertEqual('en');
    });

    it('frenchDetected', 0, () => {
      expect(LetterLanguage.detect('Je suis très heureux aujourd\'hui parce que j\'ai fini mon travail et je peux enfin me reposer.'))
        .assertEqual('fr');
    });

    it('spanishDetected', 0, () => {
      expect(LetterLanguage.detect('Hoy fui al mercado con mi hermana para comprar pan y queso fresco.'))
        .assertEqual('es');
    });

    it('spanishAccentsDetected', 0, () => {
      // ñ / á / é 混排：重音字符 ñ+á 投西语，é 不投票
      expect(LetterLanguage.detect('Mañana iré al mercado con mi hermana para comprar pañuelos.'))
        .assertEqual('es');
    });

    // ---- 韩文 ----

    it('koreanDetected', 0, () => {
      expect(LetterLanguage.detect('오늘 날씨가 정말 좋아서 공원에 산책했다.')).assertEqual('ko');
    });

    // ---- 少于 12 字 / App 语言兜底 ----

    it('tooShortFallsBackToAppLanguage', 0, () => {
      expect(LetterLanguage.detect('hello world')).assertNull(); // 11 字符
      expect(LetterLanguage.detect('今天很好')).assertNull();
      expect(LetterLanguage.forLetter(['今天很好'], 'zh-Hant')).assertEqual('zh-Hant');
    });

    it('appLanguageNotSupportedFallsBackToEnglish', 0, () => {
      expect(LetterLanguage.forLetter(['今天很好'], 'ru')).assertEqual('en');
    });

    // ---- forLetter 合并标题 + 正文 ----

    it('forLetterJoinsTitleAndBody', 0, () => {
      expect(LetterLanguage.forLetter(['标题', '这段文字比较长够识别了'], 'zh-Hant'))
        .assertEqual('zh-Hans');
    });
  });
}
