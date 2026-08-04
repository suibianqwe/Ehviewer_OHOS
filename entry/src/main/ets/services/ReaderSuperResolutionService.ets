import { image, videoProcessingEngine } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'ReaderSuperResolution';
const DOMAIN = 0x3210;
const MIN_DIMENSION: number = 32;
const MEDIUM_MAX_DIMENSION: number = 3000;
const HIGH_MIN_DIMENSION: number = 512;
const HIGH_MAX_DIMENSION: number = 2000;
const MAX_SCALE: number = 2;
const MIN_USEFUL_SCALE: number = 1.05;

interface ReaderSuperResolutionEntry {
  key: string;
  sourcePath: string;
  references: number;
  cancelled: boolean;
  pixelMap: image.PixelMap | undefined;
  pending: Promise<image.PixelMap | undefined> | undefined;
  completed: boolean;
}

interface ReaderSuperResolutionTask {
  entry: ReaderSuperResolutionEntry;
  resolveTask: (value: image.PixelMap | undefined) => void;
  priority: number;
  sequence: number;
}

class ReaderSuperResolutionPlan {
  width: number = 0;
  height: number = 0;
  level: videoProcessingEngine.QualityLevel = videoProcessingEngine.QualityLevel.MEDIUM;
}

class ReaderSuperResolutionService {
  private entries: Map<string, ReaderSuperResolutionEntry> = new Map<string, ReaderSuperResolutionEntry>();
  private queue: ReaderSuperResolutionTask[] = [];
  private activeTask: ReaderSuperResolutionTask | undefined = undefined;
  private nextSequence: number = 0;
  private processor: videoProcessingEngine.ImageProcessor | undefined = undefined;
  private environmentPromise: Promise<boolean> | undefined = undefined;
  private capabilityUnavailable: boolean = false;

