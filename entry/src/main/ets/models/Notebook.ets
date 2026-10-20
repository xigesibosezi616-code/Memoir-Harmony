/**
 * 日记本（05_DATA_MODEL.md §4）。对应 iOS `Models/Tag.swift`、`BookColor.swift`、
 * `CoverLayout.swift`、`BookTexture.swift`（鸿蒙侧合并为一个文件，类名按
 * `01_TECH_STACK_MAPPING.md` 的建议用 Notebook，规则函数与 iOS 同名）。
 *
 * - 🔴 **名字就是身份**：日记靠 `JournalEntry.tags` 里的名字字符串挂在日记本上，
 *   不是外键。改名必须连带改所有日记的 tags（名字规则见下方静态方法）
 * - 本地时间字段存毫秒
 * - `textureId`：2026-10 起只剩亚麻；**新写一律 "Linen"**（渲染不读这个字段）
 */
export enum BookColor {
  WineRed = 'WineRed',
  PineGreen = 'PineGreen',
  PrussianBlue = 'PrussianBlue',
  Eggplant = 'Eggplant',
  AmberBrown = 'AmberBrown',
  Charcoal = 'Charcoal',
  Slate = 'Slate',
  Ivory = 'Ivory'
}

/** 已下架颜色 → 最接近的保留色（05 §4.1）。迁移、导入、渲染三处都要接 */
export function retiredColorReplacement(raw: string): BookColor | undefined {
  switch (raw) {
    case 'RustRed': return BookColor.WineRed;
    case 'OliveBrown': return BookColor.PineGreen;
    case 'BronzeBrown': return BookColor.AmberBrown;
    case 'Camel': return BookColor.AmberBrown;
    default: return undefined;
  }
}

export function bookColorFromRaw(raw: string): BookColor | undefined {
  switch (raw) {
    case 'WineRed': return BookColor.WineRed;
    case 'PineGreen': return BookColor.PineGreen;
    case 'PrussianBlue': return BookColor.PrussianBlue;
    case 'Eggplant': return BookColor.Eggplant;
    case 'AmberBrown': return BookColor.AmberBrown;
    case 'Charcoal': return BookColor.Charcoal;
    case 'Slate': return BookColor.Slate;
    case 'Ivory': return BookColor.Ivory;
    default: return undefined;
  }
}

/** 颜色色点（颜色选择器小圆点预览用；实际封面渲染走 Cover_* 图） */
export function bookColorHex(color: BookColor): string {
  switch (color) {
    case BookColor.WineRed: return '#592A2C';
    case BookColor.PineGreen: return '#34473B';
    case BookColor.PrussianBlue: return '#233C58';
    case BookColor.Eggplant: return '#3E2F43';
    case BookColor.AmberBrown: return '#7A5429';
    case BookColor.Charcoal: return '#201E1C';
    case BookColor.Slate: return '#625F5C';
    case BookColor.Ivory: return '#EBE2D2';
  }
}

/** 浅色底（仅象牙白），决定叠加文字颜色（深棕 vs 米白） */
export function isLightBookColor(color: BookColor): boolean {
  return color === BookColor.Ivory;
}

/** 封面纹理。2026-10 起只剩亚麻（rawValue 与 iOS 对齐） */
export enum BookTexture {
  Linen = 'Linen'
}

/** 照片封面的版式（05 §4 / iOS `CoverLayout.swift`）。rawValue 进库和备份包，不要改 */
export enum CoverLayout {
  /** 满版：照片铺满整个封面，书名压在照片上 */
  FullBleed = 'FullBleed',
  /** 白框：米白纸封面，照片嵌上半部，书名在照片下面 */
  Framed = 'Framed',
  /** 贴照片：亚麻布面中间贴一张带白边的照片，书名烫在下面 */
  TipIn = 'TipIn'
}

export function coverLayoutFromRaw(raw: string): CoverLayout | undefined {
  switch (raw) {
    case 'FullBleed': return CoverLayout.FullBleed;
    case 'Framed': return CoverLayout.Framed;
    case 'TipIn': return CoverLayout.TipIn;
    default: return undefined;
  }
}

