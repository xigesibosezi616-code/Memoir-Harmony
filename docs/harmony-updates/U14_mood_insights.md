# U14 · 情绪捕捉（写作统计）+ 会员的情绪小结

> 基于：**v1** + U03（心情页：九档 + 情绪词，`JournalEntry.moodValence` / `moodLabels`）｜ 状态：**已交付 2026-10-28**（iOS 73309bd；后端已部署）
> 本更新包**自成一体**：鸿蒙团队只看这份 + v1 + U03 即可实现（不依赖还是草稿的 U01；求助卡片在本包 R-MOOD-09 里写全了）。

---

## 一句话

写作统计下半页多一段「情绪捕捉」：心情走势、心情分布、最常出现的情绪，以及天气、地点、星期、时段下的平均心情，**免费、全在本机算**；最上面是会员的「情绪小结」，每周、每月、每年一份，一段小结加两三条建议。顺带：一小时内、同一处再写日记，沿用上一次的天气，不再调用天气服务。

## 哪些两端共用、哪些鸿蒙要做

| 两端共用（服务端，**已部署**，鸿蒙不用做） | 鸿蒙要做（App 里） |
|---|---|
| `POST /mood-summary`：小结的提示词、语言、不合格重写、「很沉」的判定（`heavy`）、会员校验 | 本机统计（R-MOOD-02–05）、六张卡片 |
| | 刚结束的是哪一期、该不该写（R-MOOD-07）、请求体怎么拼（🔴 不发正文、不发地名） |
| | `MoodSummary` 表（云同步）、备份包读写 |
| | 情绪小结卡片的几种状态、往期列表、求助卡片（R-MOOD-08、09） |
| | 天气一小时内同一处不重复取（R-WEATHER-01） |

## 改了什么、为什么

- 2026-10-27 产品定：原计划的「月度 / 年度回望」（笔友写一封「这个月的你」）**不做了**，改成写作统计里的情绪分析 —— 尺素是效率工具，以后往健康和生活方面扩展（写进系统「健康」是第二期，不在这个包里）
- **天气和地点不进会员**：照常免费记（它们是写日记的一部分，也是情绪分析的原料；免费用户不记的话，开通会员那天往回看是空的）。天气服务的开销靠「一小时内同一处不重复取」压（R-WEATHER-01），鸿蒙用哪家天气服务自己定
- 会员的小结**只发统计数字和情绪词**给服务端：不发日记正文、不发地名；服务端用完即弃

## 规则

**R-MOOD-01 入口和顺序**：设置 → 写作统计。三张数字卡片、写作日历不变；下面一段标题「情绪捕捉」，依次是：情绪小结卡片（R-MOOD-08）→ 时间范围（近 7 天 / 近 30 天 / 今年 / 全部，默认近 30 天）→ 心情走势 → 心情分布（v1 原有的环形图，搬到这里）→ 最常出现的情绪 → 天气与心情 → 地点与心情 → 星期与时段。时间范围管下面所有图，不管情绪小结。

**R-MOOD-02 只算记了心情的日记**：没有 `moodValence` 的日记不进任何一张图、不进分母。「心情」一律用愉悦度（-1…1）的**平均值**，再落回九档取颜色和名字（U03 的 `MoodLevel(valence:)`：九段均分）。

**R-MOOD-03 心情走势**：近 7 天、近 30 天按天，今年、全部按自然月；每一格的平均愉悦度连成线，点的颜色是那一档的颜色，中间一条虚线是 0（「不悲不喜」）。**没记心情的那一格不画、不补 0**。少于 2 个点时只写「再写几篇，就能看出走势」。纵轴不画刻度，只在图里左上写「愉快」、左下写「低落」；横轴日期按 App 语言格式化（中文 10/4）。

**R-MOOD-04 最常出现的情绪**：范围内选过的情绪词按次数从多到少，最多 5 个；次数一样按九档从低到高排。每行：那一档颜色的小圆点、词、一条按次数长短的条、次数。

