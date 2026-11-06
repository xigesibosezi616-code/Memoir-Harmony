# 尺素设置页图标 · 鸿蒙放置手册（给 agent）

> 2026-11-07 iOS 侧出。对应更新包 **U10**（设置首页重排 + 关注我们）的 R-SETTINGS-07 / 09 / 10。
> 这个目录里的图都是**成品**：圆框、图形、颜色已经画好，**拿来就放，不要再加工**。

---

## 为什么给图片

iOS 设置首页每行前面是一套尺素自己画的单色线条图标，外面套一个细线框。DevEco 里复刻不出这套线条，所以改成直接给图片：
图形是从 iOS 源码（`Memoir/Views/Settings/SettingsIcon.swift`）**原样导出**的，不是照着重画，和 iOS 逐像素比只差边缘的抗锯齿。

和 iOS 只差一处：**iOS 是细线圆角方框，鸿蒙是细线圆框**（照鸿蒙系统「设置」的样子，产品负责人定）。
另外「给我们评分」在 iOS 是 App Store 的「A」，鸿蒙换成**华为应用市场（AppGallery）的购物袋**，同样画成线条。

## 目录

```
settings_icons/
├── GUIDE.md              这份
├── preview.html          四套主题的设置首页打样（浏览器打开），做完拿它对照
├── SettingsIcons.ets     按主题取图的对照表（ArkTS），直接拷进工程用
├── png/<主题>/*.png      ✅ 鸿蒙用这个：4 倍图
└── svg/<主题>/*.svg      矢量原件，备用，不用放进工程
```

主题目录：`bamboo` 素笺、`leather` 皮革、`kent` 肯特、`polar` 极夜（id 和 iOS、和你们工程里的主题 id 一样）。

## 有哪些图（每套主题 14 张）

| 文件名（`<主题>` 换成主题 id） | 用在哪一行 | 显示尺寸 | PNG 像素 |
|---|---|---|---|
| `ic_settings_appearance_<主题>` | 外观 | 30×30vp | 120×120 |
| `ic_settings_journal_<主题>` | 日记 | 30×30vp | 120×120 |
| `ic_settings_penpal_<主题>` | 笔友 | 30×30vp | 120×120 |
| `ic_settings_location_<主题>` | 位置与天气 | 30×30vp | 120×120 |
| `ic_settings_language_<主题>` | 语言 | 30×30vp | 120×120 |
| `ic_settings_data_<主题>` | 数据与备份 | 30×30vp | 120×120 |
| `ic_settings_stats_<主题>` | 写作统计 | 30×30vp | 120×120 |
| `ic_settings_rate_<主题>` | 给我们评分（AppGallery 购物袋） | 30×30vp | 120×120 |
| `ic_settings_feedback_<主题>` | 反馈与建议 | 30×30vp | 120×120 |
| `ic_settings_about_<主题>` | 关于 | 30×30vp | 120×120 |
| `ic_follow_xiaohongshu_<主题>` | 关注我们 · 小红书 | 30×30vp | 120×120 |
| `ic_follow_douyin_<主题>` | 关注我们 · 抖音 | 30×30vp | 120×120 |
| `ic_follow_weibo_<主题>` | 关注我们 · 微博 | 30×30vp | 120×120 |
| `img_avatar_mark_<主题>` | 账户卡头像（手写 m.） | 60×60vp | 240×240 |

**没有图的两样**，照原规则自己画：
- 「尺素会员」那一行的**火漆印**：印面是用户昵称的首字，每个人不一样，不能做成图（规则见 U10 R-SETTINGS-09 和火漆相关的包）
- 二级页（外观、日记、笔友……点进去以后）每行前面的小图标：见下面「二级页」一节

## 怎么放

### 1. 拷文件

- 把 `png/` 下**四个主题目录里的全部 PNG** 平铺拷进 `entry/src/main/resources/base/media/`（文件名已经带主题，不会重名）
- **不要**放进 `dark/` 等限定词目录：图片跟着**尺素自己的主题**换，不跟系统深浅色走
- `SettingsIcons.ets` 拷进工程（放哪个目录照你们的结构），里面是 `settingsIcon(themeId, key)`

> ArkTS 的 `$r()` 只认写死的字符串，**不能**写成 `$r('app.media.ic_settings_' + key + '_' + themeId)`。
> 所以 `SettingsIcons.ets` 把四套主题全列出来了，用 `settingsIcon(当前主题 id, 'journal')` 取。没认出来的主题 id 按素笺（和 iOS 一样）。

### 2. 每一行

```ts
Row({ space: 14 }) {
  Image(settingsIcon(this.themeId, 'journal'))
    .width(30)
    .height(30)
    .objectFit(ImageFit.Contain)
    .interpolation(ImageInterpolation.High)   // 4 倍图缩小显示，边缘才干净
  Text($r('app.string.xxx'))                  // 「日记」，七种语言照原来的字符串
    .fontSize(16)
    .fontColor(主题的主文字色)
    .layoutWeight(1)
  // 右侧：进页面的是 >，外跳的（给我们评分、关注我们）是 ↗ —— 照 U10 R-SETTINGS-09
}
```

