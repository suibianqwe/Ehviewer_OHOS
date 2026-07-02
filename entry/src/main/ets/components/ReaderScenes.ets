import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { batteryInfo } from '@kit.BasicServicesKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import inputConsumer from '@ohos.multimodalInput.inputConsumer';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { KeyEvent } from '@ohos.multimodalInput.keyEvent';
import { GalleryPage } from '../model/GalleryModels';
import {
  applyReaderWindowState,
  applyReaderBrightnessFromSettings,
  getMainWindow,
  getReaderWindow,
  isEmbeddedReaderActive,
  rememberMainWindow,
  rememberReaderWindow,
  readerOrientationFromImageMatch,
  readerOrientationFromSetting,
  readerScreenRotationSetting,
  setEmbeddedReaderActive
} from '../services/EhWindowImmersive';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { galleryPageCache } from '../services/GalleryPageCache';
import { readerImageCache } from '../services/ReaderImageCache';
import {
  createEmptyPage,
  getAbilityContext,
  readerDisplayImageUrl,
  readerPageImageCacheKey,
  readerClockText,
  normalizePageScalingOption,
  normalizeReadingDirectionOption,
  normalizeStartPositionOption,
  normalizeAutoTransferTimeOption,
  normalizeBrightnessLevelOption,
  normalizeUltraDarkLightnessOption,
  BOTTOM_AVOID_HEIGHT_KEY,
  STATUS_BAR_HEIGHT_KEY,
  uiText
} from '../shared/EhShared';
import { ArrayDataSource } from '../shared/ListDataSource';
import {
  READER_BASE_SCALE,
  READER_MAX_SCALE,
  READER_MIN_SCALE,
  READER_OFFSCREEN_RENDER_COUNT,
  readerBackgroundColor
} from './reader/core/ReaderCore';
import {
  addUniquePath,
  albumImageFileType,
  copyFileContent,
  readerImageExtension,
  readerImageFileName,
  removeFileIfExists,
  stripFileScheme
} from './reader/io/ReaderImageFileOps';
import { readerUltraDarkSliderValue } from './reader/menu/ReaderMenuControls';
import {
  ReaderImageActionsOverlay,
  ReaderInfoOverlay,
  ReaderSettingsMenuOverlay,
  ReaderSliderPanel
} from './reader/overlays/ReaderOverlays';
import { ReaderContinuousImageItem } from './reader/viewports/ReaderContinuousImageItem';
import { ReaderImageViewport } from './reader/viewports/ReaderImageViewport';

export { ReaderNavButton, ReaderToolButton } from './reader/controls/ReaderButtons';
export { CommentsScene, PlaceholderScene } from './reader/scenes/ReaderAuxScenes';

const SLIDER_AUTO_HIDE_DELAY: number = 3000;
const READER_SCREEN_TAP_DELAY: number = 220;

