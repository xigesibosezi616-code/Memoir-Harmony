/**
 * 信箱调试页（10_BUILD_MANUAL.md 5.1 验收脚手架，临时）。
 *
 * 一键插不同 deliveredAt 的测试信：已到达 / 在路上 / 已读 / 火漆，配清空。
 * 5.1 验收：插几封不同到达时刻的信 → 到点自动出现在信箱、红点亮起（R-BOX-02）。
 * 仅 HomeView 调试按钮行进入；真「回信加速」开关是 5.8（仅测试包），本页届时收编或删。
 * 调试文案英文硬编码，不进本地化体系（同 ThemeDebug 约定）。
 */
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../theme/AppTheme';
import { BambooTheme } from '../theme/BambooTheme';
import { STORAGE_KEY_THEME } from '../theme/ThemeManager';
import {
  STORAGE_KEY_SAFE_AREA_TOP_VP,
  STORAGE_KEY_SAFE_AREA_BOTTOM_VP
} from '../services/ImmersiveChrome';
import { AppDatabase } from '../data/Database';
import { LetterRepository } from '../data/LetterRepository';
import { Letter, LetterStatus, LetterStationeryKind, LetterTriggerKind } from '../models/Letter';
import { generateUuid } from '../models/Uuid';

const DOMAIN = 0x0000;
const TAG = 'LetterDebug';

/** 调试信正文样例（多段，够预览截断与读信滚动） */
const DEBUG_LETTER_BODY: string =
  '亲爱的朋友：\n\n见字如面。今天窗外落了些小雨，泡了一壶茶，翻到你上次说在整理的旧照片。' +
  '回忆这种东西，收得太急会碎，摊开来慢慢看才好。\n\n愿你的雨天也有热茶和旧时光。\n\n你的笔友\n青鸟';

/** 插信规格：到达时刻相对「现在」的偏移（毫秒）+ 是否已读 + 是否火漆 */
class DebugLetterSpec {
  readonly label: string;
  readonly deliveredOffsetMs: number;
  readonly read: boolean;
  readonly sealed: boolean;

  constructor(label: string, deliveredOffsetMs: number, read: boolean, sealed: boolean) {
    this.label = label;
    this.deliveredOffsetMs = deliveredOffsetMs;
    this.read = read;
    this.sealed = sealed;
  }
}

@Entry
@Component
struct LetterDebugPage {
  @StorageProp(STORAGE_KEY_THEME) theme: AppTheme = new BambooTheme();
  @StorageProp(STORAGE_KEY_SAFE_AREA_TOP_VP) safeAreaTopVp: number = 0;
  @StorageProp(STORAGE_KEY_SAFE_AREA_BOTTOM_VP) safeAreaBottomVp: number = 0;
  @State private lastAction: string = '';
  private store: relationalStore.RdbStore | undefined = undefined;

  /** 5.1 验收组合：已到（红点亮）→ 等到点自动出现 → 已读不亮 → 火漆不露预览 */
  private readonly specs: DebugLetterSpec[] = [
    new DebugLetterSpec('已到达·未读（5 分钟前到）', -5 * 60 * 1000, false, false),
    new DebugLetterSpec('即将到达（40 秒后到）', 40 * 1000, false, false),
    new DebugLetterSpec('在路上（3 小时后到）', 3 * 3600 * 1000, false, false),
    new DebugLetterSpec('已读（昨天到）', -24 * 3600 * 1000, true, false),
    new DebugLetterSpec('火漆信·已到达未拆（10 分钟前到）', -10 * 60 * 1000, false, true)
  ];

  build() {
    Column({ space: 16 }) {
      Text('LetterDebug')
        .fontSize(this.theme.headingFont.size)
        .fontWeight(this.theme.headingFont.weight)
        .fontFamily(this.theme.headingFont.family)
        .fontColor(this.theme.textPrimary)
        .margin({ top: this.safeAreaTopVp + 24 })

      ForEach(this.specs, (spec: DebugLetterSpec) => {
        Button(spec.label)
          .fontSize(this.theme.bodyFont.size)
          .fontColor(this.theme.accent)
          .backgroundColor(this.theme.accentBackground)
          .borderRadius(10)
          .width('80%')
          .onClick((): void => {
            this.insertLetter(spec);
          })
      }, (spec: DebugLetterSpec): string => spec.label)

      Button('ClearAllLetters')
        .fontSize(this.theme.bodyFont.size)
        .fontColor(this.theme.accent)
        .backgroundColor(this.theme.accentBackground)
        .borderRadius(10)
        .width('80%')
        .onClick((): void => {
          this.clearLetters();
        })

      Text(this.lastAction)
        .fontSize(this.theme.captionFont.size)
        .fontWeight(this.theme.captionFont.weight)
        .fontFamily(this.theme.captionFont.family)
        .fontColor(this.theme.textTertiary)
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })

      Column()
        .width('100%')
        .layoutWeight(1)

      Column()
        .width('100%')
        .height(this.safeAreaBottomVp + 32)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.theme.background)
  }

  /** 按规格插一封测试信（saveLetter upsert：同 id 才会覆盖，这里每次都是新 id） */
  private async insertLetter(spec: DebugLetterSpec): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      if (this.store === undefined) {
        this.store = await AppDatabase.open(context);
      }
      const now = Date.now();
      const letter = new Letter(generateUuid(), now, now);
      letter.status = spec.read ? LetterStatus.Read : LetterStatus.Pending;
      letter.body = DEBUG_LETTER_BODY;
      letter.fromCharacter = '青鸟';
      letter.toName = '你好';
      letter.triggerKind = LetterTriggerKind.Weekly;
      letter.deliveredAt = now + spec.deliveredOffsetMs;
      letter.stationery = spec.sealed ? LetterStationeryKind.Sealed : undefined;
      if (spec.read) {
        letter.readAt = now;
      }
      await LetterRepository.saveLetter(this.store, letter);
      this.lastAction = `Inserted: ${spec.label}`;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'insert debug letter failed: %{public}s', JSON.stringify(err));
      this.lastAction = `Insert FAILED: ${JSON.stringify(err)}`;
    }
  }

  /** 清空信件表（验收前重置现场用） */
  private async clearLetters(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      if (this.store === undefined) {
        this.store = await AppDatabase.open(context);
      }
      await LetterRepository.deleteAllLetters(this.store);
      this.lastAction = 'All letters cleared.';
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'clear debug letters failed: %{public}s', JSON.stringify(err));
      this.lastAction = `Clear FAILED: ${JSON.stringify(err)}`;
    }
  }
}
