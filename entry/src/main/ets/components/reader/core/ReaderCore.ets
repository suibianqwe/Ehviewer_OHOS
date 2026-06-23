import { image } from '@kit.ImageKit';
import { GalleryPage } from '../../../model/GalleryModels';
import { ehSettingsStore } from '../../../services/EhSettingsStore';
import { readerImageCache } from '../../../services/ReaderImageCache';
import { getAbilityContext, readerDisplayImageUrl } from '../../../shared/EhShared';

export const READER_MIN_SCALE: number = 0.25;
export const READER_BASE_SCALE: number = 1;
export const READER_MAX_SCALE: number = 4;
export const READER_DOUBLE_TAP_SCALE: number = 2.25;
export const READER_INERTIA_DURATION: number = 180;
export const READER_OFFSCREEN_RENDER_COUNT: number = 2;

export interface ReaderImageCompleteEvent {
  width: number;
  height: number;
  componentWidth: number;
  componentHeight: number;
  loadingStatus: number;
}

export interface ReaderSourceImageSize {
  width: number;
  height: number;
}

export function readerBackgroundColor(): string {
  const value = ehSettingsStore.getValue('reader_background', 'Deep gray');
  if (value === 'Black') {
    return '#000000';
  }
  if (value === 'White') {
    return '#FFFFFF';
  }
  return '#050608';
}

export function stripFileScheme(path: string): string {
  return path.indexOf('file://') === 0 ? path.substring('file://'.length) : path;
}

export function readerLocalSourceImagePath(page: GalleryPage, preferOriginal: boolean): string {
  if (preferOriginal && page.cachedOriginImagePath !== undefined && page.cachedOriginImagePath.length > 0) {
    return stripFileScheme(page.cachedOriginImagePath);
  }
  if (!preferOriginal && page.cachedImagePath !== undefined && page.cachedImagePath.length > 0) {
    return stripFileScheme(page.cachedImagePath);
  }
  if (page.cachedImagePath !== undefined && page.cachedImagePath.length > 0) {
    return stripFileScheme(page.cachedImagePath);
  }
  if (page.cachedOriginImagePath !== undefined && page.cachedOriginImagePath.length > 0) {
    return stripFileScheme(page.cachedOriginImagePath);
  }
  const displayUrl = readerDisplayImageUrl(page, preferOriginal);
  if (displayUrl.indexOf('file://') === 0) {
    return stripFileScheme(displayUrl);
  }
  const context = getAbilityContext();
  if (context === undefined) {
    return '';
  }
  const sourceUrl = preferOriginal && page.originImageUrl.length > 0 ? page.originImageUrl : page.imageUrl;
  return readerImageCache.getCachedPath(context, sourceUrl);
}

export async function readReaderSourceImageSize(path: string): Promise<ReaderSourceImageSize> {
  let imageSource: image.ImageSource | undefined = undefined;
  try {
    imageSource = image.createImageSource(path);
    const imageInfo: image.ImageInfo = imageSource.getImageInfoSync();
    return {
      width: imageInfo.size.width,
      height: imageInfo.size.height
    };
  } catch (error) {
    return { width: 0, height: 0 };
  } finally {
    if (imageSource !== undefined) {
      try {
        await imageSource.release();
      } catch (error) {
      }
    }
  }
}

@Observed
export class ReaderPreviewModel {
  currentScale: number = READER_BASE_SCALE;
  lastScale: number = READER_BASE_SCALE;
  currentOffsetX: number = 0;
  currentOffsetY: number = 0;
  lastOffsetX: number = 0;
  lastOffsetY: number = 0;
  componentWidth: number = 1;
  componentHeight: number = 1;
  imageWidth: number = 1;
  imageHeight: number = 1;
  centerX: number = 0.5;
  centerY: number = 0.5;
  disableSwipe: boolean = false;

  reset(): void {
    this.currentScale = READER_BASE_SCALE;
    this.lastScale = READER_BASE_SCALE;
    this.currentOffsetX = 0;
    this.currentOffsetY = 0;
    this.lastOffsetX = 0;
    this.lastOffsetY = 0;
    this.centerX = 0.5;
    this.centerY = 0.5;
    this.disableSwipe = false;
  }