function mediaAssetTitle(fileName: string): string {
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
  onRefreshPage: (index: number) => void = () => {};
  restoreAppChromeOnExit: boolean = true;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  @StorageProp(BOTTOM_AVOID_HEIGHT_KEY) bottomAvoidHeight: number = 0;

  @State fitMode: string = 'Fit screen';
  @State startPosition: string = 'Top right';
  @State showInfo: boolean = false;
  @State preferOriginal: boolean = false;
  @State menuVisible: boolean = false;
  @State imageActionsVisible: boolean = false;
  @State sliderVisible: boolean = false;
  @State sliderLiveIndex: number = 0;
  @State sliderDragging: boolean = false;
  @State sliderTrackWidth: number = 1;
  @State readerLayoutWidth: number = 0;
  @State readerLayoutHeight: number = 0;
  @State autoTransferPlaying: boolean = false;
  @State currentIndex: number = 0;
  @State isDisableSwipe: boolean = false;
  @State zoomPercent: number = 100;
  @State fixedScale: number = READER_BASE_SCALE;
  @State continuousOffsetX: number = 0;
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
  @State clockText: string = '';
  private swiperController: SwiperController = new SwiperController();
  private sliderHideTimer: number = -1;
  private readerPageIndexesSource: ArrayDataSource<number> = new ArrayDataSource<number>([]);
  private readerPageIndexesCount: number = -1;
  private readerPageIndexesReversed: boolean = false;
  private continuousScroller: Scroller = new Scroller();
  private activeImageWidth: number = 0;
  private activeImageHeight: number = 0;
  private continuousDragStartOffsetX: number = 0;

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
  @State menuUltraDarkMode: boolean = false;
  @State menuUltraDarkBrightness: string = '50%';
  private readerWindowActive: boolean = false;
  private hostReaderWindow: window.Window | undefined = undefined;
  private autoTransferTimer: number = -1;
  private overlayRefreshTimer: number = -1;
  private overlayRefreshCount: number = 0;
  private screenTapTimer: number = -1;
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
  private volumeUpRegistered: boolean = false;
  private volumeDownRegistered: boolean = false;
  private transientDisappearCleanupTimer: number = -1;
  private volumeUpCallback: (event: KeyEvent) => void = (event: KeyEvent) => {
    this.handleVolumePageKey(event);
  };
  private volumeDownCallback: (event: KeyEvent) => void = (event: KeyEvent) => {
    this.handleVolumePageKey(event);
  };

  aboutToAppear(): void {
    if (this.transientDisappearCleanupTimer !== -1) {
      clearTimeout(this.transientDisappearCleanupTimer);
      this.transientDisappearCleanupTimer = -1;
    }
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
    this.syncUltraDarkState();
    this.refreshBattery();
    this.refreshOverlayInfo();
    this.startOverlayRefreshTimer();
    this.applyReaderWindowSettings();
    this.applyBrightnessFromSettings().catch(() => {});
    this.updateVolumePageBinding();
  }

  aboutToDisappear(): void {
    if (this.restoreAppChromeOnExit && !isEmbeddedReaderActive()) {
      this.restoreSystemBarsForReaderExit();
    }
    if (this.restoreAppChromeOnExit && isEmbeddedReaderActive()) {
      this.scheduleTransientDisappearCleanup();
      return;
    }
    this.cleanupReaderScene();
  }

  private restoreSystemBarsForReaderExit(): void {
    const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (hostContext === undefined) {
      return;
    }
    window.getLastWindow(hostContext).then(async (win: window.Window) => {
      const visibleBars: Array<'status' | 'navigation'> = ['status'];
      try {
        await win.setWindowSystemBarEnable(visibleBars);
      } catch (error) {
      }
      try {
        await win.setSpecificSystemBarEnabled('status', true);
      } catch (error) {
      }
      try {
        await win.setSpecificSystemBarEnabled('navigationIndicator', false);
      } catch (error) {
      }
    }).catch(() => {});
  }

  private scheduleTransientDisappearCleanup(): void {
    if (this.transientDisappearCleanupTimer !== -1) {
      clearTimeout(this.transientDisappearCleanupTimer);
    }
    this.transientDisappearCleanupTimer = setTimeout(() => {
      this.transientDisappearCleanupTimer = -1;
      if (!this.restoreAppChromeOnExit || !isEmbeddedReaderActive()) {
        this.cleanupReaderScene();
      }
    }, 120) as number;
  }

  private cleanupReaderScene(): void {
    this.readerWindowActive = false;
    this.clearSliderTimer();
    this.clearScreenTapTimer();
    this.clearAutoTransferTimer();
    this.clearOverlayRefreshTimer();
    this.unregisterVolumePageKeys();
    this.resetReaderBrightness().catch(() => {});
  }

  private applyReaderWindowSettings(): void {
    const keepOn = ehSettingsStore.getValue('keep_screen_on', 'Off') === 'On';
    const orientation = readerScreenRotationSetting();
    const fullscreen = ehSettingsStore.getValue('reading_fullscreen', 'On') === 'On';
    this.applyReaderWindowSettingsAsync(keepOn, orientation, fullscreen).catch(() => {});
  }

  private async obtainReaderWindow(): Promise<window.Window | undefined> {
    if (this.hostReaderWindow !== undefined) {
      return this.hostReaderWindow;
    }
    try {
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (hostContext !== undefined) {
        const win = hostContext.windowStage.getMainWindowSync();
        this.hostReaderWindow = win;
        if (this.restoreAppChromeOnExit) {
          rememberMainWindow(win);
        } else {
          rememberReaderWindow(win);
        }
        return win;
      }
    } catch (error) {
    }
    const readerWin = getReaderWindow();
    if (readerWin !== undefined) {
      return readerWin;
    }
    if (!this.restoreAppChromeOnExit) {
      return undefined;
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
    if (this.restoreAppChromeOnExit && !isEmbeddedReaderActive()) {
      return;
    }
    if (this.restoreAppChromeOnExit) {
      setEmbeddedReaderActive(true);
    }
    await applyReaderWindowState(win, keepOn, this.readerOrientationForSetting(win, orientation), fullscreen);
  }

  private readerOrientationForSetting(win: window.Window, orientation: string): window.Orientation | undefined {
    if (orientation === 'Match image') {
      return readerOrientationFromImageMatch(win, this.activeImageWidth, this.activeImageHeight);
    }
    return readerOrientationFromSetting(orientation);
  }

  onRenderVersionChange(): void {
    this.applyReaderWindowSettings();
  }

  onTotalPagesChange(): void {
    this.syncReaderPageIndexSource();
    this.sliderLiveIndex = this.clampReaderPageIndex(this.currentIndex);
  }

  private statusBarHeightVp(): number {
    if (this.statusBarHeightPx <= 0) {
      return 0;
    }
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  private readerStatusOverlayTop(): number {
    return Math.max(12, this.statusBarHeightVp() + 8);
  }

  private readerStatusOverlayRight(): number {
    return 12;
  }

  private readerBottomInset(): number {
    return Math.max(0, this.bottomAvoidHeight);
  }

  private scheduleReaderChromeMode(delay: number): void {
    setTimeout(() => {
      if (!this.readerWindowActive) {
        return;
      }
      if (this.restoreAppChromeOnExit && !isEmbeddedReaderActive()) {
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

  private refreshOverlayInfo(): void {
    this.clockText = readerClockText();
    this.overlayRefreshCount++;
    if (this.overlayRefreshCount % 10 === 0 || this.batteryLevel < 0) {
      this.refreshBattery();
    }
  }

  private startOverlayRefreshTimer(): void {
    this.clearOverlayRefreshTimer();
    this.overlayRefreshTimer = setInterval(() => {
      if (!this.readerWindowActive) {
        return;
      }
      this.refreshOverlayInfo();
    }, 1000);
  }

  private clearOverlayRefreshTimer(): void {
    if (this.overlayRefreshTimer >= 0) {
      clearInterval(this.overlayRefreshTimer);
      this.overlayRefreshTimer = -1;
    }
  }

  onPageIndexChange(): void {
    this.currentIndex = this.pageIndex;
    this.sliderLiveIndex = this.clampReaderPageIndex(this.pageIndex);
    this.sliderDragging = false;
    this.isDisableSwipe = false;
    this.zoomPercent = this.isFixedScaleMode() ? Math.round(this.fixedScale * 100) : 100;
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

  private isFixedScaleMode(): boolean {
    return normalizePageScalingOption(this.fitMode) === 'Fixed scale';
  }

  private isContinuousVerticalMode(): boolean {
    return this.swiperVertical;
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

  private clearScreenTapTimer(): void {
    if (this.screenTapTimer !== -1) {
      clearTimeout(this.screenTapTimer);
      this.screenTapTimer = -1;
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
    this.sliderLiveIndex = this.clampReaderPageIndex(this.currentIndex);
    this.sliderDragging = false;
    this.sliderVisible = true;
    this.scheduleSliderHide();
  }

  private hideSlider(): void {
    this.clearSliderTimer();
    this.sliderVisible = false;
    this.sliderDragging = false;
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
    const nextFitMode = normalizePageScalingOption(this.menuPageScaling);
    if (nextFitMode === 'Fixed scale') {
      this.fixedScale = Math.max(READER_MIN_SCALE, Math.min(READER_MAX_SCALE, this.zoomPercent / 100));
      this.zoomPercent = Math.round(this.fixedScale * 100);
    } else {
      this.zoomPercent = 100;
    }
    this.fitMode = nextFitMode;
    this.startPosition = normalizeStartPositionOption(this.menuStartPosition);
    this.issueViewportCommand(nextFitMode === 'Fixed scale' ? 'fixed_scale' : 'reset');
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

  private applyContinuousMenuConstraints(): void {
    this.menuScreenRotation = 'Default';
    this.menuPageScaling = 'Fixed scale';
    this.zoomPercent = 100;
    this.fixedScale = READER_BASE_SCALE;
  }

  private readerMenuScreenRotationOptions(): string[] {
    if (this.menuReadingDirection === 'Top to bottom') {
      return ['Default', 'Portrait', 'Landscape', 'Auto rotate'];
    }
    return ['Default', 'Portrait', 'Landscape', 'Auto rotate', 'Match image'];
  }

  private readerMenuPageScalingOptions(): string[] {
    if (this.menuReadingDirection === 'Top to bottom') {
      return ['Actual size', 'Fit width', 'Fixed scale'];
    }
    return ['Actual size', 'Fit width', 'Fit height', 'Fit screen', 'Fixed scale'];
  }

  private onMenuReadingDirectionChange(value: string): void {
    const previous = this.menuReadingDirection;
    this.menuReadingDirection = normalizeReadingDirectionOption(value);
    if (previous !== 'Top to bottom' && this.menuReadingDirection === 'Top to bottom') {
      this.applyContinuousMenuConstraints();
    }
  }

  private async applyBrightness(): Promise<void> {
    const win = await this.obtainReaderWindow();
    if (win === undefined) {
      return;
    }
    if (this.menuUltraDarkMode) {
      win.setWindowBrightness(0).catch(() => {});
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
    await applyReaderBrightnessFromSettings(win);
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
    if (this.volumeUpRegistered && this.volumeDownRegistered) {
      return;
    }
    try {
      if (!this.volumeUpRegistered) {
        inputConsumer.on('keyPressed', this.volumeUpConfig, this.volumeUpCallback);
        this.volumeUpRegistered = true;
      }
    } catch (error) {
      this.volumeUpRegistered = false;
    }
    try {
      if (!this.volumeDownRegistered) {
        inputConsumer.on('keyPressed', this.volumeDownConfig, this.volumeDownCallback);
        this.volumeDownRegistered = true;
      }
    } catch (error) {
      this.volumeDownRegistered = false;
    }
  }

  private unregisterVolumePageKeys(): void {
    if (this.volumeUpRegistered) {
      try {
        inputConsumer.off('keyPressed', this.volumeUpCallback);
      } catch (error) {
      }
      this.volumeUpRegistered = false;
    }
    if (this.volumeDownRegistered) {
      try {
        inputConsumer.off('keyPressed', this.volumeDownCallback);
      } catch (error) {
      }
      this.volumeDownRegistered = false;
    }
  }

  private handleVolumePageKey(event: KeyEvent): void {
    if (!this.readerWindowActive || ehSettingsStore.getValue('volume_page', 'Off') !== 'On') {
      return;
    }
    if (event.key.code === KeyCode.KEYCODE_VOLUME_UP) {
      this.previousReaderPage();
    } else if (event.key.code === KeyCode.KEYCODE_VOLUME_DOWN) {
      this.nextReaderPage();
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

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
    }
  }

  private refreshCurrentImage(): void {
    const page = this.pageForIndex(this.currentIndex);
    const index = this.currentIndex;
    this.hideImageActions();
    this.removeCurrentImageFiles(page);
    this.onRefreshPage(index);
  }

  private shareCurrentImage(): void {
    const page = this.pageForIndex(this.currentIndex);
    const index = this.currentIndex;
    this.hideImageActions();
    this.shareCurrentImageAsync(page, index).catch(() => {});
  }

  private saveCurrentImageToAlbum(): void {
    const page = this.pageForIndex(this.currentIndex);
    const index = this.currentIndex;
    this.saveReaderImageToAlbumAsync(page, index).catch(() => {});
  }

  private saveCurrentImageToPicker(): void {
    const page = this.pageForIndex(this.currentIndex);
    const index = this.currentIndex;
    this.hideImageActions();
    this.saveReaderImageAsync(page, index).catch(() => {});
  }

  private removeCurrentImageFiles(page: GalleryPage): void {
    const context = getAbilityContext();
    const paths: string[] = [];
    addUniquePath(paths, page.cachedImagePath);
    addUniquePath(paths, page.cachedOriginImagePath);
    if (context !== undefined) {
      addUniquePath(paths, readerImageCache.removeCached(context, page.imageUrl, readerPageImageCacheKey(page, false)));
      addUniquePath(paths, readerImageCache.removeCached(context, page.originImageUrl, readerPageImageCacheKey(page, true)));
    }
    for (let i = 0; i < paths.length; i++) {
      removeFileIfExists(paths[i]);
    }
    galleryPageCache.remove(page.pageUrl);
  }

  private async shareCurrentImageAsync(page: GalleryPage, index: number): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    const sourcePath = await this.ensureLocalImagePathForPage(page);
    if (sourcePath.length === 0) {
      return;
    }
    const extension = readerImageExtension(sourcePath);
    const utdTypeId = utd.getUniformDataTypeByFilenameExtension(extension);
    const shareData: systemShare.SharedData = new systemShare.SharedData({
      utd: utdTypeId,
      uri: fileUri.getUriFromPath(sourcePath),
      title: readerImageFileName(index, sourcePath, this.currentImageShareTarget()),
      description: 'EhViewer'
    });
    const controller = new systemShare.ShareController(shareData);
    try {
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
    } catch (error) {
    }
  }

  private syncUltraDarkState(): void {
    this.menuUltraDarkMode = ehSettingsStore.getValue('ultra_dark_mode', 'Off') === 'On';
    this.menuUltraDarkBrightness = normalizeUltraDarkLightnessOption(ehSettingsStore.getValue('ultra_dark_lightness', '50%'));
  }

  private ultraDarkOverlayOpacity(): number {
    if (!this.menuUltraDarkMode) {
      return 0;
    }
    return 1 - readerUltraDarkSliderValue(this.menuUltraDarkBrightness) / 100;
  }

  private async saveReaderImageToAlbumAsync(page: GalleryPage, index: number): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    const sourcePath = await this.ensureLocalImagePathForPage(page);
    if (sourcePath.length === 0) {
      this.showToast(uiText('Save failed'));
      return;
    }
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const fileName = readerImageFileName(index, sourcePath, this.currentImageShareTarget());
      const title = mediaAssetTitle(fileName);
      const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, albumImageFileType(sourcePath), { title: title });
      if (copyFileContent(sourcePath, uri)) {
        this.showToast(uiText('Saved to album') + ': ' + fileName);
        this.hideImageActions();
      } else {
        this.showToast(uiText('Save failed'));
      }
    } catch (error) {
      this.showToast(uiText('Save failed'));
    }
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

  private async ensureLocalImagePathForPage(page: GalleryPage): Promise<string> {
    const context = getAbilityContext();
    if (context === undefined) {
      return '';
    }
    let sourcePath = this.localImagePathForPage(page);
    if (sourcePath.length === 0) {
      const imageUrl = this.preferOriginal && page.originImageUrl.length > 0 ? page.originImageUrl : page.imageUrl;
      if (imageUrl.length === 0) {
        return '';
      }
      sourcePath = await readerImageCache.ensureCached(context, imageUrl, page.pageUrl, true, undefined,
        readerPageImageCacheKey(page, this.preferOriginal && page.originImageUrl.length > 0));
    }
    return sourcePath;
  }

  private async saveReaderImageAsync(page: GalleryPage, index: number): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    const sourcePath = await this.ensureLocalImagePathForPage(page);
    if (sourcePath.length === 0) {
      return;
    }
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [readerImageFileName(index, sourcePath, this.currentImageShareTarget())];
    const documentPicker = new picker.DocumentViewPicker(context);
    const uris = await documentPicker.save(options);
    if (uris.length === 0) {
      return;
    }
    try {
      copyFileContent(sourcePath, uris[0]);
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
      if (relY < 1.0 / 3.0) {
        this.previousReaderPage();
      } else if (relY > 2.0 / 3.0) {
        this.nextReaderPage();
      } else if (relX < 1.0 / 3.0 || relX > 2.0 / 3.0) {
        this.showSlider();
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

  private clampReaderPageIndex(value: number): number {
    const total = this.totalPages <= 0 ? 1 : this.totalPages;
    return Math.max(0, Math.min(total - 1, Math.round(value)));
  }

  private sliderBubbleX(): number {
    const total = this.totalPages <= 0 ? 1 : this.totalPages;
    // ArkUI Slider default blockSize=16vp, so thumb travels [8, trackWidth-8].
    const blockRadius = 8;
    const usableWidth = Math.max(1, this.sliderTrackWidth - 2 * blockRadius);
    if (total <= 1) {
      return blockRadius;
    }
    return blockRadius + Math.max(0, Math.min(usableWidth, usableWidth * this.sliderLiveIndex / (total - 1)));
  }

  private sliderPageText(): string {
    return (this.sliderLiveIndex + 1).toString();
  }

  private jumpTo(value: number): void {
    if (this.totalPages <= 0) {
      return;
    }
    const target = Math.max(0, Math.min(this.totalPages - 1, Math.round(value)));
    this.sliderLiveIndex = target;
    if (target === this.currentIndex) {
      return;
    }
    this.resetActiveImageSize();
    this.currentIndex = target;
    this.isDisableSwipe = false;
    this.zoomPercent = this.isFixedScaleMode() ? Math.round(this.fixedScale * 100) : 100;
    this.imageActionsVisible = false;
    if (this.autoTransferPlaying) {
      this.scheduleAutoTransfer();
    }
    try {
      this.swiperController.changeIndex(this.visualIndexForPageIndex(target), true);
    } catch (e) {}
    this.onJump(target);
  }

  private previousReaderPage(): void {
    if (this.swiperVertical) {
      this.scrollVerticalReaderByPage(-1);
      return;
    }
    this.jumpTo(this.currentIndex - 1);
  }

  private nextReaderPage(): void {
    if (this.swiperVertical) {
      this.scrollVerticalReaderByPage(1);
      return;
    }
    this.jumpTo(this.currentIndex + 1);
  }

  private verticalPageScrollDistance(): number {
    return Math.max(1, this.readerLayoutHeight * 0.8);
  }

  private scrollVerticalReaderByPage(direction: number): void {
    if (direction === 0) {
      return;
    }
    this.continuousScroller.scrollBy(0, this.verticalPageScrollDistance() * direction);
  }

  private onSwiperChange(visualIndex: number): void {
    const index = this.pageIndexForVisualIndex(visualIndex);
    if (index === this.currentIndex) {
      return;
    }
    this.resetActiveImageSize();
    this.currentIndex = index;
    this.isDisableSwipe = false;
    this.zoomPercent = this.isFixedScaleMode() ? Math.round(this.fixedScale * 100) : 100;
    this.imageActionsVisible = false;
    if (this.autoTransferPlaying) {
      this.scheduleAutoTransfer();
    }
    this.onJump(index);
  }

  private onContinuousScrollIndex(index: number): void {
    const pageIndex = this.pageIndexForVisualIndex(index);
    if (pageIndex === this.currentIndex) {
      return;
    }
    this.currentIndex = pageIndex;
    this.sliderLiveIndex = pageIndex;
    this.onJump(pageIndex);
  }

  private resetActiveImageSize(): void {
    this.activeImageWidth = 0;
    this.activeImageHeight = 0;
  }

  private clampContinuousOffsetX(value: number, maxOffsetX: number): number {
    const maxX = Math.max(0, maxOffsetX);
    return Math.max(-maxX, Math.min(maxX, value));
  }

  private onContinuousHorizontalBoundsChange(maxOffsetX: number): void {
    const clamped = this.clampContinuousOffsetX(this.continuousOffsetX, maxOffsetX);
    if (Math.abs(clamped - this.continuousOffsetX) > 0.5) {
      this.continuousOffsetX = clamped;
    }
  }

  private onContinuousHorizontalDragStart(maxOffsetX: number): void {
    this.continuousDragStartOffsetX = this.clampContinuousOffsetX(this.continuousOffsetX, maxOffsetX);
    this.continuousOffsetX = this.continuousDragStartOffsetX;
  }

  private onContinuousHorizontalDragUpdate(offsetX: number, maxOffsetX: number): void {
    this.continuousOffsetX = this.clampContinuousOffsetX(this.continuousDragStartOffsetX + offsetX, maxOffsetX);
  }

  private onContinuousHorizontalDragEnd(velocityX: number, maxOffsetX: number): void {
    const inertiaX = Math.abs(velocityX) > 20 ? Math.max(-180, Math.min(180, velocityX * 0.12)) : 0;
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.continuousOffsetX = this.clampContinuousOffsetX(this.continuousOffsetX + inertiaX, maxOffsetX);
    });
    this.continuousDragStartOffsetX = this.continuousOffsetX;
  }

  private onActiveImageSizeChange(width: number, height: number): void {
    this.activeImageWidth = width > 0 ? width : 0;
    this.activeImageHeight = height > 0 ? height : 0;
    if (readerScreenRotationSetting() === 'Match image') {
      this.applyReaderWindowSettings();
    }
  }

  private progressText(): string {
    const total = this.totalPages <= 0 ? 1 : this.totalPages;
    return (this.currentIndex + 1).toString() + '/' + total.toString();
  }

  private tapLocalX(event: GestureEvent): number {
    if (event.fingerList.length > 0) {
      return event.fingerList[0].localX;
    }
    return this.readerLayoutWidth / 2;
  }

  private tapLocalY(event: GestureEvent): number {
    if (event.fingerList.length > 0) {
      return event.fingerList[0].localY;
    }
    return this.readerLayoutHeight / 2;
  }

  private onReaderScreenTap(event: GestureEvent): void {
    if (this.screenTapTimer !== -1) {
      this.clearScreenTapTimer();
      return;
    }
    const tapX = this.tapLocalX(event);
    const tapY = this.tapLocalY(event);
    const width = Math.max(1, this.readerLayoutWidth);
    const height = Math.max(1, this.readerLayoutHeight);
    this.screenTapTimer = setTimeout(() => {
      this.screenTapTimer = -1;
      this.onTap(tapX, tapY, width, height);
    }, READER_SCREEN_TAP_DELAY) as number;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isContinuousVerticalMode()) {
        List({ space: 0, scroller: this.continuousScroller }) {
          LazyForEach(this.readerPageIndexSource(), (index: number) => {
            ListItem() {
              ReaderContinuousImageItem({
                page: this.pageForIndex(index),
                statusText: index === this.pageIndex ? this.statusText : uiText('Image page is loading'),
                preferOriginal: this.preferOriginal,
                fitMode: this.fitMode,
                zoomScale: this.fixedScale,
                sharedOffsetX: this.continuousOffsetX,
                isActive: index === this.currentIndex,
                onTap: () => {},
                onRetry: () => {
                  this.onJump(index);
                },
                onImageLongPress: () => {
                  this.currentIndex = index;
                  this.showImageActions();
                },
                onImageSizeChange: (width: number, height: number) => {
                  if (index === this.currentIndex) {
                    this.onActiveImageSizeChange(width, height);
                  }
                },
                onZoomChange: (percent: number) => {
                  this.zoomPercent = percent;
                  this.fixedScale = Math.max(READER_MIN_SCALE, Math.min(READER_MAX_SCALE, percent / 100));
                },
                onHorizontalBoundsChange: (maxOffsetX: number) => {
                  if (index === this.currentIndex) {
                    this.onContinuousHorizontalBoundsChange(maxOffsetX);
                  }
                },
                onHorizontalDragStart: (maxOffsetX: number) => {
                  if (index === this.currentIndex) {
                    this.onContinuousHorizontalDragStart(maxOffsetX);
                  }
                },
                onHorizontalDragUpdate: (offsetX: number, maxOffsetX: number) => {
                  if (index === this.currentIndex) {
                    this.onContinuousHorizontalDragUpdate(offsetX, maxOffsetX);
                  }
                },
                onHorizontalDragEnd: (velocityX: number, maxOffsetX: number) => {
                  if (index === this.currentIndex) {
                    this.onContinuousHorizontalDragEnd(velocityX, maxOffsetX);
                  }
                }
              })
                .width('100%')
            }
            .reuseId('reader-continuous-page')
          }, (index: number) => index.toString())
        }
        .width('100%')
        .height('100%')
        .backgroundColor(readerBackgroundColor())
        .scrollBar(BarState.Off)
        .cachedCount(this.readerRenderCacheCount() + 2)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .onScrollIndex((first: number) => {
          this.onContinuousScrollIndex(first);
        })
      } else {
        Swiper(this.swiperController) {
          LazyForEach(this.readerPageIndexSource(), (index: number) => {
            ReaderImageViewport({
              page: this.pageForIndex(index),
              statusText: index === this.pageIndex ? this.statusText : uiText('Image page is loading'),
              preferOriginal: this.preferOriginal,
              fitMode: this.fitMode,
              fixedScale: this.fixedScale,
              startPosition: this.startPosition,
              isActive: index === this.currentIndex,
              allowEdgeSwipe: !this.swiperVertical,
              command: this.viewportCommand,
              commandVersion: this.viewportCommandVersion,
              onTap: () => {},
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
                  if (this.isFixedScaleMode()) {
                    this.fixedScale = Math.max(READER_MIN_SCALE, Math.min(READER_MAX_SCALE, percent / 100));
                  }
                }
              },
              onImageSizeChange: (width: number, height: number) => {
                if (index === this.currentIndex) {
                  this.onActiveImageSizeChange(width, height);
                }
              },
              onEdgeSwipe: (direction: number) => {
                if (index === this.currentIndex) {
                  this.jumpByVisualDirection(direction);
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
        .vertical(false)
        .displayCount(1)
        .itemSpace(0)
        .prevMargin(0)
        .nextMargin(0)
        .duration(180)
        .curve(Curve.EaseOut)
        .effectMode(EdgeEffect.None)
        .disableSwipe(this.isDisableSwipe)
        .onChange((index: number) => {
          this.onSwiperChange(index);
        })
        .width('100%')
        .height('100%')
        .backgroundColor(readerBackgroundColor())
      }

      if (this.menuUltraDarkMode) {
        Stack() {}
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)
          .opacity(this.ultraDarkOverlayOpacity())
          .hitTestBehavior(HitTestMode.Transparent)
          .zIndex(2)
      }

      Stack() {}
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Transparent)
        .gesture(
          TapGesture({ count: 1 })
            .onAction((event: GestureEvent) => {
              this.onReaderScreenTap(event);
            })
        )
        .zIndex(3)

      if (!this.menuVisible) {
        Stack({ alignContent: Alignment.TopEnd }) {
          ReaderInfoOverlay({
            showProgress: this.overlayShowProgress,
            showClock: this.overlayShowClock,
            showBattery: this.overlayShowBattery,
            progressText: this.progressText(),
            clockText: this.clockText,
            batteryText: this.batteryText(),
            top: this.readerStatusOverlayTop(),
            right: this.readerStatusOverlayRight()
          })
            .margin({ top: this.readerStatusOverlayTop(), right: this.readerStatusOverlayRight() })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(4)
      }
      if (this.sliderVisible) {
        ReaderSliderPanel({
          progressText: this.progressText(),
          sliderDragging: this.sliderDragging,
          sliderPageText: this.sliderPageText(),
          sliderBubbleX: this.sliderBubbleX(),
          sliderTrackWidth: this.sliderTrackWidth,
          sliderLiveIndex: this.sliderLiveIndex,
          totalPages: this.totalPages,
          bottomInset: this.readerBottomInset(),
          autoTransferPlaying: this.autoTransferPlaying,
          autoTransferEnabled: this.autoTransferDelayMs() > 0 && this.canGoNext(),
          onDismiss: () => {
            this.hideSliderAndStopPlayback();
          },
          onSliderChange: (value: number, mode: SliderChangeMode) => {
            this.clearSliderTimer();
            this.sliderLiveIndex = this.clampReaderPageIndex(value);
            this.sliderDragging = mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving;
            if (mode === SliderChangeMode.End) {
              this.stopAutoTransferPlayback();
              this.jumpTo(value);
              this.scheduleSliderHide();
            } else if (mode === SliderChangeMode.Click) {
              this.stopAutoTransferPlayback();
              this.jumpTo(value);
              this.scheduleSliderHide();
            }
          },
          onTrackWidthChange: (width: number) => {
            this.sliderTrackWidth = width;
          },
          onToggleAutoTransfer: () => {
            this.toggleAutoTransferPlayback();
          }
        })
          .zIndex(5)
      }
      if (this.imageActionsVisible) {
        ReaderImageActionsOverlay({
          onDismiss: () => {
            this.hideImageActions();
          },
          onRefresh: () => {
            this.refreshCurrentImage();
          },
          onShare: () => {
            this.shareCurrentImage();
          },
          onSaveToAlbum: (result: SaveButtonOnClickResult) => {
            if (result === SaveButtonOnClickResult.SUCCESS) {
              this.saveCurrentImageToAlbum();
            } else {
              this.showToast(uiText('Save failed'));
            }
          },
          onSave: () => {
            this.saveCurrentImageToPicker();
          }
        })
          .zIndex(6)
      }
      if (this.menuVisible) {
        ReaderSettingsMenuOverlay({
          statusText: this.statusText,
          menuShowClock: this.menuShowClock,
          menuShowProgress: this.menuShowProgress,
          progressText: this.progressText(),
          menuScreenRotation: this.menuScreenRotation,
          menuReadingDirection: this.menuReadingDirection,
          menuPageScaling: this.menuPageScaling,
          menuStartPosition: this.menuStartPosition,
          menuAutoTransferTime: this.menuAutoTransferTime,
          menuKeepScreenOn: this.menuKeepScreenOn,
          menuShowBattery: this.menuShowBattery,
          batteryText: this.batteryText(),
          menuReadingFullscreen: this.menuReadingFullscreen,
          menuVolumePage: this.menuVolumePage,
          menuCustomBrightness: this.menuCustomBrightness,
          menuBrightnessLevel: this.menuBrightnessLevel,
          menuUltraDarkMode: this.menuUltraDarkMode,
          menuUltraDarkBrightness: this.menuUltraDarkBrightness,
          screenRotationOptions: this.readerMenuScreenRotationOptions(),
          pageScalingOptions: this.readerMenuPageScalingOptions(),
          onDismiss: () => {
            this.hideMenu();
          },
          onBack: () => {
            this.onBack();
          },
          onScreenRotationChange: (value: string) => {
            this.menuScreenRotation = value;
          },
          onReadingDirectionChange: (value: string) => {
            this.onMenuReadingDirectionChange(value);
          },
          onPageScalingChange: (value: string) => {
            this.menuPageScaling = value;
          },
          onStartPositionChange: (value: string) => {
            this.menuStartPosition = value;
          },
          onAutoTransferTimeChange: (value: string) => {
            this.menuAutoTransferTime = value;
          },
          onKeepScreenOnChange: (value: boolean) => {
            this.menuKeepScreenOn = value;
          },
          onShowClockChange: (value: boolean) => {
            this.menuShowClock = value;
          },
          onShowProgressChange: (value: boolean) => {
            this.menuShowProgress = value;
          },
          onShowBatteryChange: (value: boolean) => {
            this.menuShowBattery = value;
          },
          onReadingFullscreenChange: (value: boolean) => {
            this.menuReadingFullscreen = value;
          },
          onVolumePageChange: (value: boolean) => {
            this.menuVolumePage = value;
          },
          onCustomBrightnessChange: (value: boolean) => {
            this.menuCustomBrightness = value;
            this.applyBrightness().catch(() => {});
          },
          onBrightnessLevelChange: (value: string) => {
            this.menuBrightnessLevel = value;
            this.applyBrightness().catch(() => {});
          },
          onUltraDarkModeChange: (value: boolean) => {
            this.menuUltraDarkMode = value;
            this.applyBrightness().catch(() => {});
          },
          onUltraDarkBrightnessChange: (value: string) => {
            this.menuUltraDarkBrightness = value;
          }
        })
          .zIndex(6)
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width = newArea.width as number;
      if (width > 0 && !Number.isNaN(width)) {
        this.readerLayoutWidth = width;
      }
      const height = newArea.height as number;
      if (height > 0 && !Number.isNaN(height)) {
        this.readerLayoutHeight = height;
      }
    })
    .backgroundColor(readerBackgroundColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private jumpByVisualDirection(direction: number): void {
    if (direction === 0 || this.totalPages <= 0) {
      return;
    }
    const visualIndex = this.visualIndexForPageIndex(this.currentIndex);
    const targetVisualIndex = visualIndex + (direction < 0 ? 1 : -1);
    this.jumpTo(this.pageIndexForVisualIndex(targetVisualIndex));
  }
}
