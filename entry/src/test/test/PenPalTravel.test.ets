/**
 * 路程单测（U01「标准答案」—— 两端必须算得一样，iOS 已实现）。
 *
 * 大圆距离 haversine、地球半径 6371.0088 km：
 * - 西安 → 斯图尔特岛 ≈ 10,785 km（far，36–72 小时）
 * - 西安 → 京都 ≈ 2,448 km（near，6–24）
 * - 西安 → 新加坡 ≈ 3,700 km（middle，18–48）
 * - 西安 → 南极 ≈ 16,581 km（南极固定 72–120）
 * - 上海 → 济州 ≈ 563 km（near）
 * - 没有位置 → unknownDistance 18–48
 */
import { describe, it, expect } from '@ohos/hypium';
import { PenPal, PenPalCoordinate, LocalizedText } from '../../main/ets/models/PenPal';
import { ReplyTime, ReplyHours, replyHoursOf, arrivalDateMs, replyTimeTo,
  distanceKilometers, pointOnGreatCircle, EARTH_RADIUS_KM } from '../../main/ets/models/PenPalTravel';

const EMPTY_TEXT = new LocalizedText('', '', '', '', '', '', '', '');

function penPalAt(id: string, region: string, lat: number, lon: number): PenPal {
  return new PenPal(id, EMPTY_TEXT, region, new PenPalCoordinate(lat, lon),
    'UTC', 'en', 1, EMPTY_TEXT, EMPTY_TEXT);
}

const XI_AN = new PenPalCoordinate(34.26, 108.95);
const SHANGHAI = new PenPalCoordinate(31.23, 121.47);

const STEWART = penPalAt('mcrae', 'NZ', -46.90, 168.13);
const KYOTO = penPalAt('amano', 'JP', 35.03, 135.78);
const SINGAPORE = penPalAt('tan', 'SG', 1.33, 103.85);
const ANTARCTIC = penPalAt('researcher', 'AQ', -64.80, -63.50);

const TOLERANCE_KM = 30;

