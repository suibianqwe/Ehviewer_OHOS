import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { batteryInfo, pasteboard } from '@kit.BasicServicesKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import inputConsumer from '@ohos.multimodalInput.inputConsumer';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { KeyEvent } from '@ohos.multimodalInput.keyEvent';
import { GalleryComment, GalleryPage } from '../model/GalleryModels';
import {
  applyReaderWindowState,
  getMainWindow,
  getReaderWindow,
  rememberMainWindow,
  readerOrientationFromSetting,
  readerScreenRotationSetting,
  restoreAppWindowState,
  setEmbeddedReaderActive
} from '../services/EhWindowImmersive';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { readerImageCache } from '../services/ReaderImageCache';
import {
  createEmptyPage,
  getAbilityContext,
  plainTextFromHtml,
  readerClockText,
  readerDisplayImageUrl,
  normalizePageScalingOption,
  normalizeReadingDirectionOption,
  normalizeStartPositionOption,
  normalizeAutoTransferTimeOption,
  normalizeBrightnessLevelOption,
  uiStatusText,
  uiText,
  uiValue
} from '../shared/EhShared';
import { ArrayDataSource } from '../shared/ListDataSource';
import { readerSelectColors, selectArrowModifier } from '../shared/EhSelectStyle';
import { themeOnPrimaryText, themeOnPrimarySecondaryText, themeScrimColor } from '../shared/EhTheme';
import { EhSubNavBar } from './NavigationComponents';

const READER_MIN_SCALE: number = 1;
const READER_MAX_SCALE: number = 4;
const READER_DOUBLE_TAP_SCALE: number = 2.25;
const SLIDER_AUTO_HIDE_DELAY: number = 3000;
const READER_OFFSCREEN_RENDER_COUNT: number = 2;

export interface ReaderPageState {
  index: number;
  page: GalleryPage;
}

interface ReaderImageCompleteEvent {
  width: number;
  height: number;
  componentWidth: number;
  componentHeight: number;
  loadingStatus: number;
}

