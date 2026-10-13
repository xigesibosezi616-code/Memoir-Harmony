#!/usr/bin/env python3
"""漏翻审计 —— 一条命令查出「哪句用户看得见的话还没翻」。

    python3 Scripts/check_localization.py

CLAUDE.md 的「多语言（硬性）」写着七种语言一个都不能少，但光靠人肉记不住 ——
设置页那批文案就是这么漏了大半年，直到用户把手机切成英文才发现。
这个脚本把「漏没漏」变成一条命令能回答的事。

查三类问题：
  🔴 缺 key   —— Swift 里有这句中文，`Localizable.xcstrings` 里根本没有
  🟠 缺语言   —— catalog 里有这个 key，但 LANGS 里的语言没齐（或还是 `state: new`）
  🟣 裸 return —— 从 `String` 属性/函数里 `return "中文"`，压根不走本地化

第三类是最阴的：`Text(String)` **不查本地化表**，Xcode 的提取器也不会把它收进
catalog —— 于是"漏翻了"这件事连痕迹都没有。设置页的「列表」「一屏多条，便于翻找」
就是这么在任何外语下都显示中文的。修法是显式
`NSLocalizedString("…", bundle: .appLanguage, comment: "…")`
（用 `.main` 会跟系统语言走，无视 App 内选的语言），参照 `MoodTag.localizedName`。

退出码：有问题返回 1，干净返回 0（方便以后挂进 CI 或 git hook）。
"""
import json
import os
import re
import sys

LANGS = {"zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "es"}
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "Memoir", "Localizable.xcstrings")
SOURCE_DIR = os.path.join(ROOT, "Memoir")

CJK = re.compile(r"[一-鿿]")

# 只看这些「会显示给用户」的构造，避免把注释、日志、字典 key 当成文案。
# 每条都是「取双引号里的内容」，已排除转义引号。
STR = r'"((?:[^"\\]|\\.)*)"'
PATTERNS = [
    re.compile(r"\bText\(\s*" + STR),                      # Text("…")
    re.compile(r"\bLabel\(\s*" + STR),                     # Label("…", systemImage:)
    re.compile(r"\bButton\(\s*" + STR),                    # Button("…")
    re.compile(r"\bTextField\(\s*" + STR),                 # TextField("…", text:)
    re.compile(r"\bNavigationLink\(\s*" + STR),            # NavigationLink("…")
    re.compile(r"\bNSLocalizedString\(\s*" + STR),         # NSLocalizedString("…")
    re.compile(r"\.navigationTitle\(\s*" + STR),
    re.compile(r"\.alert\(\s*" + STR),
    re.compile(r"\.confirmationDialog\(\s*" + STR),
    re.compile(r"\btitle:\s*" + STR),                      # settingsRow(title: "…")
    re.compile(r"\bplaceholder:\s*" + STR),
    # ThemePaper(name:subtitle:story:source:) —— 主题选择页那批纸史文案。
    # 它们是 `LocalizedStringKey` 字面量，最终都进 `Text(…)`，
    # 但写在结构体的初始化参数里，上面那些 `Text(` 开头的模式一条都盖不住。
    re.compile(r"\bname:\s*" + STR),
    re.compile(r"\bsubtitle:\s*" + STR),
    re.compile(r"\bstory:\s*" + STR),
    re.compile(r"\bsource:\s*" + STR),
]

# 这些文件里的中文是**数据**不是 UI 文案（示例日记正文、调试脚手架）
SKIP_FILES = {"DebugDraftHarness.swift", "MemoirApp.swift"}


