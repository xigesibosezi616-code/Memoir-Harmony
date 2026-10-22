#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
导出全语言文案对照表。

    python3 Scripts/export_localization.py

产物：Memoir/Docs/LOCALIZATION_ALL_LANGUAGES.txt

**放在 Memoir/ 目录之外是刻意的** —— 那个目录是 Xcode 的「文件系统同步文件夹」，
里面的非 Swift 文件会被当成资源打进 App 包（Info.plist 当初就是这么撞上
「Multiple commands produce」的）。工具脚本不该进包。

分类不写死：问候语和语录直接从 `GreetingManager.swift` 里解析，
所以往那两个数组里加文案，这份表会自动跟上，不用改脚本。
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Memoir/Localizable.xcstrings"
INFOPLIST = ROOT / "Memoir/InfoPlist.xcstrings"
GREETINGS = ROOT / "Memoir/Services/GreetingManager.swift"
OUT = ROOT / "Memoir/Docs/LOCALIZATION_ALL_LANGUAGES.txt"

# 顺序即文档里的呈现顺序
LANGS = [
    ("zh-Hans", "简体中文"),
    ("zh-Hant", "繁體中文"),
    ("en", "English"),
    ("ja", "日本語"),
    ("fr", "Français"),
    ("es", "Español"),
]
CJK = re.compile(r"[一-鿿]")


def pad(label, width=12):
    """按**显示宽度**对齐：中日文字符占两格，Python 的 str.ljust 按字符数算会歪掉"""
    shown = sum(2 if ord(c) > 0x2E80 else 1 for c in label)
    return label + " " * max(1, width - shown)


def value(strings, key, lang):
    unit = (strings[key].get("localizations", {}).get(lang) or {}).get("stringUnit") or {}
    return unit.get("value", "")


def swift_array(source, name):
    """从 GreetingManager.swift 里抠出某个字符串数组的内容"""
    m = re.search(name + r"[^\[]*\[(.*?)\n    \]", source, re.S)
    return re.findall(r'"([^"]+)"', m.group(1)) if m else []


def main():
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog["strings"]
    src = GREETINGS.read_text(encoding="utf-8")

    greetings = []
    for name in ("morningGreetings", "morningLateGreetings", "afternoonGreetings",
                 "eveningGreetings", "nightGreetings"):
        greetings += swift_array(src, name)
    quotes = swift_array(src, "dailyQuotes")

    greet_set, quote_set = set(greetings), set(quotes)
    moods = sorted(k for k in strings if k.startswith("mood."))
    ui = sorted(k for k in strings
                if CJK.search(k) and k not in greet_set and k not in quote_set)

    lines = []
    add = lines.append
    add("尺素 Memoir · 全语言文案对照表")
    add("=" * 70)
    add(f"条目：{len(ui) + len(greetings) + len(quotes) + len(moods)} 条 × 6 语言")
    add("语言：简体中文 / 繁體中文 / English / 日本語 / Français / Español")
    add("")
    add("由 Scripts/export_localization.py 生成，改完文案重跑即可。")
    add("=" * 70)

    def block(title, keys, note=""):
        add("")
        add("█" * 70)
        add(f"■ {title}（{len(keys)} 条）")
        if note:
            add(f"  {note}")
        add("█" * 70)
        add("")
        for i, key in enumerate(keys, 1):
            add(f"[{i:03d}] " + "─" * 56)
            for code, label in LANGS:
                add(f"  {pad(label)}{value(strings, key, code) or key}")
            add("")

    add("")
    add("█" * 70)
    add("■ App 名称（各语言桌面显示名）")
    add("█" * 70)
    add("")
    info = json.loads(INFOPLIST.read_text(encoding="utf-8"))
    names = info["strings"]["CFBundleDisplayName"]["localizations"]
    for code, label in LANGS:
        add(f"  {pad(label)}{names[code]['stringUnit']['value']}")

    block("界面文案 UI", ui)
    block("时段问候语", sorted(greet_set),
          "首页顶部按时间显示。语气：安静、温和、不打扰")
    block("每日语录", sorted(quote_set),
          "每天固定一条。引号已按各语言习惯写入译文（中日「」/ 英 “” / 法 « » / 西 «»）")
    block("默认心情", moods,
          "key 为数据库存储值，不可更改；用户自建的心情不翻译")

    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"已生成 {OUT.relative_to(ROOT)}")
    print(f"  界面 {len(ui)} · 问候 {len(greet_set)} · 语录 {len(quote_set)} · 心情 {len(moods)}")


if __name__ == "__main__":
    main()
