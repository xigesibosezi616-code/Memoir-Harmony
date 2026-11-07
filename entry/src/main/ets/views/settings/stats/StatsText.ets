/**
 * 写作统计的文案映射（6.3）：enum → $r 字面量。
 * 档名 / 情绪词 / 天气六类 / 时段四段 / 范围名，键 = s_ + sha1(简中原文)[:10]，
 * 七种语言取自 iOS xcstrings。纯 UI 层，逻辑层（单测覆盖）不 import 本文件。
 */
import { MoodLevel } from '../../../models/MoodLevel';
import { MoodLabel } from '../../../models/MoodLabel';
import { WeatherKind, DayPart } from '../../../models/MoodInsights';
import { StatsRange } from '../../../models/StatsCalculator';

/** 九档档名（写作统计的心情分布、天气地点星期时段的行值） */
export function moodLevelTitle(level: MoodLevel): Resource {
  switch (level) {
    case MoodLevel.rockBottom: return $r('app.string.s_9f24026626');
    case MoodLevel.heartsick: return $r('app.string.s_33be7bd82b');
    case MoodLevel.melancholy: return $r('app.string.s_b83ba48b71');
    case MoodLevel.glum: return $r('app.string.s_d39917428a');
    case MoodLevel.even: return $r('app.string.s_b86ded4a21');
    case MoodLevel.content: return $r('app.string.s_810e1db235');
    case MoodLevel.joyful: return $r('app.string.s_a305bdce5e');
    case MoodLevel.radiant: return $r('app.string.s_6d33b0d1f9');
    case MoodLevel.overjoyed: return $r('app.string.s_674bd11a2a');
    default: return $r('app.string.s_b86ded4a21');
  }
}

/** 38 个情绪词（「最常出现的情绪」） */
export function moodLabelTitle(label: MoodLabel): Resource {
  switch (label) {
    case MoodLabel.hopeless: return $r('app.string.s_88dd24c6f2');
    case MoodLabel.overwhelmed: return $r('app.string.s_f2d2c96c62');
    case MoodLabel.scared: return $r('app.string.s_8f9a55ccb3');
    case MoodLabel.angry: return $r('app.string.s_0cfa09d980');
    case MoodLabel.disgusted: return $r('app.string.s_05aa9400bd');
    case MoodLabel.sad: return $r('app.string.s_7d048ef485');
    case MoodLabel.lonely: return $r('app.string.s_28c46f23f7');
    case MoodLabel.disappointed: return $r('app.string.s_833e892fa2');
    case MoodLabel.guilty: return $r('app.string.s_231468e491');
    case MoodLabel.ashamed: return $r('app.string.s_733f4ad13a');
    case MoodLabel.drained: return $r('app.string.s_8174d1e505');
    case MoodLabel.discouraged: return $r('app.string.s_89e57b7930');
    case MoodLabel.frustrated: return $r('app.string.s_73cc66ab46');
    case MoodLabel.anxious: return $r('app.string.s_f893902ee4');
    case MoodLabel.jealous: return $r('app.string.s_d48fd5f69b');
    case MoodLabel.annoyed: return $r('app.string.s_9131b3c5b6');
    case MoodLabel.irritated: return $r('app.string.s_c57af70474');
    case MoodLabel.stressed: return $r('app.string.s_04e86ea902');
    case MoodLabel.worried: return $r('app.string.s_60f0393ca0');
    case MoodLabel.embarrassed: return $r('app.string.s_181e010524');
    case MoodLabel.calm: return $r('app.string.s_85dc6e7aed');
    case MoodLabel.peaceful: return $r('app.string.s_f4b0ec3120');
    case MoodLabel.indifferent: return $r('app.string.s_36f485a94d');
    case MoodLabel.content: return $r('app.string.s_3a31adc3b5');
    case MoodLabel.satisfied: return $r('app.string.s_fda7539bde');
    case MoodLabel.relieved: return $r('app.string.s_50a5de527c');
    case MoodLabel.grateful: return $r('app.string.s_7bb5b11a5d');
    case MoodLabel.happy: return $r('app.string.s_d946dacd50');
    case MoodLabel.joyful: return $r('app.string.s_72c38981e7');
    case MoodLabel.amused: return $r('app.string.s_8d34f398c2');
    case MoodLabel.hopeful: return $r('app.string.s_f2544d8e37');
    case MoodLabel.confident: return $r('app.string.s_3225d1a315');
    case MoodLabel.proud: return $r('app.string.s_3017ebc38b');
    case MoodLabel.brave: return $r('app.string.s_a5b49a429e');
    case MoodLabel.passionate: return $r('app.string.s_fe2161f91d');
    case MoodLabel.excited: return $r('app.string.s_09f81f62fd');
    case MoodLabel.amazed: return $r('app.string.s_12e33f7397');
    case MoodLabel.surprised: return $r('app.string.s_bd6bd4738c');
    default: return $r('app.string.s_85dc6e7aed');
  }
}

/** 天气六类（「天气与心情」行首） */
export function weatherKindTitle(kind: WeatherKind): Resource {
  switch (kind) {
    case WeatherKind.clear: return $r('app.string.s_0d05046a43');
    case WeatherKind.cloudy: return $r('app.string.s_39b6b4c787');
    case WeatherKind.rain: return $r('app.string.s_8995b89799');
    case WeatherKind.snow: return $r('app.string.s_7d742a7f9f');
    case WeatherKind.fog: return $r('app.string.s_b08cdeb8a7');
    case WeatherKind.wind: return $r('app.string.s_f0b2b86513');
    default: return $r('app.string.s_0d05046a43');
  }
}

/** 时段四段（「星期与时段」行首） */
export function dayPartTitle(part: DayPart): Resource {
  switch (part) {
    case DayPart.morning: return $r('app.string.s_172fb7196f');
    case DayPart.afternoon: return $r('app.string.s_1dfaab6548');
    case DayPart.evening: return $r('app.string.s_76a4159492');
    case DayPart.night: return $r('app.string.s_0e458fad76');
    default: return $r('app.string.s_172fb7196f');
  }
}

/** 时间范围名（RangePicker 四个胶囊） */
export function statsRangeTitle(range: StatsRange): Resource {
  switch (range) {
    case StatsRange.week: return $r('app.string.s_f297b996de');
    case StatsRange.month: return $r('app.string.s_00a0a58be6');
    case StatsRange.year: return $r('app.string.s_fe9ea3f070');
    case StatsRange.all: return $r('app.string.s_778fc8f994');
    default: return $r('app.string.s_00a0a58be6');
  }
}
