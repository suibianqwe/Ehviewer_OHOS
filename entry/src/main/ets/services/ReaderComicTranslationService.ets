import { common } from '@kit.AbilityKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { GalleryInfo } from '../model/GalleryModels';
import {
  ReaderPageTranslation,
  ReaderTranslationLine,
  ReaderTranslationPoint,
  cloneReaderPageTranslation
} from '../model/ReaderTranslationModels';
import { ehDownloadFileStore } from './EhDownloadFileStore';
import { ehHistoryStore } from './EhHistoryStore';
import { ehTranslationService } from './EhTranslationService';

interface ReaderComicTranslationTask {
  key: string;
  context: common.UIAbilityContext;
  gallery: GalleryInfo;
  pageIndex: number;
  imagePath: string;
  priority: number;
  force: boolean;
  sequence: number;
  resolve: (value: ReaderPageTranslation) => void;
  reject: (error: Error) => void;
}

interface ReaderComicTranslationPending {
  key: string;
  task: ReaderComicTranslationTask;
  promise: Promise<ReaderPageTranslation>;
}

interface OcrDecodeSize {
  width: number;
  height: number;
}

interface OcrBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface OcrLineCandidate {
  text: string;
  bounds: OcrBounds;
  vertical: boolean;
}

interface OcrTextGroup {
  lines: OcrLineCandidate[];
  bounds: OcrBounds;
  vertical: boolean;
}

const MAX_OCR_IMAGE_EDGE: number = 4096;
const READER_TRANSLATION_LAYOUT_VERSION: number = 2;

export class ReaderComicTranslationService {
  private queue: ReaderComicTranslationTask[] = [];
  private pending: ReaderComicTranslationPending[] = [];
  private running: boolean = false;
  private sequence: number = 0;
  private initialized: boolean = false;
  private initPromise: Promise<boolean> | null = null;

  async loadStored(context: common.UIAbilityContext, gallery: GalleryInfo,
    pageIndex: number): Promise<ReaderPageTranslation | null> {
    const downloaded = ehDownloadFileStore.getReaderTranslation(context, gallery, pageIndex);
    if (downloaded !== null && downloaded.layoutVersion === READER_TRANSLATION_LAYOUT_VERSION) {
      return downloaded;
    }
    await ehHistoryStore.ensureLoaded(context);
    const history = ehHistoryStore.getReaderTranslation(gallery.gid, pageIndex);
    return history !== null && history.layoutVersion === READER_TRANSLATION_LAYOUT_VERSION ? history : null;
  }

  request(context: common.UIAbilityContext, gallery: GalleryInfo, pageIndex: number, imagePath: string,
    priority: number, force: boolean = false): Promise<ReaderPageTranslation> {
    const baseKey = gallery.gid.toString() + ':' + pageIndex.toString() + ':' + imagePath;
    if (!force) {
      const existing = this.findPending(baseKey);
      if (existing !== null) {
        existing.task.priority = Math.max(existing.task.priority, priority);
        this.sortQueue();
        return existing.promise;
      }
    }
    const key = force ? baseKey + ':force:' + this.sequence.toString() : baseKey;
    let resolveTask: (value: ReaderPageTranslation) => void = (_value: ReaderPageTranslation) => {};
    let rejectTask: (error: Error) => void = (_error: Error) => {};
    const promise = new Promise<ReaderPageTranslation>((resolve: (value: ReaderPageTranslation) => void,
      reject: (error: Error) => void) => {
      resolveTask = resolve;
      rejectTask = reject;
    });
    const task: ReaderComicTranslationTask = {
      key: key,
      context: context,
      gallery: gallery,
      pageIndex: pageIndex,
      imagePath: imagePath,
      priority: priority,
      force: force,
      sequence: this.sequence++,
      resolve: resolveTask,
      reject: rejectTask
    };
    this.queue.push(task);
    this.pending.push({ key: baseKey, task: task, promise: promise });
    this.sortQueue();
    this.runNext();
    return promise;
  }

  private findPending(key: string): ReaderComicTranslationPending | null {
    for (let i = 0; i < this.pending.length; i++) {
      if (this.pending[i].key === key) {
        return this.pending[i];
      }
    }
    return null;
  }

  private sortQueue(): void {
    this.queue.sort((left: ReaderComicTranslationTask, right: ReaderComicTranslationTask) => {
      if (left.priority !== right.priority) {
        return right.priority - left.priority;
      }
      return left.sequence - right.sequence;
    });
  }

