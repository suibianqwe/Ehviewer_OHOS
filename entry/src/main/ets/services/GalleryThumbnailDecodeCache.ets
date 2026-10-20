import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';

const MAX_ACTIVE_DECODES: number = 2;
const MAX_PENDING_PREFETCHES: number = 32;
const MAX_IDLE_ENTRIES: number = 64;
const MAX_IDLE_BYTES: number = 24 * 1024 * 1024;
const MAX_DECODE_PIXELS: number = 4 * 1024 * 1024;

export class DecodedGalleryThumbnail {
  path: string = '';
  width: number = 0;
  height: number = 0;
  pixelMap: image.PixelMap | undefined = undefined;
  bytes: number = 0;
}

class ThumbnailEntry {
  key: string;
  path: string = '';
  references: number = 0;
  lastUse: number = 0;
  settled: boolean = false;
  retired: boolean = false;
  result: DecodedGalleryThumbnail | null = null;
  resolve: (result: DecodedGalleryThumbnail | null) => void = () => {};
  pending: Promise<DecodedGalleryThumbnail | null>;

  constructor(key: string) {
    this.key = key;
    this.pending = new Promise<DecodedGalleryThumbnail | null>((resolve) => {
      this.resolve = resolve;
    });
  }
}

// Each mounted Image owns a lease. LRU eviction never releases its PixelMap.
export class GalleryThumbnailLease {
  ready: DecodedGalleryThumbnail | null;
  pending: Promise<DecodedGalleryThumbnail | null>;
  private onRelease: () => void;
  private onInvalidate: () => void;
  private released: boolean = false;

  constructor(ready: DecodedGalleryThumbnail | null, pending: Promise<DecodedGalleryThumbnail | null>,
    onRelease: () => void, onInvalidate: () => void) {
    this.ready = ready;
    this.pending = pending;
    this.onRelease = onRelease;
    this.onInvalidate = onInvalidate;
  }

  invalidate(): void {
    if (!this.released) {
      this.onInvalidate();
    }
  }

  release(): void {
    if (!this.released) {
      this.released = true;
      this.onRelease();
    }
  }
}

export class GalleryThumbnailDecodeCache {
  private entries: Map<string, ThumbnailEntry> = new Map<string, ThumbnailEntry>();
  private queue: ThumbnailEntry[] = [];
  private activeDecodes: number = 0;
  private pumpScheduled: boolean = false;
  private useSequence: number = 0;

  acquire(key: string, loadPath: () => Promise<string>): GalleryThumbnailLease {
    const entry = this.obtain(key, loadPath);
    entry.references++;
    return new GalleryThumbnailLease(entry.result, entry.pending, () => {
      entry.references = Math.max(0, entry.references - 1);
      entry.lastUse = ++this.useSequence;
      if (entry.retired && entry.references === 0) {
        this.disposeResult(entry);
      }
      this.trim();
    }, () => {
      // Retire only this lease's entry. A late failure must not evict a newer retry.
      entry.retired = true;
      if (this.entries.get(key) === entry) {
        this.entries.delete(key);
      }
    });
  }

  prefetch(key: string, loadPath: () => Promise<string>): void {
    const existing = this.entries.get(key);
    if (existing !== undefined) {
      existing.lastUse = ++this.useSequence;
      return;
    }
    let pendingCount = 0;
    this.entries.forEach((entry: ThumbnailEntry) => {
      if (!entry.settled && entry.references === 0) {
        pendingCount++;
      }
    });
    if (pendingCount < MAX_PENDING_PREFETCHES) {
      this.obtain(key, loadPath);
    }
  }

  clear(): void {
    this.entries.forEach((entry: ThumbnailEntry) => {
      entry.retired = true;
      if (entry.references === 0) {
        this.disposeResult(entry);
        entry.resolve(null);
      }
    });
    this.entries.clear();
  }

  private obtain(key: string, loadPath: () => Promise<string>): ThumbnailEntry {
    let entry = this.entries.get(key);
    if (entry !== undefined) {
      entry.lastUse = ++this.useSequence;
      return entry;
    }
    entry = new ThumbnailEntry(key);
    entry.lastUse = ++this.useSequence;
    this.entries.set(key, entry);
    const request = entry;
    // Do not perform even a cache-path lookup from a component's build/appear stack.
    Promise.resolve().then(loadPath).then((path: string) => {
      if (path.length === 0 || (request.retired && request.references === 0)) {
        this.finish(request, null);
        return;
      }
      request.path = path;
      this.queue.push(request);
      this.schedulePump();
    }).catch(() => this.finish(request, null));
    return request;
  }

