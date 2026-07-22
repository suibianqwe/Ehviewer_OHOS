import { GalleryPage } from '../../../model/GalleryModels';
import { ReaderPageTranslation } from '../../../model/ReaderTranslationModels';
import {
  IMAGE_DOWNLOAD_PRIORITY_READER,
  ImageDownloadProgress,
  readerImageCache
} from '../../../services/ReaderImageCache';
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
  private isPinching: boolean = false;
  private pinchStartScale: number = READER_BASE_SCALE;
  private sourceSizeRequestId: number = 0;
  private downloadProgressRequestId: number = 0;
  private retainedImageUrl: string = '';

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
    return 'reader-continuous-image-' + this.imageRetryVersion.toString() + '-' + sourceKey;
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
    this.startDownloadProgressMonitor();
  }

  private releaseRuntimeState(): void {
    this.sourceSizeRequestId++;
    this.downloadProgressRequestId++;
    forgetReaderImageRuntimeState(this.retainedImageUrl);
    this.retainedImageUrl = '';
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

  private startDownloadProgressMonitor(): void {
    const requestId = this.downloadProgressRequestId + 1;
    this.downloadProgressRequestId = requestId;
    this.downloadProgress = -1;
    if (this.localSourceImagePath().length > 0) {
      return;
    }
    if (!this.isActive) {
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
    const sourceWidth = this.sourceImageWidth > 0 ? this.sourceImageWidth : this.componentWidth;
    const sourceHeight = this.sourceImageHeight > 0 ? this.sourceImageHeight : this.componentWidth * 1.35;
    const normalized = normalizePageScalingOption(this.fitMode);
    let width = this.componentWidth;
    if (normalized === 'Actual size') {
      width = this.sourceImageWidth > 0 ? this.getUIContext().px2vp(this.sourceImageWidth) : sourceWidth;
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
    this.onImageSizeChange(this.sourceImageWidth, this.sourceImageHeight);
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
        Image(this.imageUrl())
          .id(this.imageNodeId())
          .width(this.displayWidth())
          .height(this.displayHeight())
          .objectFit(this.imageObjectFit())
          .syncLoad(this.shouldSyncLoadImage())
          .draggable(false)
          .backgroundColor(readerBackgroundColor())
          .opacity(this.failedImageUrl === this.imageUrl() ? 0 : 1)
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
          })
          .onError(() => {
            this.failedImageUrl = this.imageUrl();
          })
          .translate({ x: this.sharedOffsetX, y: 0 })
        if (this.translation !== null && this.displayImageWidth > 1 && this.displayImageHeight > 1) {
          ReaderTranslationOverlay({
            translation: this.translation,
            displayWidth: this.displayWidth(),
            displayHeight: this.displayHeight()
          })
            .translate({ x: this.sharedOffsetX, y: 0 })
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