  private runNext(): void {
    if (this.running || this.queue.length === 0) {
      return;
    }
    const task = this.queue.shift();
    if (task === undefined) {
      return;
    }
    this.running = true;
    this.executeTask(task).then((translation: ReaderPageTranslation) => {
      task.resolve(cloneReaderPageTranslation(translation));
    }).catch((error: Error) => {
      task.reject(error);
    }).finally(() => {
      this.removePending(task);
      this.running = false;
      this.runNext();
    });
  }

  private removePending(task: ReaderComicTranslationTask): void {
    const next: ReaderComicTranslationPending[] = [];
    for (let i = 0; i < this.pending.length; i++) {
      if (this.pending[i].task !== task) {
        next.push(this.pending[i]);
      }
    }
    this.pending = next;
  }

  private async executeTask(task: ReaderComicTranslationTask): Promise<ReaderPageTranslation> {
    if (!task.force) {
      const stored = await this.loadStored(task.context, task.gallery, task.pageIndex);
      if (stored !== null) {
        return stored;
      }
    }
    await this.ensureInitialized();
    const translation = await this.recognizeAndTranslate(task.imagePath, task.pageIndex, task.priority);
    if (!ehDownloadFileStore.setReaderTranslation(task.context, task.gallery, translation)) {
      await ehHistoryStore.ensureLoaded(task.context);
      ehHistoryStore.setReaderTranslation(task.gallery.gid, translation);
    }
    return translation;
  }

  private async ensureInitialized(): Promise<void> {
    if (this.initialized) {
      return;
    }
    if (this.initPromise === null) {
      this.initPromise = textRecognition.init();
    }
    const ready = await this.initPromise;
    this.initPromise = null;
    if (!ready) {
      throw new Error('OCR service initialization failed');
    }
    this.initialized = true;
  }

  private async recognizeAndTranslate(path: string, pageIndex: number,
    priority: number): Promise<ReaderPageTranslation> {
    let imageSource: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      imageSource = image.createImageSource(path);
      const info = imageSource.getImageInfoSync();
      const size = ocrDecodeSize(info.size.width, info.size.height);
      pixelMap = await imageSource.createPixelMap({ desiredSize: { width: size.width, height: size.height } });
      let result: textRecognition.TextRecognitionResult;
      try {
        result = await textRecognition.recognizeText({ pixelMap: pixelMap },
          { isDirectionDetectionSupported: true });
      } catch (error) {
        throw new Error('OCR recognition failed: ' + String(error));
      }
      const lines = collectOcrLines(result.blocks);
      await Promise.all(lines.map(async (line: ReaderTranslationLine) => {
        const contentKind = line.isVertical === true ? 'vertical comic dialogue' : 'comic dialogue';
        line.translatedText = await ehTranslationService.translate(line.sourceText, contentKind, priority, true);
      }));
      return {
        pageIndex: pageIndex,
        imageWidth: size.width,
        imageHeight: size.height,
        lines: lines,
        updatedAt: Date.now(),
        layoutVersion: READER_TRANSLATION_LAYOUT_VERSION
      };
    } finally {
      if (pixelMap !== undefined) {
        try {
          pixelMap.release();
        } catch (error) {
        }
      }
      if (imageSource !== undefined) {
        try {
          await imageSource.release();
        } catch (error) {
        }
      }
    }
  }
}

function collectOcrLines(blocks: textRecognition.TextBlock[]): ReaderTranslationLine[] {
  const groups: OcrTextGroup[] = [];
  for (let i = 0; i < blocks.length; i++) {
    const lines: OcrLineCandidate[] = [];
    for (let j = 0; j < blocks[i].lines.length; j++) {
      const candidate = createOcrLineCandidate(blocks[i].lines[j]);
      if (candidate !== null) {
        lines.push(candidate);
      }
    }
    if (lines.length > 0) {
      groups.push(createOcrTextGroup(lines));
    }
  }
  mergeNearbyOcrTextGroups(groups);
  const result: ReaderTranslationLine[] = [];
  for (let i = 0; i < groups.length; i++) {
    const source = groupedOcrSource(groups[i]);
    if (source.length === 0) {
      continue;
    }
    result.push({
      sourceText: source,
      translatedText: '',
      cornerPoints: boundsCornerPoints(groups[i].bounds),
      isVertical: groups[i].vertical
    });
  }
  return result;
}

