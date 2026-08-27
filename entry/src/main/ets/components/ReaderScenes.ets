import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { batteryInfo } from '@kit.BasicServicesKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { systemShare } from '@kit.ShareKit';
import inputConsumer from '@ohos.multimodalInput.inputConsumer';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { KeyEvent as InputKeyEvent } from '@ohos.multimodalInput.keyEvent';
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
  setEmbeddedReaderActive,
  setReaderTransientStatusBarVisible
} from '../services/EhWindowImmersive';
import { READER_TRANSLATION_BUTTON_VISIBLE_KEY, ehSettingsStore } from '../services/EhSettingsStore';
import {
  activeReaderPresetProfile,
  allReaderPresetProfiles,
  createReaderPresetValues,
  deleteCustomReaderPreset,
  findReaderPresetByName,
  findReaderPresetProfile,
  ReaderPresetProfile,
  ReaderPresetSaveResult,
  ReaderPresetValues,
  READER_CUSTOM_PRESETS_SETTING_KEY,
  saveCustomReaderPreset,
  saveReaderPreset
} from '../services/ReaderPresetSupport';
import { galleryPageCache } from '../services/GalleryPageCache';
import {
  ReaderImageProcessingPrefetchPlan,
  ReaderImageProcessingPrefetchScope
} from '../services/ReaderImageProcessingPrefetchService';
import { IMAGE_DOWNLOAD_PRIORITY_READER, readerImageCache } from '../services/ReaderImageCache';
import { readerHdrService } from '../services/ReaderHdrService';
import { readerImageAdjustmentService } from '../services/ReaderImageAdjustmentService';
import {
  cloneReaderImageAdjustmentSettings,
  ReaderImageAdjustmentSettings,
  readerImageAdjustmentSettingsFromStore,
  resetReaderImageAdjustmentSettings,
  saveReaderImageAdjustmentSettings
} from '../services/ReaderImageAdjustmentSupport';
import { readerSuperResolutionService } from '../services/ReaderSuperResolutionService';
import {
  effectiveReaderSuperResolutionEngine,
  readerSuperResolutionEngineCacheKey,
  readerSuperResolutionEngineOptions,
  READER_SUPER_RESOLUTION_ENGINE_DETAIL
} from '../services/ReaderSuperResolutionSupport';
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
  currentThemeName,
  notifyThemeChanged,
  pushActiveBackHandler,
  setReaderActiveBackHandler,
  BOTTOM_AVOID_HEIGHT_KEY,
  STATUS_BAR_HEIGHT_KEY,
  uiText
} from '../shared/EhShared';
import { ArrayDataSource } from '../shared/ListDataSource';
import {
  isHarmonyUiStyle,
  uiButtonMaterial,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiTintedButtonMaterial
} from '../shared/EhUiStyle';
import {
  READER_BASE_SCALE,
  READER_INERTIA_DURATION,
  READER_MAX_SCALE,
  READER_MIN_SCALE,
  READER_OFFSCREEN_RENDER_SCREEN_COUNT,
  ReaderPreviewModel,
  readerBackgroundColor,
  readerLocalSourceImagePath
} from './reader/core/ReaderCore';
import {
  addUniquePath,
  albumImageFileType,
  copyFileContent,
  packPixelMapContent,
  readerImageExtension,
  readerImageFileName,
  readerProcessedImageFileName,
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
const READER_SCREEN_TAP_DELAY: number = 300;
const READER_PAIRED_TAP_DELAY: number = 420;
const READER_PAIRED_TAP_MOVE_TOLERANCE: number = 14;
const READER_PAIRED_DOUBLE_TAP_DISTANCE: number = 48;
const READER_DUAL_PAGE_OVERFLOW_RATIO: number = 1.15;
const READER_PAGE_GROUP_REFRESH_DELAY: number = 220;
const READER_TRANSLATION_BUTTON_SIZE: number = 52;
const READER_TRANSLATION_BUTTON_EDGE: number = 8;
const READER_AXIS_PAGE_INTERVAL: number = 140;

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

interface ReaderSuperResolutionDisplayTarget {
  width: number;
  height: number;
}

interface ReaderPageGroupItem {
  index: number;
  key: string;
  paired: boolean;
}

class ReaderProcessedImageLease {
  pixelMap: image.PixelMap | undefined = undefined;
  superResolutionKey: string = '';
  hdrKey: string = '';
  adjustmentKey: string = '';

  release(): void {
    if (this.hdrKey.length > 0) {
      readerHdrService.release(this.hdrKey);
      this.hdrKey = '';
    }
    if (this.superResolutionKey.length > 0) {
      readerSuperResolutionService.release(this.superResolutionKey);
      this.superResolutionKey = '';
    }
    if (this.adjustmentKey.length > 0) {
      readerImageAdjustmentService.release(this.adjustmentKey);
      this.adjustmentKey = '';
    }
    this.pixelMap = undefined;
  }
}

@Component
struct ReaderPairedTransformViewport {
  @ObjectLink model: ReaderPreviewModel;
  @BuilderParam content: () => void = this.EmptyContent;

  @Builder
  private EmptyContent() {
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      this.content()
    }
    .scale({
      x: this.model.currentScale,
      y: this.model.currentScale,
      centerX: '50%',
      centerY: '50%'
    })
    .translate({
      x: this.model.currentOffsetX,
      y: this.model.currentOffsetY
    })
  }
}

@Component
export struct ReaderScene {
  @Prop @Watch('onRenderVersionChange') renderVersion: number = 0;
  @Prop page: GalleryPage = createEmptyPage();
  @Prop @Watch('onReaderPagesChange') readerPages: ReaderPageState[] = [];
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
  onComicTranslationRefresh: (pageIndexes: number[]) => void = (_pageIndexes: number[]) => {};
  restoreAppChromeOnExit: boolean = true;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  @StorageProp(BOTTOM_AVOID_HEIGHT_KEY) bottomAvoidHeight: number = 0;
  @StorageProp(READER_TRANSLATION_BUTTON_VISIBLE_KEY) comicTranslationButtonVisible: boolean = false;

