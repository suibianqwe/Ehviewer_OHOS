export const READER_VISIBLE_IMAGE_PRIORITY: number = 200;
export const READER_PREFETCH_IMAGE_PRIORITY: number = 80;

export class ReaderImageDemand {
  galleryId: number;
  index: number;
  indexes: number[];
  priority: number;
  cancelled: boolean = false;
  pinned: boolean = false;
  onChange: () => void = () => {};
  abort: () => void = () => {};

  constructor(galleryId: number, index: number, priority: number) {
    this.galleryId = galleryId;
    this.index = index;
    this.indexes = [index];
    this.priority = priority;
  }
}

// Only reading requests participate. Explicit saves/downloads sharing the same
// cache entry can pin a demand, and must not be cancelled by page navigation.
export class ReaderImageRequestControl {
  private sequence: number = 0;
  private owner: number = -1;
  private galleryId: number = 0;
  private visible: number[] = [];
  private first: number = 0;
  private last: number = -1;
  private demands: ReaderImageDemand[] = [];

  createOwner(): number {
    return ++this.sequence;
  }

  update(owner: number, galleryId: number, visible: number[], preloadCount: number): void {
    if (this.owner > owner) {
      return;
    }
    this.owner = owner;
    this.galleryId = galleryId;
    this.visible = visible.slice();
    const anchor = visible.length > 0 ? Math.min(...visible) : 0;
    const end = visible.length > 0 ? Math.max(...visible) : anchor;
    this.first = Math.max(0, anchor - preloadCount);
    this.last = Math.max(end, anchor + preloadCount);
    this.refresh();
  }

  clear(owner: number): void {
    if (this.owner !== owner) {
      return;
    }
    this.galleryId = 0;
    this.visible = [];
    this.last = -1;
    this.refresh();
    this.owner = -1;
  }

  wants(owner: number, index: number): boolean {
    return this.owner === owner && index >= this.first && index <= this.last;
  }

  acquire(pageUrl: string, priority: number): ReaderImageDemand | undefined {
    const match = /^https?:\/\/[^/]+\/s\/[^/]+\/(\d+)-(\d+)(?:[?#]|$)/i.exec(pageUrl);
    if (match === null || this.owner < 0) {
      return undefined;
    }
    const demand = new ReaderImageDemand(Number(match[1]), Number(match[2]) - 1, priority);
    this.demands.push(demand);
    this.refreshDemand(demand);
    return demand;
  }

  release(demand: ReaderImageDemand | undefined): void {
    if (demand === undefined) {
      return;
    }
    const index = this.demands.indexOf(demand);
    if (index >= 0) {
      this.demands.splice(index, 1);
    }
    demand.onChange = () => {};
    demand.abort = () => {};
  }

  attach(demand: ReaderImageDemand, pageUrl: string): void {
    const match = /^https?:\/\/[^/]+\/s\/[^/]+\/(\d+)-(\d+)(?:[?#]|$)/i.exec(pageUrl);
    if (match === null || demand.cancelled) {
      return;
    }
    if (Number(match[1]) !== demand.galleryId) {
      demand.pinned = true;
      return;
    }
    const index = Number(match[2]) - 1;
    if (demand.indexes.indexOf(index) < 0) {
      demand.indexes.push(index);
    }
    this.refreshDemand(demand);
  }

  private refresh(): void {
    for (const demand of this.demands.slice()) {
      this.refreshDemand(demand);
    }
  }

  private refreshDemand(demand: ReaderImageDemand): void {
    if (demand.cancelled || demand.pinned) {
      return;
    }
    const wanted = demand.indexes.filter((index: number) => index >= this.first && index <= this.last);
    if (demand.galleryId !== this.galleryId || wanted.length === 0) {
      demand.cancelled = true;
      console.info('ReaderImageQueue: cancel out-of-window page=' + (demand.index + 1).toString());
      demand.onChange();
      demand.abort();
      return;
    }
    const visible = wanted.find((index: number) => this.visible.indexOf(index) >= 0);
    demand.index = visible === undefined ? wanted[0] : visible;
    demand.priority = visible !== undefined ?
      READER_VISIBLE_IMAGE_PRIORITY : READER_PREFETCH_IMAGE_PRIORITY;
    demand.onChange();
  }
}

export const readerImageRequestControl: ReaderImageRequestControl = new ReaderImageRequestControl();
