import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { batteryInfo } from '@kit.BasicServicesKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import inputConsumer from '@ohos.multimodalInput.inputConsumer';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { KeyEvent } from '@ohos.multimodalInput.keyEvent';
import { GalleryPage, GalleryPreview } from '../model/GalleryModels';
import { ReaderPageTranslation } from '../model/ReaderTranslationModels';
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
  restoreAppWindowState,
  setEmbeddedReaderActive
} from '../services/EhWindowImmersive';
import { READER_TRANSLATION_BUTTON_VISIBLE_KEY, ehSettingsStore } from '../services/EhSettingsStore';
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
const READER_DUAL_PAGE_OVERFLOW_RATIO: number = 1.15;
const READER_PAGE_GROUP_REFRESH_DELAY: number = 220;
const READER_TRANSLATION_BUTTON_SIZE: number = 52;
const READER_TRANSLATION_BUTTON_EDGE: number = 8;

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

interface ReaderPageImageSize {
  index: number;
  width: number;
  height: number;
}

interface ReaderPageGroupItem {
  index: number;
  key: string;
}

@Component
export struct ReaderScene {
  @Prop @Watch('onRenderVersionChange') renderVersion: number = 0;
  @Prop page: GalleryPage = createEmptyPage();
  @Prop readerPages: ReaderPageState[] = [];
  @Prop @Watch('onReaderPreviewsChange') readerPreviews: GalleryPreview[] = [];
  @Prop @Watch('onGalleryIdChange') galleryId: number = 0;
  @Prop statusText: string = '';
  @Prop @Watch('onPageIndexChange') pageIndex: number = 0;
  @Prop @Watch('onTotalPagesChange') totalPages: number = 0;
  @Prop readerTranslations: ReaderPageTranslation[] = [];
  @Prop comicTranslationActive: boolean = false;
  @Prop comicTranslationNotice: string = '';
  @Prop @Watch('onComicTranslationNoticeChange') comicTranslationNoticeRevision: number = 0;
  onBack: () => void = () => {};
  onPrev: () => void = () => {};
  onNext: () => void = () => {};
  onJump: (index: number) => void = () => {};
  onRetry: () => void = () => {};
  onRefreshPage: (index: number) => void = () => {};
  onAdaptiveDualPageChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onComicTranslationToggle: (enabled: boolean) => void = (_enabled: boolean) => {};
  onComicTranslationRefresh: () => void = () => {};
  restoreAppChromeOnExit: boolean = true;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  @StorageProp(BOTTOM_AVOID_HEIGHT_KEY) bottomAvoidHeight: number = 0;
  @StorageProp(READER_TRANSLATION_BUTTON_VISIBLE_KEY) comicTranslationButtonVisible: boolean = false;

  @State fitMode: string = 'Fit screen';
  @State adaptiveDualPage: boolean = false;
  @State startPosition: string = 'Top right';
  @State showInfo: boolean = false;
  @State preferOriginal: boolean = false;
  @State menuVisible: boolean = false;
  @State imageActionsVisible: boolean = false;
  @State imageActionPageIndex: number = 0;
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
  @State comicTranslationButtonX: number = 0;
  @State comicTranslationButtonY: number = 160;
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
  private readerPageIndexesSource: ArrayDataSource<ReaderPageGroupItem> =
    new ArrayDataSource<ReaderPageGroupItem>([]);
  private readerPageIndexesCount: number = -1;
  private readerPageIndexesReversed: boolean = false;
  private readerPageIndexesSignature: string = '';
  private readerPageGroupRevision: number = 0;
  private readerPageImageSizes: ReaderPageImageSize[] = [];
  private readerImageSizeGalleryId: number = -1;
  private pageGroupRefreshTimer: number = -1;
  private pageGroupRefreshPending: boolean = false;
  private swiperAnimating: boolean = false;
  private continuousScroller: Scroller = new Scroller();
  private activeImageWidth: number = 0;
  private activeImageHeight: number = 0;
  private continuousDragStartOffsetX: number = 0;
  private comicTranslationDragStartX: number = 0;
  private comicTranslationDragStartY: number = 0;
  private comicTranslationLongPressHandled: boolean = false;