  @State fitMode: string = 'Fit screen';
  @State adaptiveDualPage: boolean = false;
  @State cropWhiteBorders: boolean = false;
  @State imageSuperResolutionEnabled: boolean = false;
  @State imageSuperResolutionEngine: string = READER_SUPER_RESOLUTION_ENGINE_DETAIL;
  @State sdrToHdrEnabled: boolean = false;
  @State imageAdjustmentSettings: ReaderImageAdjustmentSettings = new ReaderImageAdjustmentSettings();
  @State startPosition: string = 'Center';
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
  @State readerAvoidAreaReady: boolean = false;
  @State readerSafeTopPx: number = 0;
  @State readerSafeRightPx: number = 0;
  @State readerSafeBottomPx: number = 0;
  @State autoTransferPlaying: boolean = false;
  @State currentIndex: number = 0;
  @State isDisableSwipe: boolean = false;
  @State zoomPercent: number = 100;
  @State fixedScale: number = READER_BASE_SCALE;
  @State continuousOffsetX: number = 0;
  @State viewportCommand: string = '';
  @State viewportCommandVersion: number = 0;
  @State readerPageImageSizeRevision: number = 0;
  @State pairedImageModel: ReaderPreviewModel = new ReaderPreviewModel();
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
  private imageProcessingPrefetchScope: ReaderImageProcessingPrefetchScope =
    new ReaderImageProcessingPrefetchScope();
  private readerPageImageSizes: ReaderPageImageSize[] = [];
  private readerImageSizeGalleryId: number = -1;
  private pageGroupRefreshTimer: number = -1;
  private pageGroupRefreshPending: boolean = false;
  private swiperAnimating: boolean = false;
  private swiperSourceSyncTarget: number = -1;
  private swiperSourceSyncRevision: number = 0;
  private swiperSourceSyncTimer: number = -1;
  private continuousScroller: Scroller = new Scroller();
  private continuousScrollTarget: number = -1;
  private continuousScrollRevision: number = 0;
  private continuousScrollTimer: number = -1;
  private activeImageWidth: number = 0;
  private activeImageHeight: number = 0;
  private pairedViewportIndex: number = -1;
  private mountedPairedPageKeys: string[] = [];
  private continuousDragStartOffsetX: number = 0;
  private comicTranslationDragStartX: number = 0;
  private comicTranslationDragStartY: number = 0;
  private comicTranslationLongPressHandled: boolean = false;
  private readerSystemAvoidArea: window.AvoidArea | undefined = undefined;
  private readerCutoutAvoidArea: window.AvoidArea | undefined = undefined;
  private readerNavigationAvoidArea: window.AvoidArea | undefined = undefined;
  private readerAvoidAreaWindow: window.Window | undefined = undefined;
  private readerAvoidAreaCallback: (data: window.AvoidAreaOptions) => void =
    (data: window.AvoidAreaOptions): void => {
      if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
        this.readerSystemAvoidArea = data.area;
      } else if (data.type === window.AvoidAreaType.TYPE_CUTOUT) {
        this.readerCutoutAvoidArea = data.area;
      } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
        this.readerNavigationAvoidArea = data.area;
      } else {
        return;
      }
      this.refreshReaderSafeInsets();
    };

  // Menu settings state (reflects ehSettingsStore, applied on menu close)
  @State menuScreenRotation: string = 'Default';
  @State menuReaderPreset: string = 'Current settings';
  @State menuReaderPresetOptions: string[] = [];
  @State menuReaderPresetTargetId: string = '';
  @State menuReaderPresetSelected: boolean = false;
  @State menuReaderPresetCustom: boolean = false;
  @State menuReaderPresetEditName: string = '';
  @State menuSettingsTab: number = 0;
  @State menuReadingDirection: string = 'Right to left';
  @State menuPageScaling: string = 'Fit screen';
  @State menuTheme: string = 'Light';
  @State menuReaderBackground: string = 'Deep gray';
  @State menuAdaptiveDualPage: boolean = false;
  @State menuCropWhiteBorders: boolean = false;
  @State menuImageSuperResolutionEnabled: boolean = false;
  @State menuImageSuperResolutionEngine: string = READER_SUPER_RESOLUTION_ENGINE_DETAIL;
  @State menuSdrToHdrEnabled: boolean = false;
  @State menuImageAdjustmentSettings: ReaderImageAdjustmentSettings = new ReaderImageAdjustmentSettings();
  @State menuStartPosition: string = 'Center';
  @State menuKeepScreenOn: boolean = false;
  @State menuShowClock: boolean = true;
  @State menuShowProgress: boolean = true;
  @State menuShowBattery: boolean = true;
  @State menuReadingFullscreen: boolean = true;
  @State menuVolumePage: boolean = false;
  @State menuReverseVolumePage: boolean = false;
  @State menuComicTranslation: boolean = false;
  @State menuAiTranslation: boolean = false;
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
  private pairedTapTimer: number = -1;
  private pairedTouchStartX: number = 0;
  private pairedTouchStartY: number = 0;
  private pairedTouchStartTime: number = 0;
  private pairedLastTapX: number = 0;
  private pairedLastTapY: number = 0;
  private pairedTouchMoved: boolean = false;
  private pairedTouchHadMultipleFingers: boolean = false;
  private lastAxisPageAt: number = 0;
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
  private unregisterEmbeddedBackHandler: () => void = () => {};
  private readerBackHandlerInstalled: boolean = false;
  private volumeUpCallback: (event: InputKeyEvent) => void = (event: InputKeyEvent) => {
    this.handleVolumePageKey(event);
  };
  private volumeDownCallback: (event: InputKeyEvent) => void = (event: InputKeyEvent) => {
    this.handleVolumePageKey(event);
  };

  aboutToAppear(): void {
    if (this.transientDisappearCleanupTimer !== -1) {
      clearTimeout(this.transientDisappearCleanupTimer);
      this.transientDisappearCleanupTimer = -1;
    }
    this.readerWindowActive = true;
    this.installReaderBackHandler();
    setReaderTransientStatusBarVisible(false);
    this.adaptiveDualPage = ehSettingsStore.getValue('adaptive_dual_page', 'Off') === 'On';
    this.cropWhiteBorders = ehSettingsStore.getValue('reader_crop_white_borders', 'Off') === 'On';
    this.imageSuperResolutionEnabled =
      ehSettingsStore.getValue('reader_image_super_resolution', 'Off') === 'On';
    this.imageSuperResolutionEngine = effectiveReaderSuperResolutionEngine(
      ehSettingsStore.getValue('reader_super_resolution_engine', READER_SUPER_RESOLUTION_ENGINE_DETAIL));
    this.sdrToHdrEnabled = ehSettingsStore.getValue('reader_sdr_to_hdr', 'Off') === 'On';
    this.imageAdjustmentSettings = readerImageAdjustmentSettingsFromStore();
    this.resetReaderImageSizesForGallery();
    if (!this.cropWhiteBorders) {
      this.syncReaderPreviewImageSizes();
    }
    this.currentIndex = this.pageGroupAnchorForPageIndex(this.pageIndex);
    this.syncReaderPageIndexSource();
    if (this.restoreAppChromeOnExit) {
      setEmbeddedReaderActive(true);
    }
    this.fitMode = normalizePageScalingOption(ehSettingsStore.getValue('page_scaling', 'Fit screen'));
    this.startPosition = normalizeStartPositionOption(ehSettingsStore.getValue('start_position', 'Center'));
    this.menuTheme = currentThemeName();
    this.menuReaderBackground = ehSettingsStore.getValue('reader_background', 'Deep gray');
    this.menuVisible = false;
    this.imageActionsVisible = false;
    this.sliderVisible = false;
    this.imageActionPageIndex = this.currentIndex;
    this.syncOverlayState();
    this.syncDirectionState();
    if (this.isContinuousVerticalMode()) {
      this.scheduleContinuousPageSync(this.currentIndex, false);
    }
    this.syncUltraDarkState();
    this.refreshBattery();
    this.refreshOverlayInfo();
    this.startOverlayRefreshTimer();
    this.applyReaderWindowSettings();
    this.applyBrightnessFromSettings().catch(() => {});
    this.updateVolumePageBinding();
    this.syncImageProcessingPrefetch();
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
    this.uninstallReaderBackHandler();
    this.imageProcessingPrefetchScope.clear();
    setReaderTransientStatusBarVisible(false);
    this.unregisterReaderAvoidAreaListener();
    this.readerWindowSettingsRevision++;
    if (this.readerWindowSettingsTimer !== -1) {
      clearTimeout(this.readerWindowSettingsTimer);
      this.readerWindowSettingsTimer = -1;
    }
    this.clearPageGroupRefreshTimer();
    this.pageGroupRefreshPending = false;
    this.clearContinuousPageSync();
    this.clearSwiperSourceSync();
    this.swiperAnimating = false;
    this.clearSliderTimer();
    this.clearScreenTapTimer();
    this.clearPairedTapTimer();
    this.clearAutoTransferTimer();
    this.clearOverlayRefreshTimer();
    this.unregisterVolumePageKeys();
    this.resetReaderBrightness().catch(() => {});
  }

  private installReaderBackHandler(): void {
    this.uninstallReaderBackHandler();
    if (this.restoreAppChromeOnExit) {
      this.unregisterEmbeddedBackHandler = pushActiveBackHandler(() => this.handleReaderSystemBack());
    } else {
      setReaderActiveBackHandler(() => this.handleReaderSystemBack());
    }
    this.readerBackHandlerInstalled = true;
  }

  private uninstallReaderBackHandler(): void {
    if (!this.readerBackHandlerInstalled) {
      return;
    }
    if (this.restoreAppChromeOnExit) {
      this.unregisterEmbeddedBackHandler();
      this.unregisterEmbeddedBackHandler = () => {};
    } else {
      setReaderActiveBackHandler(null);
    }
    this.readerBackHandlerInstalled = false;
  }

  private handleReaderSystemBack(): boolean {
    if (!this.dismissReaderControlOverlay()) {
      this.onBack();
    }
    return true;
  }

  private applyReaderWindowSettings(): void {
    const keepOn = ehSettingsStore.getValue('keep_screen_on', 'Off') === 'On';
    const orientation = readerScreenRotationSetting();
    const fullscreen = this.readerWindowFullscreen();
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
      this.registerReaderAvoidAreaListener(this.hostReaderWindow);
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
        this.registerReaderAvoidAreaListener(win);
        return win;
      }
    } catch (error) {
    }
    const readerWin = getReaderWindow();
    if (readerWin !== undefined) {
      this.registerReaderAvoidAreaListener(readerWin);
      return readerWin;
    }
    if (!this.restoreAppChromeOnExit) {
      return undefined;
    }
    const mainWin = getMainWindow();
    if (mainWin !== undefined) {
      this.registerReaderAvoidAreaListener(mainWin);
    }
    return mainWin;
  }

  private readerTransientStatusBarVisible(): boolean {
    return this.menuVisible || this.sliderVisible;
  }

  private readerWindowFullscreen(): boolean {
    return ehSettingsStore.getValue('reading_fullscreen', 'On') === 'On' &&
      !this.readerTransientStatusBarVisible();
  }

  private syncReaderTransientStatusBar(): void {
    setReaderTransientStatusBarVisible(this.readerTransientStatusBarVisible());
    this.applyReaderWindowSettings();
  }

  private registerReaderAvoidAreaListener(win: window.Window): void {
    if (this.readerAvoidAreaWindow === win) {
      return;
    }
    this.unregisterReaderAvoidAreaListener();
    this.readerAvoidAreaWindow = win;
    try {
      this.readerSystemAvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    } catch (_error) {
      this.readerSystemAvoidArea = undefined;
    }
    try {
      this.readerCutoutAvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
    } catch (_error) {
      this.readerCutoutAvoidArea = undefined;
    }
    try {
      this.readerNavigationAvoidArea =
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    } catch (_error) {
      this.readerNavigationAvoidArea = undefined;
    }
    this.readerAvoidAreaReady = true;
    this.refreshReaderSafeInsets();
    try {
      win.on('avoidAreaChange', this.readerAvoidAreaCallback);
    } catch (_error) {
    }
  }

  private unregisterReaderAvoidAreaListener(): void {
    if (this.readerAvoidAreaWindow !== undefined) {
      try {
        this.readerAvoidAreaWindow.off('avoidAreaChange', this.readerAvoidAreaCallback);
      } catch (_error) {
      }
    }
    this.readerAvoidAreaWindow = undefined;
    this.readerSystemAvoidArea = undefined;
    this.readerCutoutAvoidArea = undefined;
    this.readerNavigationAvoidArea = undefined;
    this.readerAvoidAreaReady = false;
  }

  private avoidAreaTop(area: window.AvoidArea | undefined): number {
    return area === undefined ? 0 : Math.max(0, area.topRect.top + area.topRect.height);
  }

  private avoidAreaRight(area: window.AvoidArea | undefined): number {
    return area === undefined ? 0 : Math.max(0, area.rightRect.width);
  }

  private avoidAreaBottom(area: window.AvoidArea | undefined): number {
    return area === undefined ? 0 : Math.max(0, area.bottomRect.height);
  }

  private refreshReaderSafeInsets(): void {
    this.readerSafeTopPx = Math.max(this.avoidAreaTop(this.readerSystemAvoidArea),
      this.avoidAreaTop(this.readerCutoutAvoidArea));
    this.readerSafeRightPx = Math.max(this.avoidAreaRight(this.readerSystemAvoidArea),
      this.avoidAreaRight(this.readerCutoutAvoidArea));
    this.readerSafeBottomPx = Math.max(this.avoidAreaBottom(this.readerSystemAvoidArea),
      this.avoidAreaBottom(this.readerCutoutAvoidArea), this.avoidAreaBottom(this.readerNavigationAvoidArea));
    this.syncComicTranslationButtonPosition();
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
    this.syncImageProcessingPrefetch();
  }

  onGalleryIdChange(): void {
    this.imageProcessingPrefetchScope.clear();
    this.resetPairedViewport();
    if (!this.resetReaderImageSizesForGallery()) {
      return;
    }
    if (!this.cropWhiteBorders) {
      this.syncReaderPreviewImageSizes();
    }
    this.currentIndex = this.pageGroupAnchorForPageIndex(this.pageIndex);
    this.sliderLiveIndex = this.clampReaderPageIndex(this.currentIndex);
    this.readerPageIndexesCount = -1;
    if (this.readerWindowActive) {
      this.syncReaderPageIndexSource();
      this.syncImageProcessingPrefetch();
      this.syncPairedViewport(this.currentIndex);
      if (this.isContinuousVerticalMode()) {
        this.scheduleContinuousPageSync(this.currentIndex, false);
      }
    }
  }

  onReaderPagesChange(): void {
    this.syncImageProcessingPrefetch();
  }

  onReaderPreviewsChange(): void {
    if (!this.cropWhiteBorders && this.syncReaderPreviewImageSizes()) {
      this.schedulePageGroupRefresh();
    }
  }

  onTotalPagesChange(): void {
    this.resetPairedViewport();
    this.currentIndex = this.pageGroupAnchorForPageIndex(this.pageIndex);
    this.sliderLiveIndex = this.clampReaderPageIndex(this.currentIndex);
    this.syncReaderPageIndexSource();
    this.syncImageProcessingPrefetch();
    this.syncPairedViewport(this.currentIndex);
    if (this.readerWindowActive && this.isContinuousVerticalMode()) {
      this.scheduleContinuousPageSync(this.currentIndex, false);
    }
  }

  private statusBarHeightVp(): number {
    const heightPx = this.readerAvoidAreaReady ? this.readerSafeTopPx : this.statusBarHeightPx;
    if (heightPx <= 0) {
      return 0;
    }
    return this.getUIContext().px2vp(heightPx);
  }

  private readerStatusOverlayTop(): number {
    return Math.max(12, this.statusBarHeightVp() + 8);
  }

  private readerStatusOverlayRight(): number {
    if (!this.readerAvoidAreaReady || this.readerSafeRightPx <= 0) {
      return 12;
    }
    return this.getUIContext().px2vp(this.readerSafeRightPx) + 12;
  }

  private readerBottomInset(): number {
    const readerInset = this.readerAvoidAreaReady && this.readerSafeBottomPx > 0 ?
      this.getUIContext().px2vp(this.readerSafeBottomPx) : 0;
    return Math.max(0, this.bottomAvoidHeight, readerInset);
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
      const fullscreen = this.readerWindowFullscreen();
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
    const oldVertical = this.swiperVertical;
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
    if (this.swiperVertical) {
      if (!oldVertical || oldReversed !== this.swiperReversed) {
        this.scheduleContinuousPageSync(this.currentIndex, false);
      }
    } else if (oldVertical) {
      this.clearContinuousPageSync();
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
    const targetIndex = this.pageGroupAnchorForPageIndex(this.pageIndex);
    const pageGroupChanged = targetIndex !== this.currentIndex;
    if (pageGroupChanged) {
      this.resetPairedViewport();
      this.isDisableSwipe = false;
      this.zoomPercent = this.isFixedScaleMode() ? Math.round(this.fixedScale * 100) : 100;
    }
    this.currentIndex = targetIndex;
    this.sliderLiveIndex = this.clampReaderPageIndex(this.currentIndex);
    this.sliderDragging = false;
    this.imageActionsVisible = false;
    this.scheduleAutoTransfer();
    this.syncReaderPageIndexSource();
    this.syncImageProcessingPrefetch();
    this.syncPairedViewport(this.currentIndex);
    if (pageGroupChanged) {
      if (this.isContinuousVerticalMode()) {
        this.scheduleContinuousPageSync(this.currentIndex, false);
      } else {
        try {
          this.swiperController.changeIndex(this.visualIndexForPageIndex(this.currentIndex), false);
        } catch (e) {}
      }
    }
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
        this.readerPageImageSizeRevision++;
        this.schedulePageGroupRefresh();
        return;
      }
    }
    this.readerPageImageSizes.push({ index: index, width: width, height: height });
    this.readerPageImageSizeRevision++;
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
      const previousIndex = this.currentIndex;
      const previousGroup = this.readerPageGroupItem(previousIndex);
      const nextAnchor = this.pageGroupAnchorForPageIndex(previousIndex);
      const currentGroupUnchanged = previousGroup !== null && previousGroup.index === nextAnchor &&
        previousGroup.paired === this.shouldPairPage(nextAnchor);
      // Size reports from prefetched pages may rebuild other groups; keep the active group's zoom in that case.
      if (!currentGroupUnchanged) {
        this.resetPairedViewport();
      }
      this.normalizeCurrentPageGroup();
      this.syncReaderPageIndexSource();
      this.syncImageProcessingPrefetch();
      this.syncPairedViewport(this.currentIndex);
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
    this.resetPairedViewport();
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

  private readerRenderScreenCacheCount(): number {
    return READER_OFFSCREEN_RENDER_SCREEN_COUNT;
  }

  private readerContinuousCacheCount(): number {
    return this.readerRenderScreenCacheCount() + 2;
  }

  private shouldRenderPageGroup(index: number): boolean {
    const currentVisualIndex = this.visualIndexForPageIndex(this.currentIndex);
    const targetVisualIndex = this.visualIndexForPageIndex(index);
    return Math.abs(targetVisualIndex - currentVisualIndex) <= this.readerRenderScreenCacheCount();
  }

  private imageProcessingPrefetchPageIndexes(): number[] {
    const result: number[] = [];
    const count = this.totalPages <= 0 ? 1 : this.totalPages;
    if (this.isContinuousVerticalMode()) {
      const radius = this.readerContinuousCacheCount();
      const first = Math.max(0, this.currentIndex - radius);
      const last = Math.min(count - 1, this.currentIndex + radius);
      for (let index = first; index <= last; index++) {
        result.push(index);
      }
      return result;
    }
    const groups = this.pageGroupIndexesAscending();
    const currentGroup = groups.indexOf(this.pageGroupAnchorForPageIndex(this.currentIndex));
    const firstGroup = Math.max(0, currentGroup - this.readerRenderScreenCacheCount());
    const lastGroup = Math.min(groups.length - 1, currentGroup + this.readerRenderScreenCacheCount());
    for (let i = firstGroup; i <= lastGroup; i++) {
      const pageIndex = groups[i];
      result.push(pageIndex);
      if (this.shouldPairPage(pageIndex) && pageIndex + 1 < count) {
        result.push(pageIndex + 1);
      }
    }
    return result;
  }

  private superResolutionViewportSize(index: number): ReaderSuperResolutionDisplayTarget {
    let width = Math.max(1, this.readerLayoutWidth);
    let height = Math.max(1, this.readerLayoutHeight);
    if (!this.isContinuousVerticalMode()) {
      const groupIndex = this.pageGroupAnchorForPageIndex(index);
      if (this.shouldPairPage(groupIndex)) {
        if (this.readerLayoutHeight >= this.readerLayoutWidth) {
          width = this.pairedPageCrossExtent(groupIndex);
          height = this.pairedPageDisplayExtent(groupIndex, index);
        } else {
          width = this.pairedPageDisplayExtent(groupIndex, index);
          height = this.pairedPageCrossExtent(groupIndex);
        }
      }
    }
    return {
      width: Math.max(1, Math.round(this.getUIContext().vp2px(width))),
      height: Math.max(1, Math.round(this.getUIContext().vp2px(height)))
    };
  }

  private superResolutionDisplayTarget(index: number): ReaderSuperResolutionDisplayTarget {
    // The size cache itself is intentionally kept outside ArkUI observation. Reading this revision
    // makes the computed child props refresh as soon as the first decoded image reports its size.
    this.readerPageImageSizeRevision;
    const empty: ReaderSuperResolutionDisplayTarget = { width: 0, height: 0 };
    if (this.readerLayoutWidth <= 0 || this.readerLayoutHeight <= 0) {
      return empty;
    }
    const viewport = this.superResolutionViewportSize(index);
    const source = this.pageImageSize(index);
    const mode = normalizePageScalingOption(this.fitMode);
    if (this.isContinuousVerticalMode() || mode === 'Fit width' || mode === 'Fixed scale') {
      return {
        width: Math.round(viewport.width * (mode === 'Fixed scale' ? Math.max(1, this.fixedScale) : 1)),
        height: 0
      };
    }
    if (mode === 'Fit height') {
      return { width: 0, height: viewport.height };
    }
    if (mode === 'Actual size' && source !== null && source.width > 0) {
      return { width: source.width, height: 0 };
    }
    if (mode !== 'Fit screen' || source === null || source.width <= 0 || source.height <= 0) {
      return empty;
    }
    const widthScale = viewport.width / source.width;
    const heightScale = viewport.height / source.height;
    return widthScale <= heightScale ? { width: viewport.width, height: 0 } :
      { width: 0, height: viewport.height };
  }

  private superResolutionTargetKey(target: ReaderSuperResolutionDisplayTarget): string {
    return Math.max(0, target.width).toString() + 'x' + Math.max(0, target.height).toString();
  }

  private syncImageProcessingPrefetch(): void {
    if (!this.readerWindowActive || (!this.imageSuperResolutionEnabled && !this.sdrToHdrEnabled &&
      !this.imageAdjustmentSettings.requiresOfflineProcessing())) {
      this.imageProcessingPrefetchScope.clear();
      return;
    }
    const pageIndexes = this.imageProcessingPrefetchPageIndexes();
    const plans: ReaderImageProcessingPrefetchPlan[] = [];
    for (let i = 0; i < pageIndexes.length; i++) {
      const pageIndex = pageIndexes[i];
      const page = this.pageForIndex(pageIndex);
      const sourcePath = readerLocalSourceImagePath(page, this.preferOriginal);
      if (sourcePath.length === 0) {
        continue;
      }
      const original = this.preferOriginal && page.originImageUrl.length > 0;
      const sourceKey = readerPageImageCacheKey(page, original);
      const target = this.superResolutionDisplayTarget(pageIndex);
      const targetKey = this.superResolutionTargetKey(target);
      const engineKey = readerSuperResolutionEngineCacheKey(this.imageSuperResolutionEngine);
      const sourceInputKey = sourceKey + '|' + sourcePath;
      const adjustmentKey = sourceInputKey + '|adjust|' + this.imageAdjustmentSettings.detailCacheKey() +
        '|target|' + targetKey;
      const offlineAdjustment = this.imageAdjustmentSettings.requiresOfflineProcessing();
      const superResolutionInputKey = offlineAdjustment ? adjustmentKey : sourceInputKey;
      const superResolutionKey = superResolutionInputKey + '|sr|' + engineKey + '|' + targetKey;
      const fallbackSuperResolutionKey = sourceInputKey + '|sr|' + engineKey + '|' + targetKey;
      const hdrInputKey = this.imageSuperResolutionEnabled ? superResolutionKey :
        (offlineAdjustment ? adjustmentKey : sourceInputKey);
      const hdrKey = hdrInputKey + '|hdr';
      const fallbackHdrKey = sourceKey + '|' + sourcePath + '|hdr';
      const priority = this.isContinuousVerticalMode() ? Math.abs(pageIndex - this.currentIndex) :
        Math.abs(this.visualIndexForPageIndex(pageIndex) - this.visualIndexForPageIndex(this.currentIndex));
      plans.push({
        id: pageIndex.toString() + '|' + superResolutionKey + '|' + hdrKey + '|' +
          adjustmentKey + '|' + (this.imageSuperResolutionEnabled ? '1' : '0') +
          (this.sdrToHdrEnabled ? '1' : '0') + (offlineAdjustment ? '1' : '0'),
        sourcePath: sourcePath,
        superResolutionKey: superResolutionKey,
        fallbackSuperResolutionKey: fallbackSuperResolutionKey,
        hdrKey: hdrKey,
        fallbackHdrKey: fallbackHdrKey,
        adjustmentKey: adjustmentKey,
        adjustmentSettings: this.imageAdjustmentSettings,
        targetWidth: target.width,
        targetHeight: target.height,
        superResolutionEngine: this.imageSuperResolutionEngine,
        superResolution: this.imageSuperResolutionEnabled,
        hdr: this.sdrToHdrEnabled,
        adjustment: offlineAdjustment,
        priority: priority
      });
    }
    this.imageProcessingPrefetchScope.sync(plans);
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
      items.push({
        index: pages[i],
        key: this.readerPageGroupRevision.toString() + ':' + pages[i].toString(),
        paired: this.shouldPairPage(pages[i])
      });
    }
    this.mountedPairedPageKeys = [];
    const anchor = this.pageGroupAnchorForPageIndex(this.currentIndex);
    const targetVisualIndex = pages.indexOf(anchor);
    this.scheduleSwiperSourceSync(targetVisualIndex < 0 ? 0 : targetVisualIndex);
    this.readerPageIndexesSource.setItems(items);
  }

  private clearSwiperSourceSync(): void {
    this.swiperSourceSyncRevision++;
    this.swiperSourceSyncTarget = -1;
    if (this.swiperSourceSyncTimer !== -1) {
      clearTimeout(this.swiperSourceSyncTimer);
      this.swiperSourceSyncTimer = -1;
    }
  }

  private scheduleSwiperSourceSync(targetVisualIndex: number): void {
    if (this.isContinuousVerticalMode()) {
      this.clearSwiperSourceSync();
      return;
    }
    if (this.swiperSourceSyncTimer !== -1) {
      clearTimeout(this.swiperSourceSyncTimer);
      this.swiperSourceSyncTimer = -1;
    }
    const revision = ++this.swiperSourceSyncRevision;
    this.swiperSourceSyncTarget = targetVisualIndex;
    this.swiperSourceSyncTimer = setTimeout(() => {
      this.swiperSourceSyncTimer = -1;
      if (!this.readerWindowActive || revision !== this.swiperSourceSyncRevision ||
        this.isContinuousVerticalMode()) {
        if (revision === this.swiperSourceSyncRevision) {
          this.swiperSourceSyncTarget = -1;
        }
        return;
      }
      const expectedIndex = this.visualIndexForPageIndex(this.currentIndex);
      this.swiperSourceSyncTarget = expectedIndex;
      try {
        this.swiperController.changeIndex(expectedIndex, false);
      } catch (error) {
      }
      this.swiperSourceSyncTimer = setTimeout(() => {
        if (revision === this.swiperSourceSyncRevision) {
          this.swiperSourceSyncTarget = -1;
          this.swiperSourceSyncTimer = -1;
        }
      }, 80) as number;
    }, 0) as number;
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

  private issueViewportCommand(command: string, centerX: number = -1, centerY: number = -1): void {
    if (!this.isContinuousVerticalMode() && this.shouldPairPage(this.currentIndex)) {
      this.syncPairedViewport(this.currentIndex);
      if (command === 'zoom_in') {
        this.pairedImageModel.zoomBy(1.25);
      } else if (command === 'zoom_out') {
        this.pairedImageModel.zoomBy(0.8);
      } else if (command === 'double_zoom') {
        this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
          this.pairedImageModel.toggleDoubleTap(
            centerX >= 0 ? centerX : this.pairedImageModel.componentWidth / 2,
            centerY >= 0 ? centerY : this.pairedImageModel.componentHeight / 2
          );
          this.reportPairedViewportState(this.currentIndex);
        });
      } else if (command === 'reset') {
        this.pairedImageModel.reset();
      }
      this.reportPairedViewportState(this.currentIndex);
    }
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
      this.sliderHideTimer = -1;
      this.sliderVisible = false;
      this.sliderDragging = false;
      this.syncReaderTransientStatusBar();
    }, SLIDER_AUTO_HIDE_DELAY) as number;
  }

  private clearPairedTapTimer(): void {
    if (this.pairedTapTimer !== -1) {
      clearTimeout(this.pairedTapTimer);
      this.pairedTapTimer = -1;
    }
  }

  private showSlider(): void {
    this.imageActionsVisible = false;
    this.sliderLiveIndex = this.clampReaderPageIndex(this.currentIndex);
    this.sliderDragging = false;
    this.sliderVisible = true;
    this.syncReaderTransientStatusBar();
    this.scheduleSliderHide();
  }

  private hideSlider(): void {
    this.clearSliderTimer();
    this.sliderVisible = false;
    this.sliderDragging = false;
    this.syncReaderTransientStatusBar();
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
    this.menuTheme = currentThemeName();
    this.menuReaderBackground = ehSettingsStore.getValue('reader_background', 'Deep gray');
    this.menuAdaptiveDualPage = ehSettingsStore.getValue('adaptive_dual_page', 'Off') === 'On';
    this.menuCropWhiteBorders = ehSettingsStore.getValue('reader_crop_white_borders', 'Off') === 'On';
    this.menuImageSuperResolutionEnabled =
      ehSettingsStore.getValue('reader_image_super_resolution', 'Off') === 'On';
    this.menuImageSuperResolutionEngine = effectiveReaderSuperResolutionEngine(
      ehSettingsStore.getValue('reader_super_resolution_engine', READER_SUPER_RESOLUTION_ENGINE_DETAIL));
    this.menuSdrToHdrEnabled = ehSettingsStore.getValue('reader_sdr_to_hdr', 'Off') === 'On';
    this.menuImageAdjustmentSettings = readerImageAdjustmentSettingsFromStore();
    this.menuSettingsTab = this.readerSettingsTabFromStore();
    this.menuStartPosition = normalizeStartPositionOption(ehSettingsStore.getValue('start_position', 'Center'));
    this.menuKeepScreenOn = ehSettingsStore.getValue('keep_screen_on', 'Off') === 'On';
    this.menuShowClock = ehSettingsStore.getValue('gallery_show_clock', 'On') === 'On';
    this.menuShowProgress = ehSettingsStore.getValue('gallery_show_progress', 'On') === 'On';
    this.menuShowBattery = ehSettingsStore.getValue('gallery_show_battery', 'On') === 'On';
    this.menuReadingFullscreen = ehSettingsStore.getValue('reading_fullscreen', 'On') === 'On';
    this.menuVolumePage = ehSettingsStore.getValue('volume_page', 'Off') === 'On';
    this.menuReverseVolumePage = ehSettingsStore.getValue('reverse_volume_page', 'Off') === 'On';
    this.menuComicTranslation = ehSettingsStore.getValue('reader_translation_enabled', 'Off') === 'On';
    this.menuAiTranslation = ehSettingsStore.getValue('translation_ai_enabled', 'Off') === 'On';
    this.menuAutoTransferTime = normalizeAutoTransferTimeOption(ehSettingsStore.getValue('start_transfer_time', '5s'));
    this.menuCustomBrightness = ehSettingsStore.getValue('custom_screen_lightness', 'Off') === 'On';
    this.menuBrightnessLevel = normalizeBrightnessLevelOption(ehSettingsStore.getValue('screen_lightness', '50%'));
    this.syncMenuReaderPreset();
    this.menuVisible = true;
    this.syncReaderTransientStatusBar();
    this.clearAutoTransferTimer();
    this.autoTransferPlaying = false;
  }

  private readerSettingsTabFromStore(): number {
    const parsed = Number.parseInt(ehSettingsStore.getValue('reader_settings_tab', '0'));
    return Number.isNaN(parsed) ? 0 : Math.max(0, Math.min(3, parsed));
  }

  private applyMenuTheme(value: string): void {
    const normalized = value === 'Black' ? 'Black' : (value === 'Dark' ? 'Dark' : 'Light');
    this.menuTheme = normalized;
    ehSettingsStore.setValue('follow_system_dark_mode', 'Off');
    ehSettingsStore.setValue('theme', normalized);
    notifyThemeChanged();
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch(() => {});
    }
  }

  private applyMenuReaderBackground(value: string): void {
    const normalized = value === 'Black' ? 'Black' : (value === 'White' ? 'White' : 'Deep gray');
    this.menuReaderBackground = normalized;
    ehSettingsStore.setValue('reader_background', normalized);
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch(() => {});
    }
  }

  private currentReaderBackgroundColor(): string {
    return readerBackgroundColor(this.menuReaderBackground);
  }

  private applyMenuSettings(): void {
    this.applyAdaptiveDualPageMenuConstraints();
    const previousAdaptiveDualPage = this.adaptiveDualPage;
    const previousCropWhiteBorders = this.cropWhiteBorders;
    ehSettingsStore.setValue('adaptive_dual_page', this.menuAdaptiveDualPage ? 'On' : 'Off');
    ehSettingsStore.setValue('reader_crop_white_borders', this.menuCropWhiteBorders ? 'On' : 'Off');
    ehSettingsStore.setValue('reader_image_super_resolution',
      this.menuImageSuperResolutionEnabled ? 'On' : 'Off');
    ehSettingsStore.setValue('reader_super_resolution_engine', this.menuImageSuperResolutionEngine);
    ehSettingsStore.setValue('reader_sdr_to_hdr', this.menuSdrToHdrEnabled ? 'On' : 'Off');
    saveReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
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
    ehSettingsStore.setValue('reverse_volume_page', this.menuReverseVolumePage ? 'On' : 'Off');
    ehSettingsStore.setValue('reader_translation_enabled', this.menuComicTranslation ? 'On' : 'Off');
    ehSettingsStore.setValue('translation_ai_enabled', this.menuAiTranslation ? 'On' : 'Off');
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
    this.cropWhiteBorders = this.menuCropWhiteBorders;
    this.imageSuperResolutionEnabled = this.menuImageSuperResolutionEnabled;
    this.imageSuperResolutionEngine = effectiveReaderSuperResolutionEngine(this.menuImageSuperResolutionEngine);
    this.sdrToHdrEnabled = this.menuSdrToHdrEnabled;
    this.imageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
    if (previousAdaptiveDualPage !== this.adaptiveDualPage) {
      this.onAdaptiveDualPageChange(this.adaptiveDualPage);
    }
    if (previousCropWhiteBorders !== this.cropWhiteBorders) {
      this.readerPageImageSizes = [];
      if (!this.cropWhiteBorders) {
        this.syncReaderPreviewImageSizes();
      }
      this.schedulePageGroupRefresh(0);
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
    this.syncImageProcessingPrefetch();
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

  private currentMenuReaderPresetValues(): ReaderPresetValues {
    return createReaderPresetValues(this.menuScreenRotation, this.menuReadingDirection, this.menuPageScaling,
      this.menuAdaptiveDualPage, this.menuCropWhiteBorders, this.menuImageSuperResolutionEnabled,
      this.menuImageSuperResolutionEngine, this.menuSdrToHdrEnabled, this.menuStartPosition,
      this.menuImageAdjustmentSettings);
  }

  private syncMenuReaderPreset(): void {
    const profiles = allReaderPresetProfiles(
      ehSettingsStore.getValue(READER_CUSTOM_PRESETS_SETTING_KEY, '[]'));
    this.updateMenuReaderPresetOptions(profiles);
    const active = activeReaderPresetProfile(profiles, this.currentMenuReaderPresetValues());
    this.menuReaderPreset = active === null ? 'Current settings' : active.name;
    this.menuReaderPresetTargetId = active === null ? '' : active.id;
    this.menuReaderPresetSelected = active !== null;
    this.menuReaderPresetCustom = active !== null && !active.builtIn;
    this.menuReaderPresetEditName = active === null ? '' : active.name;
  }

  private updateMenuReaderPresetOptions(profiles: ReaderPresetProfile[]): void {
    const options: string[] = [];
    for (let i = 0; i < profiles.length; i++) {
      options.push(profiles[i].name);
    }
    options.push('Current settings');
    this.menuReaderPresetOptions = options;
  }

  private markMenuReaderPresetCustom(): void {
    this.menuReaderPreset = 'Current settings';
  }

  private onMenuReaderPresetChange(value: string): void {
    if (value === 'Current settings') {
      this.menuReaderPreset = value;
      this.menuReaderPresetTargetId = '';
      this.menuReaderPresetSelected = false;
      this.menuReaderPresetCustom = false;
      this.menuReaderPresetEditName = '';
      return;
    }
    const profiles = allReaderPresetProfiles(
      ehSettingsStore.getValue(READER_CUSTOM_PRESETS_SETTING_KEY, '[]'));
    const profile: ReaderPresetProfile | null = findReaderPresetByName(profiles, value);
    if (profile === null) {
      return;
    }
    this.menuScreenRotation = profile.values.screenRotation;
    this.menuReadingDirection = profile.values.readingDirection;
    this.menuPageScaling = profile.values.pageScaling;
    this.menuAdaptiveDualPage = profile.values.adaptiveDualPage;
    this.menuCropWhiteBorders = profile.values.cropWhiteBorders;
    this.menuImageSuperResolutionEnabled = profile.values.imageSuperResolution;
    this.menuImageSuperResolutionEngine = effectiveReaderSuperResolutionEngine(profile.values.superResolutionEngine);
    this.menuSdrToHdrEnabled = profile.values.sdrToHdr;
    this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(profile.values.imageAdjustment);
    this.menuStartPosition = profile.values.startPosition;
    this.applyAdaptiveDualPageMenuConstraints();
    this.menuReaderPreset = profile.name;
    this.menuReaderPresetTargetId = profile.id;
    this.menuReaderPresetSelected = true;
    this.menuReaderPresetCustom = !profile.builtIn;
    this.menuReaderPresetEditName = profile.name;
  }

  private menuReaderPresetTarget(): ReaderPresetProfile | null {
    const profiles = allReaderPresetProfiles(
      ehSettingsStore.getValue(READER_CUSTOM_PRESETS_SETTING_KEY, '[]'));
    return findReaderPresetProfile(profiles, this.menuReaderPresetTargetId);
  }

  private persistReaderPresetRaw(raw: string, status: string): void {
    ehSettingsStore.setValue(READER_CUSTOM_PRESETS_SETTING_KEY, raw);
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch(() => {
        this.showToast(uiText('Save failed'));
      });
    }
    this.showToast(uiText(status));
  }

  private selectSavedReaderPreset(profile: ReaderPresetProfile): void {
    const profiles = allReaderPresetProfiles(
      ehSettingsStore.getValue(READER_CUSTOM_PRESETS_SETTING_KEY, '[]'));
    this.updateMenuReaderPresetOptions(profiles);
    this.menuReaderPreset = profile.name;
    this.menuReaderPresetTargetId = profile.id;
    this.menuReaderPresetSelected = true;
    this.menuReaderPresetCustom = !profile.builtIn;
    this.menuReaderPresetEditName = profile.name;
  }

  private createMenuReaderPreset(name: string): void {
    const raw = ehSettingsStore.getValue(READER_CUSTOM_PRESETS_SETTING_KEY, '[]');
    const nameError = this.readerPresetNameError(raw, name, '');
    if (nameError.length > 0) {
      this.showToast(uiText(nameError));
      return;
    }
    const result: ReaderPresetSaveResult = saveCustomReaderPreset(raw, '', name,
      this.currentMenuReaderPresetValues());
    if (result.profile === null) {
      this.showToast(uiText(result.error.length > 0 ? result.error : 'Save failed'));
      return;
    }
    this.persistReaderPresetRaw(result.raw, 'Reading preset saved');
    this.selectSavedReaderPreset(result.profile);
  }

  private saveMenuReaderPreset(): void {
    const target = this.menuReaderPresetTarget();
    if (target === null) {
      return;
    }
    const raw = ehSettingsStore.getValue(READER_CUSTOM_PRESETS_SETTING_KEY, '[]');
    const result: ReaderPresetSaveResult = saveReaderPreset(raw, target.id, target.name,
      this.currentMenuReaderPresetValues());
    if (result.profile === null) {
      this.showToast(uiText(result.error.length > 0 ? result.error : 'Save failed'));
      return;
    }
    this.persistReaderPresetRaw(result.raw, 'Reading preset updated');
    this.selectSavedReaderPreset(result.profile);
  }

  private renameMenuReaderPreset(name: string): void {
    const target = this.menuReaderPresetTarget();
    if (target === null || target.builtIn) {
      return;
    }
    const raw = ehSettingsStore.getValue(READER_CUSTOM_PRESETS_SETTING_KEY, '[]');
    const nameError = this.readerPresetNameError(raw, name, target.id);
    if (nameError.length > 0) {
      this.showToast(uiText(nameError));
      return;
    }
    const result: ReaderPresetSaveResult = saveCustomReaderPreset(raw, target.id, name, target.values);
    if (result.profile === null) {
      this.showToast(uiText(result.error.length > 0 ? result.error : 'Save failed'));
      return;
    }
    this.persistReaderPresetRaw(result.raw, 'Reading preset renamed');
    this.selectSavedReaderPreset(result.profile);
  }

  private deleteMenuReaderPreset(): void {
    const target = this.menuReaderPresetTarget();
    if (target === null || target.builtIn) {
      return;
    }
    const raw = ehSettingsStore.getValue(READER_CUSTOM_PRESETS_SETTING_KEY, '[]');
    this.persistReaderPresetRaw(deleteCustomReaderPreset(raw, target.id), 'Reading preset deleted');
    this.menuReaderPresetTargetId = '';
    this.menuReaderPresetSelected = false;
    this.menuReaderPresetCustom = false;
    this.menuReaderPresetEditName = '';
    this.syncMenuReaderPreset();
  }

  private readerPresetNameError(raw: string, name: string, excludedId: string): string {
    const normalized = name.trim().toLowerCase();
    if (normalized.length === 0) {
      return 'Preset name is required';
    }
    if (normalized === 'current settings' || normalized === uiText('Current settings').trim().toLowerCase()) {
      return 'Preset name is reserved';
    }
    const profiles = allReaderPresetProfiles(raw);
    for (let i = 0; i < profiles.length; i++) {
      if (profiles[i].id === excludedId) {
        continue;
      }
      if (profiles[i].name.trim().toLowerCase() === normalized ||
        uiText(profiles[i].name).trim().toLowerCase() === normalized) {
        return 'Preset name already exists';
      }
    }
    return '';
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
    this.markMenuReaderPresetCustom();
  }

  private onMenuImageSuperResolutionChange(value: boolean): void {
    this.menuImageSuperResolutionEnabled = value;
    this.markMenuReaderPresetCustom();
  }

  private onMenuImageSuperResolutionEngineChange(value: string): void {
    this.menuImageSuperResolutionEngine = effectiveReaderSuperResolutionEngine(value);
    this.markMenuReaderPresetCustom();
  }

  private onMenuSdrToHdrChange(value: boolean): void {
    this.menuSdrToHdrEnabled = value;
    this.markMenuReaderPresetCustom();
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
    this.markMenuReaderPresetCustom();
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

  private handleVolumePageKey(event: InputKeyEvent): void {
    if (!this.readerWindowActive || ehSettingsStore.getValue('volume_page', 'Off') !== 'On') {
      return;
    }
    const reversed = ehSettingsStore.getValue('reverse_volume_page', 'Off') === 'On';
    if (event.key.code === KeyCode.KEYCODE_VOLUME_UP) {
      if (reversed) {
        this.nextReaderPage();
      } else {
        this.previousReaderPage();
      }
    } else if (event.key.code === KeyCode.KEYCODE_VOLUME_DOWN) {
      if (reversed) {
        this.previousReaderPage();
      } else {
        this.nextReaderPage();
      }
    }
  }

  private readerControlOverlayVisible(): boolean {
    return this.menuVisible || this.imageActionsVisible || this.sliderVisible;
  }

  private dismissReaderControlOverlay(): boolean {
    if (this.menuVisible) {
      this.hideMenu();
      return true;
    }
    if (this.imageActionsVisible) {
      this.hideImageActions();
      return true;
    }
    if (this.sliderVisible) {
      this.hideSliderAndStopPlayback();
      return true;
    }
    return false;
  }

  private isDpadControlKey(code: number): boolean {
    return code === KeyCode.KEYCODE_DPAD_UP || code === KeyCode.KEYCODE_DPAD_DOWN ||
      code === KeyCode.KEYCODE_DPAD_LEFT || code === KeyCode.KEYCODE_DPAD_RIGHT ||
      code === KeyCode.KEYCODE_DPAD_CENTER;
  }

  private isGameControllerKey(code: number): boolean {
    return code === KeyCode.KEYCODE_BUTTON_A || code === KeyCode.KEYCODE_BUTTON_B ||
      code === KeyCode.KEYCODE_BUTTON_L1 || code === KeyCode.KEYCODE_BUTTON_R1 ||
      code === KeyCode.KEYCODE_BUTTON_L2 || code === KeyCode.KEYCODE_BUTTON_R2 ||
      code === KeyCode.KEYCODE_BUTTON_START || code === KeyCode.KEYCODE_BUTTON_SELECT ||
      code === KeyCode.KEYCODE_BUTTON_MODE;
  }

  private isKeyboardReaderKey(code: number): boolean {
    return code === KeyCode.KEYCODE_PAGE_UP || code === KeyCode.KEYCODE_PAGE_DOWN ||
      code === KeyCode.KEYCODE_SPACE || code === KeyCode.KEYCODE_ENTER ||
      code === KeyCode.KEYCODE_NUMPAD_ENTER || code === KeyCode.KEYCODE_ESCAPE ||
      code === KeyCode.KEYCODE_MOVE_HOME || code === KeyCode.KEYCODE_MOVE_END ||
      code === KeyCode.KEYCODE_PLUS || code === KeyCode.KEYCODE_EQUALS ||
      code === KeyCode.KEYCODE_NUMPAD_ADD || code === KeyCode.KEYCODE_MINUS ||
      code === KeyCode.KEYCODE_NUMPAD_SUBTRACT || code === KeyCode.KEYCODE_0 ||
      code === KeyCode.KEYCODE_NUMPAD_0 || code === KeyCode.KEYCODE_MENU;
  }

  private readerKeyControlEnabled(event: KeyEvent): boolean {
    const code = event.keyCode;
    return this.isGameControllerKey(code) || this.isDpadControlKey(code) || this.isKeyboardReaderKey(code);
  }

  private turnReaderByHorizontalSide(leftSide: boolean): void {
    if (this.swiperVertical) {
      if (leftSide) {
        this.previousReaderPage();
      } else {
        this.nextReaderPage();
      }
      return;
    }
    if (leftSide) {
      this.jumpToAdjacentPageGroup(this.swiperReversed ? 1 : -1);
    } else {
      this.jumpToAdjacentPageGroup(this.swiperReversed ? -1 : 1);
    }
  }

  private handleReaderKeyEvent(event: KeyEvent): boolean {
    if (!this.readerWindowActive || !this.readerKeyControlEnabled(event)) {
      return false;
    }
    const code = event.keyCode;
    const isDismissKey = code === KeyCode.KEYCODE_ESCAPE || code === KeyCode.KEYCODE_BUTTON_B;
    if (event.type !== KeyType.Down) {
      return isDismissKey || !this.readerControlOverlayVisible();
    }
    if (isDismissKey) {
      if (!this.dismissReaderControlOverlay()) {
        this.onBack();
      }
      return true;
    }
    if (this.readerControlOverlayVisible()) {
      if (code === KeyCode.KEYCODE_MENU || code === KeyCode.KEYCODE_BUTTON_START ||
        code === KeyCode.KEYCODE_BUTTON_MODE) {
        this.dismissReaderControlOverlay();
        return true;
      }
      return false;
    }
    if (code === KeyCode.KEYCODE_PAGE_UP || code === KeyCode.KEYCODE_DPAD_UP ||
      code === KeyCode.KEYCODE_BUTTON_L1 || code === KeyCode.KEYCODE_BUTTON_L2) {
      this.previousReaderPage();
      return true;
    }
    if (code === KeyCode.KEYCODE_PAGE_DOWN || code === KeyCode.KEYCODE_DPAD_DOWN ||
      code === KeyCode.KEYCODE_BUTTON_R1 || code === KeyCode.KEYCODE_BUTTON_R2) {
      this.nextReaderPage();
      return true;
    }
    if (code === KeyCode.KEYCODE_DPAD_LEFT) {
      this.turnReaderByHorizontalSide(true);
      return true;
    }
    if (code === KeyCode.KEYCODE_DPAD_RIGHT) {
      this.turnReaderByHorizontalSide(false);
      return true;
    }
    if (code === KeyCode.KEYCODE_SPACE || code === KeyCode.KEYCODE_ENTER ||
      code === KeyCode.KEYCODE_NUMPAD_ENTER || code === KeyCode.KEYCODE_DPAD_CENTER ||
      code === KeyCode.KEYCODE_MENU || code === KeyCode.KEYCODE_BUTTON_A ||
      code === KeyCode.KEYCODE_BUTTON_START || code === KeyCode.KEYCODE_BUTTON_MODE) {
      this.showMenu();
      return true;
    }
    if (code === KeyCode.KEYCODE_MOVE_HOME) {
      this.jumpTo(0);
      return true;
    }
    if (code === KeyCode.KEYCODE_MOVE_END) {
      this.jumpTo(Math.max(0, this.totalPages - 1));
      return true;
    }
    if (code === KeyCode.KEYCODE_PLUS || code === KeyCode.KEYCODE_EQUALS ||
      code === KeyCode.KEYCODE_NUMPAD_ADD) {
      if (!this.swiperVertical) {
        this.issueViewportCommand('zoom_in');
      }
      return true;
    }
    if (code === KeyCode.KEYCODE_MINUS || code === KeyCode.KEYCODE_NUMPAD_SUBTRACT) {
      if (!this.swiperVertical) {
        this.issueViewportCommand('zoom_out');
      }
      return true;
    }
    if (code === KeyCode.KEYCODE_0 || code === KeyCode.KEYCODE_NUMPAD_0) {
      if (!this.swiperVertical) {
        this.issueViewportCommand('reset');
      }
      return true;
    }
    return false;
  }

  private handleReaderAxisEvent(event: AxisEvent): void {
    if (!this.readerWindowActive || this.readerControlOverlayVisible() || this.swiperVertical ||
      event.action !== AxisAction.UPDATE) {
      return;
    }
    const vertical = event.getVerticalAxisValue();
    const horizontal = event.getHorizontalAxisValue();
    const value = Math.abs(vertical) >= Math.abs(horizontal) ? vertical : horizontal;
    if (Math.abs(value) < 0.01) {
      return;
    }
    const now = Date.now();
    if (now - this.lastAxisPageAt < READER_AXIS_PAGE_INTERVAL) {
      return;
    }
    this.lastAxisPageAt = now;
    if (value > 0) {
      this.nextReaderPage();
    } else {
      this.previousReaderPage();
    }
  }

  private handleReaderMouseEvent(event: MouseEvent): void {
    if (!this.readerWindowActive || event.action !== MouseAction.Release) {
      return;
    }
    if (this.readerControlOverlayVisible()) {
      if (event.button === MouseButton.Back || event.button === MouseButton.Middle) {
        this.dismissReaderControlOverlay();
        event.stopPropagation();
      }
      return;
    }
    if (event.button === MouseButton.Back) {
      this.previousReaderPage();
    } else if (event.button === MouseButton.Forward) {
      this.nextReaderPage();
    } else if (event.button === MouseButton.Middle) {
      this.showMenu();
    } else if (event.button === MouseButton.Right) {
      this.showImageActions();
    } else {
      return;
    }
    event.stopPropagation();
  }

  private hideMenu(): void {
    this.menuVisible = false;
    setReaderTransientStatusBarVisible(this.readerTransientStatusBarVisible());
    this.applyMenuSettings();
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
    const processedImage = await this.acquireProcessedImageForSave(page, index, sourcePath);
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const hasProcessedImage = processedImage.pixelMap !== undefined;
      const fileName = hasProcessedImage ? readerProcessedImageFileName(index) :
        readerImageFileName(index, sourcePath, this.currentImageShareTarget());
      const title = mediaAssetTitle(fileName);
      // @SuppressWarnings permission
      const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE,
        hasProcessedImage ? 'jpeg' : albumImageFileType(sourcePath), { title: title });
      const saved = hasProcessedImage && processedImage.pixelMap !== undefined ?
        await packPixelMapContent(processedImage.pixelMap, uri) : copyFileContent(sourcePath, uri);
      if (saved) {
        this.showToast(uiText('Saved to album') + ': ' + fileName);
        this.hideImageActions();
      } else {
        this.showToast(uiText('Save failed'));
      }
    } catch (error) {
      this.showToast(uiText('Save failed'));
    } finally {
      processedImage.release();
    }
  }

  private async acquireProcessedImageForSave(page: GalleryPage, index: number,
    sourcePath: string): Promise<ReaderProcessedImageLease> {
    const lease = new ReaderProcessedImageLease();
    if ((!this.imageSuperResolutionEnabled && !this.sdrToHdrEnabled && !this.imageAdjustmentSettings.enabled &&
      !this.imageAdjustmentSettings.hasMoireReduction()) ||
      sourcePath.length === 0) {
      return lease;
    }
    const original = this.preferOriginal && page.originImageUrl.length > 0;
    const sourceKey = readerPageImageCacheKey(page, original);
    const target = this.superResolutionDisplayTarget(index);
    const targetKey = this.superResolutionTargetKey(target);
    let adjustedPixelMap: image.PixelMap | undefined = undefined;
    if (this.imageAdjustmentSettings.enabled || this.imageAdjustmentSettings.hasMoireReduction()) {
      lease.adjustmentKey = sourceKey + '|' + sourcePath + '|adjust-baked|' +
        this.imageAdjustmentSettings.cacheKey() + '|target|' + targetKey;
      try {
        adjustedPixelMap = await readerImageAdjustmentService.acquire(lease.adjustmentKey, sourcePath,
          this.imageAdjustmentSettings, 0, true, target.width, target.height);
      } catch (_error) {
        adjustedPixelMap = undefined;
      }
    }
    let superResolutionPixelMap: image.PixelMap | undefined = undefined;
    if (this.imageSuperResolutionEnabled) {
      const superResolutionInputKey = adjustedPixelMap !== undefined ? lease.adjustmentKey :
        sourceKey + '|' + sourcePath;
      lease.superResolutionKey = superResolutionInputKey + '|sr|' +
        readerSuperResolutionEngineCacheKey(this.imageSuperResolutionEngine) + '|' +
        this.superResolutionTargetKey(target);
      try {
        superResolutionPixelMap = adjustedPixelMap !== undefined ?
          await readerSuperResolutionService.acquirePixelMap(lease.superResolutionKey,
            adjustedPixelMap, 0, target.width, target.height, this.imageSuperResolutionEngine) :
          await readerSuperResolutionService.acquire(lease.superResolutionKey,
            sourcePath, 0, target.width, target.height, this.imageSuperResolutionEngine);
      } catch (_error) {
        superResolutionPixelMap = undefined;
      }
    }
    if (this.sdrToHdrEnabled) {
      try {
        const hdrInput = superResolutionPixelMap !== undefined ? superResolutionPixelMap : adjustedPixelMap;
        if (hdrInput !== undefined) {
          lease.hdrKey = (superResolutionPixelMap !== undefined ? lease.superResolutionKey :
            lease.adjustmentKey) + '|hdr';
          lease.pixelMap = await readerHdrService.acquirePixelMap(lease.hdrKey, hdrInput, 0);
        } else {
          lease.hdrKey = sourceKey + '|' + sourcePath + '|hdr';
          lease.pixelMap = await readerHdrService.acquire(lease.hdrKey, sourcePath, 0);
        }
      } catch (_error) {
        lease.pixelMap = undefined;
      }
    }
    if (lease.pixelMap === undefined) {
      lease.pixelMap = superResolutionPixelMap !== undefined ? superResolutionPixelMap : adjustedPixelMap;
    }
    return lease;
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
    const pageIndexes = this.visiblePageIndexesForComicTranslation();
    this.onComicTranslationRefresh(pageIndexes);
    this.showToast(uiText(pageIndexes.length > 1 ? 'Retranslating visible pages' : 'Retranslating current page'));
  }

  private visiblePageIndexesForComicTranslation(): number[] {
    const anchor = this.pageGroupAnchorForPageIndex(this.currentIndex);
    const pageIndexes: number[] = [anchor];
    if (this.shouldPairPage(anchor)) {
      pageIndexes.push(anchor + 1);
    }
    return pageIndexes;
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
      sourcePath = await readerImageCache.ensureCached(context, imageUrl, page.pageUrl,
        IMAGE_DOWNLOAD_PRIORITY_READER, undefined,
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
    const processedImage = await this.acquireProcessedImageForSave(page, index, sourcePath);
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [processedImage.pixelMap !== undefined ? readerProcessedImageFileName(index) :
        readerImageFileName(index, sourcePath, this.currentImageShareTarget())];
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris = await documentPicker.save(options);
      if (uris.length === 0) {
        return;
      }
      if (processedImage.pixelMap !== undefined) {
        await packPixelMapContent(processedImage.pixelMap, uris[0]);
      } else {
        copyFileContent(sourcePath, uris[0]);
      }
    } catch (_error) {
    } finally {
      processedImage.release();
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
    this.resetPairedViewport();
    this.resetActiveImageSize();
    this.currentIndex = target;
    this.isDisableSwipe = false;
    this.zoomPercent = this.isFixedScaleMode() ? Math.round(this.fixedScale * 100) : 100;
    this.imageActionsVisible = false;
    this.syncPairedViewport(target);
    if (this.autoTransferPlaying) {
      this.scheduleAutoTransfer();
    }
    if (this.isContinuousVerticalMode()) {
      this.scheduleContinuousPageSync(target, true);
    } else {
      try {
        this.swiperController.changeIndex(this.visualIndexForPageIndex(target), true);
      } catch (e) {}
    }
    this.onJump(target);
  }

  private clearContinuousPageSync(): void {
    this.continuousScrollRevision++;
    this.continuousScrollTarget = -1;
    if (this.continuousScrollTimer !== -1) {
      clearTimeout(this.continuousScrollTimer);
      this.continuousScrollTimer = -1;
    }
  }

  private scheduleContinuousPageSync(pageIndex: number, smooth: boolean): void {
    if (!this.isContinuousVerticalMode()) {
      return;
    }
    const target = this.clampReaderPageIndex(pageIndex);
    this.continuousScrollTarget = target;
    const revision = ++this.continuousScrollRevision;
    if (this.continuousScrollTimer !== -1) {
      clearTimeout(this.continuousScrollTimer);
      this.continuousScrollTimer = -1;
    }
    this.scheduleContinuousPageSyncAttempt(target, revision, smooth, 0);
  }

  private scheduleContinuousPageSyncAttempt(target: number, revision: number, smooth: boolean,
    attempt: number): void {
    const delay = attempt === 0 ? 0 : attempt === 1 ? 80 : 180;
    this.continuousScrollTimer = setTimeout(() => {
      this.continuousScrollTimer = -1;
      if (!this.readerWindowActive || !this.isContinuousVerticalMode() ||
        revision !== this.continuousScrollRevision || target !== this.continuousScrollTarget) {
        return;
      }
      try {
        this.continuousScroller.scrollToIndex(this.visualIndexForPageIndex(target), smooth, ScrollAlign.START);
      } catch (error) {
      }
      if (attempt < 2 && target === this.continuousScrollTarget && revision === this.continuousScrollRevision) {
        this.scheduleContinuousPageSyncAttempt(target, revision, false, attempt + 1);
      }
    }, delay) as number;
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
    if (this.swiperSourceSyncTarget >= 0) {
      const expectedIndex = this.visualIndexForPageIndex(this.currentIndex);
      if (visualIndex !== expectedIndex) {
        try {
          this.swiperController.changeIndex(expectedIndex, false);
        } catch (error) {
        }
        return;
      }
      this.clearSwiperSourceSync();
      return;
    }
    const index = this.pageIndexForVisualIndex(visualIndex);
    if (index === this.currentIndex) {
      return;
    }
    this.resetPairedViewport();
    this.resetActiveImageSize();
    this.currentIndex = index;
    this.syncImageProcessingPrefetch();
    this.isDisableSwipe = false;
    this.zoomPercent = this.isFixedScaleMode() ? Math.round(this.fixedScale * 100) : 100;
    this.imageActionsVisible = false;
    this.syncPairedViewport(index);
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
    if (this.continuousScrollTarget >= 0) {
      if (pageIndex !== this.continuousScrollTarget) {
        return;
      }
      this.continuousScrollTarget = -1;
      if (this.continuousScrollTimer !== -1) {
        clearTimeout(this.continuousScrollTimer);
        this.continuousScrollTimer = -1;
      }
    }
    if (pageIndex === this.currentIndex) {
      return;
    }
    this.currentIndex = pageIndex;
    this.sliderLiveIndex = pageIndex;
    this.syncImageProcessingPrefetch();
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
    if (!this.isContinuousVerticalMode() && this.shouldPairPage(this.currentIndex)) {
      return;
    }
    if (this.screenTapTimer !== -1) {
      this.clearScreenTapTimer();
      this.issueViewportCommand('double_zoom', this.tapLocalX(event), this.tapLocalY(event));
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

  private pairedCanvasWidth(index: number): number {
    if (this.readerLayoutHeight >= this.readerLayoutWidth) {
      return this.pairedPageCrossExtent(index);
    }
    return this.pairedPageDisplayExtent(index, index) + this.pairedPageDisplayExtent(index, index + 1);
  }

  private pairedCanvasHeight(index: number): number {
    if (this.readerLayoutHeight >= this.readerLayoutWidth) {
      return this.pairedPageDisplayExtent(index, index) + this.pairedPageDisplayExtent(index, index + 1);
    }
    return this.pairedPageCrossExtent(index);
  }

  private resetPairedViewport(): void {
    this.clearPairedTapTimer();
    this.pairedTouchMoved = false;
    this.pairedTouchHadMultipleFingers = false;
    this.pairedViewportIndex = -1;
    this.pairedImageModel.reset();
  }

  private readerPageGroupItem(index: number): ReaderPageGroupItem | null {
    for (let i = 0; i < this.readerPageIndexesSource.totalCount(); i++) {
      const item = this.readerPageIndexesSource.getData(i);
      if (item.index === index) {
        return item;
      }
    }
    return null;
  }

  private rememberMountedPairedPage(key: string): void {
    if (this.mountedPairedPageKeys.indexOf(key) < 0) {
      this.mountedPairedPageKeys.push(key);
    }
  }

  private forgetMountedPairedPage(key: string): void {
    this.mountedPairedPageKeys = this.mountedPairedPageKeys.filter((value: string) => value !== key);
  }

  private pairedPageGroupMounted(index: number): boolean {
    const item = this.readerPageGroupItem(index);
    return item !== null && item.paired && this.mountedPairedPageKeys.indexOf(item.key) >= 0;
  }

  private syncPairedViewport(index: number, width: number = this.readerLayoutWidth,
    height: number = this.readerLayoutHeight): void {
    const paired = index === this.currentIndex && this.shouldPairPage(index) &&
      this.pairedPageGroupMounted(index);
    if (!paired || width <= 0 || height <= 0) {
      return;
    }
    if (this.pairedViewportIndex !== index) {
      this.pairedImageModel.reset();
      this.pairedViewportIndex = index;
    }
    this.pairedImageModel.setComponentSize(width, height);
    this.pairedImageModel.setImageSize(this.pairedCanvasWidth(index), this.pairedCanvasHeight(index));
    this.reportPairedViewportState(index);
  }

  private reportPairedViewportState(index: number): void {
    if (index !== this.currentIndex || this.pairedViewportIndex !== index) {
      return;
    }
    this.isDisableSwipe = this.pairedImageModel.disableSwipe;
    this.zoomPercent = this.pairedImageModel.zoomPercent();
  }

  private pairedPageIndexAt(index: number, event: GestureEvent): number {
    const scale = Math.max(READER_MIN_SCALE, this.pairedImageModel.currentScale);
    const canvasLeft = (this.pairedImageModel.componentWidth - this.pairedImageModel.imageWidth * scale) / 2 +
      this.pairedImageModel.currentOffsetX;
    const canvasTop = (this.pairedImageModel.componentHeight - this.pairedImageModel.imageHeight * scale) / 2 +
      this.pairedImageModel.currentOffsetY;
    const localX = (this.tapLocalX(event) - canvasLeft) / scale;
    const localY = (this.tapLocalY(event) - canvasTop) / scale;
    if (this.readerLayoutHeight >= this.readerLayoutWidth) {
      return localY < this.pairedPageDisplayExtent(index, index) ? index : index + 1;
    }
    const firstVisualExtent = this.swiperReversed ?
      this.pairedPageDisplayExtent(index, index + 1) : this.pairedPageDisplayExtent(index, index);
    if (localX < firstVisualExtent) {
      return this.swiperReversed ? index + 1 : index;
    }
    return this.swiperReversed ? index : index + 1;
  }

  private shouldLetSwiperHandlePairedPan(event: BaseGestureEvent): boolean {
    const panEvent = event as PanGestureEvent;
    return this.pairedImageModel.shouldLetSwiperHandlePan(
      panEvent.offsetX,
      panEvent.velocityX,
      panEvent.offsetY,
      panEvent.velocityY
    );
  }

  private pairedTouchX(event: TouchEvent): number {
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0].x;
    }
    return event.touches.length > 0 ? event.touches[0].x : this.readerLayoutWidth / 2;
  }

  private pairedTouchY(event: TouchEvent): number {
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0].y;
    }
    return event.touches.length > 0 ? event.touches[0].y : this.readerLayoutHeight / 2;
  }

  private triggerPairedSingleTap(x: number, y: number): void {
    this.onTap(
      x,
      y,
      Math.max(1, this.readerLayoutWidth),
      Math.max(1, this.readerLayoutHeight)
    );
  }

  private pairedGestureReady(): boolean {
    return !this.isContinuousVerticalMode() && this.shouldPairPage(this.currentIndex) &&
      this.pairedViewportIndex === this.currentIndex;
  }

  private handlePairedOverlayTouch(event: TouchEvent): void {
    const x = this.pairedTouchX(event);
    const y = this.pairedTouchY(event);
    if (event.type === TouchType.Down) {
      if (!this.isContinuousVerticalMode() && this.shouldPairPage(this.currentIndex)) {
        this.syncPairedViewport(this.currentIndex);
      }
      if (!this.pairedGestureReady()) {
        return;
      }
      if (event.touches.length > 1) {
        this.pairedTouchHadMultipleFingers = true;
        this.pairedTouchMoved = true;
        this.clearPairedTapTimer();
        return;
      }
      this.pairedTouchStartX = x;
      this.pairedTouchStartY = y;
      this.pairedTouchStartTime = Date.now();
      this.pairedTouchMoved = false;
      this.pairedTouchHadMultipleFingers = false;
      return;
    }
    if (!this.pairedGestureReady()) {
      return;
    }
    if (event.type === TouchType.Move) {
      if (event.touches.length > 1) {
        this.pairedTouchHadMultipleFingers = true;
        this.pairedTouchMoved = true;
        this.clearPairedTapTimer();
        return;
      }
      const moveX = x - this.pairedTouchStartX;
      const moveY = y - this.pairedTouchStartY;
      if (Math.sqrt(moveX * moveX + moveY * moveY) > READER_PAIRED_TAP_MOVE_TOLERANCE) {
        this.pairedTouchMoved = true;
        this.clearPairedTapTimer();
      }
      return;
    }
    if (event.type === TouchType.Cancel) {
      this.pairedTouchMoved = true;
      this.pairedTouchHadMultipleFingers = false;
      return;
    }
    if (event.type !== TouchType.Up || this.pairedTouchHadMultipleFingers || this.pairedTouchMoved ||
      Date.now() - this.pairedTouchStartTime > READER_PAIRED_TAP_DELAY) {
      return;
    }
    const doubleTapX = x - this.pairedLastTapX;
    const doubleTapY = y - this.pairedLastTapY;
    if (this.pairedTapTimer !== -1 &&
      Math.sqrt(doubleTapX * doubleTapX + doubleTapY * doubleTapY) <= READER_PAIRED_DOUBLE_TAP_DISTANCE) {
      this.clearPairedTapTimer();
      if (this.pairedGestureReady()) {
        this.issueViewportCommand('double_zoom', x, y);
      }
      return;
    }
    if (this.pairedTapTimer !== -1) {
      this.clearPairedTapTimer();
      this.triggerPairedSingleTap(this.pairedLastTapX, this.pairedLastTapY);
    }
    this.pairedLastTapX = x;
    this.pairedLastTapY = y;
    this.pairedTapTimer = setTimeout(() => {
      this.pairedTapTimer = -1;
      this.triggerPairedSingleTap(x, y);
    }, READER_PAIRED_TAP_DELAY) as number;
  }

  @Builder
  private ReaderPageViewport(index: number, width: Length, height: Length, interactive: boolean = true) {
    ReaderImageViewport({
      page: this.pageForIndex(index),
      statusText: index === this.pageIndex ? this.statusText : uiText('Image page is loading'),
      preferOriginal: this.preferOriginal,
      fitMode: this.fitMode,
      fixedScale: this.fixedScale,
      startPosition: this.startPosition,
      isActive: this.pageGroupAnchorForPageIndex(index) === this.currentIndex,
      hdrEnabled: this.sdrToHdrEnabled,
      imageAdjustmentSettings: this.imageAdjustmentSettings,
      superResolutionEnabled: this.imageSuperResolutionEnabled,
      superResolutionEngine: this.imageSuperResolutionEngine,
      superResolutionTargetWidth: this.superResolutionDisplayTarget(index).width,
      superResolutionTargetHeight: this.superResolutionDisplayTarget(index).height,
      cropWhiteBorders: this.cropWhiteBorders,
      hdrPriority: Math.abs(this.visualIndexForPageIndex(index) - this.visualIndexForPageIndex(this.currentIndex)),
      translation: this.pageGroupAnchorForPageIndex(index) === this.currentIndex ?
        this.readerTranslationForPage(index) : null,
      allowEdgeSwipe: !this.swiperVertical,
      interactive: interactive,
      readerBackgroundColorValue: this.currentReaderBackgroundColor(),
      command: this.viewportCommand,
      commandVersion: this.viewportCommandVersion,
      onTap: (x: number, y: number, w: number, h: number) => {
        if (interactive && this.pageGroupAnchorForPageIndex(index) === this.currentIndex) {
          this.onTap(x, y, w, h);
        }
      },
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
        }
      },
      onZoomCommit: (percent: number) => {
        if (this.pageGroupAnchorForPageIndex(index) === this.currentIndex && this.isFixedScaleMode()) {
          this.fixedScale = Math.max(READER_MIN_SCALE, Math.min(READER_MAX_SCALE, percent / 100));
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
  private ReaderPairedPageGroup(index: number, key: string) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.readerLayoutHeight >= this.readerLayoutWidth) {
        ReaderPairedTransformViewport({ model: this.pairedImageModel }) {
          Column({ space: 0 }) {
            this.ReaderPageViewport(index, '100%', this.pairedPageDisplayExtent(index, index), false)
            this.ReaderPageViewport(index + 1, '100%', this.pairedPageDisplayExtent(index, index + 1), false)
          }
          .width(this.pairedCanvasWidth(index))
          .height(this.pairedCanvasHeight(index))
        }
      } else {
        ReaderPairedTransformViewport({ model: this.pairedImageModel }) {
          Row({ space: 0 }) {
            if (this.swiperReversed) {
              this.ReaderPageViewport(index + 1, this.pairedPageDisplayExtent(index, index + 1), '100%', false)
              this.ReaderPageViewport(index, this.pairedPageDisplayExtent(index, index), '100%', false)
            } else {
              this.ReaderPageViewport(index, this.pairedPageDisplayExtent(index, index), '100%', false)
              this.ReaderPageViewport(index + 1, this.pairedPageDisplayExtent(index, index + 1), '100%', false)
            }
          }
          .width(this.pairedCanvasWidth(index))
          .height(this.pairedCanvasHeight(index))
        }
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onAppear(() => {
      this.rememberMountedPairedPage(key);
      this.syncPairedViewport(index);
    })
    .onDisAppear(() => {
      // A data-source refresh can temporarily unmount this cached node without changing the active page group.
      this.forgetMountedPairedPage(key);
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.rememberMountedPairedPage(key);
      const width = Number.parseFloat(newArea.width.toString());
      const height = Number.parseFloat(newArea.height.toString());
      this.syncPairedViewport(index, width, height);
    })
    .draggable(false)
  }

  @Builder
  private ReaderPairedGestureOverlay() {
    Stack() {}
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .hitTestBehavior(HitTestMode.Transparent)
      .onTouch((event: TouchEvent) => {
        this.handlePairedOverlayTouch(event);
      })
      .gesture(
        GestureGroup(GestureMode.Parallel,
            LongPressGesture({ repeat: false })
              .onAction((event: GestureEvent) => {
                this.showImageActions(this.pairedPageIndexAt(this.currentIndex, event));
              }),
            PanGesture({ fingers: 1, distance: 3 })
              .onActionStart(() => {
                this.pairedImageModel.panStart();
                this.reportPairedViewportState(this.currentIndex);
              })
              .onActionUpdate((event: GestureEvent) => {
                this.pairedImageModel.panUpdate(event.offsetX, event.offsetY);
                this.reportPairedViewportState(this.currentIndex);
              })
              .onActionEnd((event: GestureEvent) => {
                const edgeDirection = this.pairedImageModel.edgeSwipeDirection(
                  event.offsetX,
                  event.velocityX,
                  event.offsetY,
                  event.velocityY
                );
                this.getUIContext().animateTo({ duration: READER_INERTIA_DURATION, curve: Curve.EaseOut }, () => {
                  this.pairedImageModel.panEnd(event.velocityX, event.velocityY);
                  this.reportPairedViewportState(this.currentIndex);
                });
                if (edgeDirection !== 0) {
                  this.jumpByVisualDirection(edgeDirection);
                }
              })
              .onActionCancel(() => {
                this.getUIContext().animateTo({ duration: READER_INERTIA_DURATION, curve: Curve.EaseOut }, () => {
                  this.pairedImageModel.panEnd();
                  this.reportPairedViewportState(this.currentIndex);
                });
              }),
            PinchGesture({ fingers: 2, distance: 1 })
              .onActionStart((event: GestureEvent) => {
                this.pairedImageModel.pinchStart(event.pinchCenterX, event.pinchCenterY);
                this.reportPairedViewportState(this.currentIndex);
              })
              .onActionUpdate((event: GestureEvent) => {
                this.pairedImageModel.pinchUpdate(event.scale, event.pinchCenterX, event.pinchCenterY);
                this.reportPairedViewportState(this.currentIndex);
              })
              .onActionEnd(() => {
                this.pairedImageModel.pinchEnd();
                this.reportPairedViewportState(this.currentIndex);
              })
              .onActionCancel(() => {
                this.pairedImageModel.pinchEnd();
                this.reportPairedViewportState(this.currentIndex);
              })
        )
      )
      .onGestureJudgeBegin((gestureInfo: GestureInfo, event: BaseGestureEvent) => {
        if (!this.pairedGestureReady()) {
          return GestureJudgeResult.REJECT;
        }
        if (gestureInfo.type === GestureControl.GestureType.DRAG) {
          return GestureJudgeResult.REJECT;
        }
        if (gestureInfo.type === GestureControl.GestureType.PAN_GESTURE &&
          this.shouldLetSwiperHandlePairedPan(event)) {
          return GestureJudgeResult.REJECT;
        }
        return GestureJudgeResult.CONTINUE;
      })
      .draggable(false)
      .zIndex(3)
  }

  @Builder
  private ReaderPageGroup(index: number, paired: boolean, key: string) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.shouldRenderPageGroup(index)) {
        if (paired) {
          this.ReaderPairedPageGroup(index, key)
        } else {
          this.ReaderPageViewport(index, '100%', '100%')
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.currentReaderBackgroundColor())
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isContinuousVerticalMode()) {
        List({
          space: 0,
          scroller: this.continuousScroller,
          initialIndex: this.visualIndexForPageIndex(this.currentIndex)
        }) {
          LazyForEach(this.readerPageIndexSource(), (item: ReaderPageGroupItem) => {
            ListItem() {
              ReaderContinuousImageItem({
                page: this.pageForIndex(item.index),
                statusText: item.index === this.pageIndex ? this.statusText : uiText('Image page is loading'),
                preferOriginal: this.preferOriginal,
                fitMode: this.fitMode,
                zoomScale: this.fixedScale,
                command: this.viewportCommand,
                commandVersion: this.viewportCommandVersion,
                sharedOffsetX: this.continuousOffsetX,
                isActive: item.index === this.currentIndex,
                hdrEnabled: this.sdrToHdrEnabled &&
                  Math.abs(item.index - this.currentIndex) <= this.readerContinuousCacheCount(),
                imageAdjustmentSettings: this.imageAdjustmentSettings,
                superResolutionEnabled: this.imageSuperResolutionEnabled &&
                  Math.abs(item.index - this.currentIndex) <= this.readerContinuousCacheCount(),
                superResolutionEngine: this.imageSuperResolutionEngine,
                superResolutionTargetWidth: this.superResolutionDisplayTarget(item.index).width,
                superResolutionTargetHeight: this.superResolutionDisplayTarget(item.index).height,
                cropWhiteBorders: this.cropWhiteBorders &&
                  Math.abs(item.index - this.currentIndex) <= this.readerContinuousCacheCount(),
                hdrPriority: Math.abs(item.index - this.currentIndex),
                translation: item.index === this.currentIndex ? this.readerTranslationForPage(item.index) : null,
                readerBackgroundColorValue: this.currentReaderBackgroundColor(),
                onTap: () => {},
                onRetry: () => {
                  this.onJump(item.index);
                },
                onImageLongPress: () => {
                  this.currentIndex = item.index;
                  this.showImageActions(item.index);
                },
                onImageSizeChange: (width: number, height: number) => {
                  this.rememberPageImageSize(item.index, width, height);
                  if (item.index === this.currentIndex) {
                    this.onActiveImageSizeChange(width, height);
                  }
                },
                onZoomChange: (percent: number) => {
                  this.zoomPercent = percent;
                },
                onZoomCommit: (percent: number) => {
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
        .backgroundColor(this.currentReaderBackgroundColor())
        .scrollBar(BarState.Off)
        .cachedCount(this.readerContinuousCacheCount())
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .onScrollIndex((first: number) => {
          this.onContinuousScrollIndex(first);
        })
      } else {
        Swiper(this.swiperController) {
          LazyForEach(this.readerPageIndexSource(), (item: ReaderPageGroupItem) => {
            // Each Swiper child is one screen. A paired child renders two physical pages.
            this.ReaderPageGroup(item.index, item.paired, item.key)
          }, (item: ReaderPageGroupItem) => item.key)
        }
        .index(this.visualIndexForPageIndex(this.currentIndex))
        .cachedCount(this.readerRenderScreenCacheCount())
        .indicator(false)
        .loop(false)
        .autoPlay(false)
        .vertical(false)
        .displayCount(1)
        .itemSpace(0)
        .prevMargin(0)
        .nextMargin(0)
        .duration(isHarmonyUiStyle() ? 220 : 180)
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
        .backgroundColor(this.currentReaderBackgroundColor())
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

      if (!this.isContinuousVerticalMode()) {
        this.ReaderPairedGestureOverlay()
      } else {
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
      }

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
          menuReaderPreset: $menuReaderPreset,
          menuReaderPresetSelected: $menuReaderPresetSelected,
          menuReaderPresetCustom: $menuReaderPresetCustom,
          menuReaderPresetEditName: $menuReaderPresetEditName,
          selectedTab: $menuSettingsTab,
          readerPresetOptions: $menuReaderPresetOptions,
          menuScreenRotation: this.menuScreenRotation,
          menuReadingDirection: this.menuReadingDirection,
          menuPageScaling: this.menuPageScaling,
          menuTheme: this.menuTheme,
          menuReaderBackground: this.menuReaderBackground,
          menuAdaptiveDualPage: this.menuAdaptiveDualPage,
          menuCropWhiteBorders: this.menuCropWhiteBorders,
          menuImageSuperResolution: this.menuImageSuperResolutionEnabled,
          menuImageSuperResolutionEngine: this.menuImageSuperResolutionEngine,
          menuSdrToHdrEnabled: this.menuSdrToHdrEnabled,
          menuMoireReduction: this.menuImageAdjustmentSettings.moireReduction,
          menuImageAdjustmentEnabled: this.menuImageAdjustmentSettings.enabled,
          menuImageContrast: this.menuImageAdjustmentSettings.contrast,
          menuImageClarity: this.menuImageAdjustmentSettings.clarity,
          menuImageSharpening: this.menuImageAdjustmentSettings.sharpening,
          menuImageExposure: this.menuImageAdjustmentSettings.exposure,
          menuImageBrightness: this.menuImageAdjustmentSettings.brightness,
          menuImageHighlights: this.menuImageAdjustmentSettings.highlights,
          menuImageShadows: this.menuImageAdjustmentSettings.shadows,
          menuImageHue: this.menuImageAdjustmentSettings.hue,
          menuImageSaturation: this.menuImageAdjustmentSettings.saturation,
          menuImageVibrance: this.menuImageAdjustmentSettings.vibrance,
          menuImageTemperature: this.menuImageAdjustmentSettings.temperature,
          menuImageGrayscale: this.menuImageAdjustmentSettings.grayscale,
          menuStartPosition: this.menuStartPosition,
          menuAutoTransferTime: this.menuAutoTransferTime,
          menuKeepScreenOn: this.menuKeepScreenOn,
          menuShowBattery: this.menuShowBattery,
          batteryText: this.batteryText(),
          menuReadingFullscreen: this.menuReadingFullscreen,
          menuVolumePage: this.menuVolumePage,
          menuReverseVolumePage: this.menuReverseVolumePage,
          menuComicTranslation: this.menuComicTranslation,
          menuAiTranslation: this.menuAiTranslation,
          menuCustomBrightness: this.menuCustomBrightness,
          menuBrightnessLevel: this.menuBrightnessLevel,
          menuUltraDarkMode: this.menuUltraDarkMode,
          menuUltraDarkBrightness: this.menuUltraDarkBrightness,
          screenRotationOptions: this.readerMenuScreenRotationOptions(),
          readingDirectionOptions: this.readerMenuReadingDirectionOptions(),
          pageScalingOptions: this.readerMenuPageScalingOptions(),
          superResolutionEngineOptions: readerSuperResolutionEngineOptions(),
          onDismiss: () => {
            this.hideMenu();
          },
          onBack: () => {
            this.hideMenu();
          },
          onReaderPresetChange: (value: string) => {
            this.onMenuReaderPresetChange(value);
          },
          onCreateReaderPreset: (name: string) => {
            this.createMenuReaderPreset(name);
          },
          onSaveReaderPreset: () => {
            this.saveMenuReaderPreset();
          },
          onRenameReaderPreset: (name: string) => {
            this.renameMenuReaderPreset(name);
          },
          onDeleteReaderPreset: () => {
            this.deleteMenuReaderPreset();
          },
          onSelectedTabChange: (value: number) => {
            this.menuSettingsTab = Math.max(0, Math.min(3, Math.round(value)));
            ehSettingsStore.setValue('reader_settings_tab', this.menuSettingsTab.toString());
          },
          onScreenRotationChange: (value: string) => {
            this.menuScreenRotation = value;
            this.markMenuReaderPresetCustom();
          },
          onReadingDirectionChange: (value: string) => {
            this.onMenuReadingDirectionChange(value);
          },
          onPageScalingChange: (value: string) => {
            this.menuPageScaling = value;
            this.markMenuReaderPresetCustom();
          },
          onThemeChange: (value: string) => {
            this.applyMenuTheme(value);
          },
          onReaderBackgroundChange: (value: string) => {
            this.applyMenuReaderBackground(value);
          },
          onAdaptiveDualPageChange: (value: boolean) => {
            this.onMenuAdaptiveDualPageChange(value);
          },
          onCropWhiteBordersChange: (value: boolean) => {
            this.menuCropWhiteBorders = value;
            this.markMenuReaderPresetCustom();
          },
          onImageSuperResolutionChange: (value: boolean) => {
            this.onMenuImageSuperResolutionChange(value);
          },
          onImageSuperResolutionEngineChange: (value: string) => {
            this.onMenuImageSuperResolutionEngineChange(value);
          },
          onSdrToHdrChange: (value: boolean) => {
            this.onMenuSdrToHdrChange(value);
          },
          onMoireReductionChange: (value: string) => {
            this.menuImageAdjustmentSettings.moireReduction = value;
            this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.markMenuReaderPresetCustom();
          },
          onImageAdjustmentEnabledChange: (value: boolean) => {
            this.menuImageAdjustmentSettings.enabled = value;
            this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.markMenuReaderPresetCustom();
          },
          onImageContrastChange: (value: number) => {
            this.menuImageAdjustmentSettings.contrast = Math.round(value);
            this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.markMenuReaderPresetCustom();
          },
          onImageClarityChange: (value: number) => {
            this.menuImageAdjustmentSettings.clarity = Math.round(value);
            this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.markMenuReaderPresetCustom();
          },
          onImageSharpeningChange: (value: number) => {
            this.menuImageAdjustmentSettings.sharpening = Math.round(value);
            this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.markMenuReaderPresetCustom();
          },
          onImageExposureChange: (value: number) => {
            this.menuImageAdjustmentSettings.exposure = Math.round(value);
            this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.markMenuReaderPresetCustom();
          },
          onImageBrightnessChange: (value: number) => {
            this.menuImageAdjustmentSettings.brightness = Math.round(value);
            this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.markMenuReaderPresetCustom();
          },
          onImageHighlightsChange: (value: number) => {
            this.menuImageAdjustmentSettings.highlights = Math.round(value);
            this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.markMenuReaderPresetCustom();
          },
          onImageShadowsChange: (value: number) => {
            this.menuImageAdjustmentSettings.shadows = Math.round(value);
            this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.markMenuReaderPresetCustom();
          },
          onImageHueChange: (value: number) => {
            this.menuImageAdjustmentSettings.hue = Math.round(value);
            this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.markMenuReaderPresetCustom();
          },
          onImageSaturationChange: (value: number) => {
            this.menuImageAdjustmentSettings.saturation = Math.round(value);
            this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.markMenuReaderPresetCustom();
          },
          onImageVibranceChange: (value: number) => {
            this.menuImageAdjustmentSettings.vibrance = Math.round(value);
            this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.markMenuReaderPresetCustom();
          },
          onImageTemperatureChange: (value: number) => {
            this.menuImageAdjustmentSettings.temperature = Math.round(value);
            this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.markMenuReaderPresetCustom();
          },
          onImageGrayscaleChange: (value: number) => {
            this.menuImageAdjustmentSettings.grayscale = Math.round(value);
            this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.markMenuReaderPresetCustom();
          },
          onResetImageAdjustments: () => {
            resetReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.menuImageAdjustmentSettings = cloneReaderImageAdjustmentSettings(this.menuImageAdjustmentSettings);
            this.markMenuReaderPresetCustom();
          },
          onStartPositionChange: (value: string) => {
            this.menuStartPosition = value;
            this.markMenuReaderPresetCustom();
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
          onReverseVolumePageChange: (value: boolean) => {
            this.menuReverseVolumePage = value;
          },
          onComicTranslationChange: (value: boolean) => {
            this.menuComicTranslation = value;
          },
          onAiTranslationChange: (value: boolean) => {
            this.menuAiTranslation = value;
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
            .fontColor([uiMaterialForegroundColor(Color.White)])
        }
        .width(READER_TRANSLATION_BUTTON_SIZE)
        .height(READER_TRANSLATION_BUTTON_SIZE)
        .backgroundColor(uiMaterialBackground(this.comicTranslationActive ? '#167A9A' : '#34454D'))
        .systemMaterial(this.comicTranslationActive ? uiTintedButtonMaterial('#167A9A') : uiButtonMaterial())
        .border({
          width: this.comicTranslationActive ? 2 : 1,
          color: this.comicTranslationActive ? Color.White : 'rgba(255,255,255,0.42)'
        })
        .opacity(this.comicTranslationActive ? 0.96 : 0.78)
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
    .focusable(true)
    .defaultFocus(true)
    .focusOnTouch(true)
    .onKeyEvent((event: KeyEvent): boolean => {
      return this.handleReaderKeyEvent(event);
    })
    .onAxisEvent((event: AxisEvent) => {
      this.handleReaderAxisEvent(event);
    })
    .onMouse((event: MouseEvent) => {
      this.handleReaderMouseEvent(event);
    })
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
        this.resetPairedViewport();
        this.normalizeCurrentPageGroup();
        this.syncReaderPageIndexSource();
        this.syncComicTranslationButtonPosition();
        this.syncImageProcessingPrefetch();
        this.syncPairedViewport(this.currentIndex);
      }
    })
    .backgroundColor(this.currentReaderBackgroundColor())
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