def catalog_matcher(catalog_keys):
    """含插值的字面量要按 xcstrings 的格式化 key 去匹配。

    `Text("\\(n) 字")` 在 catalog 里是 `%lld 字`，`Text("来自\\(x)")` 是 `来自%@` ——
    直接拿原文查一定查不到，会报一堆假的"缺 key"。
    这里把 `\\(…)` 当通配符，去 catalog 的 key 里找能对上的那条。
    """
    def split_interpolations(text):
        """挖掉 `\\(…)`，返回中间的固定片段。

        必须自己数括号，不能用 `\\\\([^)]*\\)` 这种正则 ——
        `\\(formatBytes(exported.byteCount))` 里有**嵌套括号**，
        正则会在第一个 `)` 就断开，拼出来的模式永远匹配不上。
        """
        parts, buf, i, n = [], [], 0, len(text)
        while i < n:
            if text.startswith("\\(", i):
                parts.append("".join(buf))
                buf = []
                depth, i = 1, i + 2
                while i < n and depth:
                    if text[i] == "(":
                        depth += 1
                    elif text[i] == ")":
                        depth -= 1
                    i += 1
            else:
                buf.append(text[i])
                i += 1
        parts.append("".join(buf))
        return parts

    def find(text):
        if "\\(" not in text:
            return text if text in catalog_keys else None
        parts = split_interpolations(text)
        rx = re.compile("^" + ".+?".join(re.escape(p) for p in parts) + "$")
        for key in catalog_keys:
            if rx.match(key):
                return key
        return None
    return find


def swift_files():
    for base, dirs, files in os.walk(SOURCE_DIR):
        dirs[:] = [d for d in dirs if d not in {".build", "Preview Content"}]
        for name in files:
            if name.endswith(".swift") and name not in SKIP_FILES:
                yield os.path.join(base, name)


def strip_comments(src):
    """去掉 // 行注释和 /* */ 块注释 —— 注释里的中文不是文案。

    先把字符串字面量挖空占位，避免误伤 URL 里的 `//`。
    """
    out, i, n = [], 0, len(src)
    while i < n:
        ch = src[i]
        if ch == '"':
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == '"':
                    break
                j += 1
            out.append(src[i:j + 1])
            i = j + 1
        elif src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(ch)
            i += 1
    return "".join(out)


# `return "中文"` / `case .x: "中文"` —— 这些交给 Text(String) 渲染时不会本地化
BARE_RETURN = re.compile(r"\breturn\s+" + STR)
# 已经显式本地化的不算问题
LOCALIZED_CALL = re.compile(r"NSLocalizedString\s*\(")


# 这些属性/函数里的中文是给开发者看的，不显示给用户
DEBUG_MEMBERS = re.compile(r"\bvar\s+debugDescription\b|\bfunc\s+debug[A-Z]\w*")

# 返回 LocalizedStringKey 的成员 —— 里面 `return "中文"` 是**正确写法**，
# SwiftUI 渲染时按 \.locale 查表，切换语言能当场跟着变。
# 这些字面量要当作普通文案送去查 catalog，而不是当成"裸 return"来报。
LOCALIZED_KEY_MEMBERS = re.compile(
    r"\bvar\s+\w+\s*:\s*LocalizedStringKey\b|\bfunc\s+\w+\([^)]*\)\s*->\s*LocalizedStringKey\b"
)


def _member_ranges(src, pattern):
    """粗略框出某类成员的范围（从声明到下一个同级 `var`/`func`/`static`）。"""
    ranges = []
    for m in pattern.finditer(src):
        nxt = re.search(r"\n    (?:private )?(?:var|func|static)\s", src[m.end():])
        ranges.append((m.start(), m.end() + (nxt.start() if nxt else len(src))))
    return ranges


def debug_member_ranges(src):
    return _member_ranges(src, DEBUG_MEMBERS)


def localized_key_ranges(src):
    return _member_ranges(src, LOCALIZED_KEY_MEMBERS)


