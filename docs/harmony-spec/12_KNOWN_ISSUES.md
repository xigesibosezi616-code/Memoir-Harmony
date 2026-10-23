# 12 · 问题清单（阶段 1~3.5 收口审查）

> 建档：2026-10-23。用户指令：① 3.5 中一直没能优化好的体验点记录归档、后面修复；
> ② git 推送前全面体检；③ 阶段 1~3.5 所有问题统一收集成表、后续统一优化。
>
> 与 09（待决事项/产品后端阻塞）、11（未建成功能）分工：**本表只收「已交付功能
> 的质量问题、体验差距、验收欠账」**。三表互补，编号互不通用。
>
> 状态：🔴 上架阻塞 · 🟠 体验不达标（多轮调教未过产品关，专项修复）·
> 🟡 与 iOS 偏差待产品定 · ⚪ 验收欠账（代码绿、正式验收未走完）· 🔵 工程遗留

## 一、推送前体检结论（2026-10-23）

- **单测**：489 例全绿（0 失败，`hvigor test` 真执行）
- **构建**：`devecocli build` 零 ERROR
- **本地化**：`check_localization.js` 过绿（七语言齐全、无脱离资源的中文字面量）
- **代码卫生**：无 TODO/FIXME 遗留（仅 2 处计划内钩子：CoverEditorView 7.2 paywall、
  BookContentsView 3.5 已接通）；无 console.log 遗留
- **git**：3.5 全部代码 + 本表为未提交内容（untracked / modified），提交推送由用户执行

## 二、问题总表

