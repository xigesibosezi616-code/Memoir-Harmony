/**
 * 写日记的心情横滑选择（10_BUILD_MANUAL.md 2.1）。对应 iOS `Views/Compose/MoodSelector.swift`。
 *
 * - **只读预设**：12 个心情从 mood 表按 sortOrder 读出，用户只能选，
 *   不能新建 / 改名 / 改色（R-ENTRY-09）
 * - 单选；点已选的**不取消** —— 以 iOS 源码为准（卡片「可取消」与 iOS 不一致，
 *   记 09_OPEN_QUESTIONS，用户已确认按 iOS）
 * - 默认心情 `name` 存英文 key，显示名按语言查 `mood.*` 译文（R-LANG-09）；
 *   导入来的自定义心情显示原名，不查表
 */
import { AppTheme } from '../../theme/AppTheme';
import { BambooTheme } from '../../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../../theme/ThemeManager';
import { MoodTag, isDefaultMoodKey } from '../../models/Mood';

/**
 * 默认心情 key → 显示名资源（R-LANG-09：`mood.<key>` 的译文，七种语言齐）。
 * key 集与 Mood.ets 的 12 预设一一对应；这里只做显示映射，不重复声明预设。
 */
function moodLabelRes(key: string): Resource | undefined {
  switch (key) {
    case 'calm': return $r('app.string.s_cb2d681e91');       // 平静
    case 'productive': return $r('app.string.s_b2c510fd6a'); // 充实
    case 'reflective': return $r('app.string.s_287dbc9adc'); // 沉思
    case 'joyful': return $r('app.string.s_840d2718da');     // 喜悦
    case 'low': return $r('app.string.s_824e119909');        // 低落
    case 'anxious': return $r('app.string.s_f685ba2f14');    // 焦虑
    case 'grateful': return $r('app.string.s_83c6e3fd12');   // 感恩
    case 'excited': return $r('app.string.s_ee7391e94f');    // 期待
    case 'tired': return $r('app.string.s_d63d98608d');      // 疲惫
    case 'peaceful': return $r('app.string.s_1d72fd4c59');   // 安宁
    case 'nostalgic': return $r('app.string.s_fdc1a10b4f');  // 怀念
    case 'hopeful': return $r('app.string.s_5fdfe71cba');    // 希望
    default: return undefined;
  }
}

@Component
export struct MoodSelector {
  @Prop moods: MoodTag[] = [];
  @Prop selectedMoodName: string = '';
  onMoodPicked: (mood: MoodTag) => void = (_mood: MoodTag): void => {};
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();

  build() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.moods, (mood: MoodTag) => {
          this.moodChip(mood)
        }, (mood: MoodTag): string => mood.id)
      }
      .padding({ top: 2, bottom: 2 }) // 选中时 1.05 倍放大，留点余地不被裁
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .align(Alignment.Start)
  }

  /** 单个心情胶囊：选中 = 心情色底 + 白字；未选中 = 透明底 + moodBorder 描边 */
  @Builder
  private moodChip(mood: MoodTag) {
    Text(this.moodLabel(mood))
      .fontSize(this.theme.captionFont.size)
      .fontWeight(this.theme.captionFont.weight)
      .fontFamily(this.theme.captionFont.family)
      .fontColor(this.isSelected(mood) ? Color.White : this.theme.moodText)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.isSelected(mood) ? mood.colorHex : Color.Transparent)
      .borderRadius(14)
      .border({
        width: 0.5,
        color: this.isSelected(mood) ? mood.colorHex : this.theme.moodBorder
      })
      .scale({ x: this.isSelected(mood) ? 1.05 : 1.0, y: this.isSelected(mood) ? 1.05 : 1.0 })
      .onClick((): void => {
        // 单选、只读预设；点已选不取消（以 iOS 源码为准，见文件头注释）
        this.onMoodPicked(mood);
      })
  }

  /** 显示名：默认心情查 mood.* 译文，查不到 / 自定义心情显示原名（R-LANG-09/10） */
  private moodLabel(mood: MoodTag): ResourceStr {
    if (isDefaultMoodKey(mood.name)) {
      const res = moodLabelRes(mood.name);
      if (res !== undefined) {
        return res;
      }
    }
    return mood.name;
  }

  private isSelected(mood: MoodTag): boolean {
    return this.selectedMoodName === mood.name;
  }
}