function createOcrLineCandidate(line: textRecognition.TextLine): OcrLineCandidate | null {
  const source = line.value.trim();
  if (source.length === 0 || line.cornerPoints.length < 2) {
    return null;
  }
  const points: ReaderTranslationPoint[] = [];
  for (let i = 0; i < line.cornerPoints.length; i++) {
    points.push({ x: line.cornerPoints[i].x, y: line.cornerPoints[i].y });
  }
  const bounds = pointsBounds(points);
  return {
    text: source,
    bounds: bounds,
    vertical: isVerticalOcrLine(line, bounds)
  };
}

function isVerticalOcrLine(line: textRecognition.TextLine, bounds: OcrBounds): boolean {
  if (line.words.length >= 2) {
    let minX = Number.MAX_VALUE;
    let maxX = -Number.MAX_VALUE;
    let minY = Number.MAX_VALUE;
    let maxY = -Number.MAX_VALUE;
    for (let i = 0; i < line.words.length; i++) {
      const center = wordCenter(line.words[i]);
      minX = Math.min(minX, center.x);
      maxX = Math.max(maxX, center.x);
      minY = Math.min(minY, center.y);
      maxY = Math.max(maxY, center.y);
    }
    if (maxX >= minX && maxY >= minY && Math.max(maxX - minX, maxY - minY) > 0) {
      return maxY - minY > (maxX - minX) * 1.15;
    }
  }
  return bounds.height > bounds.width * 1.35;
}

function wordCenter(word: textRecognition.TextWord): ReaderTranslationPoint {
  if (word.cornerPoints.length === 0) {
    return { x: 0, y: 0 };
  }
  let x = 0;
  let y = 0;
  for (let i = 0; i < word.cornerPoints.length; i++) {
    x += word.cornerPoints[i].x;
    y += word.cornerPoints[i].y;
  }
  return { x: x / word.cornerPoints.length, y: y / word.cornerPoints.length };
}

function createOcrTextGroup(lines: OcrLineCandidate[]): OcrTextGroup {
  let verticalWeight = 0;
  let totalWeight = 0;
  let bounds = lines[0].bounds;
  for (let i = 0; i < lines.length; i++) {
    const weight = Math.max(1, lines[i].text.length);
    totalWeight += weight;
    if (lines[i].vertical) {
      verticalWeight += weight;
    }
    if (i > 0) {
      bounds = unionOcrBounds(bounds, lines[i].bounds);
    }
  }
  return {
    lines: lines,
    bounds: bounds,
    vertical: verticalWeight > totalWeight / 2
  };
}

function mergeNearbyOcrTextGroups(groups: OcrTextGroup[]): void {
  let changed = true;
  while (changed) {
    changed = false;
    for (let i = 0; i < groups.length && !changed; i++) {
      for (let j = i + 1; j < groups.length; j++) {
        if (!shouldMergeOcrTextGroups(groups[i], groups[j])) {
          continue;
        }
        const lines: OcrLineCandidate[] = [];
        for (let k = 0; k < groups[i].lines.length; k++) {
          lines.push(groups[i].lines[k]);
        }
        for (let k = 0; k < groups[j].lines.length; k++) {
          lines.push(groups[j].lines[k]);
        }
        groups[i] = createOcrTextGroup(lines);
        groups.splice(j, 1);
        changed = true;
        break;
      }
    }
  }
}

function shouldMergeOcrTextGroups(left: OcrTextGroup, right: OcrTextGroup): boolean {
  if (left.vertical !== right.vertical) {
    return false;
  }
  const xOverlap = axisOverlap(left.bounds.x, left.bounds.width, right.bounds.x, right.bounds.width);
  const yOverlap = axisOverlap(left.bounds.y, left.bounds.height, right.bounds.y, right.bounds.height);
  const xOverlapRatio = xOverlap / Math.max(1, Math.min(left.bounds.width, right.bounds.width));
  const yOverlapRatio = yOverlap / Math.max(1, Math.min(left.bounds.height, right.bounds.height));
  const xGap = axisGap(left.bounds.x, left.bounds.width, right.bounds.x, right.bounds.width);
  const yGap = axisGap(left.bounds.y, left.bounds.height, right.bounds.y, right.bounds.height);
  const thickness = Math.max(groupAverageThickness(left), groupAverageThickness(right));
  if (xOverlapRatio >= 0.25 && yOverlapRatio >= 0.25) {
    return true;
  }
  if (left.vertical) {
    const sameColumnFragments = xOverlapRatio >= 0.55 && yGap <= thickness * 1.1;
    const neighboringColumns = yOverlapRatio >= 0.55 && xGap <= thickness * 1.1;
    return sameColumnFragments || neighboringColumns;
  }
  const sameRowFragments = yOverlapRatio >= 0.55 && xGap <= thickness * 1.1;
  const neighboringRows = xOverlapRatio >= 0.55 && yGap <= thickness * 1.1;
  return sameRowFragments || neighboringRows;
}

