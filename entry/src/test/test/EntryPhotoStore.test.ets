/**
 * 大屏照片缓存的单测（10_BUILD_MANUAL.md 3.6，U06 R-HOME-10）。
 * 可单测的部分：
 * - 缓存键 / 小图落盘路径的格式（重跑不改名、按尺寸分目录）
 * - DecodeGate：同时最多 limit 个（多余的排队）；**后来的先进**（LIFO）——
 *   快速滚动时眼前刚出现的格子比早就滚走的要紧；release 把名额直接交给
 *   排在最后的那个，不经过队头
 * 真正的解码（image Kit）、取色（readPixels）在真机验收走查，不在单测里。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  DecodeGate,
  entryPhotoKey,
  smallPhotoPath
} from '../../main/ets/services/EntryPhotoStore';

/** 等一个宏任务节拍（让排队的 resolve 跑完） */
function tick(): Promise<void> {
  return new Promise<void>((resolve: (value: void) => void) => {
    setTimeout((): void => {
      resolve();
    }, 0);
  });
}

export default function entryPhotoStoreTest() {
  describe('EntryPhotoStore', () => {
    it('entryPhotoKeyJoinsSizeAndFilename', 0, () => {
      expect(entryPhotoKey(600, 'a.jpg')).assertEqual('600:a.jpg');
      expect(entryPhotoKey(1400, 'a.jpg')).assertEqual('1400:a.jpg');
      expect(entryPhotoKey(600, 'b.jpg') === entryPhotoKey(600, 'a.jpg')).assertFalse();
    })

    it('smallPhotoPathNestsBySizeAndForcesJpg', 0, () => {
      // 小图统一转 JPEG 落盘：原文件名 + 固定 .jpg 后缀（PNG 源也存 .jpg）
      expect(smallPhotoPath('/data/cache', 600, 'a.heic'))
        .assertEqual('/data/cache/EntryPhotos/600/a.heic.jpg');
      expect(smallPhotoPath('/data/cache', 160, 'b.png'))
        .assertEqual('/data/cache/EntryPhotos/160/b.png.jpg');
    })

    it('gateLetsLimitThroughImmediately', 0, async (): Promise<void> => {
      const gate = new DecodeGate(3);
      // 3 个名额内：全部立即拿到，不用等
      await gate.acquire();
      await gate.acquire();
      await gate.acquire();
      gate.release();
      gate.release();
      gate.release();
    })

    it('gateQueuesBeyondLimit', 0, async (): Promise<void> => {
      const gate = new DecodeGate(1);
      await gate.acquire();
      let entered = false;
      const queued = gate.acquire().then((): void => {
        entered = true;
        gate.release();
      });
      await tick();
      // 名额被占着：排队的还没进
      expect(entered).assertFalse();
      gate.release();
      await queued;
      expect(entered).assertTrue();
    })

    it('gateIsLifoNewcomerGoesFirst', 0, async (): Promise<void> => {
      const gate = new DecodeGate(1);
      await gate.acquire();
      const order: string[] = [];
      const b = gate.acquire().then((): void => {
        order.push('B');
        gate.release();
      });
      const c = gate.acquire().then((): void => {
        order.push('C');
        gate.release();
      });
      gate.release();
      // release 把名额交给排在最后的 C，不是队头 B；B 的 release 又同步
      // 唤醒 C 链下游，所以必须把两条都等完再验顺序
      await b;
      await c;
      expect(order.length).assertEqual(2);
      expect(order[0]).assertEqual('C');
      expect(order[1]).assertEqual('B');
    })

    it('gateCapsConcurrencyAtLimit', 0, async (): Promise<void> => {
      const gate = new DecodeGate(3);
      let running = 0;
      let peak = 0;
      const task = async (): Promise<void> => {
        await gate.acquire();
        running++;
        if (running > peak) {
          peak = running;
        }
        await tick();
        running--;
        gate.release();
      };
      const tasks: Array<Promise<void>> = [];
      for (let i = 0; i < 8; i++) {
        tasks.push(task());
      }
      await Promise.all(tasks);
      expect(peak).assertEqual(3);
    })
  })
}
