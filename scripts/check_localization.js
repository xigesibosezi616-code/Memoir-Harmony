#!/usr/bin/env node
/**
 * 漏翻检查（10_BUILD_MANUAL.md 0.4）—— 一条命令查出「哪句用户看得见的话还没翻」。
 *
 *   node scripts/check_localization.js
 *
 * 查两类问题（退出码非 0）：
 *   🔴 缺资源 —— entry 代码（entry/src/main/ets）里出现的中文字符串字面量
 *               在 strings_index.json 里查不到对应资源；
 *   🟠 不齐全 —— 字符串资源七种语言不齐：
 *               entry 七个语言目录 string.json 的资源名集合不一致、
 *               base 缺条目、strings_index.json 与实际资源脱节、
 *               AppScope 的 app_name 没覆盖全部语言。
 *
 * 与 iOS 版（Scripts/check_localization.py，参照实现）的差异：
 *   - 剥掉注释再扫（本工程约定「代码注释用中文」，注释里的中文不是文案）；
 *   - 模板串里的 ${…} 当通配符去匹配索引（iOS 的 \(…) 同理），
 *     索引原文里的 %@ / %d / %1$s 等占位符也会被插值通配吸收；
 *   - hilog / console 调用里的中文是开发者日志，跳过不报。
 *   - ArkTS 里资源查找必须显式 $r()/getString，不存在 SwiftUI 的
 *     LocalizedStringKey 自动查表，「裸 return」一类问题在 1.2 多语言
 *     基础设施卡片里用统一封装解决，不在本脚本职责内。
 *
 * 退出码：有问题返回 1，干净返回 0（方便挂进 git hook / CI）。
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const ENTRY_RES = path.join(ROOT, 'entry', 'src', 'main', 'resources');
const APPSCOPE_RES = path.join(ROOT, 'AppScope', 'resources');
const ETS_DIR = path.join(ROOT, 'entry', 'src', 'main', 'ets');
const INDEX_FILE = path.join(ROOT, 'strings_index.json');

const LANG_DIRS = ['zh_Hans', 'zh_Hant', 'en', 'ja', 'ko', 'fr', 'es'];

/**
 * 中文字面量豁免文件（相对仓库根）：这些文件里的中文不是待翻译的界面文案，不走字符串资源：
 * - `services/AppDateFormatters.ets`：zh 日期格式片段（「2026年9月」「9月27日 星期日」），
 *   与 iOS `Date+Formatting.swift` 的固定 pattern（"yyyy年M月"、"EEEE"）等价；
 *   非 zh 分支用标准 Intl 按 CLDR 本地化，不硬编码任何语言文案。
 * - `data/Database.ets`：建表 SQL 里的列默认值（`from_character DEFAULT '青鸟'` 是
 *   用户数据的默认值，随数据走不随界面语言走）+ 抛给调用方的内部错误消息
 *   （只进 hilog / 日志，不上界面；1.5 起纳入豁免，1.3 遗留 9 条清零）。
 * - `models/Notebook.ets`：`DEFAULT_NOTEBOOK_NAMES`（生活/读书笔记/旅行/工作）。
 *   首启写库的**用户数据**，按名字就是身份的设计不能换语言重查
 *   （R-LANG-10；iOS `ContentView.swift` 同样硬编码）。
 * 这些文件的**资源齐全性检查不豁免**（七种语言目录一致性照查）。
 */
const EXEMPT_LITERAL_FILES = new Set([
  'entry/src/main/ets/services/AppDateFormatters.ets',
  'entry/src/main/ets/data/Database.ets',
  'entry/src/main/ets/models/Notebook.ets',
]);

const CJK = /[\u4e00-\u9fff]/;

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function readStringNames(file) {
  if (!fs.existsSync(file)) {
    return null;
  }
  try {
    const data = readJson(file);
    if (!data || !Array.isArray(data.string)) {
      return null;
    }
    return data.string.map((item) => item.name).filter((n) => typeof n === 'string');
  } catch (e) {
    return { parseError: String(e.message) };
  }
}

