import { image, videoProcessingEngine } from '@kit.ImageKit';
import { imageSuperResolution, visionBase } from '@kit.CoreVisionKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import readerHdr from 'libreaderhdr.so';
import {
  coreVisionSuperResolutionAvailable,
  effectiveReaderSuperResolutionEngine,
  READER_SUPER_RESOLUTION_ENGINE_CORE_VISION,
  READER_SUPER_RESOLUTION_ENGINE_DETAIL
} from './ReaderSuperResolutionSupport';

const TAG = 'ReaderSuperResolution';
const DOMAIN = 0x3210;
const MIN_DIMENSION: number = 32;
const MEDIUM_MAX_DIMENSION: number = 3000;
// API 23+ accepts HIGH input dimensions from 180 px while HIGH output still starts at 512 px.
const HIGH_MIN_INPUT_DIMENSION: number = 180;
const HIGH_MIN_OUTPUT_DIMENSION: number = 512;
const HIGH_MAX_DIMENSION: number = 2000;
const SEGMENT_OVERLAP: number = 32;
const CORE_VISION_MAX_INPUT_DIMENSION: number = 3000;
const CORE_VISION_MAX_INPUT_PIXELS: number = 2500000;
const CORE_VISION_MAX_ASPECT_RATIO: number = 10;

interface ReaderSuperResolutionEntry {
  key: string;
  sourcePath: string;
  sourcePixelMap: image.PixelMap | undefined;
  ownsSourcePixelMap: boolean;
  engine: string;
  targetWidth: number;
  targetHeight: number;
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
  scale: number = 1;
  segmented: boolean = false;
  level: videoProcessingEngine.QualityLevel = videoProcessingEngine.QualityLevel.MEDIUM;
}

class ReaderSuperResolutionSegmentRegion {
  start: number = 0;
  end: number = 0;
}

class ReaderSuperResolutionService {
  private entries: Map<string, ReaderSuperResolutionEntry> = new Map<string, ReaderSuperResolutionEntry>();
  private queue: ReaderSuperResolutionTask[] = [];
  private activeTask: ReaderSuperResolutionTask | undefined = undefined;
  private nextSequence: number = 0;
  private processor: videoProcessingEngine.ImageProcessor | undefined = undefined;
  private environmentPromise: Promise<boolean> | undefined = undefined;
  private detailEnhancerUnavailable: boolean = false;
  private coreVisionAnalyzer: imageSuperResolution.ImageSRAnalyzer | undefined = undefined;
  private coreVisionAnalyzerPromise: Promise<boolean> | undefined = undefined;
  private coreVisionUnavailable: boolean = false;

  acquire(key: string, sourcePath: string, priority: number = 0,
    targetWidth: number = 0, targetHeight: number = 0,
    engine: string = READER_SUPER_RESOLUTION_ENGINE_DETAIL): Promise<image.PixelMap | undefined> {
    if (key.length === 0 || sourcePath.length === 0) {
      return Promise.resolve(undefined);
    }
    return this.acquireEntry(key, sourcePath, undefined, priority, targetWidth, targetHeight, engine);
  }

