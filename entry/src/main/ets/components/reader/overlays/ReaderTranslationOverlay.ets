import {
  ReaderPageTranslation,
  ReaderTranslationLine,
  ReaderTranslationPoint
} from '../../../model/ReaderTranslationModels';

interface ReaderTranslationBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface ReaderTranslationLayout extends ReaderTranslationBounds {
  key: string;
  text: string;
  fontSize: number;
  lineHeight: number;
  maxLines: number;
}

const TRANSLATION_LAYOUT_GAP: number = 2;

@Component
export struct ReaderTranslationOverlay {
  @Prop translation: ReaderPageTranslation | null = null;
  @Prop displayWidth: number = 1;
  @Prop displayHeight: number = 1;

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
    const sourceWidth = Math.max(1, this.translation.imageWidth);
    const sourceHeight = Math.max(1, this.translation.imageHeight);
    const x = Math.max(0, Math.min(this.displayWidth - 1, minX * this.displayWidth / sourceWidth));
    const y = Math.max(0, Math.min(this.displayHeight - 1, minY * this.displayHeight / sourceHeight));
    const width = Math.max(24, Math.min(this.displayWidth - x, (maxX - minX) * this.displayWidth / sourceWidth));
    const height = Math.max(14, Math.min(this.displayHeight - y, (maxY - minY) * this.displayHeight / sourceHeight));
    return { x: x, y: y, width: width, height: height };
  }

  private baseLayout(line: ReaderTranslationLine, index: number): ReaderTranslationLayout {
    const source = this.sourceBounds(line);
    const fontSize = Math.max(10, Math.min(24, source.height * 0.72));
    const preferredWidth = Math.max(source.width,
      Math.min(this.displayWidth * 0.46, line.translatedText.length * fontSize * 0.82 + 6));
    const width = Math.max(24, Math.min(this.displayWidth, preferredWidth));
    const x = Math.max(0, Math.min(this.displayWidth - width, source.x));
    const availableTextWidth = Math.max(8, width - 4);
    const maxLines = Math.max(1, Math.ceil(line.translatedText.length * fontSize * 0.82 / availableTextWidth));
    const lineHeight = fontSize * 1.12;
    const height = Math.max(source.height, maxLines * lineHeight + 4);
    return {
      key: index.toString() + ':' + line.sourceText,
      text: line.translatedText,
      x: x,
      y: Math.max(0, Math.min(Math.max(0, this.displayHeight - height), source.y)),
      width: width,
      height: Math.min(this.displayHeight, height),
      fontSize: fontSize,
      lineHeight: lineHeight,
      maxLines: maxLines
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
    const placed: ReaderTranslationLayout[] = [];
    for (let i = 0; i < pending.length; i++) {
      placed.push(this.placeWithoutTextOverlap(pending[i], placed));
    }
    return placed;
  }

  private placeWithoutTextOverlap(item: ReaderTranslationLayout,
    placed: ReaderTranslationLayout[]): ReaderTranslationLayout {
    if (!this.overlapsAny(item, placed)) {
      return item;
    }
    const step = Math.max(2, Math.min(8, item.lineHeight / 2));
    const maxSteps = Math.ceil(this.displayHeight / step);
    const xPositions = this.candidateXPositions(item, placed);
    let best = this.copyLayout(item, item.x, item.y);
    let bestOverlap = this.overlapArea(best, placed);
    for (let i = 0; i <= maxSteps; i++) {
      const downY = Math.min(Math.max(0, this.displayHeight - item.height), item.y + step * i);
      const upY = Math.max(0, item.y - step * i);
      for (let j = 0; j < xPositions.length; j++) {
        const down = this.copyLayout(item, xPositions[j], downY);
        if (!this.overlapsAny(down, placed)) {
          return down;
        }
        const downOverlap = this.overlapArea(down, placed);
        if (downOverlap < bestOverlap) {
          best = down;
          bestOverlap = downOverlap;
        }
        const up = this.copyLayout(item, xPositions[j], upY);
        if (!this.overlapsAny(up, placed)) {
          return up;
        }
        const upOverlap = this.overlapArea(up, placed);
        if (upOverlap < bestOverlap) {
          best = up;
          bestOverlap = upOverlap;
        }
      }
    }
    return best;
  }

  private candidateXPositions(item: ReaderTranslationLayout,
    placed: ReaderTranslationLayout[]): number[] {
    const values: number[] = [item.x, 0, Math.max(0, this.displayWidth - item.width)];
    for (let i = 0; i < placed.length; i++) {
      values.push(Math.max(0, Math.min(this.displayWidth - item.width,
        placed[i].x + placed[i].width + TRANSLATION_LAYOUT_GAP)));
      values.push(Math.max(0, Math.min(this.displayWidth - item.width,
        placed[i].x - item.width - TRANSLATION_LAYOUT_GAP)));
    }
    const unique: number[] = [];
    for (let i = 0; i < values.length; i++) {
      let found = false;
      for (let j = 0; j < unique.length; j++) {
        if (Math.abs(unique[j] - values[i]) < 1) {
          found = true;
          break;
        }
      }
      if (!found) {
        unique.push(values[i]);
      }
    }
    return unique;
  }

  private copyLayout(item: ReaderTranslationLayout, x: number, y: number): ReaderTranslationLayout {
    return {
      key: item.key,
      text: item.text,
      x: x,
      y: y,
      width: item.width,
      height: item.height,
      fontSize: item.fontSize,
      lineHeight: item.lineHeight,
      maxLines: item.maxLines
    };
  }

  private overlapsAny(item: ReaderTranslationBounds, placed: ReaderTranslationBounds[]): boolean {
    for (let i = 0; i < placed.length; i++) {
      if (rectanglesOverlap(item, placed[i], TRANSLATION_LAYOUT_GAP)) {
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

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.translation !== null) {
        ForEach(this.backgroundLayouts(), (box: ReaderTranslationBounds, index: number) => {
          Stack() {}
            .width(box.width)
            .height(box.height)
            .backgroundColor('rgba(255,255,255,0.08)')
            .border({ width: 0.5, color: 'rgba(255,255,255,0.18)' })
            .borderRadius(3)
            .position({ x: box.x, y: box.y })
            .id('reader-translation-background-' + index.toString())
        }, (_box: ReaderTranslationBounds, index: number) => index.toString())
        ForEach(this.translationLayouts(), (item: ReaderTranslationLayout) => {
          Text(item.text)
            .width(item.width)
            .height(item.height)
            .fontSize(item.fontSize)
            .fontColor(Color.Black)
            .lineHeight(item.lineHeight)
            .maxLines(item.maxLines)
            .textAlign(TextAlign.Center)
            .padding({ left: 2, right: 2, top: 2, bottom: 2 })
            .textShadow({ radius: 3, color: 'rgba(255,255,255,0.96)', offsetX: 0, offsetY: 0 })
            .position({ x: item.x, y: item.y })
            .id('reader-translation-text-' + item.key)
        }, (item: ReaderTranslationLayout) => item.key)
      }
    }
    .width(this.displayWidth)
    .height(this.displayHeight)
    .clip(true)
    .hitTestBehavior(HitTestMode.Transparent)
  }
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
