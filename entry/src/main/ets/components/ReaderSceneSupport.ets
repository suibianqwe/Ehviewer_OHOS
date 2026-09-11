import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { GalleryPage } from '../model/GalleryModels';
import { readerHdrService } from '../services/ReaderHdrService';
import { readerImageAdjustmentService } from '../services/ReaderImageAdjustmentService';
import { readerSuperResolutionService } from '../services/ReaderSuperResolutionService';
import { ReaderPreviewModel } from './reader/core/ReaderCore';

export const SLIDER_AUTO_HIDE_DELAY: number = 3000;
export const READER_SCREEN_TAP_DELAY: number = 300;
export const READER_PAIRED_TAP_DELAY: number = 420;
export const READER_PAIRED_TAP_MOVE_TOLERANCE: number = 14;
export const READER_PAIRED_DOUBLE_TAP_DISTANCE: number = 48;
export const READER_DUAL_PAGE_OVERFLOW_RATIO: number = 1.15;
export const READER_PAGE_GROUP_REFRESH_DELAY: number = 220;
export const READER_TRANSLATION_BUTTON_SIZE: number = 52;
export const READER_TRANSLATION_BUTTON_EDGE: number = 8;
export const READER_AXIS_PAGE_INTERVAL: number = 140;

export function mediaAssetTitle(fileName: string): string {
  const dotIndex = fileName.lastIndexOf('.');
  const baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  const cleaned = baseName.replace(/[.\\/:*?"'`<>|{}\[\]]/g, '_').replace(/\s+/g, ' ').trim();
  if (cleaned.length === 0) {
    return 'ehviewer_page';
  }
  return cleaned.length > 120 ? cleaned.substring(0, 120).trim() : cleaned;
}

export interface ReaderPageState {
  index: number;
  page: GalleryPage;
}

export interface ReaderPageImageSize {
  index: number;
  width: number;
  height: number;
}

export interface ReaderSuperResolutionDisplayTarget {
  width: number;
  height: number;
}

export interface ReaderPageGroupItem {
  index: number;
  key: string;
  paired: boolean;
}

export class ReaderProcessedImageLease {
  pixelMap: image.PixelMap | undefined = undefined;
  superResolutionKey: string = '';
  hdrKey: string = '';
  adjustmentKey: string = '';

  release(): void {
    if (this.hdrKey.length > 0) {
      readerHdrService.release(this.hdrKey);
      this.hdrKey = '';
    }
    if (this.superResolutionKey.length > 0) {
      readerSuperResolutionService.release(this.superResolutionKey);
      this.superResolutionKey = '';
    }
    if (this.adjustmentKey.length > 0) {
      readerImageAdjustmentService.release(this.adjustmentKey);
      this.adjustmentKey = '';
    }
    this.pixelMap = undefined;
  }
}

@Component
export struct ReaderPairedTransformViewport {
  @ObjectLink model: ReaderPreviewModel;
  @BuilderParam content: () => void = this.EmptyContent;

  @Builder
  private EmptyContent() {
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      this.content()
    }
    .scale({
      x: this.model.currentScale,
      y: this.model.currentScale,
      centerX: '50%',
      centerY: '50%'
    })
    .translate({
      x: this.model.currentOffsetX,
      y: this.model.currentOffsetY
    })
  }
}
export function usableReaderLocalPath(path: string): string {
  if (path.length === 0 || path.endsWith('.part')) {
    return '';
  }
  try {
    return fs.statSync(path).size > 0 ? path : '';
  } catch (error) {
    return '';
  }
}