  acquire(key: string, sourcePath: string, priority: number = 0): Promise<image.PixelMap | undefined> {
    if (key.length === 0 || sourcePath.length === 0 || this.capabilityUnavailable) {
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
    const task = this.queue.find((item: ReaderSuperResolutionTask) => item.entry.key === key);
    if (task === undefined || task.priority === priority) {
      return;
    }
    task.priority = Math.max(0, priority);
    this.sortQueue();
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
    const entries = Array.from(this.entries.values());
    for (let i = 0; i < entries.length; i++) {
      this.disposeEntry(entries[i]);
    }
  }

  private enqueue(entry: ReaderSuperResolutionEntry, priority: number): Promise<image.PixelMap | undefined> {
    let resolveTask: (value: image.PixelMap | undefined) => void = (_value: image.PixelMap | undefined) => {};
    const pending = new Promise<image.PixelMap | undefined>((resolve: (value: image.PixelMap | undefined) => void) => {
      resolveTask = resolve;
    });
    entry.pending = pending;
    const task: ReaderSuperResolutionTask = {
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
    this.queue.sort((left: ReaderSuperResolutionTask, right: ReaderSuperResolutionTask) => {
      if (left.priority !== right.priority) {
        return left.priority - right.priority;
      }
      return right.sequence - left.sequence;
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
    this.process(task).then(() => {
      this.activeTask = undefined;
      this.processNext();
    }).catch((error: Error | Object | string) => {
      hilog.warn(DOMAIN, TAG, `Unexpected super-resolution queue error: ${String(error)}`);
      this.finishTask(task, undefined);
      this.activeTask = undefined;
      this.processNext();
    });
  }

  private async process(task: ReaderSuperResolutionTask): Promise<void> {
    const entry = task.entry;
    if (!this.isEntryActive(entry)) {
      this.finishTask(task, undefined);
      return;
    }
    const pixelMap = await this.runEnhancement(entry);
    if (pixelMap !== undefined && this.isEntryActive(entry)) {
      entry.pixelMap = pixelMap;
      hilog.info(DOMAIN, TAG, 'Image super-resolution succeeded');
    } else if (pixelMap !== undefined) {
      this.releasePixelMap(pixelMap);
    }
    this.finishTask(task, entry.pixelMap);
  }

  private finishTask(task: ReaderSuperResolutionTask, pixelMap: image.PixelMap | undefined): void {
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

  private isEntryActive(entry: ReaderSuperResolutionEntry): boolean {
    return !entry.cancelled && entry.references > 0 && this.entries.get(entry.key) === entry;
  }

  private async ensureProcessor(): Promise<boolean> {
    if (this.processor !== undefined) {
      return true;
    }
    if (this.capabilityUnavailable) {
      return false;
    }
    if (this.environmentPromise === undefined) {
      this.environmentPromise = this.initializeProcessor();
    }
    return this.environmentPromise;
  }

  private async initializeProcessor(): Promise<boolean> {
    try {
      await videoProcessingEngine.initializeEnvironment();
      this.processor = videoProcessingEngine.create();
      if (this.processor === undefined || this.processor === null) {
        this.capabilityUnavailable = true;
        return false;
      }
      return true;
    } catch (error) {
      this.capabilityUnavailable = true;
      hilog.warn(DOMAIN, TAG, `System image super-resolution is unavailable: ${String(error)}`);
      return false;
    }
  }

  private enhancementPlan(width: number, height: number): ReaderSuperResolutionPlan | null {
    if (width < MIN_DIMENSION || height < MIN_DIMENSION ||
      width > MEDIUM_MAX_DIMENSION || height > MEDIUM_MAX_DIMENSION) {
      return null;
    }
    const highQuality = width >= HIGH_MIN_DIMENSION && height >= HIGH_MIN_DIMENSION &&
      width <= HIGH_MAX_DIMENSION && height <= HIGH_MAX_DIMENSION;
    const maxDimension = highQuality ? HIGH_MAX_DIMENSION : MEDIUM_MAX_DIMENSION;
    const scale = Math.min(MAX_SCALE, maxDimension / width, maxDimension / height);
    if (scale < MIN_USEFUL_SCALE && !highQuality) {
      return null;
    }
    const plan = new ReaderSuperResolutionPlan();
    plan.width = Math.max(MIN_DIMENSION, Math.round(width * Math.max(1, scale)));
    plan.height = Math.max(MIN_DIMENSION, Math.round(height * Math.max(1, scale)));
    plan.level = highQuality ? videoProcessingEngine.QualityLevel.HIGH :
      videoProcessingEngine.QualityLevel.MEDIUM;
    return plan;
  }

  private async runEnhancement(entry: ReaderSuperResolutionEntry): Promise<image.PixelMap | undefined> {
    let source: image.ImageSource | undefined = undefined;
    let sourcePixelMap: image.PixelMap | undefined = undefined;
    try {
      source = image.createImageSource(entry.sourcePath);
      const sourceInfo = source.getImageInfoSync();
      const frameCount = await source.getFrameCount();
      const mimeType = sourceInfo.mimeType.toLowerCase();
      if (frameCount !== 1 || sourceInfo.isHdr || mimeType.indexOf('svg') >= 0) {
        return undefined;
      }
      const plan = this.enhancementPlan(sourceInfo.size.width, sourceInfo.size.height);
      if (plan === null || !this.isEntryActive(entry) || !await this.ensureProcessor() ||
        this.processor === undefined) {
        return undefined;
      }
      sourcePixelMap = await source.createPixelMapUsingAllocator({
        editable: false,
        index: 0,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredDynamicRange: image.DecodingDynamicRange.SDR
      }, image.AllocatorType.DMA);
      const pixelInfo = sourcePixelMap.getImageInfoSync();
      if (pixelInfo.isHdr || pixelInfo.pixelFormat !== image.PixelMapFormat.RGBA_8888 ||
        !this.isEntryActive(entry)) {
        return undefined;
      }
      return await this.processor.enhanceDetail(sourcePixelMap, plan.width, plan.height, plan.level);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `Image super-resolution failed: ${String(error)}`);
      return undefined;
    } finally {
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

  private removeFromQueue(entry: ReaderSuperResolutionEntry): void {
    const index = this.queue.findIndex((task: ReaderSuperResolutionTask) => task.entry === entry);
    if (index < 0) {
      return;
    }
    const task = this.queue.splice(index, 1)[0];
    entry.pending = undefined;
    task.resolveTask(undefined);
  }

  private disposeEntry(entry: ReaderSuperResolutionEntry): void {
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

export const readerSuperResolutionService: ReaderSuperResolutionService = new ReaderSuperResolutionService();
