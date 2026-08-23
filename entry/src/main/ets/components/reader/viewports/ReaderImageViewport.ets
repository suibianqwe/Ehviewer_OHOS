import { image } from '@kit.ImageKit';
import { GalleryPage } from '../../../model/GalleryModels';
import { ReaderPageTranslation } from '../../../model/ReaderTranslationModels';
import {
  IMAGE_DOWNLOAD_PRIORITY_READER,
  ImageDownloadProgress,
  readerImageCache
} from '../../../services/ReaderImageCache';
import { readerHdrService } from '../../../services/ReaderHdrService';
import { readerImageAdjustmentService } from '../../../services/ReaderImageAdjustmentService';
import {
  readerImageColorFilter,
  ReaderImageAdjustmentSettings
} from '../../../services/ReaderImageAdjustmentSupport';
import { readerSuperResolutionService } from '../../../services/ReaderSuperResolutionService';
import {
  readerSuperResolutionEngineCacheKey,
  READER_SUPER_RESOLUTION_ENGINE_DETAIL
} from '../../../services/ReaderSuperResolutionSupport';
import {
  ReaderCropRect,
  readerWhiteBorderCropService
} from '../../../services/ReaderWhiteBorderCropService';
import {
  createEmptyPage,
  getAbilityContext,
  normalizePageScalingOption,
  normalizeStartPositionOption,
  readerDisplayImageUrl,
  readerPageImageCacheKey
} from '../../../shared/EhShared';
import {
  READER_BASE_SCALE,
  READER_INERTIA_DURATION,
  ReaderImageCompleteEvent,
  ReaderPreviewModel,
  cachedReaderSourceImageSize,
  cacheReaderImageComplete,
  cacheReaderSourceImageSize,
  forgetReaderImageRuntimeState,
  isReaderImageComplete,
  readReaderSourceImageSize,
  readerBackgroundColor,
  readerLocalSourceImagePath
} from '../core/ReaderCore';
import { ReaderStatusView } from '../status/ReaderStatusView';
import { ReaderTranslationOverlay } from '../overlays/ReaderTranslationOverlay';

@Component
export struct ReaderImageViewport {
  @Prop @Watch('onImageSourceChange') page: GalleryPage = createEmptyPage();
  @Prop statusText: string = '';
  @Prop @Watch('onImageSourceChange') preferOriginal: boolean = false;
  @Prop @Watch('onFitModeChange') fitMode: string = 'Fit screen';
  @Prop @Watch('onFixedScaleChange') fixedScale: number = READER_BASE_SCALE;
  @Prop startPosition: string = 'Top right';
  @Prop @Watch('onActiveChange') isActive: boolean = false;
  @Prop @Watch('onHdrEnabledChange') hdrEnabled: boolean = false;
  @Prop @Watch('onImageAdjustmentChange') imageAdjustmentSettings: ReaderImageAdjustmentSettings =
    new ReaderImageAdjustmentSettings();
  @Prop @Watch('onSuperResolutionEnabledChange') superResolutionEnabled: boolean = false;
  @Prop @Watch('onSuperResolutionEnabledChange') superResolutionEngine: string =
    READER_SUPER_RESOLUTION_ENGINE_DETAIL;
  @Prop @Watch('onSuperResolutionTargetChange') superResolutionTargetWidth: number = 0;
  @Prop @Watch('onSuperResolutionTargetChange') superResolutionTargetHeight: number = 0;
  @Prop @Watch('onHdrPriorityChange') hdrPriority: number = 0;
  @Prop @Watch('onCropWhiteBordersChange') cropWhiteBorders: boolean = false;
  @Prop translation: ReaderPageTranslation | null = null;
  @Prop allowEdgeSwipe: boolean = true;
  @Prop interactive: boolean = true;
  @Prop command: string = '';
  @Prop @Watch('onCommandChange') commandVersion: number = 0;
  onTap: (x: number, y: number, w: number, h: number) => void = () => {};
  onRetry: () => void = () => {};
  onImageLongPress: () => void = () => {};
  onSwipeLockChange: (locked: boolean) => void = (_locked: boolean) => {};
  onZoomChange: (percent: number) => void = (_percent: number) => {};
  onImageSizeChange: (width: number, height: number) => void = (_width: number, _height: number) => {};
  onEdgeSwipe: (direction: number) => void = (_direction: number) => {};