| # | 级别 | 阶段 | 问题 | 现状 / 根因 | 修复方向 | 关联 |
|---|------|------|------|------------|---------|------|
| 1 | 🔵 | 横切 | **包名是占位符** `com.example.temproject`（AppScope/app.json5） | **已解决（2026-10-23）**：包名切到正式 **`com.sinaratech.memoir.hmos`**（AGC 实测 `harmony` 是保留字符不能做独立段，Q18 旧候选 `com.sinaratech.memoir.harmony` 不合规作废）——AGC 新建应用（app_id 6917619854007528919）+ 新调试 Profile（`Memoir 尺素Debug.p7b`，证书 = AGC「Memoir」调试证书 4D:C9:10:7B…，双测试机 UDID 齐全）+ 新 agconnect-services.json（entry/）+ app.json5/build-profile 全局替换；build 零 ERROR + X6 装机启动 Smoke PASS。**剩余（阶段 8 上架前）**：发布证书/发布 Profile、AGC 正式「SHA256 公钥指纹」复核（账号 Kit 用）、上架审核材料 | Q18 |
| 2 | 🔴 | 1.5/8 | **隐私协议 / 用户协议是 iOS 逐字拷贝占位**（rawfile 两份 md） | 写的是 Apple 登录/iCloud/Apple 天气/Apple 支付，与鸿蒙事实不符；法务改前不可上架 | 法务出鸿蒙版；**须加彩云天气第三方清单**（2.10 坐标发彩云） | Q12 · Q8 |
| 3 | 🔴 | 横切 | **调试脚手架随包发布**：ThemeDebug / LanguageDebug / LocationDebug 注册在 main_pages.json；HomeView 调试区 Seed15/Clear15 造数按钮 + **2 条硬编码中文**（HomeView.ets:916-917「测试日记 x月x日」「自动验证用测试日记…」，check_localization 报红） | 计划内脚手架（6.x 删），但当前配置下会进发布包；Seed15 造数文案未走字符串资源 | 发布前从 main_pages.json / 路由入口移除（或 build-profile 分离 debug/release 页面）；Seed15/Clear15 随 6.x 一并删（删后 check_localization 自然归零，不单独补七语） | 1.1/1.2/2.10/3.6 |
| 4 | 🟠 | 3.5 | **翻书手感多轮调教未达产品关**（专项跟踪，详见 §三） | 角卷两轮被否 → 2026-10-23 统一 Edge 整页卷曲 + foldFromDrag + 持久节点性能修复，**待用户真机复测**；Edge 材质标定精度、松手参数对照等遗留 | 见 §三清单 | Q36 |
| 5 | 🟠 | 3.2 | **拖书手感四项**：① 32° 转身露书脊透视不对 ② 侧转一瞬红线 ③ 动画生硬卡顿 ④ 落格/让位与 iOS 差距大 | 逻辑与 398 单测绿，手感多轮未过；初步假设见 Q32（eyeDistance 口径/双面栅格化拼缝/setInterval 状态驱动/smooth 曲线形状） | 专项修复 + 录屏过产品验收，**过验收前 3.2 不结案** | Q32 |
| 6 | 🟠 | 2.5 | **荧光笔整块色底**，画不出 iOS「只压文字中下部的圆头条」 | RichEditor `textBackgroundStyle` 能力所限；圆头自绘需绕排 paint 桥（已下线） | 整块色底观感可接受先用；圆头条候选 = `Run.getPositions` 字形级自绘（依赖 11 #7 恢复条件） | Q23 · 11 #7 |
| 7 | 🟡 | 2.6 | **正文小图加载不放大**，iOS `preparingThumbnail` 会把小图放大到 600（更糊） | 鸿蒙省内存更清晰，但与 iOS 行为不一致；2.6 真机对比后定——**尚未正式定** | 与 iOS 并排对比观感后拍板；要一致就改 `decodeFit` 缩放策略 | Q19 |
| 8 | 🟡 | 2.8 | **墨迹三处小偏差**：补记段标不做（无段前距）/ scissors·strikethrough 符号缺失（痕迹行纯文字）/ sys.symbol 离线不可枚举 | ArkUI 段落模型拿不到段前距；符号不在系统符号集 | 段标：产品拍板不做（已定）；符号：等系统符号集扩充 | Q26 |
| 9 | 🟡 | 2.1 | **心情点已选不取消**（iOS 行为）；产品若想「再点取消」需 iOS 同步改 | 按 iOS 源码实现（冲突裁决序 iOS > 文档） | 产品定；要改两端一起改 | Q22 |
| 10 | 🟡 | 3.3 | **本子主页大图复用 600px 全局缓存**，iOS 用独立 300px | 清晰度更高、内存略大；观感差异微小 | 真机若见内存压力/锯齿，给 BookHeroView 建独立 300px 入口 | Q34 |
| 11 | 🟡 | 1.1 | **Georgia 字体授权未定**，当前 Noto Serif（西文）+ HarmonyOS Sans SC（中文）占位 | 商业字体打包需授权 | 产品定：买授权 / 换 OFL 衬线 / 用系统衬线；字体集中在主题 token，换只改一处 | Q6 |
| 12 | 🟡 | 2.2 | **记录页行卡片样式留待重新设计**：近透明小卡片（glassBackground+圆角16）2026-10-16 试装真机显示异常，回退官方线式 | 显示异常根因未查（当时优先保交付） | 后续重新设计卡片样式时先查 glassBackground 异常根因 | PROGRESS 2.2 |
| 13 | ⚪ | 1.3 | **DB 升级路径未用真实旧库验证**：planUpgrade 纯逻辑单测覆盖（fresh/upgrade/current/future 四态），「拿上一版真实库跑升级」未验 | 本 SDK StoreConfig 无 onUpgrade，走 PRAGMA user_version 方案 | 升版前用 ohosTest/真机侧拿旧版库跑一遍 | PROGRESS 1.3 |
| 14 | ⚪ | 1.5 | **首启验收三项未正式走查**：卸载重装走一遍 / 断网抓包同意前零请求 / 版本号改大重弹 | 静态侧已核（无 INTERNET 时期声明过；同意前发不出请求）；正式走查未做 | 真机补三项走查 | PROGRESS 1.5 |
| 15 | ⚪ | 3.1 | **书架正式结案待用户**：直板（含空态卡居中）+ 折叠展开 6 列大屏均真机验收过，状态仍 ⬜；创建流 UI 自动化文本输入受 IME 限制未走通（创建/撞名逻辑早前已真机验） | 流程状态未结 | 用户确认后 ✅ 结案；IME 自动化限制记录在案 | PROGRESS 3.1 |
| 16 | ⚪ | 3.3 | **本子主页正式结案待用户**：Q35 四轮真机定稿（hero 48%/顶栏磨砂 iOS 原版/底条胶囊清让/安全区 OTA 修复） | 流程状态未结 | 用户确认后 ✅ 结案 | Q35 |
| 17 | ⚪ | 3.4 | **封面编辑真机验收未做**：代码完成、438 单测绿（含 CoverCropOverlay 捏合裁切、NotebookCoverStore 烤盘、会员矩阵 R-MEMBER-06） | 本卡完成时真机未连接 | 真机走查：创建/重命名/裁切/会员拦截 | PROGRESS 3.4 |
| 18 | ⚪ | 3.5 | **阅读器验收欠账**：R-READ-05 长文不截断、R-READ-06 三主题、结尾页、眼动翻页真人复测、录屏给用户；Q36③ 尺寸常量（trace 25/audio 60/photoHeight）真机核对 | 489 单测绿 + 已装机；手感复测与录屏待用户 | 真机逐项过 + 录屏归档 | Q36 · R-READ-05/06 |
| 19 | ⚪ | 2.10 | **动态照片跨端互通待 6.4**（iOS 包导入 / 鸿蒙包导出）；weatherCode 跨端词表需 iOS 侧导出实际会写出的 SF Symbols 名单 | 鸿蒙侧拍/选/播全过（Q28）；跨端是 6.4 导入导出的事 | 6.4 时验证；Q7 词表向 iOS 要清单 | Q13 · Q7 |
| 20 | 🔵 | 2.5b | **WrapFlow 绕排全家桶下线保留**（引擎/适配器/视图/编辑器 + 278 单测，页面零引用） | 平台缺陷连环（strut 行高不生效/orphanChar×strut 零输出/heading 合并污染）回退备忘录式，产品拍板 | 恢复条件见 11 #1（平台修 strut 或后期重投入）；平时注意不要误引用 | 11 #1~#9 |
| 21 | 🔵 | 5.x | **测试开关上架前关**：服务端 `LETTER_RHYTHM_OFF`、假开通会员 | 测试期预期行为 | 上架清单执行时关（iOS 清单 A0c 同款） | Q14 |
| 22 | 🔵 | 2.5 | **键盘-工具条安全区空隙**：键盘展开时底部 safeAreaBottom padding 仍在，工具条与键盘间留背景条 | 无 keyboardHeight API 可订阅（当时）；2.5 真机验收未见明显问题，正式调优未做 | 已有 `keyboardHeightChange` 先例（3.4 用过），后续统一调优时接 | PROGRESS 2.5 |
| 23 | 🟡 | 3.6 | **大屏模式平台能力偏差五项**：① 无「减弱动态效果」可读开关（换级转场恒 400ms FastOutSlowIn，iOS 读 Reduce Motion 走 crossfade——鸿蒙侧 `accessibility` 无对应设置项）② 无振动强度档（`vibrator` 只有 preset 触感，iOS `UIImpactFeedbackGenerator(style:)` 三档对齐不了，捏合换级统一 soft）③ `accessibilityActions` 自定义动作受限（换级只有滑动手势，读屏用户无等效按钮）④ **`scrollToItemInGroup` 锚点对齐（原记「无此参数」为事实错误，已纠错）**：第 4 参 `align: ScrollAlign`（START/CENTER/END）本 SDK 即有，换级定位已改 `ScrollAlign.CENTER` 近似 iOS `scrollTo(anchor:)`（锚点居中语义），12 #24-③ 修复落地⑤ **读屏基础版**：捏合层级只报「第 N 层」不报语义内容（大屏模式的照片墙对 VoiceOver/TalkBack 逐格朗读成本高，只做了格级 label） | 平台 API 缺失或能力降级，非实现缺陷 | ①②③④ 接受偏差；⑤ 后续版本若产品要求做逐格语义朗读再投入（iOS 侧也是基础版） | PROGRESS 3.6 · U06/U07 |
| 24 | ✅ | 3.6 | **大屏模式真机走查六项（2026-10-23 全部收官）**：①溶解接缝 ②主色 R/B ③scrollToItemInGroup 定位 ④pinch focus 坐标系 ⑤换级方向/误触守卫 ⑥懒加载 | **①② 像素实测过（接缝逐行均差 ≤8.3；夜景染蓝 (r84,g88,b115) b>r）；③ 根因实锤+修复+四路径回归过（见下）；④ focus 定位在 ③ 回归中隐式验证（落点行与手指下篇一致）；⑤ 换级四级双向 + 误触守卫 400ms 冷却 + zoom 持久化冷启恢复实测过（`hdc shell uinput -T -m` 双指注入可替代真人捏合：每指 4 坐标 x1 y1 x2 y2 + 尾参 smoothTimeMs）；⑥ 9月组各位置滚入渲染完整（多 dump 序列）、尾部留白正常、SixtyFour 16 篇不满屏全渲染**。**③ 修复档案**：根因 = `scrollToItemInGroup` 默认 START 置顶，焦点在尾部月份组时目标 offset 超出 maxOffset 被钳到列表底（顶部显示其他月份、焦点行不可见；尾部留白 120→500vp 同路径落点即正确，实锤几何钳制非时序——600ms 延时版与 300ms 快速捏合均复现同样落点，证伪「组未建」「手势未结束」两假说）；iOS 基准 = `scrollTo(id:focus, anchor:)` 锚点对齐 + 尾部仅 96pt；修法 = 第 4 参 `ScrollAlign.CENTER`（组下标 +1 语义不变）+ setTimeout 回 66ms + 留白回 120vp，标定脚手架（S20/S14/SI2 按钮、calibLog、临时日志）全部移除。四路径回归（X6 16 篇 seed 数据）：Four 末页捏近主路径 offset 700px 焦点行屏显 59% 可见（bug 时钳底 924px 焦点行不可见）、(2,1) 深路径 CENTER 超限钳底但 9月组完整可见、SixtyFour 逆向内容不满屏全可见、(1,0) 对照路径无回归（offset 0 页首完整）。已知余量：66ms 转场中调用时布局为中间态，CENTER 落点与稳定几何有 ±170px 级偏差（焦点行始终在视口内，转场盖住，不追） | **③⑥ 收官；3.6 走查全过，待用户捏合手感终验后结案** | PROGRESS 3.6 |
| 25 | 🟡 | W1 | **应用接续：照片/录音文件不随接续迁移**（端到端已验收 ✅） | wantParam 只装草稿数据（官方 <100KB 约束）；文件迁移官方路径 = 分布式文件目录 + commonType.Asset 封装分布式对象（后续项）；块引用原样保留，对端缺文件按既有占位渲染，正文文字完整接续。**双设备端到端验收通过（2026-10-23，X6 ↔ Mate 80 Pro Max，A→B→A 双向；首轮 B 端白屏根因 = 接续冷启动只回调 onWindowStageRestore 不回调 onWindowStageCreate，官方 bpta-continue-cast 明示，EntryAbility 补齐 Restore 实现 + onContinue 禁系统 router 页面栈迁移后全链落编辑页）** | 后续版本接文件资产迁移（分布式文件目录 + commonType.Asset） | PROGRESS W1 · faqs-free-flow-1 |
| 26 | ⚪ | 3.6 | **捏合换级无振动（X6）——非 bug 结案**：换级振动（preset soft）不触发 | 用户 X6「系统触感反馈」开关为关（用户确认）；官方 faqs-sensor-service-3：系统触感反馈关闭时管控 usage 列表内的振动静默，属预期行为；无需修码 | 无需修复；真机验振动时先确认开关开启 | PROGRESS 3.6 |
| 27 | 🟡 | 3.6 | **`componentUtils.getRectangleById` 实测返回 px（X6 本 SDK），与捏合手势 vp 坐标不同单位**（2026-10-23 页首固定改造连带暴露并修复）：fingerList（FingerInfo）与 `ListScroller.currentOffset().yOffset` 均为 vp，rect 为 px（实测 rect=(0,435,1080,2005.5)=px，与 uitest dumpLayout 同单位）；混算致 Sixteen→Four 分开定位恒落 p0（idx 恒 0），Four→Sixteen 方向被 row 粒度掩盖碰巧对 | 已修：`HomeView.componentRect` 统一 `px ÷ display.getDefaultDisplaySync().densityPixels` 折 vp（真机终验：Sixteen 滚动后分开落 p3 ✓ 修复前恒 p0）；**B 端（Mate 80 Pro Max）未复验** | B 端装机时回归一次捏合定位（density 3.4，px 语义需复验）；若官方后续版本改回 vp 语义需重标定 | PROGRESS 3.6 |

