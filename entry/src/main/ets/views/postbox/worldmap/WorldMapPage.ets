/**
 * 世界笔友地图（U01 决策 13–17、21–23）。对应 iOS
 * `Views/PostBox/WorldMap/WorldMapPage.swift`。
 *
 * 上面是一张摊开的地图（Map Kit 标准图，四周晕进纸色），下面一叠名片：
 * - 地图固定高（窗高 34%，夹在 140~320vp）：角上没有 +/− 缩放键（手势缩放
 *   本来就顺手），左下角比例尺常显
 * - 滑名片 = 翻到下一位，地图也飞到他身边（focusCamera，0.9s easeInOut，
 *   iOS withAnimation 同款；远近固定 FOCUS_ZOOM 一档能看清城市；
 *   自己那位没有住址，翻到他回开场世界一览）
 * - 点地图上的墨点 = 名片翻到他
 * - 名片上「寄给他」= 加进收件人：墨点换成邮戳色，从你这里画一条虚线航线
 * - 已寄出、还在路上的信 = 航线上的小信封
 * - 官方标题栏：系统返回键独占一行；「今雨与雅故」+ 右上角邮票夹在内容区顶上
 * - 最下一行写这次寄给谁、要贴几张邮票；「好了」回到邮筒
 *
 * 自己起名的那位没有住址，不在地图上：名片第一张，翻到他时地图回到「你」。
 * 地图跟着你这里的白天黑夜走（MapDaylight，三主题一样）。
 *
 * 鸿蒙实现要点（iOS 差异）：
 * - Map Kit 的 MapPolylineOptions 没有 dash 参数——虚线测地线画在盖在地图
 *   上的 ArkUI Canvas 里（pointOnGreatCircle 采样 + toScreenLocation 投影），
 *   相机一动（cameraMove 逐帧 / cameraIdle 收尾）就重投影重画
 * - 墨点 /「你」/ 在途信封也是 ArkUI 覆盖层（不用 Marker）：@Observed 的
 *   WorldMark 实例就地改坐标，@ObjectLink 子组件跟着动（数组键不变也能刷）
 * - 相机起点写进 MapOptions（不等挂载再设——iOS init 注释同款排雷）
 * - 收件人存 AppStorage（'postRecipients'），邮筒页和这里双向同步
 */
