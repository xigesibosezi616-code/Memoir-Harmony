/**
 * 危险的那封信下面固定附的一张求助卡片（U01 读信规则 6，2026-10-16）。
 * 对应 iOS `Views/PostBox/CrisisHelpCard.swift`。
 *
 * 服务端判出日记里有危险信号时（`Letter.danger`），信里已经写了求助热线；
 * 这张卡片把同一条热线放到信纸外面，**点一下就能拨**，不用从信里抄号码。
 * 只写事实、不许诺（不写「一定有人接」「会好起来的」），不加别的号码；
 * 补各地热线前先问产品。
 *
 * 热线按**这封信是用哪种语言写给你的**选（调用方用 LetterLanguage 识别，
 * 有译文看译文、没有看原文），和服务端写进信里的那条一致：
 * - 简体中文：北京心理危机研究与干预中心 010-82951332
 * - 英语：美国 988
 * - 每种语言都附 findahelpline.com（按所在国家列出免费的求助热线）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { call } from '@kit.TelephonyKit';
import { LetterPalette } from './LetterPalette';

const DOMAIN = 0x0000;
const TAG = 'CrisisHelpCard';

/** '#RRGGBB' + 透明度 → '#AARRGGBB'（LetterStationery 同款） */
function withAlpha(hex: string, alpha01: number): string {
  const a = Math.round(Math.max(0, Math.min(1, alpha01)) * 255);
  const s = a.toString(16);
  return `#${s.length < 2 ? '0' : ''}${s}${hex.substring(1)}`;
}

/** 一条求助渠道。dial=true 时 target 是号码（点一下跳拨号盘），否则是网址 */
interface HelpLine {
  id: string;
  title: ResourceStr;
  detail: string;
  symbol: Resource;
  dial: boolean;
  target: string;
}

@Component
export struct CrisisHelpCard {
  /** 这封信是用哪种语言写给你的（LetterLanguage 的语言代码） */
  language: string = 'en';
  palette: LetterPalette = LetterPalette.bamboo;

  build() {
    Column({ space: 16 }) {
      Column({ space: 6 }) {
        Text($r('app.string.s_32256643cf'))
          .fontSize(17)
          .fontWeight(600)
          .fontColor(this.palette.ink)
        Text($r('app.string.s_948a67b305'))
          .fontSize(15)
          .fontColor(withAlpha(this.palette.ink, 0.75))
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 10 }) {
        ForEach(this.helpLines(), (line: HelpLine) => {
          this.row(line)
        }, (line: HelpLine): string => line.id)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    // 一张夹在信后面的小卡片：和信纸同一种纸，比信纸小一圈的阴影
    .backgroundColor(this.palette.paper)
    .shadow({ radius: 5, color: '#1A000000', offsetX: 0, offsetY: 2 })
  }

  /** 热线按读信语言选（zh-Hans → 北京，en → 988，其余只有查找渠道） */
  private helpLines(): HelpLine[] {
    // 每种语言都有：按所在国家查当地的免费热线
    const finder: HelpLine = {
      id: 'findahelpline',
      title: $r('app.string.s_7c124dbbca'),
      detail: 'findahelpline.com',
      symbol: $r('sys.symbol.magnifyingglass'),
      dial: false,
      target: 'https://findahelpline.com'
    };
    const lines: HelpLine[] = [];
    if (this.language === 'zh-Hans') {
      const beijing: HelpLine = {
        id: 'beijing',
        title: $r('app.string.s_5c7cc8abd6', '010-82951332'),
        detail: this.getString($r('app.string.s_e141654f13')),
        symbol: $r('sys.symbol.phone'),
        dial: true,
        target: '01082951332'
      };
      lines.push(beijing);
      lines.push(finder);
    } else if (this.language === 'en') {
      const usa: HelpLine = {
        id: '988',
        title: $r('app.string.s_5c7cc8abd6', '988'),
        detail: this.getString($r('app.string.s_f73492117c')),
        symbol: $r('sys.symbol.phone'),
        dial: true,
        target: '988'
      };
      lines.push(usa);
      lines.push(finder);
    } else {
      lines.push(finder);
    }
    return lines;
  }

  /** 取本地化串（detail 不带参数，直接解出来当纯文本放行） */
  private getString(res: Resource): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringSync(res.id);
  }

  @Builder
  private row(line: HelpLine) {
    Row({ space: 12 }) {
      SymbolGlyph(line.symbol)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.palette.ink])
        .width(24)
      Column({ space: 3 }) {
        Text(line.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette.ink)
        Text(line.detail)
          .fontSize(13)
          .fontColor(withAlpha(this.palette.ink, 0.6))
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontWeight(600)
        .fontColor([withAlpha(this.palette.ink, 0.35)])
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .borderRadius(8)
    .border({ width: 0.8, color: withAlpha(this.palette.ink, 0.3) })
    .onClick((): void => {
      if (line.dial) {
        this.dial(line.target);
      } else {
        this.openTarget(line.target);
      }
    })
  }

  /** 跳拨号盘（call.makeCall 不需要权限；没有通话能力的设备上静默失败，只记日志） */
  private dial(phoneNumber: string): void {
    call.makeCall(phoneNumber)
      .catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'makeCall failed %{public}d: %{public}s', err.code, err.message);
      });
  }

  /** 打开网页（findahelpline.com） */
  private openTarget(url: string): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) {
      return;
    }
    context.openLink(url)
      .catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'openLink failed %{public}d: %{public}s', err.code, err.message);
      });
  }
}
