const GALLERY_CARD_ANCHOR_SETTLE_DELAY: number = 64;
const GALLERY_CARD_ANCHOR_EXPIRE_DELAY: number = 1000;

export class GalleryCardScrollAnchor {
  private anchorKey: string = '';
  private anchorColumnCount: number = 0;
  private anchorWindowY: number = 0;
  private measuredWindowY: number = 0;
  private restoreTimer: number = -1;
  private expireTimer: number = -1;

  capture(key: string, columnCount: number, windowY: number): void {
    this.clear();
    if (key.length === 0 || columnCount <= 0 || Number.isNaN(windowY)) {
      return;
    }
    this.anchorKey = key;
    this.anchorColumnCount = columnCount;
    this.anchorWindowY = windowY;
    this.measuredWindowY = windowY;
    this.expireTimer = setTimeout(() => {
      this.clear();
    }, GALLERY_CARD_ANCHOR_EXPIRE_DELAY) as number;
  }

  observe(key: string, columnCount: number, windowY: number, restore: (deltaY: number) => void): void {
    if (this.anchorKey.length === 0 || key !== this.anchorKey || columnCount <= 0 ||
      columnCount === this.anchorColumnCount || Number.isNaN(windowY)) {
      return;
    }
    this.measuredWindowY = windowY;
    if (this.restoreTimer !== -1) {
      clearTimeout(this.restoreTimer);
    }
    this.restoreTimer = setTimeout(() => {
      this.restoreTimer = -1;
      const deltaY = this.measuredWindowY - this.anchorWindowY;
      this.clear();
      if (Math.abs(deltaY) >= 0.5) {
        restore(deltaY);
      }
    }, GALLERY_CARD_ANCHOR_SETTLE_DELAY) as number;
  }

  clear(): void {
    if (this.restoreTimer !== -1) {
      clearTimeout(this.restoreTimer);
      this.restoreTimer = -1;
    }
    if (this.expireTimer !== -1) {
      clearTimeout(this.expireTimer);
      this.expireTimer = -1;
    }
    this.anchorKey = '';
    this.anchorColumnCount = 0;
    this.anchorWindowY = 0;
    this.measuredWindowY = 0;
  }
}
