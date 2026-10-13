# Memoir·尺素 鸿蒙线 · 施工图

> 给鸿蒙事业部（负责人 + coding agent）的完整复刻资料。
> iOS 端是参考实现：**行为与数据必须一致，界面可以按 HarmonyOS Design 重画，不要逐行翻译 Swift 代码。**
>
> **当前基线：2026-10-12**（iOS schema V8）。00–10 描述的是这一刻的「现状」；之后 iOS 的变化看 `CHANGELOG.md` 顶部。

---

## 从哪开始

| 你是 | 先读 | 然后 |
|---|---|---|
| **鸿蒙负责人** | `00_PRODUCT_OVERVIEW.md` → `09_OPEN_QUESTIONS.md` → **`10_BUILD_MANUAL.md`** | 按手册阶段 0 准备物料、认领阻塞项、排期 |
| **coding agent** | 鸿蒙仓库的 `CLAUDE.md`（模板 `templates/HARMONY_CLAUDE.md`）→ 手册里当前这一步的卡片 → 卡片「先读」列出的文档与 iOS 文件 | 做完按卡片「验收」自查，更新 `PROGRESS.md` |
| **产品 / 法务 / 后端** | `09_OPEN_QUESTIONS.md` | 认领 🔴 项，结论写回表里 |

---

## 文档地图

| # | 文档 | 内容 | 性质 |
|---|---|---|---|
| 00 | [PRODUCT_OVERVIEW](00_PRODUCT_OVERVIEW.md) | 产品定位、核心功能、风格、隐私承诺、商业模式 | 现状 |
| 01 | [TECH_STACK_MAPPING](01_TECH_STACK_MAPPING.md) | iOS 用 X → 鸿蒙候选 Y | 现状 |
| 02 | [BACKEND_API](02_BACKEND_API.md) | 后端接口契约（逐路由核对过） | **契约** |
| 03 | [USER_FLOWS](03_USER_FLOWS.md) | 端到端流程（首启、写、读、寄信收信、登录、会员、启动） | 现状 |
| 04 | [DESIGN_LANGUAGE](04_DESIGN_LANGUAGE.md) | 三套主题全部色值、字号、图标、动效、语调 | 现状 |
| 05 | [DATA_MODEL](05_DATA_MODEL.md) | 本地数据模型：字段、默认值、内容块 JSON、偏好键、建议建表 | **契约** |
| 06 | [RULES](06_RULES.md) | 现行跨端规则，**带编号**，验收引用 | **契约** |
| 09 | [OPEN_QUESTIONS](09_OPEN_QUESTIONS.md) | 阻塞与待决（Q1–Q18），谁来定 | 活文档 |
| 10 | [BUILD_MANUAL](10_BUILD_MANUAL.md) | **分步操作手册**：9 个阶段、约 50 张任务卡、提示词与进度表模板、截图清单 | 手册 |
| — | [modules/08_backup_package](modules/08_backup_package.md) | 备份包的决策与坑（两端唯一的数据通路） | 契约补充 |
| — | [templates/HARMONY_CLAUDE](templates/HARMONY_CLAUDE.md) | 鸿蒙仓库的 agent 协作约定模板 | 模板 |
| — | [CHANGELOG](CHANGELOG.md) | iOS 侧的**增量**（倒序） | 增量 |

本目录之外还要一起给的（详见手册 0.1）：

| 文件 | 为什么 |
|---|---|
| `Memoir/Docs/EXPORT_FORMAT.md` | 备份包格式权威 |
| `Memoir/Docs/MEMBERSHIP.md` | 免费与会员的边界、价格 |
| `Backend/shared/src/types.ts` 等 | 接口类型权威 |
| `Memoir/Localizable.xcstrings`、`InfoPlist.xcstrings` | 七种语言的全部译文（**不要机翻**） |
| `Memoir/Resources/`（Legal / Sounds / SplashCovers）与 `Assets.xcassets` 里的插画、布面、图标 | 素材 |
| iOS 源码只读副本 | 每张任务卡都指到具体的参考文件 |

---

## 冲突时以谁为准

**iOS 源码 > `06_RULES.md` > `00`–`05` > `CHANGELOG.md` 的旧条目。**

CHANGELOG 是历史记录，里面有不少已被撤销或取代的条目（书架封顶 9 格、果冻回弹、皮革付费、自动保存……），
**不要把 CHANGELOG 的旧条目当规格读**。基线之前的内容已全部吸收进 00–06。

发现文档之间、文档与 iOS 源码之间不一致 → 追加到 `09_OPEN_QUESTIONS.md`，不要自己挑一个。

---

## 保持同步

**iOS → 鸿蒙**：iOS 每做完一件跨端的事（数据契约 / 产品决策 / 行为规则 / 撤销功能），当次就往 `CHANGELOG.md` 顶部追加一条，
并就地修正 00–06 里被改错的描述（规则写在 iOS 仓库 `Memoir/CLAUDE.md`「鸿蒙同步」一节）。
**鸿蒙每周看一次 CHANGELOG 顶部**，🔴 条目排进计划。

**鸿蒙 → iOS**：鸿蒙这边做了跨端的决定，写进鸿蒙仓库 `docs/harmony-spec/CHANGELOG_FROM_HARMONY.md` 并通知 iOS 负责人。

---

## 不在这套文档里的（请鸿蒙端自己处理）

- ArkTS 语法、ArkUI 组件用法、各 Kit 的 API 细节 → 华为开发者文档（本套文档里标「需核实」的能力都以官方文档为准）
- 华为应用市场上架流程、华为账号与 IAP 的接入步骤 → HMS / AppGallery Connect 文档
