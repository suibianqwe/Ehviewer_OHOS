import {
  ReaderPageTranslation,
  ReaderTranslationLine,
  ReaderTranslationPoint
} from '../../../model/ReaderTranslationModels';
import {
  ReaderOcrOverlayDebugItem,
  readerOcrDebugLog
} from '../../../services/ReaderOcrDebugLog';

interface ReaderTranslationBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface ReaderTranslationLayout extends ReaderTranslationBounds {
  key: string;
  sourceText: string;
  text: string;
  fontSize: number;
  lineHeight: number;
  estimatedLines: number;
  sourceX: number;
  sourceY: number;
  sourceWidth: number;
  sourceHeight: number;
  sourceFontSize: number;
  padding: number;
  anchorX: number;
  anchorY: number;
  vertical: boolean;
  verticalColumns: string[];
  columnWidth: number;
}

interface ReaderVerticalTextLayout {
  columns: string[];
  width: number;
  height: number;
  rows: number;
  columnWidth: number;
}

const TRANSLATION_REFERENCE_EDGE: number = 1280;
const TRANSLATION_REFERENCE_LAYOUT_GAP: number = 4;
const TRANSLATION_REFERENCE_TEXT_PADDING: number = 6;
const TRANSLATION_REFERENCE_MIN_WIDTH: number = 48;
const TRANSLATION_REFERENCE_MIN_HEIGHT: number = 28;
const TRANSLATION_REFERENCE_MIN_FONT_SIZE: number = 23;
const TRANSLATION_REFERENCE_MAX_FONT_SIZE: number = 84;
const TRANSLATION_HORIZONTAL_MAX_WIDTH_RATIO: number = 0.96;

@Component
export struct ReaderTranslationOverlay {
  @Prop translation: ReaderPageTranslation | null = null;
  @Prop displayWidth: number = 1;
  @Prop displayHeight: number = 1;

  private canvasWidth(): number {
    return Math.max(1, this.translation?.imageWidth ?? this.displayWidth);
  }

  private canvasHeight(): number {
    return Math.max(1, this.translation?.imageHeight ?? this.displayHeight);
  }

  private coordinateScale(): number {
    return Math.max(0.1, Math.min(this.canvasWidth(), this.canvasHeight()) / TRANSLATION_REFERENCE_EDGE);
  }

  private layoutGap(): number {
    return TRANSLATION_REFERENCE_LAYOUT_GAP * this.coordinateScale();
  }

  private textPadding(): number {
    return TRANSLATION_REFERENCE_TEXT_PADDING * this.coordinateScale();
  }

  private sourceBounds(line: ReaderTranslationLine): ReaderTranslationBounds {
    if (this.translation === null || line.cornerPoints.length === 0) {
      return { x: 0, y: 0, width: 1, height: 1 };
    }
    let minX = line.cornerPoints[0].x;
    let maxX = line.cornerPoints[0].x;
    let minY = line.cornerPoints[0].y;
    let maxY = line.cornerPoints[0].y;
    for (let i = 1; i < line.cornerPoints.length; i++) {
      const point: ReaderTranslationPoint = line.cornerPoints[i];
      minX = Math.min(minX, point.x);
      maxX = Math.max(maxX, point.x);
      minY = Math.min(minY, point.y);
      maxY = Math.max(maxY, point.y);
    }
    const canvasWidth = this.canvasWidth();
    const canvasHeight = this.canvasHeight();
    const coordinateScale = this.coordinateScale();
    const x = Math.max(0, Math.min(canvasWidth - 1, minX));
    const y = Math.max(0, Math.min(canvasHeight - 1, minY));
    const width = Math.min(canvasWidth - x,
      Math.max(TRANSLATION_REFERENCE_MIN_WIDTH * coordinateScale, maxX - minX));
    const height = Math.min(canvasHeight - y,
      Math.max(TRANSLATION_REFERENCE_MIN_HEIGHT * coordinateScale, maxY - minY));
    return { x: x, y: y, width: width, height: height };
  }

