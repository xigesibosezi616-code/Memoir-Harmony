/**
 * 世界笔友地图纯逻辑单测（U01 决策 14–17、21）。
 *
 * - 名片次序：自己那位在前，世界笔友按离你从近到远（西安出发：
 *   京都 2,448 < 新加坡 3,700 < 斯图尔特岛 10,785）
 * - 收件人名字的列举：各语言连接词手写（zh「、和」、en「, and」、ja「、」、
 *   ko「, 및」、fr「, et」、es「, y」），照 iOS「阿远、天野和 McRae」的语感
 * - 邮票：一位一张、南极两张、自己那位一张
 * - 收件人：own 恒留；世界笔友要会员且服务端备好；一位不剩退回 own
 * - 测试会员放行：TEST_UNLOCK 假会员把名册全算能寄（不等服务端点头）；
 *   正式包 isTestMember 恒 false，只认服务端名单
 * - 航线：收件人 + 正在看还没选的那位，不重复
 */
import { describe, it, expect } from '@ohos/hypium';
import { PenPal, PenPalCoordinate, LocalizedText } from '../../main/ets/models/PenPal';
import { OWN_PEN_PAL_ID, InTransitLetter, RouteTarget, orderedRoster, cardIds,
  joinedNames, recipientNames, stampCount, routeTargets, startCenter,
  roundedDistanceKm, distanceText, filterRecipients, mapHeightForWindow,
  sendablePenPalIds } from '../../main/ets/models/WorldMapLogic';

function text(zhHans: string, en: string): LocalizedText {
  return new LocalizedText(en, zhHans, '', en, '', '', '', '');
}

/** 一位世界笔友：姓给简中 / 英文，坐标、邮资自定 */
function penPalAt(id: string, surnameZh: string, surnameEn: string, region: string,
  lat: number, lon: number, postage: number): PenPal {
  return new PenPal(id, text(surnameZh, surnameEn), region, new PenPalCoordinate(lat, lon),
    'UTC', 'en', postage, text('', ''), text('', ''));
}

const XI_AN = new PenPalCoordinate(34.26, 108.95);

const KYOTO = penPalAt('amano', '宫下', 'Amano', 'JP', 35.03, 135.78, 1);
const SINGAPORE = penPalAt('tan', '陈', 'Tan', 'SG', 1.33, 103.85, 1);
const STEWART = penPalAt('mcrae', 'McRae', 'McRae', 'NZ', -46.90, 168.13, 1);
const ANTARCTIC = penPalAt('researcher', 'M.', 'M.', 'AQ', -64.80, -63.50, 2);

const ROSTER: PenPal[] = [STEWART, KYOTO, SINGAPORE, ANTARCTIC];

function setOf(items: string[]): Set<string> {
  const out = new Set<string>();
  for (const item of items) {
    out.add(item);
  }
  return out;
}