## 三、3.5 翻书手感专项档案（用户点名：一直优化不好，记录后修）

**演进史**：
1. **角卷 A-K（第一版，2026-10-22）**：官方《翻页动效》配方 + 华为阅读 hc4 逐像素
   材质标定（背面带/弦影/折缘影），四角真机回归零差异——但**中间起手时页角突现、
   卷页钉死页角与手指脱节**（触点被 constrainTouchPoint 钳在角部圆内），用户否。
2. **角卷全域（第二版，2026-10-22 深夜）**：TOUCH_CIRCLE_RATIO 0.6→0.7 放宽跟手，
   仍被否（角部质感差、上下角翻页观感不行，用户原话「字体排版 + 纸感都不行」）。
3. **Edge 整页卷曲 + 纸感重构（第三版，2026-10-23）**：所有水平拖拽统一整页卷曲
   （角卷纯函数/渲染保留休眠）；镜像副本 24→12 条竖条圆柱弯曲、92% 不透明留 8%
   薄纸透出；字体排版改 graphics.text 实测行高。**用户三反馈**：① 中间无法翻页
   ② 上下角翻页有问题 ③ 翻页动画卡顿。
4. **当前版（2026-10-23 本轮修复，待复测）**：
   - ①② 根因 = beginFlip 把所有水平拖拽都按角卷起手（起手 Y 定上/下角）；修复 =
     统一 Edge 管线 + `foldFromDrag`（折缝从平出发按拖拽增量半速跟随，页缘起手
     精确退化为华为实测对折中点公式，中间起手不跳变）。
   - ③ 根因 = 每帧 `new CurlRenderNode` + remove/append（NodeContainer 重排）+
     saveLayer 全屏离屏层 + 28 条镜像绘制；修复 = 持久节点 + `updateFrame`
     invalidate（vsync 对齐）、去 saveLayer、镜像条 28→12、首帧整页兜底绘制。
   - 489 单测全绿 + 已装机 Mate X6，**待用户真机复测**。