  private baseLayout(line: ReaderTranslationLine, index: number): ReaderTranslationLayout {
    const source = this.sourceBounds(line);
    const sourceThickness = line.isVertical === true ? source.width : source.height;
    const sourceFontSize = line.estimatedFontSize !== undefined && line.estimatedFontSize > 0 ?
      line.estimatedFontSize : sourceThickness * 0.72;
    const coordinateScale = this.coordinateScale();
    const fontSize = Math.max(TRANSLATION_REFERENCE_MIN_FONT_SIZE * coordinateScale,
      Math.min(TRANSLATION_REFERENCE_MAX_FONT_SIZE * coordinateScale, sourceFontSize * 0.95));
    const padding = this.textPadding();
    const canvasWidth = this.canvasWidth();
    const canvasHeight = this.canvasHeight();
    const minimumWidth = TRANSLATION_REFERENCE_MIN_WIDTH * coordinateScale;
    const lineHeight = fontSize * 1.12;
    const vertical = line.isVertical === true;
    let width: number;
    let height: number;
    let estimatedLines: number;
    let verticalColumns: string[] = [];
    let columnWidth = fontSize * 1.08;
    if (vertical) {
      const verticalLayout = createVerticalTextLayout(line.translatedText, source, fontSize,
        lineHeight, padding, canvasWidth, canvasHeight);
      verticalColumns = verticalLayout.columns;
      columnWidth = verticalLayout.columnWidth;
      width = verticalLayout.width;
      height = verticalLayout.height;
      estimatedLines = verticalLayout.rows;
    } else {
      const preferredWidth = Math.max(minimumWidth, source.width,
        Math.min(canvasWidth * TRANSLATION_HORIZONTAL_MAX_WIDTH_RATIO,
          estimateUnwrappedTextWidth(line.translatedText, fontSize) + padding * 2 + fontSize * 0.5));
      width = Math.max(minimumWidth, Math.min(canvasWidth, preferredWidth));
      // Leave a small glyph-width margin because ArkUI's actual font metrics and line breaking can differ from the
      // estimate. maxLines must not be used here: an underestimated line count silently clips the final wrapped line.
      const availableTextWidth = Math.max(8 * coordinateScale, width - padding * 2 - fontSize * 0.25);
      estimatedLines = estimateWrappedTextLines(line.translatedText, availableTextWidth, fontSize);
      height = Math.min(canvasHeight,
        estimatedLines * lineHeight + padding * 2 + 2 * coordinateScale);
    }
    const anchorX = source.x + source.width / 2 - width / 2;
    const anchorY = source.y + source.height / 2 - height / 2;
    const x = Math.max(0, Math.min(canvasWidth - width, anchorX));
    const y = Math.max(0, Math.min(Math.max(0, canvasHeight - height), anchorY));
    return {
      key: index.toString() + ':' + line.sourceText + ':' + (this.translation?.updatedAt ?? 0).toString(),
      sourceText: line.sourceText,
      text: line.translatedText,
      x: x,
      y: y,
      width: width,
      height: height,
      fontSize: fontSize,
      lineHeight: lineHeight,
      estimatedLines: estimatedLines,
      sourceX: source.x,
      sourceY: source.y,
      sourceWidth: source.width,
      sourceHeight: source.height,
      sourceFontSize: sourceFontSize,
      padding: padding,
      anchorX: x,
      anchorY: y,
      vertical: vertical,
      verticalColumns: verticalColumns,
      columnWidth: columnWidth
    };
  }

  private translationLayouts(): ReaderTranslationLayout[] {
    if (this.translation === null) {
      return [];
    }
    const pending: ReaderTranslationLayout[] = [];
    for (let i = 0; i < this.translation.lines.length; i++) {
      if (this.translation.lines[i].translatedText.length > 0) {
        pending.push(this.baseLayout(this.translation.lines[i], i));
      }
    }
    pending.sort((left: ReaderTranslationLayout, right: ReaderTranslationLayout) => {
      if (Math.abs(left.y - right.y) >= 1) {
        return left.y - right.y;
      }
      return left.x - right.x;
    });
    const sourceLayouts: ReaderTranslationLayout[] = [];
    for (let i = 0; i < pending.length; i++) {
      sourceLayouts.push(this.placeWithoutTextOverlap(pending[i], sourceLayouts));
    }
    const placed: ReaderTranslationLayout[] = [];
    for (let i = 0; i < sourceLayouts.length; i++) {
      placed.push(this.scaleLayoutToDisplay(sourceLayouts[i]));
    }
    this.recordOverlayDebug(placed);
    return placed;
  }