/** ets 源码词法扫描：剥注释，取字符串字面量 → [{text, line}] */
function extractStringLiterals(src) {
  const out = [];
  let i = 0;
  let line = 1;
  const n = src.length;
  while (i < n) {
    const ch = src[i];
    if (ch === '\n') {
      line++;
      i++;
    } else if (ch === '/' && src[i + 1] === '/') {
      while (i < n && src[i] !== '\n') {
        i++;
      }
    } else if (ch === '/' && src[i + 1] === '*') {
      i += 2;
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) {
        if (src[i] === '\n') {
          line++;
        }
        i++;
      }
      i += 2;
    } else if (ch === "'" || ch === '"') {
      const startLine = line;
      const buf = [];
      i++;
      while (i < n && src[i] !== ch) {
        if (src[i] === '\\') {
          buf.push(unescape(src[i], src[i + 1]));
          i += 2;
        } else {
          if (src[i] === '\n') {
            line++;
          }
          buf.push(src[i]);
          i++;
        }
      }
      i++;
      out.push({ text: buf.join(''), line: startLine });
    } else if (ch === '`') {
      const startLine = line;
      const buf = [];
      i++;
      let depth = 0;
      while (i < n) {
        const c = src[i];
        if (c === '\\' && depth === 0) {
          buf.push(unescape(src[i], src[i + 1]));
          i += 2;
          continue;
        }
        if (c === '$' && src[i + 1] === '{' && depth === 0) {
          buf.push('${');
          depth = 1;
          i += 2;
          continue;
        }
        if (depth > 0) {
          if (c === '{') {
            depth++;
          } else if (c === '}') {
            depth--;
          }
          buf.push(c);
          i++;
          continue;
        }
        if (c === '`') {
          i++;
          break;
        }
        if (c === '\n') {
          line++;
        }
        buf.push(c);
        i++;
      }
      out.push({ text: buf.join(''), line: startLine });
    } else {
      i++;
    }
  }
  return out;
}

/** 常见转义还原（够用即可：\n \t \\ \' \" \`，其余按原样去斜线） */
function unescape(backslash, next) {
  if (next === 'n') {
    return '\n';
  }
  if (next === 't') {
    return '\t';
  }
  return typeof next === 'string' ? next : '';
}

/** 把字面量里的 ${…} 挖掉，返回中间的固定片段（自己数花括号，嵌套表达式不会被截断） */
function splitInterpolations(text) {
  const parts = [];
  let buf = '';
  let i = 0;
  const n = text.length;
  while (i < n) {
    if (text.startsWith('${', i)) {
      parts.push(buf);
      buf = '';
      let depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (text[i] === '{') {
          depth++;
        } else if (text[i] === '}') {
          depth--;
        }
        i++;
      }
    } else {
      buf += text[i];
      i++;
    }
  }
  parts.push(buf);
  return parts;
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** 含 ${…} 的字面量 → 能匹配索引原文的正则（插值当通配符，. 不跨换行无妨——索引原文无换行内插值） */
function literalPattern(text) {
  const parts = splitInterpolations(text);
  return new RegExp('^' + parts.map(escapeRegExp).join('.+?') + '$', 's');
}

