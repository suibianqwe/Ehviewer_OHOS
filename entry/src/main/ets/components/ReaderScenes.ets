import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { batteryInfo } from '@kit.BasicServicesKit';
import inputConsumer from '@ohos.multimodalInput.inputConsumer';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { KeyEvent } from '@ohos.multimodalInput.keyEvent';
import { GalleryComment, GalleryPage } from '../model/GalleryModels';
import {
  applyReaderWindowState,
  getMainWindow,
  getReaderWindow,
  rememberMainWindow,
  restoreAppWindowState,
  setEmbeddedReaderActive
} from '../services/EhWindowImmersive';
import { ehSettingsStore } from '../services/EhSettingsStore';
import {
  createEmptyPage,
  getAbilityContext,
  plainTextFromHtml,
  readerClockText,
  readerDisplayImageUrl,
  uiStatusText,
  uiText
} from '../shared/EhShared';
import { readerSelectColors, selectArrowModifier } from '../shared/EhSelectStyle';
import { themeOnPrimaryText, themeOnPrimarySecondaryText, themeScrimColor } from '../shared/EhTheme';
import { EhSubNavBar } from './NavigationComponents';

const READER_MIN_SCALE: number = 1;
const READER_MAX_SCALE: number = 4;
const READER_DOUBLE_TAP_SCALE: number = 2.25;
const SLIDER_AUTO_HIDE_DELAY: number = 3000;
const READER_AUTO_TRANSFER_OFF: string = 'Off';