  private scaleLayoutToDisplay(item: ReaderTranslationLayout): ReaderTranslationLayout {
    const scaleX = this.displayWidth / this.canvasWidth();
    const scaleY = this.displayHeight / this.canvasHeight();
    const fontScale = Math.min(scaleX, scaleY);
    return {
      key: item.key + ':' + layoutNumber(this.displayWidth) + 'x' + layoutNumber(this.displayHeight),
      sourceText: item.sourceText,
      text: item.text,
      x: item.x * scaleX,
      y: item.y * scaleY,
      width: item.width * scaleX,
      height: item.height * scaleY,
      fontSize: item.fontSize * fontScale,
      lineHeight: item.lineHeight * fontScale,
      estimatedLines: item.estimatedLines,
      sourceX: item.sourceX * scaleX,
      sourceY: item.sourceY * scaleY,
      sourceWidth: item.sourceWidth * scaleX,
      sourceHeight: item.sourceHeight * scaleY,
      sourceFontSize: item.sourceFontSize * fontScale,
      padding: item.padding * fontScale,
      anchorX: item.anchorX * scaleX,
      anchorY: item.anchorY * scaleY,
      vertical: item.vertical,
      verticalColumns: item.verticalColumns,
      columnWidth: item.columnWidth * fontScale
    };
  }

  private placeWithoutTextOverlap(item: ReaderTranslationLayout,
    placed: ReaderTranslationLayout[]): ReaderTranslationLayout {
    if (!this.overlapsAny(item, placed)) {
      return item;
    }
    const coordinateScale = this.coordinateScale();
    const step = Math.max(2 * coordinateScale, Math.min(6 * coordinateScale, item.lineHeight / 3));
    const xPositions = this.candidateAxisPositions(item.anchorX, this.canvasWidth() - item.width, item.width,
      placed, true, step);
    const yPositions = this.candidateAxisPositions(item.anchorY, this.canvasHeight() - item.height, item.height,
      placed, false, step);
    let best = this.copyLayout(item, item.x, item.y);
    let bestOverlap = this.overlapArea(best, placed);
    let bestDistance = 0;
    for (let i = 0; i < yPositions.length; i++) {
      for (let j = 0; j < xPositions.length; j++) {
        const x = xPositions[j];
        const y = yPositions[i];
        const candidate = this.copyLayout(item, x, y);
        const overlap = this.overlapArea(candidate, placed);
        const distance = Math.pow(x - item.anchorX, 2) + Math.pow(y - item.anchorY, 2);
        if (overlap < bestOverlap || (Math.abs(overlap - bestOverlap) < 0.1 && distance < bestDistance)) {
          best = candidate;
          bestOverlap = overlap;
          bestDistance = distance;
        }
      }
    }
    return best;
  }

  private candidateAxisPositions(anchor: number, maximum: number, itemSize: number,
    placed: ReaderTranslationLayout[], horizontal: boolean, step: number): number[] {
    const result: number[] = [];
    const safeMaximum = Math.max(0, maximum);
    appendUniqueLayoutPosition(result, Math.max(0, Math.min(safeMaximum, anchor)));
    const nearLimit = Math.max(step, Math.min(horizontal ? this.canvasWidth() * 0.07 : this.canvasHeight() * 0.05,
      step * 12));
    const offsets = candidateLayoutOffsets(nearLimit, step);
    for (let i = 0; i < offsets.length; i++) {
      appendUniqueLayoutPosition(result, Math.max(0, Math.min(safeMaximum, anchor + offsets[i])));
    }
    for (let i = 0; i < placed.length; i++) {
      const start = horizontal ? placed[i].x : placed[i].y;
      const size = horizontal ? placed[i].width : placed[i].height;
      const before = Math.max(0, Math.min(safeMaximum, start - itemSize - this.layoutGap()));
      const after = Math.max(0, Math.min(safeMaximum, start + size + this.layoutGap()));
      if (Math.abs(before - anchor) <= nearLimit) {
        appendUniqueLayoutPosition(result, before);
      }
      if (Math.abs(after - anchor) <= nearLimit) {
        appendUniqueLayoutPosition(result, after);
      }
    }
    return result;
  }

  private copyLayout(item: ReaderTranslationLayout, x: number, y: number): ReaderTranslationLayout {
    return {
      key: item.key,
      sourceText: item.sourceText,
      text: item.text,
      x: x,
      y: y,
      width: item.width,
      height: item.height,
      fontSize: item.fontSize,
      lineHeight: item.lineHeight,
      estimatedLines: item.estimatedLines,
      sourceX: item.sourceX,
      sourceY: item.sourceY,
      sourceWidth: item.sourceWidth,
      sourceHeight: item.sourceHeight,
      sourceFontSize: item.sourceFontSize,
      padding: item.padding,
      anchorX: item.anchorX,
      anchorY: item.anchorY,
      vertical: item.vertical,
      verticalColumns: item.verticalColumns,
      columnWidth: item.columnWidth
    };
  }

