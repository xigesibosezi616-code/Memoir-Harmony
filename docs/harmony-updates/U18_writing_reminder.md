# U18 · 提醒写日记（到点本机提醒；鸿蒙只做通知）

> 基于：**v1**（设置 →「日记」二级页、回信到达通知）｜ 状态：**草稿**（iOS 真机 2026-11-07 已验过到点提醒；等文案定稿）
> 本更新包**自成一体**、**内容只依赖 v1**：鸿蒙团队只看这份 + v1 即可实现。

---

## 一句话

设置 →「日记」多一栏「提醒写日记」：开关、几点、一周哪几天。到点在**本机**提醒一下「今天的那页还空着。」这类一句话，点开直接去写日记；**那天已经写过就不提醒**。默认关。

## 改了什么、为什么

- 2026-11-07 产品定：对标 Day One 后挑出公测前先做的三件之一（另两件是导入导出、手绘）。提醒是留存的基本盘
- **iOS 26 起**到点由系统拉起一张**锁屏实况 + 灵动岛**（纸色卡片：手写 m.、那句话、「记录一下」）；iOS 18–25 是普通通知
- **鸿蒙只做普通通知**：华为「实况窗」只开放给打车、外卖、航班、排队这类有始有终的服务，单纯的提醒不属于实况窗，申请不下来。**不要去申请实况窗、不要做锁屏卡片**
- 全在本机排，**不经过服务器**（和回信到达通知一样）
- **2026-11-07 真机补一条（R-REMIND-07）**：用户凌晨 00:54 写了一篇，白天把提醒设到几分钟后测，锁屏、灵动岛、通知都不出 —— 不是坏了，是「当天写过就不提醒」把今天跳过了，可界面上一个字都没说，看起来就是坏了。所以设置页那一组下面加一行「下一次提醒：…」，今天因为写过而跳过时再加一句说明

## 规则

**R-REMIND-01 设置**：设置 →「日记」二级页，在「照片相纸样式 / 封条提醒天数」那一组下面另起一组：
- 「提醒写日记」开关，**默认关**
- 打开后多两行：「时间」（几点几分，默认 **21:00**）、「重复」（一周七个小圆点，默认七天全选；**至少留一天**，点最后一个选中的不让取消）
- 组下面一行说明：「到点发一条通知提醒一下；那天写过了就不打扰。」
- 圆点上的字用系统的星期极短写法、跟 App 选的语言（简体「日 一 二…」，英文「S M T…」），从系统设置的一周第一天排起

**R-REMIND-02 权限**：**打开开关的那一刻**才申请通知权限（用户自己想要提醒，知道为什么）；拒了开关照样开着，说明上面多一行红字「通知没有打开，提醒发不出来。」+「去设置」（跳系统设置里尺素的通知页）。每次进这一页重新查一次权限

**R-REMIND-03 什么时候提醒**：选中的那几天、设定的那个时刻。**当天已经写过一篇（任何一篇正式日记，按写下的时刻算，另一台设备同步过来的也算）就不提醒**。草稿不算

**R-REMIND-04 怎么排**：全在本机，一次往后排 **14 天**内该提醒的每一次（一条一次性的定时通知，不用「每天重复」的那种 —— 要能单独跳过写过的那天）。以下时候**全部取消再重排**：
- App 回到前台（这时候顺带把另一台设备同步来的日记算进去）
- 改了提醒的任何设置
- **写完一篇**（存好那一刻）：今天不再提醒，通知中心里已经弹出来的今天那条也收掉
- 换了 App 语言（那句话要换成新语言）
- 关掉开关：排着的、已经弹出来的全部收掉

几处同时触发时排队一个个来，别两边各排一遍。

**R-REMIND-05 说什么**：标题是 App 名「尺素」，正文是下面六句里的一句，**按日子轮**（同一天不管重排几次都是同一句：取「这一天是纪元以来第几天」除以 6 的余数）。按 App 选的语言写进通知，不跟系统语言。**不催**：不出现「连续 N 天要断了」这类话，不显示任何日记内容

