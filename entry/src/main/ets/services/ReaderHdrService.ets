import { colorSpaceManager } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import readerHdr from 'libreaderhdr.so';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'ReaderHdrService';
const DOMAIN = 0x3210;
const MAX_QUEUE_SIZE = 3;

interface ReaderHdrCacheEntry {
  key: string;
  sourcePath: string;
  references: number;
  cancelled: boolean;
  pixelMap: image.PixelMap | undefined;
  enqueued: boolean;
  conversionDone: boolean;
}

interface ReaderHdrQueueTask {
  entry: ReaderHdrCacheEntry;
  resolveTask: (value: image.PixelMap | undefined) => void;
  priority: number;
}

class ReaderHdrService {
  private entries: Map<string, ReaderHdrCacheEntry> = new Map<string, ReaderHdrCacheEntry>();
  private queue: ReaderHdrQueueTask[] = [];
  private processing: boolean = false;
  private nextPriority: number = 0;
  private capabilityKnown: boolean = false;
  private capabilitySupported: boolean = false;
  private hlgColorSpace: colorSpaceManager.ColorSpaceManager | undefined = undefined;

  acquire(key: string, sourcePath: string): Promise<image.PixelMap | undefined> {
    if (key.length === 0 || sourcePath.length === 0 || !this.isSupported()) {
      return Promise.resolve(undefined);
    }
    let entry = this.entries.get(key);
    if (entry === undefined || entry.sourcePath !== sourcePath) {
      if (entry !== undefined) {
        this.disposeEntry(entry);
      }
      entry = {
        key: key,
        sourcePath: sourcePath,
        references: 0,
        cancelled: false,
        pixelMap: undefined,
        enqueued: false,
        conversionDone: false
      };
      this.entries.set(key, entry);
    }
    entry.references++;
    entry.cancelled = false;
    if (entry.conversionDone) {
      return Promise.resolve(entry.pixelMap);
    }
    if (entry.enqueued) {
      return Promise.resolve(undefined);
    }
    return this.enqueue(entry);
  }

  release(key: string): void {
    const entry = this.entries.get(key);
    if (entry === undefined) {
      return;
    }
    entry.references = Math.max(0, entry.references - 1);
    if (entry.references > 0) {
      return;
    }
    entry.cancelled = true;
    this.removeFromQueue(entry);
    if (entry.pixelMap !== undefined) {
      return;
    }
    this.entries.delete(key);
  }

  private removeFromQueue(entry: ReaderHdrCacheEntry): void {
    const index = this.queue.findIndex((task: ReaderHdrQueueTask) => task.entry === entry);
    if (index >= 0) {
      this.queue.splice(index, 1);
    }
  }

  private isSupported(): boolean {
    if (!this.capabilityKnown) {
      this.capabilityKnown = true;
      try {
        this.capabilitySupported = readerHdr.isSdrToHdrSupported();
      } catch (_error) {
        this.capabilitySupported = false;
      }
    }
    return this.capabilitySupported;
  }

  private enqueue(entry: ReaderHdrCacheEntry): Promise<image.PixelMap | undefined> {
    return new Promise<image.PixelMap | undefined>((resolve: (value: image.PixelMap | undefined) => void) => {
      entry.enqueued = true;
      const priority = this.nextPriority;
      this.nextPriority++;
      const task: ReaderHdrQueueTask = {
        entry: entry,
        resolveTask: resolve,
        priority: priority
      };
      if (this.queue.length < MAX_QUEUE_SIZE) {
        this.queue.push(task);
      } else {
        const lowest = this.findLowestPriorityNonProcessing();
        if (lowest >= 0) {
          this.queue[lowest].entry.enqueued = false;
          this.queue[lowest].resolveTask(undefined);
          this.queue[lowest] = task;
        } else {
          entry.enqueued = false;
          resolve(undefined);
          return;
        }
      }
      this.sortQueue();
      this.processNext();
    });
  }

  private findLowestPriorityNonProcessing(): number {
    let maxIndex = -1;
    let maxPriority = -1;
    for (let i = 0; i < this.queue.length; i++) {
      if (i === 0 && this.processing) {
        continue;
      }
      if (this.queue[i].priority > maxPriority) {
        maxPriority = this.queue[i].priority;
        maxIndex = i;
      }
    }
    return maxIndex;
  }