  setComponentSize(width: number, height: number): void {
    if (width > 0) {
      this.componentWidth = width;
    }
    if (height > 0) {
      this.componentHeight = height;
    }
    this.restrictBoundary();
    this.commit();
  }

  setImageSize(width: number, height: number): void {
    if (width > 0) {
      this.imageWidth = width;
    }
    if (height > 0) {
      this.imageHeight = height;
    }
    this.restrictBoundary();
    this.commit();
  }

  pinchStart(centerX: number, centerY: number): void {
    const center = this.evaluateCenter(centerX, centerY);
    this.centerX = center[0];
    this.centerY = center[1];
    this.lastScale = this.currentScale;
    this.lastOffsetX = this.currentOffsetX;
    this.lastOffsetY = this.currentOffsetY;
    this.disableSwipe = true;
  }

  pinchUpdate(scale: number): void {
    if (scale <= 0 || Number.isNaN(scale)) {
      return;
    }
    const nextScale = this.clampScale(this.lastScale * scale);
    const deltaScale = nextScale / this.lastScale;
    this.currentScale = nextScale;
    this.currentOffsetX = this.lastOffsetX + (0.5 - this.centerX) * this.imageWidth * (1 - deltaScale) * this.lastScale;
    this.currentOffsetY = this.lastOffsetY + (0.5 - this.centerY) * this.imageHeight * (1 - deltaScale) * this.lastScale;
    this.restrictBoundary();
  }

  pinchEnd(): void {
    this.restrictBoundary();
    this.commit();
  }

  panStart(): void {
    this.lastOffsetX = this.currentOffsetX;
    this.lastOffsetY = this.currentOffsetY;
    this.lastScale = this.currentScale;
    this.disableSwipe = this.canPanHorizontally() && !this.isHorizontalBoundary();
  }

  panUpdate(offsetX: number, offsetY: number): void {
    if (!this.canPan()) {
      this.disableSwipe = false;
      return;
    }
    this.currentOffsetX = this.lastOffsetX + offsetX;
    this.currentOffsetY = this.lastOffsetY + offsetY;
    this.restrictBoundary();
  }

  panEnd(velocityX: number = 0, velocityY: number = 0): void {
    if (this.canPan() && (Math.abs(velocityX) > 20 || Math.abs(velocityY) > 20)) {
      const inertiaX = Math.max(-180, Math.min(180, velocityX * 0.12));
      const inertiaY = Math.max(-180, Math.min(180, velocityY * 0.12));
      this.currentOffsetX += inertiaX;
      this.currentOffsetY += inertiaY;
    }
    this.restrictBoundary();
    this.commit();
  }

  edgeSwipeDirection(offsetX: number, velocityX: number = 0, offsetY: number = 0, velocityY: number = 0): number {
    const maxX = this.maxOffsetX();
    if (maxX <= 0 || !this.isHorizontalGestureIntent(offsetX, velocityX, offsetY, velocityY)) {
      return 0;
    }
    const direction = Math.abs(offsetX) >= 8 ? offsetX : velocityX;
    const strongDrag = Math.abs(offsetX) >= 14 || Math.abs(velocityX) >= 120;
    if (!strongDrag) {
      return 0;
    }
    if (direction < 0 && this.currentOffsetX <= -maxX + 0.5) {
      return -1;
    }
    if (direction > 0 && this.currentOffsetX >= maxX - 0.5) {
      return 1;
    }
    return 0;
  }

  toggleDoubleTap(centerX: number, centerY: number): void {
    if (Math.abs(this.currentScale - READER_BASE_SCALE) > 0.01) {
      this.reset();
      return;
    }
    const center = this.evaluateCenter(centerX, centerY);
    this.centerX = center[0];
    this.centerY = center[1];
    this.lastScale = READER_BASE_SCALE;
    this.lastOffsetX = 0;
    this.lastOffsetY = 0;
    this.currentScale = READER_DOUBLE_TAP_SCALE;
    this.currentOffsetX = (0.5 - this.centerX) * this.imageWidth * (1 - READER_DOUBLE_TAP_SCALE);
    this.currentOffsetY = (0.5 - this.centerY) * this.imageHeight * (1 - READER_DOUBLE_TAP_SCALE);
    this.restrictBoundary();
    this.commit();
  }

