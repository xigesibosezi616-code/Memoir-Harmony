/**
 * 写日记页的纯逻辑（10_BUILD_MANUAL.md 2.1）。对应 iOS `ComposeView.swift` 里的
 * `hasContent` / `cleanedBlocks` / `totalCharCount`。
 *
 * 全部纯函数：块判定、清理、字数、草稿日记本选择，单测见 ComposeLogic.test.ets。
 * v1 只有纯文本（单块），但逻辑按通用块数组写 —— 2.5/2.6/2.7 加照片录音时不用改这里。
 */
import { ContentBlock, ContentBlockType } from '../models/ContentBlock';
import { singleNotebook } from '../models/Notebook';

/**
 * 正文有没有内容（✓ 能不能点）。
 * 与 iOS `hasContent` 一致：非文本块（照片 / 录音）都算有；
 * 文本块去掉首尾空白后非空才算有。**标题不算** —— 只有标题没有正文，✓ 仍不可点。
 */
export function composeHasContent(blocks: ContentBlock[]): boolean {
  for (const block of blocks) {
    if (block.type !== ContentBlockType.Text) {
      return true;
    }
    const text = block.text ?? '';
    if (text.trim().length > 0) {
      return true;
    }
  }
  return false;
}

/** 顶部字数：所有文本块的字符数之和（iOS `totalCharCount`） */
export function composeCharCount(blocks: ContentBlock[]): number {
  let count = 0;
  for (const block of blocks) {
    if (block.type === ContentBlockType.Text) {
      count += (block.text ?? '').length;
    }
  }
  return count;
}

/**
 * 存盘（日记或草稿）前的块清理（iOS `cleanedBlocks`）：
 * 去掉纯空白的文字段；照片 / 录音都留着。全空则保底一个空文本块。
 */
export function composeCleanedBlocks(blocks: ContentBlock[], makeId: () => string): ContentBlock[] {
  const cleaned: ContentBlock[] = [];
  for (const block of blocks) {
    if (block.type !== ContentBlockType.Text) {
      cleaned.push(block);
      continue;
    }
    if ((block.text ?? '').trim().length > 0) {
      cleaned.push(block);
    }
  }
  if (cleaned.length === 0) {
    return [ContentBlock.makeText(makeId(), '')];
  }
  return cleaned;
}

/**
 * 恢复草稿时的日记本选择（R-ENTRY-05）：草稿里选过的（单本规则整理后恰好一本）优先；
 * 没选过才用「从哪本点进来写」带进来的那本。v1 的入口不带日记本上下文，初值恒为空。
 * 草稿里存了多本的（单本规则之前存的）视同没选（iOS `restoreDraftIfNeeded` 同款）。
 */
export function restoredNotebookSelection(draftTags: string[], initialTags: string[]): string[] {
  const drafted = singleNotebook(draftTags);
  return drafted.length > 0 ? drafted : singleNotebook(initialTags);
}
