/**
 * 心情的九档（U03；对应 iOS `Views/Mood/MoodLevel.swift`，6.3 写作统计引入）。
 * 愉悦度 -1…1 均分九段，档名是四字称谓。
 *
 * 纯逻辑无 UI 依赖：颜色给 hex 串（环形图 / 刻度条 / 情绪词圆点共用），
 * 档名文案由 UI 层按语言映射（见 StatsView 的 moodLevelTitle）。
 */
export enum MoodLevel {
  rockBottom = 0,
  heartsick = 1,
  melancholy = 2,
  glum = 3,
  even = 4,
  content = 5,
  joyful = 6,
  radiant = 7,
  overjoyed = 8
}

export class MoodLevels {
  static readonly count: number = 9;
  /** 一档有多宽（愉悦度） */
  static readonly width: number = 2.0 / MoodLevels.count;
  /** 全部九档，从跌入谷底到心花怒放 */
  static readonly all: MoodLevel[] = [
    MoodLevel.rockBottom, MoodLevel.heartsick, MoodLevel.melancholy, MoodLevel.glum,
    MoodLevel.even, MoodLevel.content, MoodLevel.joyful, MoodLevel.radiant, MoodLevel.overjoyed
  ];

  /** 愉悦度 → 档。越界夹到 -1…1，均分九段取整段 */
  static fromValence(valence: number): MoodLevel {
    const clamped = Math.min(Math.max(valence, -1), 1);
    const index = Math.floor((clamped + 1) / 2 * MoodLevels.count);
    const safe = Math.min(Math.max(index, 0), MoodLevels.count - 1);
    return safe as MoodLevel;
  }

  /** 这一档的中间值（点「平常」之类回到正中时用） */
  static centerValence(level: MoodLevel): number {
    return (level + 0.5) * MoodLevels.width - 1;
  }

  static isUnpleasant(level: MoodLevel): boolean {
    return level < MoodLevel.even;
  }

  static isPleasant(level: MoodLevel): boolean {
    return level > MoodLevel.even;
  }

  /**
   * 这一档的代表色（hex 串）：取自 iOS `MoodLevel.tint`
   * （线团爱心那一档的调色板，从灰蓝一路到玫瑰红）。
   * 写作统计的心情分布、情绪词圆点、刻度条渐变都用它
   */
  static tintHex(level: MoodLevel): string {
    switch (level) {
      case MoodLevel.rockBottom: return '#6B7394';
      case MoodLevel.heartsick: return '#7078A8';
      case MoodLevel.melancholy: return '#7380BF';
      case MoodLevel.glum: return '#9E99DB';
      case MoodLevel.even: return '#61BFD1';
      case MoodLevel.content: return '#85D670';
      case MoodLevel.joyful: return '#F5CC4C';
      case MoodLevel.radiant: return '#FF876B';
      case MoodLevel.overjoyed: return '#FA5C94';
      default: return '#61BFD1';
    }
  }

  /** 发给后端写来信提示词用的英文名（不跟 App 语言走） */
  static englishName(level: MoodLevel): string {
    switch (level) {
      case MoodLevel.rockBottom: return 'rock bottom';
      case MoodLevel.heartsick: return 'heartsick';
      case MoodLevel.melancholy: return 'melancholy';
      case MoodLevel.glum: return 'a little glum';
      case MoodLevel.even: return 'neither sad nor glad';
      case MoodLevel.content: return 'content';
      case MoodLevel.joyful: return 'joyful';
      case MoodLevel.radiant: return 'radiant';
      case MoodLevel.overjoyed: return 'over the moon';
      default: return 'neither sad nor glad';
    }
  }
}
