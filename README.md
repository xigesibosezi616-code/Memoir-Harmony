# 尺素 · 鸿蒙版

尺素（Memoir）的 HarmonyOS 版本。iOS 版是参考实现：**行为与数据必须与 iOS 一致，界面可以按 HarmonyOS Design 重画。**

## 从哪开始

1. 负责人：读 [`docs/harmony-spec/README.md`](docs/harmony-spec/README.md) → [`09_OPEN_QUESTIONS.md`](docs/harmony-spec/09_OPEN_QUESTIONS.md) → [`10_BUILD_MANUAL.md`](docs/harmony-spec/10_BUILD_MANUAL.md)
2. coding agent：每次做手册里的一张任务卡。在 agent 里输入一句 **读取 TASK.md，执行第 X.Y 步** 即可（[`TASK.md`](TASK.md) 里是完整的开场提示词，会让它先读 [`CLAUDE.md`](CLAUDE.md)）
3. 进度记在 [`PROGRESS.md`](PROGRESS.md)
4. iOS 在 v1 之后的变化写成**更新包**，在 [`docs/harmony-updates/`](docs/harmony-updates/HARMONY_UPDATES.md)。**每次 `git pull` 之后看一眼那里的索引**：
   状态「草稿」的只看不做（可以提前知道 v1 里哪些东西以后会删、会改），「已交付」的按包里的任务卡做（步骤号形如 U02-1）。
   v1 还没做完也能一边做：已经做完的那几步，单独排更新包的卡去改；还没做到的，做 v1 那张卡时 agent 会先查已交付的包、直接按新规则做（见 `TASK.md` 第 2 步）

## 目录

| 路径 | 是什么 | 谁维护 |
|---|---|---|
| `docs/harmony-spec/` | 施工图：产品、接口、数据模型、编号规则、分步手册 | iOS 侧更新，鸿蒙侧只读（发现问题记进 `09_OPEN_QUESTIONS.md`） |
| `docs/harmony-spec/CHANGELOG.md` | v1 交付前 iOS 侧的增量（v1 已冻结，之后的变化都在 `docs/harmony-updates/`） | iOS 侧 |
| `docs/harmony-spec/CHANGELOG_FROM_HARMONY.md` | 鸿蒙侧做的跨端决定 | 鸿蒙侧 |
| `docs/harmony-updates/` | **更新包**：v1 之后 iOS 的一切跨端变化（新功能、改现有功能、撤销、更正 v1），索引和规则见 `HARMONY_UPDATES.md` | iOS 侧整份替换，鸿蒙侧只读 |
| `reference/ios/` | v1 交付时的 iOS App 源码快照，**只读参考，不参与编译**；v1 任务卡对照它，不再替换（见 `reference/ios/SNAPSHOT.md`） | iOS 侧 |
| `reference/ios-latest/` | iOS 最新的源码快照，更新包的任务卡对照它（版本见 `reference/ios-latest/SNAPSHOT.md`） | iOS 侧整份替换 |
| `CLAUDE.md` | agent 协作约定（`<尖括号>` 处请按实际填写） | 鸿蒙侧 |
| `PROGRESS.md` | 进度表 | 鸿蒙侧 |
| 鸿蒙工程本身（`entry/` 等） | 由 DevEco Studio 在仓库根目录新建 | 鸿蒙侧 |

## 约定

- 签名证书、密钥、`local.properties` **不进仓库**（`.gitignore` 已排除）
- 改 `docs/harmony-spec/` 或 `reference/` 之前先和 iOS 负责人说一声，避免下次同步时被覆盖；`docs/harmony-updates/`、`reference/ios-latest/` 每次同步都会整份替换，有问题记进 `09_OPEN_QUESTIONS.md`，不要直接改
