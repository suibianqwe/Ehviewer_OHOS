import { GalleryPage } from '../../../model/GalleryModels';
import { ReaderPageTranslation } from '../../../model/ReaderTranslationModels';
import { ReaderImageAdjustmentSettings } from '../../../services/ReaderImageAdjustmentSupport';
import { READER_SUPER_RESOLUTION_ENGINE_DETAIL } from '../../../services/ReaderSuperResolutionSupport';
import { ReaderSpreadMotion, readerSpreadGeometry, ReaderSpreadGeometry } from '../../../services/ReaderSpreadTransition';
import { createEmptyPage, normalizeStartPositionOption } from '../../../shared/EhShared';
import { ReaderPreviewModel } from '../core/ReaderCore';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ReaderImageViewport } from './ReaderImageViewport';

@Component
export struct ReaderSpreadViewport {
  @Prop firstPage: GalleryPage = createEmptyPage();
  @Prop secondPage: GalleryPage = createEmptyPage();
  @Prop @Watch('onLayoutChange') paired: boolean = false;
  @Prop @Watch('onLayoutChange') isActive: boolean = false;
  @Prop @Watch('onLayoutChange') reversed: boolean = false;
  @Prop @Watch('onLayoutChange') viewportWidth: number = 1;
  @Prop @Watch('onLayoutChange') viewportHeight: number = 1;
  @Prop @Watch('onLayoutChange') firstWidth: number = 1;
  @Prop @Watch('onLayoutChange') firstHeight: number = 1;
  @Prop @Watch('onLayoutChange') secondWidth: number = 1;
  @Prop @Watch('onLayoutChange') secondHeight: number = 1;
  @ObjectLink model: ReaderPreviewModel;
  @Prop statusText: string = '';
  @Prop preferOriginal: boolean = false;
  @Prop fitMode: string = 'Fit screen';
  @Prop fixedScale: number = 1;
  @Prop @Watch('onLayoutChange') startPosition: string = 'Center';
  @Prop hdrEnabled: boolean = false;
  @Prop imageAdjustmentSettings: ReaderImageAdjustmentSettings = new ReaderImageAdjustmentSettings();
  @Prop superResolutionEnabled: boolean = false;
  @Prop superResolutionEngine: string = READER_SUPER_RESOLUTION_ENGINE_DETAIL;
  @Prop firstTargetWidth: number = 0;
  @Prop firstTargetHeight: number = 0;
  @Prop secondTargetWidth: number = 0;
  @Prop secondTargetHeight: number = 0;
  @Prop cropWhiteBorders: boolean = false;
  @Prop hdrPriority: number = 0;
  @Prop firstTranslation: ReaderPageTranslation | null = null;
  @Prop secondTranslation: ReaderPageTranslation | null = null;
  @Prop allowEdgeSwipe: boolean = true;
  @Prop readerBackgroundColorValue: string = '#050608';
  @Prop command: string = '';
  @Prop commandVersion: number = 0;
  onTap: (x: number, y: number, w: number, h: number) => void = () => {};
  onRetry: (offset: number) => void = () => {};
  onImageLongPress: (offset: number) => void = () => {};
  onSwipeLockChange: (locked: boolean) => void = () => {};
  onZoomChange: (percent: number) => void = () => {};
  onZoomCommit: (percent: number) => void = () => {};
  onImageSizeChange: (offset: number, width: number, height: number) => void = () => {};
  onEdgeSwipe: (direction: number) => void = () => {};
  onPresentationChange: (ready: boolean, animating: boolean) => void = () => {};
  @State motion: ReaderSpreadMotion = new ReaderSpreadMotion();
  @State preparedSecond: boolean = false;
  @State pairedReady: boolean = false;
  private mounted: boolean = false;
  private firstReady: boolean = false;
  private secondReady: boolean = false;
  private wasPaired: boolean = false;
  private layoutSignature: string = '';
  private revision: number = 0;
  private startTimer: number = -1;

  aboutToAppear(): void {
    this.mounted = true;
    this.onLayoutChange();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.cancelMotion();
    this.onPresentationChange(false, false);
  }

  private geometry(): ReaderSpreadGeometry {
    return readerSpreadGeometry(this.viewportWidth, this.viewportHeight, this.firstWidth, this.firstHeight,
      this.secondWidth, this.secondHeight, this.reversed, normalizeStartPositionOption(this.startPosition));
  }

  private cancelMotion(): void {
    this.revision++;
    if (this.startTimer >= 0) {
      clearTimeout(this.startTimer);
      this.startTimer = -1;
    }
  }

  private onLayoutChange(): void {
    if (!this.mounted) return;
    const signature = [this.paired, this.isActive, this.reversed, this.viewportWidth, this.viewportHeight,
      this.firstWidth, this.firstHeight, this.secondWidth, this.secondHeight, this.startPosition].join('|');
    if (signature === this.layoutSignature) return;
    this.layoutSignature = signature;
    const arriving = this.paired && !this.wasPaired && this.isActive && this.firstReady;
    this.wasPaired = this.paired;
    this.cancelMotion();
    if (arriving || (this.paired && this.isActive && this.motion.phase === 'waiting')) {
      this.motion.prepare(this.geometry());
      this.preparedSecond = true;
      this.pairedReady = false;
      this.onPresentationChange(false, false);
      this.startArrivalWhenReady();
    } else if (this.paired) {
      this.motion.settle(this.geometry());
      this.motion.finish();
      this.preparedSecond = false;
      this.pairedReady = true;
      this.onPresentationChange(true, false);
    } else {
      this.motion.reset();
      this.secondReady = false;
      this.preparedSecond = false;
      this.pairedReady = false;
      this.onPresentationChange(false, false);
    }
  }

