# 执行一张任务卡

> 给 coding agent 读的。用户只需要输入一句：**读取 TASK.md，执行第 X.Y 步**（X.Y 是步骤号，如 0.4、1.1）。

你是「尺素」鸿蒙版的 coding agent。按下面的顺序做，**每一步都不要跳**：

1. **读约定**：完整读根目录 `CLAUDE.md`，全程遵守。
2. **读任务卡**：打开 `docs/harmony-spec/10_BUILD_MANUAL.md`，找到标题以「### X.Y」开头的那一节（阶段 0 的 0.4 也是这样的一节），完整读完。卡片里的「目标 / 先读 / 要做 / 不要 / 验收」就是这次的全部范围。
3. **读资料**：读卡片「先读」里列出的文档和 iOS 文件。
   - 文档都在 `docs/harmony-spec/`
   - 卡片里写的 iOS 路径（如 `Services/LetterOutbox.swift`、`Views/...`）在本仓库的 **`reference/ios/Memoir/`** 下；`Scripts/` 在 `reference/ios/Scripts/`
   - 七种语言的译文在 `reference/ios/Memoir/Localizable.xcstrings`、`reference/ios/Memoir/InfoPlist.xcstrings`
   - iOS 代码**只读、只参考**，不要逐行翻译，**不要改 `reference/` 下的任何文件**
4. **先复述再动手**：用几行话告诉用户这一步要做什么、明确不做什么、怎么验收；有拿不准的先问，得到确认再写代码。
5. **只做卡片「要做」里的事**；发现必须扩大范围才能完成，先停下来说明。
6. **规则以 `docs/harmony-spec/06_RULES.md` 为准**。文档和 iOS 源码不一致时以 iOS 源码为准，并把不一致追加到 `docs/harmony-spec/09_OPEN_QUESTIONS.md` 的表尾（编号接着往下排）。
7. **用户可见文字一律走字符串资源**，七种语言取自 iOS 的 xcstrings，不要机翻。
8. 需要写脚本时，先确认这台电脑上实际能跑哪种语言（`python3` / `node` 等），再选。
9. **每完成一处有意义的改动就编译一次**；纯逻辑写单元测试并跑通。
10. **做完汇报**：对照卡片「验收」逐条说结果（✅ 通过 / ❌ 没过 / 🟡 需要真机或产品确认），然后在 `PROGRESS.md` 更新这一步的状态，写下与 iOS 的偏差。
11. **不要自己 `git push`**。提交和推送由用户确认后再做。
