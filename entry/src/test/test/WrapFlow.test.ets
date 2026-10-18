/**
 * 绕排引擎单测（10_BUILD_MANUAL.md 2.7，R-RICH-02）。
 * mock 测量器：等宽字符贪心换行（正文字符 10vp、小标题 14vp），
 * 覆盖锚定语义 / 逐行缩进切分 / 跨块续排 / 多照片串联 / 无重叠不变量 /
 * 宽度变化重排确定性 / 相纸尺寸公式。
 */
import { describe, it, expect } from '@ohos/hypium';
import { PaperStyle, PhotoPosition, TextStyleRun } from '../../main/ets/models/ContentBlock';
import {
  CardSize,
  TextLayoutAdapter,
  TextMeasureResult,
  TextPart,
  WrapFlowItem,
  WrapFlowPhotoItem,
  WrapFlowTextItem,
  photoCardMetrics,
  textPartsOfBlock
} from '../../main/ets/views/components/richtext/WrapFlowModel';
import { WrapFlowEngine, WrapFlowParams } from '../../main/ets/views/components/richtext/WrapFlowEngine';

/** mock 测量器：每字符 10vp（小标题 14vp），贪心换行；行号超数组取末位缩进 */
class MockAdapter implements TextLayoutAdapter {
  /** mock 实测行距（vp）：默认与参数行高一致；子类覆写以模拟「实绘≠参数」 */
  mockPitch: number = -1;

  measure(text: string, isHeading: boolean, width: number,
    headIndents: number[], tailIndents: number[]): TextMeasureResult {
    const charW = isHeading ? 14 : 10;
    let line = 0;
    let x = 0;
    for (let i = 0; i < text.length; i++) {
      const head = line < headIndents.length ? headIndents[line] : headIndents[headIndents.length - 1];
      const tail = line < tailIndents.length ? tailIndents[line] : tailIndents[tailIndents.length - 1];
      const avail = width - head - tail;
      if (x > 0 && x + charW > avail) {
        line++;
        x = 0;
      }
      x += charW;
    }
    return new TextMeasureResult(line + 1);
  }

  measurePitch(isHeading: boolean): number {
    if (this.mockPitch > 0) {
      return isHeading ? Math.max(this.mockPitch, 28) : this.mockPitch;
    }
    return isHeading ? 28 : 20;
  }
}

/** 实测行距 16vp 的 mock（模拟 strut 不生效：实绘 16.3vp ≠ 参数 20vp） */
class Pitch16Adapter extends MockAdapter {
  constructor() {
    super();
    this.mockPitch = 16;
  }
}

/** 生产参数：正文行高 20、小标题行高 28、间距 12、下沉 4（与常量一致） */
function makeEngine(): WrapFlowEngine {
  return new WrapFlowEngine(new WrapFlowParams(20, 28, 12, 4), new MockAdapter());
}

function text(textValue: string, isHeading: boolean = false): WrapFlowTextItem {
  return new WrapFlowTextItem(textValue, isHeading);
}

function photo(id: string, lane: PhotoPosition, w: number, h: number): WrapFlowPhotoItem {
  return new WrapFlowPhotoItem(id, lane, new CardSize(w, h));
}

/** 「a」× n 的正文（每字符 10vp） */
function body(n: number): string {
  let s = '';
  for (let i = 0; i < n; i++) {
    s += 'a';
  }
  return s;
}

