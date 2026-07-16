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
import { ehTranslationService, TranslationCancellationToken } from './EhTranslationService';
import { readerOcrDebugLog } from './ReaderOcrDebugLog';

interface ReaderComicTranslationTask {
  key: string;
  context: common.UIAbilityContext;
  gallery: GalleryInfo;
  pageIndex: number;
  imagePath: string;
  priority: number;
  force: boolean;
  scope: string;
  cancellationToken: TranslationCancellationToken;
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
  blockIndex: number;
  lineIndex: number;
  fontSize: number;
}

interface OcrTextGroup {
  lines: OcrLineCandidate[];
  bounds: OcrBounds;
  vertical: boolean;
}

const MAX_OCR_IMAGE_EDGE: number = 4096;
const MAX_CONCURRENT_OCR_TASKS: number = 1;
const READER_TRANSLATION_LAYOUT_VERSION: number = 8;
const READER_TRANSLATION_CANCELLED_MESSAGE: string = 'Reader translation request cancelled';

export class ReaderComicTranslationService {
  private queue: ReaderComicTranslationTask[] = [];
  private pending: ReaderComicTranslationPending[] = [];
  private activeOcrTasks: number = 0;
  private sequence: number = 0;
  private scopeSequence: number = 0;
  private cancelledScopes: string[] = [];
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
    priority: number, force: boolean = false, scope: string = ''): Promise<ReaderPageTranslation> {
    const taskScope = scope.length > 0 ? scope : this.beginScope();
    if (this.isScopeCancelled(taskScope)) {
      return Promise.reject(new Error(READER_TRANSLATION_CANCELLED_MESSAGE));
    }
    const baseKey = gallery.gid.toString() + ':' + pageIndex.toString() + ':' + imagePath;
    if (!force) {
      const existing = this.findPending(baseKey, taskScope);
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
      scope: taskScope,
      cancellationToken: new TranslationCancellationToken(),
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

  beginScope(): string {
    return 'reader-translation:' + (this.scopeSequence++).toString();
  }

  promote(scope: string, pageIndex: number, priority: number): void {
    if (scope.length === 0) {
      return;
    }
    for (let i = 0; i < this.pending.length; i++) {
      const task = this.pending[i].task;
      if (task.scope === scope && task.pageIndex === pageIndex && priority > task.priority) {
        task.priority = priority;
      }
    }
    this.sortQueue();
  }

  cancelScope(scope: string): void {
    if (scope.length === 0 || this.isScopeCancelled(scope)) {
      return;
    }
    this.cancelledScopes.push(scope);
    for (let i = this.queue.length - 1; i >= 0; i--) {
      const task = this.queue[i];
      if (task.scope !== scope) {
        continue;
      }
      this.queue.splice(i, 1);
      task.cancellationToken.cancel();
      task.reject(new Error(READER_TRANSLATION_CANCELLED_MESSAGE));
      this.removePending(task);
    }
    for (let i = 0; i < this.pending.length; i++) {
      if (this.pending[i].task.scope === scope) {
        this.pending[i].task.cancellationToken.cancel();
      }
    }
  }

  private findPending(key: string, scope: string): ReaderComicTranslationPending | null {
    for (let i = 0; i < this.pending.length; i++) {
      if (this.pending[i].key === key && this.pending[i].task.scope === scope) {
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
    while (this.activeOcrTasks < MAX_CONCURRENT_OCR_TASKS && this.queue.length > 0) {
      const task = this.queue.shift();
      if (task === undefined) {
        return;
      }
      if (this.isScopeCancelled(task.scope)) {
        task.cancellationToken.cancel();
        task.reject(new Error(READER_TRANSLATION_CANCELLED_MESSAGE));
        this.removePending(task);
        continue;
      }
      this.activeOcrTasks++;
      this.executeTask(task).then((translation: ReaderPageTranslation) => {
        task.resolve(cloneReaderPageTranslation(translation));
      }).catch((error: Error) => {
        task.reject(error);
      }).finally(() => {
        this.removePending(task);
        this.activeOcrTasks = Math.max(0, this.activeOcrTasks - 1);
        this.runNext();
      });
    }
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
    this.ensureTaskActive(task);
    if (!task.force) {
      const stored = await this.loadStored(task.context, task.gallery, task.pageIndex);
      this.ensureTaskActive(task);
      if (stored !== null) {
        return stored;
      }
    }
    await this.ensureInitialized();
    this.ensureTaskActive(task);
    const translation = await this.recognizeAndTranslate(task);
    this.ensureTaskActive(task);
    if (!ehDownloadFileStore.setReaderTranslation(task.context, task.gallery, translation)) {
      await ehHistoryStore.ensureLoaded(task.context);
      this.ensureTaskActive(task);
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

  private async recognizeAndTranslate(task: ReaderComicTranslationTask): Promise<ReaderPageTranslation> {
    let imageSource: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    const debug: string[] = [];
    debug.push('图片路径：' + task.imagePath);
    debug.push('强制刷新：' + task.force.toString());
    try {
      this.ensureTaskActive(task);
      imageSource = image.createImageSource(task.imagePath);
      const info = imageSource.getImageInfoSync();
      const size = ocrDecodeSize(info.size.width, info.size.height);
      debug.push('原图尺寸：' + info.size.width.toString() + 'x' + info.size.height.toString());
      debug.push('OCR尺寸：' + size.width.toString() + 'x' + size.height.toString());
      pixelMap = await imageSource.createPixelMap({ desiredSize: { width: size.width, height: size.height } });
      let result: textRecognition.TextRecognitionResult;
      try {
        result = await textRecognition.recognizeText({ pixelMap: pixelMap },
          { isDirectionDetectionSupported: true });
      } catch (error) {
        throw new Error('OCR recognition failed: ' + String(error));
      }
      this.ensureTaskActive(task);
      debug.push('OCR块数量：' + result.blocks.length.toString());
      const lines = collectOcrLines(result.blocks, debug);
      await Promise.all(lines.map(async (line: ReaderTranslationLine) => {
        this.ensureTaskActive(task);
        const contentKind = line.isVertical === true ? 'vertical comic dialogue' : 'comic dialogue';
        line.translatedText = await ehTranslationService.translate(line.sourceText, contentKind, task.priority, true,
          true, task.force, task.cancellationToken);
      }));
      this.ensureTaskActive(task);
      debug.push('[最终翻译]');
      for (let i = 0; i < lines.length; i++) {
        debug.push((i + 1).toString() + '. 原文=' + JSON.stringify(lines[i].sourceText));
        debug.push('   译文=' + JSON.stringify(lines[i].translatedText));
        debug.push('   方向=' + (lines[i].isVertical === true ? '竖排' : '横排') + '，框=' +
          formatOcrPointsBounds(lines[i].cornerPoints));
      }
      const translation: ReaderPageTranslation = {
        pageIndex: task.pageIndex,
        imageWidth: size.width,
        imageHeight: size.height,
        lines: lines,
        updatedAt: Date.now(),
        layoutVersion: READER_TRANSLATION_LAYOUT_VERSION
      };
      readerOcrDebugLog.recordRecognition(task.context, task.gallery.gid, task.pageIndex, debug.join('\n'));
      return translation;
    } catch (error) {
      debug.push('[失败] ' + String(error));
      if (!this.isScopeCancelled(task.scope)) {
        readerOcrDebugLog.recordRecognition(task.context, task.gallery.gid, task.pageIndex, debug.join('\n'));
      }
      throw error instanceof Error ? error : new Error(String(error));
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

  private ensureTaskActive(task: ReaderComicTranslationTask): void {
    if (this.isScopeCancelled(task.scope)) {
      throw new Error(READER_TRANSLATION_CANCELLED_MESSAGE);
    }
    task.cancellationToken.throwIfCancelled();
  }

  private isScopeCancelled(scope: string): boolean {
    return this.cancelledScopes.indexOf(scope) >= 0;
  }

}

function collectOcrLines(blocks: textRecognition.TextBlock[], debug: string[]): ReaderTranslationLine[] {
  const groups: OcrTextGroup[] = [];
  debug.push('[OCR原始行]');
  for (let i = 0; i < blocks.length; i++) {
    debug.push('块 ' + i.toString() + '：' + JSON.stringify(blocks[i].value));
    for (let j = 0; j < blocks[i].lines.length; j++) {
      const line = blocks[i].lines[j];
      const candidate = createOcrLineCandidate(line, i, j);
      if (candidate !== null) {
        groups.push(createOcrTextGroup([candidate]));
        debug.push('  行 ' + j.toString() + '：文本=' + JSON.stringify(candidate.text) + '，框=' +
          formatOcrBounds(candidate.bounds) + '，方向=' + (candidate.vertical ? '竖排' : '横排') +
          '，估算字号=' + roundOcrNumber(candidate.fontSize));
        appendOcrWordDebug(debug, line);
      } else {
        debug.push('  行 ' + j.toString() + '：已过滤，原因=' + ocrLineSkipReason(line) + '，文本=' +
          JSON.stringify(line.value));
      }
    }
  }
  mergeNearbyOcrTextGroups(groups);
  debug.push('[分组结果]');
  const result: ReaderTranslationLine[] = [];
  for (let i = 0; i < groups.length; i++) {
    const source = groupedOcrSource(groups[i]);
    if (source.length === 0) {
      continue;
    }
    debug.push('组 ' + i.toString() + '：成员=' + ocrGroupMemberText(groups[i]) + '，框=' +
      formatOcrBounds(groups[i].bounds) + '，方向=' + (groups[i].vertical ? '竖排' : '横排') +
      '，估算字号=' + roundOcrNumber(groupAverageFontSize(groups[i])) + '，原文=' + JSON.stringify(source));
    result.push({
      sourceText: source,
      translatedText: '',
      cornerPoints: boundsCornerPoints(groups[i].bounds),
      isVertical: groups[i].vertical,
      estimatedFontSize: groupAverageFontSize(groups[i])
    });
  }
  return result;
}

function createOcrLineCandidate(line: textRecognition.TextLine, blockIndex: number,
  lineIndex: number): OcrLineCandidate | null {
  const source = line.value.trim();
  if (source.length === 0 || line.cornerPoints.length < 2 || !containsReadableOcrText(source)) {
    return null;
  }
  const points: ReaderTranslationPoint[] = [];
  for (let i = 0; i < line.cornerPoints.length; i++) {
    points.push({ x: line.cornerPoints[i].x, y: line.cornerPoints[i].y });
  }
  const bounds = pointsBounds(points);
  const vertical = isVerticalOcrLine(line, bounds);
  return {
    text: source,
    bounds: bounds,
    vertical: vertical,
    blockIndex: blockIndex,
    lineIndex: lineIndex,
    fontSize: estimateOcrFontSize(line, bounds, vertical)
  };
}

function containsReadableOcrText(value: string): boolean {
  return /[A-Za-z0-9\u00c0-\u02af\u0370-\u052f\u0600-\u06ff\u0e00-\u0e7f\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]/
    .test(value);
}

function ocrLineSkipReason(line: textRecognition.TextLine): string {
  if (line.value.trim().length === 0) {
    return '空文本';
  }
  if (line.cornerPoints.length < 2) {
    return '坐标不足';
  }
  if (!containsReadableOcrText(line.value)) {
    return '仅包含符号';
  }
  return '无有效内容';
}

function appendOcrWordDebug(debug: string[], line: textRecognition.TextLine): void {
  for (let i = 0; i < line.words.length; i++) {
    const bounds = textWordBounds(line.words[i]);
    debug.push('    词 ' + i.toString() + '：' + JSON.stringify(line.words[i].value) + '，框=' +
      (bounds === null ? '(无)' : formatOcrBounds(bounds)));
  }
}

function ocrGroupMemberText(group: OcrTextGroup): string {
  const values: string[] = [];
  for (let i = 0; i < group.lines.length; i++) {
    values.push(group.lines[i].blockIndex.toString() + ':' + group.lines[i].lineIndex.toString());
  }
  return values.join(',');
}

function formatOcrPointsBounds(points: ReaderTranslationPoint[]): string {
  return points.length === 0 ? '(无)' : formatOcrBounds(pointsBounds(points));
}

function formatOcrBounds(bounds: OcrBounds): string {
  return '(' + roundOcrNumber(bounds.x) + ',' + roundOcrNumber(bounds.y) + ',' +
    roundOcrNumber(bounds.width) + ',' + roundOcrNumber(bounds.height) + ')';
}

function roundOcrNumber(value: number): string {
  return (Math.round(value * 10) / 10).toString();
}

function estimateOcrFontSize(line: textRecognition.TextLine, bounds: OcrBounds, vertical: boolean): number {
  const sizes: number[] = [];
  for (let i = 0; i < line.words.length; i++) {
    const wordBounds = textWordBounds(line.words[i]);
    if (wordBounds !== null) {
      sizes.push(vertical ? wordBounds.width : wordBounds.height);
    }
  }
  if (sizes.length === 0) {
    return Math.max(1, vertical ? bounds.width : bounds.height);
  }
  sizes.sort((left: number, right: number) => left - right);
  const middle = Math.floor(sizes.length / 2);
  const median = sizes.length % 2 === 0 ? (sizes[middle - 1] + sizes[middle]) / 2 : sizes[middle];
  // CoreVision occasionally reports every glyph in a vertical line as a narrow strip spanning the complete line
  // height. The line width is a more reliable font-size estimate in that case.
  if (vertical) {
    return Math.max(median, bounds.width * 0.8);
  }
  return median;
}

function textWordBounds(word: textRecognition.TextWord): OcrBounds | null {
  if (word.cornerPoints.length === 0) {
    return null;
  }
  let minX = word.cornerPoints[0].x;
  let maxX = minX;
  let minY = word.cornerPoints[0].y;
  let maxY = minY;
  for (let i = 1; i < word.cornerPoints.length; i++) {
    minX = Math.min(minX, word.cornerPoints[i].x);
    maxX = Math.max(maxX, word.cornerPoints[i].x);
    minY = Math.min(minY, word.cornerPoints[i].y);
    maxY = Math.max(maxY, word.cornerPoints[i].y);
  }
  return { x: minX, y: minY, width: Math.max(1, maxX - minX), height: Math.max(1, maxY - minY) };
}

function isVerticalOcrLine(line: textRecognition.TextLine, bounds: OcrBounds): boolean {
  // Prefer the complete line bounds when the aspect ratio is unambiguous. Some CoreVision results for vertical
  // Japanese text contain horizontal word centres because each word box incorrectly spans the whole column.
  if (bounds.height > bounds.width * 1.8) {
    return true;
  }
  if (bounds.width > bounds.height * 1.8) {
    return false;
  }
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
        if (!shouldMergeOcrTextGroups(groups[i], groups[j], groupsShareSourceBlock(groups[i], groups[j]))) {
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

function shouldMergeOcrTextGroups(left: OcrTextGroup, right: OcrTextGroup, sameBlock: boolean): boolean {
  if (left.vertical !== right.vertical) {
    return false;
  }
  const leftThickness = groupAverageFontSize(left);
  const rightThickness = groupAverageFontSize(right);
  const fontSizeRatio = Math.max(leftThickness, rightThickness) /
    Math.max(1, Math.min(leftThickness, rightThickness));
  if (fontSizeRatio > (sameBlock ? 1.65 : 1.4)) {
    return false;
  }
  const xOverlap = axisOverlap(left.bounds.x, left.bounds.width, right.bounds.x, right.bounds.width);
  const yOverlap = axisOverlap(left.bounds.y, left.bounds.height, right.bounds.y, right.bounds.height);
  const xOverlapRatio = xOverlap / Math.max(1, Math.min(left.bounds.width, right.bounds.width));
  const yOverlapRatio = yOverlap / Math.max(1, Math.min(left.bounds.height, right.bounds.height));
  const xGap = axisGap(left.bounds.x, left.bounds.width, right.bounds.x, right.bounds.width);
  const yGap = axisGap(left.bounds.y, left.bounds.height, right.bounds.y, right.bounds.height);
  const thickness = Math.max(leftThickness, rightThickness);
  if (xOverlapRatio >= 0.4 && yOverlapRatio >= 0.4) {
    return mergedOcrGroupIsCompact(left, right, sameBlock);
  }
  const fragmentGapLimit = thickness * (sameBlock ? 0.7 : 0.35);
  const neighboringGapLimit = thickness * (sameBlock ? 0.65 : 0.25);
  let nearby = false;
  if (left.vertical) {
    const sameColumnFragments = xOverlapRatio >= 0.7 && yGap <= fragmentGapLimit;
    const longitudinalOverlap = yOverlap / Math.max(1, Math.max(left.bounds.height, right.bounds.height));
    const neighboringColumns = yOverlapRatio >= 0.72 &&
      longitudinalOverlap >= (sameBlock ? 0.32 : 0.48) && xGap <= neighboringGapLimit &&
      groupAxisSpacingIsConsistent(left, right, true, thickness);
    nearby = sameColumnFragments || neighboringColumns;
  } else {
    const sameRowFragments = yOverlapRatio >= 0.7 && xGap <= fragmentGapLimit;
    const longitudinalOverlap = xOverlap / Math.max(1, Math.max(left.bounds.width, right.bounds.width));
    const neighboringRows = xOverlapRatio >= 0.72 &&
      longitudinalOverlap >= (sameBlock ? 0.32 : 0.48) && yGap <= neighboringGapLimit &&
      groupAxisSpacingIsConsistent(left, right, false, thickness);
    nearby = sameRowFragments || neighboringRows;
  }
  return nearby && mergedOcrGroupIsCompact(left, right, sameBlock);
}

function groupsShareSourceBlock(left: OcrTextGroup, right: OcrTextGroup): boolean {
  for (let i = 0; i < left.lines.length; i++) {
    for (let j = 0; j < right.lines.length; j++) {
      if (left.lines[i].blockIndex === right.lines[j].blockIndex) {
        return true;
      }
    }
  }
  return false;
}

function mergedOcrGroupIsCompact(left: OcrTextGroup, right: OcrTextGroup, sameBlock: boolean): boolean {
  const bounds = unionOcrBounds(left.bounds, right.bounds);
  const thickness = Math.max(groupAverageFontSize(left), groupAverageFontSize(right));
  const crossAxisSpan = left.vertical ? bounds.width : bounds.height;
  if (crossAxisSpan > thickness * (sameBlock ? 7 : 4.5)) {
    return false;
  }
  const unionArea = Math.max(1, bounds.width * bounds.height);
  const occupiedArea = groupLineArea(left) + groupLineArea(right);
  const minimumCoverage = sameBlock ? 0.14 : 0.24;
  if (occupiedArea / unionArea < minimumCoverage) {
    return false;
  }
  const sourceArea = Math.max(1, left.bounds.width * left.bounds.height +
    right.bounds.width * right.bounds.height);
  return unionArea / sourceArea <= (sameBlock ? 2.4 : 1.65);
}

function groupLineArea(group: OcrTextGroup): number {
  let area = 0;
  for (let i = 0; i < group.lines.length; i++) {
    area += group.lines[i].bounds.width * group.lines[i].bounds.height;
  }
  return area;
}

function groupAxisSpacingIsConsistent(left: OcrTextGroup, right: OcrTextGroup, vertical: boolean,
  fontSize: number): boolean {
  const centers: number[] = [];
  appendGroupAxisCenters(centers, left, vertical);
  appendGroupAxisCenters(centers, right, vertical);
  centers.sort((first: number, second: number) => first - second);
  const axes: number[] = [];
  const sameAxisTolerance = fontSize * 0.5;
  for (let i = 0; i < centers.length; i++) {
    if (axes.length === 0 || centers[i] - axes[axes.length - 1] > sameAxisTolerance) {
      axes.push(centers[i]);
    } else {
      axes[axes.length - 1] = (axes[axes.length - 1] + centers[i]) / 2;
    }
  }
  if (axes.length <= 2) {
    return true;
  }
  let minimumGap = Number.MAX_VALUE;
  let maximumGap = 0;
  for (let i = 1; i < axes.length; i++) {
    const gap = axes[i] - axes[i - 1];
    minimumGap = Math.min(minimumGap, gap);
    maximumGap = Math.max(maximumGap, gap);
  }
  return maximumGap - minimumGap <= fontSize * 0.75 &&
    maximumGap / Math.max(1, minimumGap) <= 1.8;
}

function appendGroupAxisCenters(result: number[], group: OcrTextGroup, vertical: boolean): void {
  for (let i = 0; i < group.lines.length; i++) {
    result.push(vertical ? group.lines[i].bounds.x + group.lines[i].bounds.width / 2 :
      group.lines[i].bounds.y + group.lines[i].bounds.height / 2);
  }
}

function groupAverageFontSize(group: OcrTextGroup): number {
  let total = 0;
  for (let i = 0; i < group.lines.length; i++) {
    total += group.lines[i].fontSize;
  }
  return total / Math.max(1, group.lines.length);
}

function groupedOcrSource(group: OcrTextGroup): string {
  const lines: OcrLineCandidate[] = [];
  for (let i = 0; i < group.lines.length; i++) {
    lines.push(group.lines[i]);
  }
  const tolerance = Math.max(1, groupAverageFontSize(group) * (group.vertical ? 0.32 : 0.65));
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
