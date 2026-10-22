# iOS 源码快照（最新）

- 来源：iOS 仓库提交 `0fef42d`（2026-10-23，schema V10）
- 对应的更新包：`docs/harmony-updates/` 里的 U01–U08 —— U02、U03、U04、U06、U07、U08 **已交付**（按任务卡做）；U01 世界笔友、U05 邮筒还是**草稿**（只看不做）。
  快照里世界笔友、邮筒的代码是 iOS 现在的样子，等那两包交付再照着做
- 内容和 `reference/ios/` 同一个范围：App 源码 `Memoir/`（含 `Assets.xcassets`、`Resources/`、`Localizable.xcstrings`、`InfoPlist.xcstrings`）、
  `Scripts/` 里的漏翻检查与素材 / 音效生成脚本、`Memoir/Docs/` 下的 `EXPORT_FORMAT.md` 与 `MEMBERSHIP.md`
- **不含**：后端代码（接口变化写在各更新包里）、Xcode 工程文件、iOS 内部的上架与历史设计文档
- **只读参考，不参与编译**，不要在这里改代码
- **v1 的任务卡（X.Y）对照 `reference/ios/`**（v1 交付时的快照，不再替换）；**更新包的任务卡（Uxx-y）对照这一份**
- iOS 再有更新时，由 iOS 负责人整体替换这个目录，并改上面的「来源」
