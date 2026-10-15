/**
 * 时段问候 + 每日语录（10_BUILD_MANUAL.md 2.2）。对应 iOS `Services/GreetingManager.swift`。
 *
 * - 五个时段各一组（5–8 / 9–11 / 12–16 / 17–20 / 其余），**同一小时固定**
 *   （`hour % 池长` 取模，R-HOME-01）
 * - 每日语录**同一天固定**（一年中的第几天 `(dayOfYear - 1) % 池长`）
 * - 池子是字符串资源数组（译文取自 iOS `Localizable.xcstrings`，七种语言齐，
 *   R-LANG 约定不机翻）；**顺序与 iOS 源文件逐条一致**，保证同小时 / 同天
 *   与 iOS 显示同一条
 * - 取模逻辑抽成纯静态方法（时间参数可注入），单测跑穿全天 / 全年
 */
export class GreetingManager {
  // ---- 时段问候（池长 6/6/6/6/7，与 iOS 一致） ----

  private static readonly morningGreetings: Resource[] = [
    $r('app.string.s_c11b65b92c'),  // 晨光微露，新的一页等你落笔
    $r('app.string.s_2a90aa456f'),
    $r('app.string.s_c266fc5a91'),
    $r('app.string.s_3505075551'),
    $r('app.string.s_168b37f367'),
    $r('app.string.s_9a21654c81')
  ];

  private static readonly morningLateGreetings: Resource[] = [
    $r('app.string.s_5a616bb0d3'),
    $r('app.string.s_59a4ba58b0'),
    $r('app.string.s_808887de3e'),
    $r('app.string.s_9b87ed617f'),
    $r('app.string.s_2d54b2d8e5'),
    $r('app.string.s_f90d3aab55')
  ];

  private static readonly afternoonGreetings: Resource[] = [
    $r('app.string.s_b981bb73cb'),
    $r('app.string.s_0b3e909f02'),
    $r('app.string.s_62d5f22319'),
    $r('app.string.s_dcf37c99eb'),
    $r('app.string.s_b5040678f0'),
    $r('app.string.s_384964cd05')
  ];

  private static readonly eveningGreetings: Resource[] = [
    $r('app.string.s_e1d765507d'),
    $r('app.string.s_c72e1ce65f'),
    $r('app.string.s_22739c882c'),
    $r('app.string.s_daf00cb705'),
    $r('app.string.s_ed7a57b32a'),
    $r('app.string.s_bd1775eabd')
  ];

  private static readonly nightGreetings: Resource[] = [
    $r('app.string.s_70eeb8233a'),
    $r('app.string.s_42ffce9145'),
    $r('app.string.s_5a393262ea'),
    $r('app.string.s_ddb8fb6094'),
    $r('app.string.s_f075b5a3ad'),
    $r('app.string.s_e73f6f1b4f'),
    $r('app.string.s_1a4cb39357')
  ];

  // ---- 每日语录（64 条，顺序与 iOS dailyQuotes 一致；译文自带引号，不再包「」） ----

