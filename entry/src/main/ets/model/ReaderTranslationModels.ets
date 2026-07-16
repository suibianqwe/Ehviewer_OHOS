export interface ReaderTranslationPoint {
  x: number;
  y: number;
}

export interface ReaderTranslationLine {
  sourceText: string;
  translatedText: string;
  cornerPoints: ReaderTranslationPoint[];
  isVertical?: boolean;
  estimatedFontSize?: number;
}

export interface ReaderPageTranslation {
  pageIndex: number;
  imageWidth: number;
  imageHeight: number;
  lines: ReaderTranslationLine[];
  updatedAt: number;
  layoutVersion?: number;
}

export function cloneReaderPageTranslation(value: ReaderPageTranslation): ReaderPageTranslation {
  const lines: ReaderTranslationLine[] = [];
  for (let i = 0; i < value.lines.length; i++) {
    const points: ReaderTranslationPoint[] = [];
    for (let j = 0; j < value.lines[i].cornerPoints.length; j++) {
      points.push({
        x: value.lines[i].cornerPoints[j].x,
        y: value.lines[i].cornerPoints[j].y
      });
    }
    lines.push({
      sourceText: value.lines[i].sourceText,
      translatedText: value.lines[i].translatedText,
      cornerPoints: points,
      isVertical: value.lines[i].isVertical,
      estimatedFontSize: value.lines[i].estimatedFontSize
    });
  }
  return {
    pageIndex: value.pageIndex,
    imageWidth: value.imageWidth,
    imageHeight: value.imageHeight,
    lines: lines,
    updatedAt: value.updatedAt,
    layoutVersion: value.layoutVersion
  };
}

export function cloneReaderPageTranslations(values: ReaderPageTranslation[] | undefined): ReaderPageTranslation[] {
  const result: ReaderPageTranslation[] = [];
  if (values === undefined || !Array.isArray(values)) {
    return result;
  }
  for (let i = 0; i < values.length; i++) {
    if (isValidReaderPageTranslation(values[i])) {
      result.push(cloneReaderPageTranslation(values[i]));
    }
  }
  return result;
}

export function isValidReaderPageTranslation(value: ReaderPageTranslation): boolean {
  return value !== undefined && value !== null && value.pageIndex >= 0 && value.imageWidth > 0 &&
    value.imageHeight > 0 && Array.isArray(value.lines);
}