**R-MOOD-05 天气、地点、星期、时段**：
- 天气按日记存的天气代码归六类（含有这些字样，按这个顺序判）：雪（snow / sleet / hail / flurries / blizzard）→ 雨（rain / drizzle / bolt / thunder）→ 雾霾（fog / haze / smoke / dust）→ 大风（wind / tornado / hurricane / tropicalstorm）→ 多云（cloud）→ 晴（sun / moon / clear / hot）；都不含的不归类。鸿蒙存的天气代码不同的话，按同样的六类自己映射
- 地点：日记上存的地名原样（不再合并），按篇数从多到少最多 5 处
- 星期：一周从哪天开始跟着 App 语言；时段：早上 5–11 点、下午 11–17 点、晚上 17–23 点、深夜 23–5 点（按写日记那一刻）
- 🔴 **一组不到 3 篇不显示**；某一张卡片一组都没有就整张不出，这时卡片下面一行小字「天气、地点、星期和时段，每一组至少记 3 篇心情才显示。…」
- 每一行：组名、一条从低落到愉快的刻度（颜色顺着九档）、点落在平均值上、右边那一档的名字和篇数；名字长时折两行，不截断

**R-MOOD-06 情绪小结是什么**：每周（**周一开始**）/ 每月 / 每年一份，按设备时区。一段 2–4 句的小结 + 2–3 条建议，用 **App 语言**写（换了语言，旧的不重写）。只说数据里真有的规律，不下诊断、不给医疗建议，不提具体数值。

**R-MOOD-07 什么时候写**：会员**打开写作统计**时，周、月、年各看一眼**刚结束的那一期**：本机还没有这一期的小结、那一期记了心情的日记 ≥ 3 篇，就调 `POST /mood-summary` 写一份（一期一期依次问，不并发；同一期正在写时不重复问）。**只写刚结束的那一期，不往前补**。没登录不写。写不成不弹窗：卡片上一句「这期小结没写成，下次打开会再试。」+「重试」。「同一期」= 同一种且起点相差不到 12 小时（换过时区、夏令时）。

**R-MOOD-08 情绪小结卡片**：
- 会员：标题「情绪小结」右边「周 / 月 / 年」三个小胶囊（默认周），下面是这一种最新的一期：日期（周「10月19日至25日」、月「2026年9月」、年「2026年」，按 App 语言）、小结、建议（每条前一个小圆点）；同一种有两期以上时下面一行「往期小结 ›」，点开是这一种的全部，新的在前
- 正在写：转圈 +「正在写这一期的小结…」；还没有：「每过完一周（一个月 / 一年），打开这里就会有一份…（要记满 3 篇心情）」；会员没登录：「登录尺素账号后，每过完一期就会自动写一份小结。」
- 🔴 **心情很沉的那一期**（服务端回 `heavy: true`）：小结下面附**求助卡片**（R-MOOD-09；和危险的那封信下面是同一张，鸿蒙已经做了的话直接复用）
- 不是会员：标题旁一枚会员小火漆，正文「每周、每月、每年，一段小结和几条建议，陪你看清这段时间的心情。」+ 按钮「了解尺素会员」→ 付费页
- 付费页的会员权益里「月度与年度回望」换成「情绪小结」（说明同上面那句）

**R-MOOD-09 求助卡片**（心情很沉的那期小结下面；按**这期小结的 `language`** 选热线）：
- 一张小卡片：标题「如果你现在很难受」，下面一句「请和身边信任的人说一说，或者联系专业的求助热线。」，再下面一行一个渠道，**点一下直接拨号或打开网页**
- 渠道：简体中文 →「拨打 010-82951332」（小字：北京心理危机研究与干预中心 · 24 小时，拨 `tel:01082951332`）；英语 →「拨打 988」（小字：美国 · 988 自杀与危机生命线，拨 `tel:988`）；**每种语言**最后都有「查找你所在地区的求助热线」（小字 findahelpline.com，打开 `https://findahelpline.com`）
- 只写事实、不许诺（不写「一定有人接」「会好起来的」），不加别的号码；要补各地热线先问产品

