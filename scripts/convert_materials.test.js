/**
 * scripts/convert_materials.js 与 scripts/check_localization.js 的单元测试（node:test）。
 *
 *   node --test scripts/
 */
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('path');
const fs = require('fs');

const cm = require('./convert_materials.js');
const cl = require('./check_localization.js');

// ---------- convertPlaceholders：iOS 占位符 → 鸿蒙格式化写法 ----------
test('convertPlaceholders：基础占位符', () => {
  assert.strictEqual(cm.convertPlaceholders('致%@'), '致%s');
  assert.strictEqual(cm.convertPlaceholders('已写 %lld 字'), '已写 %d 字');
  assert.strictEqual(cm.convertPlaceholders('重新发送（%llds）'), '重新发送（%ds）');
});

test('convertPlaceholders：带位置序号的占位符', () => {
  assert.strictEqual(cm.convertPlaceholders('%1$@ 篇'), '%1$s 篇');
  assert.strictEqual(cm.convertPlaceholders('清理 %1$lld 个，释放 %2$@'), '清理 %1$d 个，释放 %2$s');
  assert.strictEqual(cm.convertPlaceholders('%2$@ 于 %1$@'), '%2$s 于 %1$s');
});

test('convertPlaceholders：不动普通文本与 % 相邻内容', () => {
  assert.strictEqual(cm.convertPlaceholders('写下今天的故事'), '写下今天的故事');
  assert.strictEqual(cm.convertPlaceholders('100% 好评'), '100% 好评');
  assert.strictEqual(cm.convertPlaceholders(''), '');
});

// ---------- resName：稳定资源名 ----------
test('resName：同输入同输出、格式为 s_ + 10 位 hex', () => {
  const a = cm.resName('写下今天的故事');
  const b = cm.resName('写下今天的故事');
  assert.strictEqual(a, b);
  assert.match(a, /^s_[0-9a-f]{10}$/);
  assert.notStrictEqual(a, cm.resName('写下昨天的故事'));
});

test('resName：InfoPlist 前缀避免与正文条目碰撞', () => {
  assert.notStrictEqual(cm.resName('InfoPlist:CFBundleDisplayName'), cm.resName('CFBundleDisplayName'));
});

// ---------- extractEntries ----------
const FIXTURE = {
  sourceLanguage: 'zh-Hans',
  strings: {
    '': { localizations: {} },
    '写下今天的故事': {
      comment: '写日记占位符',
      localizations: {
        'zh-Hans': { stringUnit: { state: 'translated', value: '写下今天的故事' } },
        en: { stringUnit: { state: 'translated', value: 'Write today’s story' } },
        ja: { stringUnit: { state: 'translated', value: '今日の物語を書く' } },
      },
    },
    '已写 %lld 字': {
      localizations: {
        'zh-Hans': { stringUnit: { state: 'translated', value: '已写 %lld 字' } },
        en: { stringUnit: { state: 'translated', value: '%lld words' } },
        ja: { stringUnit: { state: 'translated', value: '%lld文字' } },
      },
    },
    '·': {},
    'Apple ID': {},
  },
};

test('extractEntries：跳过空 key，七语言值齐（缺的回退 key 原文）', () => {
  const entries = cm.extractEntries(FIXTURE, 'Localizable');
  assert.strictEqual(entries.length, 4);
  assert.ok(!entries.some((e) => e.key === ''));
  // 排序按资源名（见下一用例），这里按 key 找回条目逐一断言

  const story = entries.find((e) => e.key === '写下今天的故事');
  assert.strictEqual(story.comment, '写日记占位符');
  assert.strictEqual(story.values['zh-Hans'], '写下今天的故事');
  assert.strictEqual(story.values.en, 'Write today’s story');
  assert.strictEqual(story.values.ja, '今日の物語を書く');
  // 缺的语言回退 key 原文（与 iOS 行为一致）
  assert.strictEqual(story.values.ko, '写下今天的故事');

  const dot = entries.find((e) => e.key === '·');
  for (const { ios } of cm.LANGS) {
    assert.strictEqual(dot.values[ios], '·');
  }
});

test('extractEntries：占位符随语言各自的译文转换', () => {
  const entries = cm.extractEntries(FIXTURE, 'Localizable');
  const words = entries.find((e) => e.key === '已写 %lld 字');
  assert.strictEqual(words.values['zh-Hans'], '已写 %d 字');
  assert.strictEqual(words.values.en, '%d words');
  assert.strictEqual(words.values.ja, '%d文字');
});

