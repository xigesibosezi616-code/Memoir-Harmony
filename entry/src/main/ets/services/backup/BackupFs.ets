/**
 * 备份服务共用的文件操作辅助（6.4 / 6.5；导入 / 导出两个服务都用，不依赖业务模型）。
 * 统一走 @kit.CoreFileKit 的 fileIo；失败返回 undefined / false / -1，由调用方决定怎么报错。
 */
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'BackupFs';

/** 读文件头若干字节（不解整包）。读不到返回 undefined */
export function readHeadBytes(filePath: string, count: number): Uint8Array | undefined {
  try {
    const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
    try {
      const buf = new ArrayBuffer(count);
      fileIo.readSync(file.fd, buf);
      return new Uint8Array(buf);
    } finally {
      fileIo.closeSync(file);
    }
  } catch (err) {
    return undefined;
  }
}

/** 整个文件读成字节（备份包可能上百 MB；导入路径一次性读入，与 iOS mappedIfSafe 等效） */
export function readBytes(filePath: string): Uint8Array | undefined {
  try {
    const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
    try {
      const size = fileIo.statSync(file.fd).size;
      const buf = new ArrayBuffer(size);
      fileIo.readSync(file.fd, buf);
      return new Uint8Array(buf);
    } finally {
      fileIo.closeSync(file);
    }
  } catch (err) {
    return undefined;
  }
}

/** 字节写盘（失败返回 false） */
export function writeBytes(filePath: string, data: Uint8Array): boolean {
  try {
    const file = fileIo.openSync(filePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, data.buffer);
    } finally {
      fileIo.closeSync(file);
    }
    return true;
  } catch (err) {
    return false;
  }
}

/** 文本写盘（失败返回 false） */
export function writeTextFile(filePath: string, text: string): boolean {
  try {
    const file = fileIo.openSync(filePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, text);
    } finally {
      fileIo.closeSync(file);
    }
    return true;
  } catch (err) {
    return false;
  }
}

/** 读文本文件（文件不存在 / 读不了返回 undefined） */
export function readTextFile(filePath: string): string | undefined {
  try {
    return fileIo.readTextSync(filePath);
  } catch (err) {
    return undefined;
  }
}

/** 递归删目录 / 文件（清临时目录用；不存在静默） */
export function removeTree(path: string): void {
  try {
    if (fileIo.statSync(path).isDirectory()) {
      let names: string[] = [];
      try {
        names = fileIo.listFileSync(path);
      } catch (err) {
        names = [];
      }
      for (const name of names) {
        removeTree(`${path}/${name}`);
      }
      fileIo.rmdirSync(path);
      return;
    }
    fileIo.unlinkSync(path);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'removeTree failed: %{public}s', path);
  }
}

/** 递归建目录（已存在不报错） */
export function ensureDir(dirPath: string): boolean {
  try {
    if (!fileIo.accessSync(dirPath)) {
      fileIo.mkdirSync(dirPath, true);
    }
    return true;
  } catch (err) {
    return false;
  }
}

export function fileExists(filePath: string): boolean {
  try {
    return fileIo.accessSync(filePath);
  } catch (err) {
    return false;
  }
}

/** 文件字节数；不存在 / 读不了返回 -1（区分「0 字节的空文件」） */
export function fileSizeOf(filePath: string): number {
  try {
    return fileIo.statSync(filePath).size;
  } catch (err) {
    return -1;
  }
}

/**
 * 只取路径最后一段：备份包 json 里的文件名是外部输入，
 * 不能让 "../../x" 决定往哪读 / 往哪写
 */
export function lastPathComponent(path: string): string {
  const slash = path.lastIndexOf('/');
  return slash >= 0 ? path.substring(slash + 1) : path;
}
