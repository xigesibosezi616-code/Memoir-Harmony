/**
 * 你大概在哪（U01 决策 17）—— 世界笔友地图上的「你」、信要走多远、
 * 地图该是白天还是夜里，都靠它。对应 iOS `Services/PenPals/ApproximateLocation.swift`。
 *
 * - **只在本机用，不上传**（产品定：位置不离开手机）
 * - 记下来时取整到 0.1°（约 10 公里），几公里的精度就够
 * - 记一份在本机：下次打开地图不用等定位，「你」立刻就在
 * - 不主动弹权限框：地图上有一行「打开定位」，用户点了才问
 *   （先问过、给过的话直接定位；鸿蒙拒过不再弹窗，只能引导去系统设置）
 */
import { geoLocationManager } from '@kit.LocationKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPrefs } from './AppPrefs';
import { PenPalCoordinate } from '../models/PenPal';

const DOMAIN = 0x0000;
const TAG = 'ApproximateLocation';

/** 本机记一份上次的位置（iOS `penPalMapLastLocation` 同名） */
const PREF_KEY_LAST_LOCATION = 'penPalMapLastLocation';
/** 问过定位没有（鸿蒙分不清「没问过」和「拒过」，自己记；问过且没给 = 拒了） */
const PREF_KEY_LOCATION_ASKED = 'penPalMapLocationAsked';

const WANTED_PERMISSIONS: Array<Permissions> = [
  'ohos.permission.LOCATION',
  'ohos.permission.APPROXIMATELY_LOCATION'
];

/** 取整到 0.1°（约 10 公里） */
function roundedTenth(value: number): number {
  return Math.round(value * 10) / 10;
}

export class ApproximateLocation {
  /** 取整后的坐标；null = 还不知道（没给权限，或者还没定到） */
  coordinate: PenPalCoordinate | null = null;

  constructor() {
    this.coordinate = ApproximateLocation.loadSaved();
  }

  /** 有定位权限吗（不弹窗，只查状态） */
  private hasPermission(context: common.Context): boolean {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const tokenId = context.applicationInfo.accessTokenId;
      for (const permission of WANTED_PERMISSIONS) {
        if (atManager.checkAccessTokenSync(tokenId, permission) !== 0) {
          return false;
        }
      }
      return true;
    } catch (err) {
      const be = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'checkAccessToken failed: %{public}d %{public}s',
        be.code, be.message ?? '');
      return false;
    }
  }

  /** 能用定位就定一次（进地图页时调；没权限不动） */
  async refresh(context: common.Context): Promise<void> {
    if (!this.hasPermission(context)) {
      return;
    }
    await this.locateOnce();
  }

  /** 用户点了「打开定位」：没问过就问（弹窗），问过没给直接试一把 */
  async requestPermission(context: common.Context): Promise<void> {
    const atManager = abilityAccessCtrl.createAtManager();
    let granted = false;
    try {
      const result = await atManager.requestPermissionsFromUser(context, WANTED_PERMISSIONS);
      granted = result.authResults.length > 0;
      for (const code of result.authResults) {
        if (code !== 0) {
          granted = false;
        }
      }
    } catch (err) {
      const be = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'requestPermissions failed: %{public}d %{public}s',
        be.code, be.message ?? '');
      granted = false;
    }
    AppPrefs.putBool(PREF_KEY_LOCATION_ASKED, true);
    if (granted) {
      await this.locateOnce();
    }
  }

  /**
   * 定位被拒了吗（问过、且现在没权限 → 拒了，只能引导去系统设置）。
   * 没问过不算拒：这时点「打开定位」会弹系统权限框。
   */
  isDenied(context: common.Context): boolean {
    return AppPrefs.getBool(PREF_KEY_LOCATION_ASKED, false) && !this.hasPermission(context);
  }

  /** 定一次、取整、记下（定不到就用上次记下的，不打扰用户） */
  private async locateOnce(): Promise<void> {
    try {
      const location = await geoLocationManager.getCurrentLocation();
      const rounded = new PenPalCoordinate(
        roundedTenth(location.latitude), roundedTenth(location.longitude));
      this.coordinate = rounded;
      AppPrefs.putString(PREF_KEY_LAST_LOCATION, `${rounded.lat},${rounded.lon}`);
    } catch (err) {
      const be = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'getCurrentLocation failed: %{public}d %{public}s',
        be.code, be.message ?? '');
    }
  }

  /** 上次记下的位置（AppPrefs 里 "lat,lon"）；没有 / 坏了返回 null */
  private static loadSaved(): PenPalCoordinate | null {
    const raw = AppPrefs.getString(PREF_KEY_LAST_LOCATION, '');
    if (raw.length === 0) {
      return null;
    }
    const parts = raw.split(',');
    if (parts.length !== 2) {
      return null;
    }
    const lat = Number(parts[0]);
    const lon = Number(parts[1]);
    if (!Number.isFinite(lat) || !Number.isFinite(lon) ||
      Math.abs(lat) > 90 || Math.abs(lon) > 180) {
      return null;
    }
    return new PenPalCoordinate(lat, lon);
  }
}