| 简体 | 繁體 | English | 日本語 | 한국어 | Français | Español |
|---|---|---|---|---|---|---|
| 如果你现在很难受 | 如果你現在很難受 | If you're struggling right now | いま、とてもつらいなら | 지금 많이 힘들다면 | Si c'est très dur en ce moment | Si ahora mismo lo estás pasando muy mal |
| 请和身边信任的人说一说，或者联系专业的求助热线。 | 請和身邊信任的人說一說，或者聯絡專業的求助熱線。 | Please talk to someone you trust, or contact a crisis line. | 信頼できる人に話してみてください。専門の相談窓口に連絡することもできます。 | 믿을 수 있는 사람에게 이야기하거나, 전문 상담 전화에 연락해 주세요. | Parlez-en à une personne de confiance, ou contactez une ligne d'écoute. | Habla con alguien de confianza o contacta con una línea de ayuda. |
| 拨打 %@ | 撥打 %@ | Call %@ | %@ に電話する | %@에 전화하기 | Appeler le %@ | Llamar al %@ |
| 北京心理危机研究与干预中心 · 24 小时 | 北京心理危機研究與干預中心 · 24 小時 | Beijing Psychological Crisis Research and Intervention Center · 24 hours | 北京心理危機研究・介入センター · 24 時間 | 베이징 심리위기연구개입센터 · 24시간 | Centre de recherche et d'intervention en crise psychologique de Pékin · 24 h/24 | Centro de Investigación e Intervención en Crisis Psicológicas de Pekín · 24 horas |
| 美国 · 988 自杀与危机生命线 | 美國 · 988 自殺與危機生命線 | 988 Suicide & Crisis Lifeline · United States | アメリカ · 988 自殺・危機ライフライン | 미국 · 988 자살·위기 상담전화 | États-Unis · 988 Suicide & Crisis Lifeline | Estados Unidos · 988 Suicide & Crisis Lifeline |
| 查找你所在地区的求助热线 | 尋找你所在地區的求助熱線 | Find a helpline where you are | お住まいの地域の相談窓口を探す | 내가 있는 지역의 상담 전화 찾기 | Trouver une ligne d'écoute près de chez vous | Buscar una línea de ayuda cerca de ti |

**R-WEATHER-01 天气不重复取**：取到天气后在本机记下（坐标取到小数点后两位、时刻、天气代码、温度）；**一小时内、离上次不到 3 公里**再写日记，直接沿用，不调天气服务。只存最近一次、不上传、不进备份。地名照常每次解析（系统的反地理编码不收钱；鸿蒙如果收钱，同样规则沿用）。

## 数据模型变化（对照 v1 `05_DATA_MODEL.md`）

**新增 MoodSummary**（情绪小结，本机 + 用户自己的云同步，跟备份包走）：

| 字段 | 类型 | 含义 |
|---|---|---|
| `id` | UUID | |
| `period` | string，默认 `"week"` | `week` / `month` / `year` |
| `periodStart` | date | 这一期的起点（周一 0 点 / 1 号 0 点 / 1 月 1 日 0 点，设备时区） |
| `periodEnd` | date | 这一期的终点（不含） |
| `text` | string | 小结 |
| `suggestions` | string[]? | 两三条建议 |
| `language` | string | 写的时候的 App 语言 |
| `entryCount` | int | 这一期记了心情的篇数 |
| `heavy` | bool，默认 false | 心情很沉：下面附求助卡片 |
| `createdAt` | date | |

iOS 是 SwiftData 第 12 版（V11 → V12 轻量迁移，只加这一张表）。

## 后端接口变化（对照 v1 `02_BACKEND_API.md`；2026-10-28 已部署）

| 接口 | 变化 |
|---|---|
| `POST /mood-summary` 🆕（要登录） | 请求 `{ period, periodStart, periodEnd, language, entryCount, averageValence, levels: [9 个篇数，从跌入谷底到心花怒放], labels: [{ label, count }], weather: [Group], places: [Group], weekdays: [Group], dayParts: [Group], trend: [{ start, valence, count }], previousAverage? }` → `{ summary, suggestions: [string], heavy }`。超时给 60 秒。**不扣邮票、服务端不存** |

