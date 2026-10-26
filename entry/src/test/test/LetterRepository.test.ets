/**
 * LetterRepository 映射单测（10_BUILD_MANUAL.md 5.1）。
 *
 * 库读写（listLetters / saveLetter upsert / findLetter）属设备侧验收
 * （调试页插信 → 信箱出现，5.1 验收步骤）；本套只覆盖纯映射：
 * Letter → 列值（蛇形列名、可空字段 undefined → null），与 DraftRepository
 * 测试约定一致（Local Test 不开真库，见 Database.test 说明）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { Letter, LetterStatus, LetterStationeryKind, LetterTriggerKind } from '../../main/ets/models/Letter';
import { letterToValues } from '../../main/ets/data/LetterRepository';

export default function letterRepositoryTest() {
  describe('LetterRepositoryTest', () => {
    it('letterToValuesMapsAllColumns', 0, () => {
      const letter = new Letter('l1', 1000, 2000);
      letter.status = LetterStatus.Read;
      letter.body = '正文';
      letter.fromCharacter = '青鸟';
      letter.toName = '你好';
      letter.stationery = LetterStationeryKind.Sealed;
      letter.triggerKind = LetterTriggerKind.Weekly;
      letter.errorMessage = 'err';
      letter.deliveredAt = 1500;
      letter.readAt = 1800;
      const values = letterToValues(letter);
      expect(values['id']).assertEqual('l1');
      expect(values['status']).assertEqual('read');
      expect(values['body']).assertEqual('正文');
      expect(values['from_character']).assertEqual('青鸟');
      expect(values['to_name']).assertEqual('你好');
      expect(values['stationery']).assertEqual('sealed');
      expect(values['trigger_kind']).assertEqual('weekly');
      expect(values['error_message']).assertEqual('err');
      expect(values['generated_at']).assertEqual(1000);
      expect(values['delivered_at']).assertEqual(1500);
      expect(values['read_at']).assertEqual(1800);
      expect(values['updated_at']).assertEqual(2000);
    })

    it('letterToValuesNullsOptionalColumns', 0, () => {
      const letter = new Letter('l2', 1000, 2000);
      const values = letterToValues(letter);
      expect(values['to_name']).assertNull();
      expect(values['stationery']).assertNull();
      expect(values['error_message']).assertNull();
      expect(values['delivered_at']).assertNull();
      expect(values['read_at']).assertNull();
    })

    it('letterToValuesKeepsDefaults', 0, () => {
      const letter = new Letter('l3', 1000, 2000);
      const values = letterToValues(letter);
      // 默认值（05 §6）：status pending、笔友青鸟、triggerKind weekly、正文空串
      expect(values['status']).assertEqual('pending');
      expect(values['from_character']).assertEqual('青鸟');
      expect(values['trigger_kind']).assertEqual('weekly');
      expect(values['body']).assertEqual('');
    })
  })
}