  private recordOverlayDebug(layouts: ReaderTranslationLayout[]): void {
    if (this.translation === null) {
      return;
    }
    const items: ReaderOcrOverlayDebugItem[] = [];
    for (let i = 0; i < layouts.length; i++) {
      items.push({
        sourceText: layouts[i].sourceText,
        translatedText: layouts[i].text,
        sourceX: layouts[i].sourceX,
        sourceY: layouts[i].sourceY,
        sourceWidth: layouts[i].sourceWidth,
        sourceHeight: layouts[i].sourceHeight,
        layoutX: layouts[i].x,
        layoutY: layouts[i].y,
        layoutWidth: layouts[i].width,
        layoutHeight: layouts[i].height,
        sourceFontSize: layouts[i].sourceFontSize,
        fontSize: layouts[i].fontSize,
        lineHeight: layouts[i].lineHeight,
        estimatedLines: layouts[i].estimatedLines,
        vertical: layouts[i].vertical,
        columnCount: layouts[i].verticalColumns.length
      });
    }
    readerOcrDebugLog.recordOverlaySnapshot(this.translation, this.displayWidth, this.displayHeight, items);
  }

  private overlapsAny(item: ReaderTranslationBounds, placed: ReaderTranslationBounds[]): boolean {
    for (let i = 0; i < placed.length; i++) {
      if (rectanglesOverlap(item, placed[i], this.layoutGap())) {
        return true;
      }
    }
    return false;
  }

  private overlapArea(item: ReaderTranslationBounds, placed: ReaderTranslationBounds[]): number {
    let area = 0;
    for (let i = 0; i < placed.length; i++) {
      const width = Math.max(0, Math.min(item.x + item.width, placed[i].x + placed[i].width) -
        Math.max(item.x, placed[i].x));
      const height = Math.max(0, Math.min(item.y + item.height, placed[i].y + placed[i].height) -
        Math.max(item.y, placed[i].y));
      area += width * height;
    }
    return area;
  }

  private backgroundLayouts(): ReaderTranslationBounds[] {
    const texts = this.translationLayouts();
    const backgrounds: ReaderTranslationBounds[] = [];
    for (let i = 0; i < texts.length; i++) {
      let merged: ReaderTranslationBounds = {
        x: texts[i].x,
        y: texts[i].y,
        width: texts[i].width,
        height: texts[i].height
      };
      let changed = true;
      while (changed) {
        changed = false;
        const remaining: ReaderTranslationBounds[] = [];
        for (let j = 0; j < backgrounds.length; j++) {
          if (rectanglesOverlap(merged, backgrounds[j], 0)) {
            merged = unionBounds(merged, backgrounds[j]);
            changed = true;
          } else {
            remaining.push(backgrounds[j]);
          }
        }
        backgrounds.splice(0, backgrounds.length);
        for (let j = 0; j < remaining.length; j++) {
          backgrounds.push(remaining[j]);
        }
      }
      backgrounds.push(merged);
    }
    return backgrounds;
  }

