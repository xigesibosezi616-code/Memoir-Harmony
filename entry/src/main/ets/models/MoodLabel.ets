/**
 * 心情页第二步的情绪词（U03；对应 iOS `Views/Mood/MoodLabel.swift`）。
 * 苹果「健康」的那 38 个词，存英文 key（`rawValue`）；每个词只在一档里出现。
 *
 * 6.3 写作统计的「最常出现的情绪」读日记上的 `moodLabels`（key 数组），
 * 文案由 UI 层按语言映射（见 StatsView 的 moodLabelTitle）。
 */
import { MoodLevel, MoodLevels } from './MoodLevel';

export enum MoodLabel {
  hopeless = 0, overwhelmed, scared, angry, disgusted,
  sad, lonely, disappointed, guilty, ashamed,
  drained, discouraged, frustrated, anxious, jealous,
  annoyed, irritated, stressed, worried, embarrassed,
  calm, peaceful, indifferent,
  content, satisfied, relieved, grateful,
  happy, joyful, amused, hopeful,
  confident, proud, brave, passionate,
  excited, amazed, surprised
}

export class MoodLabels {
  static readonly all: MoodLabel[] = [
    MoodLabel.hopeless, MoodLabel.overwhelmed, MoodLabel.scared, MoodLabel.angry, MoodLabel.disgusted,
    MoodLabel.sad, MoodLabel.lonely, MoodLabel.disappointed, MoodLabel.guilty, MoodLabel.ashamed,
    MoodLabel.drained, MoodLabel.discouraged, MoodLabel.frustrated, MoodLabel.anxious, MoodLabel.jealous,
    MoodLabel.annoyed, MoodLabel.irritated, MoodLabel.stressed, MoodLabel.worried, MoodLabel.embarrassed,
    MoodLabel.calm, MoodLabel.peaceful, MoodLabel.indifferent,
    MoodLabel.content, MoodLabel.satisfied, MoodLabel.relieved, MoodLabel.grateful,
    MoodLabel.happy, MoodLabel.joyful, MoodLabel.amused, MoodLabel.hopeful,
    MoodLabel.confident, MoodLabel.proud, MoodLabel.brave, MoodLabel.passionate,
    MoodLabel.excited, MoodLabel.amazed, MoodLabel.surprised
  ];

  /** 这一档给哪几个词（常见的在前）。38 个词分到九档，每词只在一档 */
  static choices(level: MoodLevel): MoodLabel[] {
    switch (level) {
      case MoodLevel.rockBottom:
        return [MoodLabel.hopeless, MoodLabel.overwhelmed, MoodLabel.scared, MoodLabel.angry, MoodLabel.disgusted];
      case MoodLevel.heartsick:
        return [MoodLabel.sad, MoodLabel.lonely, MoodLabel.disappointed, MoodLabel.guilty, MoodLabel.ashamed];
      case MoodLevel.melancholy:
        return [MoodLabel.drained, MoodLabel.discouraged, MoodLabel.frustrated, MoodLabel.anxious, MoodLabel.jealous];
      case MoodLevel.glum:
        return [MoodLabel.annoyed, MoodLabel.irritated, MoodLabel.stressed, MoodLabel.worried, MoodLabel.embarrassed];
      case MoodLevel.even:
        return [MoodLabel.calm, MoodLabel.peaceful, MoodLabel.indifferent];
      case MoodLevel.content:
        return [MoodLabel.content, MoodLabel.satisfied, MoodLabel.relieved, MoodLabel.grateful];
      case MoodLevel.joyful:
        return [MoodLabel.happy, MoodLabel.joyful, MoodLabel.amused, MoodLabel.hopeful];
      case MoodLevel.radiant:
        return [MoodLabel.confident, MoodLabel.proud, MoodLabel.brave, MoodLabel.passionate];
      case MoodLevel.overjoyed:
        return [MoodLabel.excited, MoodLabel.amazed, MoodLabel.surprised];
      default:
        return [MoodLabel.calm, MoodLabel.peaceful, MoodLabel.indifferent];
    }
  }

  /** 这个情绪词属于九档里的哪一档（心情页就是按档给词的） */
  static levelOf(label: MoodLabel): MoodLevel {
    for (const level of MoodLevels.all) {
      if (MoodLabels.choices(level).includes(label)) {
        return level;
      }
    }
    return MoodLevel.even;
  }

  /** 认不出的 key（以后新增的词）→ undefined，显示时跳过 */
  static fromKey(key: string): MoodLabel | undefined {
    for (const label of MoodLabels.all) {
      if (MoodLabels.keyOf(label) === key) {
        return label;
      }
    }
    return undefined;
  }

  /** 存库 / 备份用的英文 key（与 iOS rawValue 一致） */
  static keyOf(label: MoodLabel): string {
    switch (label) {
      case MoodLabel.hopeless: return 'hopeless';
      case MoodLabel.overwhelmed: return 'overwhelmed';
      case MoodLabel.scared: return 'scared';
      case MoodLabel.angry: return 'angry';
      case MoodLabel.disgusted: return 'disgusted';
      case MoodLabel.sad: return 'sad';
      case MoodLabel.lonely: return 'lonely';
      case MoodLabel.disappointed: return 'disappointed';
      case MoodLabel.guilty: return 'guilty';
      case MoodLabel.ashamed: return 'ashamed';
      case MoodLabel.drained: return 'drained';
      case MoodLabel.discouraged: return 'discouraged';
      case MoodLabel.frustrated: return 'frustrated';
      case MoodLabel.anxious: return 'anxious';
      case MoodLabel.jealous: return 'jealous';
      case MoodLabel.annoyed: return 'annoyed';
      case MoodLabel.irritated: return 'irritated';
      case MoodLabel.stressed: return 'stressed';
      case MoodLabel.worried: return 'worried';
      case MoodLabel.embarrassed: return 'embarrassed';
      case MoodLabel.calm: return 'calm';
      case MoodLabel.peaceful: return 'peaceful';
      case MoodLabel.indifferent: return 'indifferent';
      case MoodLabel.content: return 'content';
      case MoodLabel.satisfied: return 'satisfied';
      case MoodLabel.relieved: return 'relieved';
      case MoodLabel.grateful: return 'grateful';
      case MoodLabel.happy: return 'happy';
      case MoodLabel.joyful: return 'joyful';
      case MoodLabel.amused: return 'amused';
      case MoodLabel.hopeful: return 'hopeful';
      case MoodLabel.confident: return 'confident';
      case MoodLabel.proud: return 'proud';
      case MoodLabel.brave: return 'brave';
      case MoodLabel.passionate: return 'passionate';
      case MoodLabel.excited: return 'excited';
      case MoodLabel.amazed: return 'amazed';
      case MoodLabel.surprised: return 'surprised';
      default: return 'calm';
    }
  }
}