  private onImageReady(offset: number, ready: boolean): void {
    if (!this.mounted) return;
    if (offset === 0) this.firstReady = ready;
    else this.secondReady = ready;
    if (!ready && this.paired && this.isActive &&
      (this.motion.phase === 'waiting' || this.motion.phase === 'joining' || this.motion.phase === 'settling')) {
      this.cancelMotion();
      this.motion.prepare(this.geometry());
      this.preparedSecond = true;
      this.pairedReady = false;
      this.onPresentationChange(false, false);
    }
    this.startArrivalWhenReady();
  }

  private onImageFailed(offset: number): void {
    if (!this.mounted || offset !== 1 || !this.paired || this.motion.phase !== 'waiting') return;
    // Keep the existing first node and expose the incoming page's retry control.
    this.cancelMotion();
    this.motion.settle(this.geometry());
    this.motion.finish();
    this.preparedSecond = false;
    this.pairedReady = true;
    this.onPresentationChange(true, false);
  }

  private startArrivalWhenReady(): void {
    if (!this.mounted || !this.isActive || !this.paired || !this.firstReady || !this.secondReady ||
      this.motion.phase !== 'waiting' || this.startTimer >= 0) return;
    const revision = this.revision;
    // Both native Image nodes exist before touching their render transforms.
    this.startTimer = setTimeout(() => {
      this.startTimer = -1;
      if (!this.isCurrent(revision) || !this.firstReady || !this.secondReady) return;
      hilog.info(0xE001, 'EhReaderSpread', 'Late spread join started; reversed=%{public}s', String(this.reversed));
      this.onPresentationChange(false, true);
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut, onFinish: () => {
        if (!this.isCurrent(revision)) return;
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut, onFinish: () => {
          if (!this.isCurrent(revision)) return;
          this.motion.finish();
          this.preparedSecond = false;
          this.pairedReady = true;
          this.onPresentationChange(true, false);
          hilog.info(0xE001, 'EhReaderSpread', 'Late spread join completed');
        } }, () => { this.motion.settle(this.geometry()); });
      } }, () => { this.motion.join(this.geometry()); });
    }, 0);
  }

  private isCurrent(revision: number): boolean {
    return this.mounted && this.isActive && this.paired && revision === this.revision;
  }

  private firstInteractive(): boolean {
    return this.motion.phase === 'single' || this.motion.phase === 'waiting';
  }

  @Builder
  private Page(offset: number) {
    ReaderImageViewport({
      page: offset === 0 ? this.firstPage : this.secondPage,
      statusText: this.statusText,
      preferOriginal: this.preferOriginal,
      fitMode: this.fitMode,
      fixedScale: this.fixedScale,
      startPosition: this.startPosition,
      isActive: this.isActive,
      hdrEnabled: this.hdrEnabled,
      imageAdjustmentSettings: this.imageAdjustmentSettings,
      superResolutionEnabled: this.superResolutionEnabled,
      superResolutionEngine: this.superResolutionEngine,
      superResolutionTargetWidth: offset === 0 ? this.firstTargetWidth : this.secondTargetWidth,
      superResolutionTargetHeight: offset === 0 ? this.firstTargetHeight : this.secondTargetHeight,
      cropWhiteBorders: this.cropWhiteBorders,
      hdrPriority: this.hdrPriority,
      translation: offset === 0 ? this.firstTranslation : this.secondTranslation,
      allowEdgeSwipe: this.allowEdgeSwipe,
      interactive: offset === 0 && this.firstInteractive(),
      prepareForPresentation: offset === 1 && this.preparedSecond,
      transparentBackground: true,
      readerBackgroundColorValue: this.readerBackgroundColorValue,
      command: this.command,
      commandVersion: this.commandVersion,
      onImageReady: (ready: boolean) => { this.onImageReady(offset, ready); },
      onImageFailed: () => { this.onImageFailed(offset); },
      onTap: (x: number, y: number, w: number, h: number) => {
        if (offset === 0 && this.firstInteractive()) this.onTap(x, y, w, h);
      },
      onRetry: () => { this.onRetry(offset); },
      onImageLongPress: () => { this.onImageLongPress(offset); },
      onSwipeLockChange: (locked: boolean) => { if (this.firstInteractive()) this.onSwipeLockChange(locked); },
      onZoomChange: (percent: number) => { if (this.firstInteractive()) this.onZoomChange(percent); },
      onZoomCommit: (percent: number) => { if (this.firstInteractive()) this.onZoomCommit(percent); },
      onImageSizeChange: (width: number, height: number) => { this.onImageSizeChange(offset, width, height); },
      onEdgeSwipe: (direction: number) => { this.onEdgeSwipe(direction); }
    })
      .width('100%')
      .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        // This call site and native Image survive single -> spread changes.
        Stack() { this.Page(0) }
          .width('100%').height('100%')
          .scale({ x: this.motion.scale, y: this.motion.scale })
          .translate({ x: this.motion.firstX, y: this.motion.firstY })
        if (this.paired) {
          Stack() { this.Page(1) }
            .width('100%').height('100%')
            .scale({ x: this.motion.scale, y: this.motion.scale })
            .translate({ x: this.motion.secondX, y: this.motion.secondY })
        }
      }
      .width('100%').height('100%')
      .scale({ x: this.pairedReady && this.isActive ? this.model.currentScale : 1,
        y: this.pairedReady && this.isActive ? this.model.currentScale : 1 })
      .translate({ x: this.pairedReady && this.isActive ? this.model.currentOffsetX : 0,
        y: this.pairedReady && this.isActive ? this.model.currentOffsetY : 0 })
    }
    .width('100%').height('100%')
    .backgroundColor(this.readerBackgroundColorValue)
    .clip(true)
  }
}
