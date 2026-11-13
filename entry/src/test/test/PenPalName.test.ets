/**
 * 笔友名纯逻辑单测（对应 iOS `PenPalName`；2026-10-24 产品定：名字只能由用户自己起）。
 *
 * - normalized：去首尾空白、截到上限 16；空串保持空
 * - truncated：输入中限长（不去空白，只截长）
 * - needsNaming：空 / 全空白 / 旧默认「青鸟」= 还没起名；正常名字 false
 * - display：没起名 → 调用方传入的本地化「笔友」；起了 → normalized
 */
import { describe, it, expect } from '@ohos/hypium';
import { PenPalName } from '../../main/ets/models/PenPalName';

/** 16 个字（上限正好）；17 个字（超一个） */
const SIXTEEN = '一二三四五六七八九十一二三四五六';
const SEVENTEEN = '一二三四五六七八九十一二三四五六七';

export default function penPalNameTest() {
  describe('PenPalName', () => {
    it('normalized_trimsAndTruncates', 0, () => {
      expect(PenPalName.normalized('  小满  ')).assertEqual('小满');
      // 首尾的换行、制表符一并裁掉（iOS whitespaceAndNewlines 同款）
      expect(PenPalName.normalized('\n\t 小满 \r\n')).assertEqual('小满');
      expect(PenPalName.normalized('')).assertEqual('');
      expect(PenPalName.normalized('   ')).assertEqual('');
      // 超上限截到 16，中间的空白不动
      expect(PenPalName.normalized(SIXTEEN)).assertEqual(SIXTEEN);
      expect(PenPalName.normalized(SEVENTEEN)).assertEqual(SIXTEEN);
      expect(PenPalName.normalized(` ${SEVENTEEN} `)).assertEqual(SIXTEEN);
    });

    it('truncated_limitsTypingWithoutTrim', 0, () => {
      expect(PenPalName.truncated('小满')).assertEqual('小满');
      expect(PenPalName.truncated(SEVENTEEN)).assertEqual(SIXTEEN);
      // 输入中不去空白：正在打的首尾空格留着，只有超长才截
      expect(PenPalName.truncated('  小满  ')).assertEqual('  小满  ');
      expect(PenPalName.truncated('')).assertEqual('');
    });

    it('needsNaming_emptyOrLegacyDefault', 0, () => {
      expect(PenPalName.needsNaming('')).assertTrue();
      expect(PenPalName.needsNaming('   ')).assertTrue();
      expect(PenPalName.needsNaming('青鸟')).assertTrue();
      // 带空白的旧默认也认（老偏好可能存过没 trim 的）
      expect(PenPalName.needsNaming(' 青鸟 ')).assertTrue();
      expect(PenPalName.needsNaming('小满')).assertFalse();
      // 名字里含「青鸟」两个字但不是它 → 是起过名的
      expect(PenPalName.needsNaming('青鸟信使')).assertFalse();
      expect(PenPalName.needsNaming(SIXTEEN)).assertFalse();
    });

    it('display_fallsBackToUnnamed', 0, () => {
      // 没起名：用调用方传入的本地化「笔友」
      expect(PenPalName.display('', '笔友')).assertEqual('笔友');
      expect(PenPalName.display('青鸟', '笔友')).assertEqual('笔友');
      expect(PenPalName.display('  ', 'Pen Pal')).assertEqual('Pen Pal');
      // 起了名：显示 normalized 后的
      expect(PenPalName.display(' 小满 ', '笔友')).assertEqual('小满');
      expect(PenPalName.display(SIXTEEN, '笔友')).assertEqual(SIXTEEN);
    });

    it('maxLength_is16', 0, () => {
      expect(PenPalName.MAX_LENGTH).assertEqual(16);
    });
  });
}