  private static readonly dailyQuotes: Resource[] = [
    $r('app.string.s_72ca690ff2'),
    $r('app.string.s_b04c38d8e1'),
    $r('app.string.s_91c4b31f0e'),
    $r('app.string.s_0ba6de577f'),
    $r('app.string.s_dc7945487b'),
    $r('app.string.s_76e2f7abf9'),
    $r('app.string.s_41f8b5303e'),
    $r('app.string.s_76a21b5df1'),
    $r('app.string.s_805a0473b6'),
    $r('app.string.s_aca36c266f'),
    $r('app.string.s_6efeb2c455'),
    $r('app.string.s_d5af163131'),
    $r('app.string.s_e524dcf71e'),
    $r('app.string.s_4c99a7a774'),
    $r('app.string.s_2312adef49'),
    $r('app.string.s_2c6afc5f55'),
    $r('app.string.s_09f2cefb0c'),
    $r('app.string.s_c15e3efa81'),
    $r('app.string.s_2afb730db8'),
    $r('app.string.s_fac430ea0c'),
    $r('app.string.s_8cd62ee39c'),
    $r('app.string.s_91e5f2c416'),
    $r('app.string.s_e2aedf50f2'),
    $r('app.string.s_1a6ddc0c96'),
    $r('app.string.s_e6dbbfdb59'),
    $r('app.string.s_8e39a34dcc'),
    $r('app.string.s_c65a22ccf7'),
    $r('app.string.s_354343bcbf'),
    $r('app.string.s_bf6ad0ba08'),
    $r('app.string.s_446462a28f'),
    $r('app.string.s_ed839905d8'),
    $r('app.string.s_75ce20b461'),
    $r('app.string.s_34028338a4'),
    $r('app.string.s_8fad83c181'),
    $r('app.string.s_5a0a430923'),
    $r('app.string.s_28cfd5c34e'),
    $r('app.string.s_03d786b9dc'),
    $r('app.string.s_eae4b17fa9'),
    $r('app.string.s_cd91dfd56d'),
    $r('app.string.s_0ae0dc846a'),
    $r('app.string.s_b74d58bd95'),
    $r('app.string.s_477a226253'),
    $r('app.string.s_3c079f2974'),
    $r('app.string.s_0064d7c8e8'),
    $r('app.string.s_c74dd33b63'),
    $r('app.string.s_9860e2406f'),
    $r('app.string.s_a0b3cc9c47'),
    $r('app.string.s_6a8e6df501'),
    $r('app.string.s_930c3a22eb'),
    $r('app.string.s_60dbc09b63'),
    $r('app.string.s_8ad31155b2'),
    $r('app.string.s_ec094809a3'),
    $r('app.string.s_c567ba63ab'),
    $r('app.string.s_5e03599e74'),
    $r('app.string.s_08cf5d323f'),
    $r('app.string.s_8c8658f454'),
    $r('app.string.s_fa58d00e4f'),
    $r('app.string.s_bddddc8c10'),
    $r('app.string.s_ab58e2f999'),
    $r('app.string.s_efa9b5121e'),
    $r('app.string.s_6d1f3e58bb'),
    $r('app.string.s_dee14a14e2'),
    $r('app.string.s_b1a9ba7930'),
    $r('app.string.s_f99c577247')
  ];

  // ---- 纯逻辑（时间参数可注入，单测用） ----

  /** 小时 → 时段池。5–8 / 9–11 / 12–16 / 17–20 / 其余（R-HOME-01，与 iOS switch 一致） */
  static poolForHour(hour: number): Resource[] {
    if (hour >= 5 && hour <= 8) {
      return GreetingManager.morningGreetings;
    }
    if (hour >= 9 && hour <= 11) {
      return GreetingManager.morningLateGreetings;
    }
    if (hour >= 12 && hour <= 16) {
      return GreetingManager.afternoonGreetings;
    }
    if (hour >= 17 && hour <= 20) {
      return GreetingManager.eveningGreetings;
    }
    return GreetingManager.nightGreetings;
  }

  /** 时段问候（同一小时固定：`hour % 池长`） */
  static timeBasedGreeting(hour: number): Resource {
    const pool = GreetingManager.poolForHour(hour);
    return pool[hour % pool.length];
  }

  /** 每日语录（同一天固定：`(dayOfYear - 1) % 64`，dayOfYear 1–366） */
  static dailyQuote(dayOfYear: number): Resource {
    const quotes = GreetingManager.dailyQuotes;
    const safeDay = dayOfYear > 0 ? dayOfYear : 1;
    return quotes[(safeDay - 1) % quotes.length];
  }

  /** 一年中的第几天（1 起，本地时区；对应 iOS `Calendar.ordinality(of: .day, in: .year)`） */
  static dayOfYear(date: Date): number {
    const start = new Date(date.getFullYear(), 0, 1);
    return Math.floor((date.getTime() - start.getTime()) / 86400000) + 1;
  }
}
