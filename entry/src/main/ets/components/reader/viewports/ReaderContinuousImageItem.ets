import { GalleryPage } from '../../../model/GalleryModels';
import { createEmptyPage, normalizePageScalingOption, readerDisplayImageUrl } from '../../../shared/EhShared';
import {
  READER_BASE_SCALE,
  ReaderImageCompleteEvent,
  ReaderPreviewModel,
  readReaderSourceImageSize,
  readerBackgroundColor,
  readerLocalSourceImagePath
} from '../core/ReaderCore';
import { ReaderStatusView } from '../status/ReaderStatusView';

@Component
export struct ReaderContinuousImageItem {
  @Prop @Watch('onImageSourceChange') page: GalleryPage = createEmptyPage();
  @Prop statusText: string = '';
  @Prop @Watch('onImageSourceChange') preferOriginal: boolean = false;
  @Prop @Watch('onFitModeChange') fitMode: string = 'Fixed scale';
  @Prop @Watch('onZoomScaleChange') zoomScale: number = READER_BASE_SCALE;
  @Prop isActive: boolean = false;
  onTap: () => void = () => {};
  onRetry: () => void = () => {};
  onImageLongPress: () => void = () => {};
  onImageSizeChange: (width: number, height: number) => void = (_width: number, _height: number) => {};
  onZoomChange: (percent: number) => void = (_percent: number) => {};

  @State imageModel: ReaderPreviewModel = new ReaderPreviewModel();
  @State completedImageUrl: string = '';
  @State failedImageUrl: string = '';
  @State sourceImageWidth: number = 0;
  @State sourceImageHeight: number = 0;
  @State componentWidth: number = 1;
  @State displayImageWidth: number = 1;
  @State displayImageHeight: number = 120;
  private isPinching: boolean = false;
  private pinchStartScale: number = READER_BASE_SCALE;
  private sourceSizeRequestId: number = 0;

  aboutToAppear(): void {
    this.onImageSourceChange();
    this.onFitModeChange();
  }

  private imageUrl(): string {
    return readerDisplayImageUrl(this.page, this.preferOriginal);
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
    this.sourceImageWidth = 0;
    this.sourceImageHeight = 0;
    this.loadCachedSourceImageSize(requestId, url).catch(() => {});
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
      this.updateDisplayImageSize();
      this.reportImageSize();
    }
  }

  private localSourceImagePath(): string {
    return readerLocalSourceImagePath(this.page, this.preferOriginal);
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

  private onZoomScaleChange(): void {
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

  private reportImageSize(): void {
    if (!this.isActive || this.sourceImageWidth <= 0 || this.sourceImageHeight <= 0) {
      return;
    }
    this.onImageSizeChange(this.sourceImageWidth, this.sourceImageHeight);
  }

  private reportState(): void {
    this.onZoomChange(this.imageModel.zoomPercent());
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
    return this.displayHeight() / 2;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.imageUrl().length > 0) {
        Image(this.imageUrl())
          .width(this.displayWidth())
          .height(this.displayHeight())
          .objectFit(ImageFit.Fill)
          .draggable(false)
          .backgroundColor(readerBackgroundColor())
          .opacity(this.failedImageUrl === this.imageUrl() ? 0 : 1)
          .onComplete((event?: ReaderImageCompleteEvent) => {
            if (event !== undefined && event.width > 0 && event.height > 0 && this.sourceImageWidth <= 0) {
              this.sourceImageWidth = event.width;
              this.sourceImageHeight = event.height;
              this.reportImageSize();
            }
            this.completedImageUrl = this.imageUrl();
            this.failedImageUrl = '';
          })
          .onError(() => {
            this.failedImageUrl = this.imageUrl();
          })
          .translate({ x: this.imageModel.currentOffsetX, y: this.imageModel.currentOffsetY })
      }
      if (this.imageUrl().length === 0 || this.isImageLoading()) {
        ReaderStatusView({ failed: false, compact: true })
      } else if (this.isFailed()) {
        ReaderStatusView({
          failed: true,
          compact: true,
          onRetry: () => {
            this.failedImageUrl = '';
            this.completedImageUrl = '';
            this.onRetry();
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
          .onAction(() => {
            if (this.isFailed()) {
              this.failedImageUrl = '';
              this.completedImageUrl = '';
              this.onRetry();
              return;
            }
            this.onTap();
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
              this.reportState();
            })
            .onActionUpdate((event: GestureEvent) => {
              this.imageModel.panUpdate(event.offsetX, event.offsetY);
              this.reportState();
            })
            .onActionEnd((event: GestureEvent) => {
              this.imageModel.panEnd(event.velocityX, event.velocityY);
              this.reportState();
            })
            .onActionCancel(() => {
              this.imageModel.panEnd();
              this.reportState();
            })
        )
      )
    )
    .onGestureJudgeBegin((gestureInfo: GestureInfo, _event: BaseGestureEvent) => {
      if (gestureInfo.type === GestureControl.GestureType.PAN_GESTURE && !this.imageModel.canHandleLocalPan()) {
        return GestureJudgeResult.REJECT;
      }
      return GestureJudgeResult.CONTINUE;
    })
  }
}