export default function worldMapLogicTest() {
  describe('WorldMapLogicTest', () => {
    it('ownPenPalIdIsOwn', 0, () => {
      expect(OWN_PEN_PAL_ID).assertEqual('own');
    })

    it('filterRecipientsKeepsOwnAlways', 0, () => {
      // 不是会员 / 服务端一位都没备好：own 恒留，世界笔友全去掉
      const kept = filterRecipients('own,amano,mcrae', false, setOf(['amano']));
      expect(kept.size).assertEqual(1);
      expect(kept.has(OWN_PEN_PAL_ID)).assertTrue();
    })

    it('filterRecipientsKeepsSendableWorldPenPalsForMembers', 0, () => {
      // 会员 + 服务端备好了 amano：own、amano 留，没备好的 mcrae 去掉
      const kept = filterRecipients('own,amano,mcrae', true, setOf(['amano']));
      expect(kept.size).assertEqual(2);
      expect(kept.has(OWN_PEN_PAL_ID)).assertTrue();
      expect(kept.has('amano')).assertTrue();
      expect(kept.has('mcrae')).assertFalse();
    })

    it('filterRecipientsDropsUnknownAndEmptySegments', 0, () => {
      // 不认识的 id（老信里的笔友可能已下名册）和空段都跳过
      const kept = filterRecipients('amano,,ghost,own', true, setOf(['amano']));
      expect(kept.size).assertEqual(2);
      expect(kept.has('amano')).assertTrue();
      expect(kept.has('own')).assertTrue();
    })

    it('filterRecipientsFallsBackToOwnWhenNothingLeft', 0, () => {
      // 只选了世界笔友又不是会员 → 全滤掉，退回自己那位（总有得寄）
      const notMember = filterRecipients('amano,mcrae', false, setOf(['amano']));
      expect(notMember.size).assertEqual(1);
      expect(notMember.has(OWN_PEN_PAL_ID)).assertTrue();
      // 空串也退 own
      const empty = filterRecipients('', true, setOf(['amano']));
      expect(empty.size).assertEqual(1);
      expect(empty.has(OWN_PEN_PAL_ID)).assertTrue();
    })

    it('sendablePenPalIdsTestMemberUnlocksWholeRoster', 0, () => {
      // 测试会员：服务端一位都不给（假会员不交服务器，名单对不上），名册全算能寄
      const unlocked = sendablePenPalIds(ROSTER, true, setOf([]));
      expect(unlocked.size).assertEqual(4);
      expect(unlocked.has('mcrae')).assertTrue();
      expect(unlocked.has('amano')).assertTrue();
      expect(unlocked.has('researcher')).assertTrue();
      // 服务端只给了一部分也一样全放行（以名册为准）
      const partial = sendablePenPalIds(ROSTER, true, setOf(['amano']));
      expect(partial.size).assertEqual(4);
      // 名册空：没有世界笔友可放行，空集（不会把服务端名单漏进来）
      expect(sendablePenPalIds([], true, setOf(['amano'])).size).assertEqual(0);
    })

    it('sendablePenPalIdsNonTestFollowsServerList', 0, () => {
      // 不是测试会员（正式包 / 测试包没开假会员）：原样只认服务端名单
      const ids = sendablePenPalIds(ROSTER, false, setOf(['amano', 'tan']));
      expect(ids.size).assertEqual(2);
      expect(ids.has('amano')).assertTrue();
      expect(ids.has('mcrae')).assertFalse();
    })

    it('filterRecipientsKeepsWorldPenPalsForTestMemberWithoutServer', 0, () => {
      // 端到端：测试会员 + 服务端空名单 → 选中的世界笔友照样留下（own 恒留）
      const sendable = sendablePenPalIds(ROSTER, true, setOf([]));
      const kept = filterRecipients('own,amano,mcrae', true, sendable);
      expect(kept.size).assertEqual(3);
      expect(kept.has(OWN_PEN_PAL_ID)).assertTrue();
      expect(kept.has('amano')).assertTrue();
      expect(kept.has('mcrae')).assertTrue();
    })

    it('inTransitLetterClampsProgress', 0, () => {
      expect(new InTransitLetter('l1', 'amano', -1).progress).assertEqual(0);
      expect(new InTransitLetter('l1', 'amano', 0.4).progress).assertEqual(0.4);
      expect(new InTransitLetter('l1', 'amano', 2).progress).assertEqual(1);
    })

    it('orderedRosterSortsByDistanceFromUser', 0, () => {
      const ordered = orderedRoster(ROSTER, XI_AN);
      expect(ordered.length).assertEqual(4);
      expect(ordered[0].id).assertEqual('amano');
      expect(ordered[1].id).assertEqual('tan');
      expect(ordered[2].id).assertEqual('mcrae');
      expect(ordered[3].id).assertEqual('researcher');
    })

    it('orderedRosterWithoutUserKeepsRosterOrder', 0, () => {
      const ordered = orderedRoster(ROSTER, null);
      expect(ordered.length).assertEqual(4);
      expect(ordered[0].id).assertEqual('mcrae');
      expect(ordered[1].id).assertEqual('amano');
      expect(ordered[2].id).assertEqual('tan');
      expect(ordered[3].id).assertEqual('researcher');
    })

    it('orderedRosterDoesNotMutateInput', 0, () => {
      orderedRoster(ROSTER, XI_AN);
      expect(ROSTER[0].id).assertEqual('mcrae');
    })

    it('cardIdsPutOwnFirst', 0, () => {
      const ids = cardIds(ROSTER, XI_AN);
      expect(ids.length).assertEqual(5);
      expect(ids[0]).assertEqual(OWN_PEN_PAL_ID);
      expect(ids[1]).assertEqual('amano');
      expect(ids[4]).assertEqual('researcher');
    })

    it('joinedNamesPerLanguage', 0, () => {
      // zh：「阿远、天野和 McRae」（iOS 注释里的原句）
      expect(joinedNames(['阿远', '天野', 'McRae'], 'zh-Hans')).assertEqual('阿远、天野和McRae');
      expect(joinedNames(['阿远', 'McRae'], 'zh-Hant')).assertEqual('阿远和McRae');
      // en：两位「A and B」，三位「A, B and C」
      expect(joinedNames(['Ayu', 'McRae'], 'en')).assertEqual('Ayu and McRae');
      expect(joinedNames(['Ayu', 'Amano', 'McRae'], 'en')).assertEqual('Ayu, Amano and McRae');
      // ja：全「、」；ko：最后「및」；fr：最后「et」；es：最后「y」
      expect(joinedNames(['あゆ', '天野', 'マクレイ'], 'ja')).assertEqual('あゆ、天野、マクレイ');
      expect(joinedNames(['아유', '아마노', '맥레이'], 'ko')).assertEqual('아유, 아마노 및 맥레이');
      expect(joinedNames(['Ayu', 'Amano'], 'fr')).assertEqual('Ayu et Amano');
      expect(joinedNames(['Ayu', 'Amano'], 'es')).assertEqual('Ayu y Amano');
    })

    it('joinedNamesSingleAndEmpty', 0, () => {
      expect(joinedNames([], 'en')).assertEqual('');
      expect(joinedNames(['阿远'], 'zh-Hans')).assertEqual('阿远');
    })

    it('recipientNamesInCardOrder', 0, () => {
      // 自己那位在前：收了 McRae 和自己 → 「阿远和McRae」
      const recipients = setOf(['mcrae', OWN_PEN_PAL_ID]);
      expect(recipientNames(recipients, '阿远', ROSTER, XI_AN, 'zh-Hans'))
        .assertEqual('阿远和McRae');
      // 世界笔友按离你从近到远：京都 → 斯图尔特岛
      const world = setOf(['mcrae', 'amano']);
      expect(recipientNames(world, '阿远', ROSTER, XI_AN, 'zh-Hans'))
        .assertEqual('宫下和McRae');
      // 英文取英文姓
      expect(recipientNames(world, 'Ayu', ROSTER, XI_AN, 'en'))
        .assertEqual('Amano and McRae');
    })

    it('stampCountOnePerRecipientAntarcticTwo', 0, () => {
      // 自己一张 + 京都一张 + 南极两张 = 4
      const recipients = setOf([OWN_PEN_PAL_ID, 'amano', 'researcher']);
      expect(stampCount(recipients, ROSTER)).assertEqual(4);
      // 只有自己 = 1
      expect(stampCount(setOf([OWN_PEN_PAL_ID]), ROSTER)).assertEqual(1);
      // 不认识的 id 当一张（老信里的笔友可能已不在名册）
      expect(stampCount(setOf(['ghost']), ROSTER)).assertEqual(1);
    })

    it('routeTargetsRecipientsThenFocused', 0, () => {
      const recipients = setOf(['tan']);
      const targets: RouteTarget[] = routeTargets(recipients, 'amano', ROSTER);
      expect(targets.length).assertEqual(2);
      expect(targets[0].penPal.id).assertEqual('tan');
      expect(targets[0].isRecipient).assertTrue();
      expect(targets[1].penPal.id).assertEqual('amano');
      expect(targets[1].isRecipient).assertFalse();
    })

    it('routeTargetsDoNotDuplicateFocusedRecipient', 0, () => {
      const targets = routeTargets(setOf(['amano']), 'amano', ROSTER);
      expect(targets.length).assertEqual(1);
      expect(targets[0].penPal.id).assertEqual('amano');
      expect(targets[0].isRecipient).assertTrue();
    })

    it('routeTargetsIgnoreUnknownFocused', 0, () => {
      const targets = routeTargets(setOf([]), 'ghost', ROSTER);
      expect(targets.length).assertEqual(0);
    })

    it('startCenterFollowsUserLongitude', 0, () => {
      const center = startCenter(XI_AN);
      expect(center.lat).assertEqual(10);
      expect(center.lon).assertEqual(108.95);
      const fallback = startCenter(null);
      expect(fallback.lat).assertEqual(10);
      expect(fallback.lon).assertEqual(110);
    })

    it('roundedDistanceTensOfKilometers', 0, () => {
      // 西安 → 斯图尔特岛 ≈ 10,78x km → 取整到十公里 10,780
      expect(roundedDistanceKm(XI_AN, STEWART.coordinate)).assertEqual(10780);
      // 西安 → 京都 ≈ 2,448 → 2,450
      expect(roundedDistanceKm(XI_AN, KYOTO.coordinate)).assertEqual(2450);
    })

    it('distanceTextFollowsLanguageUnit', 0, () => {
      const zh = distanceText(10790, 'zh-Hans');
      expect(zh.includes('公里')).assertTrue();
      expect(zh.includes('10,790')).assertTrue();
      const en = distanceText(10790, 'en');
      expect(en.includes('km')).assertTrue();
      expect(en.includes('10,790')).assertTrue();
    })

    it('mapHeightForWindowClampsToRange', 0, () => {
      // 常规手机（≈876vp 窗高）：34% ≈ 298，落在区间内
      expect(mapHeightForWindow(876)).assertEqual(298);
      // 大窗（平板 / 折叠屏展开）封顶 320
      expect(mapHeightForWindow(1200)).assertEqual(320);
      // 小窗（分屏）保底 140
      expect(mapHeightForWindow(300)).assertEqual(140);
      // 窗高未知（0）：按 782.65 兜底 → 266
      expect(mapHeightForWindow(0)).assertEqual(266);
    })
  })
}