  zoomBy(factor: number): void {
    const target = this.clampScale(this.currentScale * factor);
    if (Math.abs(target - READER_BASE_SCALE) < 0.01) {
      this.reset();
      return;
    }
    this.currentScale = target;
    this.restrictBoundary();
    this.commit();
  }

  setScale(target: number): void {
    this.currentScale = this.clampScale(target);
    this.restrictBoundary();
    this.commit();
  }

  zoomPercent(): number {
    return Math.round(this.currentScale * 100);
  }

  canHandleLocalPan(): boolean {
    return this.canPanHorizontally();
  }

  shouldLetSwiperHandlePan(offsetX: number, velocityX: number, offsetY: number = 0, velocityY: number = 0): boolean {
    if (this.canPanVertically() && !this.isHorizontalGestureIntent(offsetX, velocityX, offsetY, velocityY)) {
      return false;
    }
    const maxX = this.maxOffsetX();
    const direction = Math.abs(offsetX) >= 1 ? offsetX : velocityX;
    if (maxX <= 0) {
      return true;
    }
    if (direction < -0.5 && this.currentOffsetX <= -maxX + 0.5) {
      return true;
    }
    if (direction > 0.5 && this.currentOffsetX >= maxX - 0.5) {
      return true;
    }
    return false;
  }

  private commit(): void {
    this.lastScale = this.currentScale;
    this.lastOffsetX = this.currentOffsetX;
    this.lastOffsetY = this.currentOffsetY;
    this.disableSwipe = this.canPanHorizontally() && !this.isHorizontalBoundary();
  }

  private clampScale(value: number): number {
    return Math.max(READER_MIN_SCALE, Math.min(READER_MAX_SCALE, value));
  }

  private evaluateCenter(centerX: number, centerY: number): [number, number] {
    const imgDisplayWidth = this.imageWidth * this.lastScale;
    const imgDisplayHeight = this.imageHeight * this.lastScale;
    const imgX = (this.componentWidth - imgDisplayWidth) / 2 + this.lastOffsetX;
    const imgY = (this.componentHeight - imgDisplayHeight) / 2 + this.lastOffsetY;
    const cX = Math.max(0, Math.min(1, (centerX - imgX) / imgDisplayWidth));
    const cY = Math.max(0, Math.min(1, (centerY - imgY) / imgDisplayHeight));
    return [cX, cY];
  }

  private maxOffsetX(): number {
    const scaledWidth = this.imageWidth * this.currentScale;
    return scaledWidth > this.componentWidth ? (scaledWidth - this.componentWidth) / 2 : 0;
  }

  private maxOffsetY(): number {
    const scaledHeight = this.imageHeight * this.currentScale;
    return scaledHeight > this.componentHeight ? (scaledHeight - this.componentHeight) / 2 : 0;
  }

  private restrictBoundary(): void {
    const maxX = this.maxOffsetX();
    const maxY = this.maxOffsetY();
    this.currentOffsetX = Math.max(-maxX, Math.min(maxX, this.currentOffsetX));
    this.currentOffsetY = Math.max(-maxY, Math.min(maxY, this.currentOffsetY));
    this.disableSwipe = this.canPanHorizontally() && !this.isHorizontalBoundary();
  }

  private isHorizontalBoundary(): boolean {
    const maxX = this.maxOffsetX();
    if (maxX <= 0) {
      return true;
    }
    return Math.abs(this.currentOffsetX) >= maxX - 0.5;
  }

  private canPan(): boolean {
    return this.maxOffsetX() > 0 || this.maxOffsetY() > 0;
  }

  private canPanHorizontally(): boolean {
    return this.maxOffsetX() > 0;
  }

  private canPanVertically(): boolean {
    return this.maxOffsetY() > 0;
  }

  private isHorizontalGestureIntent(offsetX: number, velocityX: number = 0, offsetY: number = 0, velocityY: number = 0): boolean {
    const x = Math.abs(offsetX) >= 1 ? Math.abs(offsetX) : Math.abs(velocityX);
    const y = Math.abs(offsetY) >= 1 ? Math.abs(offsetY) : Math.abs(velocityY);
    return x > 0.5 && x >= y * 1.15;
  }
}