export class Notebook {
  readonly id: string;
  /** 只去首尾空白存库，大小写 / 全半角原样保留（判重另见 nameKey） */
  name: string;
  /** 封面颜色：BookColor 的 rawValue。默认酒红（声明默认与 iOS 一致） */
  colorId: string = 'WineRed';
  /** 封面纹理。新写一律 "Linen"（iOS 声明处默认 "Leather" 是历史包袱，不抄） */
  textureId: string = BookTexture.Linen;
  /** 最后打开时间（保留备用，不渲染） */
  lastOpenedAt: number;
  /** 创建时刻。排序的第二键（sortOrder 相同时按它） */
  createdAt: number;
  /** 书架位置，小的在前。新建 = 现有最大值 + 1（nextSortOrder） */
  sortOrder: number = 0;
  /** 照片封面文件名（journal_photos/ 下）。空 = 纯色亚麻 */
  coverPhotoFilename?: string;
  /** 版式：FullBleed / Framed / TipIn。空或不认识 = 满版 */
  coverLayoutId?: string;
  /** 书名下的小字，≤ 24 字，去首尾空白，空 = 没有 */
  subtitle?: string;

  constructor(id: string, name: string, createdAt: number, lastOpenedAt: number) {
    this.id = id;
    this.name = name;
    this.createdAt = createdAt;
    this.lastOpenedAt = lastOpenedAt;
  }

  /**
   * 解析封面颜色：已下架的就近映射，再不认识回落酒红 ——
   * 迁移只在启动时跑一次，接不住之后才到的数据（旧版本同步来的、旧备份包导的）。
   * 完全不认识的 colorId 在**存库时**原样保留（可能是更新版本加的色）。
   */
  get bookColor(): BookColor {
    const direct = bookColorFromRaw(this.colorId);
    if (direct !== undefined) {
      return direct;
    }
    const retired = retiredColorReplacement(this.colorId);
    return retired !== undefined ? retired : BookColor.WineRed;
  }

  /** 封面版式；库里没有 / 不认识的值（更新版本加的）按满版 */
  get coverLayout(): CoverLayout {
    if (this.coverLayoutId !== undefined) {
      const layout = coverLayoutFromRaw(this.coverLayoutId);
      if (layout !== undefined) {
        return layout;
      }
    }
    return CoverLayout.FullBleed;
  }

  /** 封面渲染用的标题文案：每行最多 4 字，超出自动折行。`name` 仍是逻辑用的原值 */
  get displayName(): string {
    if (this.name.length <= 4) {
      return this.name;
    }
    let result = '';
    for (let i = 0; i < this.name.length; i++) {
      if (i > 0 && i % 4 === 0) {
        result += '\n';
      }
      result += this.name.charAt(i);
    }
    return result;
  }
}

// ---- 名字规则：日记本不许重名（iOS `Tag.swift` 的静态方法，同名同义） ----

/**
 * 判重用的键：去首尾空白、忽略大小写与全半角。
 * 「Travel」「travel」「Ｔｒａｖｅｌ」「 旅行 」各算同一个名字。
 * **只用于比较，不要存进库** —— 用户输入的大小写和全半角原样保留。
 *
 * 全半角折叠用 NFKC 兼容分解（全角拉丁 → 半角、半角假名 → 全角），
 * 与 iOS `folding(.caseInsensitive + .widthInsensitive)` 对齐。
 */
export function nameKey(name: string): string {
  return name.trim().normalize('NFKC').toLowerCase();
}

/** 存库前的名字：只去首尾空白 */
export function cleanedName(raw: string): string {
  return raw.trim();
}

/** `name` 是否和 `names` 里的某一个撞名（按 nameKey 比）。
 * 重命名时调用方要先把自己从 names 里排除，否则改个大小写也会被拦 */
export function isNameTaken(name: string, names: string[]): boolean {
  const key = nameKey(name);
  for (const existing of names) {
    if (nameKey(existing) === key) {
      return true;
    }
  }
  return false;
}

/**
 * 新建的日记本排在书架最后：现有最大 sortOrder + 1。
 * 每个新建日记本的入口都要用它，否则新书会插进老书中间。
 */
export function nextSortOrder(existingSortOrders: number[]): number {
  let max = -1;
  for (const v of existingSortOrders) {
    if (v > max) {
      max = v;
    }
  }
  return max + 1;
}