test('extractEntries：InfoPlist 条目用前缀 hash，可与正文同名 key 区分', () => {
  const entries = cm.extractEntries({ strings: { CFBundleDisplayName: { localizations: {} } } }, 'InfoPlist');
  assert.strictEqual(entries[0].name, cm.resName('InfoPlist:CFBundleDisplayName'));
  assert.strictEqual(entries[0].values['zh-Hans'], 'CFBundleDisplayName');
});

test('extractEntries：结果按资源名排序（可重复运行的前提）', () => {
  const a = cm.extractEntries(FIXTURE, 'Localizable').map((e) => e.name);
  const b = cm.extractEntries(FIXTURE, 'Localizable').map((e) => e.name);
  assert.deepStrictEqual(a, b);
  assert.deepStrictEqual(a, [...a].sort());
});

test('assertNoCollisions：同名不同文抛错', () => {
  assert.throws(() => cm.assertNoCollisions([
    { name: 's_xxx', key: '甲' },
    { name: 's_xxx', key: '乙' },
  ]));
  assert.doesNotThrow(() => cm.assertNoCollisions([
    { name: 's_xxx', key: '甲' },
    { name: 's_yyy', key: '乙' },
  ]));
});

// ---------- 真实物料（集成性质：reference/ 必须已就位） ----------
test('真实 xcstrings 可解析、条数 > 600、无碰撞', () => {
  const localizable = JSON.parse(fs.readFileSync(path.join(cm.IOS_MEMOIR, 'Localizable.xcstrings'), 'utf8'));
  const infoPlist = JSON.parse(fs.readFileSync(path.join(cm.IOS_MEMOIR, 'InfoPlist.xcstrings'), 'utf8'));
  const entries = cm.extractEntries(localizable, 'Localizable')
    .concat(cm.extractEntries(infoPlist, 'InfoPlist'));
  assert.ok(entries.length > 600, `条数 ${entries.length}`);
  assert.doesNotThrow(() => cm.assertNoCollisions(entries));
});

test('图片 / 声音清单的源文件都存在', () => {
  for (const [src] of cm.IMAGE_MAP) {
    assert.ok(fs.existsSync(path.join(cm.IOS_MEMOIR, src)), `缺 ${src}`);
  }
  for (const [src] of cm.SOUND_FILES) {
    assert.ok(fs.existsSync(path.join(cm.IOS_MEMOIR, src)), `缺 ${src}`);
  }
});

// ---------- check_localization 的词法与匹配 ----------
test('extractStringLiterals：剥注释、取三种引号、记行号', () => {
  const src = [
    '// 注释里的 "中文" 不算',
    'const a = "已写 3 字"; /* 块注释',
    '继续块注释 */ const b = \'尺素\';',
    'const c = `致 ${name} 的信`;',
  ].join('\n');
  const lits = cl.extractStringLiterals(src);
  assert.deepStrictEqual(lits.map((l) => l.text), ['已写 3 字', '尺素', '致 ${name} 的信']);
  assert.strictEqual(lits[0].line, 2);
  assert.strictEqual(lits[1].line, 3);
  assert.strictEqual(lits[2].line, 4);
});

test('extractStringLiterals：转义引号与插值嵌套', () => {
  const src = 'const s = "他说\\"好\\""; const t = `${f({ a: `内层` })} 完`;';
  const lits = cl.extractStringLiterals(src);
  assert.deepStrictEqual(lits.map((l) => l.text), ['他说"好"', '${f({ a: `内层` })} 完']);
});

test('literalPattern：插值当通配，能匹配索引原文', () => {
  const rx = cl.literalPattern('已写 ${count} 字');
  assert.ok(rx.test('已写 %d 字'));
  assert.ok(rx.test('已写 %lld 字'));
  // 「已写 3 字」也能匹配是通配语义的正确行为（格式化结果本就等价），
  // 真正要抓的是固定部分都不同的句子：
  assert.ok(!rx.test('完全不同的句子'));
  const exact = cl.literalPattern('写下今天的故事');
  assert.ok(exact.test('写下今天的故事'));
  assert.ok(!exact.test('写下昨天的故事'));
});

test('literalPattern：嵌套花括号的插值不被截断', () => {
  const rx = cl.literalPattern('共 ${fmt({ n: count })} 篇');
  assert.ok(rx.test('共 %d 篇'));
});

test('splitInterpolations：普通文本返回单片段', () => {
  assert.deepStrictEqual(cl.splitInterpolations('没有插值'), ['没有插值']);
});