- `Group = { key, valence, count }`：天气 key `clear / cloudy / rain / snow / fog / wind`；🔴 **地点不发地名**，key 是按篇数排第几处 `place1`…`place5`；星期 `monday`…`sunday`；时段 `morning / afternoon / evening / night`。每组都要 ≥ 3 篇（不够的别发，发了服务端也丢掉）
- `labels` 用情绪词的英文 rawValue（U03 的 `MoodLabel`，如 `anxious`），多的在前
- `trend`：周 → 按天，月 → 按周（周一开始），年 → 按月
- `previousAverage`：上一期（上一周 / 上个月 / 去年）的平均愉悦度，上一期没记心情就不带
- `heavy`：服务端判（最低两档 ≥ 3 篇且占三成），客户端照着附求助卡片
- 错误：403 `forbidden` + `reason = "member_required"`（不是会员）；400 `reason = "not_enough_entries"`（不到 3 篇）；其余按 v1 的错误格式

## 备份包变化（对照 v1 `modules/08_backup_package.md`）

**不升 `formatVersion`**：`entries.json` 顶层多一个可选的 `moodSummaries: [{ id, period, periodStart, periodEnd, text, suggestions, language, entryCount, heavy, createdAt }]`，没有就不写这个字段。导入时**按 `id` 去重**，本机已经有同一期（R-MOOD-07 的「同一期」）的也不导；单独解析，坏了不影响日记导入。

## 七种语言的新文案（取自 iOS 的 xcstrings）

天气六类、时段四段、周 / 月 / 年都在里面；星期几用系统按 App 语言给的简写，不另起文案。