function main() {
  const problems = [];

  // ---------- 资源齐全性 ----------
  const langNameSets = {};
  for (const dir of LANG_DIRS) {
    const names = readStringNames(path.join(ENTRY_RES, dir, 'element', 'string.json'));
    langNameSets[dir] = names;
    if (names === null) {
      problems.push(`🟠 entry/${dir}/element/string.json 不存在或不是合法的 string.json`);
    } else if (!Array.isArray(names)) {
      problems.push(`🟠 entry/${dir}/element/string.json 解析失败: ${names.parseError}`);
    }
  }
  const validDirs = LANG_DIRS.filter((d) => Array.isArray(langNameSets[d]));
  if (validDirs.length > 1) {
    const base = new Set(langNameSets[validDirs[0]]);
    for (const dir of validDirs.slice(1)) {
      const other = new Set(langNameSets[dir]);
      for (const name of base) {
        if (!other.has(name)) {
          problems.push(`🟠 资源 ${name} 在 entry/${validDirs[0]} 有、entry/${dir} 没有`);
        }
      }
      for (const name of other) {
        if (!base.has(name)) {
          problems.push(`🟠 资源 ${name} 在 entry/${dir} 有、entry/${validDirs[0]} 没有`);
        }
      }
    }
  }
  const baseNames = readStringNames(path.join(ENTRY_RES, 'base', 'element', 'string.json'));
  if (!Array.isArray(baseNames)) {
    problems.push('🟠 entry/base/element/string.json 不存在或解析失败');
  } else if (validDirs.length > 0) {
    const baseSet = new Set(baseNames);
    for (const name of new Set(langNameSets[validDirs[0]])) {
      if (!baseSet.has(name)) {
        problems.push(`🟠 资源 ${name} 不在 entry/base（base 是兜底，必须全量）`);
      }
    }
  }

  // AppScope 的 app_name 必须覆盖 base + 七语言
  for (const dir of ['base'].concat(LANG_DIRS)) {
    const names = readStringNames(path.join(APPSCOPE_RES, dir, 'element', 'string.json'));
    if (!Array.isArray(names) || !names.includes('app_name')) {
      problems.push(`🟠 AppScope/${dir} 缺 app_name`);
    }
  }

  // strings_index.json 与实际资源一致
  if (!fs.existsSync(INDEX_FILE)) {
    problems.push(`🔴 ${path.relative(ROOT, INDEX_FILE)} 不存在（先跑 scripts/convert_materials.js）`);
  } else {
    try {
      const index = readJson(INDEX_FILE);
      const indexNames = new Set(Object.keys(index.entries || {}));
      if (Array.isArray(baseNames)) {
        for (const name of baseNames) {
          if (name.startsWith('s_') && !indexNames.has(name)) {
            problems.push(`🟠 资源 ${name} 在 base 里但 strings_index.json 没有`);
          }
        }
        for (const name of indexNames) {
          if (!baseNames.includes(name)) {
            problems.push(`🟠 索引里的 ${name} 不在 entry/base 资源里`);
          }
        }
      }
    } catch (e) {
      problems.push(`🔴 strings_index.json 解析失败: ${e.message}`);
    }
  }

  // ---------- 代码里的中文字面量 ----------
  const missingKey = [];
  if (fs.existsSync(INDEX_FILE)) {
    let index;
    try {
      index = readJson(INDEX_FILE);
    } catch (e) {
      index = null;
    }
    if (index && index.entries) {
      const zhTexts = Object.values(index.entries).map((e) => e.zh);
      const zhSet = new Set(zhTexts);
      const zhPatterns = zhTexts.map((t) => ({ zh: t, rx: literalPattern(t) }));

      const etsFiles = [];
      (function walk(dir) {
        for (const name of fs.readdirSync(dir)) {
          const p = path.join(dir, name);
          const stat = fs.statSync(p);
          if (stat.isDirectory()) {
            walk(p);
          } else if (name.endsWith('.ets')) {
            etsFiles.push(p);
          }
        }
      })(ETS_DIR);

      for (const file of etsFiles) {
        const relPath = path.relative(ROOT, file);
        if (EXEMPT_LITERAL_FILES.has(relPath)) {
          continue; // 格式 pattern 文件：中文是格式不是文案（见 EXEMPT_LITERAL_FILES 注释）
        }
        const src = fs.readFileSync(file, 'utf8');
        const lines = src.split('\n');
        for (const lit of extractStringLiterals(src)) {
          if (!CJK.test(lit.text)) {
            continue;
          }
          // hilog / console 行的中文是开发者日志，不显示给用户
          const lineText = lines[lit.line - 1] || '';
          if (/\bhilog\s*\.|\bconsole\./.test(lineText)) {
            continue;
          }
          const exact = zhSet.has(lit.text);
          const matched = exact || zhPatterns.some((p) => p.rx.test(lit.text));
          if (!matched) {
            missingKey.push({ text: lit.text, file: path.relative(ROOT, file), line: lit.line });
          }
        }
      }
    }
  }

  if (missingKey.length > 0) {
    console.log(`\n🔴 这 ${missingKey.length} 句中文不在字符串资源里（用户会看到硬编码的中文）：\n`);
    for (const item of missingKey) {
      console.log(`  ${JSON.stringify(item.text)}\n      ${item.file}:${item.line}`);
    }
  }

  if (problems.length > 0) {
    console.log(`\n🟠 资源齐全性问题 ${problems.length} 条：\n`);
    for (const p of problems) {
      console.log(`  ${p}`);
    }
  }

  const total = problems.length + missingKey.length;
  console.log();
  if (total === 0) {
    console.log('✅ 资源七种语言齐全，代码里没有脱离资源的中文字面量。');
    return 0;
  }
  console.log(`共 ${total} 条待处理。补完记得再跑一遍本脚本确认归零。`);
  return 1;
}

if (require.main === module) {
  process.exit(main());
}

module.exports = { extractStringLiterals, splitInterpolations, literalPattern };