🔴 **不要**对这些图再做任何加工：
- 不加 `backgroundColor`、`border`、`borderRadius`、`clip`（圆框已经画在图里了，再加一圈就是两圈）
- 不加 `fillColor` / `colorFilter` 改色（颜色就是该主题的颜色）
- 不拉伸，宽高一样，都是 30vp（头像 60vp）
- 不给每一行换不同颜色（用户定的，见 U10）

### 3. 账户卡头像

```ts
Image(settingsIcon(this.themeId, 'avatar'))
  .width(60)
  .height(60)
  .interpolation(ImageInterpolation.High)
```

图本身是圆的（四角透明），细边也画在里面了，不用再裁圆。**不显示华为账号的头像**（U10 R-SETTINGS-10）。

### 4. 切主题

主题一换，这一页的图跟着换（`themeId` 是状态变量就行）。四套主题的打样在 `preview.html`。

## 各主题的颜色（照 iOS，给行文字、卡片、页面底用）

| 主题 | 页面底 | 卡片 | 大标题「设置」 | 行文字 | 右侧箭头 | 图标线色（图里已有） | 圆框线色（图里已有） |
|---|---|---|---|---|---|---|---|
| 素笺 bamboo | `#F0EBE1` | `#FAF7F2` | `#3D3428` | `#3D3428` | `#C8BDA8` | `#8B7E6A` | `#E8E2D6` |
| 皮革 leather | `#1C1410` | `#2A2019` | `#FFFFFF` | `#D4C4A8` | `#7A6B5A` | `#8A7B6A` | `#3A2E25` |
| 肯特 kent | `#F2F2F5` | `#FFFFFF` | `#1A1A1A` | `#1A1A1A` | `#999999` | `#666666` | `#E5E5E5` |
| 极夜 polar | `#000000` | `#1C1C1E` | `#FFFFFF` | `#E5E5EA` | `#636366` | `#8E8E93` | `#2C2C2E` |

页面底 / 卡片 / 大标题的规则见 U10 R-SETTINGS-08。🔴 **这些颜色都按尺素的主题定死，不跟系统深浅色走** —— 尤其左上角的大标题「设置」：浅色主题下手机开了深色模式，系统默认的标题色是白的，压在浅色页面底上几乎看不见（iOS 2026-11-07 修过这个）。

## 二级页的小图标（不在这批图里）

iOS 二级页每行前面用的是苹果的 **SF Symbols**。🔴 **SF Symbols 的授权不允许用在苹果以外的平台**，不要截图、不要描。
鸿蒙用系统自带的 **HarmonyOS Symbol** 里意思最接近的一个：单色、颜色 = 主题的图标线色（上表）、约 16vp，**不套框**。

| 行 | iOS 用的符号（只为说明意思） | 找一个意思相同的 |
|---|---|---|
| 主题选择 | paintbrush | 画笔 / 调色 |
| 应用图标 | app.badge | 应用 |
| 启动动画 | sparkles | 闪光 / 星星 |
| 搜索日记 | magnifyingglass | 搜索 |
| 手记页 | 随当前首页样式变（大屏 / 列表） | 卡片 / 列表 |
| 照片相纸样式 | photo.on.rectangle | 图片 |
| 同步 Live Photo 视频 | livephoto | 动态照片 |
| 笔友名、昵称 | person.crop.circle、signature | 人像、签名 / 编辑 |
| 封条提醒天数 | calendar.badge.exclamationmark | 日历 |
| 记录位置、位置精度 | location、scope | 定位、准星 |
| 导出备份、导入备份 | square.and.arrow.up / down | 上传 / 下载（导出 / 导入） |
| 照片与录音占用 | internaldrive | 存储 |
| 版本、用户协议、隐私政策 | info.circle、doc.text、lock.shield | 信息、文档、盾牌 / 锁 |
| 手机号、绑定手机号 | iphone、exclamationmark.triangle | 手机、警告 |
| 退出登录 | rectangle.portrait.and.arrow.right | 退出 |
| Apple ID、绑定 Apple ID | applelogo | 鸿蒙版没有这两行（华为账号见 U02） |

## 验收

1. 四个主题各截一张设置首页，和 `preview.html` 里同一主题那一列对比：每行一个细线圆框、图形一样、颜色一样
2. 放大截图看图标边缘：没有锯齿、没有糊、圆框是一圈（不是两圈）
3. 切主题，图标、头像跟着换；没认出来的主题显示素笺那一套
4. 「给我们评分」是购物袋，不是「A」
5. 「关注我们」三行的 logo 是单色的，不是平台的彩色图标
6. 手机切到深色模式，素笺、肯特两套主题下左上角的「设置」还是深色字、看得清（上表「大标题」一列）

## 以后改了怎么办

图形、颜色、主题有变化，**iOS 侧**重跑 `Scripts/make_harmony_settings_icons.py` 重出整个目录（这份 `GUIDE.md` 不会被覆盖），鸿蒙这边整批替换 `media/` 里同名的图和 `SettingsIcons.ets`。**不要在鸿蒙这边手修图。**
加新主题时，iOS 那边加好主题再重跑脚本，会多出一套 `<新主题>` 的图，对照表也跟着多一组。