  @State imageModel: ReaderPreviewModel = new ReaderPreviewModel();
  @State completedImageUrl: string = '';
  @State failedImageUrl: string = '';
  @State sourceImageWidth: number = 0;
  @State sourceImageHeight: number = 0;
  @State displayImageWidth: number = 1;
  @State displayImageHeight: number = 1;
  @State downloadProgress: number = -1;
  @State imageRetryVersion: number = 0;
  @State hdrPixelMap: image.PixelMap | undefined = undefined;
  @State hdrFromSuperResolution: boolean = false;
  @State superResolutionPixelMap: image.PixelMap | undefined = undefined;
  @State adjustedPixelMap: image.PixelMap | undefined = undefined;
  @State cropRect: ReaderCropRect = new ReaderCropRect();
  private lastCommandVersion: number = -1;
  private sourceSizeRequestId: number = 0;
  private downloadProgressRequestId: number = 0;
  private retainedImageUrl: string = '';
  private retainedSourceIdentity: string = '';
  private retainedHdrKey: string = '';
  private hdrRequestId: number = 0;
  private retainedSuperResolutionKey: string = '';
  private superResolutionRequestId: number = 0;
  private superResolutionCompleted: boolean = false;
  private retainedAdjustmentKey: string = '';
  private adjustmentRequestId: number = 0;
  private adjustmentCompleted: boolean = false;
  private cropRequestId: number = 0;

  aboutToAppear(): void {
    this.onImageSourceChange();
    this.onFitModeChange();
    this.reportState();
  }

  aboutToDisappear(): void {
    this.releaseRuntimeState();
    if (this.isActive && this.interactive) {
      this.onSwipeLockChange(false);
    }
  }