  private sortQueue(): void {
    if (this.processing && this.queue.length > 1) {
      const head = this.queue[0];
      const tail = this.queue.slice(1);
      tail.sort((a: ReaderHdrQueueTask, b: ReaderHdrQueueTask) => a.priority - b.priority);
      this.queue = [head].concat(tail);
    } else {
      this.queue.sort((a: ReaderHdrQueueTask, b: ReaderHdrQueueTask) => a.priority - b.priority);
    }
  }

  private processNext(): void {
    if (this.processing || this.queue.length === 0) {
      return;
    }
    const task = this.queue[0];
    this.processing = true;
    this.convert(task).then(() => {
      this.processing = false;
      this.cleanupCompleted();
      this.processNext();
    });
  }

  private async convert(task: ReaderHdrQueueTask): Promise<void> {
    const entry = task.entry;
    if (entry.cancelled || entry.references <= 0 || this.entries.get(entry.key) !== entry) {
      entry.enqueued = false;
      entry.conversionDone = true;
      task.resolveTask(undefined);
      this.cleanupCancelled();
      return;
    }
    const pixelMap = await this.runConversion(entry.sourcePath);
    entry.enqueued = false;
    entry.conversionDone = true;
    if (pixelMap !== undefined) {
      hilog.info(DOMAIN, TAG, `HDR conversion succeeded for key`);
      if (!entry.cancelled && entry.references > 0 && this.entries.get(entry.key) === entry) {
        entry.pixelMap = pixelMap;
      } else {
        this.releasePixelMap(pixelMap);
      }
    }
    task.resolveTask(entry.pixelMap);
  }

  private async runConversion(sourcePath: string): Promise<image.PixelMap | undefined> {
    let source: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      if (this.hlgColorSpace === undefined) {
        this.hlgColorSpace = colorSpaceManager.create(colorSpaceManager.ColorSpace.BT2020_HLG);
      }
      source = image.createImageSource(sourcePath);
      pixelMap = await source.createPixelMapUsingAllocator({
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredDynamicRange: image.DecodingDynamicRange.AUTO
      }, image.AllocatorType.DMA);
      const info = pixelMap.getImageInfoSync();
      if (info.size.width < 32 || info.size.height < 32 || info.size.width > 8880 || info.size.height > 8880) {
        return undefined;
      }
      pixelMap.setColorSpace(this.hlgColorSpace);
      await pixelMap.setMetadata(image.HdrMetadataKey.HDR_METADATA_TYPE,
        image.HdrMetadataType.ALTERNATE);
      const result = pixelMap;
      pixelMap = undefined;
      return result;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `SDR to HDR conversion error: ${JSON.stringify(error)}`);
      return undefined;
    } finally {
      if (pixelMap !== undefined) {
        this.releasePixelMap(pixelMap);
      }
      if (source !== undefined) {
        try {
          await source.release();
        } catch (_error) {
        }
      }
    }
  }

  private cleanupCompleted(): void {
    while (this.queue.length > 0) {
      const task = this.queue[0];
      if (task.entry.cancelled || task.entry.references <= 0) {
        this.queue.shift();
      } else {
        break;
      }
    }
  }

  private cleanupCancelled(): void {
    this.queue = this.queue.filter((task: ReaderHdrQueueTask) => !task.entry.cancelled && task.entry.references > 0);
  }

  private disposeEntry(entry: ReaderHdrCacheEntry): void {
    entry.references = 0;
    entry.cancelled = true;
    this.removeFromQueue(entry);
    if (entry.pixelMap !== undefined) {
      this.releasePixelMap(entry.pixelMap);
      entry.pixelMap = undefined;
    }
    this.entries.delete(entry.key);
  }

  private async releasePixelMap(pixelMap: image.PixelMap): Promise<void> {
    try {
      await pixelMap.release();
    } catch (_error) {
    }
  }
}

export const readerHdrService: ReaderHdrService = new ReaderHdrService();