/**
 * 起一个不撞名的名字：「旅行」→「旅行 2」→「旅行 3」……
 * 序号前的半角空格不进本地化：名字是用户数据，换语言不该跟着变（R-LANG-10）。
 */
export function uniqueName(basedOn: string, avoiding: string[]): string {
  const taken = new Set<string>();
  for (const name of avoiding) {
    taken.add(nameKey(name));
  }
  const cleaned = cleanedName(basedOn);
  if (!taken.has(nameKey(cleaned))) {
    return cleaned;
  }
  let n = 2;
  while (taken.has(nameKey(`${cleaned} ${n}`))) {
    n++;
  }
  return `${cleaned} ${n}`;
}

/**
 * 按单本规则整理一组日记本名字：去重后恰好一本 → 留下；一本没有或多于一本 → 空。
 * 多于一本的不去猜「主要是哪本」，一律退回「全部日记」，由用户重新选（R-BOOK-01）。
 */
export function singleNotebook(names: string[]): string[] {
  const unique: string[] = [];
  for (const name of names) {
    if (!unique.includes(name)) {
      unique.push(name);
    }
  }
  return unique.length === 1 ? unique : [];
}

/** 首启默认日记本名（按中文写入，是用户数据，不翻译 —— R-APP-07 / R-LANG-10） */
export const DEFAULT_NOTEBOOK_NAMES: string[] = ['生活', '读书笔记', '旅行', '工作'];

/**
 * 封面渲染用的书名折行（iOS `BookCoverView.displayName`，与 `Notebook.displayName`
 * 的差别）：中日韩标题按每 4 字断行；**带拉丁字母的**（英文名、外语界面下
 * 「全部日记」的译名）不手动断——按 4 个字符硬切会把「All Entries」切成
 * 「All 」「Entr」「ies」，交给系统按词换行。
 */
export function coverDisplayName(name: string): string {
  if (name.length <= 4) {
    return name;
  }
  for (let i = 0; i < name.length; i++) {
    const code = name.charCodeAt(i);
    // ASCII 字母（A-Z / a-z）：交给系统按词换行
    if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) {
      return name;
    }
  }
  let result = '';
  for (let i = 0; i < name.length; i++) {
    if (i > 0 && i % 4 === 0) {
      result += '\n';
    }
    result += name.charAt(i);
  }
  return result;
}

/** `BookColor` 声明顺序（并列取色时的确定性依据，与 iOS `BookColor.allCases` 一致） */
export const BOOK_COLOR_ORDER: BookColor[] = [
  BookColor.WineRed,
  BookColor.PineGreen,
  BookColor.PrussianBlue,
  BookColor.Eggplant,
  BookColor.AmberBrown,
  BookColor.Charcoal,
  BookColor.Slate,
  BookColor.Ivory
];

/**
 * 写日记页顺手新建日记本时取的颜色（iOS `TagSelector.quietestColor`，05 §4.1）：
 * 书架上**用得最少**的颜色，免得连建几本全是同一个颜色、摆在架子上分不清。
 * 象牙白不参与（那是「全部日记」的门面）；并列按 `BookColor` 声明顺序取第一个，
 * 结果确定——所以书架上一本都没有时返回声明序第一个**酒红**（与 iOS
 * `candidates.min ?? .pineGreen` 行为一致：`??` 只在候选为空时触发，永不发生）。
 */
export function quietestColor(notebooks: Notebook[]): BookColor {
  const usage: number[] = [];
  for (let i = 0; i < BOOK_COLOR_ORDER.length; i++) {
    usage.push(0);
  }
  for (const notebook of notebooks) {
    const color = notebook.bookColor;
    const index = BOOK_COLOR_ORDER.indexOf(color);
    if (index >= 0) {
      usage[index]++;
    }
  }
  let bestIndex = -1;
  let bestCount = Number.MAX_SAFE_INTEGER;
  for (let i = 0; i < BOOK_COLOR_ORDER.length; i++) {
    const color = BOOK_COLOR_ORDER[i];
    if (color === BookColor.Ivory) {
      continue; // 象牙白是「全部日记」的门面，不给新本子用
    }
    if (usage[i] < bestCount) {
      bestCount = usage[i];
      bestIndex = i;
    }
  }
  return bestIndex >= 0 ? BOOK_COLOR_ORDER[bestIndex] : BookColor.PineGreen;
}
