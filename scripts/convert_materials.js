#!/usr/bin/env node
/**
 * 物料转换（10_BUILD_MANUAL.md 0.4）—— 把 iOS 移交的字符串 / 图片 / 声音
 * 转成鸿蒙工程资源。本机没有 python3，用 Node.js。
 *
 *   node scripts/convert_materials.js
 *
 * 可重复运行：输出是确定性的。
 *   - 字符串资源名 = "s_" + SHA1(简中原文 / "InfoPlist:" + key) 前 10 位，
 *     同一份 xcstrings 跑多少遍，资源名不变；
 *   - 生成条目按资源名排序写出，不写时间戳。
 *
 * 做四件事：
 *   1. Localizable.xcstrings → entry 的 base + 七语言目录 element/string.json，
 *      并在工程根输出 strings_index.json（资源名 → 简中原文 / iOS 注释）；
 *   2. InfoPlist.xcstrings   → App 名（AppScope 的 app_name、entry 的
 *      EntryAbility_label，R-LANG-06）+ 权限说明（entry 字符串资源，R-LANG-05）；
 *   3. 图片（0.1 清单 + BookOpen/Texture，见 IMAGE_MAP）→ base/media，小写下划线命名；
 *   4. 声音（5 个 wav，见 SOUND_FILES）→ rawfile/sounds/，原样。
 *
 * 无译文的 xcstrings 条目（如 "·"、"#%@"、"Apple ID"）与 iOS 的回退行为一致：
 * 七种语言都填 key 原文（占位符已转换）。空 key（""）跳过。
 * 只读 reference/，不改 iOS 参考目录里的任何文件。
 */
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const IOS_MEMOIR = path.join(ROOT, 'reference', 'ios', 'Memoir');
const ENTRY_RES = path.join(ROOT, 'entry', 'src', 'main', 'resources');
const APPSCOPE_RES = path.join(ROOT, 'AppScope', 'resources');
const INDEX_FILE = path.join(ROOT, 'strings_index.json');

/** 七种语言：iOS 语言码 → 鸿蒙限定词目录名（R-LANG-01，顺序固定） */
const LANGS = [
  { ios: 'zh-Hans', dir: 'zh_Hans' },
  { ios: 'zh-Hant', dir: 'zh_Hant' },
  { ios: 'en', dir: 'en' },
  { ios: 'ja', dir: 'ja' },
  { ios: 'ko', dir: 'ko' },
  { ios: 'fr', dir: 'fr' },
  { ios: 'es', dir: 'es' },
];

/**
 * iOS 格式占位符 → 鸿蒙格式化写法（R-LANG-07：带参数的整句保持整句）。
 *   %@ → %s    %lld → %d    %1$@ → %1$s    %2$lld → %2$d
 */
function convertPlaceholders(text) {
  return text
    .replace(/%(\d+)\$@/g, '%$1$s')
    .replace(/%(\d+)\$lld/g, '%$1$d')
    .replace(/%(\d+)\$ld/g, '%$1$d')
    .replace(/%@/g, '%s')
    .replace(/%lld/g, '%d')
    .replace(/%ld/g, '%d');
}

/** 稳定资源名：s_ + 原文 SHA1 前 10 位 */
function resName(hashInput) {
  return 's_' + crypto.createHash('sha1').update(hashInput, 'utf8').digest('hex').slice(0, 10);
}