**遗留质量点（修复时逐条过）**：
- **a. Edge 材质标定精度**：角卷时代做过华为 hc4 逐像素标定（背面带渐变 88→98%、
  弦影 0x1E 起 0.22W 衰减、折缘软影三带）；Edge 整页卷曲只做了简化材质（折缝高光 +
  折缘投影 + 透出页暗化），**未与华为阅读整页卷曲帧做过同精度对照**。修复方向：
  抓华为阅读水平拖拽 hold 帧，同方法逐像素标定。
- **b. 镜像条质感**：12 条竖条近似圆柱弯曲，条间接缝在浅色主题下是否可见未验证；
  真实卷页曲率是变曲率（页角更弯），平铺条带是常曲率近似。
- **c. 松手判定参数手感**：进度 >0.25（COMMIT_PROGRESS）或速度 >600vp/s
  （FLICK_VELOCITY_VP）补完——数值未与华为阅读对照；回弹曲线 16ms setInterval
  驱动，是否改 springMotion（RS 侧物理弹簧）待定。
- **d. 薄纸透出**：整层 92% 不透明留 8% 透出（角卷时代弦影带是画在透出页上的
  渐变）；Edge 版透出是均匀的，华为是折缘附近更亮——观感差距未对照。
- **e. 眼动翻页**：`EyeFlipMachine` 页缘虚拟抓取（beginFlip(true, W, W-2)）+
  `EyeFlipTracker` 真机标定，**真人复测未做**；摄像头权限拒绝引导链路已备。