def collect_bare_returns():
    """→ [(文案, 文件, 行号)]，只报还没走 NSLocalizedString 的。"""
    found = []
    for path in swift_files():
        with open(path, encoding="utf-8") as f:
            clean = strip_comments(f.read())
        rel = os.path.relpath(path, ROOT)
        skip = debug_member_ranges(clean) + localized_key_ranges(clean)
        for m in BARE_RETURN.finditer(clean):
            if any(a <= m.start() < b for a, b in skip):
                continue
            text = m.group(1)
            if not CJK.search(text):
                continue
            # 整行若已含 NSLocalizedString，说明已经处理过
            line_start = clean.rfind("\n", 0, m.start()) + 1
            line_end = clean.find("\n", m.end())
            line_src = clean[line_start: line_end if line_end > 0 else len(clean)]
            if LOCALIZED_CALL.search(line_src):
                continue
            found.append((text, rel, clean[: m.start()].count("\n") + 1))
    return found


def collect_used():
    """→ {文案: [(文件, 行号), …]}"""
    used = {}
    for path in swift_files():
        with open(path, encoding="utf-8") as f:
            raw = f.read()
        clean = strip_comments(raw)
        rel = os.path.relpath(path, ROOT)
        for pattern in PATTERNS:
            for m in pattern.finditer(clean):
                text = m.group(1)
                if not CJK.search(text):
                    continue
                line = clean[: m.start()].count("\n") + 1
                used.setdefault(text, []).append((rel, line))

        # 返回 LocalizedStringKey 的成员里，`return "中文"` 同样是要翻译的文案
        for a, b in localized_key_ranges(clean):
            for m in BARE_RETURN.finditer(clean, a, b):
                text = m.group(1)
                if not CJK.search(text):
                    continue
                line = clean[: m.start()].count("\n") + 1
                used.setdefault(text, []).append((rel, line))
    return used


def main():
    with open(CATALOG, encoding="utf-8") as f:
        catalog = json.load(f)["strings"]

    used = collect_used()
    resolve = catalog_matcher(list(catalog))
    missing_key, missing_lang = [], []

    for text, places in sorted(used.items()):
        key = resolve(text)
        entry = catalog.get(key) if key else None
        if entry is None:
            missing_key.append((text, places))
            continue
        locs = entry.get("localizations", {})
        absent = LANGS - set(locs)
        untranslated = {
            lg for lg, v in locs.items()
            if lg in LANGS and v.get("stringUnit", {}).get("state") != "translated"
        }
        bad = absent | untranslated
        if bad:
            missing_lang.append((text, sorted(bad), places))

    if missing_key:
        print(f"\n🔴 catalog 里根本没有这 {len(missing_key)} 条（用户会看到硬编码的中文）：\n")
        for text, places in missing_key:
            where = places[0]
            more = f" 等 {len(places)} 处" if len(places) > 1 else ""
            print(f"  {text!r}\n      {where[0]}:{where[1]}{more}")

    if missing_lang:
        print(f"\n🟠 这 {len(missing_lang)} 条语言没齐：\n")
        for text, bad, places in missing_lang:
            where = places[0]
            print(f"  {text!r}\n      缺 {', '.join(bad)}  ←  {where[0]}:{where[1]}")

    bare = collect_bare_returns()
    if bare:
        by_file = {}
        for text, path, line in bare:
            by_file.setdefault(path, []).append((text, line))
        print(f"\n🟣 这 {len(bare)} 处从 String 里裸 return 中文，不会本地化"
              f"（分布在 {len(by_file)} 个文件）：\n")
        for path in sorted(by_file):
            items = by_file[path]
            sample = ", ".join(repr(t) for t, _ in items[:3])
            more = f" …共 {len(items)} 处" if len(items) > 3 else ""
            print(f"  {path}")
            print(f"      {sample}{more}")
        print("\n   修法：NSLocalizedString(\"…\", bundle: .appLanguage, comment: \"…\")"
              " —— 参照 MoodTag.localizedName")

    total = len(missing_key) + len(missing_lang) + len(bare)
    print()
    if total == 0:
        print(f"✅ 扫了 {len(used)} 条用户可见文案，{len(LANGS)} 种语言全齐，没有裸 return。")
        return 0
    print(f"共 {total} 条待处理（扫描了 {len(used)} 条 Text 文案）。")
    print("补完记得跑一遍本脚本确认归零。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