function loadXcstrings(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

/**
 * 从 xcstrings 提取待转条目。
 * source: 'Localizable'（hash 输入 = key）| 'InfoPlist'（hash 输入 = "InfoPlist:" + key）
 * 返回 [{ name, key, comment, source, values: { iOS语言码: 转换后文本 } }]，按 name 排序。
 */
function extractEntries(xcstrings, source) {
  const out = [];
  for (const [key, entry] of Object.entries(xcstrings.strings || {})) {
    if (key === '') {
      continue;
    }
    const name = resName(source === 'InfoPlist' ? 'InfoPlist:' + key : key);
    const locs = entry.localizations || {};
    const values = {};
    for (const { ios } of LANGS) {
      const unit = locs[ios] && locs[ios].stringUnit;
      const raw = typeof unit === 'object' && typeof unit.value === 'string' ? unit.value : key;
      values[ios] = convertPlaceholders(raw);
    }
    out.push({ name, key, comment: entry.comment || '', source, values });
  }
  out.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  return out;
}

/** 资源名碰撞检查：不同 hash 输入生成同一资源名 → 直接失败 */
function assertNoCollisions(entries) {
  const seen = new Map();
  for (const e of entries) {
    const prev = seen.get(e.name);
    if (prev && prev !== e.key) {
      throw new Error(`资源名碰撞: ${e.name} ← ${JSON.stringify(prev)} / ${JSON.stringify(e.key)}`);
    }
    seen.set(e.name, e.key);
  }
}

/** 图片映射：[iOS 相对 Memoir 的源路径, base/media 下的目标名] */
const IMAGE_MAP = [
  // 三套 App 图标（0.1 物料清单；6.2 主题与图标会接线）
  ['Assets.xcassets/AppIcon.appiconset/memoir-icon-any-1024.png', 'app_icon_any_1024.png'],
  ['Assets.xcassets/AppIcon.appiconset/memoir-icon-dark-1024.png', 'app_icon_dark_1024.png'],
  ['Assets.xcassets/AppIcon.appiconset/memoir-icon-tinted-1024.png', 'app_icon_tinted_1024.png'],
  ['Assets.xcassets/KentIcon.appiconset/kent-icon-1024.png', 'kent_icon_1024.png'],
  ['Assets.xcassets/LeatherIcon.appiconset/leather-icon-1024.png', 'leather_icon_1024.png'],
  // App 图标预览（主题选择）
  ['Assets.xcassets/AppIconPreview_Bamboo.imageset/AppIconPreview_Bamboo.png', 'app_icon_preview_bamboo.png'],
  ['Assets.xcassets/AppIconPreview_Leather.imageset/AppIconPreview_Leather.png', 'app_icon_preview_leather.png'],
  ['Assets.xcassets/AppIconPreview_Kent.imageset/AppIconPreview_Kent.png', 'app_icon_preview_kent.png'],
  // 书打开的插画
  ['Assets.xcassets/BookOpen_Leather.imageset/BookOpen_Leather.png', 'book_open_leather.png'],
  ['Assets.xcassets/BookOpen_Nordic.imageset/BookOpen_Nordic.png', 'book_open_nordic.png'],
  ['Assets.xcassets/BookOpen_Washi.imageset/BookOpen_Washi.png', 'book_open_washi.png'],
  // 品牌 Logo、协议同意页背景
  ['Assets.xcassets/BrandLogo.imageset/Sinara玄纳司-LOGO-06.jpg', 'brand_logo.jpg'],
  ['Assets.xcassets/ConsentBackground.imageset/consent_bg.jpg', 'consent_background.jpg'],
  // 日记本布面（11 色）
  ['Assets.xcassets/Cover_AmberBrown_Linen.imageset/Cover_AmberBrown_Linen.png', 'cover_amber_brown_linen.png'],
  ['Assets.xcassets/Cover_BronzeBrown_Linen.imageset/Cover_BronzeBrown_Linen.png', 'cover_bronze_brown_linen.png'],
  ['Assets.xcassets/Cover_Charcoal_Linen.imageset/Cover_Charcoal_Linen.png', 'cover_charcoal_linen.png'],
  ['Assets.xcassets/Cover_Eggplant_Linen.imageset/Cover_Eggplant_Linen.png', 'cover_eggplant_linen.png'],
  ['Assets.xcassets/Cover_Ivory_Linen.imageset/Cover_Ivory_Linen.png', 'cover_ivory_linen.png'],
  ['Assets.xcassets/Cover_OliveBrown_Linen.imageset/Cover_OliveBrown_Linen.png', 'cover_olive_brown_linen.png'],
  ['Assets.xcassets/Cover_PineGreen_Linen.imageset/Cover_PineGreen_Linen.png', 'cover_pine_green_linen.png'],
  ['Assets.xcassets/Cover_PrussianBlue_Linen.imageset/Cover_PrussianBlue_Linen.png', 'cover_prussian_blue_linen.png'],
  ['Assets.xcassets/Cover_RustRed_Linen.imageset/Cover_RustRed_Linen.png', 'cover_rust_red_linen.png'],
  ['Assets.xcassets/Cover_Slate_Linen.imageset/Cover_Slate_Linen.png', 'cover_slate_linen.png'],
  ['Assets.xcassets/Cover_WineRed_Linen.imageset/Cover_WineRed_Linen.png', 'cover_wine_red_linen.png'],
  // 邮筒插画（三主题）
  ['Assets.xcassets/Mailbox_Bamboo.imageset/mailbox-bamboo.png', 'mailbox_bamboo.png'],
  ['Assets.xcassets/Mailbox_Leather.imageset/mailbox-leather.png', 'mailbox_leather.png'],
  ['Assets.xcassets/Mailbox_Kent.imageset/mailbox-kent.png', 'mailbox_kent.png'],
  // 纸纹（主题系统）
  ['Assets.xcassets/Texture_Canvas.imageset/Texture_Canvas.png', 'texture_canvas.png'],
  ['Assets.xcassets/Texture_Denim.imageset/Texture_Denim.png', 'texture_denim.png'],
  ['Assets.xcassets/Texture_Leather.imageset/Texture_Leather.png', 'texture_leather.png'],
  ['Assets.xcassets/Texture_Linen.imageset/Texture_Linen.png', 'texture_linen.png'],
  ['Assets.xcassets/Texture_Paper.imageset/Texture_Paper.png', 'texture_paper.png'],
  // 启动封面（1290×2796）
  ['Resources/SplashCovers/splash_bamboo.png', 'splash_bamboo.png'],
  ['Resources/SplashCovers/splash_leather.png', 'splash_leather.png'],
  ['Resources/SplashCovers/splash_kent.png', 'splash_kent.png'],
];

/** 声音：[iOS 相对 Memoir 的源路径, rawfile/sounds 下的目标名]（原样拷贝） */
const SOUND_FILES = [
  ['Resources/Sounds/letter_open_1.wav', 'letter_open_1.wav'],
  ['Resources/Sounds/letter_open_2.wav', 'letter_open_2.wav'],
  ['Resources/Sounds/letter_open_3.wav', 'letter_open_3.wav'],
  ['Resources/Sounds/letter_post_plain.wav', 'letter_post_plain.wav'],
  ['Resources/Sounds/letter_post_sealed.wav', 'letter_post_sealed.wav'],
];

/** 读 element/string.json；不存在或解析失败返回 null */
function readStringJson(file) {
  if (!fs.existsSync(file)) {
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    return null;
  }
}

/**
 * 合并写出一个 string.json：
 *   - 保留文件里已有的非生成条目（"s_" 开头视为生成条目，由本脚本全权管理）；
 *   - keepOriginals 里的固定名条目按给定值强制更新（如 EntryAbility_label）；
 *   - 追加 generated（[{name, value}]，调用方保证已排序）。
 */
function mergeWriteStringJson(file, generated, keepOriginals) {
  const existing = readStringJson(file);
  const kept = [];
  if (existing && Array.isArray(existing.string)) {
    for (const item of existing.string) {
      if (typeof item.name === 'string' && !item.name.startsWith('s_')) {
        kept.push({ name: item.name, value: item.value });
      }
    }
  }
  const keepNames = new Set(keepOriginals.map((k) => k.name));
  const merged = kept.filter((k) => !keepNames.has(k.name)).concat(keepOriginals);
  const out = { string: merged.concat(generated) };
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(out, null, 2) + '\n', 'utf8');
}

