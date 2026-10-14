/**
 * Uuid 约定单测（10_BUILD_MANUAL.md 1.3 / 05_DATA_MODEL.md §0）。
 *
 * 新记录一律大写带横线；比较忽略大小写（备份包按 id 去重时
 * 大小写不一致会把同一篇当两篇）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { generateUuid, uuidEquals, uuidKey } from '../../main/ets/models/Uuid';

export default function uuidTest() {
  describe('UuidTest', () => {
    it('generatedUuidIsUppercaseWithDashes', 0, () => {
      const u = generateUuid();
      expect(u.length).assertEqual(36);
      expect(u === u.toUpperCase()).assertTrue();
      expect(u.charAt(8)).assertEqual('-');
      expect(u.charAt(13)).assertEqual('-');
      expect(u.charAt(18)).assertEqual('-');
      expect(u.charAt(23)).assertEqual('-');
    })

    it('generatedUuidIsVersion4', 0, () => {
      expect(generateUuid().charAt(14)).assertEqual('4');
      const variant = generateUuid().charAt(19);
      expect('89AB'.includes(variant)).assertTrue();
    })

    it('uuidEqualsIgnoresCase', 0, () => {
      expect(uuidEquals('8B1F2C3D-0000-4000-8000-ABCDEF123456',
        '8b1f2c3d-0000-4000-8000-abcdef123456')).assertTrue();
      expect(uuidEquals('8B1F2C3D-0000-4000-8000-ABCDEF123456',
        '8b1f2c3d-0000-4000-8000-abcdef123457')).assertFalse();
    })

    it('uuidKeyUppercasesForDedup', 0, () => {
      expect(uuidKey('8b1f2c3d-0000-4000-8000-abcdef123456'))
        .assertEqual('8B1F2C3D-0000-4000-8000-ABCDEF123456');
    })
  })
}