export default function penPalTravelTest() {
  describe('PenPalTravelTest', () => {
    it('earthRadiusMatchesIos', 0, () => {
      expect(Math.abs(EARTH_RADIUS_KM - 6371.0088) < 1e-9).assertTrue();
    })

    it('distanceXianToStewartIsland', 0, () => {
      const d = distanceKilometers(XI_AN, STEWART.coordinate);
      expect(Math.abs(d - 10785) <= TOLERANCE_KM).assertTrue();
    })

    it('distanceXianToKyoto', 0, () => {
      const d = distanceKilometers(XI_AN, KYOTO.coordinate);
      expect(Math.abs(d - 2448) <= TOLERANCE_KM).assertTrue();
    })

    it('distanceXianToSingapore', 0, () => {
      const d = distanceKilometers(XI_AN, SINGAPORE.coordinate);
      expect(Math.abs(d - 3700) <= TOLERANCE_KM).assertTrue();
    })

    it('distanceXianToAntarctica', 0, () => {
      const d = distanceKilometers(XI_AN, ANTARCTIC.coordinate);
      expect(Math.abs(d - 16581) <= TOLERANCE_KM).assertTrue();
    })

    it('distanceShanghaiToJeju', 0, () => {
      const jeju = new PenPalCoordinate(33.55, 126.80);
      const d = distanceKilometers(SHANGHAI, jeju);
      expect(Math.abs(d - 563) <= TOLERANCE_KM).assertTrue();
    })

    it('distanceIsSymmetric', 0, () => {
      const a = distanceKilometers(XI_AN, STEWART.coordinate);
      const b = distanceKilometers(STEWART.coordinate, XI_AN);
      expect(Math.abs(a - b) < 1e-6).assertTrue();
    })

    it('distanceToSelfIsZero', 0, () => {
      expect(distanceKilometers(XI_AN, new PenPalCoordinate(34.26, 108.95)) < 1e-6).assertTrue();
    })

    it('replyTimeFollowsDistanceTiers', 0, () => {
      expect(replyTimeTo(STEWART, XI_AN)).assertEqual(ReplyTime.Far);
      expect(replyTimeTo(KYOTO, XI_AN)).assertEqual(ReplyTime.Near);
      expect(replyTimeTo(SINGAPORE, XI_AN)).assertEqual(ReplyTime.Middle);
      expect(replyTimeTo(ANTARCTIC, XI_AN)).assertEqual(ReplyTime.Antarctic);
    })

    it('replyTimeWithoutUserLocation', 0, () => {
      expect(replyTimeTo(STEWART, null)).assertEqual(ReplyTime.UnknownDistance);
      // 南极不看你在哪
      expect(replyTimeTo(ANTARCTIC, null)).assertEqual(ReplyTime.Antarctic);
    })

    it('replyHoursMatchU01', 0, () => {
      const expectRange = (replyTime: ReplyTime, min: number, max: number): void => {
        const hours: ReplyHours = replyHoursOf(replyTime);
        expect(hours.minHours).assertEqual(min);
        expect(hours.maxHours).assertEqual(max);
      };
      expectRange(ReplyTime.OwnPenPal, 2, 6);
      expectRange(ReplyTime.Near, 6, 24);
      expectRange(ReplyTime.Middle, 18, 48);
      expectRange(ReplyTime.UnknownDistance, 18, 48);
      expectRange(ReplyTime.Far, 36, 72);
      expectRange(ReplyTime.Antarctic, 72, 120);
    })

    it('arrivalDateSpansTheTier', 0, () => {
      const sent = 1_000_000_000;
      // random01 = 0 → 下界；= 1 → 上界；= 0.5 → 中间
      expect(arrivalDateMs(sent, ReplyTime.Near, 0)).assertEqual(sent + 6 * 3600 * 1000);
      expect(arrivalDateMs(sent, ReplyTime.Near, 1)).assertEqual(sent + 24 * 3600 * 1000);
      expect(arrivalDateMs(sent, ReplyTime.Near, 0.5)).assertEqual(sent + 15 * 3600 * 1000);
      // 南极 72–120
      expect(arrivalDateMs(sent, ReplyTime.Antarctic, 1)).assertEqual(sent + 120 * 3600 * 1000);
    })

    it('arrivalDateClampsRandomAndScale', 0, () => {
      const sent = 1_000_000_000;
      // 越界随机数夹回 [0,1]
      expect(arrivalDateMs(sent, ReplyTime.OwnPenPal, -5)).assertEqual(sent + 2 * 3600 * 1000);
      expect(arrivalDateMs(sent, ReplyTime.OwnPenPal, 9)).assertEqual(sent + 6 * 3600 * 1000);
      // timeScale 60：一小时走完一天（开发加速）
      const fast = arrivalDateMs(sent, ReplyTime.Near, 1, 60);
      expect(fast).assertEqual(sent + 24 * 3600 * 1000 / 60);
    })

    it('pointOnGreatCircleEndpoints', 0, () => {
      const start = pointOnGreatCircle(XI_AN, STEWART.coordinate, 0);
      expect(Math.abs(start.lat - XI_AN.lat) < 1e-6).assertTrue();
      expect(Math.abs(start.lon - XI_AN.lon) < 1e-6).assertTrue();
      const end = pointOnGreatCircle(XI_AN, STEWART.coordinate, 1);
      expect(Math.abs(end.lat - STEWART.coordinate.lat) < 1e-6).assertTrue();
      expect(Math.abs(end.lon - STEWART.coordinate.lon) < 1e-6).assertTrue();
    })

    it('pointOnGreatCircleMidpointPlausible', 0, () => {
      const mid = pointOnGreatCircle(XI_AN, KYOTO.coordinate, 0.5);
      // 中点离两端各约一半路程
      const half = distanceKilometers(XI_AN, KYOTO.coordinate) / 2;
      expect(Math.abs(distanceKilometers(XI_AN, mid) - half) < 60).assertTrue();
      expect(Math.abs(distanceKilometers(mid, KYOTO.coordinate) - half) < 60).assertTrue();
    })

    it('pointOnGreatCircleClampsFraction', 0, () => {
      const before = pointOnGreatCircle(XI_AN, KYOTO.coordinate, -1);
      expect(Math.abs(before.lat - XI_AN.lat) < 1e-6).assertTrue();
      const after = pointOnGreatCircle(XI_AN, KYOTO.coordinate, 2);
      expect(Math.abs(after.lat - KYOTO.coordinate.lat) < 1e-6).assertTrue();
    })

    it('pointOnGreatCircleSamePointReturnsIt', 0, () => {
      const p = pointOnGreatCircle(XI_AN, new PenPalCoordinate(34.26, 108.95), 0.5);
      expect(Math.abs(p.lat - XI_AN.lat) < 1e-6).assertTrue();
      expect(Math.abs(p.lon - XI_AN.lon) < 1e-6).assertTrue();
    })
  })
}
