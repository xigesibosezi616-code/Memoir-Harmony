import nativeCurl from 'libbookcurl.so';

export class NativeCurl {
  static createSurface(surfaceId: bigint): boolean {
    return nativeCurl.createSurface(surfaceId);
  }

  static destroySurface(): void {
    nativeCurl.destroySurface();
  }

  static setPage(slot: number, width: number, height: number, pixels: ArrayBuffer): boolean {
    return nativeCurl.setPage(slot, width, height, pixels);
  }

  static setFrame(progress: number, direction: number, corner: number, paperColor: number): void {
    nativeCurl.setFrame(progress, direction, corner, paperColor);
  }

  static setSize(width: number, height: number): void {
    nativeCurl.setSize(width, height);
  }
}