@Observed
class ReaderPreviewModel {
  currentScale: number = READER_MIN_SCALE;
  lastScale: number = READER_MIN_SCALE;
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
    this.currentScale = READER_MIN_SCALE;
    this.lastScale = READER_MIN_SCALE;
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
    if (this.currentScale <= READER_MIN_SCALE + 0.01) {
      this.reset();
      return;
    }
    this.restrictBoundary();
    this.commit();
  }

  panStart(): void {
    this.lastOffsetX = this.currentOffsetX;
    this.lastOffsetY = this.currentOffsetY;
    this.lastScale = this.currentScale;
    this.disableSwipe = this.currentScale > READER_MIN_SCALE + 0.01 && !this.isHorizontalBoundary();
  }

  panUpdate(offsetX: number, offsetY: number): void {
    if (this.currentScale <= READER_MIN_SCALE + 0.01) {
      this.disableSwipe = false;
      return;
    }
    this.currentOffsetX = this.lastOffsetX + offsetX;
    this.currentOffsetY = this.lastOffsetY + offsetY;
    this.restrictBoundary();
  }

  panEnd(): void {
    this.restrictBoundary();
    this.commit();
  }

  toggleDoubleTap(centerX: number, centerY: number): void {
    if (this.currentScale > READER_MIN_SCALE + 0.01) {
      this.reset();
      return;
    }
    const center = this.evaluateCenter(centerX, centerY);
    this.centerX = center[0];
    this.centerY = center[1];
    this.lastScale = READER_MIN_SCALE;
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
    if (Math.abs(target - READER_MIN_SCALE) < 0.01) {
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

  private commit(): void {
    this.lastScale = this.currentScale;
    this.lastOffsetX = this.currentOffsetX;
    this.lastOffsetY = this.currentOffsetY;
    this.disableSwipe = this.currentScale > READER_MIN_SCALE + 0.01 && !this.isHorizontalBoundary();
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
    if (this.currentScale <= READER_MIN_SCALE + 0.01) {
      this.currentOffsetX = 0;
      this.currentOffsetY = 0;
      this.disableSwipe = false;
    } else {
      this.disableSwipe = !this.isHorizontalBoundary();
    }
  }

  private isHorizontalBoundary(): boolean {
    const maxX = this.maxOffsetX();
    if (maxX <= 0) {
      return true;
    }
    return Math.abs(this.currentOffsetX) >= maxX - 0.5;
  }
}

@Component
export struct CommentsScene {
  @Prop renderVersion: number = 0;
  @Prop comments: GalleryComment[] = [];
  @Prop galleryTitle: string = '';
  onBack: () => void = () => {};
  @StorageProp('statusBarHeight') statusBarHeightPx: number = 0;

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  build() {
    Column() {
      EhSubNavBar({
        statusBarHeight: this.statusBarVp(),
        title: uiText('Comments'),
        onBack: this.onBack
      })
      Row() {
        Text(this.galleryTitle)
          .fontSize(12)
          .fontColor('#667085')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.comments.length.toString() + ' ' + uiText('total'))
          .fontSize(12)
          .fontColor('#667085')
          .margin({ left: 12 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(Color.White)

      if (this.comments.length === 0) {
        PlaceholderScene({
          title: 'Comments',
          detail: 'No comments for this gallery.'
        })
      } else {
        List({ space: 0 }) {
          ForEach(this.comments, (comment: GalleryComment) => {
            ListItem() {
              Column() {
                Row() {
                  Text(comment.user.length > 0 ? comment.user : uiText('Anonymous'))
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#17202A')
                    .layoutWeight(1)
                  if (comment.score !== 0) {
                    Text((comment.score > 0 ? '+' : '') + comment.score.toString())
                      .fontSize(12)
                      .fontColor(comment.score > 0 ? '#0A6B45' : '#B03060')
                      .margin({ left: 8 })
                  }
                }
                .width('100%')
                .margin({ bottom: 4 })

                Text(comment.posted)
                  .fontSize(11)
                  .fontColor('#667085')
                  .margin({ bottom: 8 })

                Text(plainTextFromHtml(comment.content))
                  .fontSize(14)
                  .fontColor('#17202A')
                  .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .backgroundColor(Color.White)
            }
            .reuseId('comment-row')
          }, (comment: GalleryComment) => comment.id)
          ListItem() {
            Divider()
              .height(1)
              .color('#F0F0F0')
          }
          .reuseId('comment-divider')
        }
        .divider({ strokeWidth: 1, color: '#F0F0F0' })
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .cachedCount(4)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}

@Component
export struct ReaderScene {
  @Prop @Watch('onRenderVersionChange') renderVersion: number = 0;
  @Prop page: GalleryPage = createEmptyPage();
  @Prop readerPages: ReaderPageState[] = [];
  @Prop statusText: string = '';
  @Prop @Watch('onPageIndexChange') pageIndex: number = 0;
  @Prop @Watch('onTotalPagesChange') totalPages: number = 0;
  onBack: () => void = () => {};
  onPrev: () => void = () => {};
  onNext: () => void = () => {};
  onJump: (index: number) => void = () => {};
  onRetry: () => void = () => {};
  restoreAppChromeOnExit: boolean = true;

  @State fitMode: string = 'Fit screen';
  @State startPosition: string = 'Top right';
  @State showInfo: boolean = false;
  @State preferOriginal: boolean = false;
  @State menuVisible: boolean = false;
  @State imageActionsVisible: boolean = false;
  @State sliderVisible: boolean = false;
  @State autoTransferPlaying: boolean = false;
  @State currentIndex: number = 0;
  @State isDisableSwipe: boolean = false;
  @State zoomPercent: number = 100;
  @State viewportCommand: string = '';
  @State viewportCommandVersion: number = 0;
  // Swiper direction state (applied from menu)
  @State swiperVertical: boolean = false;
  @State swiperReversed: boolean = false;
  // Overlay display state (updated when menu closes)
  @State overlayShowProgress: boolean = true;
  @State overlayShowClock: boolean = true;
  @State overlayShowBattery: boolean = true;
  @State batteryLevel: number = -1;
  private swiperController: SwiperController = new SwiperController();
  private sliderHideTimer: number = -1;
  private readerPageIndexesSource: ArrayDataSource<number> = new ArrayDataSource<number>([]);
  private readerPageIndexesCount: number = -1;
  private readerPageIndexesReversed: boolean = false;

  // Menu settings state (reflects ehSettingsStore, applied on menu close)
  @State menuScreenRotation: string = 'Default';
  @State menuReadingDirection: string = 'Right to left';
  @State menuPageScaling: string = 'Fit screen';
  @State menuStartPosition: string = 'Top right';
  @State menuKeepScreenOn: boolean = false;
  @State menuShowClock: boolean = true;
  @State menuShowProgress: boolean = true;
  @State menuShowBattery: boolean = true;
  @State menuReadingFullscreen: boolean = true;
  @State menuVolumePage: boolean = false;
  @State menuAutoTransferTime: string = '5s';
  @State menuCustomBrightness: boolean = false;
  @State menuBrightnessLevel: string = '50%';
  private readerWindowActive: boolean = false;
  private hostReaderWindow: window.Window | undefined = undefined;
  private autoTransferTimer: number = -1;
  private volumeUpConfig: inputConsumer.KeyPressedConfig = {
    key: KeyCode.KEYCODE_VOLUME_UP,
    action: 1,
    isRepeat: false
  };
  private volumeDownConfig: inputConsumer.KeyPressedConfig = {
    key: KeyCode.KEYCODE_VOLUME_DOWN,
    action: 1,
    isRepeat: false
  };
  private volumePageRegistered: boolean = false;
  private volumePageCallback: (event: KeyEvent) => void = (event: KeyEvent) => {
    this.handleVolumePageKey(event);
  };

  aboutToAppear(): void {
    this.readerWindowActive = true;
    this.syncReaderPageIndexSource();
    if (this.restoreAppChromeOnExit) {
      setEmbeddedReaderActive(true);
    }
    this.fitMode = normalizePageScalingOption(ehSettingsStore.getValue('page_scaling', 'Fit screen'));
    this.startPosition = normalizeStartPositionOption(ehSettingsStore.getValue('start_position', 'Top right'));
    this.menuVisible = false;
    this.imageActionsVisible = false;
    this.sliderVisible = false;
    this.currentIndex = this.pageIndex;
    this.syncOverlayState();
    this.syncDirectionState();
    this.refreshBattery();
    this.applyReaderWindowSettings();
    this.applyBrightnessFromSettings().catch(() => {});
    this.updateVolumePageBinding();
  }

  aboutToDisappear(): void {
    this.readerWindowActive = false;
    this.clearSliderTimer();
    this.clearAutoTransferTimer();
    this.unregisterVolumePageKeys();
    this.resetReaderBrightness().catch(() => {});
    this.restoreWindowSettings();
  }

  private restoreWindowSettings(): void {
    if (!this.restoreAppChromeOnExit) {
      return;
    }
    this.restoreWindowSettingsAsync().catch(() => {});
  }

  private applyReaderWindowSettings(): void {
    const keepOn = ehSettingsStore.getValue('keep_screen_on', 'Off') === 'On';
    const orientation = readerScreenRotationSetting();
    const fullscreen = ehSettingsStore.getValue('reading_fullscreen', 'On') === 'On';
    this.applyReaderWindowSettingsAsync(keepOn, orientation, fullscreen).catch(() => {});
  }

  private async obtainReaderWindow(): Promise<window.Window | undefined> {
    if (!this.restoreAppChromeOnExit) {
      return getReaderWindow();
    }
    if (this.hostReaderWindow !== undefined) {
      return this.hostReaderWindow;
    }
    try {
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (hostContext !== undefined) {
        const win = await window.getLastWindow(hostContext);
        this.hostReaderWindow = win;
        rememberMainWindow(win);
        return win;
      }
    } catch (error) {
    }
    return getMainWindow();
  }

  private async applyReaderWindowSettingsAsync(keepOn: boolean, orientation: string, fullscreen: boolean): Promise<void> {
    await this.applyReaderWindowSettingsOnce(keepOn, orientation, fullscreen);
    this.scheduleReaderChromeMode(80);
    this.scheduleReaderChromeMode(260);
    this.scheduleReaderChromeMode(620);
  }

  private async applyReaderWindowSettingsOnce(keepOn: boolean, orientation: string, fullscreen: boolean): Promise<void> {
    const win = await this.obtainReaderWindow();
    if (win === undefined) {
      return;
    }
    if (this.restoreAppChromeOnExit) {
      setEmbeddedReaderActive(true);
    }
    await applyReaderWindowState(win, keepOn, readerOrientationFromSetting(orientation), fullscreen);
  }

  private async restoreWindowSettingsAsync(): Promise<void> {
    setEmbeddedReaderActive(false);
    const win = await this.obtainReaderWindow();
    if (win === undefined) {
      return;
    }
    await restoreAppWindowState(win);
  }

  onRenderVersionChange(): void {
    this.applyReaderWindowSettings();
  }

  onTotalPagesChange(): void {
    this.syncReaderPageIndexSource();
  }

  private scheduleReaderChromeMode(delay: number): void {
    setTimeout(() => {
      if (!this.readerWindowActive) {
        return;
      }
      const keepOn = ehSettingsStore.getValue('keep_screen_on', 'Off') === 'On';
      const orientation = readerScreenRotationSetting();
      const fullscreen = ehSettingsStore.getValue('reading_fullscreen', 'On') === 'On';
      this.applyReaderWindowSettingsOnce(keepOn, orientation, fullscreen).catch(() => {});
    }, delay);
  }

  private syncOverlayState(): void {
    this.overlayShowProgress = ehSettingsStore.getValue('gallery_show_progress', 'On') === 'On';
    this.overlayShowClock = ehSettingsStore.getValue('gallery_show_clock', 'On') === 'On';
    this.overlayShowBattery = ehSettingsStore.getValue('gallery_show_battery', 'On') === 'On';
  }

  private syncDirectionState(): void {
    const dir = normalizeReadingDirectionOption(ehSettingsStore.getValue('reading_direction', 'Right to left'));
    const oldReversed = this.swiperReversed;
    this.swiperVertical = dir === 'Top to bottom';
    this.swiperReversed = dir === 'Right to left';
    if (oldReversed !== this.swiperReversed) {
      this.readerPageIndexesCount = -1;
      this.syncReaderPageIndexSource();
      try {
        this.swiperController.changeIndex(this.visualIndexForPageIndex(this.currentIndex), false);
      } catch (e) {}
    }
  }

  private refreshBattery(): void {
    try {
      this.batteryLevel = batteryInfo.batterySOC;
    } catch (e) {
      this.batteryLevel = -1;
    }
  }

  private batteryText(): string {
    return this.batteryLevel >= 0 ? this.batteryLevel.toString() + '%' : '--';
  }

  onPageIndexChange(): void {
    this.currentIndex = this.pageIndex;
    this.isDisableSwipe = false;
    this.zoomPercent = 100;
    this.imageActionsVisible = false;
    this.scheduleAutoTransfer();
    try {
      this.swiperController.changeIndex(this.visualIndexForPageIndex(this.pageIndex), false);
    } catch (e) {}
  }

  private pageIndexes(): number[] {
    const count = this.totalPages <= 0 ? 1 : this.totalPages;
    const pages: number[] = [];
    if (this.swiperReversed) {
      for (let i = count - 1; i >= 0; i--) {
        pages.push(i);
      }
    } else {
      for (let i = 0; i < count; i++) {
        pages.push(i);
      }
    }
    return pages;
  }

  private pageForIndex(index: number): GalleryPage {
    if (index === this.pageIndex) {
      return this.page;
    }
    for (let i = 0; i < this.readerPages.length; i++) {
      if (this.readerPages[i].index === index) {
        return this.readerPages[i].page;
      }
    }
    return createEmptyPage();
  }

  private readerPageIndexSource(): ArrayDataSource<number> {
    this.syncReaderPageIndexSource();
    return this.readerPageIndexesSource;
  }

  private readerRenderCacheCount(): number {
    return READER_OFFSCREEN_RENDER_COUNT;
  }

  private syncReaderPageIndexSource(): void {
    const count = this.totalPages <= 0 ? 1 : this.totalPages;
    if (count === this.readerPageIndexesCount && this.readerPageIndexesReversed === this.swiperReversed) {
      return;
    }
    this.readerPageIndexesCount = count;
    this.readerPageIndexesReversed = this.swiperReversed;
    this.readerPageIndexesSource.setItems(this.pageIndexes());
  }

  private visualIndexForPageIndex(index: number): number {
    const count = this.totalPages <= 0 ? 1 : this.totalPages;
    const pageIndex = Math.max(0, Math.min(count - 1, index));
    return this.swiperReversed ? count - 1 - pageIndex : pageIndex;
  }

  private pageIndexForVisualIndex(index: number): number {
    const count = this.totalPages <= 0 ? 1 : this.totalPages;
    const visualIndex = Math.max(0, Math.min(count - 1, index));
    return this.swiperReversed ? count - 1 - visualIndex : visualIndex;
  }

  private issueViewportCommand(command: string): void {
    this.viewportCommand = command;
    this.viewportCommandVersion++;
  }

  private clearSliderTimer(): void {
    if (this.sliderHideTimer !== -1) {
      clearTimeout(this.sliderHideTimer);
      this.sliderHideTimer = -1;
    }
  }

  private scheduleSliderHide(): void {
    this.clearSliderTimer();
    this.sliderHideTimer = setTimeout(() => {
      this.sliderVisible = false;
      this.sliderHideTimer = -1;
    }, SLIDER_AUTO_HIDE_DELAY) as number;
  }

  private showSlider(): void {
    this.imageActionsVisible = false;
    this.sliderVisible = true;
    this.scheduleSliderHide();
  }

  private hideSlider(): void {
    this.clearSliderTimer();
    this.sliderVisible = false;
  }

  private hideSliderAndStopPlayback(): void {
    this.stopAutoTransferPlayback();
    this.hideSlider();
  }

  private showMenu(): void {
    this.imageActionsVisible = false;
    this.menuScreenRotation = readerScreenRotationSetting();
    this.menuReadingDirection = normalizeReadingDirectionOption(ehSettingsStore.getValue('reading_direction', 'Right to left'));
    this.menuPageScaling = normalizePageScalingOption(ehSettingsStore.getValue('page_scaling', 'Fit screen'));
    this.menuStartPosition = normalizeStartPositionOption(ehSettingsStore.getValue('start_position', 'Top right'));
    this.menuKeepScreenOn = ehSettingsStore.getValue('keep_screen_on', 'Off') === 'On';
    this.menuShowClock = ehSettingsStore.getValue('gallery_show_clock', 'On') === 'On';
    this.menuShowProgress = ehSettingsStore.getValue('gallery_show_progress', 'On') === 'On';
    this.menuShowBattery = ehSettingsStore.getValue('gallery_show_battery', 'On') === 'On';
    this.menuReadingFullscreen = ehSettingsStore.getValue('reading_fullscreen', 'On') === 'On';
    this.menuVolumePage = ehSettingsStore.getValue('volume_page', 'Off') === 'On';
    this.menuAutoTransferTime = normalizeAutoTransferTimeOption(ehSettingsStore.getValue('start_transfer_time', '5s'));
    this.menuCustomBrightness = ehSettingsStore.getValue('custom_screen_lightness', 'Off') === 'On';
    this.menuBrightnessLevel = normalizeBrightnessLevelOption(ehSettingsStore.getValue('screen_lightness', '50%'));
    this.menuVisible = true;
    this.clearAutoTransferTimer();
    this.autoTransferPlaying = false;
  }

  private applyMenuSettings(): void {
    ehSettingsStore.setValue('screen_rotation', this.menuScreenRotation);
    ehSettingsStore.setValue('reading_direction', this.menuReadingDirection);
    ehSettingsStore.setValue('page_scaling', this.menuPageScaling);
    ehSettingsStore.setValue('start_position', this.menuStartPosition);
    ehSettingsStore.setValue('keep_screen_on', this.menuKeepScreenOn ? 'On' : 'Off');
    ehSettingsStore.setValue('gallery_show_clock', this.menuShowClock ? 'On' : 'Off');
    ehSettingsStore.setValue('gallery_show_progress', this.menuShowProgress ? 'On' : 'Off');
    ehSettingsStore.setValue('gallery_show_battery', this.menuShowBattery ? 'On' : 'Off');
    ehSettingsStore.setValue('reading_fullscreen', this.menuReadingFullscreen ? 'On' : 'Off');
    ehSettingsStore.setValue('volume_page', this.menuVolumePage ? 'On' : 'Off');
    ehSettingsStore.setValue('start_transfer_time', normalizeAutoTransferTimeOption(this.menuAutoTransferTime));
    ehSettingsStore.setValue('custom_screen_lightness', this.menuCustomBrightness ? 'On' : 'Off');
    ehSettingsStore.setValue('screen_lightness', normalizeBrightnessLevelOption(this.menuBrightnessLevel));
    this.fitMode = normalizePageScalingOption(this.menuPageScaling);
    this.startPosition = normalizeStartPositionOption(this.menuStartPosition);
    this.issueViewportCommand('reset');
    this.syncOverlayState();
    this.syncDirectionState();
    this.refreshBattery();
    this.applyBrightness().catch(() => {});
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch(() => {});
    }
    this.applyReaderWindowSettings();
    this.updateVolumePageBinding();
    if (this.autoTransferPlaying) {
      this.scheduleAutoTransfer();
    }
  }

  private async applyBrightness(): Promise<void> {
    const win = await this.obtainReaderWindow();
    if (win === undefined) {
      return;
    }
    if (!this.menuCustomBrightness) {
      win.setWindowBrightness(-1).catch(() => {});
      return;
    }
    const pct = Number.parseFloat(this.menuBrightnessLevel) / 100;
    const brightness = Number.isNaN(pct) ? 0.5 : Math.max(0, Math.min(1, pct));
    win.setWindowBrightness(brightness).catch(() => {});
  }

  private async applyBrightnessFromSettings(): Promise<void> {
    const win = await this.obtainReaderWindow();
    if (win === undefined) {
      return;
    }
    if (ehSettingsStore.getValue('custom_screen_lightness', 'Off') !== 'On') {
      win.setWindowBrightness(-1).catch(() => {});
      return;
    }
    const pct = Number.parseFloat(ehSettingsStore.getValue('screen_lightness', '50%')) / 100;
    const brightness = Number.isNaN(pct) ? 0.5 : Math.max(0, Math.min(1, pct));
    win.setWindowBrightness(brightness).catch(() => {});
  }

  private async resetReaderBrightness(): Promise<void> {
    const win = await this.obtainReaderWindow();
    if (win !== undefined) {
      win.setWindowBrightness(-1).catch(() => {});
    }
  }

  private clearAutoTransferTimer(): void {
    if (this.autoTransferTimer !== -1) {
      clearTimeout(this.autoTransferTimer);
      this.autoTransferTimer = -1;
    }
  }

  private autoTransferDelayMs(): number {
    const value = normalizeAutoTransferTimeOption(ehSettingsStore.getValue('start_transfer_time', '5s'));
    const seconds = Number.parseInt(value);
    if (Number.isNaN(seconds) || seconds <= 0) {
      return 0;
    }
    return seconds * 1000;
  }

  private scheduleAutoTransfer(): void {
    this.clearAutoTransferTimer();
    if (!this.readerWindowActive || !this.autoTransferPlaying) {
      return;
    }
    if (!this.canGoNext()) {
      this.autoTransferPlaying = false;
      return;
    }
    const delay = this.autoTransferDelayMs();
    if (delay <= 0) {
      return;
    }
    this.autoTransferTimer = setTimeout(() => {
      this.autoTransferTimer = -1;
      if (!this.readerWindowActive || this.menuVisible || this.sliderVisible || !this.canGoNext()) {
        return;
      }
      this.jumpTo(this.currentIndex + 1);
    }, delay) as number;
  }

  private startAutoTransferPlayback(): void {
    if (!this.canGoNext() || this.autoTransferDelayMs() <= 0) {
      return;
    }
    this.autoTransferPlaying = true;
    this.hideSlider();
    this.scheduleAutoTransfer();
  }

  private stopAutoTransferPlayback(): void {
    this.autoTransferPlaying = false;
    this.clearAutoTransferTimer();
  }

  private toggleAutoTransferPlayback(): void {
    if (this.autoTransferPlaying) {
      this.stopAutoTransferPlayback();
    } else {
      this.startAutoTransferPlayback();
    }
  }

  private updateVolumePageBinding(): void {
    if (ehSettingsStore.getValue('volume_page', 'Off') === 'On') {
      this.registerVolumePageKeys();
    } else {
      this.unregisterVolumePageKeys();
    }
  }

  private registerVolumePageKeys(): void {
    if (this.volumePageRegistered) {
      return;
    }
    try {
      inputConsumer.on('keyPressed', this.volumeUpConfig, this.volumePageCallback);
      inputConsumer.on('keyPressed', this.volumeDownConfig, this.volumePageCallback);
      this.volumePageRegistered = true;
    } catch (error) {
      this.volumePageRegistered = false;
    }
  }

  private unregisterVolumePageKeys(): void {
    if (!this.volumePageRegistered) {
      return;
    }
    try {
      inputConsumer.off('keyPressed', this.volumePageCallback);
    } catch (error) {
    }
    this.volumePageRegistered = false;
  }

  private handleVolumePageKey(event: KeyEvent): void {
    if (!this.readerWindowActive || ehSettingsStore.getValue('volume_page', 'Off') !== 'On') {
      return;
    }
    if (event.key.code === KeyCode.KEYCODE_VOLUME_UP) {
      this.jumpTo(this.currentIndex - 1);
    } else if (event.key.code === KeyCode.KEYCODE_VOLUME_DOWN) {
      this.jumpTo(this.currentIndex + 1);
    }
  }

  private hideMenu(): void {
    this.applyMenuSettings();
    this.menuVisible = false;
    this.showInfo = false;
    if (this.autoTransferPlaying) {
      this.scheduleAutoTransfer();
    }
  }

  private hideAll(): void {
    if (this.menuVisible) {
      this.hideMenu();
    }
    this.imageActionsVisible = false;
    this.hideSliderAndStopPlayback();
  }

  private showImageActions(): void {
    if (readerDisplayImageUrl(this.pageForIndex(this.currentIndex), this.preferOriginal).length === 0) {
      return;
    }
    this.hideSliderAndStopPlayback();
    this.menuVisible = false;
    this.imageActionsVisible = true;
  }

  private hideImageActions(): void {
    this.imageActionsVisible = false;
  }

  private refreshCurrentImage(): void {
    this.hideImageActions();
    this.onRetry();
  }

  private shareCurrentImage(): void {
    const target = this.currentImageShareTarget();
    this.hideImageActions();
    if (target.length === 0) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, target);
      pasteboard.getSystemPasteboard().setData(data).catch(() => {});
    } catch (error) {
    }
  }

  private saveCurrentImage(): void {
    const page = this.pageForIndex(this.currentIndex);
    this.hideImageActions();
    this.saveReaderImageAsync(page).catch(() => {});
  }

  private currentImageShareTarget(): string {
    const page = this.pageForIndex(this.currentIndex);
    const path = this.localImagePathForPage(page);
    if (path.length > 0) {
      return path;
    }
    if (this.preferOriginal && page.originImageUrl.length > 0) {
      return page.originImageUrl;
    }
    return page.imageUrl;
  }

  private localImagePathForPage(page: GalleryPage): string {
    if (this.preferOriginal && page.cachedOriginImagePath !== undefined && page.cachedOriginImagePath.length > 0) {
      return stripFileScheme(page.cachedOriginImagePath);
    }
    if (!this.preferOriginal && page.cachedImagePath !== undefined && page.cachedImagePath.length > 0) {
      return stripFileScheme(page.cachedImagePath);
    }
    if (page.cachedImagePath !== undefined && page.cachedImagePath.length > 0) {
      return stripFileScheme(page.cachedImagePath);
    }
    if (page.cachedOriginImagePath !== undefined && page.cachedOriginImagePath.length > 0) {
      return stripFileScheme(page.cachedOriginImagePath);
    }
    return '';
  }

  private async saveReaderImageAsync(page: GalleryPage): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    let sourcePath = this.localImagePathForPage(page);
    if (sourcePath.length === 0) {
      const imageUrl = this.preferOriginal && page.originImageUrl.length > 0 ? page.originImageUrl : page.imageUrl;
      if (imageUrl.length === 0) {
        return;
      }
      sourcePath = await readerImageCache.ensureCached(context, imageUrl, page.pageUrl, true);
    }
    if (sourcePath.length === 0) {
      return;
    }
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [readerImageFileName(this.currentIndex, sourcePath, this.currentImageShareTarget())];
    const documentPicker = new picker.DocumentViewPicker(context);
    const uris = await documentPicker.save(options);
    if (uris.length === 0) {
      return;
    }
    try {
      fs.copyFileSync(sourcePath, uris[0]);
    } catch (error) {
    }
  }

  // Called from ReaderImageViewport with tap coordinates (vp units)
  private onTap(x: number, y: number, w: number, h: number): void {
    if (this.autoTransferPlaying) {
      this.stopAutoTransferPlayback();
      return;
    }
    if (this.menuVisible) {
      this.hideAll();
      return;
    }
    if (this.imageActionsVisible) {
      this.hideImageActions();
      return;
    }
    if (this.sliderVisible) {
      this.hideSliderAndStopPlayback();
      return;
    }
    const relX = w > 0 ? x / w : 0.5;
    const relY = h > 0 ? y / h : 0.5;
    if (this.swiperVertical) {
      // Top-to-bottom: tap top 1/3 → prev, bottom 1/3 → next, center → menu
      if (relY < 1.0 / 3.0) {
        this.jumpTo(this.currentIndex - 1);
      } else if (relY > 2.0 / 3.0) {
        this.jumpTo(this.currentIndex + 1);
      } else {
        this.showMenu();
      }
      return;
    }
    // Horizontal modes
    if (relX < 1.0 / 3.0) {
      // Left tap: prev for LTR, next for RTL
      this.swiperReversed ? this.jumpTo(this.currentIndex + 1) : this.jumpTo(this.currentIndex - 1);
    } else if (relX > 2.0 / 3.0) {
      // Right tap: next for LTR, prev for RTL
      this.swiperReversed ? this.jumpTo(this.currentIndex - 1) : this.jumpTo(this.currentIndex + 1);
    } else if (relY < 2.0 / 3.0) {
      this.showMenu();
    } else {
      this.showSlider();
    }
  }

  private canGoNext(): boolean {
    return this.totalPages <= 0 || this.currentIndex + 1 < this.totalPages;
  }

  private jumpTo(value: number): void {
    if (this.totalPages <= 0) {
      return;
    }
    const target = Math.max(0, Math.min(this.totalPages - 1, Math.round(value)));
    if (target === this.currentIndex) {
      return;
    }
    this.currentIndex = target;
    this.isDisableSwipe = false;
    this.zoomPercent = 100;
    this.imageActionsVisible = false;
    if (this.autoTransferPlaying) {
      this.scheduleAutoTransfer();
    }
    try {
      this.swiperController.changeIndex(this.visualIndexForPageIndex(target), true);
    } catch (e) {}
    this.onJump(target);
  }

  private onSwiperChange(visualIndex: number): void {
    const index = this.pageIndexForVisualIndex(visualIndex);
    if (index === this.currentIndex) {
      return;
    }
    this.currentIndex = index;
    this.isDisableSwipe = false;
    this.zoomPercent = 100;
    this.imageActionsVisible = false;
    if (this.autoTransferPlaying) {
      this.scheduleAutoTransfer();
    }
    this.onJump(index);
  }

  private progressText(): string {
    const total = this.totalPages <= 0 ? 1 : this.totalPages;
    return (this.currentIndex + 1).toString() + '/' + total.toString();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Swiper(this.swiperController) {
        LazyForEach(this.readerPageIndexSource(), (index: number) => {
          ReaderImageViewport({
            page: this.pageForIndex(index),
            statusText: index === this.pageIndex ? this.statusText : uiText('Image page is loading'),
            preferOriginal: this.preferOriginal,
            fitMode: this.fitMode,
            startPosition: this.startPosition,
            isActive: index === this.currentIndex,
            command: this.viewportCommand,
            commandVersion: this.viewportCommandVersion,
            onTap: (x: number, y: number, w: number, h: number) => {
              if (index === this.currentIndex) {
                this.onTap(x, y, w, h);
              }
            },
            onRetry: () => {
              if (index === this.currentIndex) {
                this.onRetry();
              }
            },
            onImageLongPress: () => {
              if (index === this.currentIndex) {
                this.showImageActions();
              }
            },
            onSwipeLockChange: (locked: boolean) => {
              if (index === this.currentIndex) {
                this.isDisableSwipe = locked;
              }
            },
            onZoomChange: (percent: number) => {
              if (index === this.currentIndex) {
                this.zoomPercent = percent;
              }
            }
          })
            .width('100%')
            .height('100%')
        }, (index: number) => index.toString())
      }
      .index(this.visualIndexForPageIndex(this.currentIndex))
      .cachedCount(this.readerRenderCacheCount())
      .indicator(false)
      .loop(false)
      .autoPlay(false)
      .vertical(this.swiperVertical)
      .displayCount(1)
      .itemSpace(0)
      .duration(180)
      .curve(Curve.EaseOut)
      .effectMode(EdgeEffect.None)
      .disableSwipe(this.isDisableSwipe)
      .onChange((index: number) => {
        this.onSwiperChange(index);
      })
      .width('100%')
      .height('100%')
      .backgroundColor('#050608')

      // Floating progress / clock / battery overlay (when no panel shown)
      if (!this.menuVisible && !this.sliderVisible) {
        Row() {
          Row({ space: 8 }) {
            if (this.overlayShowProgress) {
              Text(this.progressText())
                .fontSize(12)
                .fontColor(themeOnPrimaryText())
                .lineHeight(16)
            }
            if (this.overlayShowClock) {
              Text(readerClockText())
                .fontSize(12)
                .fontColor(themeOnPrimaryText())
                .lineHeight(16)
            }
            if (this.overlayShowBattery) {
              Text(this.batteryText())
                .fontSize(12)
                .fontColor(themeOnPrimaryText())
                .lineHeight(16)
            }
          }
          .alignItems(VerticalAlign.Center)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(themeScrimColor())
          .borderRadius(10)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 12, right: 12 })
        .position({ x: 0, y: 12 })
        .zIndex(3)
      }

      // ── Slider panel (lower 1/3 tap, auto-hides after 3s) ──
      if (this.sliderVisible) {
        Stack() {}
          .width('100%')
          .height('100%')
          .onClick(() => { this.hideSliderAndStopPlayback(); })
          .zIndex(4)

        Column() {
          Row() {
            Text((this.currentIndex + 1).toString())
              .fontSize(12)
              .fontColor('#E5E7EB')
              .width(42)
              .textAlign(TextAlign.Center)
            Slider({
              value: this.currentIndex,
              min: 0,
              max: Math.max(0, this.totalPages - 1),
              step: 1
            })
              .layoutWeight(1)
              .enabled(this.totalPages > 1)
              .onChange((value: number, mode: SliderChangeMode) => {
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  this.stopAutoTransferPlayback();
                  this.clearSliderTimer();
                  this.jumpTo(value);
                  this.scheduleSliderHide();
                }
              })
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph(this.autoTransferPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
                .fontSize(18)
                .fontColor([Color.White])
            }
              .width(42)
              .height(36)
              .enabled(this.autoTransferDelayMs() > 0 && this.canGoNext())
              .backgroundColor(this.autoTransferDelayMs() > 0 && this.canGoNext() ? '#334155' : '#1F2937')
              .onClick(() => {
                this.toggleAutoTransferPlayback();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 16 })
        .backgroundColor('#CC111827')
        .position({ x: 0, y: '100%' })
        .translate({ y: '-100%' })
        .zIndex(5)
      }

      if (this.imageActionsVisible) {
        ReaderPopupBackdrop({
          onDismiss: () => {
            this.hideImageActions();
          }
        })
          .zIndex(6)

        ReaderImageActionDialog({
          onRefresh: () => {
            this.refreshCurrentImage();
          },
          onShare: () => {
            this.shareCurrentImage();
          },
          onSave: () => {
            this.saveCurrentImage();
          }
        })
          .zIndex(7)
      }

      // ── Settings menu (upper 2/3 tap) ──
      if (this.menuVisible) {
        ReaderPopupBackdrop({
          onDismiss: () => {
            this.hideMenu();
          }
        })
          .zIndex(6)

        Column() {
          // Top bar: back + title + clock/progress
          Row() {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(20)
                .fontColor([Color.White])
            }
            .width(36)
            .height(36)
            .backgroundColor('#334155')
            .onClick(() => { this.onBack(); })

            Text(uiStatusText(this.statusText))
              .fontSize(12)
              .fontColor('#E5E7EB')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 10 })
              .layoutWeight(1)
            if (this.menuShowClock) {
              Text(readerClockText())
                .fontSize(12)
                .fontColor('#E5E7EB')
                .margin({ left: 8 })
            }
            if (this.menuShowProgress) {
              Text(this.progressText())
                .fontSize(12)
                .fontColor('#E5E7EB')
                .margin({ left: 8 })
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 10 })
          .backgroundColor(themeScrimColor())

          // Scrollable settings body
          Scroll() {
            Column({ space: 0 }) {

              ReaderMenuSelect({
                label: uiText('Screen rotation'),
                options: ['Default', 'Portrait', 'Landscape', 'Auto rotate'],
                value: this.menuScreenRotation,
                onChange: (v: string) => { this.menuScreenRotation = v; }
              })
              ReaderMenuDivider()

              ReaderMenuSelect({
                label: uiText('Reading direction'),
                options: ['Left to right', 'Right to left', 'Top to bottom'],
                value: this.menuReadingDirection,
                onChange: (v: string) => { this.menuReadingDirection = v; }
              })
              ReaderMenuDivider()

              ReaderMenuSelect({
                label: uiText('Page scaling'),
                options: ['Actual size', 'Fit width', 'Fit height', 'Fit screen', 'Fixed scale'],
                value: this.menuPageScaling,
                onChange: (v: string) => { this.menuPageScaling = v; }
              })
              ReaderMenuDivider()

              ReaderMenuSelect({
                label: uiText('Start position'),
                options: ['Top left', 'Top right', 'Bottom left', 'Bottom right', 'Center'],
                value: this.menuStartPosition,
                onChange: (v: string) => { this.menuStartPosition = v; }
              })
              ReaderMenuDivider()

              ReaderMenuSlider({
                label: uiText('Auto transfer time'),
                value: readerAutoTransferSliderValue(this.menuAutoTransferTime),
                min: 1,
                max: 20,
                step: 1,
                valueText: (value: number) => {
                  return uiValue(readerAutoTransferValue(value));
                },
                onChange: (value: number) => {
                  this.menuAutoTransferTime = readerAutoTransferValue(value);
                }
              })
              ReaderMenuDivider()

              ReaderMenuToggle({
                label: uiText('Keep screen on'),
                value: this.menuKeepScreenOn,
                onChange: (v: boolean) => { this.menuKeepScreenOn = v; }
              })
              ReaderMenuDivider()

              ReaderMenuToggle({
                label: uiText('Show clock'),
                value: this.menuShowClock,
                onChange: (v: boolean) => { this.menuShowClock = v; }
              })
              ReaderMenuDivider()

              ReaderMenuToggle({
                label: uiText('Show progress'),
                value: this.menuShowProgress,
                onChange: (v: boolean) => { this.menuShowProgress = v; }
              })
              ReaderMenuDivider()

              ReaderMenuToggle({
                label: uiText('Show battery'),
                value: this.menuShowBattery,
                onChange: (v: boolean) => { this.menuShowBattery = v; }
              })
              ReaderMenuDivider()

              ReaderMenuToggle({
                label: uiText('Reading fullscreen'),
                value: this.menuReadingFullscreen,
                onChange: (v: boolean) => { this.menuReadingFullscreen = v; }
              })
              ReaderMenuDivider()

              ReaderMenuToggle({
                label: uiText('Volume page'),
                value: this.menuVolumePage,
                onChange: (v: boolean) => { this.menuVolumePage = v; }
              })
              ReaderMenuDivider()

              ReaderMenuToggle({
                label: uiText('Custom brightness'),
                value: this.menuCustomBrightness,
                onChange: (v: boolean) => { this.menuCustomBrightness = v; }
              })

              if (this.menuCustomBrightness) {
                ReaderMenuDivider()
                ReaderMenuSlider({
                  label: uiText('Screen lightness'),
                  value: readerBrightnessSliderValue(this.menuBrightnessLevel),
                  min: 0,
                  max: 100,
                  step: 1,
                  valueText: (value: number) => {
                    return readerBrightnessValue(value);
                  },
                  onChange: (value: number) => {
                    this.menuBrightnessLevel = readerBrightnessValue(value);
                    this.applyBrightness().catch(() => {});
                  }
                })
              }
            }
            .width('100%')
          }
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Off)
        }
        .width('92%')
        .constraintSize({ maxWidth: 520, maxHeight: '82%' })
        .backgroundColor('#EE111827')
        .borderRadius(12)
        .clip(true)
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
        .zIndex(7)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#050608')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

}

@Component
struct ReaderPopupBackdrop {
  onDismiss: () => void = () => {};

  build() {
    Stack() {}
      .width('100%')
      .height('100%')
      .backgroundColor('#99000000')
      .onClick(() => {
        this.onDismiss();
      })
      .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
  }
}

@Component
struct ReaderImageActionDialog {
  onRefresh: () => void = () => {};
  onShare: () => void = () => {};
  onSave: () => void = () => {};

  build() {
    Column({ space: 0 }) {
      ReaderImageActionButton({
        label: uiText('Refresh'),
        symbolIcon: $r('sys.symbol.arrow_clockwise'),
        onTap: this.onRefresh
      })
      ReaderMenuDivider()
      ReaderImageActionButton({
        label: uiText('Share'),
        symbolIcon: $r('sys.symbol.share'),
        onTap: this.onShare
      })
      ReaderMenuDivider()
      ReaderImageActionButton({
        label: uiText('Save'),
        symbolIcon: $r('sys.symbol.save'),
        onTap: this.onSave
      })
    }
    .width('78%')
    .constraintSize({ maxWidth: 360 })
    .padding({ top: 6, bottom: 6 })
    .backgroundColor('#F0111827')
    .borderRadius(12)
    .clip(true)
    .shadow({ radius: 18, color: '#66000000', offsetY: 8 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
  }
}

@Component
struct ReaderImageActionButton {
  label: string = '';
  symbolIcon: Resource = $r('sys.symbol.circle');
  onTap: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row() {
        SymbolGlyph(this.symbolIcon)
          .fontSize(20)
          .fontColor([Color.White])
        Text(this.label)
          .fontSize(15)
          .fontColor(Color.White)
          .margin({ left: 12 })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height(48)
    .backgroundColor(Color.Transparent)
    .borderRadius(0)
    .onClick(() => {
      this.onTap();
    })
  }
}

@Component
struct ReaderMenuDivider {
  build() {
    Divider()
      .height(1)
      .color('#1FFFFFFF')
      .margin({ left: 16, right: 16 })
  }
}

@Component
struct ReaderMenuSelect {
  label: string = '';
  options: string[] = [];
  value: string = '';
  onChange: (v: string) => void = () => {};

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor('#E5E7EB')
        .layoutWeight(1)
      Select(this.options.map((o: string) => ({ value: uiValue(o) } as SelectOption)))
        .id('reader-menu-select-' + this.label + '-' + this.value)
        .selected(readerMenuOptionIndex(this.options, this.value))
        .value(uiValue(this.value))
        .font({ size: 13 })
        .fontColor(readerSelectColors().buttonText)
        .backgroundColor(readerSelectColors().buttonBackground)
        .menuBackgroundColor(readerSelectColors().menuBackground)
        .menuBackgroundBlurStyle(undefined)
        .optionBgColor(readerSelectColors().optionBackground)
        .optionFontColor(readerSelectColors().optionText)
        .optionFont({ size: 13 })
        .selectedOptionBgColor(readerSelectColors().selectedOptionBackground)
        .selectedOptionFontColor(readerSelectColors().selectedOptionText)
        .menuOutline({ width: 1, color: readerSelectColors().outline })
        .arrowModifier(selectArrowModifier(readerSelectColors().arrow))
        .onSelect((idx: number) => {
          if (idx >= 0 && idx < this.options.length) {
            this.onChange(this.options[idx]);
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }
}

@Component
struct ReaderMenuSlider {
  label: string = '';
  @Prop @Watch('onValueChange') value: number = 0;
  min: number = 0;
  max: number = 100;
  step: number = 1;
  valueText: (v: number) => string = (v: number): string => v.toString();
  onChange: (v: number) => void = () => {};
  @State liveValue: number = 0;

  aboutToAppear(): void {
    this.liveValue = this.value;
  }

  onValueChange(): void {
    this.liveValue = this.value;
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text(this.label)
          .fontSize(14)
          .fontColor('#E5E7EB')
          .layoutWeight(1)
        Text(this.valueText(this.liveValue))
          .fontSize(13)
          .fontColor('#CBD5E1')
          .width(54)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Slider({
        value: this.liveValue,
        min: this.min,
        max: this.max,
        step: this.step
      })
        .width('100%')
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.liveValue = Math.max(this.min, Math.min(this.max, Math.round(value)));
          this.onChange(this.liveValue);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 10 })
  }
}

function readerMenuOptionIndex(options: string[], value: string): number {
  for (let i = 0; i < options.length; i++) {
    if (options[i] === value) {
      return i;
    }
  }
  return 0;
}

function readerAutoTransferSliderValue(value: string): number {
  return Number.parseInt(normalizeAutoTransferTimeOption(value));
}

function readerAutoTransferValue(value: number): string {
  return Math.max(1, Math.min(20, Math.round(value))).toString() + 's';
}

function readerBrightnessSliderValue(value: string): number {
  const numberValue = Number.parseInt(value);
  if (Number.isNaN(numberValue)) {
    return 50;
  }
  return Math.max(0, Math.min(100, numberValue));
}

function readerBrightnessValue(value: number): string {
  return normalizeBrightnessLevelOption(Math.max(0, Math.min(100, Math.round(value))).toString() + '%');
}

function stripFileScheme(path: string): string {
  return path.indexOf('file://') === 0 ? path.substring('file://'.length) : path;
}

function readerImageFileName(index: number, sourcePath: string, sourceUrl: string): string {
  const ext = readerImageExtension(sourcePath.length > 0 ? sourcePath : sourceUrl);
  return 'ehviewer_page_' + (index + 1).toString() + ext;
}

function readerImageExtension(value: string): string {
  const lower = value.toLowerCase();
  const queryIndex = lower.indexOf('?');
  const clean = queryIndex >= 0 ? lower.substring(0, queryIndex) : lower;
  const slash = clean.lastIndexOf('/');
  const dot = clean.lastIndexOf('.');
  if (dot > slash && dot >= 0) {
    const ext = clean.substring(dot);
    if (ext === '.jpg' || ext === '.jpeg' || ext === '.png' || ext === '.webp' || ext === '.gif') {
      return ext;
    }
  }
  return '.jpg';
}

@Component
struct ReaderMenuToggle {
  label: string = '';
  value: boolean = false;
  onChange: (v: boolean) => void = () => {};

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor('#E5E7EB')
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.value })
        .onChange((v: boolean) => { this.onChange(v); })
        .selectedColor('#2F6F8F')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }
}

