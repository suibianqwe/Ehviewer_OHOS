import { image } from '@kit.ImageKit';
import { acquireImageSource, releaseImageSource } from './ReaderPixelMapCache';

const SAMPLE_MAX_EDGE: number = 360;
const CROP_CACHE_LIMIT: number = 160;
const MAX_ACTIVE_ANALYSES: number = 2;

export class ReaderCropRect {
  x: number;
  y: number;
  width: number;
  height: number;

  constructor(x: number = 0, y: number = 0, width: number = 1, height: number = 1) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }
}

interface ReaderCropCacheEntry {
  key: string;
  rect: ReaderCropRect;
  lastAccess: number;
}

interface PendingReaderCrop {
  key: string;
  promise: Promise<ReaderCropRect>;
}

const CROP_CACHE: ReaderCropCacheEntry[] = [];
const PENDING_CROPS: PendingReaderCrop[] = [];
const WAITING_ANALYSES: (() => void)[] = [];
let activeAnalyses: number = 0;

export class ReaderWhiteBorderCropService {
  async analyze(cacheKey: string, sourcePath: string): Promise<ReaderCropRect> {
    if (sourcePath.length === 0) {
      return fullCropRect();
    }
    const key = cacheKey.length > 0 ? cacheKey + '|' + sourcePath : sourcePath;
    const cached = getCachedCrop(key);
    if (cached !== null) {
      return cached;
    }
    const pending = getPendingCrop(key);
    if (pending !== null) {
      return pending;
    }
    const promise = this.analyzeSource(key, sourcePath);
    PENDING_CROPS.push({ key: key, promise: promise });
    try {
      const rect = await promise;
      putCachedCrop(key, rect);
      return copyCropRect(rect);
    } finally {
      removePendingCrop(key);
    }
  }

  private async analyzeSource(_key: string, sourcePath: string): Promise<ReaderCropRect> {
    await acquireAnalysisSlot();
    let imageSource: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    let reusedSource: boolean = false;
    try {
      const reused = acquireImageSource(sourcePath);
      if (reused !== undefined) {
        imageSource = reused;
        reusedSource = true;
      } else {
        imageSource = image.createImageSource(sourcePath);
      }
      const sourceInfo = await imageSource.getImageInfo(0);
      if (sourceInfo.size.width <= 0 || sourceInfo.size.height <= 0) {
        return fullCropRect();
      }
      const sampleSize = sampleDimensions(sourceInfo.size.width, sourceInfo.size.height);
      const options: image.DecodingOptions = {
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: sampleSize,
        index: 0
      };
      pixelMap = await imageSource.createPixelMap(options);
      const sampleInfo = await pixelMap.getImageInfo();
      const byteCount = pixelMap.getPixelBytesNumber();
      if (sampleInfo.size.width <= 0 || sampleInfo.size.height <= 0 || byteCount <= 0) {
        return fullCropRect();
      }
      const pixels = new ArrayBuffer(byteCount);
      await pixelMap.readPixelsToBuffer(pixels);
      return detectWhiteBorder(new Uint8Array(pixels), sampleInfo.size.width, sampleInfo.size.height, byteCount);
    } catch (_error) {
      return fullCropRect();
    } finally {
      if (pixelMap !== undefined) {
        try {
          await pixelMap.release();
        } catch (_error) {
        }
      }
      if (imageSource !== undefined) {
        if (reusedSource) {
          releaseImageSource(sourcePath, imageSource);
        } else {
          try {
            await imageSource.release();
          } catch (_error) {
          }
        }
      }
      releaseAnalysisSlot();
    }
  }
}

function sampleDimensions(width: number, height: number): image.Size {
  const longest = Math.max(width, height);
  if (longest <= SAMPLE_MAX_EDGE) {
    return { width: width, height: height };
  }
  const scale = SAMPLE_MAX_EDGE / longest;
  return {
    width: Math.max(24, Math.round(width * scale)),
    height: Math.max(24, Math.round(height * scale))
  };
}

