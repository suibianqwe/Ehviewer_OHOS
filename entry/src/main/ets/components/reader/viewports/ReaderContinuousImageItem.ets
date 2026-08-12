import { image } from '@kit.ImageKit';
import { GalleryPage } from '../../../model/GalleryModels';
import { ReaderPageTranslation } from '../../../model/ReaderTranslationModels';
import {
  IMAGE_DOWNLOAD_PRIORITY_READER,
  ImageDownloadProgress,
  readerImageCache
} from '../../../services/ReaderImageCache';
import { readerHdrService } from '../../../services/ReaderHdrService';
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
  readerDisplayImageUrl,
  readerPageImageCacheKey
} from '../../../shared/EhShared';
import {
  READER_BASE_SCALE,
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
export struct ReaderContinuousImageItem {
  @Prop @Watch('onImageSourceChange') page: GalleryPage = createEmptyPage();
  @Prop statusText: string = '';
  @Prop @Watch('onImageSourceChange') preferOriginal: boolean = false;
  @Prop @Watch('onFitModeChange') fitMode: string = 'Fixed scale';
  @Prop @Watch('onZoomScaleChange') zoomScale: number = READER_BASE_SCALE;
  @Prop sharedOffsetX: number = 0;
  @Prop @Watch('onActiveChange') isActive: boolean = false;
  @Prop @Watch('onHdrEnabledChange') hdrEnabled: boolean = false;
  @Prop @Watch('onSuperResolutionEnabledChange') superResolutionEnabled: boolean = false;
  @Prop @Watch('onSuperResolutionEnabledChange') superResolutionEngine: string =
    READER_SUPER_RESOLUTION_ENGINE_DETAIL;
  @Prop @Watch('onSuperResolutionTargetChange') superResolutionTargetWidth: number = 0;
  @Prop @Watch('onSuperResolutionTargetChange') superResolutionTargetHeight: number = 0;
  @Prop @Watch('onHdrPriorityChange') hdrPriority: number = 0;
  @Prop @Watch('onCropWhiteBordersChange') cropWhiteBorders: boolean = false;
  @Prop translation: ReaderPageTranslation | null = null;
  onTap: (x: number, y: number, w: number, h: number) => void =
    (_x: number, _y: number, _w: number, _h: number) => {};
  onRetry: () => void = () => {};
  onImageLongPress: () => void = () => {};
  onImageSizeChange: (width: number, height: number) => void = (_width: number, _height: number) => {};
  onZoomChange: (percent: number) => void = (_percent: number) => {};
  onHorizontalBoundsChange: (maxOffsetX: number) => void = (_maxOffsetX: number) => {};
  onHorizontalDragStart: (maxOffsetX: number) => void = (_maxOffsetX: number) => {};
  onHorizontalDragUpdate: (offsetX: number, maxOffsetX: number) => void = (_offsetX: number, _maxOffsetX: number) => {};
  onHorizontalDragEnd: (velocityX: number, maxOffsetX: number) => void = (_velocityX: number, _maxOffsetX: number) => {};

  @State imageModel: ReaderPreviewModel = new ReaderPreviewModel();
  @State completedImageUrl: string = '';
  @State failedImageUrl: string = '';
  @State sourceImageWidth: number = 0;
  @State sourceImageHeight: number = 0;
  @State componentWidth: number = 1;
  @State displayImageWidth: number = 1;
  @State displayImageHeight: number = 120;
  @State downloadProgress: number = -1;
  @State imageRetryVersion: number = 0;
  @State hdrPixelMap: image.PixelMap | undefined = undefined;
  @State hdrFromSuperResolution: boolean = false;
  @State superResolutionPixelMap: image.PixelMap | undefined = undefined;
  @State cropRect: ReaderCropRect = new ReaderCropRect();
  private isPinching: boolean = false;
  private pinchStartScale: number = READER_BASE_SCALE;
  private sourceSizeRequestId: number = 0;
  private downloadProgressRequestId: number = 0;
  private retainedImageUrl: string = '';
  private retainedSourceIdentity: string = '';
  private retainedHdrKey: string = '';
  private hdrRequestId: number = 0;
  private retainedSuperResolutionKey: string = '';
  private superResolutionRequestId: number = 0;
  private superResolutionCompleted: boolean = false;
  private cropRequestId: number = 0;

  aboutToAppear(): void {
    this.onImageSourceChange();
    this.onFitModeChange();
  }

  aboutToDisappear(): void {
    this.releaseRuntimeState();
  }

  onActiveChange(): void {
    if (this.isActive) {
      this.startDownloadProgressMonitor();
    }
  }

  private imageUrl(): string {
    return readerDisplayImageUrl(this.page, this.preferOriginal);
  }

  private imageNodeId(): string {
    const sourceKey = this.sourceImageCacheKey().length > 0 ? this.sourceImageCacheKey() : this.imageUrl();
    const processingMode = this.hdrPixelMap !== undefined ? 'hdr-' :
      (this.superResolutionPixelMap !== undefined ? 'sr-' : 'sdr-');
    return 'reader-continuous-image-' + this.imageRetryVersion.toString() + '-' +
      processingMode + sourceKey;
  }

  private displayPixelMap(): image.PixelMap | undefined {
    return this.hdrPixelMap !== undefined ? this.hdrPixelMap : this.superResolutionPixelMap;
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

  private onImageSourceChange(): void {
    const url = this.imageUrl();
    const sourceIdentity = this.imageSourceIdentity();
    if (sourceIdentity === this.retainedSourceIdentity) {
      return;
    }
    this.retainedSourceIdentity = sourceIdentity;
    this.releaseHdrPixelMap();
    this.releaseSuperResolutionPixelMap();
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
    this.updateDisplayImageSize();
    this.loadCachedSourceImageSize(requestId, url).catch(() => {});
    this.loadSuperResolutionPixelMap();
    this.loadHdrPixelMap();
    this.loadCropRect();
    this.startDownloadProgressMonitor();
  }

  private releaseRuntimeState(): void {
    this.sourceSizeRequestId++;
    this.downloadProgressRequestId++;
    forgetReaderImageRuntimeState(this.retainedImageUrl);
    this.retainedImageUrl = '';
    this.retainedSourceIdentity = '';
    this.releaseHdrPixelMap();
    this.releaseSuperResolutionPixelMap();
    this.cropRequestId++;
  }

  onCropWhiteBordersChange(): void {
    this.cropRect = new ReaderCropRect();
    this.updateDisplayImageSize();
    this.reportImageSize();
    this.loadCropRect();
    this.startDownloadProgressMonitor();
  }

  onHdrEnabledChange(): void {
    this.startDownloadProgressMonitor();
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
    if (!this.superResolutionEnabled) {
      return;
    }
    this.releaseHdrPixelMap();
    this.releaseSuperResolutionPixelMap();
    this.loadSuperResolutionPixelMap();
    this.loadHdrPixelMap();
  }

  private superResolutionKey(sourcePath: string): string {
    return this.sourceImageCacheKey() + '|' + sourcePath + '|sr|' +
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
      const requestId = this.hdrRequestId + 1;
      this.hdrRequestId = requestId;
      this.retainedHdrKey = key;
      this.acquireHdrFromSuperResolution(requestId, key, sourcePath, this.retainedSuperResolutionKey).catch(() => {});
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

  private async acquireHdrFromSuperResolution(requestId: number, hdrKey: string, sourcePath: string,
    superResolutionKey: string): Promise<void> {
    const enhancedPixelMap = await readerSuperResolutionService.acquire(superResolutionKey, sourcePath,
      this.hdrPriority, this.superResolutionTargetWidth, this.superResolutionTargetHeight,
      this.superResolutionEngine);
    try {
      if (enhancedPixelMap === undefined || requestId !== this.hdrRequestId || hdrKey !== this.retainedHdrKey ||
        !this.hdrEnabled || !this.superResolutionEnabled) {
        return;
      }
      const pixelMap = await readerHdrService.acquirePixelMap(hdrKey, enhancedPixelMap, this.hdrPriority);
      if (requestId !== this.hdrRequestId || hdrKey !== this.retainedHdrKey ||
        !this.hdrEnabled || !this.superResolutionEnabled) {
        return;
      }
      this.hdrFromSuperResolution = pixelMap !== undefined;
      this.hdrPixelMap = pixelMap;
    } finally {
      readerSuperResolutionService.release(superResolutionKey);
    }
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
    const key = this.superResolutionKey(sourcePath);
    if (!this.superResolutionEnabled || sourcePath.length === 0 || this.imageUrl().length === 0) {
      this.releaseSuperResolutionPixelMap();
      return;
    }
    if (this.retainedSuperResolutionKey === key) {
      return;
    }
    this.releaseSuperResolutionPixelMap();
    this.superResolutionCompleted = false;
    const requestId = this.superResolutionRequestId + 1;
    this.superResolutionRequestId = requestId;
    this.retainedSuperResolutionKey = key;
    readerSuperResolutionService.acquire(key, sourcePath, this.hdrPriority,
      this.superResolutionTargetWidth, this.superResolutionTargetHeight, this.superResolutionEngine)
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
        this.loadSuperResolutionPixelMap();
        this.loadHdrPixelMap();
        this.loadCropRect();
      }
    }).catch(() => {});
  }

  private onFitModeChange(): void {
    this.updateDisplayImageSize();
    this.syncFixedScale();
    this.reportState();
  }

  private syncFixedScale(): void {
    if (normalizePageScalingOption(this.fitMode) === 'Fixed scale') {
      this.imageModel.setScale(this.zoomScale);
    } else {
      this.imageModel.reset();
    }
  }

  onZoomScaleChange(): void {
    if (!this.isPinching && normalizePageScalingOption(this.fitMode) === 'Fixed scale') {
      this.imageModel.setScale(this.zoomScale);
    }
  }

  private displayWidth(): number {
    return Math.max(1, this.displayImageWidth * this.imageModel.currentScale);
  }

  private displayHeight(): number {
    return Math.max(120, this.displayImageHeight * this.imageModel.currentScale);
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
    return Math.max(1, this.displayWidth() / Math.max(0.01, this.cropRect.width));
  }

  private uncroppedDisplayHeight(): number {
    return Math.max(1, this.displayHeight() / Math.max(0.01, this.cropRect.height));
  }

  private cropOffsetX(): number {
    return -this.cropRect.x * this.uncroppedDisplayWidth();
  }

  private cropOffsetY(): number {
    return -this.cropRect.y * this.uncroppedDisplayHeight();
  }

  private imageObjectFit(): ImageFit {
    if (this.sourceImageWidth <= 0 || this.sourceImageHeight <= 0 || this.componentWidth <= 1) {
      return ImageFit.Contain;
    }
    return ImageFit.Fill;
  }

  private itemHeight(): number {
    return this.displayHeight();
  }

  private updateDisplayImageSize(): void {
    if (this.componentWidth <= 0) {
      return;
    }
    const sourceWidth = this.sourceImageWidth > 0 ? this.visibleSourceWidth() : this.componentWidth;
    const sourceHeight = this.sourceImageHeight > 0 ? this.visibleSourceHeight() : this.componentWidth * 1.35;
    const normalized = normalizePageScalingOption(this.fitMode);
    let width = this.componentWidth;
    if (normalized === 'Actual size') {
      width = this.sourceImageWidth > 0 ? this.getUIContext().px2vp(sourceWidth) : sourceWidth;
    } else if (normalized === 'Fixed scale') {
      width = this.componentWidth;
    }
    this.displayImageWidth = Math.max(1, width);
    this.displayImageHeight = Math.max(120, this.displayImageWidth * sourceHeight / sourceWidth);
    this.imageModel.setComponentSize(this.componentWidth, this.displayImageHeight);
    this.imageModel.setImageSize(this.displayImageWidth, this.displayImageHeight);
    this.reportHorizontalBounds();
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

  private shouldSyncLoadImage(): boolean {
    const url = this.imageUrl();
    return this.localSourceImagePath().length > 0 || isReaderImageComplete(url);
  }

  private reportImageSize(): void {
    if (!this.isActive || this.sourceImageWidth <= 0 || this.sourceImageHeight <= 0) {
      return;
    }
    this.onImageSizeChange(this.visibleSourceWidth(), this.visibleSourceHeight());
  }

  private reportState(): void {
    this.onZoomChange(this.imageModel.zoomPercent());
    this.reportHorizontalBounds();
  }

  private shouldHandleImagePan(event: BaseGestureEvent): boolean {
    const panEvent = event as PanGestureEvent;
    return this.imageModel.shouldHandleContinuousImagePan(
      panEvent.offsetX,
      panEvent.velocityX
    );
  }

  private horizontalMaxOffsetX(): number {
    return Math.max(0, (this.displayWidth() - this.componentWidth) / 2);
  }

  private reportHorizontalBounds(): void {
    if (this.isActive) {
      this.onHorizontalBoundsChange(this.horizontalMaxOffsetX());
    }
  }

  private tapCenterX(event: GestureEvent): number {
    if (event.fingerList.length > 0) {
      return event.fingerList[0].localX;
    }
    return this.componentWidth / 2;
  }

  private tapCenterY(event: GestureEvent): number {
    if (event.fingerList.length > 0) {
      return event.fingerList[0].localY;
    }
    return this.itemHeight() / 2;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.imageUrl().length > 0) {
        Stack({ alignContent: Alignment.TopStart }) {
          Image(this.displayImageSource())
            .id(this.imageNodeId())
            .width(this.uncroppedDisplayWidth())
            .height(this.uncroppedDisplayHeight())
            .objectFit(this.imageObjectFit())
            .interpolation(this.displayPixelMap() !== undefined && this.isActive ?
              ImageInterpolation.High : ImageInterpolation.Low)
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
        .width(this.displayWidth())
        .height(this.displayHeight())
        .clip(true)
        .translate({ x: this.sharedOffsetX, y: 0 })
        if (this.hdrPixelMap !== undefined) {
          Text(this.hdrFromSuperResolution ? 'SR+HDR' : 'HDR')
            .fontSize('9vp')
            .fontColor('#FFD700')
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#80000000')
            .borderRadius(4)
            .padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .position({ x: 8, y: this.itemHeight() - 24 })
            .hitTestBehavior(HitTestMode.None)
        } else if (this.superResolutionPixelMap !== undefined) {
          Text('SR')
            .fontSize('9vp')
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#80000000')
            .borderRadius(4)
            .padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .position({ x: 8, y: this.itemHeight() - 24 })
            .hitTestBehavior(HitTestMode.None)
        }
      }
      if (this.imageUrl().length === 0 || this.isImageLoading()) {
        ReaderStatusView({ failed: false, compact: true, progress: this.downloadProgress })
      } else if (this.isFailed()) {
        ReaderStatusView({
          failed: true,
          compact: true,
          onRetry: () => {
            this.retryImage();
          }
        })
      }
    }
    .width('100%')
    .height(this.itemHeight())
    .backgroundColor(readerBackgroundColor())
    .clip(true)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Number.parseFloat(newValue.width.toString());
      if (width > 0 && !Number.isNaN(width)) {
        this.componentWidth = width;
        this.updateDisplayImageSize();
      }
    })
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        TapGesture({ count: 1 })
          .onAction((event: GestureEvent) => {
            if (this.isFailed()) {
              this.retryImage();
              return;
            }
            this.onTap(this.tapCenterX(event), this.tapCenterY(event), this.componentWidth, this.itemHeight());
          }),
        GestureGroup(GestureMode.Parallel,
          LongPressGesture({ repeat: false })
            .onAction(() => {
              if (!this.isFailed()) {
                this.onImageLongPress();
              }
            }),
          PinchGesture({ fingers: 2, distance: 1 })
            .onActionStart((event: GestureEvent) => {
              this.isPinching = true;
              this.pinchStartScale = this.imageModel.currentScale;
              this.imageModel.pinchStart(event.pinchCenterX, event.pinchCenterY);
            })
            .onActionUpdate((event: GestureEvent) => {
              if (event.scale <= 0 || Number.isNaN(event.scale)) {
                return;
              }
              this.imageModel.setScale(this.pinchStartScale * event.scale);
              this.reportState();
            })
            .onActionEnd(() => {
              this.imageModel.pinchEnd();
              this.isPinching = false;
              this.reportState();
            })
            .onActionCancel(() => {
              this.imageModel.pinchEnd();
              this.isPinching = false;
              this.reportState();
            }),
          PanGesture({ fingers: 1, distance: 3 })
            .onActionStart(() => {
              this.imageModel.panStart();
              this.onHorizontalDragStart(this.horizontalMaxOffsetX());
              this.reportState();
            })
            .onActionUpdate((event: GestureEvent) => {
              this.onHorizontalDragUpdate(event.offsetX, this.horizontalMaxOffsetX());
              this.reportState();
            })
            .onActionEnd((event: GestureEvent) => {
              this.onHorizontalDragEnd(event.velocityX, this.horizontalMaxOffsetX());
              this.reportState();
            })
            .onActionCancel(() => {
              this.onHorizontalDragEnd(0, this.horizontalMaxOffsetX());
              this.reportState();
            })
        )
      )
    )
    .onGestureJudgeBegin((gestureInfo: GestureInfo, event: BaseGestureEvent) => {
      if (gestureInfo.type === GestureControl.GestureType.PAN_GESTURE && !this.shouldHandleImagePan(event)) {
        return GestureJudgeResult.REJECT;
      }
      return GestureJudgeResult.CONTINUE;
    })
  }
}

function readerDownloadProgressPercent(progress: ImageDownloadProgress): number {
  if (progress.totalBytes <= 0) {
    return -1;
  }
  return Math.max(0, Math.min(100, Math.floor(progress.receivedBytes * 100 / progress.totalBytes)));
}