function groupAverageThickness(group: OcrTextGroup): number {
  let total = 0;
  for (let i = 0; i < group.lines.length; i++) {
    total += group.vertical ? group.lines[i].bounds.width : group.lines[i].bounds.height;
  }
  return total / Math.max(1, group.lines.length);
}

function groupedOcrSource(group: OcrTextGroup): string {
  const lines: OcrLineCandidate[] = [];
  for (let i = 0; i < group.lines.length; i++) {
    lines.push(group.lines[i]);
  }
  const tolerance = Math.max(1, groupAverageThickness(group) * 0.65);
  lines.sort((left: OcrLineCandidate, right: OcrLineCandidate) => {
    const leftCenterX = left.bounds.x + left.bounds.width / 2;
    const rightCenterX = right.bounds.x + right.bounds.width / 2;
    const leftCenterY = left.bounds.y + left.bounds.height / 2;
    const rightCenterY = right.bounds.y + right.bounds.height / 2;
    if (group.vertical) {
      if (Math.abs(leftCenterX - rightCenterX) <= tolerance) {
        return leftCenterY - rightCenterY;
      }
      return rightCenterX - leftCenterX;
    }
    if (Math.abs(leftCenterY - rightCenterY) <= tolerance) {
      return leftCenterX - rightCenterX;
    }
    return leftCenterY - rightCenterY;
  });
  const values: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    values.push(normalizeOcrLineText(lines[i].text, group.vertical));
  }
  return values.join('\n').trim();
}

function normalizeOcrLineText(value: string, vertical: boolean): string {
  const text = value.trim();
  if (vertical && /[\u3040-\u30ff\u3400-\u9fff]/.test(text)) {
    return text.replace(/\s+/g, '');
  }
  return text.replace(/[ \t]+/g, ' ');
}

function pointsBounds(points: ReaderTranslationPoint[]): OcrBounds {
  let minX = points[0].x;
  let maxX = points[0].x;
  let minY = points[0].y;
  let maxY = points[0].y;
  for (let i = 1; i < points.length; i++) {
    minX = Math.min(minX, points[i].x);
    maxX = Math.max(maxX, points[i].x);
    minY = Math.min(minY, points[i].y);
    maxY = Math.max(maxY, points[i].y);
  }
  return { x: minX, y: minY, width: Math.max(1, maxX - minX), height: Math.max(1, maxY - minY) };
}

function unionOcrBounds(left: OcrBounds, right: OcrBounds): OcrBounds {
  const x = Math.min(left.x, right.x);
  const y = Math.min(left.y, right.y);
  return {
    x: x,
    y: y,
    width: Math.max(left.x + left.width, right.x + right.width) - x,
    height: Math.max(left.y + left.height, right.y + right.height) - y
  };
}

function boundsCornerPoints(bounds: OcrBounds): ReaderTranslationPoint[] {
  return [
    { x: bounds.x, y: bounds.y },
    { x: bounds.x + bounds.width, y: bounds.y },
    { x: bounds.x + bounds.width, y: bounds.y + bounds.height },
    { x: bounds.x, y: bounds.y + bounds.height }
  ];
}

function axisOverlap(leftStart: number, leftSize: number, rightStart: number, rightSize: number): number {
  return Math.max(0, Math.min(leftStart + leftSize, rightStart + rightSize) - Math.max(leftStart, rightStart));
}

function axisGap(leftStart: number, leftSize: number, rightStart: number, rightSize: number): number {
  if (leftStart + leftSize < rightStart) {
    return rightStart - leftStart - leftSize;
  }
  if (rightStart + rightSize < leftStart) {
    return leftStart - rightStart - rightSize;
  }
  return 0;
}

function ocrDecodeSize(width: number, height: number): OcrDecodeSize {
  if (width <= 0 || height <= 0) {
    throw new Error('OCR image size is invalid');
  }
  const edge = Math.max(width, height);
  if (edge <= MAX_OCR_IMAGE_EDGE) {
    return { width: width, height: height };
  }
  const scale = MAX_OCR_IMAGE_EDGE / edge;
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale))
  };
}

export const readerComicTranslationService: ReaderComicTranslationService = new ReaderComicTranslationService();
