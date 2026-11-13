/**
 * Database 迁移方案单测（10_BUILD_MANUAL.md 1.3）。
 *
 * 本 SDK 的 RDB 没有 onUpgrade 回调，版本化迁移走 RdbStore.version +
 * 纯函数 planUpgrade。这里对表覆盖四种库状态（新装 / 已最新 / 旧库升级 /
 * 未来版本拒绝打开）。「拿上一版真实库跑升级」属于设备侧验收，
 * 由 ohosTest / 真机回归补（05 §10 schema 演进的要求不变）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { DATABASE_VERSION, DATABASE_NAME, schemaStatements, migrationSteps,
  planUpgrade } from '../../main/ets/data/Database';

export default function databaseTest() {
  describe('DatabaseTest', () => {
    it('freshInstallRunsFullSchema', 0, () => {
      const plan = planUpgrade(0);
      expect(plan.kind).assertEqual('fresh');
      expect(plan.targetVersion).assertEqual(DATABASE_VERSION);
      expect(plan.statements.length).assertEqual(7);
    })

    it('schemaCreatesAllSevenTables', 0, () => {
      const sql = schemaStatements().join('\n');
      expect(sql.includes('CREATE TABLE IF NOT EXISTS journal_entry')).assertTrue();
      expect(sql.includes('CREATE TABLE IF NOT EXISTS notebook')).assertTrue();
      expect(sql.includes('CREATE TABLE IF NOT EXISTS mood')).assertTrue();
      expect(sql.includes('CREATE TABLE IF NOT EXISTS letter (')).assertTrue();
      expect(sql.includes('CREATE TABLE IF NOT EXISTS letter_entry')).assertTrue();
      expect(sql.includes('CREATE TABLE IF NOT EXISTS draft')).assertTrue();
      expect(sql.includes('CREATE TABLE IF NOT EXISTS pen_pal_note')).assertTrue();
    })

    it('currentVersionNeedsNoStatements', 0, () => {
      const plan = planUpgrade(DATABASE_VERSION);
      expect(plan.kind).assertEqual('current');
      expect(plan.statements.length).assertEqual(0);
      expect(plan.targetVersion).assertEqual(DATABASE_VERSION);
    })

    it('futureVersionIsRejectedWithoutTouchingData', 0, () => {
      const plan = planUpgrade(DATABASE_VERSION + 1);
      expect(plan.kind).assertEqual('future');
      expect(plan.statements.length).assertEqual(0);
      expect(plan.targetVersion).assertEqual(DATABASE_VERSION + 1);
    })

    it('migrationStepsEmptyForCurrentVersion', 0, () => {
      expect(migrationSteps(DATABASE_VERSION).length).assertEqual(0);
    })

    it('schemaStatementsReturnsDefensiveCopy', 0, () => {
      const copy = schemaStatements();
      copy.push('-- injected');
      expect(schemaStatements().length).assertEqual(7);
    })

    it('databaseNameAndVersionPinned', 0, () => {
      expect(DATABASE_NAME).assertEqual('memoir.db');
      expect(DATABASE_VERSION).assertEqual(4);
    })

    // ---- v2（6.3 写作统计）：U03 数据字段前置 ----

    it('freshSchemaCarriesMoodValenceColumns', 0, () => {
      const sql = schemaStatements()[0];
      expect(sql.includes('mood_valence REAL')).assertTrue();
      expect(sql.includes('mood_labels TEXT')).assertTrue();
    })

    it('upgradeFromV1RunsBothMigrations', 0, () => {
      // v1 库升级要一路跑到当前版本：补 v2 两列、v3 世界笔友四列、v4 手记表
      const steps = migrationSteps(1);
      expect(steps.length).assertEqual(7);
      expect(steps[0]).assertEqual('ALTER TABLE journal_entry ADD COLUMN mood_valence REAL');
      expect(steps[1]).assertEqual('ALTER TABLE journal_entry ADD COLUMN mood_labels TEXT');
      expect(steps[2]).assertEqual('ALTER TABLE letter ADD COLUMN pen_pal_id TEXT');
      expect(steps[3]).assertEqual('ALTER TABLE letter ADD COLUMN translated_body TEXT');
      expect(steps[4]).assertEqual('ALTER TABLE letter ADD COLUMN danger INTEGER');
      expect(steps[5]).assertEqual('ALTER TABLE letter ADD COLUMN postage INTEGER');
      expect(steps[6].includes('pen_pal_note')).assertTrue();
      const plan = planUpgrade(1);
      expect(plan.kind).assertEqual('upgrade');
      expect(plan.targetVersion).assertEqual(DATABASE_VERSION);
    })

    // ---- v3（U01 邮票制）：letter 一次加齐世界笔友四列（镜像 iOS SchemaV9） ----

    it('freshSchemaCarriesPenPalColumns', 0, () => {
      const sql = schemaStatements().join('\n');
      expect(sql.includes('pen_pal_id TEXT')).assertTrue();
      expect(sql.includes('translated_body TEXT')).assertTrue();
      expect(sql.includes('danger INTEGER')).assertTrue();
      expect(sql.includes('postage INTEGER')).assertTrue();
    })

    it('upgradeFromV2AddsFourLetterColumns', 0, () => {
      // 从 v2 起：四列 + v4 手记表
      const steps = migrationSteps(2);
      expect(steps.length).assertEqual(5);
      expect(steps[0]).assertEqual('ALTER TABLE letter ADD COLUMN pen_pal_id TEXT');
      expect(steps[1]).assertEqual('ALTER TABLE letter ADD COLUMN translated_body TEXT');
      expect(steps[2]).assertEqual('ALTER TABLE letter ADD COLUMN danger INTEGER');
      expect(steps[3]).assertEqual('ALTER TABLE letter ADD COLUMN postage INTEGER');
      const plan = planUpgrade(2);
      expect(plan.kind).assertEqual('upgrade');
      expect(plan.targetVersion).assertEqual(DATABASE_VERSION);
    })

    // ---- v4（U01 B3 笔友手记）：新表 pen_pal_note（镜像 iOS SchemaV11） ----

    it('freshSchemaCarriesPenPalNoteTable', 0, () => {
      const sql = schemaStatements().join('\n');
      expect(sql.includes('pen_pal_note')).assertTrue();
      expect(sql.includes('kind TEXT NOT NULL DEFAULT \'recent\'')).assertTrue();
      expect(sql.includes('noted_at INTEGER NOT NULL')).assertTrue();
      expect(sql.includes('updated_at INTEGER')).assertTrue();
    })

    it('upgradeFromV3CreatesPenPalNoteTable', 0, () => {
      const steps = migrationSteps(3);
      expect(steps.length).assertEqual(1);
      expect(steps[0].includes('CREATE TABLE IF NOT EXISTS pen_pal_note')).assertTrue();
      const plan = planUpgrade(3);
      expect(plan.kind).assertEqual('upgrade');
      expect(plan.targetVersion).assertEqual(DATABASE_VERSION);
    })
  })
}
