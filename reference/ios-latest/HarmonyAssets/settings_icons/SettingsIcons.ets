// 尺素设置页图标：按主题 id 和图标名取图。由 iOS 仓库 Scripts/make_harmony_settings_icons.py 生成，不要手改。
// ArkTS 的 $r() 只认字面量，不能按主题拼文件名，所以四套主题全列出来。
// 图标名：appearance / journal / penpal / location / language / data / stats / rate / feedback / about / follow_xiaohongshu / follow_douyin / follow_weibo / avatar
// 主题 id：bamboo / leather / kent / polar（没认出来的按 bamboo，和 iOS 一样）

const SETTINGS_ICONS: Record<string, Record<string, Resource>> = {
  // 素笺
  'bamboo': {
    'appearance': $r('app.media.ic_settings_appearance_bamboo'),
    'journal': $r('app.media.ic_settings_journal_bamboo'),
    'penpal': $r('app.media.ic_settings_penpal_bamboo'),
    'location': $r('app.media.ic_settings_location_bamboo'),
    'language': $r('app.media.ic_settings_language_bamboo'),
    'data': $r('app.media.ic_settings_data_bamboo'),
    'stats': $r('app.media.ic_settings_stats_bamboo'),
    'rate': $r('app.media.ic_settings_rate_bamboo'),
    'feedback': $r('app.media.ic_settings_feedback_bamboo'),
    'about': $r('app.media.ic_settings_about_bamboo'),
    'follow_xiaohongshu': $r('app.media.ic_follow_xiaohongshu_bamboo'),
    'follow_douyin': $r('app.media.ic_follow_douyin_bamboo'),
    'follow_weibo': $r('app.media.ic_follow_weibo_bamboo'),
    'avatar': $r('app.media.img_avatar_mark_bamboo'),
  },
  // 皮革
  'leather': {
    'appearance': $r('app.media.ic_settings_appearance_leather'),
    'journal': $r('app.media.ic_settings_journal_leather'),
    'penpal': $r('app.media.ic_settings_penpal_leather'),
    'location': $r('app.media.ic_settings_location_leather'),
    'language': $r('app.media.ic_settings_language_leather'),
    'data': $r('app.media.ic_settings_data_leather'),
    'stats': $r('app.media.ic_settings_stats_leather'),
    'rate': $r('app.media.ic_settings_rate_leather'),
    'feedback': $r('app.media.ic_settings_feedback_leather'),
    'about': $r('app.media.ic_settings_about_leather'),
    'follow_xiaohongshu': $r('app.media.ic_follow_xiaohongshu_leather'),
    'follow_douyin': $r('app.media.ic_follow_douyin_leather'),
    'follow_weibo': $r('app.media.ic_follow_weibo_leather'),
    'avatar': $r('app.media.img_avatar_mark_leather'),
  },
  // 肯特
  'kent': {
    'appearance': $r('app.media.ic_settings_appearance_kent'),
    'journal': $r('app.media.ic_settings_journal_kent'),
    'penpal': $r('app.media.ic_settings_penpal_kent'),
    'location': $r('app.media.ic_settings_location_kent'),
    'language': $r('app.media.ic_settings_language_kent'),
    'data': $r('app.media.ic_settings_data_kent'),
    'stats': $r('app.media.ic_settings_stats_kent'),
    'rate': $r('app.media.ic_settings_rate_kent'),
    'feedback': $r('app.media.ic_settings_feedback_kent'),
    'about': $r('app.media.ic_settings_about_kent'),
    'follow_xiaohongshu': $r('app.media.ic_follow_xiaohongshu_kent'),
    'follow_douyin': $r('app.media.ic_follow_douyin_kent'),
    'follow_weibo': $r('app.media.ic_follow_weibo_kent'),
    'avatar': $r('app.media.img_avatar_mark_kent'),
  },
  // 极夜
  'polar': {
    'appearance': $r('app.media.ic_settings_appearance_polar'),
    'journal': $r('app.media.ic_settings_journal_polar'),
    'penpal': $r('app.media.ic_settings_penpal_polar'),
    'location': $r('app.media.ic_settings_location_polar'),
    'language': $r('app.media.ic_settings_language_polar'),
    'data': $r('app.media.ic_settings_data_polar'),
    'stats': $r('app.media.ic_settings_stats_polar'),
    'rate': $r('app.media.ic_settings_rate_polar'),
    'feedback': $r('app.media.ic_settings_feedback_polar'),
    'about': $r('app.media.ic_settings_about_polar'),
    'follow_xiaohongshu': $r('app.media.ic_follow_xiaohongshu_polar'),
    'follow_douyin': $r('app.media.ic_follow_douyin_polar'),
    'follow_weibo': $r('app.media.ic_follow_weibo_polar'),
    'avatar': $r('app.media.img_avatar_mark_polar'),
  },
};

export function settingsIcon(themeId: string, key: string): Resource {
  const byTheme: Record<string, Resource> | undefined = SETTINGS_ICONS[themeId];
  const table: Record<string, Resource> = byTheme !== undefined ? byTheme : SETTINGS_ICONS['bamboo'];
  return table[key];
}
