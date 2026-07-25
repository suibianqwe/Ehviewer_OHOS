const GALLERY_CARD_ANCHOR_APPLY_DELAY: number = 0;
const GALLERY_CARD_ANCHOR_SETTLE_DELAY: number = 280;
const GALLERY_CARD_ANCHOR_EXPIRE_DELAY: number = 1200;

export class GalleryCardScrollAnchor {
  private anchorKey: string = '';
  private anchorColumnCount: number = 0;
  private anchorWindowY: number = 0;
  private measuredWindowY: number = 0;
  private applyTimer: number = -1;
  private settleTimer: number = -1;
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
    if (Math.abs(this.measuredWindowY - windowY) < 0.25) {
      return;
    }
    this.measuredWindowY = windowY;
    if (this.applyTimer === -1) {
      this.applyTimer = setTimeout(() => {
        this.applyTimer = -1;
        if (this.anchorKey.length === 0) {
          return;
        }
        const deltaY = this.measuredWindowY - this.anchorWindowY;
        if (Math.abs(deltaY) >= 0.5) {
          restore(deltaY);
        }
      }, GALLERY_CARD_ANCHOR_APPLY_DELAY) as number;
    }
    if (this.settleTimer !== -1) {
      clearTimeout(this.settleTimer);
    }
    this.settleTimer = setTimeout(() => {
      this.settleTimer = -1;
      this.clear();
    }, GALLERY_CARD_ANCHOR_SETTLE_DELAY) as number;
  }

  clear(): void {
    if (this.applyTimer !== -1) {
      clearTimeout(this.applyTimer);
      this.applyTimer = -1;
    }
    if (this.settleTimer !== -1) {
      clearTimeout(this.settleTimer);
      this.settleTimer = -1;
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
