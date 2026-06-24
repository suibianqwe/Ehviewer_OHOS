import { GalleryPage } from '../../../model/GalleryModels';
import {
  createEmptyPage,
  normalizePageScalingOption,
  normalizeStartPositionOption,
  readerDisplayImageUrl
} from '../../../shared/EhShared';
import {
  READER_BASE_SCALE,
  READER_DOUBLE_TAP_SCALE,
  READER_INERTIA_DURATION,
  ReaderImageCompleteEvent,
  ReaderPreviewModel,
  cachedReaderSourceImageSize,
  cacheReaderSourceImageSize,
  readReaderSourceImageSize,
  readerBackgroundColor,
  readerLocalSourceImagePath
} from '../core/ReaderCore';
import { ReaderStatusView } from '../status/ReaderStatusView';

@Component
export struct ReaderImageViewport {
  @Prop @Watch('onImageSourceChange') page: GalleryPage = createEmptyPage();
  @Prop statusText: string = '';
  @Prop @Watch('onImageSourceChange') preferOriginal: boolean = false;
  @Prop @Watch('onFitModeChange') fitMode: string = 'Fit screen';
  @Prop @Watch('onFixedScaleChange') fixedScale: number = READER_BASE_SCALE;
  @Prop startPosition: string = 'Top right';
  @Prop @Watch('onActiveChange') isActive: boolean = false;
  @Prop allowEdgeSwipe: boolean = true;
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
  private lastCommandVersion: number = -1;
  private sourceSizeRequestId: number = 0;

  aboutToAppear(): void {
    this.onImageSourceChange();
    this.onFitModeChange();
    this.reportState();
  }

  aboutToDisappear(): void {
    if (this.isActive) {
      this.onSwipeLockChange(false);
    }
  }

  onCommandChange(): void {
    if (!this.isActive || this.commandVersion === this.lastCommandVersion) {
      return;
    }
    this.lastCommandVersion = this.commandVersion;
    if (this.command === 'zoom_in') {
      this.imageModel.zoomBy(1.25);
    } else if (this.command === 'zoom_out') {
      this.imageModel.zoomBy(0.8);
    } else if (this.command === 'double_zoom') {
      this.imageModel.setScale(READER_DOUBLE_TAP_SCALE);
    } else if (this.command === 'reset') {
      this.imageModel.reset();
    } else if (this.command === 'fixed_scale') {
      this.syncFixedScale();
    }
    this.reportState();
  }

  onActiveChange(): void {
    if (this.isActive) {
      this.syncFixedScale();
      this.reportImageSize();
    }
  }

  private imageUrl(): string {
    return readerDisplayImageUrl(this.page, this.preferOriginal);
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

  private onImageSourceChange(): void {
    const url = this.imageUrl();
    const requestId = this.sourceSizeRequestId + 1;
    this.sourceSizeRequestId = requestId;
    if (this.completedImageUrl !== url) {
      this.completedImageUrl = '';
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
    this.syncFixedScale();
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
    if (!this.hasSourceImageSize()) {
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

  private updateDisplayImageSize(): void {
    const componentWidth = this.imageModel.componentWidth;
    const componentHeight = this.imageModel.componentHeight;
    if (componentWidth <= 0 || componentHeight <= 0) {
      return;
    }
    const sourceWidth = this.hasSourceImageSize() ? this.sourceImageWidth : componentWidth;
    const sourceHeight = this.hasSourceImageSize() ? this.sourceImageHeight : componentHeight;
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
      return this.getUIContext().px2vp(this.sourceImageWidth);
    }
    return sourceWidth;
  }

  private imageSourceHeightVp(sourceHeight: number): number {
    if (this.sourceImageHeight > 0) {
      return this.getUIContext().px2vp(this.sourceImageHeight);
    }
    return sourceHeight;
  }

  private startAlignment(): Alignment {
    const normalized = normalizeStartPositionOption(this.startPosition);
    const imageFitsVertically = this.displayImageHeight * this.imageModel.currentScale <= this.imageModel.componentHeight + 0.5;
    if (imageFitsVertically) {
      if (normalized === 'Top left' || normalized === 'Bottom left') {
        return Alignment.Start;
      }
      if (normalized === 'Top right' || normalized === 'Bottom right') {
        return Alignment.End;
      }
      return Alignment.Center;
    }
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
    if (!this.isActive) {
      return;
    }
    this.onSwipeLockChange(this.imageModel.disableSwipe);
    this.onZoomChange(this.imageModel.zoomPercent());
  }

  private reportImageSize(): void {
    if (!this.isActive || this.sourceImageWidth <= 0 || this.sourceImageHeight <= 0) {
      return;
    }
    this.onImageSizeChange(this.sourceImageWidth, this.sourceImageHeight);
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
    Stack({ alignContent: this.startAlignment() }) {
      if (this.imageUrl().length > 0) {
        Image(this.imageUrl())
          .width(this.imageDisplayWidth())
          .height(this.imageDisplayHeight())
          .objectFit(this.imageObjectFit())
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
            this.completedImageUrl = this.imageUrl();
            this.failedImageUrl = '';
          })
          .onError(() => {
            this.failedImageUrl = this.imageUrl();
          })
          .scale({ x: this.imageModel.currentScale, y: this.imageModel.currentScale, centerX: '50%', centerY: '50%' })
          .translate({ x: this.imageModel.currentOffsetX, y: this.imageModel.currentOffsetY })
        if (this.isImageLoading()) {
          ReaderStatusView({ failed: false, compact: false })
            .zIndex(2)
        } else if (this.isFailed()) {
          ReaderStatusView({
            failed: true,
            compact: false,
            onRetry: () => {
              this.failedImageUrl = '';
              this.completedImageUrl = '';
              this.onRetry();
            }
          })
            .zIndex(2)
        }
      } else {
        ReaderStatusView({
          failed: this.isFailed(),
          compact: false,
          onRetry: () => {
            this.onRetry();
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
            this.imageModel.toggleDoubleTap(this.tapCenterX(event), this.tapCenterY(event));
            this.reportState();
          }),
        TapGesture({ count: 1 })
          .onAction((event: GestureEvent) => {
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