  @Builder
  private TranslationTextItem(item: ReaderTranslationLayout) {
    if (item.vertical) {
      Row({ space: 0 }) {
        ForEach(item.verticalColumns, (column: string, index: number) => {
          Text(column)
            .width(item.columnWidth)
            .height(Math.max(1, item.height - item.padding * 2))
            .fontSize(item.fontSize)
            .fontColor(Color.Black)
            .lineHeight(item.lineHeight)
            .textAlign(TextAlign.Center)
            .textShadow([
              { radius: 6, color: 'rgba(255,255,255,1)', offsetX: 0, offsetY: 0 },
              { radius: 1.8, color: 'rgba(255,255,255,1)', offsetX: 1.6, offsetY: 0 },
              { radius: 1.8, color: 'rgba(255,255,255,1)', offsetX: -1.6, offsetY: 0 },
              { radius: 1.8, color: 'rgba(255,255,255,1)', offsetX: 0, offsetY: 1.6 },
              { radius: 1.8, color: 'rgba(255,255,255,1)', offsetX: 0, offsetY: -1.6 },
              { radius: 1.5, color: 'rgba(255,255,255,1)', offsetX: 1.2, offsetY: 1.2 },
              { radius: 1.5, color: 'rgba(255,255,255,1)', offsetX: -1.2, offsetY: 1.2 },
              { radius: 1.5, color: 'rgba(255,255,255,1)', offsetX: 1.2, offsetY: -1.2 },
              { radius: 1.5, color: 'rgba(255,255,255,1)', offsetX: -1.2, offsetY: -1.2 }
            ])
            .id('reader-translation-vertical-column-' + item.key + ':' + index.toString())
        }, (column: string, index: number) => item.key + ':' + index.toString() + ':' + column)
      }
      .width(item.width)
      .height(item.height)
      .padding({
        left: item.padding,
        right: item.padding,
        top: item.padding,
        bottom: item.padding
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .position({ x: item.x, y: item.y })
      .id('reader-translation-text-' + item.key)
    } else {
      Text(item.text)
        .width(item.width)
        .height(item.height)
        .fontSize(item.fontSize)
        .fontColor(Color.Black)
        .lineHeight(item.lineHeight)
        .textAlign(TextAlign.Center)
        .padding({
          left: item.padding,
          right: item.padding,
          top: item.padding,
          bottom: item.padding
        })
        .textShadow([
          { radius: 6, color: 'rgba(255,255,255,1)', offsetX: 0, offsetY: 0 },
          { radius: 1.8, color: 'rgba(255,255,255,1)', offsetX: 1.6, offsetY: 0 },
          { radius: 1.8, color: 'rgba(255,255,255,1)', offsetX: -1.6, offsetY: 0 },
          { radius: 1.8, color: 'rgba(255,255,255,1)', offsetX: 0, offsetY: 1.6 },
          { radius: 1.8, color: 'rgba(255,255,255,1)', offsetX: 0, offsetY: -1.6 },
          { radius: 1.5, color: 'rgba(255,255,255,1)', offsetX: 1.2, offsetY: 1.2 },
          { radius: 1.5, color: 'rgba(255,255,255,1)', offsetX: -1.2, offsetY: 1.2 },
          { radius: 1.5, color: 'rgba(255,255,255,1)', offsetX: 1.2, offsetY: -1.2 },
          { radius: 1.5, color: 'rgba(255,255,255,1)', offsetX: -1.2, offsetY: -1.2 }
        ])
        .position({ x: item.x, y: item.y })
        .id('reader-translation-text-' + item.key)
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.translation !== null) {
        ForEach(this.backgroundLayouts(), (box: ReaderTranslationBounds, index: number) => {
          Stack() {}
            .width(box.width)
            .height(box.height)
            .backgroundColor('rgba(255,255,255,0.20)')
            .border({ width: 0.5, color: 'rgba(255,255,255,0.32)' })
            .borderRadius(3)
            .position({ x: box.x, y: box.y })
            .id('reader-translation-background-' + index.toString())
        }, (box: ReaderTranslationBounds, index: number) => {
          return index.toString() + ':' + layoutBoundsKey(box);
        })
        ForEach(this.translationLayouts(), (item: ReaderTranslationLayout) => {
          this.TranslationTextItem(item)
        }, (item: ReaderTranslationLayout) => item.key)
      }
    }
    .width(this.displayWidth)
    .height(this.displayHeight)
    .clip(true)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

function createVerticalTextLayout(value: string, source: ReaderTranslationBounds, fontSize: number,
  lineHeight: number, padding: number, canvasWidth: number,
  canvasHeight: number): ReaderVerticalTextLayout {
  const columnWidth = fontSize * 1.08;
  const availableRows = Math.max(1, Math.floor(Math.max(lineHeight, source.height - padding * 2) / lineHeight));
  const explicitRows = nonEmptyTranslationRows(value);
  const readingOrderColumns: string[] = [];
  if (explicitRows.length > 1) {
    for (let i = 0; i < explicitRows.length; i++) {
      appendVerticalColumns(readingOrderColumns, translationCharacters(explicitRows[i]), availableRows);
    }
  } else {
    const characters = translationCharacters(value);
    const requiredColumns = Math.max(1, Math.ceil(characters.length / availableRows));
    const columnCount = Math.max(1, Math.min(requiredColumns,
      Math.floor(Math.max(columnWidth, canvasWidth - padding * 2) / columnWidth)));
    const balancedRows = Math.max(1, Math.ceil(characters.length / columnCount));
    appendVerticalColumns(readingOrderColumns, characters, balancedRows);
  }
  if (readingOrderColumns.length === 0) {
    readingOrderColumns.push('');
  }
  const columns: string[] = [];
  let maximumRows = 1;
  for (let i = readingOrderColumns.length - 1; i >= 0; i--) {
    columns.push(readingOrderColumns[i]);
    maximumRows = Math.max(maximumRows, verticalColumnRows(readingOrderColumns[i]));
  }
  return {
    columns: columns,
    width: Math.min(canvasWidth, columns.length * columnWidth + padding * 2),
    height: Math.min(canvasHeight, maximumRows * lineHeight + padding * 2 + 2),
    rows: maximumRows,
    columnWidth: columnWidth
  };
}

function nonEmptyTranslationRows(value: string): string[] {
  const source = value.split('\n');
  const result: string[] = [];
  for (let i = 0; i < source.length; i++) {
    const text = source[i].trim();
    if (text.length > 0) {
      result.push(text);
    }
  }
  return result;
}

function translationCharacters(value: string): string[] {
  const result: string[] = [];
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code === 10 || code === 13 || code === 9 || code === 32) {
      continue;
    }
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < value.length) {
      const next = value.charCodeAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        result.push(value.substring(i, i + 2));
        i++;
        continue;
      }
    }
    result.push(value.charAt(i));
  }
  return result;
}