  acquirePixelMap(key: string, sourcePixelMap: image.PixelMap, priority: number = 0,
    targetWidth: number = 0, targetHeight: number = 0,
    engine: string = READER_SUPER_RESOLUTION_ENGINE_DETAIL): Promise<image.PixelMap | undefined> {
    if (key.length === 0) {
      return Promise.resolve(undefined);
    }
    const effectiveEngine = effectiveReaderSuperResolutionEngine(engine);
    const existing = this.entries.get(key);
    if (existing !== undefined && existing.sourcePath.length === 0 && existing.engine === effectiveEngine) {
      return this.acquireEntry(key, '', existing.sourcePixelMap, priority, targetWidth, targetHeight, engine, false);
    }
    try {
      const ownedSourcePixelMap = readerHdr.createCompatibleSdrPixelMap(sourcePixelMap);
      return this.acquireEntry(key, '', ownedSourcePixelMap, priority, targetWidth, targetHeight, engine, true);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `Copy adjusted image for super-resolution failed: ${String(error)}`);
      return Promise.resolve(undefined);
    }
  }

  private acquireEntry(key: string, sourcePath: string, sourcePixelMap: image.PixelMap | undefined,
    priority: number, targetWidth: number, targetHeight: number, engine: string,
    ownsSourcePixelMap: boolean = false): Promise<image.PixelMap | undefined> {
    const effectiveEngine = effectiveReaderSuperResolutionEngine(engine);
    let entry = this.entries.get(key);
    if (entry === undefined || entry.sourcePath !== sourcePath || entry.engine !== effectiveEngine) {
      if (entry !== undefined) {
        this.disposeEntry(entry);
      }
      entry = {
        key: key,
        sourcePath: sourcePath,
        sourcePixelMap: sourcePixelMap,
        ownsSourcePixelMap: ownsSourcePixelMap,
        engine: effectiveEngine,
        targetWidth: Math.max(0, Math.round(targetWidth)),
        targetHeight: Math.max(0, Math.round(targetHeight)),
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
      try {
        const outputInfo = pixelMap.getImageInfoSync();
        hilog.info(DOMAIN, TAG,
          `Image super-resolution succeeded: output=${outputInfo.size.width}x${outputInfo.size.height}, ` +
          `target=${entry.targetWidth}x${entry.targetHeight}`);
      } catch (_error) {
        hilog.info(DOMAIN, TAG, 'Image super-resolution succeeded');
      }
    } else if (pixelMap !== undefined) {
      this.releasePixelMap(pixelMap);
    }
    this.finishTask(task, entry.pixelMap);
  }

  private finishTask(task: ReaderSuperResolutionTask, pixelMap: image.PixelMap | undefined): void {
    const entry = task.entry;
    this.releaseOwnedSourcePixelMap(entry);
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
    if (this.detailEnhancerUnavailable) {
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
        this.detailEnhancerUnavailable = true;
        return false;
      }
      return true;
    } catch (error) {
      this.detailEnhancerUnavailable = true;
      hilog.warn(DOMAIN, TAG, `System image super-resolution is unavailable: ${String(error)}`);
      return false;
    }
  }

  private async ensureCoreVisionAnalyzer(): Promise<boolean> {
    if (this.coreVisionAnalyzer !== undefined) {
      return true;
    }
    if (this.coreVisionUnavailable || !coreVisionSuperResolutionAvailable()) {
      return false;
    }
    if (this.coreVisionAnalyzerPromise === undefined) {
      this.coreVisionAnalyzerPromise = this.initializeCoreVisionAnalyzer();
    }
    return this.coreVisionAnalyzerPromise;
  }

  private async initializeCoreVisionAnalyzer(): Promise<boolean> {
    try {
      this.coreVisionAnalyzer = await imageSuperResolution.ImageSRAnalyzer.create();
      if (this.coreVisionAnalyzer === undefined || this.coreVisionAnalyzer === null) {
        this.coreVisionUnavailable = true;
        return false;
      }
      return true;
    } catch (error) {
      this.coreVisionUnavailable = true;
      hilog.warn(DOMAIN, TAG, `Core Vision AI super-resolution is unavailable: ${String(error)}`);
      return false;
    }
  }

  private coreVisionInputSize(width: number, height: number): image.Size {
    const pixelScale = Math.sqrt(CORE_VISION_MAX_INPUT_PIXELS / Math.max(1, width * height));
    const dimensionScale = Math.min(CORE_VISION_MAX_INPUT_DIMENSION / Math.max(1, width),
      CORE_VISION_MAX_INPUT_DIMENSION / Math.max(1, height));
    const scale = Math.min(1, pixelScale, dimensionScale);
    return {
      width: Math.max(MIN_DIMENSION, Math.round(width * scale)),
      height: Math.max(MIN_DIMENSION, Math.round(height * scale))
    };
  }

  private async runCoreVisionEnhancement(source: image.ImageSource, sourceWidth: number, sourceHeight: number,
    plan: ReaderSuperResolutionPlan, entry: ReaderSuperResolutionEntry): Promise<image.PixelMap | undefined> {
    const aspectRatio = Math.max(sourceWidth / Math.max(1, sourceHeight),
      sourceHeight / Math.max(1, sourceWidth));
    if (aspectRatio > CORE_VISION_MAX_ASPECT_RATIO || !await this.ensureCoreVisionAnalyzer() ||
      !this.isEntryActive(entry)) {
      return undefined;
    }
    const analyzer = this.coreVisionAnalyzer;
    if (analyzer === undefined) {
      return undefined;
    }
    const inputSize = this.coreVisionInputSize(sourceWidth, sourceHeight);
    let inputPixelMap: image.PixelMap | undefined = undefined;
    let outputPixelMap: image.PixelMap | undefined = undefined;
    try {
      if (inputSize.width !== sourceWidth || inputSize.height !== sourceHeight) {
        inputPixelMap = await source.createPixelMap({
          editable: false,
          index: 0,
          desiredSize: inputSize,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          desiredDynamicRange: image.DecodingDynamicRange.SDR
        });
      } else {
        inputPixelMap = await source.createPixelMap({
          editable: false,
          index: 0,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          desiredDynamicRange: image.DecodingDynamicRange.SDR
        });
      }
      if (!this.isEntryActive(entry)) {
        return undefined;
      }
      const imageData: visionBase.ImageData = { pixelMap: inputPixelMap };
      const request: visionBase.Request = { inputData: imageData };
      const response = await analyzer.process(request);
      outputPixelMap = response.pixelMap;
      if (!this.isEntryActive(entry)) {
        return undefined;
      }
      const outputInfo = outputPixelMap.getImageInfoSync();
      if (outputInfo.size.width <= 0 || outputInfo.size.height <= 0) {
        return undefined;
      }
      if (outputInfo.size.width !== plan.width || outputInfo.size.height !== plan.height) {
        await outputPixelMap.scale(plan.width / outputInfo.size.width,
          plan.height / outputInfo.size.height, image.AntiAliasingLevel.HIGH);
      }
      // Core Vision returns a PixelMap backed by the remote AI service. The backing buffer can be
      // reused by the next queued request, so keeping it in the reader cache may turn an earlier
      // page black. Copy the scaled result into an app-owned DMA PixelMap before caching it.
      const result = readerHdr.createCompatibleSdrPixelMap(outputPixelMap);
      hilog.info(DOMAIN, TAG,
        `Core Vision AI super-resolution succeeded: input=${inputSize.width}x${inputSize.height}, ` +
        `output=${plan.width}x${plan.height}`);
      return result;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `Core Vision AI super-resolution failed: ${String(error)}`);
      return undefined;
    } finally {
      if (outputPixelMap !== undefined) {
        await this.releasePixelMap(outputPixelMap);
      }
      if (inputPixelMap !== undefined) {
        await this.releasePixelMap(inputPixelMap);
      }
    }
  }

  private async runCoreVisionPixelMapEnhancement(sourcePixelMap: image.PixelMap, sourceWidth: number,
    sourceHeight: number, plan: ReaderSuperResolutionPlan,
    entry: ReaderSuperResolutionEntry): Promise<image.PixelMap | undefined> {
    const aspectRatio = Math.max(sourceWidth / Math.max(1, sourceHeight),
      sourceHeight / Math.max(1, sourceWidth));
    if (aspectRatio > CORE_VISION_MAX_ASPECT_RATIO || !await this.ensureCoreVisionAnalyzer() ||
      !this.isEntryActive(entry)) {
      return undefined;
    }
    const analyzer = this.coreVisionAnalyzer;
    if (analyzer === undefined) {
      return undefined;
    }
    const inputSize = this.coreVisionInputSize(sourceWidth, sourceHeight);
    let ownedInput: image.PixelMap | undefined = undefined;
    let outputPixelMap: image.PixelMap | undefined = undefined;
    try {
      let inputPixelMap = sourcePixelMap;
      if (inputSize.width !== sourceWidth || inputSize.height !== sourceHeight) {
        ownedInput = await this.cloneRgbaPixelMap(sourcePixelMap);
        await ownedInput.scale(inputSize.width / sourceWidth, inputSize.height / sourceHeight,
          image.AntiAliasingLevel.HIGH);
        inputPixelMap = ownedInput;
      }
      if (!this.isEntryActive(entry)) {
        return undefined;
      }
      const imageData: visionBase.ImageData = { pixelMap: inputPixelMap };
      const request: visionBase.Request = { inputData: imageData };
      const response = await analyzer.process(request);
      outputPixelMap = response.pixelMap;
      if (!this.isEntryActive(entry)) {
        return undefined;
      }
      const outputInfo = outputPixelMap.getImageInfoSync();
      if (outputInfo.size.width <= 0 || outputInfo.size.height <= 0) {
        return undefined;
      }
      if (outputInfo.size.width !== plan.width || outputInfo.size.height !== plan.height) {
        await outputPixelMap.scale(plan.width / outputInfo.size.width,
          plan.height / outputInfo.size.height, image.AntiAliasingLevel.HIGH);
      }
      // Detach the cached result from Core Vision's reusable remote backing buffer.
      const result = readerHdr.createCompatibleSdrPixelMap(outputPixelMap);
      hilog.info(DOMAIN, TAG,
        `Core Vision AI super-resolution succeeded: input=${inputSize.width}x${inputSize.height}, ` +
        `output=${plan.width}x${plan.height}`);
      return result;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `Core Vision AI super-resolution failed: ${String(error)}`);
      return undefined;
    } finally {
      if (outputPixelMap !== undefined) {
        await this.releasePixelMap(outputPixelMap);
      }
      if (ownedInput !== undefined) {
        await this.releasePixelMap(ownedInput);
      }
    }
  }

  private async tightRgbaBuffer(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
    try {
      const info = pixelMap.getImageInfoSync();
      const width = info.size.width;
      const height = info.size.height;
      const rowBytes = width * 4;
      const stride = pixelMap.getBytesNumberPerRow();
      const sourceBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
      await pixelMap.readPixelsToBuffer(sourceBuffer);
      if (stride === rowBytes) {
        return sourceBuffer;
      }
      const source = new Uint8Array(sourceBuffer);
      const compactBuffer = new ArrayBuffer(rowBytes * height);
      const compact = new Uint8Array(compactBuffer);
      for (let row = 0; row < height; row++) {
        compact.set(source.subarray(row * stride, row * stride + rowBytes), row * rowBytes);
      }
      return compactBuffer;
    } catch (error) {
      throw new Error(`Read RGBA PixelMap failed: ${String(error)}`);
    }
  }

  private async cloneRgbaPixelMap(pixelMap: image.PixelMap): Promise<image.PixelMap> {
    try {
      const info = pixelMap.getImageInfoSync();
      const buffer = await this.tightRgbaBuffer(pixelMap);
      return await image.createPixelMapUsingAllocator(buffer, {
        editable: true,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        size: { width: info.size.width, height: info.size.height }
      }, image.AllocatorType.DMA);
    } catch (error) {
      throw new Error(`Clone RGBA PixelMap failed: ${String(error)}`);
    }
  }

  private enhancementPlan(width: number, height: number,
    targetWidth: number, targetHeight: number, engine: string): ReaderSuperResolutionPlan | null {
    if (width < MIN_DIMENSION || height < MIN_DIMENSION || width > MEDIUM_MAX_DIMENSION) {
      return null;
    }
    const hasDisplayTarget = targetWidth > 0 || targetHeight > 0;
    if (!hasDisplayTarget) {
      return null;
    }
    let scale = Math.max(1, targetWidth / width, targetHeight / height);
    scale = Math.min(scale, MEDIUM_MAX_DIMENSION / width);
    const outputWidth = Math.max(MIN_DIMENSION, Math.round(width * scale));
    const outputHeight = Math.max(MIN_DIMENSION, Math.round(height * scale));
    if (engine === READER_SUPER_RESOLUTION_ENGINE_CORE_VISION) {
      const coreVisionPlan = new ReaderSuperResolutionPlan();
      coreVisionPlan.width = outputWidth;
      coreVisionPlan.height = outputHeight;
      coreVisionPlan.scale = scale;
      return coreVisionPlan;
    }
    const highMinimumRegion = Math.max(HIGH_MIN_INPUT_DIMENSION,
      Math.ceil(HIGH_MIN_OUTPUT_DIMENSION / scale));
    const highMaximumRegion = Math.min(HIGH_MAX_DIMENSION, Math.floor(HIGH_MAX_DIMENSION / scale));
    const highQuality = width >= HIGH_MIN_INPUT_DIMENSION && height >= HIGH_MIN_INPUT_DIMENSION &&
      outputWidth >= HIGH_MIN_OUTPUT_DIMENSION && outputHeight >= HIGH_MIN_OUTPUT_DIMENSION &&
      highMinimumRegion <= highMaximumRegion;
    const highNeedsTiling = highQuality && (width > HIGH_MAX_DIMENSION || height > HIGH_MAX_DIMENSION ||
      outputWidth > HIGH_MAX_DIMENSION || outputHeight > HIGH_MAX_DIMENSION);
    const mediumNeedsTiling = width > MEDIUM_MAX_DIMENSION || height > MEDIUM_MAX_DIMENSION ||
      outputWidth > MEDIUM_MAX_DIMENSION || outputHeight > MEDIUM_MAX_DIMENSION;
    if (scale <= 1 && !highQuality) {
      return null;
    }
    const plan = new ReaderSuperResolutionPlan();
    plan.width = outputWidth;
    plan.height = outputHeight;
    plan.scale = scale;
    plan.segmented = highQuality ? highNeedsTiling : mediumNeedsTiling;
    plan.level = highQuality ? videoProcessingEngine.QualityLevel.HIGH :
      videoProcessingEngine.QualityLevel.MEDIUM;
    return plan;
  }

  private async enhanceSegmented(source: image.ImageSource, sourceWidth: number, sourceHeight: number,
    plan: ReaderSuperResolutionPlan, entry: ReaderSuperResolutionEntry): Promise<image.PixelMap | undefined> {
    if (this.processor === undefined) {
      return undefined;
    }
    const outputBuffer = new ArrayBuffer(plan.width * plan.height * 4);
    const outputPixels = new Uint8Array(outputBuffer);
    const highQuality = plan.level === videoProcessingEngine.QualityLevel.HIGH;
    const minimumInputDimension = highQuality ? HIGH_MIN_INPUT_DIMENSION : MIN_DIMENSION;
    const minimumOutputDimension = highQuality ? HIGH_MIN_OUTPUT_DIMENSION : MIN_DIMENSION;
    const maximumDimension = highQuality ? HIGH_MAX_DIMENSION : MEDIUM_MAX_DIMENSION;
    const minimumRegionDimension = Math.max(minimumInputDimension,
      Math.ceil(minimumOutputDimension / plan.scale));
    const maximumRegionDimension = Math.min(maximumDimension, Math.floor(maximumDimension / plan.scale));
    if (minimumRegionDimension > maximumRegionDimension) {
      return undefined;
    }
    const coreDimension = Math.max(minimumInputDimension,
      maximumRegionDimension - SEGMENT_OVERLAP * 2);
    let coreStartY = 0;
    while (coreStartY < sourceHeight) {
      if (!this.isEntryActive(entry)) {
        return undefined;
      }
      const coreEndY = Math.min(sourceHeight, coreStartY + coreDimension);
      const regionY = this.segmentRegion(coreStartY, coreEndY, sourceHeight, minimumRegionDimension);
      let coreStartX = 0;
      while (coreStartX < sourceWidth) {
        if (!this.isEntryActive(entry)) {
          return undefined;
        }
        const coreEndX = Math.min(sourceWidth, coreStartX + coreDimension);
        const regionX = this.segmentRegion(coreStartX, coreEndX, sourceWidth, minimumRegionDimension);
        const regionWidth = regionX.end - regionX.start;
        const regionHeight = regionY.end - regionY.start;
        const segmentTargetWidth = Math.max(minimumOutputDimension, Math.round(regionWidth * plan.scale));
        const segmentTargetHeight = Math.max(minimumOutputDimension, Math.round(regionHeight * plan.scale));
        let sourcePixelMap: image.PixelMap | undefined = undefined;
        let enhancedPixelMap: image.PixelMap | undefined = undefined;
        try {
          sourcePixelMap = await source.createPixelMapUsingAllocator({
            editable: false,
            index: 0,
            desiredRegion: {
              x: regionX.start,
              y: regionY.start,
              size: { width: regionWidth, height: regionHeight }
            },
            desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
            desiredDynamicRange: image.DecodingDynamicRange.SDR
          }, image.AllocatorType.DMA);
          enhancedPixelMap = await this.enhancePixelMap(sourcePixelMap, segmentTargetWidth,
            segmentTargetHeight, plan.level);
          const segmentInfo = enhancedPixelMap.getImageInfoSync();
          const segmentStride = enhancedPixelMap.getBytesNumberPerRow();
          const segmentBuffer = new ArrayBuffer(enhancedPixelMap.getPixelBytesNumber());
          await enhancedPixelMap.readPixelsToBuffer(segmentBuffer);
          const segmentPixels = new Uint8Array(segmentBuffer);
          const copyStartX = Math.max(0, Math.round((coreStartX - regionX.start) * plan.scale));
          const copyStartY = Math.max(0, Math.round((coreStartY - regionY.start) * plan.scale));
          const destinationX = Math.round(coreStartX * plan.scale);
          const destinationY = Math.round(coreStartY * plan.scale);
          const desiredCopyWidth = coreEndX >= sourceWidth ? plan.width - destinationX :
            Math.round((coreEndX - coreStartX) * plan.scale);
          const desiredCopyHeight = coreEndY >= sourceHeight ? plan.height - destinationY :
            Math.round((coreEndY - coreStartY) * plan.scale);
          const copyWidth = Math.max(0, Math.min(desiredCopyWidth,
            segmentInfo.size.width - copyStartX, plan.width - destinationX));
          const copyHeight = Math.max(0, Math.min(desiredCopyHeight,
            segmentInfo.size.height - copyStartY, plan.height - destinationY));
          const copyRowBytes = copyWidth * 4;
          const outputRowBytes = plan.width * 4;
          for (let row = 0; row < copyHeight; row++) {
            const sourceOffset = (copyStartY + row) * segmentStride + copyStartX * 4;
            const destinationOffset = (destinationY + row) * outputRowBytes + destinationX * 4;
            outputPixels.set(segmentPixels.subarray(sourceOffset, sourceOffset + copyRowBytes), destinationOffset);
          }
        } catch (error) {
          hilog.warn(DOMAIN, TAG, `Image super-resolution segment failed: ${String(error)}`);
          return undefined;
        } finally {
          if (enhancedPixelMap !== undefined) {
            await this.releasePixelMap(enhancedPixelMap);
          }
          if (sourcePixelMap !== undefined) {
            await this.releasePixelMap(sourcePixelMap);
          }
        }
        coreStartX = coreEndX;
      }
      coreStartY = coreEndY;
    }
    if (!this.isEntryActive(entry)) {
      return undefined;
    }
    try {
      return await image.createPixelMapUsingAllocator(outputBuffer, {
        editable: false,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        size: { width: plan.width, height: plan.height }
      }, image.AllocatorType.DMA);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `Image super-resolution stitching failed: ${String(error)}`);
      return undefined;
    }
  }

  private async enhanceSegmentedPixelMap(sourcePixelMap: image.PixelMap, sourceWidth: number,
    sourceHeight: number, plan: ReaderSuperResolutionPlan,
    entry: ReaderSuperResolutionEntry): Promise<image.PixelMap | undefined> {
    if (this.processor === undefined) {
      return undefined;
    }
    const sourceBuffer = await this.tightRgbaBuffer(sourcePixelMap);
    const sourcePixels = new Uint8Array(sourceBuffer);
    const sourceRowBytes = sourceWidth * 4;
    const outputBuffer = new ArrayBuffer(plan.width * plan.height * 4);
    const outputPixels = new Uint8Array(outputBuffer);
    const highQuality = plan.level === videoProcessingEngine.QualityLevel.HIGH;
    const minimumInputDimension = highQuality ? HIGH_MIN_INPUT_DIMENSION : MIN_DIMENSION;
    const minimumOutputDimension = highQuality ? HIGH_MIN_OUTPUT_DIMENSION : MIN_DIMENSION;
    const maximumDimension = highQuality ? HIGH_MAX_DIMENSION : MEDIUM_MAX_DIMENSION;
    const minimumRegionDimension = Math.max(minimumInputDimension,
      Math.ceil(minimumOutputDimension / plan.scale));
    const maximumRegionDimension = Math.min(maximumDimension, Math.floor(maximumDimension / plan.scale));
    if (minimumRegionDimension > maximumRegionDimension) {
      return undefined;
    }
    const coreDimension = Math.max(minimumInputDimension,
      maximumRegionDimension - SEGMENT_OVERLAP * 2);
    let coreStartY = 0;
    while (coreStartY < sourceHeight) {
      if (!this.isEntryActive(entry)) {
        return undefined;
      }
      const coreEndY = Math.min(sourceHeight, coreStartY + coreDimension);
      const regionY = this.segmentRegion(coreStartY, coreEndY, sourceHeight, minimumRegionDimension);
      let coreStartX = 0;
      while (coreStartX < sourceWidth) {
        if (!this.isEntryActive(entry)) {
          return undefined;
        }
        const coreEndX = Math.min(sourceWidth, coreStartX + coreDimension);
        const regionX = this.segmentRegion(coreStartX, coreEndX, sourceWidth, minimumRegionDimension);
        const regionWidth = regionX.end - regionX.start;
        const regionHeight = regionY.end - regionY.start;
        const regionRowBytes = regionWidth * 4;
        const regionBuffer = new ArrayBuffer(regionRowBytes * regionHeight);
        const regionPixels = new Uint8Array(regionBuffer);
        for (let row = 0; row < regionHeight; row++) {
          const sourceOffset = (regionY.start + row) * sourceRowBytes + regionX.start * 4;
          regionPixels.set(sourcePixels.subarray(sourceOffset, sourceOffset + regionRowBytes), row * regionRowBytes);
        }
        const segmentTargetWidth = Math.max(minimumOutputDimension, Math.round(regionWidth * plan.scale));
        const segmentTargetHeight = Math.max(minimumOutputDimension, Math.round(regionHeight * plan.scale));
        let regionPixelMap: image.PixelMap | undefined = undefined;
        let enhancedPixelMap: image.PixelMap | undefined = undefined;
        try {
          regionPixelMap = await image.createPixelMapUsingAllocator(regionBuffer, {
            editable: false,
            pixelFormat: image.PixelMapFormat.RGBA_8888,
            size: { width: regionWidth, height: regionHeight }
          }, image.AllocatorType.DMA);
          enhancedPixelMap = await this.enhancePixelMap(regionPixelMap, segmentTargetWidth,
            segmentTargetHeight, plan.level);
          const segmentInfo = enhancedPixelMap.getImageInfoSync();
          const segmentStride = enhancedPixelMap.getBytesNumberPerRow();
          const segmentBuffer = new ArrayBuffer(enhancedPixelMap.getPixelBytesNumber());
          await enhancedPixelMap.readPixelsToBuffer(segmentBuffer);
          const segmentPixels = new Uint8Array(segmentBuffer);
          const copyStartX = Math.max(0, Math.round((coreStartX - regionX.start) * plan.scale));
          const copyStartY = Math.max(0, Math.round((coreStartY - regionY.start) * plan.scale));
          const destinationX = Math.round(coreStartX * plan.scale);
          const destinationY = Math.round(coreStartY * plan.scale);
          const desiredCopyWidth = coreEndX >= sourceWidth ? plan.width - destinationX :
            Math.round((coreEndX - coreStartX) * plan.scale);
          const desiredCopyHeight = coreEndY >= sourceHeight ? plan.height - destinationY :
            Math.round((coreEndY - coreStartY) * plan.scale);
          const copyWidth = Math.max(0, Math.min(desiredCopyWidth,
            segmentInfo.size.width - copyStartX, plan.width - destinationX));
          const copyHeight = Math.max(0, Math.min(desiredCopyHeight,
            segmentInfo.size.height - copyStartY, plan.height - destinationY));
          const copyRowBytes = copyWidth * 4;
          const outputRowBytes = plan.width * 4;
          for (let row = 0; row < copyHeight; row++) {
            const sourceOffset = (copyStartY + row) * segmentStride + copyStartX * 4;
            const destinationOffset = (destinationY + row) * outputRowBytes + destinationX * 4;
            outputPixels.set(segmentPixels.subarray(sourceOffset, sourceOffset + copyRowBytes), destinationOffset);
          }
        } catch (error) {
          hilog.warn(DOMAIN, TAG, `Adjusted image super-resolution segment failed: ${String(error)}`);
          return undefined;
        } finally {
          if (enhancedPixelMap !== undefined) {
            await this.releasePixelMap(enhancedPixelMap);
          }
          if (regionPixelMap !== undefined) {
            await this.releasePixelMap(regionPixelMap);
          }
        }
        coreStartX = coreEndX;
      }
      coreStartY = coreEndY;
    }
    if (!this.isEntryActive(entry)) {
      return undefined;
    }
    try {
      return await image.createPixelMapUsingAllocator(outputBuffer, {
        editable: false,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        size: { width: plan.width, height: plan.height }
      }, image.AllocatorType.DMA);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `Adjusted image super-resolution stitching failed: ${String(error)}`);
      return undefined;
    }
  }

  private segmentRegion(coreStart: number, coreEnd: number, total: number,
    minimumDimension: number): ReaderSuperResolutionSegmentRegion {
    let start = Math.max(0, coreStart - SEGMENT_OVERLAP);
    let end = Math.min(total, coreEnd + SEGMENT_OVERLAP);
    if (end - start < minimumDimension) {
      start = Math.max(0, Math.min(start, total - minimumDimension));
      end = Math.min(total, Math.max(end, start + minimumDimension));
      start = Math.max(0, end - minimumDimension);
    }
    const region = new ReaderSuperResolutionSegmentRegion();
    region.start = start;
    region.end = end;
    return region;
  }

  private async enhancePixelMap(sourcePixelMap: image.PixelMap, width: number, height: number,
    level: videoProcessingEngine.QualityLevel): Promise<image.PixelMap> {
    if (this.processor === undefined) {
      throw new Error('Image processor is unavailable');
    }
    try {
      return await this.processor.enhanceDetail(sourcePixelMap, width, height, level);
    } catch (error) {
      if (level !== videoProcessingEngine.QualityLevel.HIGH) {
        throw new Error(String(error));
      }
      hilog.warn(DOMAIN, TAG, `HIGH super-resolution failed, retrying MEDIUM: ${String(error)}`);
      try {
        return await this.processor.enhanceDetail(sourcePixelMap, width, height,
          videoProcessingEngine.QualityLevel.MEDIUM);
      } catch (fallbackError) {
        throw new Error(String(fallbackError));
      }
    }
  }

  private async runPixelMapEnhancement(entry: ReaderSuperResolutionEntry,
    sourcePixelMap: image.PixelMap): Promise<image.PixelMap | undefined> {
    try {
      const sourceInfo = sourcePixelMap.getImageInfoSync();
      if (sourceInfo.isHdr || sourceInfo.pixelFormat !== image.PixelMapFormat.RGBA_8888) {
        return undefined;
      }
      let plan = this.enhancementPlan(sourceInfo.size.width, sourceInfo.size.height,
        entry.targetWidth, entry.targetHeight, entry.engine);
      if (plan === null) {
        hilog.info(DOMAIN, TAG,
          `Adjusted image super-resolution skipped: source=${sourceInfo.size.width}x${sourceInfo.size.height}, ` +
          `target=${entry.targetWidth}x${entry.targetHeight}`);
        return undefined;
      }
      hilog.info(DOMAIN, TAG,
        `Adjusted image super-resolution started: source=${sourceInfo.size.width}x${sourceInfo.size.height}, ` +
        `target=${entry.targetWidth}x${entry.targetHeight}, output=${plan.width}x${plan.height}, ` +
        `scale=${plan.scale.toFixed(3)}, engine=${entry.engine}, quality=${plan.level}, segmented=${plan.segmented}`);
      if (entry.engine === READER_SUPER_RESOLUTION_ENGINE_CORE_VISION) {
        const coreVisionResult = await this.runCoreVisionPixelMapEnhancement(sourcePixelMap,
          sourceInfo.size.width, sourceInfo.size.height, plan, entry);
        if (coreVisionResult !== undefined) {
          return coreVisionResult;
        }
        if (!this.isEntryActive(entry)) {
          return undefined;
        }
        hilog.warn(DOMAIN, TAG, 'Core Vision AI failed; falling back to the detail enhancer');
        plan = this.enhancementPlan(sourceInfo.size.width, sourceInfo.size.height,
          entry.targetWidth, entry.targetHeight, READER_SUPER_RESOLUTION_ENGINE_DETAIL);
        if (plan === null) {
          return undefined;
        }
      }
      if (!this.isEntryActive(entry) || !await this.ensureProcessor() || this.processor === undefined) {
        return undefined;
      }
      if (plan.segmented) {
        return await this.enhanceSegmentedPixelMap(sourcePixelMap, sourceInfo.size.width,
          sourceInfo.size.height, plan, entry);
      }
      return await this.enhancePixelMap(sourcePixelMap, plan.width, plan.height, plan.level);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `Adjusted image super-resolution failed: ${String(error)}`);
      return undefined;
    }
  }

  private async runEnhancement(entry: ReaderSuperResolutionEntry): Promise<image.PixelMap | undefined> {
    if (entry.sourcePixelMap !== undefined) {
      return await this.runPixelMapEnhancement(entry, entry.sourcePixelMap);
    }
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
      let plan = this.enhancementPlan(sourceInfo.size.width, sourceInfo.size.height,
        entry.targetWidth, entry.targetHeight, entry.engine);
      if (plan === null) {
        hilog.info(DOMAIN, TAG, `Image super-resolution skipped: source=${sourceInfo.size.width}x${sourceInfo.size.height}, ` +
          `target=${entry.targetWidth}x${entry.targetHeight}`);
        return undefined;
      }
      hilog.info(DOMAIN, TAG, `Image super-resolution started: source=${sourceInfo.size.width}x${sourceInfo.size.height}, ` +
        `target=${entry.targetWidth}x${entry.targetHeight}, output=${plan.width}x${plan.height}, ` +
        `scale=${plan.scale.toFixed(3)}, engine=${entry.engine}, quality=${plan.level}, segmented=${plan.segmented}`);
      if (entry.engine === READER_SUPER_RESOLUTION_ENGINE_CORE_VISION) {
        const coreVisionResult = await this.runCoreVisionEnhancement(source, sourceInfo.size.width,
          sourceInfo.size.height, plan, entry);
        if (coreVisionResult !== undefined) {
          return coreVisionResult;
        }
        if (!this.isEntryActive(entry)) {
          return undefined;
        }
        hilog.warn(DOMAIN, TAG, 'Core Vision AI failed; falling back to the detail enhancer');
        plan = this.enhancementPlan(sourceInfo.size.width, sourceInfo.size.height,
          entry.targetWidth, entry.targetHeight, READER_SUPER_RESOLUTION_ENGINE_DETAIL);
        if (plan === null) {
          return undefined;
        }
      }
      if (!this.isEntryActive(entry) || !await this.ensureProcessor() ||
        this.processor === undefined) {
        return undefined;
      }
      if (plan.segmented) {
        return await this.enhanceSegmented(source, sourceInfo.size.width, sourceInfo.size.height, plan, entry);
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
      return await this.enhancePixelMap(sourcePixelMap, plan.width, plan.height, plan.level);
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
    if (this.activeTask === undefined || this.activeTask.entry !== entry) {
      this.releaseOwnedSourcePixelMap(entry);
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

  private releaseOwnedSourcePixelMap(entry: ReaderSuperResolutionEntry): void {
    if (!entry.ownsSourcePixelMap || entry.sourcePixelMap === undefined) {
      return;
    }
    this.releasePixelMap(entry.sourcePixelMap);
    entry.sourcePixelMap = undefined;
    entry.ownsSourcePixelMap = false;
  }
}

export const readerSuperResolutionService: ReaderSuperResolutionService = new ReaderSuperResolutionService();
