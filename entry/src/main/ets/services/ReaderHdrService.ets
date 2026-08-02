import { colorSpaceManager } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import readerHdr from 'libreaderhdr.so';

const TAG = 'ReaderHdrService';
const DOMAIN = 0x3210;

interface ReaderHdrCacheEntry {
  key: string;
  sourcePath: string;
  references: number;
  cancelled: boolean;
  pixelMap: image.PixelMap | undefined;
  pending: Promise<image.PixelMap | undefined> | undefined;
  completed: boolean;
}

interface ReaderHdrQueueTask {
  entry: ReaderHdrCacheEntry;
  resolveTask: (value: image.PixelMap | undefined) => void;
  priority: number;
  sequence: number;
}

class ReaderHdrService {
  private entries: Map<string, ReaderHdrCacheEntry> = new Map<string, ReaderHdrCacheEntry>();
  private queue: ReaderHdrQueueTask[] = [];
  private activeTask: ReaderHdrQueueTask | undefined = undefined;
  private nextSequence: number = 0;
  private capabilityKnown: boolean = false;
  private capabilitySupported: boolean = false;
  private srgbColorSpace: colorSpaceManager.ColorSpaceManager | undefined = undefined;
  private hlgColorSpace: colorSpaceManager.ColorSpaceManager | undefined = undefined;