- **f. 折缝方向限制**：`foldFromDrag` 只有竖直折缝（水平整页卷）；华为阅读支持
  斜折缝（触点带动折缝倾斜），当前版折缝恒垂直——跟手自由度低于华为，产品
  是否要求待定。

**修复约束**：角卷纯函数与 `drawCornerCurl` 休眠保留；改手势必须走
`foldFromDrag`（勿回 `foldFromFinger`，已删）；每帧换节点方案已证卡顿，保持
持久节点 + invalidate。

## 四、变更日志

- 2026-10-23 阶段 1~3 体检（包名切换后）：542 单测全绿（清缓存全量真执行，
  Failure 0 / Error 0）/ build 零 ERROR / console.log 零残留 / TODO 仅计划内 2 钩子；
  check_localization 报 2 条硬编码中文（HomeView Seed15 造数文案）→ #3 追记
  （随 6.x 删脚手架一并清理，不单独补七语）；推送代码确认未接（5.4 事项，无
  app_id 变更绑定失效问题）；体检无新增独立问题项。
- 2026-10-23 页首固定改造 + 捏合定位单位混算修复：16/64 级页首（尺素标题+加号）
  提出滚动流固定（用户拍板，对 iOS 偏差——iOS 页首跟滚+浮现小标题）；改造连带暴露
  Sixteen→Four 分开定位恒落 p0：根因 = `getRectangleById` 实测返回 px 而捏合手势
  （fingerList）/滚动量（currentOffset）均 vp，单位混算致 idx 恒 0；修法 =
  componentRect 内 px÷densityPixels 折 vp（+1 项 #27，B 端待复验）；真机终验
  四环（Four p3→捏近 9月可见→滚动→分开 p3→再捏近闭环）；临时标定日志
  （calibLog/onDidScroll）全删；542 单测绿 / build 零 ERROR。