| 简体 | 繁體 | English | 日本語 | 한국어 | Français | Español |
|---|---|---|---|---|---|---|
| 情绪捕捉 | 情緒捕捉 | Mood Insights | 気分のインサイト | 기분 인사이트 | Aperçu de vos humeurs | Resumen de tu ánimo |
| 心情走势 | 心情走勢 | Mood over time | 気分の移り変わり | 기분 흐름 | Évolution de l’humeur | Evolución del ánimo |
| 最常出现的情绪 | 最常出現的情緒 | Most frequent feelings | よく選んだ気持ち | 가장 자주 느낀 감정 | Émotions les plus fréquentes | Emociones más frecuentes |
| 天气与心情 | 天氣與心情 | Weather & mood | 天気と気分 | 날씨와 기분 | Météo et humeur | Clima y ánimo |
| 地点与心情 | 地點與心情 | Places & mood | 場所と気分 | 장소와 기분 | Lieux et humeur | Lugares y ánimo |
| 星期与时段 | 星期與時段 | Days & times | 曜日と時間帯 | 요일과 시간대 | Jours et moments | Días y momentos |
| 天气、地点、星期和时段，每一组至少记 3 篇心情才显示。多写几篇，规律会慢慢浮出来。 | 天氣、地點、星期和時段，每一組至少記 3 篇心情才顯示。多寫幾篇，規律會慢慢浮現出來。 | Weather, places, days and times appear once a group has at least 3 entries with a mood. Keep writing and the patterns will surface. | 天気・場所・曜日・時間帯は、それぞれ気分を記録した日記が3件以上になると表示されます。書き続けるうちに、傾向が少しずつ見えてきます。 | 날씨·장소·요일·시간대는 기분을 기록한 일기가 각각 3편 이상이면 보여요. 계속 쓰다 보면 패턴이 조금씩 드러나요. | La météo, les lieux, les jours et les moments s’affichent dès qu’un groupe compte au moins 3 entrées avec une humeur. Continuez d’écrire : les tendances apparaîtront peu à peu. | El clima, los lugares, los días y los momentos aparecen cuando un grupo tiene al menos 3 entradas con estado de ánimo. Sigue escribiendo y los patrones irán apareciendo. |
| 再写几篇，就能看出走势 | 再寫幾篇，就能看出走勢 | Write a few more entries to see the trend | あと少し書くと、移り変わりが見えてきます | 몇 편 더 쓰면 흐름이 보여요 | Encore quelques entrées pour voir la tendance | Escribe unas entradas más para ver la tendencia |
| 愉快 | 愉快 | Pleasant | 快い | 유쾌 | Agréable | Agradable |
| 低落 | 低落 | Unpleasant | 不快 | 불쾌 | Désagréable | Desagradable |
| 晴 | 晴 | Clear | 晴れ | 맑음 | Dégagé | Despejado |
| 多云 | 多雲 | Cloudy | くもり | 구름 많음 | Nuageux | Nublado |
| 雨 | 雨 | Rain | 雨 | 비 | Pluie | Lluvia |
| 雪 | 雪 | Snow | 雪 | 눈 | Neige | Nieve |
| 雾霾 | 霧霾 | Fog & haze | 霧・もや | 안개 | Brouillard | Niebla |
| 大风 | 大風 | Windy | 強風 | 강풍 | Vent fort | Viento |
| 早上 | 早上 | Morning | 朝 | 아침 | Matin | Mañana |
| 下午 | 下午 | Afternoon | 午後 | 오후 | Après-midi | Tarde |
| 晚上 | 晚上 | Evening | 夜 | 저녁 | Soir | Noche |
| 深夜 | 深夜 | Late night | 深夜 | 심야 | Nuit | Madrugada |
| 情绪小结 | 情緒小結 | Mood summary | 気分のまとめ | 기분 요약 | Bilan d’humeur | Resumen del ánimo |
| 周 | 週 | Week | 週 | 주간 | Semaine | Semana |
| 月 | 月 | Month | 月 | 월간 | Mois | Mes |
| 年 | 年 | Year | 年 | 연간 | Année | Año |
| 往期小结 | 往期小結 | Past summaries | 過去のまとめ | 지난 요약 | Bilans précédents | Resúmenes anteriores |
| 重试 | 重試 | Try again | 再試行 | 다시 시도 | Réessayer | Reintentar |
| 正在写这一期的小结… | 正在寫這一期的小結… | Writing this summary… | このまとめを書いています… | 이번 요약을 쓰는 중… | Rédaction du bilan… | Escribiendo el resumen… |
| 这期小结没写成，下次打开会再试。 | 這期小結沒寫成，下次打開會再試。 | This summary couldn’t be written. It’ll try again next time you open this page. | このまとめは書けませんでした。次に開いたときにもう一度試します。 | 이번 요약을 쓰지 못했어요. 다음에 열 때 다시 시도할게요. | Ce bilan n’a pas pu être rédigé. Nouvel essai à la prochaine ouverture. | No se pudo escribir este resumen. Se volverá a intentar la próxima vez que abras esta página. |
| 登录尺素账号后，每过完一期就会自动写一份小结。 | 登入尺素帳號後，每過完一期就會自動寫一份小結。 | Sign in to your Memoir account and a summary will be written after each period. | 尺素のアカウントにログインすると、期間が終わるたびにまとめが自動で届きます。 | 그리움 계정에 로그인하면 기간이 끝날 때마다 요약이 자동으로 작성돼요. | Connectez-vous à votre compte Déjà Vu : un bilan sera rédigé à la fin de chaque période. | Inicia sesión en tu cuenta de Añoranza y se escribirá un resumen al terminar cada periodo. |
| 每周、每月、每年，一段小结和几条建议，陪你看清这段时间的心情。 | 每週、每月、每年，一段小結和幾條建議，陪你看清這段時間的心情。 | Every week, month and year: a short summary and a few suggestions, to help you see how you’ve been feeling. | 毎週・毎月・毎年、短いまとめといくつかの提案で、この期間の気分を一緒に振り返ります。 | 매주, 매달, 매년 짧은 요약과 몇 가지 제안으로 그동안의 기분을 함께 돌아봐요. | Chaque semaine, chaque mois et chaque année : un court bilan et quelques suggestions pour mieux comprendre vos humeurs. | Cada semana, mes y año: un breve resumen y algunas sugerencias para ver mejor cómo ha sido tu ánimo. |
| 每过完一周，打开这里就会有一份那一周的小结（那一周要记满 3 篇心情）。 | 每過完一週，打開這裡就會有一份那一週的小結（那一週要記滿 3 篇心情）。 | When a week ends, open this page to find a summary of it (the week needs at least 3 entries with a mood). | 1週間が終わると、ここを開いたときにその週のまとめが届きます（その週に気分を3件以上記録していること）。 | 한 주가 끝나면 여기를 열 때 그 주의 요약이 생겨요(그 주에 기분을 3편 이상 기록해야 해요). | À la fin de chaque semaine, ouvrez cette page pour y trouver son bilan (au moins 3 entrées avec une humeur dans la semaine). | Al terminar cada semana, abre esta página y tendrás su resumen (la semana necesita al menos 3 entradas con estado de ánimo). |
| 每过完一个月，打开这里就会有一份那个月的小结（那个月要记满 3 篇心情）。 | 每過完一個月，打開這裡就會有一份那個月的小結（那個月要記滿 3 篇心情）。 | When a month ends, open this page to find a summary of it (the month needs at least 3 entries with a mood). | 1か月が終わると、ここを開いたときにその月のまとめが届きます（その月に気分を3件以上記録していること）。 | 한 달이 끝나면 여기를 열 때 그 달의 요약이 생겨요(그 달에 기분을 3편 이상 기록해야 해요). | À la fin de chaque mois, ouvrez cette page pour y trouver son bilan (au moins 3 entrées avec une humeur dans le mois). | Al terminar cada mes, abre esta página y tendrás su resumen (el mes necesita al menos 3 entradas con estado de ánimo). |
| 每过完一年，打开这里就会有一份那一年的小结（那一年要记满 3 篇心情）。 | 每過完一年，打開這裡就會有一份那一年的小結（那一年要記滿 3 篇心情）。 | When a year ends, open this page to find a summary of it (the year needs at least 3 entries with a mood). | 1年が終わると、ここを開いたときにその年のまとめが届きます（その年に気分を3件以上記録していること）。 | 한 해가 끝나면 여기를 열 때 그 해의 요약이 생겨요(그 해에 기분을 3편 이상 기록해야 해요). | À la fin de chaque année, ouvrez cette page pour y trouver son bilan (au moins 3 entrées avec une humeur dans l’année). | Al terminar cada año, abre esta página y tendrás su resumen (el año necesita al menos 3 entradas con estado de ánimo). |