function detectWhiteBorder(pixels: Uint8Array, width: number, height: number, byteCount: number): ReaderCropRect {
  const rowStride = Math.floor(byteCount / height);
  if (width < 12 || height < 12 || rowStride < width * 4) {
    return fullCropRect();
  }
  const background = estimateBorderBackground(pixels, width, height, rowStride);
  if (background === null) {
    return fullCropRect();
  }
  const rowThreshold = Math.max(2, Math.floor(width * 0.006));
  const columnThreshold = Math.max(2, Math.floor(height * 0.006));
  let top = findContentRow(pixels, width, height, rowStride, background, 0, 1, rowThreshold);
  let bottom = findContentRow(pixels, width, height, rowStride, background, height - 1, -1, rowThreshold);
  let left = findContentColumn(pixels, width, height, rowStride, background, 0, 1, columnThreshold);
  let right = findContentColumn(pixels, width, height, rowStride, background, width - 1, -1, columnThreshold);
  if (top < 0 || bottom < top || left < 0 || right < left) {
    return fullCropRect();
  }
  const margin = 2;
  top = Math.max(0, top - margin);
  bottom = Math.min(height - 1, bottom + margin);
  left = Math.max(0, left - margin);
  right = Math.min(width - 1, right + margin);
  const keptWidth = right - left + 1;
  const keptHeight = bottom - top + 1;
  if (keptWidth < width * 0.35 || keptHeight < height * 0.35) {
    return fullCropRect();
  }
  const removedWidth = width - keptWidth;
  const removedHeight = height - keptHeight;
  if (removedWidth < Math.max(3, width * 0.012) && removedHeight < Math.max(3, height * 0.012)) {
    return fullCropRect();
  }
  return new ReaderCropRect(left / width, top / height, keptWidth / width, keptHeight / height);
}

class ReaderCropBackground {
  red: number;
  green: number;
  blue: number;
  dark: boolean;

  constructor(red: number, green: number, blue: number, dark: boolean) {
    this.red = red;
    this.green = green;
    this.blue = blue;
    this.dark = dark;
  }
}

function estimateBorderBackground(pixels: Uint8Array, width: number, height: number,
  rowStride: number): ReaderCropBackground | null {
  const patch = Math.max(2, Math.min(8, Math.floor(Math.min(width, height) * 0.04)));
  const corners: ReaderCropBackground[] = [];
  appendCornerBackground(corners, pixels, width, height, rowStride, 0, 0, patch);
  appendCornerBackground(corners, pixels, width, height, rowStride, width - patch, 0, patch);
  appendCornerBackground(corners, pixels, width, height, rowStride, 0, height - patch, patch);
  appendCornerBackground(corners, pixels, width, height, rowStride, width - patch, height - patch, patch);
  let lightCount = 0;
  let darkCount = 0;
  for (let i = 0; i < corners.length; i++) {
    if (corners[i].dark) {
      darkCount++;
    } else {
      lightCount++;
    }
  }
  const useDark = darkCount > lightCount;
  const matchingCount = useDark ? darkCount : lightCount;
  if (matchingCount < 2) {
    return null;
  }
  let red = 0;
  let green = 0;
  let blue = 0;
  for (let i = 0; i < corners.length; i++) {
    if (corners[i].dark !== useDark) {
      continue;
    }
    red += corners[i].red;
    green += corners[i].green;
    blue += corners[i].blue;
  }
  return new ReaderCropBackground(red / matchingCount, green / matchingCount, blue / matchingCount, useDark);
}

function appendCornerBackground(result: ReaderCropBackground[], pixels: Uint8Array, width: number, height: number,
  rowStride: number, startX: number, startY: number, patch: number): void {
  let red = 0;
  let green = 0;
  let blue = 0;
  let count = 0;
  let minimumLuminance = 255;
  let maximumLuminance = 0;
  const endX = Math.min(width, startX + patch);
  const endY = Math.min(height, startY + patch);
  for (let y = Math.max(0, startY); y < endY; y++) {
    for (let x = Math.max(0, startX); x < endX; x++) {
      const offset = y * rowStride + x * 4;
      red += pixels[offset];
      green += pixels[offset + 1];
      blue += pixels[offset + 2];
      const luminance = pixels[offset] * 0.2126 + pixels[offset + 1] * 0.7152 + pixels[offset + 2] * 0.0722;
      minimumLuminance = Math.min(minimumLuminance, luminance);
      maximumLuminance = Math.max(maximumLuminance, luminance);
      count++;
    }
  }
  if (count <= 0) {
    return;
  }
  red /= count;
  green /= count;
  blue /= count;
  const luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722;
  const spread = Math.max(red, green, blue) - Math.min(red, green, blue);
  const uniform = maximumLuminance - minimumLuminance <= 52;
  if (uniform && luminance >= 205 && spread <= 48) {
    result.push(new ReaderCropBackground(red, green, blue, false));
  } else if (uniform && luminance <= 55 && spread <= 48) {
    result.push(new ReaderCropBackground(red, green, blue, true));
  }
}

