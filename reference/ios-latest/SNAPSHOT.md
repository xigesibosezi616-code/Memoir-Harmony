# iOS 源码快照（最新）

- 来源：iOS 仓库提交 `2b52098`（2026-11-07，schema V12；含设置页图片素材（U10）、全 App 图标对照与设置各页详解（U19，按 U20 改成只有字和代码）、提醒写日记的代码（U18 草稿，多了「下一次提醒」那一行））
- 对应的更新包：`docs/harmony-updates/` 里的 U01–U20 —— U02、U03、U04、U06、U07、U08、U09、U10、U14、U15、U16、U19、**U20** **已交付**（按任务卡做；🔴 U15 是一级 bug，先做）；
  U01 世界笔友（含笔友手记）、U05 邮筒、U11 要删掉的东西、U12 搜日记、U13 新手一串、U17 图标素材换成矢量、U18 提醒写日记还是**草稿**（只看不做）。
  快照里这些草稿对应的代码是 iOS 现在的样子，等那几包交付再照着做
- 内容和 `reference/ios/` 同一个范围：App 源码 `Memoir/`（含 `Assets.xcassets`、`AppIcons/`（桌面图标，U09）、`Resources/`、`Localizable.xcstrings`、`InfoPlist.xcstrings`）、
  `Scripts/` 里的漏翻检查与素材 / 音效生成脚本（2026-10-28 起多了邮筒上换 m. 的 `make_mailbox_mark.py`）、`Memoir/Docs/` 下的 `EXPORT_FORMAT.md` 与 `MEMBERSHIP.md`
- **2026-11-07 起多一个 `HarmonyAssets/`**：iOS 侧专门给鸿蒙出好的素材和文档，从这里拷进工程，不要在这里改：
  - `settings_icons/`：设置首页的行首图标、关注我们、账户卡头像，四套主题，圆框 —— U10 的任务卡直接用，怎么放见里面的 `GUIDE.md`
  - `icons/`（U19，U20 更正）：`ICONS.md` 全 App 图标对照（每一处 iOS 图标 → 鸿蒙 `sys.symbol` 名、天气图标表）+ 火漆印的 `WaxSeal` ArkTS 组件（照代码画，不用 `wax_seal/` 的图）；`harmony_symbols/` 是预览图，只给人看、不进工程
  - `settings_pages/`（U19，U20 更正）：`SETTINGS_PAGES.md` 设置各页详解，第三节有四套主题的颜色 / 字号表和 ArkTS 骨架；`screenshots/` 是 iOS 截图，给人对照
  - 🔴 **两份 md 只有字和代码（U20 R-DOC-01）**：照字做，不打开图片；同目录的 `preview.html`、`screenshots/`、`harmony_symbols/` 是给人（陈总）看的
- **不含**：后端代码（接口变化写在各更新包里）、Xcode 工程文件、iOS 内部的上架与历史设计文档
- **只读参考，不参与编译**，不要在这里改代码
- **v1 的任务卡（X.Y）对照 `reference/ios/`**（v1 交付时的快照，不再替换）；**更新包的任务卡（Uxx-y）对照这一份**
- iOS 再有更新时，由 iOS 负责人整体替换这个目录，并改上面的「来源」
