/**
 * 首启默认数据单测（10_BUILD_MANUAL.md 1.5，R-APP-07）。
 * 对应 iOS `ContentView.swift` 的三件套（insertDefaultMoodTagsIfNeeded /
 * ensureAllDefaultMoodsExist / ensureDefaultTagsExist）。
 *
 * - 12 个预设心情：空库全量（preset 顺序即 sortOrder）；非空库按 key 补缺，
 *   补的接现有最大 sortOrder 后面；**以库为准，不信本机标记**（换机 /
 *   云同步恢复出来的库可能已有数据）
 * - 4 本默认日记本：只在空库时建；用户删光后重启**不重建**（数据以用户为准）
 * - 🔴 不铺任何示例日记 / 示例来信（R-APP-07）：两个纯函数只产出心情与日记本
 */
import { describe, it, expect } from '@ohos/hypium';
import { MoodTag, defaultMoodTags } from '../../main/ets/models/Mood';
import { DEFAULT_NOTEBOOK_NAMES } from '../../main/ets/models/Notebook';
import { moodsToEnsure, notebooksToEnsure } from '../../main/ets/data/DefaultData';

let idCounter = 0;
function makeId(): string {
  idCounter++;
  return `default-data-test-${idCounter}`;
}

export default function defaultDataTest() {
  describe('DefaultDataTest', () => {
    // ---- 心情：空库全量插入 ----

    it('emptyDbGetsAllTwelveDefaultMoods', 0, () => {
      const moods = moodsToEnsure([], makeId, 1000);
      expect(moods.length).assertEqual(12);
      // 顺序即 preset 顺序（sortOrder 0–11）
      expect(moods[0].name).assertEqual('calm');
      expect(moods[0].sortOrder).assertEqual(0);
      expect(moods[11].name).assertEqual('hopeful');
      expect(moods[11].sortOrder).assertEqual(11);
      for (const mood of moods) {
        expect(mood.isDefault).assertTrue();
        expect(mood.createdAt).assertEqual(1000);
        expect(mood.iconName !== undefined).assertTrue();
      }
    })

    it('completeDbAddsNothing', 0, () => {
      const existing = defaultMoodTags(makeId, 0);
      expect(moodsToEnsure(existing, makeId, 1000).length).assertEqual(0);
    })

    it('missingDefaultsAppendAfterMaxSortOrder', 0, () => {
      // 库里只剩 calm（sortOrder 7）和一个自定义心情（sortOrder 3）：
      // 补的 11 个接在现有最大值 7 后面递增
      const calm = defaultMoodTags(makeId, 0)[0];
      calm.sortOrder = 7;
      const custom = new MoodTag(makeId(), '自定义心情', '#FFFFFF', 0);
      custom.sortOrder = 3;
      const missing = moodsToEnsure([calm, custom], makeId, 1000);
      expect(missing.length).assertEqual(11);
      expect(missing[0].name).assertEqual('productive');
      expect(missing[0].sortOrder).assertEqual(8);
      expect(missing[1].name).assertEqual('reflective');
      expect(missing[1].sortOrder).assertEqual(9);
      // 不重复补已有的 calm
      for (const mood of missing) {
        expect(mood.name === 'calm').assertFalse();
      }
    })

    it('customMoodWithPresetNameDoesNotBlockBackfill', 0, () => {
      // 用户自建的同名心情不挡补齐：只与 isDefault 的行比（iOS 同款）
      const custom = new MoodTag(makeId(), 'calm', '#000000', 0);
      const missing = moodsToEnsure([custom], makeId, 1000);
      expect(missing.length).assertEqual(12);
      expect(missing[0].sortOrder).assertEqual(1); // max(0) + 1
    })

    // ---- 日记本：只在空库时建 4 本 ----

    it('emptyDbGetsFourDefaultNotebooks', 0, () => {
      const notebooks = notebooksToEnsure(0, makeId, 1000);
      expect(notebooks.length).assertEqual(4);
      for (let i = 0; i < 4; i++) {
        expect(notebooks[i].name).assertEqual(DEFAULT_NOTEBOOK_NAMES[i]);
        expect(notebooks[i].sortOrder).assertEqual(i);
        expect(notebooks[i].createdAt).assertEqual(1000);
      }
    })

    it('nonEmptyDbCreatesNoNotebooks', 0, () => {
      // 用户删光后重启不重建 —— 数据以用户为准
      expect(notebooksToEnsure(1, makeId, 1000).length).assertEqual(0);
      expect(notebooksToEnsure(5, makeId, 1000).length).assertEqual(0);
    })

    it('defaultNotebooksUseWineRedLinen', 0, () => {
      // 默认色酒红 + 亚麻纹理（与 iOS `Tag()` 声明处默认一致）
      const notebooks = notebooksToEnsure(0, makeId, 1000);
      expect(notebooks[0].colorId).assertEqual('WineRed');
      expect(notebooks[0].textureId).assertEqual('Linen');
    })
  })
}