  onCommandChange(): void {
    if (!this.interactive || !this.isActive || this.commandVersion === this.lastCommandVersion) {
      return;
    }
    this.lastCommandVersion = this.commandVersion;
    if (this.command === 'zoom_in') {
      this.imageModel.zoomBy(1.25);
    } else if (this.command === 'zoom_out') {
      this.imageModel.zoomBy(0.8);
    } else if (this.command === 'double_zoom') {
      this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
        this.imageModel.toggleDoubleTap(this.imageModel.componentWidth / 2,
          this.imageModel.componentHeight / 2);
      });
    } else if (this.command === 'reset') {
      this.imageModel.reset();
    } else if (this.command === 'fixed_scale') {
      this.syncFixedScale();
    }
    this.reportState();
  }

  onActiveChange(): void {
    if (this.isActive) {
      this.startDownloadProgressMonitor();
      this.syncFixedScale();
      this.reportImageSize();
    }
  }

  private imageUrl(): string {
    return readerDisplayImageUrl(this.page, this.preferOriginal);
  }

  private imageNodeId(): string {
    const sourceKey = this.sourceImageCacheKey().length > 0 ? this.sourceImageCacheKey() : this.imageUrl();
    const processingMode = this.hdrPixelMap !== undefined ? 'hdr-' :
      (this.superResolutionPixelMap !== undefined ? 'sr-' :
        (this.adjustedPixelMap !== undefined ? 'adjusted-' : 'sdr-'));
    return 'reader-image-' + this.imageRetryVersion.toString() + '-' +
      processingMode + sourceKey;
  }

  private displayPixelMap(): image.PixelMap | undefined {
    return this.hdrPixelMap !== undefined ? this.hdrPixelMap :
      (this.superResolutionPixelMap !== undefined ? this.superResolutionPixelMap : this.adjustedPixelMap);
  }

  private displayImageSource(): string | image.PixelMap {
    const pixelMap = this.displayPixelMap();
    return pixelMap === undefined ? this.imageUrl() : pixelMap;
  }

  private retryImage(): void {
    this.failedImageUrl = '';
    this.completedImageUrl = '';
    this.downloadProgress = -1;
    this.imageRetryVersion++;
    this.onRetry();
  }

  private isFailed(): boolean {
    const url = this.imageUrl();
    return this.statusText.indexOf('failed') >= 0 || this.statusText.indexOf('Failed') >= 0 ||
      (url.length > 0 && this.failedImageUrl === url);
  }

  private isImageLoading(): boolean {
    const url = this.imageUrl();
    return url.length > 0 && this.completedImageUrl !== url && this.failedImageUrl !== url;
  }

  private isImageReady(): boolean {
    const url = this.imageUrl();
    return url.length > 0 && this.completedImageUrl === url && this.failedImageUrl !== url;
  }

  private shouldSyncLoadImage(): boolean {
    const url = this.imageUrl();
    return this.localSourceImagePath().length > 0 || isReaderImageComplete(url);
  }

  private onImageSourceChange(): void {
    const url = this.imageUrl();
    const sourceIdentity = this.imageSourceIdentity();
    if (sourceIdentity === this.retainedSourceIdentity) {
      return;
    }
    this.retainedSourceIdentity = sourceIdentity;
    this.releaseHdrPixelMap();
    this.releaseSuperResolutionPixelMap();
    this.releaseAdjustedPixelMap();
    this.cropRect = new ReaderCropRect();
    if (this.retainedImageUrl.length > 0 && this.retainedImageUrl !== url) {
      forgetReaderImageRuntimeState(this.retainedImageUrl);
    }
    this.retainedImageUrl = url;
    const requestId = this.sourceSizeRequestId + 1;
    this.sourceSizeRequestId = requestId;
    if (this.completedImageUrl !== url) {
      this.completedImageUrl = isReaderImageComplete(url) ? url : '';
    }
    if (this.failedImageUrl !== url) {
      this.failedImageUrl = '';
    }
    const cachedSize = cachedReaderSourceImageSize(url);
    this.sourceImageWidth = cachedSize.width;
    this.sourceImageHeight = cachedSize.height;
    if (this.isActive && !this.hasSourceImageSize()) {
      this.onImageSizeChange(0, 0);
    }
    this.updateDisplayImageSize();
    this.reportImageSize();
    this.loadCachedSourceImageSize(requestId, url).catch(() => {});
    this.loadAdjustedPixelMap();
    this.loadSuperResolutionPixelMap();
    this.loadHdrPixelMap();
    this.loadCropRect();
    this.startDownloadProgressMonitor();
    this.syncFixedScale();
  }

  private releaseRuntimeState(): void {
    this.sourceSizeRequestId++;
    this.downloadProgressRequestId++;
    forgetReaderImageRuntimeState(this.retainedImageUrl);
    this.retainedImageUrl = '';
    this.retainedSourceIdentity = '';
    this.releaseHdrPixelMap();
    this.releaseSuperResolutionPixelMap();
    this.releaseAdjustedPixelMap();
    this.cropRequestId++;
  }

  onCropWhiteBordersChange(): void {
    this.cropRect = new ReaderCropRect();
    this.updateDisplayImageSize();
    this.reportImageSize();
    this.loadCropRect();
  }

  onHdrEnabledChange(): void {
    this.startDownloadProgressMonitor();
    this.loadHdrPixelMap();
  }

  onImageAdjustmentChange(): void {
    this.releaseHdrPixelMap();
    this.releaseSuperResolutionPixelMap();
    this.releaseAdjustedPixelMap();
    this.loadAdjustedPixelMap();
    this.loadSuperResolutionPixelMap();
    this.loadHdrPixelMap();
  }

  onSuperResolutionEnabledChange(): void {
    this.releaseHdrPixelMap();
    this.releaseSuperResolutionPixelMap();
    this.startDownloadProgressMonitor();
    this.loadSuperResolutionPixelMap();
    this.loadHdrPixelMap();
  }

  onSuperResolutionTargetChange(): void {
    if (!this.superResolutionEnabled && !this.imageAdjustmentSettings.hasMoireReduction()) {
      return;
    }
    this.releaseHdrPixelMap();
    this.releaseSuperResolutionPixelMap();
    if (this.imageAdjustmentSettings.hasMoireReduction()) {
      this.releaseAdjustedPixelMap();
      this.loadAdjustedPixelMap();
    }
    this.loadSuperResolutionPixelMap();
    this.loadHdrPixelMap();
  }

  private superResolutionKey(sourcePath: string): string {
    const inputKey = this.imageAdjustmentSettings.requiresOfflineProcessing() &&
      this.adjustedPixelMap !== undefined && this.retainedAdjustmentKey.length > 0 ?
      this.retainedAdjustmentKey : this.sourceImageCacheKey() + '|' + sourcePath;
    return inputKey + '|sr|' +
      readerSuperResolutionEngineCacheKey(this.superResolutionEngine) + '|' +
      Math.max(0, Math.round(this.superResolutionTargetWidth)).toString() + 'x' +
      Math.max(0, Math.round(this.superResolutionTargetHeight)).toString();
  }

  onHdrPriorityChange(): void {
    if (this.retainedHdrKey.length > 0) {
      readerHdrService.updatePriority(this.retainedHdrKey, this.hdrPriority);
    }
    if (this.retainedSuperResolutionKey.length > 0) {
      readerSuperResolutionService.updatePriority(this.retainedSuperResolutionKey, this.hdrPriority);
    }
    if (this.retainedAdjustmentKey.length > 0) {
      readerImageAdjustmentService.updatePriority(this.retainedAdjustmentKey, this.hdrPriority);
    }
  }

  private loadHdrPixelMap(): void {
    const sourcePath = this.localSourceImagePath();
    if (!this.hdrEnabled || sourcePath.length === 0 || this.imageUrl().length === 0) {
      this.releaseHdrPixelMap();
      return;
    }
    if (this.superResolutionEnabled && !this.superResolutionCompleted) {
      this.releaseHdrPixelMap();
      this.loadSuperResolutionPixelMap();
      return;
    }
    if (this.superResolutionEnabled && this.superResolutionPixelMap !== undefined &&
      this.retainedSuperResolutionKey.length > 0) {
      const key = this.retainedSuperResolutionKey + '|hdr';
      if (this.retainedHdrKey === key) {
        return;
      }
      this.releaseHdrPixelMap();
      const requestId = ++this.hdrRequestId;
      this.retainedHdrKey = key;
      readerHdrService.acquirePixelMap(key, this.superResolutionPixelMap, this.hdrPriority)
        .then((pixelMap: image.PixelMap | undefined) => {
          if (requestId === this.hdrRequestId && key === this.retainedHdrKey && this.hdrEnabled) {
            this.hdrFromSuperResolution = pixelMap !== undefined;
            this.hdrPixelMap = pixelMap;
          }
        }).catch(() => {});
      return;
    }
    if (this.imageAdjustmentSettings.requiresOfflineProcessing() && !this.adjustmentCompleted) {
      this.releaseHdrPixelMap();
      this.loadAdjustedPixelMap();
      return;
    }
    if (this.imageAdjustmentSettings.requiresOfflineProcessing() && this.adjustedPixelMap !== undefined &&
      this.retainedAdjustmentKey.length > 0) {
      const key = this.retainedAdjustmentKey + '|hdr';
      if (this.retainedHdrKey === key) {
        return;
      }
      this.releaseHdrPixelMap();
      const requestId = ++this.hdrRequestId;
      this.retainedHdrKey = key;
      readerHdrService.acquirePixelMap(key, this.adjustedPixelMap, this.hdrPriority)
        .then((pixelMap: image.PixelMap | undefined) => {
          if (requestId === this.hdrRequestId && key === this.retainedHdrKey && this.hdrEnabled) {
            this.hdrFromSuperResolution = false;
            this.hdrPixelMap = pixelMap;
          }
        }).catch(() => {});
      return;
    }
    const key = this.sourceImageCacheKey() + '|' + sourcePath + '|hdr';
    if (this.retainedHdrKey === key) {
      return;
    }
    this.releaseHdrPixelMap();
    const requestId = this.hdrRequestId + 1;
    this.hdrRequestId = requestId;
    this.retainedHdrKey = key;
    readerHdrService.acquire(key, sourcePath, this.hdrPriority).then((pixelMap: image.PixelMap | undefined) => {
      if (requestId !== this.hdrRequestId || key !== this.retainedHdrKey || !this.hdrEnabled) {
        return;
      }
      this.hdrFromSuperResolution = false;
      this.hdrPixelMap = pixelMap;
    }).catch(() => {});
  }

  private releaseHdrPixelMap(): void {
    this.hdrRequestId++;
    this.hdrPixelMap = undefined;
    this.hdrFromSuperResolution = false;
    if (this.retainedHdrKey.length > 0) {
      readerHdrService.release(this.retainedHdrKey);
      this.retainedHdrKey = '';
    }
  }

  private loadSuperResolutionPixelMap(): void {
    const sourcePath = this.localSourceImagePath();
    if (!this.superResolutionEnabled || sourcePath.length === 0 || this.imageUrl().length === 0) {
      this.releaseSuperResolutionPixelMap();
      return;
    }
    if (this.imageAdjustmentSettings.requiresOfflineProcessing() && !this.adjustmentCompleted) {
      this.releaseSuperResolutionPixelMap();
      this.loadAdjustedPixelMap();
      return;
    }
    const key = this.superResolutionKey(sourcePath);
    if (this.retainedSuperResolutionKey === key) {
      return;
    }
    this.releaseSuperResolutionPixelMap();
    this.superResolutionCompleted = false;
    const requestId = this.superResolutionRequestId + 1;
    this.superResolutionRequestId = requestId;
    this.retainedSuperResolutionKey = key;
    const pending = this.adjustedPixelMap !== undefined ?
      readerSuperResolutionService.acquirePixelMap(key, this.adjustedPixelMap, this.hdrPriority,
        this.superResolutionTargetWidth, this.superResolutionTargetHeight, this.superResolutionEngine) :
      readerSuperResolutionService.acquire(key, sourcePath, this.hdrPriority,
        this.superResolutionTargetWidth, this.superResolutionTargetHeight, this.superResolutionEngine);
    pending
      .then((pixelMap: image.PixelMap | undefined) => {
        if (requestId !== this.superResolutionRequestId || key !== this.retainedSuperResolutionKey ||
          !this.superResolutionEnabled) {
          return;
        }
        this.superResolutionCompleted = true;
        this.superResolutionPixelMap = pixelMap;
        this.loadHdrPixelMap();
      }).catch(() => {
        if (requestId === this.superResolutionRequestId && key === this.retainedSuperResolutionKey &&
          this.superResolutionEnabled) {
          this.superResolutionCompleted = true;
          this.loadHdrPixelMap();
        }
      });
  }

  private releaseSuperResolutionPixelMap(): void {
    this.superResolutionRequestId++;
    this.superResolutionCompleted = false;
    this.superResolutionPixelMap = undefined;
    if (this.retainedSuperResolutionKey.length > 0) {
      readerSuperResolutionService.release(this.retainedSuperResolutionKey);
      this.retainedSuperResolutionKey = '';
    }
  }

  private loadAdjustedPixelMap(): void {
    const sourcePath = this.localSourceImagePath();
    if (!this.imageAdjustmentSettings.requiresOfflineProcessing() || sourcePath.length === 0 ||
      this.imageUrl().length === 0) {
      this.releaseAdjustedPixelMap();
      return;
    }
    const key = this.sourceImageCacheKey() + '|' + sourcePath + '|adjust|' +
      this.imageAdjustmentSettings.detailCacheKey() + '|target|' +
      this.superResolutionTargetWidth.toString() + 'x' + this.superResolutionTargetHeight.toString();
    if (this.retainedAdjustmentKey === key) {
      return;
    }
    this.releaseAdjustedPixelMap();
    this.adjustmentCompleted = false;
    const requestId = ++this.adjustmentRequestId;
    this.retainedAdjustmentKey = key;
    const pending = readerImageAdjustmentService.acquire(key, sourcePath,
      this.imageAdjustmentSettings, this.hdrPriority, false,
      this.superResolutionTargetWidth, this.superResolutionTargetHeight);
    pending.then((pixelMap: image.PixelMap | undefined) => {
      if (requestId !== this.adjustmentRequestId || key !== this.retainedAdjustmentKey ||
        !this.imageAdjustmentSettings.requiresOfflineProcessing()) {
        return;
      }
      this.adjustmentCompleted = true;
      this.adjustedPixelMap = pixelMap;
      this.loadSuperResolutionPixelMap();
      this.loadHdrPixelMap();
    }).catch(() => {
      if (requestId === this.adjustmentRequestId && key === this.retainedAdjustmentKey) {
        this.adjustmentCompleted = true;
        this.loadSuperResolutionPixelMap();
        this.loadHdrPixelMap();
      }
    });
  }

  private releaseAdjustedPixelMap(): void {
    this.adjustmentRequestId++;
    this.adjustmentCompleted = false;
    this.adjustedPixelMap = undefined;
    if (this.retainedAdjustmentKey.length > 0) {
      readerImageAdjustmentService.release(this.retainedAdjustmentKey);
      this.retainedAdjustmentKey = '';
    }
  }

  private onFitModeChange(): void {
    this.updateDisplayImageSize();
    if (!this.syncFixedScale()) {
      this.imageModel.reset();
    }
    this.reportState();
  }

  private syncFixedScale(): boolean {
    if (normalizePageScalingOption(this.fitMode) !== 'Fixed scale') {
      return false;
    }
    this.imageModel.setScale(this.fixedScale);
    return true;
  }

  onFixedScaleChange(): void {
    if (normalizePageScalingOption(this.fitMode) === 'Fixed scale') {
      this.imageModel.setScale(this.fixedScale);
      this.reportState();
    }
  }

  private imageObjectFit(): ImageFit {
    if (!this.hasSourceImageSize() || this.displayImageWidth <= 1 || this.displayImageHeight <= 1) {
      return ImageFit.Contain;
    }
    return ImageFit.Fill;
  }

  private hasSourceImageSize(): boolean {
    return this.sourceImageWidth > 0 && this.sourceImageHeight > 0;
  }

  private async loadCachedSourceImageSize(requestId: number, imageUrl: string): Promise<void> {
    const path = this.localSourceImagePath();
    if (path.length === 0) {
      return;
    }
    const size = await readReaderSourceImageSize(path);
    if (requestId !== this.sourceSizeRequestId || imageUrl !== this.imageUrl()) {
      return;
    }
    if (size.width > 0 && size.height > 0) {
      this.sourceImageWidth = size.width;
      this.sourceImageHeight = size.height;
      cacheReaderSourceImageSize(imageUrl, size.width, size.height);
      this.updateDisplayImageSize();
      this.reportImageSize();
    }
  }

  private localSourceImagePath(): string {
    return readerLocalSourceImagePath(this.page, this.preferOriginal);
  }

  private sourceImageUrl(): string {
    return this.preferOriginal && this.page.originImageUrl.length > 0 ? this.page.originImageUrl : this.page.imageUrl;
  }

  private sourceImageCacheKey(): string {
    return readerPageImageCacheKey(this.page, this.preferOriginal && this.page.originImageUrl.length > 0);
  }

  private imageSourceIdentity(): string {
    return this.imageUrl() + '|' + this.sourceImageCacheKey() + '|' + (this.preferOriginal ? '1' : '0');
  }

  private startDownloadProgressMonitor(): void {
    const requestId = this.downloadProgressRequestId + 1;
    this.downloadProgressRequestId = requestId;
    this.downloadProgress = -1;
    if (this.localSourceImagePath().length > 0) {
      return;
    }
    if (!this.isActive && !this.hdrEnabled && !this.superResolutionEnabled && !this.cropWhiteBorders) {
      return;
    }
    const context = getAbilityContext();
    const sourceUrl = this.sourceImageUrl();
    if (context === undefined || sourceUrl.length === 0) {
      return;
    }
    readerImageCache.ensureCached(context, sourceUrl, this.page.pageUrl, IMAGE_DOWNLOAD_PRIORITY_READER,
      (progress: ImageDownloadProgress) => {
        if (requestId !== this.downloadProgressRequestId) {
          return;
        }
        this.downloadProgress = readerDownloadProgressPercent(progress);
      }, this.sourceImageCacheKey(), { retryLimit: 1 }).then(() => {
      if (requestId === this.downloadProgressRequestId) {
        this.downloadProgress = 100;
        this.loadAdjustedPixelMap();
        this.loadSuperResolutionPixelMap();
        this.loadHdrPixelMap();
        this.loadCropRect();
      }
    }).catch(() => {});
  }

  private imageDisplayWidth(): number | string {
    if (this.displayImageWidth <= 1) {
      return '100%';
    }
    return this.displayImageWidth;
  }

  private imageDisplayHeight(): number | string {
    if (this.displayImageHeight <= 1) {
      return '100%';
    }
    return this.displayImageHeight;
  }

  private loadCropRect(): void {
    const requestId = this.cropRequestId + 1;
    this.cropRequestId = requestId;
    if (!this.cropWhiteBorders) {
      this.cropRect = new ReaderCropRect();
      this.updateDisplayImageSize();
      this.reportImageSize();
      return;
    }
    const sourcePath = this.localSourceImagePath();
    const cacheKey = this.sourceImageCacheKey();
    if (sourcePath.length === 0) {
      return;
    }
    readerWhiteBorderCropService.analyze(cacheKey, sourcePath).then((rect: ReaderCropRect) => {
      if (requestId !== this.cropRequestId || !this.cropWhiteBorders || sourcePath !== this.localSourceImagePath()) {
        return;
      }
      this.cropRect = rect;
      this.updateDisplayImageSize();
      this.reportImageSize();
    }).catch(() => {});
  }

  private visibleSourceWidth(): number {
    return Math.max(1, this.sourceImageWidth * this.cropRect.width);
  }

  private visibleSourceHeight(): number {
    return Math.max(1, this.sourceImageHeight * this.cropRect.height);
  }

  private uncroppedDisplayWidth(): number {
    return Math.max(1, this.displayImageWidth / Math.max(0.01, this.cropRect.width));
  }

  private uncroppedDisplayHeight(): number {
    return Math.max(1, this.displayImageHeight / Math.max(0.01, this.cropRect.height));
  }

  private cropOffsetX(): number {
    return -this.cropRect.x * this.uncroppedDisplayWidth();
  }

  private cropOffsetY(): number {
    return -this.cropRect.y * this.uncroppedDisplayHeight();
  }

  private updateDisplayImageSize(): void {
    const componentWidth = this.imageModel.componentWidth;
    const componentHeight = this.imageModel.componentHeight;
    if (componentWidth <= 0 || componentHeight <= 0) {
      return;
    }
    const sourceWidth = this.hasSourceImageSize() ? this.visibleSourceWidth() : componentWidth;
    const sourceHeight = this.hasSourceImageSize() ? this.visibleSourceHeight() : componentHeight;
    let displayWidth = componentWidth;
    let displayHeight = componentHeight;
    const normalized = normalizePageScalingOption(this.fitMode);
    if (normalized === 'Fit width') {
      displayWidth = componentWidth;
      displayHeight = componentWidth * sourceHeight / sourceWidth;
    } else if (normalized === 'Fit height') {
      displayHeight = componentHeight;
      displayWidth = componentHeight * sourceWidth / sourceHeight;
    } else if (normalized === 'Fit screen') {
      const scale = Math.min(componentWidth / sourceWidth, componentHeight / sourceHeight);
      displayWidth = sourceWidth * scale;
      displayHeight = sourceHeight * scale;
    } else if (normalized === 'Actual size') {
      displayWidth = this.imageSourceWidthVp(sourceWidth);
      displayHeight = this.imageSourceHeightVp(sourceHeight);
    } else {
      displayWidth = sourceWidth;
      displayHeight = sourceHeight;
    }
    this.displayImageWidth = Math.max(1, displayWidth);
    this.displayImageHeight = Math.max(1, displayHeight);
    this.imageModel.setImageSize(this.displayImageWidth, this.displayImageHeight);
  }

  private imageSourceWidthVp(sourceWidth: number): number {
    if (this.sourceImageWidth > 0) {
      return this.getUIContext().px2vp(sourceWidth);
    }
    return sourceWidth;
  }

  private imageSourceHeightVp(sourceHeight: number): number {
    if (this.sourceImageHeight > 0) {
      return this.getUIContext().px2vp(sourceHeight);
    }
    return sourceHeight;
  }

  private startAlignment(): Alignment {
    const normalized = normalizeStartPositionOption(this.startPosition);
    if (normalized === 'Top left') {
      return Alignment.TopStart;
    }
    if (normalized === 'Top right') {
      return Alignment.TopEnd;
    }
    if (normalized === 'Bottom left') {
      return Alignment.BottomStart;
    }
    if (normalized === 'Bottom right') {
      return Alignment.BottomEnd;
    }
    return Alignment.Center;
  }

  private readAreaSize(value: Length): number {
    const parsed = Number.parseFloat(value.toString());
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  private updateComponentSize(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    this.imageModel.setComponentSize(width, height);
    this.updateDisplayImageSize();
    this.reportState();
  }

  private tapCenterX(event: GestureEvent): number {
    if (event.fingerList.length > 0) {
      return event.fingerList[0].localX;
    }
    return this.imageModel.componentWidth / 2;
  }

  private tapCenterY(event: GestureEvent): number {
    if (event.fingerList.length > 0) {
      return event.fingerList[0].localY;
    }
    return this.imageModel.componentHeight / 2;
  }

  private reportState(): void {
    if (!this.interactive || !this.isActive) {
      return;
    }
    this.onSwipeLockChange(this.imageModel.disableSwipe);
    this.onZoomChange(this.imageModel.zoomPercent());
  }

  private reportImageSize(): void {
    if (this.sourceImageWidth <= 0 || this.sourceImageHeight <= 0) {
      return;
    }
    this.onImageSizeChange(this.visibleSourceWidth(), this.visibleSourceHeight());
  }

  private shouldLetSwiperHandlePan(event: BaseGestureEvent): boolean {
    const panEvent = event as PanGestureEvent;
    return this.imageModel.shouldLetSwiperHandlePan(
      panEvent.offsetX,
      panEvent.velocityX,
      panEvent.offsetY,
      panEvent.velocityY
    );
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.imageUrl().length > 0) {
        Stack({ alignContent: this.startAlignment() }) {
          Stack({ alignContent: Alignment.TopStart }) {
            Image(this.displayImageSource())
              .id(this.imageNodeId())
              .width(this.uncroppedDisplayWidth())
              .height(this.uncroppedDisplayHeight())
              .objectFit(this.imageObjectFit())
              .colorFilter(readerImageColorFilter(this.imageAdjustmentSettings))
            .interpolation(this.isActive ? ImageInterpolation.High : ImageInterpolation.Low)
              .dynamicRangeMode(this.hdrPixelMap === undefined ? DynamicRangeMode.STANDARD : DynamicRangeMode.HIGH)
              .hdrBrightness(this.hdrPixelMap === undefined ? 0 : 1)
              .syncLoad(this.shouldSyncLoadImage())
              .draggable(false)
              .backgroundColor(readerBackgroundColor())
              .opacity(this.failedImageUrl === this.imageUrl() ? 0 : 1)
              .position({ x: this.cropOffsetX(), y: this.cropOffsetY() })
              .onComplete((event?: ReaderImageCompleteEvent) => {
                if (event !== undefined && event.width > 0 && event.height > 0 && this.sourceImageWidth <= 0) {
                  this.sourceImageWidth = event.width;
                  this.sourceImageHeight = event.height;
                  cacheReaderSourceImageSize(this.imageUrl(), event.width, event.height);
                  this.updateDisplayImageSize();
                  this.reportImageSize();
                }
                cacheReaderImageComplete(this.imageUrl());
                this.completedImageUrl = this.imageUrl();
                this.failedImageUrl = '';
                this.loadAdjustedPixelMap();
                this.loadSuperResolutionPixelMap();
                this.loadCropRect();
              })
              .onError(() => {
                this.failedImageUrl = this.imageUrl();
              })
            if (this.translation !== null && this.displayImageWidth > 1 && this.displayImageHeight > 1) {
              ReaderTranslationOverlay({
                translation: this.translation,
                displayWidth: this.uncroppedDisplayWidth(),
                displayHeight: this.uncroppedDisplayHeight()
              })
                .position({ x: this.cropOffsetX(), y: this.cropOffsetY() })
            }
          }
          .width(this.imageDisplayWidth())
          .height(this.imageDisplayHeight())
          .clip(true)
          .scale({ x: this.imageModel.currentScale, y: this.imageModel.currentScale, centerX: '50%', centerY: '50%' })
          .translate({ x: this.imageModel.currentOffsetX, y: this.imageModel.currentOffsetY })
          if (this.hdrPixelMap !== undefined) {
            Text(this.hdrFromSuperResolution ? 'SR+HDR' : 'HDR')
              .fontSize('9vp')
              .fontColor('#FFD700')
              .fontWeight(FontWeight.Bold)
              .backgroundColor('#80000000')
              .borderRadius(4)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .position({ x: 8, y: this.displayImageHeight - 24 })
              .hitTestBehavior(HitTestMode.None)
          } else if (this.superResolutionPixelMap !== undefined) {
            Text('SR')
              .fontSize('9vp')
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
              .backgroundColor('#80000000')
              .borderRadius(4)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .position({ x: 8, y: this.displayImageHeight - 24 })
              .hitTestBehavior(HitTestMode.None)
          }
        }
        .width('100%')
        .height('100%')
        if (this.isImageLoading()) {
          ReaderStatusView({ failed: false, compact: false, progress: this.downloadProgress })
            .zIndex(2)
        } else if (this.isFailed()) {
          ReaderStatusView({
            failed: true,
            compact: false,
            onRetry: () => {
              this.retryImage();
            }
          })
            .zIndex(2)
        }
      } else {
        ReaderStatusView({
          failed: this.isFailed(),
          compact: false,
          progress: this.downloadProgress,
          onRetry: () => {
            this.retryImage();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(readerBackgroundColor())
    .clip(true)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.updateComponentSize(this.readAreaSize(newValue.width), this.readAreaSize(newValue.height));
    })
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        TapGesture({ count: 2 })
          .onAction((event: GestureEvent) => {
            this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
              this.imageModel.toggleDoubleTap(this.tapCenterX(event), this.tapCenterY(event));
            });
            this.reportState();
          }),
        TapGesture({ count: 1 })
          .onAction((event: GestureEvent) => {
            if (this.isFailed()) {
              this.retryImage();
              return;
            }
            this.onTap(
              this.tapCenterX(event),
              this.tapCenterY(event),
              this.imageModel.componentWidth,
              this.imageModel.componentHeight
            );
          }),
        GestureGroup(GestureMode.Parallel,
          LongPressGesture({ repeat: false })
            .onAction(() => {
              if (this.isImageReady()) {
                this.onImageLongPress();
              }
            }),
          PanGesture({ fingers: 1, distance: 3 })
            .onActionStart(() => {
              this.imageModel.panStart();
              this.reportState();
            })
            .onActionUpdate((event: GestureEvent) => {
              this.imageModel.panUpdate(event.offsetX, event.offsetY);
              this.reportState();
            })
            .onActionEnd((event: GestureEvent) => {
              const edgeDirection = this.imageModel.edgeSwipeDirection(
                event.offsetX,
                event.velocityX,
                event.offsetY,
                event.velocityY
              );
              this.getUIContext().animateTo({ duration: READER_INERTIA_DURATION, curve: Curve.EaseOut }, () => {
                this.imageModel.panEnd(event.velocityX, event.velocityY);
              });
              this.reportState();
              if (this.allowEdgeSwipe && edgeDirection !== 0) {
                this.onEdgeSwipe(edgeDirection);
              }
            })
            .onActionCancel(() => {
              this.getUIContext().animateTo({ duration: READER_INERTIA_DURATION, curve: Curve.EaseOut }, () => {
                this.imageModel.panEnd();
              });
              this.reportState();
            }),
          PinchGesture({ fingers: 2, distance: 1 })
            .onActionStart((event: GestureEvent) => {
              this.imageModel.pinchStart(event.pinchCenterX, event.pinchCenterY);
              this.reportState();
            })
            .onActionUpdate((event: GestureEvent) => {
              this.imageModel.pinchUpdate(event.scale);
              this.reportState();
            })
            .onActionEnd(() => {
              this.imageModel.pinchEnd();
              this.reportState();
            })
            .onActionCancel(() => {
              this.imageModel.pinchEnd();
              this.reportState();
            })
        )
      )
    )
    .onGestureJudgeBegin((gestureInfo: GestureInfo, event: BaseGestureEvent) => {
      if (!this.interactive) {
        return GestureJudgeResult.REJECT;
      }
      if (gestureInfo.type === GestureControl.GestureType.DRAG) {
        return GestureJudgeResult.REJECT;
      }
      if (gestureInfo.type === GestureControl.GestureType.PAN_GESTURE && this.shouldLetSwiperHandlePan(event)) {
        return GestureJudgeResult.REJECT;
      }
      return GestureJudgeResult.CONTINUE;
    })
    .draggable(false)
  }
}

function readerDownloadProgressPercent(progress: ImageDownloadProgress): number {
  if (progress.totalBytes <= 0) {
    return -1;
  }
  return Math.max(0, Math.min(100, Math.floor(progress.receivedBytes * 100 / progress.totalBytes)));
}
