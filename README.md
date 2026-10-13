# 尺素 · 鸿蒙版

尺素（Memoir）的 HarmonyOS 版本。iOS 版是参考实现：**行为与数据必须与 iOS 一致，界面可以按 HarmonyOS Design 重画。**

## 从哪开始

1. 负责人：读 [`docs/harmony-spec/README.md`](docs/harmony-spec/README.md) → [`09_OPEN_QUESTIONS.md`](docs/harmony-spec/09_OPEN_QUESTIONS.md) → [`10_BUILD_MANUAL.md`](docs/harmony-spec/10_BUILD_MANUAL.md)
2. coding agent：根目录的 [`CLAUDE.md`](CLAUDE.md) 会自动加载；每次按手册里的一张任务卡做，开场提示词见手册附录 A
3. 进度记在 [`PROGRESS.md`](PROGRESS.md)

## 目录

| 路径 | 是什么 | 谁维护 |
|---|---|---|
| `docs/harmony-spec/` | 施工图：产品、接口、数据模型、编号规则、分步手册 | iOS 侧更新，鸿蒙侧只读（发现问题记进 `09_OPEN_QUESTIONS.md`） |
| `docs/harmony-spec/CHANGELOG.md` | iOS 侧的增量，**每周看一次顶部** | iOS 侧 |
| `docs/harmony-spec/CHANGELOG_FROM_HARMONY.md` | 鸿蒙侧做的跨端决定 | 鸿蒙侧 |
| `reference/ios/` | iOS App 源码快照，**只读参考，不参与编译**（版本见 `reference/ios/SNAPSHOT.md`） | iOS 侧 |
| `CLAUDE.md` | agent 协作约定（`<尖括号>` 处请按实际填写） | 鸿蒙侧 |
| `PROGRESS.md` | 进度表 | 鸿蒙侧 |
| 鸿蒙工程本身（`entry/` 等） | 由 DevEco Studio 在仓库根目录新建 | 鸿蒙侧 |

## 约定

- 签名证书、密钥、`local.properties` **不进仓库**（`.gitignore` 已排除）
- 改 `docs/harmony-spec/` 或 `reference/ios/` 之前先和 iOS 负责人说一声，避免下次同步时被覆盖