  private schedulePump(): void {
    if (this.pumpScheduled || this.queue.length === 0 || this.activeDecodes >= MAX_ACTIVE_DECODES) {
      return;
    }
    this.pumpScheduled = true;
    setTimeout(() => {
      this.pumpScheduled = false;
      // Mounted cards take priority over speculative offscreen work.
      this.queue.sort((left: ThumbnailEntry, right: ThumbnailEntry) =>
        (right.references > 0 ? 1 : 0) - (left.references > 0 ? 1 : 0) || left.lastUse - right.lastUse);
      while (this.activeDecodes < MAX_ACTIVE_DECODES && this.queue.length > 0) {
        const entry = this.queue.shift();
        if (entry === undefined) {
          break;
        }
        if (entry.retired && entry.references === 0) {
          this.finish(entry, null);
          continue;
        }
        this.activeDecodes++;
        this.decode(entry.path).then((result: DecodedGalleryThumbnail) => {
          this.finish(entry, result);
        }).catch(() => this.finish(entry, null)).finally(() => {
          this.activeDecodes--;
          this.schedulePump();
        });
      }
    }, 0);
  }

  private async decode(path: string): Promise<DecodedGalleryThumbnail> {
    const result = new DecodedGalleryThumbnail();
    result.path = path;
    let file: fs.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    try {
      const localPath = path.startsWith('file://') ? path.substring(7) : path;
      file = await fs.open(localPath, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      result.width = info.size.width;
      result.height = info.size.height;
      const frames = await source.getFrameCount();
      // Keep animations/vector rendering intact. Unusually large covers use ArkUI's
      // async, display-size-aware decode rather than allocating full-size PixelMaps.
      if (frames !== 1 || info.mimeType.toLowerCase().indexOf('svg') >= 0 ||
        info.size.width * info.size.height > MAX_DECODE_PIXELS) {
        return result;
      }
      result.pixelMap = await source.createPixelMap({
        editable: false,
        desiredDynamicRange: image.DecodingDynamicRange.AUTO
      });
      result.bytes = result.pixelMap.getPixelBytesNumber();
    } catch (_error) {
      // Preserve the normal asynchronous Image loader as a format/error fallback.
      if (result.pixelMap !== undefined) {
        await result.pixelMap.release().catch(() => {});
        result.pixelMap = undefined;
        result.bytes = 0;
      }
    } finally {
      if (source !== undefined) {
        await source.release().catch(() => {});
      }
      if (file !== undefined) {
        await fs.close(file).catch(() => {});
      }
    }
    return result;
  }

  private finish(entry: ThumbnailEntry, result: DecodedGalleryThumbnail | null): void {
    entry.result = result;
    entry.settled = true;
    entry.lastUse = ++this.useSequence;
    if (entry.retired && entry.references === 0) {
      this.disposeResult(entry);
      entry.resolve(null);
    } else {
      entry.resolve(result);
    }
    if (result === null && this.entries.get(entry.key) === entry) {
      this.entries.delete(entry.key);
    }
    this.trim();
  }

  private trim(): void {
    const idle: ThumbnailEntry[] = [];
    let bytes = 0;
    this.entries.forEach((entry: ThumbnailEntry) => {
      if (entry.settled && entry.references === 0) {
        idle.push(entry);
        bytes += entry.result === null ? 0 : entry.result.bytes;
      }
    });
    idle.sort((left: ThumbnailEntry, right: ThumbnailEntry) => left.lastUse - right.lastUse);
    let count = idle.length;
    for (let i = 0; i < idle.length && (count > MAX_IDLE_ENTRIES || bytes > MAX_IDLE_BYTES); i++) {
      const entry = idle[i];
      bytes -= entry.result === null ? 0 : entry.result.bytes;
      count--;
      this.entries.delete(entry.key);
      this.disposeResult(entry);
    }
  }

  private disposeResult(entry: ThumbnailEntry): void {
    const pixelMap = entry.result === null ? undefined : entry.result.pixelMap;
    entry.result = null;
    if (pixelMap !== undefined) {
      pixelMap.release().catch(() => {});
    }
  }
}

export const galleryThumbnailDecodeCache: GalleryThumbnailDecodeCache = new GalleryThumbnailDecodeCache();