## 任务卡

**U14-1 情绪捕捉的图（免费）**
- 目标：写作统计按 R-MOOD-01–05 出这几张图
- 先读：本包规则；U03 九档与情绪词
- 要做：本机统计（只算记了心情的、一组 ≥ 3 篇）、六张卡片、共用的时间范围、天气六类映射
- 不要：联网、把没记心情的算进去、给不够 3 篇的组画图
- 验收：造 60 篇带心情 / 天气 / 地点的日记，和 iOS 同样的数据对得上（同一组的平均心情落在同一档）

**U14-2 情绪小结（会员）**
- 目标：R-MOOD-06–08 + 数据模型 + 接口 + 备份包
- 要做：`MoodSummary` 表（云同步）、刚结束那一期的判定、请求体（🔴 不发正文、不发地名）、卡片四种状态、往期列表、很沉时的求助卡片（R-MOOD-09）、付费页权益换文案、备份读写
- 不要：往前补写、并发问、写不成就弹窗
- 验收：会员打开写作统计生成上周的小结；不是会员看到说明卡；关网时显示「没写成」+ 重试；备份导出再导入不重复

**U14-3 天气不重复取**
- 目标：R-WEATHER-01
- 验收：一小时内在同一处写两篇，第二篇不调天气服务（看日志）

## 鸿蒙已经做了的部分怎么改

- v1 的写作统计已经做了的：心情分布环形图挪进「情绪捕捉」这一段，时间范围从环形图里提到这一段的开头，管下面所有图
- 没有要拆的东西；「月度 / 年度回望」v1 里没有施工任务，不用拆