  acquire(key: string, sourcePath: string, priority: number = 0): Promise<image.PixelMap | undefined> {
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
        pending: undefined,
        completed: false
      };
      this.entries.set(key, entry);
    }
    entry.references++;
    entry.cancelled = false;
    if (entry.completed) {
      return Promise.resolve(entry.pixelMap);
    }
    if (entry.pending !== undefined) {
      this.updatePriority(key, priority);
      return entry.pending;
    }
    return this.enqueue(entry, priority);
  }

  updatePriority(key: string, priority: number): void {
    const task = this.queue.find((item: ReaderHdrQueueTask) => item.entry.key === key);
    if (task === undefined || task.priority === priority) {
      return;
    }
    task.priority = priority;
    this.sortQueue();
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
    this.disposeEntry(entry);
  }

  clear(): void {
    const entries = Array.from(this.entries.values());
    for (let i = 0; i < entries.length; i++) {
      this.disposeEntry(entries[i]);
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

  private enqueue(entry: ReaderHdrCacheEntry, priority: number): Promise<image.PixelMap | undefined> {
    let resolveTask: (value: image.PixelMap | undefined) => void = (_value: image.PixelMap | undefined) => {};
    const pending = new Promise<image.PixelMap | undefined>((resolve: (value: image.PixelMap | undefined) => void) => {
      resolveTask = resolve;
    });
    entry.pending = pending;
    const task: ReaderHdrQueueTask = {
      entry: entry,
      resolveTask: resolveTask,
      priority: Math.max(0, priority),
      sequence: this.nextSequence++
    };
    this.queue.push(task);
    this.sortQueue();
    this.processNext();
    return pending;
  }

  private sortQueue(): void {
    this.queue.sort((a: ReaderHdrQueueTask, b: ReaderHdrQueueTask) => {
      if (a.priority !== b.priority) {
        return a.priority - b.priority;
      }
      return b.sequence - a.sequence;
    });
  }

  private processNext(): void {
    if (this.activeTask !== undefined || this.queue.length === 0) {
      return;
    }
    const task = this.queue.shift();
    if (task === undefined) {
      return;
    }
    this.activeTask = task;
    this.convert(task).then(() => {
      this.activeTask = undefined;
      this.processNext();
    }).catch((error: Error | Object | string) => {
      hilog.warn(DOMAIN, TAG, `Unexpected HDR queue error: ${String(error)}`);
      this.finishTask(task, undefined);
      this.activeTask = undefined;
      this.processNext();
    });
  }

  private async convert(task: ReaderHdrQueueTask): Promise<void> {
    const entry = task.entry;
    if (!this.isEntryActive(entry)) {
      this.finishTask(task, undefined);
      return;
    }
    const pixelMap = await this.runConversion(entry);
    if (pixelMap !== undefined && this.isEntryActive(entry)) {
      entry.pixelMap = pixelMap;
      hilog.info(DOMAIN, TAG, 'HDR conversion succeeded');
    } else if (pixelMap !== undefined) {
      this.releasePixelMap(pixelMap);
    }
    this.finishTask(task, entry.pixelMap);
  }

  private finishTask(task: ReaderHdrQueueTask, pixelMap: image.PixelMap | undefined): void {
    const entry = task.entry;
    entry.pending = undefined;
    entry.completed = true;
    task.resolveTask(pixelMap);
    if (entry.cancelled || entry.references <= 0 || this.entries.get(entry.key) !== entry) {
      if (entry.pixelMap !== undefined) {
        this.releasePixelMap(entry.pixelMap);
        entry.pixelMap = undefined;
      }
      if (this.entries.get(entry.key) === entry) {
        this.entries.delete(entry.key);
      }
    }
  }

  private isEntryActive(entry: ReaderHdrCacheEntry): boolean {
    return !entry.cancelled && entry.references > 0 && this.entries.get(entry.key) === entry;
  }

  private async runConversion(entry: ReaderHdrCacheEntry): Promise<image.PixelMap | undefined> {
    let source: image.ImageSource | undefined = undefined;
    let sourcePixelMap: image.PixelMap | undefined = undefined;
    let destinationPixelMap: image.PixelMap | undefined = undefined;
    try {
      source = image.createImageSource(entry.sourcePath);
      const sourceInfo = source.getImageInfoSync();
      const frameCount = await source.getFrameCount();
      if (frameCount !== 1) {
        hilog.info(DOMAIN, TAG, `Skip multi-frame image, frames=${frameCount}`);
        return undefined;
      }
      const mimeType = sourceInfo.mimeType.toLowerCase();
      if (mimeType.indexOf('svg') >= 0) {
        hilog.info(DOMAIN, TAG, 'Skip SVG image because DMA decoding is unsupported');
        return undefined;
      }
      if (sourceInfo.size.width < 32 || sourceInfo.size.height < 32 ||
        sourceInfo.size.width > 8880 || sourceInfo.size.height > 8880) {
        return undefined;
      }
      if (!this.isEntryActive(entry)) {
        return undefined;
      }
      if (sourceInfo.isHdr) {
        sourcePixelMap = await source.createPixelMapUsingAllocator({
          editable: false,
          index: 0,
          desiredDynamicRange: image.DecodingDynamicRange.AUTO
        }, image.AllocatorType.DMA);
        if (!sourcePixelMap.getImageInfoSync().isHdr) {
          return undefined;
        }
        const existingHdr = sourcePixelMap;
        sourcePixelMap = undefined;
        return existingHdr;
      }
      if (this.srgbColorSpace === undefined) {
        this.srgbColorSpace = colorSpaceManager.create(colorSpaceManager.ColorSpace.SRGB);
      }
      if (this.hlgColorSpace === undefined) {
        this.hlgColorSpace = colorSpaceManager.create(colorSpaceManager.ColorSpace.BT2020_HLG);
      }
      sourcePixelMap = await source.createPixelMapUsingAllocator({
        editable: false,
        index: 0,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredColorSpace: this.srgbColorSpace,
        desiredDynamicRange: image.DecodingDynamicRange.SDR
      }, image.AllocatorType.DMA);
      const decodedInfo = sourcePixelMap.getImageInfoSync();
      if (decodedInfo.pixelFormat !== image.PixelMapFormat.RGBA_8888 || decodedInfo.isHdr ||
        !this.isEntryActive(entry)) {
        return undefined;
      }
      sourcePixelMap.setColorSpace(this.srgbColorSpace);
      await sourcePixelMap.setMetadata(image.HdrMetadataKey.HDR_METADATA_TYPE, image.HdrMetadataType.NONE);
      destinationPixelMap = image.createPixelMapUsingAllocatorSync({
        size: decodedInfo.size,
        pixelFormat: image.PixelMapFormat.RGBA_1010102,
        editable: true,
        alphaType: decodedInfo.alphaType
      }, image.AllocatorType.DMA);
      destinationPixelMap.setColorSpace(this.hlgColorSpace);
      await destinationPixelMap.setMetadata(image.HdrMetadataKey.HDR_METADATA_TYPE,
        image.HdrMetadataType.ALTERNATE);
      if (!this.isEntryActive(entry)) {
        return undefined;
      }
      const result = await readerHdr.convertSdrToHdr(sourcePixelMap, destinationPixelMap);
      if (result !== 0) {
        hilog.warn(DOMAIN, TAG, `SDR to HDR conversion failed, result=${result}, mime=${mimeType}`);
        return undefined;
      }
      const convertedInfo = destinationPixelMap.getImageInfoSync();
      if (convertedInfo.pixelFormat !== image.PixelMapFormat.RGBA_1010102) {
        hilog.warn(DOMAIN, TAG, `Unexpected HDR output format: ${convertedInfo.pixelFormat}`);
        return undefined;
      }
      const converted = destinationPixelMap;
      destinationPixelMap = undefined;
      return converted;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `SDR to HDR conversion error: ${String(error)}`);
      return undefined;
    } finally {
      if (destinationPixelMap !== undefined) {
        this.releasePixelMap(destinationPixelMap);
      }
      if (sourcePixelMap !== undefined) {
        this.releasePixelMap(sourcePixelMap);
      }
      if (source !== undefined) {
        try {
          await source.release();
        } catch (_error) {
        }
      }
    }
  }

  private removeFromQueue(entry: ReaderHdrCacheEntry): void {
    const index = this.queue.findIndex((task: ReaderHdrQueueTask) => task.entry === entry);
    if (index < 0) {
      return;
    }
    const task = this.queue.splice(index, 1)[0];
    entry.pending = undefined;
    task.resolveTask(undefined);
  }

  private disposeEntry(entry: ReaderHdrCacheEntry): void {
    entry.references = 0;
    entry.cancelled = true;
    this.removeFromQueue(entry);
    if (entry.pixelMap !== undefined) {
      this.releasePixelMap(entry.pixelMap);
      entry.pixelMap = undefined;
    }
    if (this.entries.get(entry.key) === entry) {
      this.entries.delete(entry.key);
    }
  }

  private async releasePixelMap(pixelMap: image.PixelMap): Promise<void> {
    try {
      await pixelMap.release();
    } catch (_error) {
    }
  }
}

export const readerHdrService: ReaderHdrService = new ReaderHdrService();