export interface ReaderPageState {
  index: number;
  page: GalleryPage;
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
          }, (comment: GalleryComment) => comment.id)
          ListItem() {
            Divider()
              .height(1)
              .color('#F0F0F0')
          }
        }
        .divider({ strokeWidth: 1, color: '#F0F0F0' })
        .width('100%')
        .height('100%')
        .layoutWeight(1)
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
  @Prop totalPages: number = 0;
  onBack: () => void = () => {};
  onPrev: () => void = () => {};
  onNext: () => void = () => {};
  onJump: (index: number) => void = () => {};
  onRetry: () => void = () => {};
  restoreAppChromeOnExit: boolean = true;

  @State fitMode: string = 'Fit width';
  @State showInfo: boolean = false;
  @State preferOriginal: boolean = false;
  @State menuVisible: boolean = false;
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

  // Menu settings state (reflects ehSettingsStore, applied on menu close)
  @State menuScreenRotation: string = 'System';
  @State menuReadingDirection: string = 'Right to left';
  @State menuPageScaling: string = 'Fit width';
  @State menuStartPosition: string = 'Beginning';
  @State menuKeepScreenOn: boolean = false;
  @State menuShowClock: boolean = true;
  @State menuShowProgress: boolean = true;
  @State menuShowBattery: boolean = true;
  @State menuReadingFullscreen: boolean = true;
  @State menuVolumePage: boolean = false;
  @State menuAutoTransferTime: string = READER_AUTO_TRANSFER_OFF;
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
    if (this.restoreAppChromeOnExit) {
      setEmbeddedReaderActive(true);
    }
    this.fitMode = ehSettingsStore.getValue('page_scaling', 'Fit width');
    this.menuVisible = false;
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
    const orientation = ehSettingsStore.getValue('screen_rotation', 'System');
    this.applyReaderWindowSettingsAsync(keepOn, orientation).catch(() => {});
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

  private readerOrientation(orientation: string): window.Orientation {
    if (orientation === 'Portrait') {
      return window.Orientation.PORTRAIT;
    }
    if (orientation === 'Landscape') {
      return window.Orientation.LANDSCAPE;
    }
    return window.Orientation.UNSPECIFIED;
  }

  private async applyReaderWindowSettingsAsync(keepOn: boolean, orientation: string): Promise<void> {
    await this.applyReaderWindowSettingsOnce(keepOn, orientation);
    this.scheduleReaderChromeMode(80);
    this.scheduleReaderChromeMode(260);
    this.scheduleReaderChromeMode(620);
  }

  private async applyReaderWindowSettingsOnce(keepOn: boolean, orientation: string): Promise<void> {
    const win = await this.obtainReaderWindow();
    if (win === undefined) {
      return;
    }
    if (this.restoreAppChromeOnExit) {
      setEmbeddedReaderActive(true);
    }
    await applyReaderWindowState(win, keepOn, this.readerOrientation(orientation));
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

  private scheduleReaderChromeMode(delay: number): void {
    setTimeout(() => {
      if (!this.readerWindowActive) {
        return;
      }
      const keepOn = ehSettingsStore.getValue('keep_screen_on', 'Off') === 'On';
      const orientation = ehSettingsStore.getValue('screen_rotation', 'System');
      this.applyReaderWindowSettingsOnce(keepOn, orientation).catch(() => {});
    }, delay);
  }

  private syncOverlayState(): void {
    this.overlayShowProgress = ehSettingsStore.getValue('gallery_show_progress', 'On') === 'On';
    this.overlayShowClock = ehSettingsStore.getValue('gallery_show_clock', 'On') === 'On';
    this.overlayShowBattery = ehSettingsStore.getValue('gallery_show_battery', 'On') === 'On';
  }

  private syncDirectionState(): void {
    const dir = ehSettingsStore.getValue('reading_direction', 'Right to left');
    this.swiperVertical = dir === 'Top to bottom';
    this.swiperReversed = dir === 'Right to left';
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
    this.scheduleAutoTransfer();
    try {
      this.swiperController.changeIndex(this.pageIndex, false);
    } catch (e) {}
  }

  private pageIndexes(): number[] {
    const count = this.totalPages <= 0 ? 1 : this.totalPages;
    const pages: number[] = [];
    for (let i = 0; i < count; i++) {
      pages.push(i);
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
    this.menuScreenRotation = ehSettingsStore.getValue('screen_rotation', 'System');
    this.menuReadingDirection = ehSettingsStore.getValue('reading_direction', 'Right to left');
    this.menuPageScaling = ehSettingsStore.getValue('page_scaling', 'Fit width');
    this.menuStartPosition = ehSettingsStore.getValue('start_position', 'Beginning');
    this.menuKeepScreenOn = ehSettingsStore.getValue('keep_screen_on', 'Off') === 'On';
    this.menuShowClock = ehSettingsStore.getValue('gallery_show_clock', 'On') === 'On';
    this.menuShowProgress = ehSettingsStore.getValue('gallery_show_progress', 'On') === 'On';
    this.menuShowBattery = ehSettingsStore.getValue('gallery_show_battery', 'On') === 'On';
    this.menuReadingFullscreen = ehSettingsStore.getValue('reading_fullscreen', 'On') === 'On';
    this.menuVolumePage = ehSettingsStore.getValue('volume_page', 'Off') === 'On';
    this.menuAutoTransferTime = ehSettingsStore.getValue('start_transfer_time', READER_AUTO_TRANSFER_OFF);
    this.menuCustomBrightness = ehSettingsStore.getValue('custom_screen_lightness', 'Off') === 'On';
    this.menuBrightnessLevel = ehSettingsStore.getValue('screen_lightness', '50%');
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
    ehSettingsStore.setValue('start_transfer_time', this.menuAutoTransferTime);
    ehSettingsStore.setValue('custom_screen_lightness', this.menuCustomBrightness ? 'On' : 'Off');
    ehSettingsStore.setValue('screen_lightness', this.menuBrightnessLevel);
    this.fitMode = this.menuPageScaling;
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
    const value = ehSettingsStore.getValue('start_transfer_time', READER_AUTO_TRANSFER_OFF);
    if (value === READER_AUTO_TRANSFER_OFF) {
      return 0;
    }
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
    this.hideMenu();
    this.hideSliderAndStopPlayback();
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
    if (this.autoTransferPlaying) {
      this.scheduleAutoTransfer();
    }
    try {
      this.swiperController.changeIndex(target, true);
    } catch (e) {}
    this.onJump(target);
  }

  private onSwiperChange(index: number): void {
    if (index === this.currentIndex) {
      return;
    }
    this.currentIndex = index;
    this.isDisableSwipe = false;
    this.zoomPercent = 100;
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
        ForEach(this.pageIndexes(), (index: number) => {
          ReaderImageViewport({
            page: this.pageForIndex(index),
            statusText: index === this.pageIndex ? this.statusText : uiText('Image page is loading'),
            preferOriginal: this.preferOriginal,
            fitMode: this.fitMode,
            isActive: index === this.currentIndex,
            command: this.viewportCommand,
            commandVersion: this.viewportCommandVersion,
            onTap: (x: number, y: number, w: number, h: number) => {
              if (index === this.currentIndex) {
                this.onTap(x, y, w, h);
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
      .index(this.currentIndex)
      .cachedCount(3)
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
        Column({ space: 4 }) {
          if (this.overlayShowProgress) {
            Text(this.progressText())
              .fontSize(12)
              .fontColor(themeOnPrimaryText())
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(themeScrimColor())
              .borderRadius(10)
          }
          if (this.overlayShowClock) {
            Text(readerClockText())
              .fontSize(12)
              .fontColor(themeOnPrimaryText())
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(themeScrimColor())
              .borderRadius(10)
          }
          if (this.overlayShowBattery) {
            Text(this.batteryText())
              .fontSize(12)
              .fontColor(themeOnPrimaryText())
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(themeScrimColor())
              .borderRadius(10)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .position({ x: 12, y: 12 })
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

      // ── Settings menu (upper 2/3 tap) ──
      if (this.menuVisible) {
        // Full-screen backdrop to dismiss on outside tap
        Stack() {}
          .width('100%')
          .height('100%')
          .onClick(() => { this.hideMenu(); })
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
                options: ['System', 'Portrait', 'Landscape'],
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
                options: ['Fit width', 'Fit height', 'Original', 'Smart fit'],
                value: this.menuPageScaling,
                onChange: (v: string) => { this.menuPageScaling = v; }
              })
              ReaderMenuDivider()

              ReaderMenuSelect({
                label: uiText('Start position'),
                options: ['Beginning', 'Last read', 'End'],
                value: this.menuStartPosition,
                onChange: (v: string) => { this.menuStartPosition = v; }
              })
              ReaderMenuDivider()

              ReaderMenuSelect({
                label: uiText('Auto transfer time'),
                options: [READER_AUTO_TRANSFER_OFF, '2s', '5s', '10s', '15s'],
                value: this.menuAutoTransferTime,
                onChange: (v: string) => { this.menuAutoTransferTime = v; }
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
                ReaderMenuSelect({
                  label: uiText('Screen lightness'),
                  options: ['0%', '25%', '50%', '75%', '100%'],
                  value: this.menuBrightnessLevel,
                  onChange: (v: string) => { this.menuBrightnessLevel = v; }
                })
              }

              // Bottom close button
              Button(uiText('Close'))
                .width('100%')
                .height(42)
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor('#2F6F8F')
                .borderRadius(0)
                .margin({ top: 8 })
                .onClick(() => { this.hideMenu(); })
            }
            .width('100%')
          }
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Off)
          .layoutWeight(1)
        }
        .width('100%')
        .constraintSize({ maxHeight: '80%' })
        .backgroundColor('#EE111827')
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
      Select(this.options.map((o: string) => ({ value: o } as SelectOption)))
        .id('reader-menu-select-' + this.label + '-' + this.value)
        .value(this.value)
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
        .onSelect((_idx: number, v: string) => { this.onChange(v); })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }
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
  @Prop fitMode: string = 'Fit width';
  @Prop isActive: boolean = false;
  @Prop command: string = '';
  @Prop @Watch('onCommandChange') commandVersion: number = 0;
  onTap: (x: number, y: number, w: number, h: number) => void = () => {};
  onSwipeLockChange: (locked: boolean) => void = (_locked: boolean) => {};
  onZoomChange: (percent: number) => void = (_percent: number) => {};

  @State imageModel: ReaderPreviewModel = new ReaderPreviewModel();
  @State completedImageUrl: string = '';
  @State failedImageUrl: string = '';
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

  private onImageSourceChange(): void {
    const url = this.imageUrl();
    if (this.completedImageUrl !== url) {
      this.completedImageUrl = '';
    }
    if (this.failedImageUrl !== url) {
      this.failedImageUrl = '';
    }
  }

  private imageFit(): ImageFit {
    if (this.fitMode === 'Original') {
      return ImageFit.None;
    }
    if (this.fitMode === 'Smart fit') {
      return ImageFit.Cover;
    }
    if (this.fitMode === 'Fit height') {
      return ImageFit.Fill;
    }
    // 'Fit width' — default
    return ImageFit.Contain;
  }

  private imageWidth(): string {
    if (this.fitMode === 'Fit height') {
      return 'auto';
    }
    return '100%';
  }

  private imageHeight(): string {
    if (this.fitMode === 'Fit width') {
      return 'auto';
    }
    return '100%';
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
    this.imageModel.setImageSize(width, height);
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
    Stack({ alignContent: Alignment.Center }) {
      if (this.imageUrl().length > 0) {
        Image(this.imageUrl())
          .width(this.imageWidth())
          .height(this.imageHeight())
          .objectFit(this.imageFit())
          .backgroundColor('#050608')
          .opacity(this.failedImageUrl === this.imageUrl() ? 0 : 1)
          .onComplete(() => {
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
          PanGesture({ fingers: 1, distance: this.imageModel.disableSwipe ? 3 : 50 })
            .onActionStart(() => {
              this.imageModel.panStart();
              this.reportState();
            })
            .onActionUpdate((event: GestureEvent) => {
              this.imageModel.panUpdate(event.offsetX, event.offsetY);
              this.reportState();
            })
            .onActionEnd(() => {
              this.imageModel.panEnd();
              this.reportState();
            })
            .onActionCancel(() => {
              this.imageModel.panEnd();
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