**R-REMIND-06 点通知**：打开 App，切到「记录」页，和点右上角加号完全一样去写 —— 有草稿接着写，没有先选写在哪本里。新手指引还没走完（还没有底部导航）时什么都不做

**R-REMIND-07 设置页显示下一次什么时候**（2026-11-07 加）：提醒开着时，那一组下面、说明那句**上面**，用次要文字色（比说明那句深一档）显示：
- 今天本来该提醒（今天是选中的那天、时刻还没过）、但今天已经写过 → 先一行「今天已经写过，今天不再提醒。」
- 再一行「下一次提醒：%@」，`%@` = 下一次的日期 + 时间，按 App 选的语言用系统的**相对日期**写法（简体「今天 21:00」「明天 21:00」，再往后「2026年11月10日 21:00」；英文「Today at 9:00 PM」…）
- 算法和排通知是同一套：从现在起往后 14 天里第一个该提醒的时刻（今天写过就跳过今天）；一个都没有（比如关了提醒）就整段不显示
- 打开这一页、改开关 / 时间 / 星期时当场重算（不用等通知排完）

## 七种语言的新文案

轮换的六句（通知正文）：

| 简体 | 繁體 | English | 日本語 | 한국어 | Français | Español |
|---|---|---|---|---|---|---|
| 今天的那页还空着。 | 今天的那頁還空著。 | Today’s page is still blank. | 今日のページは、まだ白いまま。 | 오늘의 페이지가 아직 비어 있어요. | La page d’aujourd’hui est encore blanche. | La página de hoy sigue en blanco. |
| 笔在桌上，纸也铺好了。 | 筆在桌上，紙也鋪好了。 | The pen’s on the desk, and the paper’s laid out. | ペンは机の上に、紙も広げてあります。 | 펜은 책상 위에, 종이도 펼쳐 두었어요. | Le stylo est sur la table, la feuille est prête. | La pluma está en la mesa y el papel, listo. |
| 今天过得怎么样？写两句也好。 | 今天過得怎麼樣？寫兩句也好。 | How was today? A line or two is plenty. | 今日はどんな一日でしたか？ひとことでも。 | 오늘 하루 어땠어요? 두어 줄이면 충분해요. | Comment s’est passée ta journée ? Deux lignes suffisent. | ¿Qué tal tu día? Con un par de líneas basta. |
| 趁今天还没过完，留一页给它。 | 趁今天還沒過完，留一頁給它。 | Before today slips away, save it a page. | 今日が終わる前に、一ページ残しておきましょう。 | 오늘이 다 가기 전에, 한 페이지 남겨 두세요. | Avant que la journée ne s’achève, garde-lui une page. | Antes de que se acabe el día, guárdale una página. |
| 有什么想记下来的吗？ | 有什麼想記下來的嗎？ | Anything you’d like to remember? | 書き留めておきたいこと、ありますか？ | 기록해 두고 싶은 일이 있나요? | Quelque chose que tu voudrais garder ? | ¿Hay algo que quieras anotar? |
| 停一下，给今天写几行。 | 停一下，給今天寫幾行。 | Pause for a moment and give today a few lines. | 少し手を止めて、今日のことを数行。 | 잠깐 멈추고, 오늘에게 몇 줄 남겨 봐요. | Prends un instant pour écrire quelques lignes sur aujourd’hui. | Haz una pausa y dedícale unas líneas al día de hoy. |

设置页：