export default function wrapFlowTest() {

describe('WrapFlowEngine', () => {
  it('无照片：全宽顺序排版，段落高=行数×行高', 0, () => {
    const result = makeEngine().layout([text(body(4)), text(body(4)), text(body(4))], 100);
    expect(result.photos.length).assertEqual(0);
    expect(result.paragraphs.length).assertEqual(3);
    expect(result.paragraphs[0].y).assertEqual(0);
    expect(result.paragraphs[1].y).assertEqual(20);
    expect(result.paragraphs[2].y).assertEqual(40);
    expect(result.totalHeight).assertEqual(60);
    // 无遮挡段：缩进数组只有末位哨兵 0
    expect(result.paragraphs[0].headIndents.length).assertEqual(1);
    expect(result.paragraphs[0].headIndents[0]).assertEqual(0);
    expect(result.paragraphs[0].tailIndents.length).assertEqual(1);
  });

  it('左照片锚定：y=首段+4，x=0，遮挡行 headIndent=卡宽+间距，末位归 0', 0, () => {
    // 卡 46×60：y 4..64，与行带 0-20/20-40/40-60/60-80 都重叠 → 4 行受挡
    const result = makeEngine().layout([photo('p1', PhotoPosition.Left, 46, 60), text(body(30))], 100);
    expect(result.photos.length).assertEqual(1);
    const p = result.photos[0];
    expect(p.x).assertEqual(0);
    expect(p.y).assertEqual(4);
    const para = result.paragraphs[0];
    // 受挡行可用宽 100-58=42 → 每行 4 字符；4 受挡行装 16 字，
    // 余 14 字在 2 行全宽行装完（10+4）→ 共 6 行
    expect(para.lineCount).assertEqual(6);
    expect(para.headIndents.length).assertEqual(5);
    expect(para.headIndents[0]).assertEqual(46 + 12);
    expect(para.headIndents[3]).assertEqual(58);
    expect(para.headIndents[4]).assertEqual(0);
    expect(para.tailIndents.length).assertEqual(5);
    expect(para.tailIndents[0]).assertEqual(0);
  });

  it('右照片锚定：x=容器宽-卡宽，遮挡行 tailIndent=容器宽-照片左边+间距', 0, () => {
    const result = makeEngine().layout([photo('p1', PhotoPosition.Right, 46, 60), text(body(30))], 100);
    const p = result.photos[0];
    expect(p.x).assertEqual(54);
    expect(p.y).assertEqual(4);
    const para = result.paragraphs[0];
    expect(para.tailIndents[0]).assertEqual(100 - 54 + 12);
    expect(para.headIndents[0]).assertEqual(0);
  });

  it('照片高于锚定段：后续段落从行 0 起继续缩进（iOS 跨段续排同款）', 0, () => {
    // 卡 46×100：y 4..104；锚定段只放得下 1 行（4 字符），第二段接续绕排
    const result = makeEngine().layout(
      [photo('p1', PhotoPosition.Left, 46, 100), text(body(4)), text(body(4))], 100);
    const para0 = result.paragraphs[0];
    expect(para0.y).assertEqual(0);
    expect(para0.lineCount).assertEqual(1);
    const para1 = result.paragraphs[1];
    expect(para1.y).assertEqual(20);
    // 第二段：照片 4..104 与其行带 20-40/40-60/60-80/80-100/100-120 重叠 → 行 0..4 受挡
    expect(para1.headIndents.length).assertEqual(6);
    expect(para1.headIndents[0]).assertEqual(58);
    expect(para1.headIndents[4]).assertEqual(58);
    expect(para1.headIndents[5]).assertEqual(0);
  });

  it('照片底边越过游标后出活跃表：之后的段落恢复全宽', 0, () => {
    // 卡 46×60（y 4..64）：第一段 30 字符占 6 行（y 0..120），照片早已出表
    const result = makeEngine().layout(
      [photo('p1', PhotoPosition.Left, 46, 60), text(body(30)), text(body(4))], 100);
    const para1 = result.paragraphs[1];
    expect(para1.y).assertEqual(120);
    expect(para1.headIndents.length).assertEqual(1);
    expect(para1.headIndents[0]).assertEqual(0);
  });

  it('同车道第二张照片串联：y=锚定位置 与 上一张底边+间距 取大', 0, () => {
    // 第一张 46×60（y 4..64）；中间段 1 行（y 0..20）；第二张锚定 y=20 → 推到 76
    const result = makeEngine().layout(
      [photo('p1', PhotoPosition.Left, 46, 60), text(body(4)),
       photo('p2', PhotoPosition.Left, 46, 40), text(body(4))], 100);
    const p1 = result.photos[0];
    const p2 = result.photos[1];
    expect(p1.y).assertEqual(4);
    expect(p2.y).assertEqual(64 + 12);
    // 第二段（y 20..40）只被 p1 遮挡行 0
    expect(result.paragraphs[0].headIndents[0]).assertEqual(58);
  });

  it('左右对开同一锚定段：head 与 tail 同时生效', 0, () => {
    const result = makeEngine().layout(
      [photo('l', PhotoPosition.Left, 40, 50), photo('r', PhotoPosition.Right, 40, 50),
       text(body(50))], 100);
    const para = result.paragraphs[0];
    expect(para.headIndents[0]).assertEqual(40 + 12);
    expect(para.tailIndents[0]).assertEqual(100 - 60 + 12);
    // 受挡行可用宽 100-52-52=-4 → 每行 0 字符仍然逐行推进（mock 贪心换行）
    expect(para.headIndents[2]).assertEqual(52);
    expect(para.headIndents[3]).assertEqual(0);
  });

  it('无重叠不变量：每个受挡行，其缩进 ≥ 所有与该行带相交照片的让位宽', 0, () => {
    const items: WrapFlowItem[] = [
      photo('l1', PhotoPosition.Left, 46, 90),
      text(body(20)),
      photo('r1', PhotoPosition.Right, 46, 70),
      text(body(20)),
      photo('l2', PhotoPosition.Left, 46, 50),
      text(body(20)),
      text(body(20))
    ];
    const engine = makeEngine();
    const result = engine.layout(items, 100);
    for (const para of result.paragraphs) {
      for (let line = 0; line < para.lineCount; line++) {
        const bandTop = para.y + line * para.lineHeight;
        const bandBottom = bandTop + para.lineHeight;
        for (const ph of result.photos) {
          const overlap = ph.y < bandBottom - 0.01 && ph.bottom() > bandTop + 0.01;
          if (!overlap) {
            continue;
          }
          if (ph.lane === PhotoPosition.Left) {
            expect(para.headIndents[Math.min(line, para.headIndents.length - 1)])
              .assertLargerOrEqual(ph.right() + 12 - 0.01);
          } else {
            expect(para.tailIndents[Math.min(line, para.tailIndents.length - 1)])
              .assertLargerOrEqual(100 - ph.x + 12 - 0.01);
          }
        }
      }
    }
    // 照片彼此不重叠（同车道）
    const lefts = result.photos.filter(p => p.lane === PhotoPosition.Left);
    for (let i = 1; i < lefts.length; i++) {
      expect(lefts[i].y).assertLargerOrEqual(lefts[i - 1].bottom() + 12 - 0.01);
    }
  });

  it('宽度变化重排：结果只依赖输入（确定性），右照片贴右边', 0, () => {
    const engine = makeEngine();
    const items: WrapFlowItem[] = [photo('p', PhotoPosition.Right, 46, 60), text(body(30))];
    const r1 = engine.layout(items, 100);
    const r2 = engine.layout(items, 100);
    expect(r2.photos[0].x).assertEqual(r1.photos[0].x);
    expect(r2.paragraphs[0].lineCount).assertEqual(r1.paragraphs[0].lineCount);
    const wide = engine.layout(items, 200);
    expect(wide.photos[0].x).assertEqual(200 - 46);
  });

  it('文末照片：锚在文字流末尾，总高=照片底边', 0, () => {
    const result = makeEngine().layout([text(body(4)), photo('p', PhotoPosition.Left, 46, 60)], 100);
    expect(result.photos[0].y).assertEqual(20 + 4);
    expect(result.totalHeight).assertEqual(24 + 60);
  });

  it('小标题段：行高走 headingLineHeight，缩进按其行带判定', 0, () => {
    const result = makeEngine().layout(
      [photo('p', PhotoPosition.Left, 46, 60), text(body(10), true)], 100);
    const para = result.paragraphs[0];
    expect(para.lineHeight).assertEqual(28);
    // 卡 y 4..64 与小标题行带 0-28/28-56/56-84 相交 → 3 行受挡
    expect(para.headIndents.length).assertEqual(4);
    expect(para.headIndents[0]).assertEqual(58);
  });

  it('空段落：至少占一行高', 0, () => {
    const result = makeEngine().layout([text(''), text(body(4))], 100);
    expect(result.paragraphs[0].lineCount).assertEqual(1);
    expect(result.paragraphs[0].height).assertEqual(20);
    expect(result.paragraphs[1].y).assertEqual(20);
  });

  it('实测行距生效：实绘 16vp ≠ 参数 20vp 时，推进/行带/锚定全按 16', 0, () => {
    // strut 不生效的实况：引擎几何必须消费 measurePitch 而非参数行高
    const engine = new WrapFlowEngine(new WrapFlowParams(20, 28, 12, 4), new Pitch16Adapter());
    const result = engine.layout([text(body(4)), text(body(4))], 100);
    expect(result.paragraphs[0].lineHeight).assertEqual(16);
    expect(result.paragraphs[0].height).assertEqual(16);
    expect(result.paragraphs[1].y).assertEqual(16);
    expect(result.totalHeight).assertEqual(32);
  });

  it('实测行距下照片遮挡带按 16 切分：受挡行数与缩进末位正确', 0, () => {
    // 卡 46×60（y 4..64）：16vp 行带 0-16/16-32/32-48/48-64 全部相交，64-80 不相交
    const engine = new WrapFlowEngine(new WrapFlowParams(20, 28, 12, 4), new Pitch16Adapter());
    const result = engine.layout([photo('p1', PhotoPosition.Left, 46, 60), text(body(30))], 100);
    expect(result.photos[0].y).assertEqual(4);
    const para = result.paragraphs[0];
    // 4 个受挡行 + 末位哨兵
    expect(para.headIndents.length).assertEqual(5);
    expect(para.headIndents[0]).assertEqual(58);
    expect(para.headIndents[3]).assertEqual(58);
    expect(para.headIndents[4]).assertEqual(0);
    // 受挡行可用宽 42 → 4 字/行 ×4 行 = 16 字，余 14 字 → 2 行 → 共 6 行；段高 6×16
    expect(para.lineCount).assertEqual(6);
    expect(para.height).assertEqual(96);
  });

  it('实测行距下照片跨段续排：第二段行带按 16 对齐照片底缘不遮字', 0, () => {
    // 卡 46×100（y 4..104）：锚定段 1 行（y 0..16），照片远高于段——跨段续排
    const engine = new WrapFlowEngine(new WrapFlowParams(20, 28, 12, 4), new Pitch16Adapter());
    const result = engine.layout(
      [photo('p1', PhotoPosition.Left, 46, 100), text(body(4)), text(body(4))], 100);
    const para1 = result.paragraphs[1];
    expect(para1.y).assertEqual(16);
    // 第二段行带 16-32/…/96-112 与照片 4..104 相交至行 5（96-112 含底缘 104）
    expect(para1.headIndents.length).assertEqual(7);
    expect(para1.headIndents[5]).assertEqual(58);
    expect(para1.headIndents[6]).assertEqual(0);
  });

  it('实测行距下文末照片紧贴实绘文字：锚定 y=流末+下沉（无漂移空隙）', 0, () => {
    const engine = new WrapFlowEngine(new WrapFlowParams(20, 28, 12, 4), new Pitch16Adapter());
    const result = engine.layout([text(body(4)), photo('p', PhotoPosition.Left, 46, 60)], 100);
    // 1 行实绘 16vp：照片顶 = 16+4，而非参数行高的 20+4
    expect(result.photos[0].y).assertEqual(20);
    expect(result.totalHeight).assertEqual(80);
  });

  it('measurePitch 不可用（≤0）：回退参数行高，行为与旧几何一致', 0, () => {
    class NoPitchAdapter extends MockAdapter {
      measurePitch(_isHeading: boolean): number {
        return 0;
      }
    }
    const engine = new WrapFlowEngine(new WrapFlowParams(20, 28, 12, 4), new NoPitchAdapter());
    const result = engine.layout([text(body(4)), text(body(4))], 100);
    expect(result.paragraphs[0].lineHeight).assertEqual(20);
    expect(result.paragraphs[1].y).assertEqual(20);
  });
});

describe('textPartsOfBlock（\\n 行段拆分）', () => {
  it('无 \\n：单段，runs 原样平移，非 heading', 0, () => {
    const run = new TextStyleRun(1, 2);
    run.bold = true;
    const parts = textPartsOfBlock('abcd', [run]);
    expect(parts.length).assertEqual(1);
    expect(parts[0].text).assertEqual('abcd');
    expect(parts[0].localStart).assertEqual(0);
    expect(parts[0].isHeading).assertFalse();
    expect(parts[0].runs.length).assertEqual(1);
    expect(parts[0].runs[0].location).assertEqual(1);
    expect(parts[0].runs[0].length).assertEqual(2);
    expect(parts[0].runs[0].bold).assertTrue();
  });

  it('heading 只覆盖首行：拆段后首段 heading、次段正文（8B704EE9 场景）', 0, () => {
    const heading = new TextStyleRun(0, 5);
    heading.heading = true;
    const highlight = new TextStyleRun(6, 2);
    highlight.highlight = true;
    const parts = textPartsOfBlock('夏日的午后\n今天整理了照片', [heading, highlight]);
    expect(parts.length).assertEqual(2);
    expect(parts[0].text).assertEqual('夏日的午后');
    expect(parts[0].localStart).assertEqual(0);
    expect(parts[0].isHeading).assertTrue();
    expect(parts[0].runs.length).assertEqual(1);
    expect(parts[0].runs[0].heading).assertTrue();
    expect(parts[1].text).assertEqual('今天整理了照片');
    expect(parts[1].localStart).assertEqual(6);
    expect(parts[1].isHeading).assertFalse();
    expect(parts[1].runs.length).assertEqual(1);
    expect(parts[1].runs[0].location).assertEqual(0);
    expect(parts[1].runs[0].length).assertEqual(2);
    expect(parts[1].runs[0].highlight).assertTrue();
  });

  it('run 跨 \\n：两侧各切片平移（b/c 加粗）', 0, () => {
    const run = new TextStyleRun(1, 3);
    run.bold = true;
    const parts = textPartsOfBlock('ab\ncd', [run]);
    expect(parts.length).assertEqual(2);
    expect(parts[0].runs[0].location).assertEqual(1);
    expect(parts[0].runs[0].length).assertEqual(1);
    expect(parts[1].runs[0].location).assertEqual(0);
    expect(parts[1].runs[0].length).assertEqual(1);
  });

  it('连续空行与末尾 \\n：空行成空段（占一行高）', 0, () => {
    const parts = textPartsOfBlock('a\n\nb', []);
    expect(parts.length).assertEqual(3);
    expect(parts[0].text).assertEqual('a');
    expect(parts[0].localStart).assertEqual(0);
    expect(parts[1].text).assertEqual('');
    expect(parts[1].localStart).assertEqual(2);
    expect(parts[2].text).assertEqual('b');
    expect(parts[2].localStart).assertEqual(3);
    const tail = textPartsOfBlock('a\n', []);
    expect(tail.length).assertEqual(2);
    expect(tail[1].text).assertEqual('');
    expect(tail[1].localStart).assertEqual(2);
  });

  it('空文本：一个空段；writtenAt/struckAt 全量拷贝', 0, () => {
    const empty = textPartsOfBlock('', []);
    expect(empty.length).assertEqual(1);
    expect(empty[0].text).assertEqual('');
    expect(empty[0].localStart).assertEqual(0);
    const run = new TextStyleRun(0, 1);
    run.writtenAt = 1000;
    run.struckAt = 2000;
    const parts = textPartsOfBlock('a', [run]);
    expect(parts[0].runs[0].writtenAt).assertEqual(1000);
    expect(parts[0].runs[0].struckAt).assertEqual(2000);
  });

  it('拆段喂引擎：heading 行段与正文行段各按各行距推进', 0, () => {
    // 块「标题行\\n正文行」拆两段 → 两段排版，heading 段按 28vp 行距推进
    const headingRun = new TextStyleRun(0, 3);
    headingRun.heading = true;
    const parts = textPartsOfBlock('标题行\n正文行', [headingRun]);
    const items: WrapFlowItem[] = parts.map((p: TextPart): WrapFlowItem =>
      new WrapFlowTextItem(p.text, p.isHeading, p.runs));
    const result = makeEngine().layout(items, 100);
    expect(result.paragraphs.length).assertEqual(2);
    expect(result.paragraphs[0].lineHeight).assertEqual(28);
    expect(result.paragraphs[1].y).assertEqual(28);
    expect(result.paragraphs[1].lineHeight).assertEqual(20);
  });
});

describe('photoCardMetrics', () => {
  it('六种相纸外框公式与 PhotoPapers 组件布局一致', 0, () => {
    const w = 100;
    const a = 4 / 3;
    // 原图：整卡即格子
    expect(photoCardMetrics(w, a, PaperStyle.Original).height).assertEqual(75);
    // 宝丽来：格子宽 84 + 四周 16 + 底部 28
    expect(photoCardMetrics(w, a, PaperStyle.Polaroid).height).assertClose(84 / a + 44, 0.001);
    // 和风贴纸：格子宽 88 + 四周 12
    expect(photoCardMetrics(w, a, PaperStyle.WashiSticker).height).assertClose(88 / a + 12, 0.001);
    // 极简卡片：整卡即格子
    expect(photoCardMetrics(w, a, PaperStyle.MinimalCard).height).assertEqual(75);
    // 胶片帧：格子宽 52 + 四周 12
    expect(photoCardMetrics(w, a, PaperStyle.FilmFrame).height).assertClose(52 / a + 12, 0.001);
    // 信纸附照：格子宽 92 + 四周 8
    expect(photoCardMetrics(w, a, PaperStyle.LetterAttached).height).assertClose(92 / a + 8, 0.001);
  });

  it('非法比例兜底 4:3，宽度原样返回', 0, () => {
    const m = photoCardMetrics(90, 0, PaperStyle.Original);
    expect(m.width).assertEqual(90);
    expect(m.height).assertClose(90 / (4 / 3), 0.001);
  });
});
}
