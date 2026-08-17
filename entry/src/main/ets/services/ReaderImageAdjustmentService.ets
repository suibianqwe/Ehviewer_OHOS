import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import readerHdr from 'libreaderhdr.so';
import { ReaderImageAdjustmentSettings } from './ReaderImageAdjustmentSupport';

const TAG: string = 'ReaderImageAdjustment';
const DOMAIN: number = 0x3210;

interface AdjustmentEntry {
  key: string;
  sourcePath: string;
  sourcePixelMap: image.PixelMap | undefined;
  settings: ReaderImageAdjustmentSettings;
  bakeColorAdjustments: boolean;
  references: number;
  cancelled: boolean;
  pixelMap: image.PixelMap | undefined;
  pending: Promise<image.PixelMap | undefined> | undefined;
  completed: boolean;
}

interface AdjustmentTask {
  entry: AdjustmentEntry;
  resolve: (value: image.PixelMap | undefined) => void;
  priority: number;
  sequence: number;
}

class ReaderImageAdjustmentService {
  private entries: Map<string, AdjustmentEntry> = new Map<string, AdjustmentEntry>();
  private queue: AdjustmentTask[] = [];
  private activeTask: AdjustmentTask | undefined = undefined;
  private sequence: number = 0;

  acquire(key: string, sourcePath: string, settings: ReaderImageAdjustmentSettings,
    priority: number = 0, bakeColorAdjustments: boolean = false): Promise<image.PixelMap | undefined> {
    if ((!settings.requiresOfflineProcessing() && !bakeColorAdjustments) || !settings.enabled ||
      key.length === 0 || sourcePath.length === 0) {
      return Promise.resolve(undefined);
    }
    return this.acquireEntry(key, sourcePath, undefined, settings, priority, bakeColorAdjustments);
  }

  acquirePixelMap(key: string, sourcePixelMap: image.PixelMap, settings: ReaderImageAdjustmentSettings,
    priority: number = 0, bakeColorAdjustments: boolean = false): Promise<image.PixelMap | undefined> {
    if ((!settings.requiresOfflineProcessing() && !bakeColorAdjustments) || !settings.enabled || key.length === 0) {
      return Promise.resolve(undefined);
    }
    return this.acquireEntry(key, '', sourcePixelMap, settings, priority, bakeColorAdjustments);
  }

  updatePriority(key: string, priority: number): void {
    const task = this.queue.find((item: AdjustmentTask) => item.entry.key === key);
    if (task !== undefined && task.priority !== priority) {
      task.priority = priority;
      this.sortQueue();
    }
  }

  release(key: string): void {
    const entry = this.entries.get(key);
    if (entry === undefined) {
      return;
    }
    entry.references = Math.max(0, entry.references - 1);
    if (entry.references <= 0) {
      this.disposeEntry(entry);
    }
  }

  clear(): void {
    const values = Array.from(this.entries.values());
    for (let i = 0; i < values.length; i++) {
      this.disposeEntry(values[i]);
    }
  }

  private acquireEntry(key: string, sourcePath: string, sourcePixelMap: image.PixelMap | undefined,
    settings: ReaderImageAdjustmentSettings, priority: number,
    bakeColorAdjustments: boolean): Promise<image.PixelMap | undefined> {
    let entry = this.entries.get(key);
    if (entry === undefined || entry.sourcePath !== sourcePath ||
      entry.bakeColorAdjustments !== bakeColorAdjustments) {
      if (entry !== undefined) {
        this.disposeEntry(entry);
      }
      entry = {
        key: key,
        sourcePath: sourcePath,
        sourcePixelMap: sourcePixelMap,
        settings: settings,
        bakeColorAdjustments: bakeColorAdjustments,
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
    let resolver: (value: image.PixelMap | undefined) => void = () => {};
    entry.pending = new Promise<image.PixelMap | undefined>((resolve) => {
      resolver = resolve;
    });
    this.queue.push({ entry: entry, resolve: resolver, priority: Math.max(0, priority), sequence: this.sequence++ });
    this.sortQueue();
    this.processNext();
    return entry.pending;
  }

  private sortQueue(): void {
    this.queue.sort((left: AdjustmentTask, right: AdjustmentTask) => {
      return left.priority === right.priority ? right.sequence - left.sequence : left.priority - right.priority;
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
    this.process(task).finally(() => {
      this.activeTask = undefined;
      this.processNext();
    });
  }

  private async process(task: AdjustmentTask): Promise<void> {
    const entry = task.entry;
    let result: image.PixelMap | undefined = undefined;
    try {
      if (this.isActive(entry)) {
        result = await this.createAdjustedPixelMap(entry);
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `Image adjustment failed: ${String(error)}`);
    }
    if (result !== undefined && this.isActive(entry)) {
      entry.pixelMap = result;
    } else if (result !== undefined) {
      this.releasePixelMap(result);
    }
    entry.pending = undefined;
    entry.completed = true;
    task.resolve(entry.pixelMap);
    if (!this.isActive(entry)) {
      this.disposeEntry(entry);
    }
  }

  private async createAdjustedPixelMap(entry: AdjustmentEntry): Promise<image.PixelMap | undefined> {
    let source: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      if (entry.sourcePixelMap !== undefined) {
        const info = entry.sourcePixelMap.getImageInfoSync();
        if (info.isHdr || info.pixelFormat !== image.PixelMapFormat.RGBA_8888) {
          return undefined;
        }
        pixelMap = readerHdr.createCompatibleSdrPixelMap(entry.sourcePixelMap);
      } else {
        source = image.createImageSource(entry.sourcePath);
        const info = source.getImageInfoSync();
        const frames = await source.getFrameCount();
        if (frames !== 1 || info.mimeType.toLowerCase().indexOf('svg') >= 0) {
          return undefined;
        }
        pixelMap = await source.createPixelMap({
          editable: true,
          index: 0,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          desiredDynamicRange: image.DecodingDynamicRange.SDR
        });
      }
      if (!this.isActive(entry) || pixelMap.getImageInfoSync().pixelFormat !== image.PixelMapFormat.RGBA_8888) {
        return undefined;
      }
      const value = entry.settings;
      const result = await readerHdr.adjustPixelMap(pixelMap,
        entry.bakeColorAdjustments ? value.contrast : 0, value.clarity, value.sharpening,
        entry.bakeColorAdjustments ? value.exposure : 0,
        entry.bakeColorAdjustments ? value.brightness : 0,
        value.highlights, value.shadows,
        entry.bakeColorAdjustments ? value.hue : 0,
        entry.bakeColorAdjustments ? value.saturation : 0,
        value.vibrance,
        entry.bakeColorAdjustments ? value.temperature : 0,
        entry.bakeColorAdjustments ? value.grayscale : 0);
      if (result !== 0 || !this.isActive(entry)) {
        return undefined;
      }
      const adjusted = pixelMap;
      pixelMap = undefined;
      return adjusted;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `Create adjusted PixelMap failed: ${String(error)}`);
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

  private isActive(entry: AdjustmentEntry): boolean {
    return !entry.cancelled && entry.references > 0 && this.entries.get(entry.key) === entry;
  }

  private disposeEntry(entry: AdjustmentEntry): void {
    entry.cancelled = true;
    entry.references = 0;
    const index = this.queue.findIndex((task: AdjustmentTask) => task.entry === entry);
    if (index >= 0) {
      const task = this.queue.splice(index, 1)[0];
      entry.pending = undefined;
      task.resolve(undefined);
    }
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

export const readerImageAdjustmentService: ReaderImageAdjustmentService = new ReaderImageAdjustmentService();