function isBorderPixel(pixels: Uint8Array, offset: number, background: ReaderCropBackground): boolean {
  const red = pixels[offset];
  const green = pixels[offset + 1];
  const blue = pixels[offset + 2];
  const luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722;
  const distance = Math.abs(red - background.red) + Math.abs(green - background.green) +
    Math.abs(blue - background.blue);
  if (background.dark) {
    return luminance <= 72 && distance <= 84;
  }
  return luminance >= 188 && distance <= 84;
}

function findContentRow(pixels: Uint8Array, width: number, height: number, rowStride: number,
  background: ReaderCropBackground, start: number, step: number, threshold: number): number {
  for (let y = start; y >= 0 && y < height; y += step) {
    let content = 0;
    for (let x = 0; x < width; x++) {
      if (!isBorderPixel(pixels, y * rowStride + x * 4, background)) {
        content++;
        if (content >= threshold) {
          return y;
        }
      }
    }
  }
  return -1;
}

function findContentColumn(pixels: Uint8Array, width: number, height: number, rowStride: number,
  background: ReaderCropBackground, start: number, step: number, threshold: number): number {
  for (let x = start; x >= 0 && x < width; x += step) {
    let content = 0;
    for (let y = 0; y < height; y++) {
      if (!isBorderPixel(pixels, y * rowStride + x * 4, background)) {
        content++;
        if (content >= threshold) {
          return x;
        }
      }
    }
  }
  return -1;
}

function fullCropRect(): ReaderCropRect {
  return new ReaderCropRect();
}

function copyCropRect(rect: ReaderCropRect): ReaderCropRect {
  return new ReaderCropRect(rect.x, rect.y, rect.width, rect.height);
}

function getCachedCrop(key: string): ReaderCropRect | null {
  for (let i = CROP_CACHE.length - 1; i >= 0; i--) {
    if (CROP_CACHE[i].key === key) {
      CROP_CACHE[i].lastAccess = Date.now();
      return copyCropRect(CROP_CACHE[i].rect);
    }
  }
  return null;
}

function putCachedCrop(key: string, rect: ReaderCropRect): void {
  while (CROP_CACHE.length >= CROP_CACHE_LIMIT) {
    let oldestIndex = 0;
    for (let i = 1; i < CROP_CACHE.length; i++) {
      if (CROP_CACHE[i].lastAccess < CROP_CACHE[oldestIndex].lastAccess) {
        oldestIndex = i;
      }
    }
    CROP_CACHE.splice(oldestIndex, 1);
  }
  CROP_CACHE.push({ key: key, rect: copyCropRect(rect), lastAccess: Date.now() });
}

function getPendingCrop(key: string): Promise<ReaderCropRect> | null {
  for (let i = 0; i < PENDING_CROPS.length; i++) {
    if (PENDING_CROPS[i].key === key) {
      return PENDING_CROPS[i].promise;
    }
  }
  return null;
}

function removePendingCrop(key: string): void {
  for (let i = PENDING_CROPS.length - 1; i >= 0; i--) {
    if (PENDING_CROPS[i].key === key) {
      PENDING_CROPS.splice(i, 1);
    }
  }
}

async function acquireAnalysisSlot(): Promise<void> {
  if (activeAnalyses < MAX_ACTIVE_ANALYSES) {
    activeAnalyses++;
    return;
  }
  await new Promise<void>((resolve: () => void) => {
    WAITING_ANALYSES.push(resolve);
  });
  activeAnalyses++;
}

function releaseAnalysisSlot(): void {
  activeAnalyses = Math.max(0, activeAnalyses - 1);
  const next = WAITING_ANALYSES.shift();
  if (next !== undefined) {
    next();
  }
}

export const readerWhiteBorderCropService: ReaderWhiteBorderCropService = new ReaderWhiteBorderCropService();
