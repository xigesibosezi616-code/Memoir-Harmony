/**
 * 媒体文件系统抽象与文件操作核心（10_BUILD_MANUAL.md 1.4）。
 *
 * 把「列目录 / 看大小 / 删文件」抽成可注入接口：真机走 `@kit.CoreFileKit`
 * 的 fileIo，单测注入内存实现即可跑穿占用统计、孤儿清理、删日记媒体的真实逻辑。
 */
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'MediaFiles';

/** 目录里扫出来的一个文件（名字 + 字节数） */
export class MediaFileEntry {
  readonly name: string;
  readonly size: number;

  constructor(name: string, size: number) {
    this.name = name;
    this.size = size;
  }
}

/** 两个媒体目录（应用沙箱 filesDir 下的绝对路径） */
export class MediaDirs {
  readonly photosDir: string;
  readonly audioDir: string;

  constructor(photosDir: string, audioDir: string) {
    this.photosDir = photosDir;
    this.audioDir = audioDir;
  }
}

/** 媒体文件系统（可注入；单测用内存实现） */
export interface MediaFileSystem {
  /** 列目录一层的文件（跳过子目录与隐藏文件）；目录不存在 / 读不了返回空 */
  listFiles(dirPath: string): MediaFileEntry[];
  /** 文件字节数；不存在 / 读不了返回 0 */
  fileSize(filePath: string): number;
  /** 删除文件，成功返回 true */
  deleteFile(filePath: string): boolean;
  /** 递归建目录（已存在不报错） */
  mkdirs(dirPath: string): void;
}

/** 真机实现：`@kit.CoreFileKit` 的 fileIo */
export class HarmonyMediaFileSystem implements MediaFileSystem {
  listFiles(dirPath: string): MediaFileEntry[] {
    const result: MediaFileEntry[] = [];
    let names: string[] = [];
    try {
      names = fileIo.listFileSync(dirPath);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'listFileSync failed: %{public}s %{public}s',
        dirPath, JSON.stringify(err));
      return result;
    }
    for (const name of names) {
      if (name.length === 0 || name.startsWith('.')) {
        continue; // 跳过隐藏文件（对齐 iOS skipsHiddenFiles）
      }
      const full = `${dirPath}/${name}`;
      try {
        if (fileIo.statSync(full).isDirectory()) {
          continue; // 子目录不算媒体文件
        }
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'statSync failed: %{public}s %{public}s',
          full, JSON.stringify(err));
        continue;
      }
      result.push(new MediaFileEntry(name, this.fileSize(full)));
    }
    return result;
  }

  fileSize(filePath: string): number {
    try {
      return fileIo.statSync(filePath).size;
    } catch (err) {
      return 0;
    }
  }

  deleteFile(filePath: string): boolean {
    try {
      fileIo.unlinkSync(filePath);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'unlinkSync failed: %{public}s %{public}s',
        filePath, JSON.stringify(err));
      return false;
    }
  }

  mkdirs(dirPath: string): void {
    try {
      if (!fileIo.accessSync(dirPath)) {
        fileIo.mkdirSync(dirPath, true);
      }
      return;
    } catch (err) {
      // accessSync 在目录不存在时抛错，落到下面的 mkdir
    }
    try {
      fileIo.mkdirSync(dirPath, true);
    } catch (err2) {
      hilog.error(DOMAIN, TAG, 'mkdirs failed: %{public}s %{public}s',
        dirPath, JSON.stringify(err2));
    }
  }
}

/** 删一个目录里的一批文件（删日记 / 草稿引用的媒体用），返回删掉的条数 */
export function deleteFilesInDir(fileSystem: MediaFileSystem, dirPath: string,
  filenames: string[]): number {
  let deleted = 0;
  for (const name of filenames) {
    if (name.length === 0) {
      continue;
    }
    if (fileSystem.deleteFile(`${dirPath}/${name}`)) {
      deleted++;
    }
  }
  return deleted;
}
