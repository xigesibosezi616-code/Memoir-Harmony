/**
 * 心情（05_DATA_MODEL.md §5）。对应 iOS `Models/MoodTag.swift`。
 *
 * - 纯预设，用户不可增删改（R-ENTRY-09）
 * - 默认心情 `name` 存**英文 key**（`calm`…），显示时按语言查表（R-LANG-09：
 *   `mood.<key>` 资源）；导入来的自定义心情（老版本）按名字去重、显示原名
 * - 本地时间字段存毫秒
 */
export class MoodTag {
  readonly id: string;
  /** 默认心情存英文 key；自定义心情存用户输入 */
  name: string;
  colorHex: string;
  isDefault: boolean = false;
  sortOrder: number = 0;
  createdAt: number;
  /** iOS SF Symbol 名，鸿蒙映射到自己的线性图标（04 图标对照） */
  iconName?: string;

  constructor(id: string, name: string, colorHex: string, createdAt: number) {
    this.id = id;
    this.name = name;
    this.colorHex = colorHex;
    this.createdAt = createdAt;
  }
}

/** 12 个预设（顺序即 sortOrder），供首启与每次启动补齐用（R-APP-07） */
class MoodPreset {
  readonly key: string;
  readonly colorHex: string;
  readonly iconName: string;

  constructor(key: string, colorHex: string, iconName: string) {
    this.key = key;
    this.colorHex = colorHex;
    this.iconName = iconName;
  }
}

const MOOD_PRESETS: MoodPreset[] = [
  new MoodPreset('calm', '#A8C5B8', 'leaf'),
  new MoodPreset('productive', '#C5B8A8', 'flame'),
  new MoodPreset('reflective', '#B8C5D4', 'drop'),
  new MoodPreset('joyful', '#D4C8A8', 'sun.max'),
  new MoodPreset('low', '#C5B8C5', 'moon'),
  new MoodPreset('anxious', '#D4B8B8', 'bolt'),
  new MoodPreset('grateful', '#B8D4C8', 'heart'),
  new MoodPreset('excited', '#D4C4B8', 'star'),
  new MoodPreset('tired', '#B8B8D4', 'cloud'),
  new MoodPreset('peaceful', '#D4D4B8', 'wind'),
  new MoodPreset('nostalgic', '#C5D4B8', 'sparkles'),
  new MoodPreset('hopeful', '#D4B8C5', 'snowflake')
];

/**
 * 创建 12 个默认心情（id 由调用方注入生成器，模型层不碰系统 API）。
 * 每次启动都要按 key 补齐缺的预设。
 */
export function defaultMoodTags(makeId: () => string, now: number): MoodTag[] {
  const result: MoodTag[] = [];
  for (let i = 0; i < MOOD_PRESETS.length; i++) {
    const preset = MOOD_PRESETS[i];
    const tag = new MoodTag(makeId(), preset.key, preset.colorHex, now);
    tag.isDefault = true;
    tag.sortOrder = i;
    tag.iconName = preset.iconName;
    result.push(tag);
  }
  return result;
}

/** 判断英文 key 是否为 12 个预设之一 */
export function isDefaultMoodKey(key: string): boolean {
  for (const preset of MOOD_PRESETS) {
    if (preset.key === key) {
      return true;
    }
  }
  return false;
}
