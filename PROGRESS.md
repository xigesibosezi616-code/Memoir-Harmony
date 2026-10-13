# 进度

> 每完成一步，在这里勾掉并写下与 iOS 的偏差。⬜ 未开始 · 🟡 进行中 · ✅ 完成 · ⛔ 被阻塞（见 `docs/harmony-spec/09_OPEN_QUESTIONS.md`）

| 步骤 | 状态 | 负责人 | 完成日期 | 与 iOS 的偏差 / 备注 |
|---|---|---|---|---|
| 0.4 物料转换 | ✅ | Gavin（agent） | 2026-10-14 | 脚本用 Node.js（本机无 python3）。资源名 `s_`+SHA1 前 10 位；11 条无译文条目（`·`、`#%@` 等）按 iOS 回退行为填原文；`尺素备份包`（InfoPlist，iOS 侧无译文）同样填原文；AppScope `app_name` + entry `EntryAbility_label` 已接七语言（R-LANG-06）。额外拷了 0.1 未点名的 BookOpen_*/Texture_*（用户确认）。图片 35 张改小写下划线进 base/media；5 个 wav 进 rawfile/sounds。检查脚本跳过 hilog/console 行（开发者日志不算文案）。App 名 base 兜底用简中「尺素」（与 iOS 回退开发区域一致） |
| 1.1 主题系统 | ✅ | Gavin（agent） | 2026-10-14 | token 接口与 iOS 同名（`AppTheme` 15 色必填 + `colorMode`/`mailboxImage`/5 档 `FontInfo` + 行距/宽字距）；三套实现色值逐项对照 04 全表。`ThemeManager`：偏好 `selectedTheme`、旧 id 归一写回（R-THEME-01）、AppStorage `theme`/`themeId` 整体替换 + `themeManager` 实例下发（1.6 接 `@Provide` 后移除）；皮革应用级 `COLOR_MODE_DARK`（R-THEME-03）。字体 serif 占位（Q6）。调试页 `pages/ThemeDebug`（临时脚手架，标签用英文调试文案，6.2 删）：全 token 列表 + 三套即时切换 + 系统弹窗样例。单测 6 条过编译（`hvigor test`：旧 id 归一/实例映射/明暗/宽字距）；**执行**被环境挡住（CLI SDK 无 previewer 二进制，待 DevEco Studio 完整环境跑绿）。构建环境：hvigorw 因沙箱禁 symlink 不可用，改引擎直调（详见会话记录） |
| 1.2 多语言 | ✅ | Gavin（agent） | 2026-10-14 | `LanguageManager`（偏好 `appLanguage`，首启 R-LANG-02 解析立刻落盘；解析逻辑拆纯函数 `LocaleParsing`）；App 级首选语言 `i18n.System.setAppPreferredLanguage`（卡片候选已核实可用）+ AppStorage `appLanguage` 整体替换驱动重渲染，切换当场生效不重建导航栈（R-LANG-03）；日期格式化 `AppDateFormatters` 全函数接受 App 语言，pattern 与 iOS `Date+Formatting.swift` 逐条对齐（R-LANG-08）；无「跟随系统」。调试页 `pages/LanguageDebug`（临时脚手架，6.1 真实设置页上线后删）。单测 3 套 17 例（LocaleParsing/LanguageManager/AppDateFormatters）过编译；**执行**仍被环境挡住（CLI SDK 无 previewer 二进制，同 1.1，待完整环境跑绿）。语言自称条目 `lang_name_*` 七种齐（值取自 iOS `LanguageManager.swift` 自称，非机翻）；`check_localization.js` 新增 `AppDateFormatters.ets` 字面量豁免（zh 日期格式 pattern 非文案，与 iOS 固定 dateFormat 等价；资源齐全性检查不豁免）。顺手修掉 ThemeManager/LanguageManager 的 ArkTS「may throw」告警（try/catch + 类型化 Error 重抛），构建零告警 |
| 1.3 数据层 | ⬜ | | | |
| 1.4 媒体存储 | ⬜ | | | |
| 1.5 首启 | ⬜ | | | |
| 1.6 主框架 | ⬜ | | | |
| 2.1 写日记 v1 | ⬜ | | | |
| 2.2 记录页 | ⬜ | | | |
| 2.3 详情页 | ⬜ | | | |
| 2.4 编辑页 | ⬜ | | | |
| 2.5 图文格式 | ⬜ | | | |
| 2.6 照片 | ⬜ | | | |
| 2.7 录音 | ⬜ | | | |
| 2.8 墨迹会干 | ⬜ | | | |
| 2.9 相机 | ⬜ | | | |
| 2.10 此时此地 | ⬜ | | | |
| 3.1 书架 | ⬜ | | | |
| 3.2 拖书 | ⬜ | | | |
| 3.3 日记本主页 | ⬜ | | | |
| 3.4 封面编辑 | ⬜ | | | |
| 3.5 阅读器 | ⬜ | | | |
| 3.6 大屏 | ⬜ | | | |
| 4.1 网络层 | ⬜ | | | |
| 4.2 登录 | ⬜ | | | |
| 4.3 账户页 | ⬜ | | | |
| 4.4 华为账号 | ⛔ Q1 | | | |
| 5.1 信箱读信 | ⬜ | | | |
| 5.2 邮筒页 | ⬜ | | | |
| 5.3 寄信队列 | ⬜ | | | |
| 5.4 到达通知 | ⬜ | | | |
| 5.5 语言识别 | ⬜ | | | |
| 5.6 投信动画 | ⬜ | | | |
| 5.7 火漆信 | ⬜ | | | |
| 5.8 测试加速 | ⬜ | | | |
| 6.1 设置结构 | ⬜ | | | |
| 6.2 主题与图标 | ⬜ | | | |
| 6.3 统计 | ⬜ | | | |
| 6.4 导入 | ⬜ | | | |
| 6.5 导出 | ⬜ | | | |
| 6.6 云同步 | ⛔ Q3 | | | |
| 6.7 关于 | ⬜ | | | |
| 7.1 华为验证（后端） | ⛔ Q2 | | | |
| 7.2 会员 | ⬜ | | | |
| 7.3 三样新权益 | ⛔ Q11 | | | |
| 8 上架前 | ⬜ | | | |