import { MapComponent, map, mapCommon } from '@kit.MapKit';
import { bundleManager, common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../../theme/AppTheme';
import { BambooTheme } from '../../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../../theme/ThemeManager';
import { STORAGE_KEY_APP_LANGUAGE } from '../../../services/LanguageManager';
import { STORAGE_KEY_SAFE_AREA_TOP_VP, STORAGE_KEY_SAFE_AREA_BOTTOM_VP,
  STORAGE_KEY_WINDOW_HEIGHT_VP } from '../../../services/ImmersiveChrome';
import { AppEnvironment } from '../../../environment/AppEnvironment';
import { AppDatabase } from '../../../data/Database';
import { LetterRepository } from '../../../data/LetterRepository';
import { Letter } from '../../../models/Letter';
import { LetterDelivery } from '../../../models/LetterDelivery';
import { StampWallet } from '../../../models/Api';
import { PenPal, PenPalCoordinate } from '../../../models/PenPal';
import { PenPalRoster } from '../../../services/PenPalRoster';
import { ApproximateLocation } from '../../../services/ApproximateLocation';
import { isNight } from '../../../models/MapDaylight';
import { MapInk, mapInkOf, withAlpha } from '../../../models/MapInk';
import { pointOnGreatCircle } from '../../../models/PenPalTravel';
import { postmarkInkHex } from '../../../models/PostBoxLogic';
import {
  OWN_PEN_PAL_ID,
  STORAGE_KEY_POST_RECIPIENTS,
  InTransitLetter,
  cardIds,
  mapHeightForWindow,
  recipientNames,
  stampCount,
  routeTargets,
  startCenter,
  filterRecipients,
  sendablePenPalIds
} from '../../../models/WorldMapLogic';
import { STORAGE_KEY_PEN_PAL_NAME } from '../../../services/AppPrefs';
import { PenPalName } from '../../../models/PenPalName';
import { LetterPalette } from '../LetterPalette';
import { MarkStamp } from '../StampPackCard';
import { PenPalCard, PEN_PAL_CARD_HEIGHT } from './PenPalCard';
import { PenPalDot, YouMark, TransitEnvelopeMark } from './PenPalMapMarks';

const DOMAIN = 0x0000;
const TAG = 'WorldMapPage';

/** 「此刻」推进间隔：他那里几点、天黑没黑、在途信走到哪儿（iOS 60 秒） */
const NOW_TICK_INTERVAL_MS: number = 60000;
/** 地图内缩：Map Kit 的「地图」标志和法律信息要露在晕边外面（iOS safeAreaPadding 同款） */
const MAP_INSET_H_VP: number = 14;
const MAP_INSET_BOTTOM_VP: number = 26;
/** 四周晕进纸色的宽（iOS EdgeFade：上 34、下 22、左右 18） */
const EDGE_FADE_TOP_VP: number = 34;
const EDGE_FADE_BOTTOM_VP: number = 22;
const EDGE_FADE_SIDE_VP: number = 18;
/** 起始 / 最大最小的缩放：下限 2（Map Kit 的底；地图改小后 3 档视野只剩
 *  ~46° 纬度、「你」都在画面外），上限 6 是决策 23 的最近一档（≈0–125–250 公里比例尺） */
const START_ZOOM: number = 2;
const MIN_ZOOM: number = 2;
const MAX_ZOOM: number = 6;
/** 滑到哪位笔友，地图就飞到谁身边：这一档能看清城市（决策 23 的 3–6 之间） */
const FOCUS_ZOOM: number = 5;
/** 相机飞过去 / 飞回来多远（iOS 0.9s easeInOut） */
const REVEAL_DURATION_MS: number = 900;
/** 航线采样段数（测地线画虚线，一段一投影） */
const ROUTE_SEGMENTS: number = 32;
/** 滑名片 / 翻名片一屏露多少（iOS contentMargins 28，两边各露邻居一条边） */
const CARD_MARGIN_VP: number = 28;
/** 卡片左右留白：相邻两张名片中间的缝 = 左右各 8vp（用户反馈：名片要分开） */
const CARD_GAP_VP: number = 8;
/** 标题栏里返回键那一行的高（用户定：返回键单独一行，不跟标题挤） */
const TITLE_BAR_ROW_VP: number = 56;
/** 标题栏顶上的富余：栏整体让开状态栏，返回键在栏内居中 */
const TITLE_BAR_SLACK_VP: number = 28;
/** 最下一行离窗口底：安全区 + 102（躲开悬浮胶囊 Tab 栏，邮筒页叠纸同款节奏） */
const BOTTOM_CLEARANCE_VP: number = 102;

/** 地图上的一个标记（覆盖层组件）：坐标是叠放层的 vp，就地改、就地跟 */
@Observed
class WorldMark {
  /** ForEach 的键（'you' / 笔友 id / 'transit:' + 信 id） */
  readonly key: string;
  /** 对应的笔友 id（you 也是 ''，渲染时按 kind 分） */
  readonly penPalId: string;
  /** 0 = 你，1 = 笔友墨点，2 = 在途信封 */
  readonly kind: number;
  /** 叠放层里的 x（vp；写进 .position） */
  xVp: number;
  /** 叠放层里的 y（vp） */
  yVp: number;
  /** 在地图外就藏（相机一动画，出界的标记不挂在外面） */
  visible: boolean;
  /** 墨点是不是收件人（换邮戳色、大一点） */
  isRecipient: boolean;
  /** 是不是正在看的那位（再大一点、写出姓） */
  isFocused: boolean;
  /** 名签上写的姓 */
  name: string;

  constructor(key: string, penPalId: string, kind: number) {
    this.key = key;
    this.penPalId = penPalId;
    this.kind = kind;
    this.xVp = 0;
    this.yVp = 0;
    this.visible = false;
    this.isRecipient = false;
    this.isFocused = false;
    this.name = '';
  }
}

/** 0xAARRGGBB 数值 → Canvas 的 rgba() 字串（航线画在 Canvas 里） */
function argbCss(argb: number): string {
  const a = ((argb >>> 24) & 0xFF) / 255;
  const r = (argb >>> 16) & 0xFF;
  const g = (argb >>> 8) & 0xFF;
  const b = argb & 0xFF;
  return `rgba(${r},${g},${b},${Math.round(a * 1000) / 1000})`;
}

/** 按 id 找一位；找不到 null（老信里的笔友可能已不在名册） */
function penPalById(id: string, roster: PenPal[]): PenPal | null {
  for (const penPal of roster) {
    if (penPal.id === id) {
      return penPal;
    }
  }
  return null;
}

/** 系统路由表入口（router_map.json → name `WorldMap`）：邮筒 tab 内推入 */
@Builder
export function WorldMapBuilder() {
  WorldMapPage()
}

@Component
export struct WorldMapPage {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_APP_LANGUAGE) appLanguage: string = 'zh-Hans';
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  /** 窗口高（vp；地图高度按它定，ImmersiveChrome 挂载时写） */
  @StorageProp(STORAGE_KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 0;
  @Consume env: AppEnvironment;
  /** 笔友名镜像（改名处写镜像，这里即时跟上） */
  @StorageProp(STORAGE_KEY_PEN_PAL_NAME) penPalName: string = '';
  /** 这次寄给谁（id 逗号分隔，自己那位是 own；邮筒页同键双向同步） */
  @StorageProp(STORAGE_KEY_POST_RECIPIENTS) @Watch('onDataChanged') recipientsStorage: string = OWN_PEN_PAL_ID;
  /** 世界笔友名册 */
  @State private roster: PenPal[] = [];
  /** 名册加载完了（名片 / 墨点都等它） */
  @State private rosterLoaded: boolean = false;
  /** 现在能寄的世界笔友（服务端备好了人设的那几位；不在里头的名片写「即将开放」） */
  @State private availablePenPals: Set<string> = new Set<string>();
  /** 你大概在哪（只在本机用；null = 还不知道） */
  @State private userLoc: PenPalCoordinate | undefined = undefined;
  /** 正在翻的那位的 id（'' = 还没定，名册一到先翻自己那位或路由参数指的那位） */
  @State @Watch('onFocusedIdChanged') private focusedId: string = '';
  /** 名片 Swiper 当前停在第几张 */
  @State private swiperIndex: number = 0;
  /** 你这里天黑了没有——决定地图是深色还是浅色 */
  @State private isNight: boolean = false;
  /** 「此刻」（毫秒），60 秒推进一次 */
  @State private nowMs: number = Date.now();
  /** 邮票夹里有几张（右上角一张小邮票 + 数字；undefined = 不知道，不显示） */
  @State private stampBalance: number | undefined = undefined;
  /** 信（算在途信封用；只读一遍，寄信只发生在邮筒页） */
  @State private letters: Letter[] = [];
  /** 覆盖层标记（you + 墨点 + 在途信封；坐标就地改） */
  @State private marks: WorldMark[] = [];
  /** 地图叠放层的尺寸（投影换算 / 出界判定 / Canvas 重画） */
  @State private mapWidthVp: number = 0;
  @State private mapHeightVp: number = 0;

  private navPathStack: NavPathStack = new NavPathStack();
  private location: ApproximateLocation = new ApproximateLocation();
  private mapController: map.MapComponentController | undefined = undefined;
  private mapReady: boolean = false;
  /** 相机起点（aboutToAppear 按你的位置重设；Map Kit 构造参数只吃一次） */
  private mapOptions: mapCommon.MapOptions = {
    mapType: mapCommon.MapType.STANDARD,
    position: { target: { longitude: 110, latitude: 10 }, zoom: START_ZOOM },
    minZoom: MIN_ZOOM,
    maxZoom: MAX_ZOOM
  };
  /** 航线 Canvas（虚线测地线画在这里，盖在地图上、不挡手势） */
  private routeCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private nowTimerId: number = -1;
  /** 路由参数：一打开先翻到哪一位（信箱里点「他在哪」；'' = 自己那位） */
  private initialFocus: string = '';
  private onReadyHappened: boolean = false;
  /** 本地化的「笔友」兜底词（没起名时显示） */
  private unnamedPenPalLabel: string = '笔友';

  aboutToAppear(): void {
    const uiContext = this.getUIContext().getHostContext();
    if (uiContext !== undefined) {
      this.unnamedPenPalLabel =
        uiContext.resourceManager.getStringSync($r('app.string.s_8dcc9a2d73').id);
    }
    this.userLoc = this.location.coordinate ?? undefined;
    this.isNight = isNight(Date.now(), this.location.coordinate,
      new Date().getHours());
    // 相机起点必须在这里给（iOS init 同款排雷）：你所在的经度、纬度 10°
    const center = startCenter(this.location.coordinate);
    const options: mapCommon.MapOptions = {
      mapType: mapCommon.MapType.STANDARD,
      position: {
        target: {
          longitude: center.lon,
          latitude: center.lat
        },
        zoom: START_ZOOM
      },
      minZoom: MIN_ZOOM,
      maxZoom: MAX_ZOOM
    };
    this.mapOptions = options;
    this.nowTimerId = setInterval((): void => {
      this.nowMs = Date.now();
      this.isNight = isNight(this.nowMs, this.userLoc ?? null,
        new Date(this.nowMs).getHours());
      this.applyDayNight();
      this.refreshOverlays();
    }, NOW_TICK_INTERVAL_MS);
    this.loadRoster(uiContext);
    this.loadLetters(uiContext);
    this.fetchStampBalance();
    // 用户给了定位权限就直接定一次（不弹框；没权限不动）
    const context = uiContext;
    if (context !== undefined) {
      this.location.refresh(context).then((): void => {
        this.userLoc = this.location.coordinate ?? undefined;
        this.rebuildMarks();
        this.refreshOverlays();
      });
    }
  }

  aboutToDisappear(): void {
    if (this.nowTimerId >= 0) {
      clearInterval(this.nowTimerId);
      this.nowTimerId = -1;
    }
  }

  /** 名册（rawfile 的 penpals.json，PenPalRoster 缓存） */
  private loadRoster(context: common.Context | undefined): void {
    if (context === undefined) {
      return;
    }
    PenPalRoster.all(context)
      .then((roster: PenPal[]): void => {
        this.roster = roster;
        this.rosterLoaded = true;
        this.tryResolveFocus();
        this.rebuildMarks();
        this.refreshOverlays();
      })
      .catch((err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'load roster failed: %{public}s', JSON.stringify(err));
        this.rosterLoaded = true;
        this.tryResolveFocus();
      });
  }

  /** 信（画在途信封用；寄信只发生在邮筒页，这里读一遍就够） */
  private loadLetters(context: common.Context | undefined): void {
    if (context === undefined) {
      return;
    }
    const load = async (): Promise<void> => {
      try {
        const store = await AppDatabase.open(context);
        this.letters = await LetterRepository.listLetters(store);
        this.rebuildMarks();
        this.refreshOverlays();
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'load letters failed: %{public}s', JSON.stringify(err));
      }
    };
    load();
  }

  /** 右上角邮票夹：问得到就显示（一张小邮票 + 数字，用户定） */
  private fetchStampBalance(): void {
    const session = this.env.session;
    const auth = this.env.auth;
    const token = session !== undefined ? session.token : null;
    if (session === undefined || !session.isLoggedIn() || auth === undefined || token === null) {
      this.stampBalance = undefined;
      return;
    }
    auth.fetchStamps(token)
      .then((wallet: StampWallet): void => {
        this.stampBalance = wallet.balance;
      })
      .catch((err: BusinessError): void => {
        // 只是显示用，问不到就不显示
        hilog.warn(DOMAIN, TAG, 'fetch stamps failed: %{public}s', JSON.stringify(err));
      });
  }

  /** 现在能寄的世界笔友（GET /penpals）；问不到当作一个都没有（名片写「即将开放」） */
  private fetchSendable(): void {
    const session = this.env.session;
    const auth = this.env.auth;
    const token = session !== undefined ? session.token : null;
    if (session === undefined || !session.isLoggedIn() || auth === undefined || token === null) {
      this.availablePenPals = new Set<string>();
      return;
    }
    auth.fetchPenPals(token)
      .then((ids: string[]): void => {
        this.availablePenPals = new Set<string>(ids);
      })
      .catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'fetch pen pals failed: %{public}s', JSON.stringify(err));
      });
  }

  // ---- 状态推导（纯取值，供 build 用） ----

  private isMemberNow(): boolean {
    return this.env.membership !== undefined && this.env.membership.isMember;
  }

  /** 测试会员开着吗（TEST_UNLOCK 假会员；正式包恒 false） */
  private isTestMemberNow(): boolean {
    return this.env.membership !== undefined && this.env.membership.isTestMember;
  }

  /** 现在能寄的世界笔友 id：测试会员全放行（方便测试），否则只认服务端名单 */
  private sendableIds(): Set<string> {
    return sendablePenPalIds(this.roster, this.isTestMemberNow(), this.availablePenPals);
  }

  private ink(): MapInk {
    return mapInkOf(this.isNight, postmarkInkHex(this.theme.id));
  }

  private palette(): LetterPalette {
    return LetterPalette.of(this.theme.id);
  }

  private ownPenPalName(): string {
    return PenPalName.display(this.penPalName, this.unnamedPenPalLabel);
  }

  /** 名片的完整次序（id）：自己那位第一张，然后按离你从近到远 */
  private cardIdList(): string[] {
    return cardIds(this.roster, this.userLoc ?? null);
  }

  /** 现在有效的收件人（寄不了的划掉，一个都不剩退回自己那位） */
  private recipientSet(): Set<string> {
    return filterRecipients(this.recipientsStorage, this.isMemberNow(), this.sendableIds());
  }

  /** 收件人的名字连成一句（按名片顺序、App 语言的列举方式） */
  private recipientNamesText(): string {
    return recipientNames(this.recipientSet(), this.ownPenPalName(), this.roster,
      this.userLoc ?? null, this.appLanguage);
  }

  /** 这次要贴几张（一位一张、南极两张，自己那位也算一张） */
  private postageNeeded(): number {
    return stampCount(this.recipientSet(), this.roster);
  }

  /** 寄出了、还在路上的世界笔友信（画在航线上） */
  private transitLetters(): InTransitLetter[] {
    const out: InTransitLetter[] = [];
    for (const letter of this.letters) {
      const penPalId = letter.penPalId;
      if (penPalId === undefined || penPalId.length === 0) {
        continue;
      }
      if (penPalById(penPalId, this.roster) === null) {
        continue;
      }
      if (LetterDelivery.hasArrived(letter, this.nowMs)) {
        continue;
      }
      const arrival = LetterDelivery.arrivalOf(letter);
      const start = letter.generatedAt;
      if (arrival <= start) {
        continue;
      }
      out.push(new InTransitLetter(letter.id, penPalId, (this.nowMs - start) / (arrival - start)));
    }
    return out;
  }

  // ---- 覆盖层（墨点 / 航线） ----

  /** 标记集合变了才重建（名册 / 信 / 收件人到齐、翻开一位）；坐标刷新走就地改 */
  private rebuildMarks(): void {
    // ForEach 键相同不重建组件——实例也按 key 复用、就地改，不然 @ObjectLink
    // 盯着旧实例，滑一次卡片墨点就断更（visible 永远是初值 false）
    const previous = new Map<string, WorldMark>();
    for (const mark of this.marks) {
      previous.set(mark.key, mark);
    }
    const marks: WorldMark[] = [];
    marks.push(this.markFor(previous, 'you', '', 0));
    for (const transit of this.transitLetters()) {
      marks.push(this.markFor(previous, `transit:${transit.id}`, transit.penPalId, 2));
    }
    // 正在看的那位最后画，压在别人上面（京都和东京挨得很近）
    const focused = this.focusedId;
    for (const penPal of this.roster) {
      if (penPal.id === focused) {
        continue;
      }
      marks.push(this.markFor(previous, penPal.id, penPal.id, 1));
    }
    if (penPalById(focused, this.roster) !== null) {
      marks.push(this.markFor(previous, focused, focused, 1));
    }
    this.marks = marks;
  }

  /** 按 key 复用旧实例（penPalId / kind 没变才复用）；没有就 new 一个 */
  private markFor(previous: Map<string, WorldMark>, key: string,
    penPalId: string, kind: number): WorldMark {
    const old = previous.get(key);
    if (old !== undefined && old.penPalId === penPalId && old.kind === kind) {
      return old;
    }
    return new WorldMark(key, penPalId, kind);
  }

  /** MapPoint（px，地图组件内）→ 叠放层 vp（含内缩偏移） */
  private toStackVp(point: mapCommon.MapPoint): [number, number] {
    const ui = this.getUIContext();
    return [ui.px2vp(point.positionX) + MAP_INSET_H_VP, ui.px2vp(point.positionY)];
  }

  /** 相机一动就重投影：墨点 /「你」/ 在途信封就位，航线重画 */
  private refreshOverlays(): void {
    const controller = this.mapController;
    if (controller === undefined || !this.mapReady) {
      return;
    }
    const projection = controller.getProjection();
    const me = this.userLoc ?? null;
    const languageKey = this.appLanguage;
    for (const mark of this.marks) {
      if (mark.kind === 0) {
        // 你
        if (me === null) {
          mark.visible = false;
          continue;
        }
        const projected = this.toStackVp(projection.toScreenLocation(
          { longitude: me.lon, latitude: me.lat }));
        mark.xVp = projected[0];
        mark.yVp = projected[1];
        mark.visible = this.inBounds(projected[0], projected[1], 40, 50);
        continue;
      }
      if (mark.kind === 2) {
        // 在途信封：走到航线的哪一段了
        if (me === null) {
          mark.visible = false;
          continue;
        }
        const penPal = penPalById(mark.penPalId, this.roster);
        if (penPal === null) {
          mark.visible = false;
          continue;
        }
        const transit = this.transitProgressOf(mark.penPalId);
        const at = pointOnGreatCircle(me, penPal.coordinate, transit);
        const projected = this.toStackVp(projection.toScreenLocation(
          { longitude: at.lon, latitude: at.lat }));
        mark.xVp = projected[0];
        mark.yVp = projected[1];
        mark.visible = this.inBounds(projected[0], projected[1], 24, 24);
        continue;
      }
      // 笔友墨点
      const penPal = penPalById(mark.penPalId, this.roster);
      if (penPal === null) {
        mark.visible = false;
        continue;
      }
      const projected = this.toStackVp(projection.toScreenLocation(
        { longitude: penPal.coordinate.lon, latitude: penPal.coordinate.lat }));
      mark.xVp = projected[0];
      mark.yVp = projected[1];
      mark.visible = this.inBounds(projected[0], projected[1], 40, 50);
      mark.isRecipient = this.recipientSet().has(mark.penPalId);
      mark.isFocused = this.focusedId === mark.penPalId;
      mark.name = penPal.surname.resolved(languageKey);
    }
    this.drawRoutes();
  }

  /** 出界判定：中心点出界多一点才算看不见（名签在墨点下面，多留一点） */
  private inBounds(xVp: number, yVp: number, marginX: number, marginY: number): boolean {
    return xVp >= -marginX && xVp <= this.mapWidthVp + marginX &&
      yVp >= -marginY && yVp <= this.mapHeightVp + marginY;
  }

  /** 在途信走到哪儿了（0…1） */
  private transitProgressOf(penPalId: string): number {
    for (const transit of this.transitLetters()) {
      if (transit.penPalId === penPalId) {
        return transit.progress;
      }
    }
    return 0;
  }

  /** 虚线测地线（Map Kit 的 polyline 没有 dash，画在盖在地图上的 Canvas 里） */
  private drawRoutes(): void {
    const ctx = this.routeCtx;
    const controller = this.mapController;
    if (ctx.width <= 0 || controller === undefined || !this.mapReady) {
      return;
    }
    const projection = controller.getProjection();
    const me = this.userLoc ?? null;
    // 清屏（px 坐标系）再画
    ctx.clearRect(0, 0, ctx.width, ctx.height);
    if (me === null) {
      return;
    }
    const ink = this.ink();
    const ui = this.getUIContext();
    // Canvas 坐标是 px：虚线间距 / 线宽按密度放大，视觉尺寸和 iOS 一致
    const density = ctx.width / Math.max(this.mapWidthVp, 1);
    const targets = routeTargets(this.recipientSet(), this.focusedId, this.roster);
    for (const target of targets) {
      ctx.strokeStyle = argbCss(target.isRecipient ? withAlpha(ink.post, 0.85) : ink.route);
      ctx.lineWidth = (target.isRecipient ? 1.6 : 1.1) * density;
      ctx.setLineDash([1.5 * density, 5 * density]);
      ctx.lineCap = 'round';
      ctx.beginPath();
      let started = false;
      let lastX = 0;
      for (let i = 0; i <= ROUTE_SEGMENTS; i++) {
        const at = pointOnGreatCircle(me, target.penPal.coordinate, i / ROUTE_SEGMENTS);
        const p = projection.toScreenLocation({ longitude: at.lon, latitude: at.lat });
        const x = ui.px2vp(p.positionX) + MAP_INSET_H_VP;
        const y = ui.px2vp(p.positionY);
        // 画布按 vp 布置、按 px 出图：坐标乘回密度
        const px = x * density;
        const py = y * density;
        // 跨日界线一跳一整屏：断笔重起，不横穿画布
        if (started && Math.abs(px - lastX) > ctx.width / 2) {
          ctx.stroke();
          ctx.beginPath();
          started = false;
        }
        if (!started) {
          ctx.moveTo(px, py);
          started = true;
        } else {
          ctx.lineTo(px, py);
        }
        lastX = px;
      }
      ctx.stroke();
    }
  }

  // ---- 相机 ----

  private applyDayNight(): void {
    const controller = this.mapController;
    if (controller === undefined) {
      return;
    }
    controller.setDayNightMode(this.isNight
      ? mapCommon.DayNightMode.NIGHT : mapCommon.DayNightMode.DAY);
  }

  /** Map Kit 回调：拿到控制器、挂事件（相机逐帧跟手、加载完做初次落位） */
  private onMapController(err: BusinessError, controller: map.MapComponentController): void {
    if (err) {
      hilog.error(DOMAIN, TAG, 'map init failed: %{public}d %{public}s', err.code, err.message);
      return;
    }
    this.mapController = controller;
    // 用户反馈：角上的 +/− 缩放键去掉（手势缩放本来就顺手），比例尺常显
    controller.setZoomControlsEnabled(false);
    controller.setScaleControlsEnabled(true);
    controller.setAlwaysShowScaleEnabled(true);
    this.applyDayNight();
    this.fetchSendable();
    const manager = controller.getEventManager();
    manager.on('mapLoad', (): void => {
      this.mapReady = true;
      this.applyDayNight();
      this.refreshOverlays();
      // 路由参数点名的（信箱「他在哪」）飞过去；默认自己那位 = 开场世界一览
      this.focusCamera(this.focusedId);
    });
    // 拖动 / 双击逐帧跟手（墨点贴着经纬度走）
    manager.on('cameraMove', (): void => {
      this.refreshOverlays();
    });
    // 收尾再对一次（惯性滚动停下来的最后一格）
    manager.on('cameraIdle', (): void => {
      this.refreshOverlays();
    });
  }

  /**
   * 滑到谁地图就飞到谁身边（用户定的交互：划名片 = 移动地图），远近固定
   * `FOCUS_ZOOM` 一档能看清城市；自己那位没有住址，翻到他回开场的世界一览。
   */
  private focusCamera(id: string): void {
    const controller = this.mapController;
    if (controller === undefined || !this.mapReady || id.length === 0) {
      return;
    }
    if (id === OWN_PEN_PAL_ID) {
      const center = startCenter(this.userLoc ?? null);
      controller.animateCamera(map.newLatLng(
        { longitude: center.lon, latitude: center.lat }, START_ZOOM), REVEAL_DURATION_MS);
      return;
    }
    const penPal = penPalById(id, this.roster);
    if (penPal === null) {
      return;
    }
    controller.animateCamera(map.newLatLng(
      { longitude: penPal.coordinate.lon, latitude: penPal.coordinate.lat },
      FOCUS_ZOOM), REVEAL_DURATION_MS);
  }

  // ---- 名片 / 收件人 ----

  /** 名册和路由参数都到齐了才定第一张名片（iOS onAppear + initialFocus 同款） */
  private tryResolveFocus(): void {
    if (!this.rosterLoaded || !this.onReadyHappened || this.focusedId.length > 0) {
      return;
    }
    const focus = this.initialFocus.length > 0 && penPalById(this.initialFocus, this.roster) !== null
      ? this.initialFocus : OWN_PEN_PAL_ID;
    this.focusedId = focus;
    this.swiperIndex = Math.max(0, this.cardIdList().indexOf(focus));
  }

  /** 翻到一位（点墨点 / 滑名片 / 路由参数）：墨点变大写出姓，地图飞到他身边 */
  private focus(id: string): void {
    if (id === this.focusedId) {
      return;
    }
    this.getUIContext().animateTo({ duration: 350, curve: Curve.EaseInOut }, (): void => {
      this.focusedId = id;
    });
  }

  /** focusedId 变了：名片 Swiper 跟过去、墨点抬到最上、地图飞到他身边 */
  private onFocusedIdChanged(): void {
    const ids = this.cardIdList();
    const index = ids.indexOf(this.focusedId);
    if (index >= 0 && index !== this.swiperIndex) {
      // 翻名片走 .index() 属性联动（changeIndex 要控制器已绑，名册没挂上时会踩空）
      this.swiperIndex = index;
    }
    this.rebuildMarks();
    this.refreshOverlays();
    this.focusCamera(this.focusedId);
  }

  /** 收件人 / 主题 / 昼夜变了：航线、墨点颜色跟着换 */
  private onDataChanged(): void {
    this.refreshOverlays();
  }

  /** 「寄给他」/「在收件人里」（一位一张，最后一位划不掉） */
  private toggleRecipient(id: string): void {
    const current = this.recipientSet();
    if (current.has(id)) {
      if (current.size <= 1) {
        return;
      }
      current.delete(id);
    } else {
      current.add(id);
    }
    const ids: string[] = [];
    current.forEach((recipient: string): void => {
      ids.push(recipient);
    });
    ids.sort();
    this.recipientsStorage = ids.join(',');
  }

  /** 「打开定位」：没问过就问（弹窗），问过没给直接试一把 */
  private requestLocation(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.location.requestPermission(context).then((): void => {
      this.userLoc = this.location.coordinate ?? undefined;
      this.rebuildMarks();
      this.refreshOverlays();
    });
  }

  /** 「去设置」：跳系统设置的本应用信息页（录音面板 / 相机同款） */
  private openAppSettings(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) {
      return;
    }
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      .then((info: bundleManager.BundleInfo): void => {
        const want: Want = {
          bundleName: 'com.huawei.hmos.settings',
          abilityName: 'com.huawei.hmos.settings.MainAbility',
          uri: `application_info_entry/${info.name}`
        };
        context.startAbility(want).catch((): void => {
          // 跳转失败（极端场景）：留在引导态
        });
      }).catch((): void => {
        // 取不到包信息：留在引导态
      });
  }

  build() {
    NavDestination() {
      Column() {
        this.header()
        if (this.userLoc === undefined) {
          this.locationNote()
        }
        this.mapArea()
        this.cardsArea()
        // 富余空间垫在名片和最下一行之间（地图固定高后不挤了）
        Blank()
        this.recipientsBar()
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.safeAreaBottomVp + BOTTOM_CLEARANCE_VP })
      .backgroundColor(this.theme.background)
    }
    // 官方标题栏：系统返回键单独一行；高度吃下状态栏（内容从栏底往下排）
    .title({
      builder: this.topBar,
      height: this.safeAreaTopVp + TITLE_BAR_ROW_VP + TITLE_BAR_SLACK_VP
    })
    .backgroundColor(this.theme.background)
    .onReady((ctx: NavDestinationContext): void => {
      this.navPathStack = ctx.pathStack;
      const param = ctx.pathInfo.param as string | undefined;
      if (param !== undefined && param.length > 0) {
        this.initialFocus = param;
      }
      this.onReadyHappened = true;
      this.tryResolveFocus();
    })
  }

  // ---- 标题栏（NavDestination 官方标题栏）：系统返回键独占一行 ----

  /**
   * 标题栏内容留空（用户定：返回键单独一行，不跟标题挤）；返回键由系统画、
   * 栏内居中。「今雨与雅故」页眉在内容区顶上另起一行，宽度和邮票夹都不受挤。
   */
  @Builder
  private topBar() {
    Column() {
      Blank()
    }
    .width('100%')
    .height('100%')
  }

  // ---- 页眉（内容区顶上）：今雨与雅故一行 + 右上角邮票夹 ----

  @Builder
  private header() {
    Row() {
      Column({ space: 4 }) {
        // 界面上不叫「世界笔友」，叫「今雨与雅故」（用户定：杜甫「旧雨今雨」）
        Text($r('app.string.s_2870d2ab3b'))
          .fontSize(this.theme.headingFont.size)
          .fontWeight(this.theme.headingFont.weight)
          .fontFamily(this.theme.headingFont.family)
          .fontColor(this.theme.textPrimary)
        Text($r('app.string.s_cbefa1b42e', this.roster.length))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.stampBalance !== undefined) {
        Row({ space: 7 }) {
          MarkStamp({
            widthVp: 18,
            ink: postmarkInkHex(this.theme.id),
            paper: this.palette().paper
          })
          Text(`${this.stampBalance}`)
            .fontSize(16)
            .fontWeight(600)
            .fontFamily('serif')
            .fontColor(this.theme.textPrimary)
        }
        .alignItems(VerticalAlign.Center)
        .padding({ left: 4, right: 4 })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: 24, right: 24, top: 4, bottom: 6 })
  }

  /** 不知道你在哪：说一句为什么要定位，用户点了才问（不一进来就弹权限框） */
  @Builder
  private locationNote() {
    Row({ space: 8 }) {
      SymbolGlyph(this.locationDenied()
        ? $r('sys.symbol.map_slash') : $r('sys.symbol.local'))
        .fontSize(this.theme.captionFont.size)
        .fontColor([this.theme.textSecondary])
      Text(this.locationDenied()
        ? $r('app.string.s_f02d71af1a') : $r('app.string.s_37a8ee52ac'))
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textSecondary)
        .layoutWeight(1)
        .maxLines(2)
      Text(this.locationDenied()
        ? $r('app.string.s_1f2998c9c8') : $r('app.string.s_65fc81e161'))
        .fontSize(this.theme.captionFont.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.textPrimary)
        .onClick((): void => {
          if (this.locationDenied()) {
            this.openAppSettings();
          } else {
            this.requestLocation();
          }
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 24, right: 24, bottom: 6 })
  }

  private locationDenied(): boolean {
    const context = this.getUIContext().getHostContext();
    return context !== undefined && this.location.isDenied(context);
  }

  // ---- 地图 + 覆盖层 ----

  @Builder
  private mapArea() {
    Stack() {
      MapComponent({
        mapOptions: this.mapOptions,
        mapCallback: (err: BusinessError, controller: map.MapComponentController): void => {
          this.onMapController(err, controller);
        }
      })
        .padding({ left: MAP_INSET_H_VP, right: MAP_INSET_H_VP, bottom: MAP_INSET_BOTTOM_VP })
        .width('100%')
        .height('100%')

      // 虚线测地线（收件人邮戳色；正在看还没选的淡淡一条）
      Canvas(this.routeCtx)
        .width('100%')
        .height('100%')
        .onReady((): void => {
          this.drawRoutes();
        })
        .hitTestBehavior(HitTestMode.Transparent)

      // 墨点 /「你」/ 在途信封（坐标就地改，@ObjectLink 跟着动）
      ForEach(this.marks, (mark: WorldMark) => {
        if (mark.kind === 0) {
          YouMarkHolder({
            mark: mark,
            ink: this.ink(),
            onTap: (): void => {
              this.focus(OWN_PEN_PAL_ID);
            }
          })
        } else if (mark.kind === 2) {
          TransitMarkHolder({
            mark: mark,
            ink: this.ink()
          })
        } else {
          DotMarkHolder({
            mark: mark,
            ink: this.ink(),
            onTap: (id: string): void => {
              this.focus(id);
            }
          })
        }
      }, (mark: WorldMark): string => mark.key)

      // 四周晕进纸色（参考图那样），不挡手势
      this.edgeFades()
    }
    .width('100%')
    .height(this.mapAreaHeightVp())
    // 出界的墨点只露到地图边为止，不漂出去盖住页眉 / 名片
    .clip(true)
    .onAreaChange((_old: Area, newArea: Area): void => {
      this.mapWidthVp = Number(newArea.width);
      this.mapHeightVp = Number(newArea.height);
      this.refreshOverlays();
    })
  }

  /** 地图固定高（vp）：窗高 34% 夹在 140~320（纯函数 mapHeightForWindow 可单测） */
  private mapAreaHeightVp(): number {
    return mapHeightForWindow(this.windowHeightVp);
  }

  /**
   * 地图四周晕进页面的纸色（iOS EdgeFade 同宽：上 34、下 22、左右 18）。
   * 晕边是纯装饰：容器和渐变条全都要 `HitTestMode.None`，只有根节点 None
   * 不够——里面全尺寸的 Column/Row 是默认命中行为，会把整张地图的触摸吃掉
   * （真机对照实验：花瓣地图 App 注入滑动能平移，这里不行，根因就是它）。
   */
  @Builder
  private edgeFades() {
    Stack() {
      Column() {
        Column()
          .width('100%')
          .height(EDGE_FADE_TOP_VP)
          .linearGradient({
            angle: 180,
            colors: [[this.theme.background, 0], [Color.Transparent, 1]]
          })
          .hitTestBehavior(HitTestMode.None)
        Blank()
          .hitTestBehavior(HitTestMode.None)
        Column()
          .width('100%')
          .height(EDGE_FADE_BOTTOM_VP)
          .linearGradient({
            angle: 180,
            colors: [[Color.Transparent, 0], [this.theme.background, 1]]
          })
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)

      Row() {
        Column()
          .width(EDGE_FADE_SIDE_VP)
          .height('100%')
          .linearGradient({
            angle: 90,
            colors: [[this.theme.background, 0], [Color.Transparent, 1]]
          })
          .hitTestBehavior(HitTestMode.None)
        Blank()
          .hitTestBehavior(HitTestMode.None)
        Column()
          .width(EDGE_FADE_SIDE_VP)
          .height('100%')
          .linearGradient({
            angle: 270,
            colors: [[Color.Transparent, 0], [this.theme.background, 1]]
          })
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  // ---- 名片 ----

  @Builder
  private cardsArea() {
    Swiper() {
      ForEach(this.cardIdList(), (id: string) => {
        this.card(id)
      }, (id: string): string => id)
    }
    .index(this.swiperIndex)
    .loop(false)
    .indicator(false)
    .cachedCount(1)
    .duration(350)
    .nextMargin(CARD_MARGIN_VP)
    .prevMargin(CARD_MARGIN_VP)
    .height(PEN_PAL_CARD_HEIGHT + 16)
    .margin({ top: 14 })
    .width('100%')
    .onChange((index: number): void => {
      this.swiperIndex = index;
      const ids = this.cardIdList();
      if (index >= 0 && index < ids.length && ids[index] !== this.focusedId) {
        this.getUIContext().animateTo({ duration: 350, curve: Curve.EaseInOut }, (): void => {
          this.focusedId = ids[index];
        });
      }
    })
  }

  /** 一张名片（自己那位或世界笔友） */
  @Builder
  private card(id: string) {
    PenPalCard({
      penPal: penPalById(id, this.roster),
      ownName: this.ownPenPalName(),
      userLocation: this.userLoc ?? null,
      isRecipient: this.recipientSet().has(id),
      isMember: this.isMemberNow(),
      canSend: id === OWN_PEN_PAL_ID || this.sendableIds().has(id),
      palette: this.palette(),
      postInk: postmarkInkHex(this.theme.id),
      nowMs: this.nowMs,
      onToggle: (): void => {
        this.toggleRecipient(id);
      },
      onBecomeMember: (): void => {
        this.navPathStack.pushPathByName('Paywall', '');
      }
    })
      // 相邻两张名片中间的缝（用户反馈：要分开）——Swiper 没有子组件间距属性，用 margin
      .margin({ left: CARD_GAP_VP, right: CARD_GAP_VP })
  }

  // ---- 最下一行：这次寄给谁 / 贴几张 / 好了 ----

  @Builder
  private recipientsBar() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text($r('app.string.s_c9ac2abd66'))
          .fontSize(this.theme.labelFont.size)
          .fontWeight(this.theme.labelFont.weight)
          .fontFamily(this.theme.labelFont.family)
          .fontColor(this.theme.textTertiary)
        Text(this.recipientNamesText().length === 0 ? '—' : this.recipientNamesText())
          .fontSize(this.theme.bodyFont.size)
          .fontWeight(this.theme.bodyFont.weight)
          .fontFamily(this.theme.bodyFont.family)
          .fontColor(this.theme.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.postageNeeded() > 0) {
        Text($r('app.string.s_bf72168234', this.postageNeeded()))
          .fontSize(this.theme.captionFont.size)
          .fontWeight(this.theme.captionFont.weight)
          .fontFamily(this.theme.captionFont.family)
          .fontColor(this.theme.textSecondary)
      }

      Button({ type: ButtonType.Capsule, stateEffect: true }) {
        Text($r('app.string.s_fac14ac621'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.background)
      }
      .padding({ left: 18, right: 18, top: 8, bottom: 8 })
      .backgroundColor(this.theme.textPrimary)
      .onClick((): void => {
        this.navPathStack.pop();
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 24, right: 24, top: 12, bottom: 12 })
    .overlay(this.recipientsBarRule(), { align: Alignment.Top })
  }

  @Builder
  private recipientsBarRule() {
    Column()
      .height(0.5)
      .backgroundColor(this.theme.border)
      .width('100%')
  }
}

/** 「你」标记的壳：@ObjectLink 盯着 WorldMark，坐标就地改就跟着动 */
@Component
struct YouMarkHolder {
  @ObjectLink mark: WorldMark;
  ink: MapInk = mapInkOf(false, '#B5473A');
  onTap: () => void = (): void => {};

  build() {
    if (this.mark.visible) {
      YouMark({
        ink: this.ink,
        onTap: this.onTap
      })
        .position({ x: this.mark.xVp - 22, y: this.mark.yVp - 22 })
    }
  }
}

/** 笔友墨点的壳（点墨点 = 名片翻到他） */
@Component
struct DotMarkHolder {
  @ObjectLink mark: WorldMark;
  ink: MapInk = mapInkOf(false, '#B5473A');
  onTap: (id: string) => void = (_id: string): void => {};

  build() {
    if (this.mark.visible) {
      PenPalDot({
        ink: this.ink,
        isRecipient: this.mark.isRecipient,
        isFocused: this.mark.isFocused,
        name: this.mark.name,
        onTap: (): void => {
          this.onTap(this.mark.penPalId);
        }
      })
        .position({ x: this.mark.xVp - 22, y: this.mark.yVp - 22 })
    }
  }
}

/** 在途信封的壳（航线上的小信封，斜着贴） */
@Component
struct TransitMarkHolder {
  @ObjectLink mark: WorldMark;
  ink: MapInk = mapInkOf(false, '#B5473A');

  build() {
    if (this.mark.visible) {
      Stack() {
        TransitEnvelopeMark({ ink: this.ink })
      }
      .width(24)
      .height(24)
      .position({ x: this.mark.xVp - 12, y: this.mark.yVp - 12 })
    }
  }
}
