/**
 * 本地库打开与版本化迁移（10_BUILD_MANUAL.md 1.3）。
 *
 * 建表 SQL 照 05_DATA_MODEL.md §10（该节自称「非契约」，字段语义以 05 正文为准）。
 * 本 SDK 的 relationalStore.StoreConfig 没有 onUpgrade 回调（与 iOS GRDB
 * migration 的差异点），版本号改走 RdbStore.version（PRAGMA user_version）：
 * - 0：新库，跑全量建表后写 DATABASE_VERSION
 * - 1..DATABASE_VERSION-1：老库，按 MIGRATIONS 逐版升
 * - > DATABASE_VERSION：未来的库（装了旧版 App），不碰数据直接抛错
 * 每次给 DATABASE_VERSION +1 时：在 MIGRATIONS 末尾追加一批语句，且必须拿
 * 上一版的真实库跑一次升级再算完成（05 §10「schema 演进」，iOS 栽过两次的坑）。
 */
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 当前库结构版本 */
export const DATABASE_VERSION: number = 1;

/** 库文件名（应用沙箱 database/rdb/ 下） */
export const DATABASE_NAME: string = 'memoir.db';

/** v1 全量建表（05_DATA_MODEL.md §10） */
const SCHEMA_V1: string[] = [
  `CREATE TABLE IF NOT EXISTS journal_entry (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '',
  date INTEGER NOT NULL,
  mood TEXT NOT NULL DEFAULT '',
  mood_color_hex TEXT,
  tags TEXT NOT NULL DEFAULT '[]',
  is_favorite INTEGER NOT NULL DEFAULT 0,
  word_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  audio_urls TEXT NOT NULL DEFAULT '[]',
  weather_code TEXT, weather_info TEXT, location_info TEXT,
  content_blocks TEXT
)`,
  `CREATE TABLE IF NOT EXISTS notebook (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  color_id TEXT NOT NULL DEFAULT 'WineRed',
  texture_id TEXT NOT NULL DEFAULT 'Linen',
  last_opened_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  cover_photo_filename TEXT, cover_layout_id TEXT, subtitle TEXT
)`,
  `CREATE TABLE IF NOT EXISTS mood (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  color_hex TEXT NOT NULL DEFAULT '#B8AD9C',
  is_default INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  icon_name TEXT
)`,
  `CREATE TABLE IF NOT EXISTS letter (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL DEFAULT 'pending',
  body TEXT NOT NULL DEFAULT '',
  from_character TEXT NOT NULL DEFAULT '青鸟',
  to_name TEXT,
  stationery TEXT,
  trigger_kind TEXT NOT NULL DEFAULT 'weekly',
  error_message TEXT,
  generated_at INTEGER NOT NULL,
  delivered_at INTEGER,
  read_at INTEGER,
  updated_at INTEGER NOT NULL
)`,
  `CREATE TABLE IF NOT EXISTS letter_entry (
  letter_id TEXT NOT NULL, entry_id TEXT NOT NULL,
  PRIMARY KEY (letter_id, entry_id)
)`,
  `CREATE TABLE IF NOT EXISTS draft (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL DEFAULT '',
  content_blocks TEXT,
  mood TEXT NOT NULL DEFAULT '', mood_color_hex TEXT,
  tags TEXT NOT NULL DEFAULT '[]',
  audio_urls TEXT NOT NULL DEFAULT '[]',
  weather_code TEXT, weather_info TEXT, location_info TEXT,
  place_mode TEXT NOT NULL DEFAULT 'auto', manual_place_name TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
)`
];

/** 一版迁移：把库从 fromVersion 升到 fromVersion + 1 */
export class SchemaMigration {
  readonly fromVersion: number;
  readonly statements: string[];

  constructor(fromVersion: number, statements: string[]) {
    this.fromVersion = fromVersion;
    this.statements = statements;
  }
}

/**
 * 版本迁移表。每项把库升一级，必须按 fromVersion 升序且自 1 起连续。
 * 当前只有 v1，尚无迁移；DATABASE_VERSION 升级时在此追加。
 */
