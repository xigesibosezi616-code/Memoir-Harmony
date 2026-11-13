/**
 * 世界笔友名册单测（U01）。
 *
 * - 解析：两端的 penpals.json 同一份；坏名册抛错、quiet 版返回空
 * - LocalizedText 回退链：语言 → 英文 → default → 第一个非空 → ''
 * - 语言键归一：zh 主区当简中、zh-TW/zh-HK 当繁中、不认识退英文
 */
import { describe, it, expect } from '@ohos/hypium';
import { PenPal, PenPalCoordinate, LocalizedText, parsePenPalRoster,
  parsePenPalRosterQuietly, penPalLanguageKey } from '../../main/ets/models/PenPal';

const ROSTER_JSON = `{"version": 1, "penPals": [
  {"id": "mcrae", "surname": {"zh-Hans": "麦克雷", "en": "McRae"},
   "region": "NZ", "coordinate": {"lat": -46.9, "lon": 168.13},
   "timeZone": "Pacific/Auckland", "nativeLanguage": "en", "postage": 1,
   "place": {"zh-Hans": "斯图尔特岛", "en": "Stewart Island"},
   "card": {"default": "the lighthouse keeper"}},
  {"id": "researcher", "surname": {"en": "M."},
   "region": "AQ", "coordinate": {"lat": -64.8, "lon": -63.5},
   "timeZone": "Antarctica/Palmer", "nativeLanguage": "en", "postage": 2,
   "place": {"en": "Antarctica"}, "card": {"en": ""}}
]}`;

const EMPTY_TEXT = new LocalizedText('', '', '', '', '', '', '', '');

function buildPenPal(id: string, region: string, lat: number, lon: number,
  postage: number): PenPal {
  return new PenPal(id, EMPTY_TEXT, region, new PenPalCoordinate(lat, lon),
    'UTC', 'en', postage, EMPTY_TEXT, EMPTY_TEXT);
}

export default function penPalTest() {
  describe('PenPalTest', () => {
    it('parsesRosterInFileOrder', 0, () => {
      const roster = parsePenPalRoster(ROSTER_JSON);
      expect(roster.length).assertEqual(2);
      expect(roster[0].id).assertEqual('mcrae');
      expect(roster[0].region).assertEqual('NZ');
      expect(roster[0].timeZone).assertEqual('Pacific/Auckland');
      expect(roster[0].postage).assertEqual(1);
      expect(roster[0].coordinate.lat).assertEqual(-46.9);
      expect(roster[0].coordinate.lon).assertEqual(168.13);
      expect(roster[1].id).assertEqual('researcher');
    })

    it('antarcticIsRegionAQ', 0, () => {
      const roster = parsePenPalRoster(ROSTER_JSON);
      expect(roster[1].isAntarctic()).assertTrue();
      expect(roster[0].isAntarctic()).assertFalse();
    })

    it('postageDefaultsToOneWhenMissing', 0, () => {
      const json = `{"penPals": [{"id": "x", "surname": {"en": "X"}, "region": "JP",
        "coordinate": {"lat": 1, "lon": 2}, "timeZone": "Asia/Tokyo",
        "nativeLanguage": "ja", "place": {"en": "p"}, "card": {"en": "c"}}]}`;
      expect(parsePenPalRoster(json)[0].postage).assertEqual(1);
    })

    it('throwsOnMissingRequiredField', 0, () => {
      const bad = `{"penPals": [{"id": "x", "region": "JP"}]}`;
      let threw = false;
      try {
        parsePenPalRoster(bad);
      } catch (err) {
        threw = true;
      }
      expect(threw).assertTrue();
    })

    it('throwsOnBadJson', 0, () => {
      let threw = false;
      try {
        parsePenPalRoster('not json at all');
      } catch (err) {
        threw = true;
      }
      expect(threw).assertTrue();
    })

    it('quietParseReturnsEmptyOnFailure', 0, () => {
      expect(parsePenPalRosterQuietly('not json').length).assertEqual(0);
      expect(parsePenPalRosterQuietly(ROSTER_JSON).length).assertEqual(2);
    })

    it('localizedTextResolvesExactLanguage', 0, () => {
      const text = parsePenPalRoster(ROSTER_JSON)[0].place;
      expect(text.resolved('zh-Hans')).assertEqual('斯图尔特岛');
      expect(text.resolved('en')).assertEqual('Stewart Island');
    })

    it('localizedTextFallsBackToEnglishThenDefault', 0, () => {
      const card = parsePenPalRoster(ROSTER_JSON)[0].card;
      // 没有日语 → 英文也没有 → default
      expect(card.resolved('ja')).assertEqual('the lighthouse keeper');
      const surname = parsePenPalRoster(ROSTER_JSON)[1].surname;
      expect(surname.resolved('ko')).assertEqual('M.');
    })

    it('localizedTextFallsBackToFirstNonEmpty', 0, () => {
      const onlyZh = new LocalizedText('', '只有中文', '', '', '', '', '', '');
      expect(onlyZh.resolved('fr')).assertEqual('只有中文');
      expect(onlyZh.resolved('en')).assertEqual('只有中文');
      const allEmpty = new LocalizedText('', '', '', '', '', '', '', '');
      expect(allEmpty.resolved('en')).assertEqual('');
    })

    it('languageKeyNormalizesAppLanguageIds', 0, () => {
      expect(penPalLanguageKey('zh-Hans')).assertEqual('zh-Hans');
      expect(penPalLanguageKey('zh-Hant')).assertEqual('zh-Hant');
      expect(penPalLanguageKey('en')).assertEqual('en');
      expect(penPalLanguageKey('ja')).assertEqual('ja');
      expect(penPalLanguageKey('ko')).assertEqual('ko');
      expect(penPalLanguageKey('fr')).assertEqual('fr');
      expect(penPalLanguageKey('es')).assertEqual('es');
      expect(penPalLanguageKey('zh-CN')).assertEqual('zh-Hans');
      expect(penPalLanguageKey('zh')).assertEqual('zh-Hans');
      expect(penPalLanguageKey('zh-TW')).assertEqual('zh-Hant');
      expect(penPalLanguageKey('zh-HK')).assertEqual('zh-Hant');
      expect(penPalLanguageKey('pt-BR')).assertEqual('en');
    })

    it('buildPenPalHelperSanity', 0, () => {
      const p = buildPenPal('x', 'JP', 35, 135, 1);
      expect(p.id).assertEqual('x');
      expect(p.isAntarctic()).assertFalse();
    })
  })
}
