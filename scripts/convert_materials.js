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
const IOS_MEMOIR_LATEST = path.join(ROOT, 'reference', 'ios-latest', 'Memoir');
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
 * 手工维护的麦克风权限说明（module.json5 requestPermissions 的 reason，
 * R-LANG-05）。不走 xcstrings：ios-latest 的 InfoPlist 文案带「可同步到你的
 * iCloud」（iOS 同步功能的措辞），鸿蒙没有 iCloud，权限弹窗不能照搬；
 * 七语言沿用移交时那份不提 iCloud 的旧译文（韩语句尾全角句号笔误已修）。
 */
const MICROPHONE_PERMISSION_REASON = {
  'zh-Hans': '尺素需要使用麦克风为日记录制语音片段。录音内容仅保存在你的设备上。',
  'zh-Hant': '尺素需要使用麥克風為日記錄製語音片段。錄音內容僅保存在你的裝置上。',
  'en': 'memoir needs the microphone to record voice notes for your journal. Recordings are kept only on your device.',
  'ja': '尺素は日記の音声メモの録音にマイクを使用します。録音内容はお使いのデバイスにのみ保存されます。',
  'ko': '그리움은 일기 음성 메모를 녹음하기 위해 마이크를 사용합니다. 녹음 내용은 기기에만 저장됩니다.',
  'fr': 'Déjà Vu a besoin du micro pour enregistrer des notes vocales dans votre journal. Les enregistrements restent uniquement sur votre appareil.',
  'es': 'Añoranza necesita el micrófono para grabar notas de voz en tu diario. Las grabaciones se guardan solo en tu dispositivo.',
};

/**
 * 手工补写的 UI 文案（历代卡片补的：iOS 物料里没有的鸿蒙侧文案，如错误
 * Toast、纸张选项）。资源名沿用 s_ + SHA1(简中原文) 前 10 位的老约定，
 * 代码已引用、不再改名；走 keepOriginals 强制写入，重跑不丢。
 */
const HAND_STRINGS = {
  s_e4c4ff3b29: { // 无法播放录音
    'zh-Hans': '无法播放录音', 'zh-Hant': '無法播放錄音',
    'en': 'Could not play the recording', 'ja': '録音を再生できません',
    'ko': '녹음을 재생할 수 없어요',
    'fr': 'Impossible de lire l\'enregistrement',
    'es': 'No se pudo reproducir la grabación' },
  s_7c3f9e2a: { // 放在
    'zh-Hans': '放在', 'zh-Hant': '放在', 'en': 'Place at', 'ja': '配置',
    'ko': '배치', 'fr': 'Placer à', 'es': 'Colocar en' },
  s_2e8d4f6b: { // 左边
    'zh-Hans': '左边', 'zh-Hant': '左邊', 'en': 'Left', 'ja': '左',
    'ko': '왼쪽', 'fr': 'Gauche', 'es': 'Izquierda' },
  s_9b5c1d3f: { // 右边
    'zh-Hans': '右边', 'zh-Hant': '右邊', 'en': 'Right', 'ja': '右',
    'ko': '오른쪽', 'fr': 'Droite', 'es': 'Derecha' },
  s_094be81a60: { // 无法开始录音
    'zh-Hans': '无法开始录音', 'zh-Hant': '無法開始錄音',
    'en': 'Could not start recording', 'ja': '録音を開始できません',
    'ko': '녹음을 시작할 수 없어요',
    'fr': 'Impossible de démarrer l\'enregistrement',
    'es': 'No se pudo iniciar la grabación' },
  s_7126a0f54e: { // 无法访问麦克风
    'zh-Hans': '无法访问麦克风', 'zh-Hant': '無法存取麥克風',
    'en': 'Cannot access the microphone', 'ja': 'マイクにアクセスできません',
    'ko': '마이크에 접근할 수 없어요',
    'fr': 'Impossible d\'accéder au micro',
    'es': 'No se puede acceder al micrófono' },
  s_36205e6628: { // 位置服务暂时不可用
    'zh-Hans': '位置服务暂时不可用', 'zh-Hant': '位置服務暫時不可用',
    'en': 'Location service is temporarily unavailable',
    'ja': '位置情報サービスは一時的に利用できません',
    'ko': '위치 서비스를 일시적으로 사용할 수 없어요',
    'fr': 'Service de localisation temporairement indisponible',
    'es': 'Servicio de ubicación temporalmente no disponible' },
  // ---- 4.2 手机号登录（iOS xcstrings 缺的短 UI 词，LoginView 疏漏的 Text(String) 在鸿蒙侧补齐）----
  s_f2d81a9c46: { // 手机号登录
    'zh-Hans': '手机号登录', 'zh-Hant': '手機號登入',
    'en': 'Phone sign-in', 'ja': '電話番号でログイン',
    'ko': '전화번호 로그인',
    'fr': 'Connexion par téléphone',
    'es': 'Iniciar sesión con teléfono' },
  s_5c3e9b7a12: { // 输入验证码
    'zh-Hans': '输入验证码', 'zh-Hant': '輸入驗證碼',
    'en': 'Enter the code', 'ja': '確認コードを入力',
    'ko': '인증번호 입력', 'fr': 'Saisir le code', 'es': 'Introducir el código' },
  s_8d4a2f6e90: { // 登录成功
    'zh-Hans': '登录成功', 'zh-Hant': '登入成功',
    'en': 'Signed in', 'ja': 'ログインしました',
    'ko': '로그인했어요', 'fr': 'Connecté', 'es': 'Sesión iniciada' },
  s_a9b3c1d5e7: { // 登录失败，请稍后再试
    'zh-Hans': '登录失败，请稍后再试', 'zh-Hant': '登入失敗，請稍後再試',
    'en': 'Could not sign in. Please try again later',
    'ja': 'ログインできませんでした。しばらくしてからもう一度お試しください',
    'ko': '로그인에 실패했어요. 잠시 후 다시 시도해 주세요',
    'fr': 'Impossible de se connecter. Veuillez réessayer plus tard',
    'es': 'No se pudo iniciar sesión. Inténtalo de nuevo más tarde' },
  s_e6f8a0b2c4: { // 验证码发送失败，请稍后再试
    'zh-Hans': '验证码发送失败，请稍后再试', 'zh-Hant': '驗證碼發送失敗，請稍後再試',
    'en': 'Could not send the code. Please try again later',
    'ja': '確認コードを送信できませんでした。しばらくしてからもう一度お試しください',
    'ko': '인증번호를 보내지 못했어요. 잠시 후 다시 시도해 주세요',
    'fr': 'Impossible d\'envoyer le code. Veuillez réessayer plus tard',
    'es': 'No se pudo enviar el código. Inténtalo de nuevo más tarde' },
  s_0b7e2d4a9c: { // 已登录
    'zh-Hans': '已登录', 'zh-Hant': '已登入',
    'en': 'Signed in', 'ja': 'ログイン済み',
    'ko': '로그인됨', 'fr': 'Connecté', 'es': 'Sesión iniciada' },
};