- 2026-10-23 深夜 3.6 走查③④⑤⑥ 全部收官：#24 状态 ⚪→✅（③ 根因实锤（START 超界钳底，
  留白实验定案）+ 修复（ScrollAlign.CENTER，第 4 参）+ 四路径回归过；④ focus 坐标系
  隐式验证；⑤ 换级/守卫/持久化实测过（uinput 双指注入方法突破）；⑥ 懒加载 dump 覆盖）；
  #23-④ 纠错（ScrollAlign 本 SDK 即有，原记「无锚点参数」为事实错误，已改用 CENTER）；
  +1 项 #26（X6 捏合无振动 = 系统触感反馈开关关闭，非 bug 结案）；Seed15/Clear15 造数
  验后清理库回 1 篇；542 单测绿 / build 零 ERROR。
- 2026-10-23 W1 接续白屏攻坚：双设备实测 B 端白屏 → 真机日志实锤根因（接续冷启动
  只回调 onWindowStageRestore、不回调 onWindowStageCreate，官方文档明示；我们只在
  Create 里 loadContent）→ 修复（补 Restore 实现 + 禁系统 router 页面栈迁移）→
  **A→B→A 双向端到端验收通过**（#25 端到端标记 ✅）；542 单测绿 / build 零 ERROR。
- 2026-10-23 建档：推送前体检三绿（489 单测/build/本地化）；归档 3.5 翻书手感
  专项档案（§三）；汇总阶段 1~3.5 问题 22 项（阻塞 3 / 体验 3 / 偏差 6 / 欠账 7 / 工程 3）。
- 2026-10-23 用户拍板：#1 包名修改排期到**阶段四**（4.x 网络与账号，随 AGC/签名/推送一起换）。
- 2026-10-23 3.6 大屏模式建档：+2 项（#23 平台能力偏差五项（读屏基础版/无减弱动态
  效果/振动无强度档/自定义无障碍动作受限/scrollToItemInGroup 无锚点）、#24 真机走查
  六项待做（设备断开））；体检基线更新：529 单测全绿 / build 零 ERROR / 本地化过绿。
- 2026-10-23 3.6 真机四修 + 走查进展：#24 ①②过（溶解接缝/主色 R/B 像素实测）；
  细长/展开钳比、第三档尾行占位、捏合误触 400ms 冷却落库（534 单测绿）；
  发现 `.test` 增量缓存吞新用例编译错误（计数不涨先清缓存）。
- 2026-10-23 W1 跨设备应用接续建档：+1 项（#25 媒体文件不随接续迁移 + 双设备
  端到端待验）；代码完成（continuable/onContinue 实时快照/CONTINUATION 恢复链），
  542 单测绿。