| 简体 | 繁體 | English | 日本語 | 한국어 | Français | Español |
|---|---|---|---|---|---|---|
| 提醒写日记 | 提醒寫日記 | Journaling Reminder | 日記のリマインダー | 일기 쓰기 알림 | Rappel d’écriture | Recordatorio para escribir |
| 时间 | 時間 | Time | 時刻 | 시간 | Heure | Hora |
| 重复 | 重複 | Repeat | 繰り返し | 반복 | Répéter | Repetir |
| 到点发一条通知提醒一下；那天写过了就不打扰。 | 到點發一則通知提醒一下；那天寫過了就不打擾。 | At the time you choose, you’ll get a gentle notification. If you’ve already written that day, it stays quiet. | 設定した時刻に、通知でそっとお知らせします。その日もう書いていれば、お知らせしません。 | 정한 시간에 알림으로 살며시 알려 드려요. 그날 이미 썼다면 알리지 않아요. | À l’heure choisie, vous recevez une petite notification. Si vous avez déjà écrit ce jour-là, elle ne s’affiche pas. | A la hora que elijas, recibirás un aviso discreto. Si ese día ya escribiste, no te molestará. |
| 通知没有打开，提醒发不出来。 | 通知沒有開啟，提醒發不出來。 | Notifications are off, so reminders can’t be sent. | 通知がオフのため、リマインダーを送れません。 | 알림이 꺼져 있어 알림을 보낼 수 없어요. | Les notifications sont désactivées : le rappel ne peut pas être envoyé. | Las notificaciones están desactivadas, así que no se pueden enviar recordatorios. |
| 今天已经写过，今天不再提醒。 | 今天已經寫過，今天不再提醒。 | You’ve already written today, so there’s no reminder today. | 今日はもう書いたので、今日はお知らせしません。 | 오늘은 이미 썼으니 오늘은 알리지 않아요. | Vous avez déjà écrit aujourd’hui : pas de rappel aujourd’hui. | Ya escribiste hoy, así que hoy no habrá recordatorio. |
| 下一次提醒：%@ | 下一次提醒：%@ | Next reminder: %@ | 次のお知らせ：%@ | 다음 알림: %@ | Prochain rappel : %@ | Próximo recordatorio: %@ |

（「去设置」「尺素」沿用已有的文案。iOS 另有「记录一下」（实况上的按钮）和一句讲锁屏、灵动岛的说明，鸿蒙用不到。）

## 数据模型变化

没有新表、不进备份包、不进云同步（每台设备自己设自己的提醒）。本机设置三个键（iOS `UserDefaults`，鸿蒙用 Preferences 存同名键即可）：
- `writingReminderEnabled`：布尔，默认 false
- `writingReminderMinutes`：整数，一天里的第几分钟，默认 1260（21:00）
- `writingReminderWeekdays`：字符串，选中的星期连起来，**1 = 周日 … 7 = 周六**（默认 `"1234567"`）

## 任务卡

**U18-1 提醒写日记**
- **目标**：R-REMIND-01–07
- **先读**：本包；v1 设置「日记」二级页、回信到达通知（点通知跳页面的那套）
- **要做**：设置那一组（开关、时间、七个圆点、说明、拒了权限的提示、下一次提醒那一行）；本机排 14 天的一次性定时通知（鸿蒙的代理提醒 `reminderAgentManager` 或等价的定时通知都行 —— 注意系统给每个应用的条数上限，14 条以内）；回到前台、改设置、写完一篇、换语言、关开关时重排；点通知去写日记
- **不要**：不申请实况窗、不做锁屏卡片；不走服务器；不显示日记内容；不加「连续天数」之类的话；不用每天重复的通知（跳不过写过的那天）
- **验收**：设成两分钟后 → 到点有通知、点开直接是选日记本（有草稿时直接接着写）；当天先写一篇再等到点 → 不提醒，设置页显示「今天已经写过，今天不再提醒。」和「下一次提醒：明天 …」；只选周一 → 其余几天没有；拒掉权限 → 设置页出红字和「去设置」；切到英文 → 下一条通知是英文

## 鸿蒙已经做了的部分怎么改

v1 没有这个功能，全新做；不动 v1 的回信到达通知。