/** 把 LANGS 之外的固定条目（keepOriginals）按语言拼出来；appName 来自 xcstrings */
function fixedEntriesFor(iosLang, appName) {
  const fixed = [
    { name: 'EntryAbility_label', value: appName },
    { name: 'microphone_permission_reason', value: MICROPHONE_PERMISSION_REASON[iosLang] },
  ];
  for (const [name, values] of Object.entries(HAND_STRINGS)) {
    fixed.push({ name, value: values[iosLang] });
  }
  return fixed;
}

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
 * 合并新旧两份 xcstrings（TASK.md 更新包规则：已交付更新包的文案以
 * `reference/ios-latest` 为准；但 latest 随未落地更新包删掉的键——如 U03
 * 心情系统换掉的 `mood.*`——鸿蒙对应卡片还没做、代码仍在引用，不能跟着丢）。
 * 规则：两份都有的键取 latest（译文修正在 latest）；只有旧份有的键保留。
 */
function mergeXcstrings(oldFile, latestFile) {
  const oldStrings = loadXcstrings(oldFile).strings || {};
  const latestStrings = loadXcstrings(latestFile).strings || {};
  return { strings: Object.assign({}, oldStrings, latestStrings) };
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
  // ---------- 1. 字符串（ios + ios-latest 合并，见 mergeXcstrings 注释） ----------
  const localizable = mergeXcstrings(
    path.join(IOS_MEMOIR, 'Localizable.xcstrings'),
    path.join(IOS_MEMOIR_LATEST, 'Localizable.xcstrings')
  );
  const infoPlist = mergeXcstrings(
    path.join(IOS_MEMOIR, 'InfoPlist.xcstrings'),
    path.join(IOS_MEMOIR_LATEST, 'InfoPlist.xcstrings')
  );
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
    mergeWriteStringJson(file, generated, fixedEntriesFor(ios, appNameValues[ios]));
  }
  // base：保留模板条目，生成条目填 zh-Hans 值
  mergeWriteStringJson(
    path.join(ENTRY_RES, 'base', 'element', 'string.json'),
    entries.map((e) => ({ name: e.name, value: e.values['zh-Hans'] })),
    fixedEntriesFor('zh-Hans', appNameValues['zh-Hans'])
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
  // 手补文案也进索引（check_localization 要求 base 里的 s_ 资源都能按中文查到）
  for (const [name, values] of Object.entries(HAND_STRINGS)) {
    indexEntries[name] = { zh: values['zh-Hans'], source: 'Hand' };
  }
  writeJson(INDEX_FILE, {
    note: '由 scripts/convert_materials.js 生成，勿手改。按简中原文（zh 字段）检索资源名；带参数的句子整句查（R-LANG-07）。',
    fixed: {
      app_name: 'AppScope 桌面 App 名（R-LANG-06）',
      EntryAbility_label: 'entry 任务栈 / 最近任务显示名（跟 App 名）',
      microphone_permission_reason: 'module.json5 麦克风权限说明（手工维护；iOS 那份带 iCloud 措辞，不能照搬）',
      hand_strings: 'HAND_STRINGS：历代卡片手补的鸿蒙侧文案（错误 Toast、纸张选项等，iOS 物料里没有），随脚本强制写入不丢',
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