function writeJson(file, obj) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(obj, null, 2) + '\n', 'utf8');
}

function main() {
  // ---------- 1. 字符串 ----------
  const localizable = loadXcstrings(path.join(IOS_MEMOIR, 'Localizable.xcstrings'));
  const infoPlist = loadXcstrings(path.join(IOS_MEMOIR, 'InfoPlist.xcstrings'));
  const entries = extractEntries(localizable, 'Localizable')
    .concat(extractEntries(infoPlist, 'InfoPlist'));
  assertNoCollisions(entries);

  const ipStrings = infoPlist.strings || {};
  const appNameValues = {};
  for (const { ios } of LANGS) {
    const unit = ipStrings.CFBundleDisplayName
      && ipStrings.CFBundleDisplayName.localizations
      && ipStrings.CFBundleDisplayName.localizations[ios]
      && ipStrings.CFBundleDisplayName.localizations[ios].stringUnit;
    if (!unit || typeof unit.value !== 'string') {
      throw new Error(`InfoPlist CFBundleDisplayName 缺 ${ios}`);
    }
    appNameValues[ios] = unit.value; // 尺素 / memoir / 그리움 / Déjà Vu / Añoranza（R-LANG-06）
  }

  // entry：base + 七语言目录。base 兜底用 zh-Hans（与 iOS 回退到开发区域一致）
  for (const { ios, dir } of LANGS) {
    const generated = entries.map((e) => ({ name: e.name, value: e.values[ios] }));
    const file = path.join(ENTRY_RES, dir, 'element', 'string.json');
    // 七语言目录也走合并写：非 s_ 开头的手工资源（lang_name_* 等）不会被覆盖
    mergeWriteStringJson(file, generated, [{ name: 'EntryAbility_label', value: appNameValues[ios] }]);
  }
  // base：保留模板条目，生成条目填 zh-Hans 值
  mergeWriteStringJson(
    path.join(ENTRY_RES, 'base', 'element', 'string.json'),
    entries.map((e) => ({ name: e.name, value: e.values['zh-Hans'] })),
    [{ name: 'EntryAbility_label', value: appNameValues['zh-Hans'] }]
  );

  // AppScope：base + 七语言目录的 app_name（桌面图标下显示的 App 名）
  for (const { ios, dir } of LANGS) {
    writeJson(
      path.join(APPSCOPE_RES, dir, 'element', 'string.json'),
      { string: [{ name: 'app_name', value: appNameValues[ios] }] }
    );
  }
  // AppScope base：保留已有条目，更新 app_name
  const appScopeBase = path.join(APPSCOPE_RES, 'base', 'element', 'string.json');
  const appScopeExisting = readStringJson(appScopeBase);
  const appScopeKept = [];
  if (appScopeExisting && Array.isArray(appScopeExisting.string)) {
    for (const item of appScopeExisting.string) {
      if (item.name !== 'app_name') {
        appScopeKept.push({ name: item.name, value: item.value });
      }
    }
  }
  writeJson(appScopeBase, { string: appScopeKept.concat([{ name: 'app_name', value: appNameValues['zh-Hans'] }]) });

  // strings_index.json：资源名 → 简中原文 / iOS 注释（agent 按中文原文查资源名）
  const indexEntries = {};
  for (const e of entries) {
    const item = { zh: e.values['zh-Hans'], source: e.source };
    if (e.comment) {
      item.comment = e.comment;
    }
    indexEntries[e.name] = item;
  }
  writeJson(INDEX_FILE, {
    note: '由 scripts/convert_materials.js 生成，勿手改。按简中原文（zh 字段）检索资源名；带参数的句子整句查（R-LANG-07）。',
    fixed: {
      app_name: 'AppScope 桌面 App 名（R-LANG-06）',
      EntryAbility_label: 'entry 任务栈 / 最近任务显示名（跟 App 名）',
    },
    entries: indexEntries,
  });

  // ---------- 2. 图片 ----------
  let images = 0;
  for (const [src, dst] of IMAGE_MAP) {
    const from = path.join(IOS_MEMOIR, src);
    if (!fs.existsSync(from)) {
      throw new Error(`图片源缺失: ${src}`);
    }
    const to = path.join(ENTRY_RES, 'base', 'media', dst);
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.copyFileSync(from, to);
    images++;
  }

  // ---------- 3. 声音 ----------
  let sounds = 0;
  for (const [src, dst] of SOUND_FILES) {
    const from = path.join(IOS_MEMOIR, src);
    if (!fs.existsSync(from)) {
      throw new Error(`声音源缺失: ${src}`);
    }
    const to = path.join(ENTRY_RES, 'rawfile', 'sounds', dst);
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.copyFileSync(from, to);
    sounds++;
  }

  console.log(`字符串 ${entries.length} 条 × 7 语言；图片 ${images} 张 → base/media；`
    + `声音 ${sounds} 个 → rawfile/sounds；索引 → ${path.relative(ROOT, INDEX_FILE)}`);
}

if (require.main === module) {
  main();
}

module.exports = {
  LANGS,
  convertPlaceholders,
  resName,
  extractEntries,
  assertNoCollisions,
  IMAGE_MAP,
  SOUND_FILES,
  IOS_MEMOIR,
};