function appendVerticalColumns(result: string[], characters: string[], rowsPerColumn: number): void {
  const rows = Math.max(1, rowsPerColumn);
  for (let start = 0; start < characters.length; start += rows) {
    const values: string[] = [];
    const end = Math.min(characters.length, start + rows);
    for (let i = start; i < end; i++) {
      values.push(characters[i]);
    }
    result.push(values.join('\n'));
  }
}

function verticalColumnRows(value: string): number {
  if (value.length === 0) {
    return 1;
  }
  return value.split('\n').length;
}

function estimateUnwrappedTextWidth(value: string, fontSize: number): number {
  const rows = value.split('\n');
  let maximumUnits = 0;
  for (let i = 0; i < rows.length; i++) {
    maximumUnits = Math.max(maximumUnits, estimateTextUnits(rows[i]));
  }
  return maximumUnits * fontSize;
}

function estimateWrappedTextLines(value: string, availableWidth: number, fontSize: number): number {
  const rows = value.split('\n');
  let total = 0;
  for (let i = 0; i < rows.length; i++) {
    const estimatedWidth = estimateTextUnits(rows[i]) * fontSize;
    total += Math.max(1, Math.ceil(estimatedWidth / availableWidth));
  }
  return Math.max(1, total);
}

function estimateTextUnits(value: string): number {
  let units = 0;
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code === 9 || code === 32) {
      units += 0.35;
    } else if (code <= 0x7F) {
      units += 0.62;
    } else {
      // CJK glyphs and full-width punctuation are approximately one em wide.
      units += 1;
    }
  }
  return units;
}

function candidateLayoutOffsets(limit: number, step: number): number[] {
  const result: number[] = [0];
  for (let value = step; value <= limit + 0.1; value += step) {
    result.push(value);
    result.push(-value);
  }
  return result;
}

function appendUniqueLayoutPosition(result: number[], value: number): void {
  for (let i = 0; i < result.length; i++) {
    if (Math.abs(result[i] - value) < 0.1) {
      return;
    }
  }
  result.push(value);
}

function layoutNumber(value: number): string {
  return Math.round(value * 10).toString();
}

function layoutBoundsKey(value: ReaderTranslationBounds): string {
  return layoutNumber(value.x) + ':' + layoutNumber(value.y) + ':' +
    layoutNumber(value.width) + ':' + layoutNumber(value.height);
}

function rectanglesOverlap(left: ReaderTranslationBounds, right: ReaderTranslationBounds, gap: number): boolean {
  return left.x < right.x + right.width + gap && left.x + left.width + gap > right.x &&
    left.y < right.y + right.height + gap && left.y + left.height + gap > right.y;
}

function unionBounds(left: ReaderTranslationBounds, right: ReaderTranslationBounds): ReaderTranslationBounds {
  const x = Math.min(left.x, right.x);
  const y = Math.min(left.y, right.y);
  return {
    x: x,
    y: y,
    width: Math.max(left.x + left.width, right.x + right.width) - x,
    height: Math.max(left.y + left.height, right.y + right.height) - y
  };
}