const MIGRATIONS: SchemaMigration[] = [];

/** 新库建表语句（副本，防调用方改内部表） */
export function schemaStatements(): string[] {
  return SCHEMA_V1.slice();
}

function migrationBatch(fromVersion: number): string[] {
  for (let i = 0; i < MIGRATIONS.length; i++) {
    if (MIGRATIONS[i].fromVersion === fromVersion) {
      return MIGRATIONS[i].statements;
    }
  }
  return [];
}

/** 把老库从 fromVersion 升到 DATABASE_VERSION 需要的全部语句（按版本顺序） */
export function migrationSteps(fromVersion: number): string[] {
  const steps: string[] = [];
  for (let v = fromVersion; v < DATABASE_VERSION; v++) {
    const batch: string[] = migrationBatch(v);
    for (let i = 0; i < batch.length; i++) {
      steps.push(batch[i]);
    }
  }
  return steps;
}

/** 升级方案种类：fresh 新库 / upgrade 老库升级 / current 已是最新 / future 未来版本 */
export type UpgradeKind = 'fresh' | 'upgrade' | 'current' | 'future';

/** 升级方案（纯数据，便于单测：10_BUILD_MANUAL.md 1.3 验收「老库升级」） */
export class UpgradePlan {
  readonly kind: UpgradeKind;
  readonly statements: string[];
  readonly targetVersion: number;

  constructor(kind: UpgradeKind, statements: string[], targetVersion: number) {
    this.kind = kind;
    this.statements = statements;
    this.targetVersion = targetVersion;
  }
}

/** 按当前库版本给出升级方案（纯函数） */
export function planUpgrade(currentVersion: number): UpgradePlan {
  if (currentVersion <= 0) {
    return new UpgradePlan('fresh', schemaStatements(), DATABASE_VERSION);
  }
  if (currentVersion === DATABASE_VERSION) {
    return new UpgradePlan('current', [], DATABASE_VERSION);
  }
  if (currentVersion > DATABASE_VERSION) {
    // 装了旧版 App 打开新库：不降级、不动数据（与 iOS「打不开」一致）
    return new UpgradePlan('future', [], currentVersion);
  }
  return new UpgradePlan('upgrade', migrationSteps(currentVersion), DATABASE_VERSION);
}

/** 库门面：打开（含建表 / 升级）并缓存单例 */
export class AppDatabase {
  private static store: relationalStore.RdbStore | null = null;

  static async open(context: common.Context): Promise<relationalStore.RdbStore> {
    if (AppDatabase.store !== null) {
      return AppDatabase.store;
    }
    const config: relationalStore.StoreConfig = {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    let store: relationalStore.RdbStore;
    try {
      store = await relationalStore.getRdbStore(context, config);
    } catch (err) {
      hilog.error(0x0000, 'AppDatabase', 'getRdbStore failed: %{public}s', JSON.stringify(err));
      throw new Error('AppDatabase.open: getRdbStore 失败');
    }
    const plan: UpgradePlan = planUpgrade(store.version);
    if (plan.kind === 'future') {
      throw new Error(`数据库版本 ${store.version} 高于本 App 支持的 ${DATABASE_VERSION}，拒绝打开`);
    }
    for (let i = 0; i < plan.statements.length; i++) {
      try {
        await store.executeSql(plan.statements[i]);
      } catch (err) {
        hilog.error(0x0000, 'AppDatabase', 'executeSql failed: %{public}s', JSON.stringify(err));
        throw new Error(`AppDatabase.open: 建表/升级语句失败：${plan.statements[i]}`);
      }
    }
    if (store.version !== plan.targetVersion) {
      store.version = plan.targetVersion;
    }
    AppDatabase.store = store;
    return store;
  }

  /** 拿到已打开的库（未 open 过则抛错；UI 层不直接用） */
  static require(): relationalStore.RdbStore {
    if (AppDatabase.store === null) {
      throw new Error('数据库尚未打开，先调 AppDatabase.open');
    }
    return AppDatabase.store;
  }
}