@Component
struct ReaderImageViewport {
  @Prop @Watch('onImageSourceChange') page: GalleryPage = createEmptyPage();
  @Prop statusText: string = '';
  @Prop @Watch('onImageSourceChange') preferOriginal: boolean = false;
  @Prop @Watch('onFitModeChange') fitMode: string = 'Fit screen';
  @Prop startPosition: string = 'Top right';
  @Prop isActive: boolean = false;
  @Prop command: string = '';
  @Prop @Watch('onCommandChange') commandVersion: number = 0;
  onTap: (x: number, y: number, w: number, h: number) => void = () => {};
  onRetry: () => void = () => {};
  onImageLongPress: () => void = () => {};
  onSwipeLockChange: (locked: boolean) => void = (_locked: boolean) => {};
  onZoomChange: (percent: number) => void = (_percent: number) => {};

  @State imageModel: ReaderPreviewModel = new ReaderPreviewModel();
  @State completedImageUrl: string = '';
  @State failedImageUrl: string = '';
  @State sourceImageWidth: number = 0;
  @State sourceImageHeight: number = 0;
  @State displayImageWidth: number = 1;
  @State displayImageHeight: number = 1;
  private lastCommandVersion: number = -1;

  aboutToAppear(): void {
    this.onImageSourceChange();
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
    }
    this.reportState();
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
    if (this.completedImageUrl !== url) {
      this.completedImageUrl = '';
    }
    if (this.failedImageUrl !== url) {
      this.failedImageUrl = '';
    }
    this.sourceImageWidth = 0;
    this.sourceImageHeight = 0;
    this.updateDisplayImageSize();
  }

  private onFitModeChange(): void {
    this.imageModel.reset();
    this.updateDisplayImageSize();
    this.reportState();
  }

  private imageFit(): ImageFit {
    return ImageFit.Fill;
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
    const sourceWidth = this.sourceImageWidth > 0 ? this.sourceImageWidth : componentWidth;
    const sourceHeight = this.sourceImageHeight > 0 ? this.sourceImageHeight : componentHeight;
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
    } else {
      displayWidth = sourceWidth;
      displayHeight = sourceHeight;
    }
    this.displayImageWidth = Math.max(1, displayWidth);
    this.displayImageHeight = Math.max(1, displayHeight);
    this.imageModel.setImageSize(this.displayImageWidth, this.displayImageHeight);
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
    if (!this.isActive) {
      return;
    }
    this.onSwipeLockChange(this.imageModel.disableSwipe);
    this.onZoomChange(this.imageModel.zoomPercent());
  }

  build() {
    Stack({ alignContent: this.startAlignment() }) {
      if (this.imageUrl().length > 0) {
        Image(this.imageUrl())
          .width(this.imageDisplayWidth())
          .height(this.imageDisplayHeight())
          .objectFit(this.imageFit())
          .backgroundColor('#050608')
          .opacity(this.failedImageUrl === this.imageUrl() ? 0 : 1)
          .onComplete((event?: ReaderImageCompleteEvent) => {
            if (event !== undefined && event.width > 0 && event.height > 0) {
              this.sourceImageWidth = event.width;
              this.sourceImageHeight = event.height;
              this.updateDisplayImageSize();
            }
            this.completedImageUrl = this.imageUrl();
            this.failedImageUrl = '';
          })
          .onError(() => {
            this.failedImageUrl = this.imageUrl();
          })
          .scale({ x: this.imageModel.currentScale, y: this.imageModel.currentScale, centerX: '50%', centerY: '50%' })
          .translate({ x: this.imageModel.currentOffsetX, y: this.imageModel.currentOffsetY })
          .animation({ duration: 120, curve: Curve.EaseOut })
        if (this.isImageLoading()) {
          LoadingProgress()
            .width(44)
            .height(44)
            .color(themeOnPrimarySecondaryText())
            .padding(8)
            .backgroundColor(themeScrimColor())
            .borderRadius(22)
            .zIndex(2)
        } else if (this.isFailed()) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
              .fontSize(32)
              .fontColor(['#98A2B3'])
            Text(uiText('Image page failed to load'))
              .fontSize(16)
              .fontColor('#98A2B3')
          }
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.failedImageUrl = '';
            this.completedImageUrl = '';
            this.onRetry();
          })
          .zIndex(2)
        }
      } else {
        Column({ space: 12 }) {
          if (this.isFailed()) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
              .fontSize(32)
              .fontColor(['#98A2B3'])
          } else {
            LoadingProgress()
              .width(36)
              .height(36)
              .color('#98A2B3')
          }
          Text(this.isFailed() ? uiText('Image page failed to load') : uiText('Image page is loading'))
            .fontSize(16)
            .fontColor('#98A2B3')
        }
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.isFailed()) {
            this.onRetry();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#050608')
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
  }
}
@Component
export struct ReaderToolButton {
  text: string = '';
  active: boolean = true;
  onTap: () => void = () => {};

  build() {
    Button(this.text)
      .height(32)
      .fontSize(12)
      .fontColor(this.active ? Color.White : '#6B7280')
      .backgroundColor(this.active ? '#334155' : '#1F2937')
      .enabled(this.active)
      .onClick(() => {
        if (this.active) {
          this.onTap();
        }
      })
  }
}

@Component
export struct ReaderNavButton {
  text: string = '';
  active: boolean = true;
  onTap: () => void = () => {};

  build() {
    Row() {
      Text(this.text)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.active ? Color.White : '#98A2B3')
    }
    .justifyContent(FlexAlign.Center)
    .height(42)
    .width('100%')
    .backgroundColor(this.active ? '#2F6F8F' : '#1F2937')
    .borderRadius(4)
    .onClick(() => {
      if (this.active) {
        this.onTap();
      }
    })
  }
}

@Component
export struct PlaceholderScene {
  title: string = '';
  detail: string = '';

  build() {
    Column() {
      Text(this.title)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#17202A')
      Text(this.detail)
        .fontSize(14)
        .fontColor('#667085')
        .lineHeight(22)
        .textAlign(TextAlign.Center)
        .margin({ top: 10 })
        .width('80%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }
}
