import { UIContext, curves } from '@kit.ArkUI';
import { DownloadInfo } from './EhDownloadStore';

export interface DownloadReorderRect {
  gid: number;
  x: number;
  y: number;
  width: number;
  height: number;
}

export function nearestDownloadSlot(rects: DownloadReorderRect[], x: number, y: number): number {
  let best = 0;
  let distance = Number.POSITIVE_INFINITY;
  for (const rect of rects) {
    const delta = (rect.x - x) ** 2 + (rect.y - y) ** 2;
    if (delta < distance) {
      distance = delta;
      best = rect.gid;
    }
  }
  return best;
}

// WaterFlow has no native onMove. Keep one in-memory permutation during the
// drag, animate the actual layout change, then persist only a successful drop.
export class DownloadReorderController {
  private visible: Set<number> = new Set();
  private original: DownloadInfo[] = [];
  private preview: DownloadInfo[] = [];
  private source: number = 0;
  private context: UIContext | undefined = undefined;
  private publish: (items: DownloadInfo[]) => void = () => {};
  private scroll: (dy: number) => void = () => {};
  private offsetX: number = 0;
  private offsetY: number = 0;
  private pointerX: number = 0;
  private pointerY: number = 0;
  private lastMove: number = 0;
  private locked: DownloadReorderRect | undefined = undefined;
  private scrollTimer: number = -1;
  private scrollStep: number = 0;

  markVisible(gid: number, visible: boolean): void {
    if (visible) this.visible.add(gid);
    else this.visible.delete(gid);
  }

  start(items: DownloadInfo[], gid: number, event: DragEvent, context: UIContext,
    publish: (items: DownloadInfo[]) => void, scroll: (dy: number) => void): void {
    this.cancel();
    this.original = items.slice();
    this.preview = items.slice();
    this.source = gid;
    this.context = context;
    this.publish = publish;
    this.scroll = scroll;
    const rect = this.rect(gid);
    this.offsetX = rect === undefined ? 0 : event.getWindowX() - rect.x;
    this.offsetY = rect === undefined ? 0 : event.getWindowY() - rect.y;
    this.lastMove = 0;
  }

  move(event: DragEvent): void {
    if (this.source <= 0) return;
    this.pointerX = event.getWindowX();
    this.pointerY = event.getWindowY();
    this.updateAutoScroll();
    this.movePointer(false);
  }

  finish(event: DragEvent): number[] | undefined {
    if (this.source <= 0) {
      event.setResult(DragResult.DRAG_FAILED);
      return undefined;
    }
    this.pointerX = event.getWindowX();
    this.pointerY = event.getWindowY();
    this.movePointer(true);
    const order = this.preview.map((item: DownloadInfo): number => item.gid);
    this.reset();
    event.setResult(DragResult.DRAG_SUCCESSFUL);
    return order;
  }

  cancel(restore: boolean = true): void {
    if (this.source > 0 && restore) this.publish(this.original);
    this.reset();
  }

  private reset(): void {
    if (this.scrollTimer >= 0) clearInterval(this.scrollTimer);
    this.scrollTimer = -1;
    this.scrollStep = 0;
    this.source = 0;
    this.context = undefined;
    this.locked = undefined;
    this.original = [];
    this.preview = [];
    this.publish = () => {};
    this.scroll = () => {};
  }

  private rect(gid: number): DownloadReorderRect | undefined {
    const context = this.context;
    if (context === undefined) return undefined;
    try {
      const box = context.getComponentUtils().getRectangleById('download-reorder-' + gid);
      if (box.size.width <= 0 || box.size.height <= 0) return undefined;
      return { gid: gid, x: context.px2vp(box.windowOffset.x), y: context.px2vp(box.windowOffset.y),
        width: context.px2vp(box.size.width), height: context.px2vp(box.size.height) };
    } catch (_error) { return undefined; }
  }

  private movePointer(force: boolean): void {
    const context = this.context;
    if (context === undefined || (!force && Date.now() - this.lastMove < 160)) return;
    const x = this.pointerX - this.offsetX;
    const y = this.pointerY - this.offsetY;
    const lock = this.locked;
    if (lock !== undefined && Math.abs(x - lock.x) < lock.width * 0.45 &&
      Math.abs(y - lock.y) < Math.min(lock.height * 0.35, 72)) return;
    const rects: DownloadReorderRect[] = [];
    this.visible.forEach((gid: number) => {
      const rect = this.rect(gid);
      if (rect !== undefined) rects.push(rect);
    });
    const target = nearestDownloadSlot(rects, x, y);
    const from = this.preview.findIndex((item: DownloadInfo): boolean => item.gid === this.source);
    const to = this.preview.findIndex((item: DownloadInfo): boolean => item.gid === target);
    if (from < 0 || to < 0 || from === to) return;
    const next = this.preview.slice();
    const item = next.splice(from, 1)[0];
    next.splice(to, 0, item);
    this.preview = next;
    this.locked = rects.find((rect: DownloadReorderRect): boolean => rect.gid === target);
    this.lastMove = Date.now();
    context.animateTo({ duration: 180, curve: curves.interpolatingSpring(0, 1, 280, 30) }, () => {
      this.publish(next);
    });
  }

  private updateAutoScroll(): void {
    const context = this.context;
    if (context === undefined) return;
    try {
      const box = context.getComponentUtils().getRectangleById('download-reorder-viewport');
      const top = context.px2vp(box.windowOffset.y);
      const bottom = top + context.px2vp(box.size.height);
      this.scrollStep = this.pointerY < top + 64 ? -10 : (this.pointerY > bottom - 64 ? 10 : 0);
    } catch (_error) { this.scrollStep = 0; }
    if (this.scrollStep !== 0 && this.scrollTimer < 0) {
      this.scrollTimer = setInterval(() => {
        this.locked = undefined;
        this.scroll(this.scrollStep);
        this.movePointer(false);
      }, 16);
    } else if (this.scrollStep === 0 && this.scrollTimer >= 0) {
      clearInterval(this.scrollTimer);
      this.scrollTimer = -1;
    }
  }
}