  // Menu settings state (reflects ehSettingsStore, applied on menu close)
  @State menuScreenRotation: string = 'Default';
  @State menuReadingDirection: string = 'Right to left';
  @State menuPageScaling: string = 'Fit screen';
  @State menuAdaptiveDualPage: boolean = false;
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
  private readerWindowSettingsRevision: number = 0;
  private readerWindowSettingsTimer: number = -1;
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
    this.adaptiveDualPage = ehSettingsStore.getValue('adaptive_dual_page', 'Off') === 'On';
    this.resetReaderImageSizesForGallery();
    this.syncReaderPreviewImageSizes();
    this.currentIndex = this.pageGroupAnchorForPageIndex(this.pageIndex);
    this.syncReaderPageIndexSource();
    if (this.restoreAppChromeOnExit) {
      setEmbeddedReaderActive(true);
    }
    this.fitMode = normalizePageScalingOption(ehSettingsStore.getValue('page_scaling', 'Fit screen'));
    this.startPosition = normalizeStartPositionOption(ehSettingsStore.getValue('start_position', 'Top right'));
    this.menuVisible = false;
    this.imageActionsVisible = false;
    this.sliderVisible = false;
    this.imageActionPageIndex = this.currentIndex;
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
      this.restoreAppWindowStateForReaderExit();
      this.restoreSystemBarsForReaderExit();
    }
    if (this.restoreAppChromeOnExit && isEmbeddedReaderActive()) {
      this.scheduleTransientDisappearCleanup();
      return;
    }
    this.cleanupReaderScene();
  }

  private restoreAppWindowStateForReaderExit(): void {
    const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (hostContext === undefined) {
      if (this.hostReaderWindow !== undefined) {
        restoreAppWindowState(this.hostReaderWindow).catch(() => {});
      }
      return;
    }
    window.getLastWindow(hostContext).then((win: window.Window) => {
      restoreAppWindowState(win).catch(() => {});
    }).catch(() => {
      if (this.hostReaderWindow !== undefined) {
        restoreAppWindowState(this.hostReaderWindow).catch(() => {});
      }
    });
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
    this.readerWindowSettingsRevision++;
    if (this.readerWindowSettingsTimer !== -1) {
      clearTimeout(this.readerWindowSettingsTimer);
      this.readerWindowSettingsTimer = -1;
    }
    this.clearPageGroupRefreshTimer();
    this.pageGroupRefreshPending = false;
    this.swiperAnimating = false;
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
    const revision = ++this.readerWindowSettingsRevision;
    if (this.readerWindowSettingsTimer !== -1) {
      clearTimeout(this.readerWindowSettingsTimer);
    }
    this.readerWindowSettingsTimer = setTimeout(() => {
      this.readerWindowSettingsTimer = -1;
      if (!this.readerWindowActive || revision !== this.readerWindowSettingsRevision) {
        return;
      }
      this.applyReaderWindowSettingsAsync(keepOn, orientation, fullscreen, revision).catch(() => {});
    }, 16) as number;
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

  private async applyReaderWindowSettingsAsync(keepOn: boolean, orientation: string, fullscreen: boolean,
    revision: number): Promise<void> {
    await this.applyReaderWindowSettingsOnce(keepOn, orientation, fullscreen);
    if (revision !== this.readerWindowSettingsRevision) {
      return;
    }
    this.scheduleReaderChromeMode(80, revision);
    this.scheduleReaderChromeMode(260, revision);
    this.scheduleReaderChromeMode(620, revision);
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

  onGalleryIdChange(): void {
    if (!this.resetReaderImageSizesForGallery()) {
      return;
    }
    this.syncReaderPreviewImageSizes();
    this.currentIndex = this.pageGroupAnchorForPageIndex(this.pageIndex);
    this.sliderLiveIndex = this.clampReaderPageIndex(this.currentIndex);
    this.readerPageIndexesCount = -1;
    if (this.readerWindowActive) {
      this.syncReaderPageIndexSource();
    }
  }

  onReaderPreviewsChange(): void {
    if (this.syncReaderPreviewImageSizes()) {
      this.schedulePageGroupRefresh();
    }
  }

  onTotalPagesChange(): void {
    this.currentIndex = this.pageGroupAnchorForPageIndex(this.currentIndex);
    this.sliderLiveIndex = this.clampReaderPageIndex(this.currentIndex);
    this.syncReaderPageIndexSource();
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

  private scheduleReaderChromeMode(delay: number, revision: number): void {
    setTimeout(() => {
      if (!this.readerWindowActive || revision !== this.readerWindowSettingsRevision) {
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
    this.currentIndex = this.pageGroupAnchorForPageIndex(this.pageIndex);
    this.sliderLiveIndex = this.clampReaderPageIndex(this.currentIndex);
    this.sliderDragging = false;
    this.isDisableSwipe = false;
    this.zoomPercent = this.isFixedScaleMode() ? Math.round(this.fixedScale * 100) : 100;
    this.imageActionsVisible = false;
    this.scheduleAutoTransfer();
    this.syncReaderPageIndexSource();
    try {
      this.swiperController.changeIndex(this.visualIndexForPageIndex(this.currentIndex), false);
    } catch (e) {}
  }

  private pageGroupIndexesAscending(): number[] {
    const count = this.totalPages <= 0 ? 1 : this.totalPages;
    const requestedPage = Math.max(0, Math.min(count - 1, this.pageIndex));
    const pages: number[] = [];
    let index = 0;
    while (index < count) {
      pages.push(index);
      const wouldConsumeRequestedPage = index + 1 === requestedPage;
      index += !wouldConsumeRequestedPage && this.shouldPairPage(index) ? 2 : 1;
    }
    return pages;
  }

  private pageIndexes(): number[] {
    const pages = this.pageGroupIndexesAscending();
    return this.swiperReversed ? pages.reverse() : pages;
  }

  private pageImageSize(index: number): ReaderPageImageSize | null {
    for (let i = 0; i < this.readerPageImageSizes.length; i++) {
      if (this.readerPageImageSizes[i].index === index) {
        return this.readerPageImageSizes[i];
      }
    }
    return null;
  }

  private resetReaderImageSizesForGallery(): boolean {
    if (this.readerImageSizeGalleryId === this.galleryId) {
      return false;
    }
    this.clearPageGroupRefreshTimer();
    this.pageGroupRefreshPending = false;
    this.readerPageImageSizes = [];
    this.readerImageSizeGalleryId = this.galleryId;
    return true;
  }

  private syncReaderPreviewImageSizes(): boolean {
    let changed = false;
    for (let i = 0; i < this.readerPreviews.length; i++) {
      const preview = this.readerPreviews[i];
      if (preview.index < 0 || preview.width <= 0 || preview.height <= 0 ||
        this.pageImageSize(preview.index) !== null) {
        continue;
      }
      this.readerPageImageSizes.push({
        index: preview.index,
        width: preview.width,
        height: preview.height
      });
      changed = true;
    }
    return changed;
  }

  private rememberPageImageSize(index: number, width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    for (let i = 0; i < this.readerPageImageSizes.length; i++) {
      if (this.readerPageImageSizes[i].index === index) {
        if (this.readerPageImageSizes[i].width === width && this.readerPageImageSizes[i].height === height) {
          return;
        }
        this.readerPageImageSizes[i].width = width;
        this.readerPageImageSizes[i].height = height;
        this.schedulePageGroupRefresh();
        return;
      }
    }
    this.readerPageImageSizes.push({ index: index, width: width, height: height });
    this.schedulePageGroupRefresh();
  }

  private clearPageGroupRefreshTimer(): void {
    if (this.pageGroupRefreshTimer !== -1) {
      clearTimeout(this.pageGroupRefreshTimer);
      this.pageGroupRefreshTimer = -1;
    }
  }

  private schedulePageGroupRefresh(delay: number = READER_PAGE_GROUP_REFRESH_DELAY): void {
    this.pageGroupRefreshPending = true;
    if (this.pageGroupRefreshTimer !== -1) {
      return;
    }
    this.pageGroupRefreshTimer = setTimeout(() => {
      this.pageGroupRefreshTimer = -1;
      if (!this.readerWindowActive) {
        this.pageGroupRefreshPending = false;
        return;
      }
      if (this.swiperAnimating) {
        this.schedulePageGroupRefresh(60);
        return;
      }
      this.pageGroupRefreshPending = false;
      this.normalizeCurrentPageGroup();
      this.syncReaderPageIndexSource();
    }, Math.max(0, delay)) as number;
  }

  private shouldPairPage(index: number): boolean {
    const count = this.totalPages <= 0 ? 1 : this.totalPages;
    if (!this.adaptiveDualPage || this.swiperVertical || normalizePageScalingOption(this.fitMode) !== 'Fit screen' ||
      index < 0 || index + 1 >= count || this.readerLayoutWidth <= 0 || this.readerLayoutHeight <= 0) {
      return false;
    }
    const first = this.pageImageSize(index);
    const second = this.pageImageSize(index + 1);
    if (first === null || second === null) {
      return false;
    }
    if (this.readerLayoutHeight >= this.readerLayoutWidth) {
      if (first.width <= first.height || second.width <= second.height) {
        return false;
      }
      const combinedHeight = this.readerLayoutWidth * first.height / first.width +
        this.readerLayoutWidth * second.height / second.width;
      return combinedHeight <= this.readerLayoutHeight * READER_DUAL_PAGE_OVERFLOW_RATIO + 1;
    }
    if (first.height <= first.width || second.height <= second.width) {
      return false;
    }
    const combinedWidth = this.readerLayoutHeight * first.width / first.height +
      this.readerLayoutHeight * second.width / second.height;
    return combinedWidth <= this.readerLayoutWidth * READER_DUAL_PAGE_OVERFLOW_RATIO + 1;
  }

  private pageGroupAnchorForPageIndex(index: number): number {
    const count = this.totalPages <= 0 ? 1 : this.totalPages;
    const target = Math.max(0, Math.min(count - 1, index));
    const groups = this.pageGroupIndexesAscending();
    let result = 0;
    for (let i = 0; i < groups.length; i++) {
      if (groups[i] > target) {
        break;
      }
      result = groups[i];
    }
    return result;
  }

  private normalizeCurrentPageGroup(): void {
    const anchor = this.pageGroupAnchorForPageIndex(this.currentIndex);
    if (anchor === this.currentIndex) {
      return;
    }
    this.currentIndex = anchor;
    this.sliderLiveIndex = anchor;
    this.imageActionPageIndex = anchor;
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

  private readerPageIndexSource(): ArrayDataSource<ReaderPageGroupItem> {
    this.syncReaderPageIndexSource();
    return this.readerPageIndexesSource;
  }

  private readerRenderCacheCount(): number {
    return READER_OFFSCREEN_RENDER_COUNT;
  }

  private syncReaderPageIndexSource(): void {
    const count = this.totalPages <= 0 ? 1 : this.totalPages;
    const pages = this.pageIndexes();
    const signature = pages.join(',');
    if (count === this.readerPageIndexesCount && this.readerPageIndexesReversed === this.swiperReversed &&
      signature === this.readerPageIndexesSignature) {
      return;
    }
    this.readerPageIndexesCount = count;
    this.readerPageIndexesReversed = this.swiperReversed;
    this.readerPageIndexesSignature = signature;
    this.readerPageGroupRevision++;
    const items: ReaderPageGroupItem[] = [];
    for (let i = 0; i < pages.length; i++) {
      items.push({ index: pages[i], key: this.readerPageGroupRevision.toString() + ':' + pages[i].toString() });
    }
    this.readerPageIndexesSource.setItems(items);
  }

  private visualIndexForPageIndex(index: number): number {
    const pages = this.pageIndexes();
    const anchor = this.pageGroupAnchorForPageIndex(index);
    const visualIndex = pages.indexOf(anchor);
    return visualIndex < 0 ? 0 : visualIndex;
  }

  private pageIndexForVisualIndex(index: number): number {
    const pages = this.pageIndexes();
    const visualIndex = Math.max(0, Math.min(pages.length - 1, index));
    return pages.length > 0 ? pages[visualIndex] : 0;
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
    this.menuAdaptiveDualPage = ehSettingsStore.getValue('adaptive_dual_page', 'Off') === 'On';
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
    this.applyAdaptiveDualPageMenuConstraints();
    const previousAdaptiveDualPage = this.adaptiveDualPage;
    ehSettingsStore.setValue('adaptive_dual_page', this.menuAdaptiveDualPage ? 'On' : 'Off');
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
    this.adaptiveDualPage = this.menuAdaptiveDualPage;
    if (previousAdaptiveDualPage !== this.adaptiveDualPage) {
      this.onAdaptiveDualPageChange(this.adaptiveDualPage);
    }
    this.startPosition = normalizeStartPositionOption(this.menuStartPosition);
    this.currentIndex = this.pageGroupAnchorForPageIndex(this.currentIndex);
    this.syncReaderPageIndexSource();
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
    if (this.menuReadingDirection === 'Top to bottom' || this.menuAdaptiveDualPage) {
      return ['Default', 'Portrait', 'Landscape', 'Auto rotate'];
    }
    return ['Default', 'Portrait', 'Landscape', 'Auto rotate', 'Match image'];
  }

  private readerMenuPageScalingOptions(): string[] {
    if (this.menuAdaptiveDualPage) {
      return ['Fit screen'];
    }
    if (this.menuReadingDirection === 'Top to bottom') {
      return ['Actual size', 'Fit width', 'Fixed scale'];
    }
    return ['Actual size', 'Fit width', 'Fit height', 'Fit screen', 'Fixed scale'];
  }

  private readerMenuReadingDirectionOptions(): string[] {
    return this.menuAdaptiveDualPage ? ['Left to right', 'Right to left'] :
      ['Left to right', 'Right to left', 'Top to bottom'];
  }

  private applyAdaptiveDualPageMenuConstraints(): void {
    if (!this.menuAdaptiveDualPage) {
      return;
    }
    if (this.menuReadingDirection === 'Top to bottom') {
      this.menuReadingDirection = 'Right to left';
    }
    if (this.menuScreenRotation === 'Match image') {
      this.menuScreenRotation = 'Default';
    }
    this.menuPageScaling = 'Fit screen';
  }

  private onMenuAdaptiveDualPageChange(value: boolean): void {
    this.menuAdaptiveDualPage = value;
    this.applyAdaptiveDualPageMenuConstraints();
  }

  private onMenuReadingDirectionChange(value: string): void {
    if (this.menuAdaptiveDualPage && value === 'Top to bottom') {
      return;
    }
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
      this.jumpToAdjacentPageGroup(1);
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

  private showImageActions(index: number = this.currentIndex): void {
    if (readerDisplayImageUrl(this.pageForIndex(index), this.preferOriginal).length === 0) {
      return;
    }
    this.imageActionPageIndex = index;
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
    const page = this.pageForIndex(this.imageActionPageIndex);
    const index = this.imageActionPageIndex;
    this.hideImageActions();
    this.removeCurrentImageFiles(page);
    this.onRefreshPage(index);
  }

  private shareCurrentImage(): void {
    const page = this.pageForIndex(this.imageActionPageIndex);
    const index = this.imageActionPageIndex;
    this.hideImageActions();
    this.shareCurrentImageAsync(page, index).catch(() => {});
  }

  private saveCurrentImageToAlbum(): void {
    const page = this.pageForIndex(this.imageActionPageIndex);
    const index = this.imageActionPageIndex;
    this.saveReaderImageToAlbumAsync(page, index).catch(() => {});
  }

  private saveCurrentImageToPicker(): void {
    const page = this.pageForIndex(this.imageActionPageIndex);
    const index = this.imageActionPageIndex;
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
      // @SuppressWarnings permission
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
    const page = this.pageForIndex(this.imageActionPageIndex);
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
      return usableReaderLocalPath(stripFileScheme(page.cachedOriginImagePath));
    }
    if (!this.preferOriginal && page.cachedImagePath !== undefined && page.cachedImagePath.length > 0) {
      return usableReaderLocalPath(stripFileScheme(page.cachedImagePath));
    }
    if (page.cachedImagePath !== undefined && page.cachedImagePath.length > 0) {
      return usableReaderLocalPath(stripFileScheme(page.cachedImagePath));
    }
    if (page.cachedOriginImagePath !== undefined && page.cachedOriginImagePath.length > 0) {
      return usableReaderLocalPath(stripFileScheme(page.cachedOriginImagePath));
    }
    return '';
  }

  onComicTranslationNoticeChange(): void {
    if (this.comicTranslationNoticeRevision <= 0 || this.comicTranslationNotice.length === 0) {
      return;
    }
    const failurePrefix = 'Comic translation failed:';
    if (this.comicTranslationNotice.indexOf(failurePrefix) === 0) {
      this.showToast(uiText('Comic translation failed') + this.comicTranslationNotice.substring(failurePrefix.length));
      return;
    }
    this.showToast(uiText(this.comicTranslationNotice));
  }

  private readerTranslationForPage(index: number): ReaderPageTranslation | null {
    if (!this.comicTranslationActive) {
      return null;
    }
    for (let i = 0; i < this.readerTranslations.length; i++) {
      if (this.readerTranslations[i].pageIndex === index) {
        return this.readerTranslations[i];
      }
    }
    return null;
  }

  private comicTranslationButtonMinY(): number {
    return Math.max(READER_TRANSLATION_BUTTON_EDGE, this.readerStatusOverlayTop());
  }

  private comicTranslationButtonMaxY(): number {
    return Math.max(this.comicTranslationButtonMinY(), this.readerLayoutHeight - READER_TRANSLATION_BUTTON_SIZE -
      this.readerBottomInset() - READER_TRANSLATION_BUTTON_EDGE);
  }

  private clampComicTranslationButtonX(value: number): number {
    return Math.max(READER_TRANSLATION_BUTTON_EDGE,
      Math.min(Math.max(READER_TRANSLATION_BUTTON_EDGE,
        this.readerLayoutWidth - READER_TRANSLATION_BUTTON_SIZE - READER_TRANSLATION_BUTTON_EDGE), value));
  }

  private clampComicTranslationButtonY(value: number): number {
    return Math.max(this.comicTranslationButtonMinY(), Math.min(this.comicTranslationButtonMaxY(), value));
  }

  private syncComicTranslationButtonPosition(): void {
    if (this.readerLayoutWidth <= 0 || this.readerLayoutHeight <= 0) {
      return;
    }
    const side = ehSettingsStore.getValue('reader_translation_button_side', 'Right');
    const ratio = Number.parseFloat(ehSettingsStore.getValue('reader_translation_button_y_ratio', '0.35'));
    const safeRatio = Number.isNaN(ratio) ? 0.35 : Math.max(0, Math.min(1, ratio));
    this.comicTranslationButtonX = side === 'Left' ? READER_TRANSLATION_BUTTON_EDGE :
      this.readerLayoutWidth - READER_TRANSLATION_BUTTON_SIZE - READER_TRANSLATION_BUTTON_EDGE;
    const minY = this.comicTranslationButtonMinY();
    this.comicTranslationButtonY = this.clampComicTranslationButtonY(minY +
      (this.comicTranslationButtonMaxY() - minY) * safeRatio);
  }

  private persistComicTranslationButtonPosition(): void {
    const side = this.comicTranslationButtonX + READER_TRANSLATION_BUTTON_SIZE / 2 <= this.readerLayoutWidth / 2 ?
      'Left' : 'Right';
    const minY = this.comicTranslationButtonMinY();
    const range = Math.max(1, this.comicTranslationButtonMaxY() - minY);
    const ratio = Math.max(0, Math.min(1, (this.comicTranslationButtonY - minY) / range));
    ehSettingsStore.setValue('reader_translation_button_side', side);
    ehSettingsStore.setValue('reader_translation_button_y_ratio', ratio.toString());
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch(() => {});
    }
  }

  private snapComicTranslationButtonToEdge(): void {
    const onLeft = this.comicTranslationButtonX + READER_TRANSLATION_BUTTON_SIZE / 2 <= this.readerLayoutWidth / 2;
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
      this.comicTranslationButtonX = onLeft ? READER_TRANSLATION_BUTTON_EDGE :
        this.readerLayoutWidth - READER_TRANSLATION_BUTTON_SIZE - READER_TRANSLATION_BUTTON_EDGE;
      this.comicTranslationButtonY = this.clampComicTranslationButtonY(this.comicTranslationButtonY);
    });
    this.persistComicTranslationButtonPosition();
  }

  private toggleComicTranslationFromButton(): void {
    if (this.comicTranslationLongPressHandled) {
      this.comicTranslationLongPressHandled = false;
      return;
    }
    const enabled = !this.comicTranslationActive;
    this.onComicTranslationToggle(enabled);
    this.showToast(uiText(enabled ? 'Comic translation started' : 'Comic translation hidden'));
  }

  private refreshComicTranslationFromButton(): void {
    this.comicTranslationLongPressHandled = true;
    this.onComicTranslationRefresh();
    this.showToast(uiText('Retranslating current page'));
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
      this.jumpToAdjacentPageGroup(this.swiperReversed ? 1 : -1);
    } else if (relX > 2.0 / 3.0) {
      // Right tap: next for LTR, prev for RTL
      this.jumpToAdjacentPageGroup(this.swiperReversed ? -1 : 1);
    } else if (relY < 2.0 / 3.0) {
      this.showMenu();
    } else {
      this.showSlider();
    }
  }

  private canGoNext(): boolean {
    const groups = this.pageGroupIndexesAscending();
    return groups.indexOf(this.pageGroupAnchorForPageIndex(this.currentIndex)) + 1 < groups.length;
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
    const target = this.pageGroupAnchorForPageIndex(Math.max(0, Math.min(this.totalPages - 1, Math.round(value))));
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
    this.jumpToAdjacentPageGroup(-1);
  }

  private nextReaderPage(): void {
    if (this.swiperVertical) {
      this.scrollVerticalReaderByPage(1);
      return;
    }
    this.jumpToAdjacentPageGroup(1);
  }

  private jumpToAdjacentPageGroup(direction: number): void {
    const groups = this.pageGroupIndexesAscending();
    const current = groups.indexOf(this.pageGroupAnchorForPageIndex(this.currentIndex));
    if (current < 0) {
      return;
    }
    const target = current + direction;
    if (target >= 0 && target < groups.length) {
      this.jumpTo(groups[target]);
    }
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
    if (index === this.pageGroupAnchorForPageIndex(this.pageIndex)) {
      return;
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
    if (this.shouldPairPage(this.currentIndex)) {
      return (this.currentIndex + 1).toString() + '-' + (this.currentIndex + 2).toString() + '/' + total.toString();
    }
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

  private pairedPageScale(index: number): number {
    const first = this.pageImageSize(index);
    const second = this.pageImageSize(index + 1);
    if (first === null || second === null || first.width <= 0 || first.height <= 0 ||
      second.width <= 0 || second.height <= 0) {
      return 1;
    }
    if (this.readerLayoutHeight >= this.readerLayoutWidth) {
      const combinedHeight = this.readerLayoutWidth * first.height / first.width +
        this.readerLayoutWidth * second.height / second.width;
      return combinedHeight > 0 ? Math.min(1, this.readerLayoutHeight / combinedHeight) : 1;
    }
    const combinedWidth = this.readerLayoutHeight * first.width / first.height +
      this.readerLayoutHeight * second.width / second.height;
    return combinedWidth > 0 ? Math.min(1, this.readerLayoutWidth / combinedWidth) : 1;
  }

  private pairedPageCrossExtent(index: number): number {
    const scale = this.pairedPageScale(index);
    if (this.readerLayoutHeight >= this.readerLayoutWidth) {
      return Math.max(1, this.readerLayoutWidth * scale);
    }
    return Math.max(1, this.readerLayoutHeight * scale);
  }

  private pairedPageDisplayExtent(groupIndex: number, pageIndex: number): number {
    const size = this.pageImageSize(pageIndex);
    if (size === null || size.width <= 0 || size.height <= 0) {
      return 1;
    }
    if (this.readerLayoutHeight >= this.readerLayoutWidth) {
      return Math.max(1, this.pairedPageCrossExtent(groupIndex) * size.height / size.width);
    }
    return Math.max(1, this.pairedPageCrossExtent(groupIndex) * size.width / size.height);
  }

  @Builder
  private ReaderPageViewport(index: number, width: Length, height: Length) {
    ReaderImageViewport({
      page: this.pageForIndex(index),
      statusText: index === this.pageIndex ? this.statusText : uiText('Image page is loading'),
      preferOriginal: this.preferOriginal,
      fitMode: this.fitMode,
      fixedScale: this.fixedScale,
      startPosition: this.startPosition,
      isActive: this.pageGroupAnchorForPageIndex(index) === this.currentIndex,
      translation: this.readerTranslationForPage(index),
      allowEdgeSwipe: !this.swiperVertical,
      command: this.viewportCommand,
      commandVersion: this.viewportCommandVersion,
      onTap: () => {},
      onRetry: () => {
        if (index === this.currentIndex) {
          this.onRetry();
        } else {
          this.onRefreshPage(index);
        }
      },
      onImageLongPress: () => {
        if (this.pageGroupAnchorForPageIndex(index) === this.currentIndex) {
          this.showImageActions(index);
        }
      },
      onSwipeLockChange: (locked: boolean) => {
        if (this.pageGroupAnchorForPageIndex(index) === this.currentIndex) {
          this.isDisableSwipe = locked;
        }
      },
      onZoomChange: (percent: number) => {
        if (this.pageGroupAnchorForPageIndex(index) === this.currentIndex) {
          this.zoomPercent = percent;
          if (this.isFixedScaleMode()) {
            this.fixedScale = Math.max(READER_MIN_SCALE, Math.min(READER_MAX_SCALE, percent / 100));
          }
        }
      },
      onImageSizeChange: (width: number, height: number) => {
        this.rememberPageImageSize(index, width, height);
        if (index === this.currentIndex) {
          this.onActiveImageSizeChange(width, height);
        }
      },
      onEdgeSwipe: (direction: number) => {
        if (this.pageGroupAnchorForPageIndex(index) === this.currentIndex) {
          this.jumpByVisualDirection(direction);
        }
      }
    })
      .width(width)
      .height(height)
  }

  @Builder
  private ReaderPageGroup(index: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.shouldPairPage(index)) {
        if (this.readerLayoutHeight >= this.readerLayoutWidth) {
          Column({ space: 0 }) {
            this.ReaderPageViewport(index, '100%', this.pairedPageDisplayExtent(index, index))
            this.ReaderPageViewport(index + 1, '100%', this.pairedPageDisplayExtent(index, index + 1))
          }
          .width(this.pairedPageCrossExtent(index))
          .height(this.pairedPageDisplayExtent(index, index) + this.pairedPageDisplayExtent(index, index + 1))
        } else {
          Row({ space: 0 }) {
            if (this.swiperReversed) {
              this.ReaderPageViewport(index + 1, this.pairedPageDisplayExtent(index, index + 1), '100%')
              this.ReaderPageViewport(index, this.pairedPageDisplayExtent(index, index), '100%')
            } else {
              this.ReaderPageViewport(index, this.pairedPageDisplayExtent(index, index), '100%')
              this.ReaderPageViewport(index + 1, this.pairedPageDisplayExtent(index, index + 1), '100%')
            }
          }
          .width(this.pairedPageDisplayExtent(index, index) + this.pairedPageDisplayExtent(index, index + 1))
          .height(this.pairedPageCrossExtent(index))
        }
      } else {
        this.ReaderPageViewport(index, '100%', '100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(readerBackgroundColor())
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isContinuousVerticalMode()) {
        List({ space: 0, scroller: this.continuousScroller }) {
          LazyForEach(this.readerPageIndexSource(), (item: ReaderPageGroupItem) => {
            ListItem() {
              ReaderContinuousImageItem({
                page: this.pageForIndex(item.index),
                statusText: item.index === this.pageIndex ? this.statusText : uiText('Image page is loading'),
                preferOriginal: this.preferOriginal,
                fitMode: this.fitMode,
                zoomScale: this.fixedScale,
                sharedOffsetX: this.continuousOffsetX,
                isActive: item.index === this.currentIndex,
                translation: this.readerTranslationForPage(item.index),
                onTap: () => {},
                onRetry: () => {
                  this.onJump(item.index);
                },
                onImageLongPress: () => {
                  this.currentIndex = item.index;
                  this.showImageActions(item.index);
                },
                onImageSizeChange: (width: number, height: number) => {
                  if (item.index === this.currentIndex) {
                    this.onActiveImageSizeChange(width, height);
                  }
                },
                onZoomChange: (percent: number) => {
                  this.zoomPercent = percent;
                  this.fixedScale = Math.max(READER_MIN_SCALE, Math.min(READER_MAX_SCALE, percent / 100));
                },
                onHorizontalBoundsChange: (maxOffsetX: number) => {
                  if (item.index === this.currentIndex) {
                    this.onContinuousHorizontalBoundsChange(maxOffsetX);
                  }
                },
                onHorizontalDragStart: (maxOffsetX: number) => {
                  if (item.index === this.currentIndex) {
                    this.onContinuousHorizontalDragStart(maxOffsetX);
                  }
                },
                onHorizontalDragUpdate: (offsetX: number, maxOffsetX: number) => {
                  if (item.index === this.currentIndex) {
                    this.onContinuousHorizontalDragUpdate(offsetX, maxOffsetX);
                  }
                },
                onHorizontalDragEnd: (velocityX: number, maxOffsetX: number) => {
                  if (item.index === this.currentIndex) {
                    this.onContinuousHorizontalDragEnd(velocityX, maxOffsetX);
                  }
                }
              })
                .width('100%')
            }
            .reuseId('reader-continuous-page')
          }, (item: ReaderPageGroupItem) => item.key)
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
          LazyForEach(this.readerPageIndexSource(), (item: ReaderPageGroupItem) => {
            this.ReaderPageGroup(item.index)
          }, (item: ReaderPageGroupItem) => item.key)
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
        .onAnimationStart((_index: number, _targetIndex: number) => {
          this.swiperAnimating = true;
        })
        .onAnimationEnd((_index: number) => {
          this.swiperAnimating = false;
          if (this.pageGroupRefreshPending) {
            this.schedulePageGroupRefresh(0);
          }
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
          menuAdaptiveDualPage: this.menuAdaptiveDualPage,
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
          readingDirectionOptions: this.readerMenuReadingDirectionOptions(),
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
          onAdaptiveDualPageChange: (value: boolean) => {
            this.onMenuAdaptiveDualPageChange(value);
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
      if (this.comicTranslationButtonVisible) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.translate'))
            .fontSize(25)
            .fontColor([Color.White])
        }
        .width(READER_TRANSLATION_BUTTON_SIZE)
        .height(READER_TRANSLATION_BUTTON_SIZE)
        .backgroundColor(this.comicTranslationActive ? '#167A9A' : '#34454D')
        .opacity(0.46)
        .shadow({ radius: 8, color: 'rgba(0,0,0,0.28)', offsetX: 0, offsetY: 2 })
        .position({ x: this.comicTranslationButtonX, y: this.comicTranslationButtonY })
        .accessibilityText(uiText('Comic translation'))
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            LongPressGesture({ repeat: false, duration: 600 })
              .onAction(() => {
                this.refreshComicTranslationFromButton();
              }),
            PanGesture({ fingers: 1, distance: 4 })
              .onActionStart(() => {
                this.comicTranslationLongPressHandled = false;
                this.comicTranslationDragStartX = this.comicTranslationButtonX;
                this.comicTranslationDragStartY = this.comicTranslationButtonY;
              })
              .onActionUpdate((event: GestureEvent) => {
                this.comicTranslationButtonX = this.clampComicTranslationButtonX(
                  this.comicTranslationDragStartX + event.offsetX);
                this.comicTranslationButtonY = this.clampComicTranslationButtonY(
                  this.comicTranslationDragStartY + event.offsetY);
              })
              .onActionEnd(() => {
                this.snapComicTranslationButtonToEdge();
              })
              .onActionCancel(() => {
                this.snapComicTranslationButtonToEdge();
              }),
            TapGesture({ count: 1 })
              .onAction(() => {
                this.toggleComicTranslationFromButton();
              })
          )
        )
        .zIndex(8)
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      let layoutChanged = false;
      const width = newArea.width as number;
      if (width > 0 && !Number.isNaN(width) && Math.abs(this.readerLayoutWidth - width) >= 1) {
        this.readerLayoutWidth = width;
        layoutChanged = true;
      }
      const height = newArea.height as number;
      if (height > 0 && !Number.isNaN(height) && Math.abs(this.readerLayoutHeight - height) >= 1) {
        this.readerLayoutHeight = height;
        layoutChanged = true;
      }
      if (layoutChanged) {
        this.normalizeCurrentPageGroup();
        this.syncReaderPageIndexSource();
        this.syncComicTranslationButtonPosition();
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

function usableReaderLocalPath(path: string): string {
  if (path.length === 0 || path.endsWith('.part')) {
    return '';
  }
  try {
    return fs.statSync(path).size > 0 ? path : '';
  } catch (error) {
    return '';
  }
}
