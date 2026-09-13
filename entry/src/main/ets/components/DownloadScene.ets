import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import { fileUri, picker } from '@kit.CoreFileKit';
import {
  GalleryCategory,
  GalleryDetail,
  GalleryInfo,
  GalleryRoute,
} from '../model/GalleryModels';
import {
  DOWNLOAD_LOCATION_APP_FILES,
  DOWNLOAD_LOCATION_DOWNLOADS,
  ehDownloadFileStore,
} from '../services/EhDownloadFileStore';
import { ehDownloadManager } from '../services/EhDownloadManager';
import { FloatingActionSideController } from '../services/EhFloatingActionSideSupport';
import { BrowsePosition, ehBrowsePositionStore } from '../services/EhBrowsePositionStore';
import { ehSearchHistoryStore } from '../services/EhSearchHistoryStore';
import { DownloadInfo, DownloadLabel, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
import {
  FLOATING_ACTION_HOLDING_HAND_REVISION_KEY,
  FLOATING_ACTION_SIDE_REVISION_KEY,
  TRANSLATION_BUTTONS_VISIBLE_KEY,
  ehSettingsStore,
} from '../services/EhSettingsStore';
import {
  TRANSLATION_ENABLED_KEY,
  ehTranslationService,
  translationPriorityForIndex,
} from '../services/EhTranslationService';
import {
  DownloadRestoreResult,
  DownloadZipImportResult,
  restoreDownloadedItemsAndArchives,
} from '../services/DownloadZipImportService';
import {
  confirmCellularNetworkWarningForSession,
  shouldConfirmCellularNetworkOperation,
} from '../services/EhCellularNetworkGuard';
import { DEFAULT_ADVANCE_SEARCH, EhUrl, ListMode } from '../services/EhUrl';
import { galleryMatchesLocalSearch, LocalGallerySearchOptions } from '../services/LocalGallerySearch';
import { DetailSearchRequest } from '../services/GalleryDetailSupport';
import {
  createEmptyGalleryDetailLink,
  createGalleryDetailLink,
  createGalleryDetailLinkFromGallery,
  GalleryDetailLink,
  initialDetailForLink,
} from '../services/GalleryDetailSupport';
import {
  applyAppChromeImmersiveMode,
  isEmbeddedReaderActive,
  leaveEmbeddedReaderFullscreen,
  mainContentWidthFallbackVp,
  rememberMainContentWidthVp,
} from '../services/EhWindowImmersive';
import {
  peekPendingContinuationSnapshot,
  takePendingContinuationSnapshot,
} from '../services/DistributedContinuationService';
import { readerSessionStore } from '../services/ReaderSessionStore';
import { LANGUAGE_REVISION_KEY, STATUS_BAR_HEIGHT_KEY, nextFloatingToolbarOffset, runDetailBackHandler, setActiveBackHandler } from '../shared/EhShared';
import { sortedStringKey, toggleStringValue } from '../shared/EhShared';
import { GalleryCardScrollAnchor } from '../shared/GalleryCardScrollAnchor';
import {
  galleryListColumnCount,
  galleryListColumnsTemplate,
  galleryListHorizontalPadding,
  galleryListTopInset,
  galleryListViewportHeight,
} from '../shared/AdaptiveGalleryListLayout';
import {
  cloneGalleryDetail,
  cloneGalleryInfo,
  createEmptyDetail,
  currentGallerySite,
  defaultDownloadLabelChoice,
  downloadProgressText,
  downloadSizeText,
  DOWNLOAD_STATUS_FILTER_OPTIONS,
  filterDownloadItems,
  galleryDetailCardPreferredWidth,
  galleryListMode,
  galleryThumbnailPreferredColumnWidth,
  getAbilityContext,
  saveDefaultDownloadLabelChoice,
  uiText,
  uiStatusText,
} from '../shared/EhShared';
import {
  themeAccentTextColor,
  themeFieldBackground,
  themeOnPrimaryText,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeShadowColor,
  themeSurface,
  themeTertiaryText,
} from '../shared/EhTheme';
import {
  uiAdaptiveToolbarHeight,
  uiButtonMaterial,
  uiTransparentButtonBackgroundEffect,
  uiListGap,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiRadius,
  uiSearchFieldHeight,
} from '../shared/EhUiStyle';
import { GalleryHomeNavBarHost, GalleryToolbarOffset, GalleryToolbarOffsetBinding } from './GalleryNavHosts';
import { PopupScrim } from './PopupScrim';
import { GalleryListRow, GalleryThumbCard } from './GalleryCards';
import { GalleryListScene } from './GalleryScenes';
import { GalleryDetailHostScene } from './GalleryDetailHostScene';
import { ReaderSessionScene } from './ReaderHostScene';
import { BlockingBusyOverlay } from './BlockingBusyOverlay';
import {
  DOWNLOAD_LABEL_FILTER_ALL,
  DOWNLOAD_LABEL_OPTION_ASK,
  DownloadLabelDrawer,
  DownloadLabelEditDialog,
  DownloadLabelManagerScene,
  DownloadLabelSelectionDialog,
} from './DownloadLabelComponents';
import {
  RightSidePanelLayer,
  SIDE_PANEL_WIDTH,
  sidePanelLeft,
  shouldOpenSidePanel,
} from './SidePanelComponents';
import {
  applyTagSuggestionToKeyword,
  buildSearchSuggestions,
  FloatingActionDock,
  normalizeSubmittedSearchKeyword,
  recordSearchHistory,
  SearchActionColumn,
  SearchAdvancedPanel,
  SearchSuggestionItem,
  SearchSuggestionList,
  SearchSummaryStrip,
} from './GallerySearchScenes';
import {
  FLOATING_ACTION_SIDE_RIGHT,
  floatingActionAvailableHeight,
} from './FloatingActionLayoutSupport';
import {
  areaDimensionToVp,
  markCurrentRouteRightPane,
  normalizeSplitPaneFocus,
  saveSplitPaneRatio,
  SPLIT_PANE_BREAKPOINT,
  SPLIT_PANE_FOCUS_LEFT,
  SPLIT_PANE_FOCUS_RIGHT,
  SPLIT_PANE_RATIO_REVISION_KEY,
  shouldFadeRestoredRightPane,
  splitPaneCurrentRatio,
  SplitPaneDivider,
  splitPaneListWidth,
  splitPaneModeEnabled,
  splitPaneRatioForWidth,
  splitPaneSideWidth,
  splitPaneWidthFromDrag,
  shouldUpdateSplitPaneFocus,
} from './SplitPaneSupport';

import {
  DownloadStatusFilterOverlay,
  DownloadToolColumn,
  DownloadCardStatus,
  DownloadCardState,
} from './DownloadComponents';

function normalizeSceneScrollOffset(offset: number): number {
  if (offset <= 1 || Number.isNaN(offset)) {
    return 0;
  }
  return offset;
}

async function pickDownloadDirectoryRoot(context: common.UIAbilityContext): Promise<string> {
  try {
    const saveOptions = new picker.DocumentSaveOptions();
    saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
    const documentPicker = new picker.DocumentViewPicker(context);
    const result = await documentPicker.save(saveOptions);
    if (result.length === 0 || result[0].length === 0) {
      return '';
    }
    return new fileUri.FileUri(result[0]).path;
  } catch (error) {
    return '';
  }
}

function normalizeDownloadSceneLocation(value: string): string {
  return value === DOWNLOAD_LOCATION_DOWNLOADS ? DOWNLOAD_LOCATION_DOWNLOADS : DOWNLOAD_LOCATION_APP_FILES;
}

const DOWNLOAD_PAGE_PROGRESS_SCALE: number = 1000;
const DOWNLOAD_JUMP_PAGE_SIZE: number = 25;

interface DownloadNavigationCache {
  activeSplitPane: string;
  showDetail: boolean;
  restoreDetailWithFade: boolean;
  detailLink: GalleryDetailLink;
  detail: GalleryDetail;
  detailRequestUrl: string;
  showTagSearch: boolean;
  tagSearchTitle: string;
  tagSearchKeyword: string;
  tagSearchMode: ListMode;
  tagSearchCategory?: number;
  tagSearchImagePath: string;
  tagSearchImageUseSimilarity: boolean;
  tagSearchImageOnlyCovers: boolean;
  tagSearchImageShowExpunged: boolean;
}

let downloadNavigationCache: DownloadNavigationCache | null = null;

function cloneDownloadDetailLink(link: GalleryDetailLink): GalleryDetailLink {
  return {
    gid: link.gid,
    token: link.token,
    url: link.url,
    referer: link.referer,
    site: link.site,
    seed: cloneGalleryInfo(link.seed)
  };
}


@Component
export struct DownloadScene {
  private unsubscribeStore: () => void = () => {};
  private unsubscribeDownloadManager: () => void = () => {};
  @Prop @Watch('onResetVersionChanged') resetVersion: number = 0;
  onMenu: () => void = () => {};

  @State items: DownloadInfo[] = [];
  @State labels: DownloadLabel[] = [];
  @State visibleItems: DownloadInfo[] = [];
  @State selectedDownloadLabel: string = DOWNLOAD_LABEL_FILTER_ALL;
  @State downloadLabelDrawerVisible: boolean = false;
  @State downloadLabelDrawerOffsetX: number = SIDE_PANEL_WIDTH;
  @State downloadLabelDrawerOverlayOpacity: number = 0;
  @State downloadLabelManagerVisible: boolean = false;
  @State defaultDownloadLabelDialogVisible: boolean = false;
  @State moveDownloadLabelDialogVisible: boolean = false;
  @State downloadLabelEditDialogVisible: boolean = false;
  @State downloadLabelEditValue: string = '';
  @State query: string = '';
  @State searchMode: ListMode = ListMode.Normal;
  @State searchCategory: number = GalleryCategory.None;
  @State advancedSearchEnabled: boolean = false;
  @State advanceSearch: number = DEFAULT_ADVANCE_SEARCH;
  @State minRating: number = -1;
  @State searchSubmitted: boolean = true;
  @State searchBarVisible: boolean = false;
  @State advancedPanelVisible: boolean = false;
  @State advancedPopupHeight: number = 0;
  @State searchSuggestionItems: SearchSuggestionItem[] = [];
  @State searchSuggestionRevision: number = 0;
  @State selectedTagNamespaces: string[] = [];
  @State statusFilters: string[] = DOWNLOAD_STATUS_FILTER_OPTIONS.slice();
  @State statusFilterDraft: string[] = DOWNLOAD_STATUS_FILTER_OPTIONS.slice();
  @State statusFilterPanelVisible: boolean = false;
  @State sortMode: string = 'Default';
  @State categoryFilter: string = 'All';
  @State statusText: string = 'Downloads: idle';
  @State showDetail: boolean = false;
  @State detailLink: GalleryDetailLink = createEmptyGalleryDetailLink();
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailRequestUrl: string = '';
  @State showReader: boolean = false;
  private readerClosing: boolean = false;
  @State restoreDetailWithFade: boolean = false;
  @State showTagSearch: boolean = false;
  @State tagSearchTitle: string = 'Search';
  @State tagSearchKeyword: string = '';
  @State tagSearchMode: ListMode = ListMode.Tag;
  @State tagSearchCategory: number = GalleryCategory.None;
  @State tagSearchImagePath: string = '';
  @State tagSearchImageUseSimilarity: boolean = false;
  @State tagSearchImageOnlyCovers: boolean = false;
  @State tagSearchImageShowExpunged: boolean = false;
  @State downloadContentWidth: number = 0;
  @State sceneContentWidth: number = 0;
  @State splitListRatio: number = splitPaneCurrentRatio();
  @State splitDragging: boolean = false;
  @State activeSplitPane: string = SPLIT_PANE_FOCUS_LEFT;
  @State selectedDownloadGids: string = '';
  private toolbarOffsetY: number = 0;
  @State private toolbarOffsetBinding: GalleryToolbarOffsetBinding = new GalleryToolbarOffsetBinding();
  private lastToolbarScrollOffset: number = 0;
  private toolbarRestoring: boolean = false;

  private toolbarState(): GalleryToolbarOffset {
    return this.toolbarOffsetBinding.state();
  }

  private syncToolbarOffsetState(): void {
    this.toolbarOffsetBinding.set(this.toolbarOffsetY);
  }
  @State downloadActionsExpanded: boolean = false;
  @State floatingActionSide: string = FLOATING_ACTION_SIDE_RIGHT;
  @State statusHintText: string = '';
  @State statusHintVisible: boolean = false;
  @State blockingBusyVisible: boolean = false;
  @State blockingBusyMessage: string = 'Loading...';
  @State downloadJumpPanelVisible: boolean = false;
  @State downloadJumpPopupHeight: number = 0;
  @State downloadJumpDraft: string = '1';
  @State downloadJumpPageIndex: number = 0;
  @State viewportHeight: number = 0;
  @State translationVisibleStart: number = -1;
  @State translationVisibleEnd: number = -1;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  @StorageProp(SPLIT_PANE_RATIO_REVISION_KEY) @Watch('onSplitPaneRatioRevisionChange') splitPaneRatioRevision: number = 0;
  @StorageLink(TRANSLATION_ENABLED_KEY) translationEnabled: boolean = false;
  @StorageProp(TRANSLATION_BUTTONS_VISIBLE_KEY) translationButtonsVisible: boolean = true;
  @StorageProp(FLOATING_ACTION_HOLDING_HAND_REVISION_KEY) @Watch('onHoldingHandSettingChanged')
  holdingHandSettingRevision: number = 0;
  @StorageProp(FLOATING_ACTION_SIDE_REVISION_KEY) @Watch('onFloatingActionSideSettingChanged')
  floatingActionSideRevision: number = 0;
  private downloadScroller: Scroller = new Scroller();
  private cardScrollAnchor: GalleryCardScrollAnchor = new GalleryCardScrollAnchor();
  private splitDragStartWidth: number = 0;
  private downloadScrollOffset: number = 0;
  private downloadFirstVisibleIndex: number = 0;
  private downloadBrowsePositionLoaded: boolean = false;
  private downloadBrowsePositionRestored: boolean = false;
  private restoringDownloadBrowsePosition: boolean = false;
  private floatingActionSideController: FloatingActionSideController = new FloatingActionSideController(
    (side: string): void => {
      this.animateFloatingActionSide(side);
    });
  private cellularWarningDialogOpen: boolean = false;
  private deleteConfirmationDialogOpen: boolean = false;
  private downloadCardStates: Map<number, DownloadCardState> = new Map<number, DownloadCardState>();
  private translationVisibleItems: number[] = [];

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    this.restoreEmbeddedContinuationIfPresent();
    this.floatingActionSideController.syncFromSettings();
    this.restoreNavigationCache();
    this.syncSceneContentWidthFromWindow();
    this.syncDownloadContentWidthFromWindow();
    markCurrentRouteRightPane(this.useSplitLayout());
    setActiveBackHandler(() => this.handleSystemBack());
    this.unsubscribeStore = ehDownloadStore.subscribe((items: DownloadInfo[], labels: DownloadLabel[]) => {
      this.items = items;
      this.labels = labels;
      if (this.selectedDownloadLabel !== DOWNLOAD_LABEL_FILTER_ALL && this.selectedDownloadLabel.length > 0 &&
        !ehDownloadStore.hasLabel(this.selectedDownloadLabel)) {
        this.selectedDownloadLabel = DOWNLOAD_LABEL_FILTER_ALL;
      }
      this.refreshDownloadRows();
    });
    this.unsubscribeDownloadManager = ehDownloadManager.subscribe((status: string) => {
      this.statusText = status;
    });
    this.refreshSearchSuggestions();
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSearchHistoryStore.load(context).then(() => {
        this.refreshSearchSuggestions();
      }).catch(() => {});
    }
    this.prepareDownloadBrowsePosition();
    this.loadDownloads();
    setTimeout(() => {
      this.syncSceneContentWidthFromWindow();
      this.syncDownloadContentWidthFromWindow();
    }, 0);
  }

  aboutToDisappear(): void {
    this.rememberDownloadScrollOffset();
    ehBrowsePositionStore.flush();
    this.cardScrollAnchor.clear();
    this.saveNavigationCache();
    this.unsubscribeStore();
    this.unsubscribeDownloadManager();
    this.floatingActionSideController.dispose();
  }

  onResetVersionChanged(): void {
    this.resetToTopLevel();
  }

  private handleSystemBack(): boolean {
    if (this.downloadLabelEditDialogVisible) {
      this.downloadLabelEditDialogVisible = false;
      return true;
    }
    if (this.defaultDownloadLabelDialogVisible) {
      this.defaultDownloadLabelDialogVisible = false;
      return true;
    }
    if (this.moveDownloadLabelDialogVisible) {
      this.moveDownloadLabelDialogVisible = false;
      return true;
    }
    if (this.downloadLabelManagerVisible) {
      this.closeDownloadLabelManager();
      return true;
    }
    if (this.downloadLabelDrawerVisible) {
      this.closeDownloadLabelDrawer();
      return true;
    }
    if (this.statusFilterPanelVisible) {
      this.closeDownloadStatusPanel();
      return true;
    }
    if (this.advancedPanelVisible) {
      this.closeAdvancedPanel();
      return true;
    }
    if (this.downloadJumpPanelVisible) {
      this.downloadJumpPanelVisible = false;
      return true;
    }
    if (this.showReader) {
      this.closeEmbeddedReader();
      return true;
    }
    if (this.useSplitLayout() && this.activeSplitPane === SPLIT_PANE_FOCUS_RIGHT && this.showDetail) {
      if (runDetailBackHandler()) {
        return true;
      }
      this.closeDetail();
      return true;
    }
    if (this.downloadSelectionCount() > 0) {
      this.clearDownloadSelection();
      return true;
    }
    if (this.searchBarVisible) {
      this.closeDownloadSearchBar();
      return true;
    }
    if (this.showTagSearch) {
      this.closeTagSearch();
      return true;
    }
    if (this.showDetail) {
      if (runDetailBackHandler()) {
        return true;
      }
      this.closeDetail();
      return true;
    }
    return false;
  }

  private resetToTopLevel(): void {
    if (this.showReader) {
      leaveEmbeddedReaderFullscreen();
    }
    this.clearDownloadSelection();
    this.searchBarVisible = false;
    this.advancedPanelVisible = false;
    this.downloadActionsExpanded = false;
    this.statusFilterPanelVisible = false;
    this.downloadLabelDrawerVisible = false;
    this.downloadLabelDrawerOffsetX = SIDE_PANEL_WIDTH;
    this.downloadLabelDrawerOverlayOpacity = 0;
    this.downloadLabelManagerVisible = false;
    this.defaultDownloadLabelDialogVisible = false;
    this.moveDownloadLabelDialogVisible = false;
    this.downloadLabelEditDialogVisible = false;
    this.downloadJumpPanelVisible = false;
    this.showTagSearch = false;
    this.showReader = false;
    this.showDetail = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
    this.restoreDetailWithFade = false;
    this.syncDownloadContentWidthForCurrentLayout();
    this.detailLink = createEmptyGalleryDetailLink();
    this.detail = createEmptyDetail();
    this.detailRequestUrl = '';
    this.tagSearchTitle = 'Search';
    this.tagSearchKeyword = '';
    this.tagSearchMode = ListMode.Tag;
    this.tagSearchCategory = GalleryCategory.None;
    this.tagSearchImagePath = '';
    this.tagSearchImageUseSimilarity = false;
    this.tagSearchImageOnlyCovers = false;
    this.tagSearchImageShowExpunged = false;
    this.restoreBackHandler();
    this.clearNavigationCache();
  }

  private toggleAdvancedPanel(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
      this.advancedPanelVisible = !this.advancedPanelVisible;
    });
  }

  private closeAdvancedPanel(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
      this.advancedPanelVisible = false;
    });
  }

  private restoreNavigationCache(): void {
    if (downloadNavigationCache === null) {
      return;
    }
    const cache = downloadNavigationCache;
    this.showDetail = cache.showDetail;
    this.activeSplitPane = normalizeSplitPaneFocus(cache.activeSplitPane, cache.showDetail);
    this.restoreDetailWithFade = cache.showDetail && shouldFadeRestoredRightPane();
    this.detailLink = cloneDownloadDetailLink(cache.detailLink);
    this.detail = cloneGalleryDetail(cache.detail);
    this.detailRequestUrl = cache.detailRequestUrl;
    this.showTagSearch = cache.showTagSearch;
    this.tagSearchTitle = cache.tagSearchTitle;
    this.tagSearchKeyword = cache.tagSearchKeyword;
    this.tagSearchMode = cache.tagSearchMode;
    this.tagSearchCategory = cache.tagSearchCategory === undefined ? GalleryCategory.None : cache.tagSearchCategory;
    this.tagSearchImagePath = cache.tagSearchImagePath;
    this.tagSearchImageUseSimilarity = cache.tagSearchImageUseSimilarity;
    this.tagSearchImageOnlyCovers = cache.tagSearchImageOnlyCovers;
    this.tagSearchImageShowExpunged = cache.tagSearchImageShowExpunged;
  }

  private saveNavigationCache(): void {
    downloadNavigationCache = {
      activeSplitPane: this.activeSplitPane,
      showDetail: this.showDetail,
      restoreDetailWithFade: this.restoreDetailWithFade,
      detailLink: cloneDownloadDetailLink(this.detailLink),
      detail: cloneGalleryDetail(this.detail),
      detailRequestUrl: this.detailRequestUrl,
      showTagSearch: this.showTagSearch,
      tagSearchTitle: this.tagSearchTitle,
      tagSearchKeyword: this.tagSearchKeyword,
      tagSearchMode: this.tagSearchMode,
      tagSearchCategory: this.tagSearchCategory,
      tagSearchImagePath: this.tagSearchImagePath,
      tagSearchImageUseSimilarity: this.tagSearchImageUseSimilarity,
      tagSearchImageOnlyCovers: this.tagSearchImageOnlyCovers,
      tagSearchImageShowExpunged: this.tagSearchImageShowExpunged
    };
  }

  private clearNavigationCache(): void {
    downloadNavigationCache = null;
  }

  private clearDownloadSelection(): void {
    this.selectedDownloadGids = '';
    this.downloadActionsExpanded = false;
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  private floatingToolbarHeight(): number {
    return this.statusBarVp() + uiAdaptiveToolbarHeight(this.downloadContentWidth);
  }

  private toolbarVisibleHeight(): number {
    return Math.max(0, Math.min(this.floatingToolbarHeight(), this.floatingToolbarHeight() + this.toolbarOffsetY));
  }

  private downloadContentStartOffset(): number {
    return galleryListTopInset(this.floatingToolbarHeight());
  }

  private downloadListViewportHeight(): number {
    return galleryListViewportHeight(this.viewportHeight);
  }

  private advancedPanelMaxHeight(): number {
    if (this.viewportHeight <= 0) {
      return 520;
    }
    return Math.max(360, this.viewportHeight - this.floatingToolbarHeight() - 28);
  }

  private downloadToolActionsMaxHeight(): number {
    const reservedTop = this.statusBarVp() + uiAdaptiveToolbarHeight(this.downloadContentWidth) + 8;
    return floatingActionAvailableHeight(this.viewportHeight, reservedTop);
  }

  onHoldingHandSettingChanged(): void {
    this.floatingActionSideController.syncFromSettings();
  }

  private restoreEmbeddedContinuationIfPresent(): void {
    const pending = peekPendingContinuationSnapshot();
    if (pending === null || pending.kind !== 'embedded_reader' ||
      pending.route !== GalleryRoute.Downloads.toString() || pending.readerSession === undefined) {
      return;
    }
    const session = pending.readerSession;
    if (session.detail.gid <= 0 || session.detail.token.length === 0) {
      return;
    }
    readerSessionStore.setSession(session);
    this.detail = cloneGalleryDetail(session.detail);
    this.detailLink = createGalleryDetailLink(session.detail.gid, session.detail.token,
      session.detail.title, session.site, session.detailRequestUrl);
    this.detailRequestUrl = session.detailRequestUrl;
    this.statusText = session.statusText;
    this.showDetail = true;
    this.showReader = true;
    takePendingContinuationSnapshot();
  }

  onFloatingActionSideSettingChanged(): void {
    this.floatingActionSideController.handleManualSettingChanged();
  }

  private animateFloatingActionSide(side: string): void {
    if (side === this.floatingActionSide) {
      return;
    }
    // 与画廊工具栏使用同一停靠动效，连续换手时继承当前动画速度。
    this.getUIContext().animateTo({ curve: curves.springMotion(0.35, 1) }, () => {
      this.floatingActionSide = side;
    });
  }

  private updateToolbarForScrollFrame(scrollOffset: number): number {
    const offset = normalizeSceneScrollOffset(this.downloadScroller.currentOffset().yOffset);
    if (offset <= 4) {
      this.restoreToolbarOnReverseScroll();
      return scrollOffset;
    }
    if (scrollOffset > 0 && this.toolbarVisibleHeight() > 0) {
      this.toolbarRestoring = false;
      this.toolbarOffsetY = nextFloatingToolbarOffset(this.toolbarOffsetY, scrollOffset, offset, this.floatingToolbarHeight());
      this.syncToolbarOffsetState();
      return scrollOffset;
    }
    if (scrollOffset < 0 && this.toolbarOffsetY < 0) {
      this.restoreToolbarOnReverseScroll();
    }
    return scrollOffset;
  }

  private restoreToolbarOnReverseScroll(): void {
    if (this.toolbarOffsetY >= 0) {
      return;
    }
    this.getUIContext().animateTo({ curve: curves.springMotion(0.35, 1) }, () => {
      this.toolbarOffsetY = 0;
      this.syncToolbarOffsetState();
    });
  }

  private loadDownloads(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.items = ehDownloadStore.getItems();
      this.refreshDownloadRows();
      return;
    }

    ehDownloadStore.load(context).then(() => {
      this.refreshDownloadRows();
      this.statusText = this.items.length.toString() + ' download items';
      if (ehDownloadManager.hasWaitingDownloads()) {
        this.startGlobalDownloadQueue();
      }
    }).catch((error: Error) => {
      this.statusText = 'Download load failed: ' + error.message;
      this.items = ehDownloadStore.getItems();
      this.refreshDownloadRows();
    });
  }

  private persistDownloads(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehDownloadStore.save(context).catch((error: Error) => {
      this.statusText = 'Download save failed: ' + error.message;
    });
  }

  private showFloatingStatus(message: string): void {
    this.statusText = message;
    try {
      this.getUIContext().getPromptAction().showToast({ message: uiStatusText(message) });
    } catch (error) {
    }
  }

  private prepareDownloadBrowsePosition(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehBrowsePositionStore.ensureLoaded(context).then(() => {
      const position = ehBrowsePositionStore.getDownloadPosition();
      this.downloadScrollOffset = position.offset;
      this.downloadFirstVisibleIndex = position.anchorIndex;
      this.downloadBrowsePositionLoaded = true;
      this.restoreDownloadScrollOffset();
    }).catch(() => {});
  }

  private openDownloadLabelDrawer(): void {
    if (this.downloadLabelDrawerVisible) {
      return;
    }
    this.downloadActionsExpanded = false;
    this.downloadLabelDrawerVisible = true;
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.downloadLabelDrawerOffsetX = 0;
      this.downloadLabelDrawerOverlayOpacity = 0.45;
    });
  }

  private closeDownloadLabelDrawer(): void {
    if (!this.downloadLabelDrawerVisible) {
      return;
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.downloadLabelDrawerOffsetX = SIDE_PANEL_WIDTH;
      this.downloadLabelDrawerOverlayOpacity = 0;
    });
    setTimeout(() => {
      if (this.downloadLabelDrawerOffsetX > SIDE_PANEL_WIDTH - 40) {
        this.downloadLabelDrawerVisible = false;
      }
    }, 220);
  }

  private downloadLabelDrawerLeft(): number {
    return sidePanelLeft(this.downloadListOverlayWidth(), this.windowContentWidthVp());
  }

  private downloadListOverlayWidth(): number {
    return this.useSplitLayout() ? this.splitListPaneWidth() : this.availableSceneWidth();
  }

  private downloadSideOverlayWidth(): number {
    return this.useSplitLayout() ? this.splitSidePaneWidth() : this.availableSceneWidth();
  }

  private downloadSideOverlayLeft(): number {
    return this.useSplitLayout() ? this.splitListPaneWidth() + 1 : 0;
  }

  private handleOpenDownloadLabelDrawerPan(event: GestureEvent | undefined): void {
    if (this.downloadLabelDrawerVisible || this.showReader || this.showTagSearch) {
      return;
    }
    if (shouldOpenSidePanel(event)) {
      this.openDownloadLabelDrawer();
    }
  }

  private selectDownloadLabel(label: string): void {
    this.selectedDownloadLabel = label;
    this.downloadJumpPageIndex = 0;
    this.downloadScrollOffset = 0;
    this.refreshDownloadRows();
    this.closeDownloadLabelDrawer();
  }

  private openDefaultDownloadLabelDialog(): void {
    this.closeDownloadLabelDrawer();
    this.defaultDownloadLabelDialogVisible = true;
  }

  private selectDefaultDownloadLabel(label: string): void {
    saveDefaultDownloadLabelChoice(label === DOWNLOAD_LABEL_OPTION_ASK ? DOWNLOAD_LABEL_OPTION_ASK : label);
    this.defaultDownloadLabelDialogVisible = false;
    this.showFloatingStatus('Default download label updated');
  }

  private openDownloadLabelManager(): void {
    this.closeDownloadLabelDrawer();
    this.downloadLabelManagerVisible = true;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.syncDownloadContentWidthForCurrentLayout();
  }

  private closeDownloadLabelManager(): void {
    this.downloadLabelManagerVisible = false;
    this.activeSplitPane = this.showDetail ? SPLIT_PANE_FOCUS_RIGHT : SPLIT_PANE_FOCUS_LEFT;
    this.syncDownloadContentWidthForCurrentLayout();
  }

  private openAddDownloadLabel(): void {
    this.downloadLabelEditValue = '';
    this.downloadLabelEditDialogVisible = true;
  }

  private renameDownloadLabel(label: string, rawValue: string): void {
    const value = rawValue.trim();
    if (value.length === 0) {
      this.showFloatingStatus('Label name cannot be empty');
      return;
    }
    if (value === label) {
      return;
    }
    const selectedWasEditing = this.selectedDownloadLabel === label;
    const defaultWasEditing = defaultDownloadLabelChoice() === label;
    if (!ehDownloadStore.renameLabel(label, value)) {
      this.showFloatingStatus('Download label already exists');
      return;
    }
    if (selectedWasEditing) {
      this.selectedDownloadLabel = value;
    }
    if (defaultWasEditing) {
      saveDefaultDownloadLabelChoice(value);
    }
    this.persistDownloads();
  }

  private confirmDownloadLabelEdit(): void {
    const value = this.downloadLabelEditValue.trim();
    if (value.length === 0) {
      this.showFloatingStatus('Label name cannot be empty');
      return;
    }
    if (!ehDownloadStore.addLabel(value)) {
      this.showFloatingStatus('Download label already exists');
      return;
    }
    this.downloadLabelEditDialogVisible = false;
    this.persistDownloads();
  }

  private moveDownloadLabel(from: number, to: number): void {
    if (ehDownloadStore.moveLabel(from, to)) {
      this.persistDownloads();
    }
  }

  private confirmDeleteDownloadLabel(label: string): void {
    const count = ehDownloadStore.labelItemCount(label);
    const wasDefault = defaultDownloadLabelChoice() === label;
    this.getUIContext().getPromptAction().showDialog({
      title: uiText('Delete label'),
      message: uiText('Downloads in this label will be moved to Default') + ' (' + count.toString() + ')',
      buttons: [
        { text: uiText('Cancel'), color: themeSecondaryText() },
        { text: uiText('Delete'), color: themeAccentTextColor() }
      ]
    }).then((data) => {
      if (data.index !== 1) {
        return;
      }
      ehDownloadStore.removeLabel(label);
      if (this.selectedDownloadLabel === label) {
        this.selectedDownloadLabel = DOWNLOAD_LABEL_FILTER_ALL;
      }
      if (wasDefault) {
        saveDefaultDownloadLabelChoice(DOWNLOAD_LABEL_OPTION_ASK);
      }
      this.persistDownloads();
    }).catch(() => {});
  }

  private openMoveSelectedDownloadLabel(): void {
    this.downloadActionsExpanded = false;
    this.moveDownloadLabelDialogVisible = true;
  }

  private moveSelectedDownloadsToLabel(label: string): void {
    const selected = this.selectedDownloadItems();
    const gids: number[] = [];
    for (let i = 0; i < selected.length; i++) {
      gids.push(selected[i].gid);
    }
    const changed = ehDownloadStore.setLabels(gids, label);
    this.moveDownloadLabelDialogVisible = false;
    this.clearDownloadSelection();
    this.persistDownloads();
    this.showFloatingStatus('Moved downloads to label: ' + changed.toString());
  }

  private showBlockingBusy(message: string): void {
    this.blockingBusyMessage = message;
    this.blockingBusyVisible = true;
  }

  private hideBlockingBusy(): void {
    this.blockingBusyVisible = false;
    this.blockingBusyMessage = 'Loading...';
  }

  private computeVisibleDownloadItems(): DownloadInfo[] {
    const visible = filterDownloadItems(this.items, '', this.statusFilters, this.selectedDownloadLabel, this.sortMode,
      this.categoryFilter);
    const filtered: DownloadInfo[] = [];
    const options = this.downloadSearchOptions();
    const query = this.query;
    for (let i = 0; i < visible.length; i++) {
      if (galleryMatchesLocalSearch(visible[i], query, options)) {
        filtered.push(visible[i]);
      }
    }
    return filtered;
  }

  private downloadSearchOptions(): LocalGallerySearchOptions {
    return {
      mode: this.searchMode,
      category: this.searchCategory,
      advancedEnabled: this.advancedSearchEnabled,
      advancedPanelOpened: this.advancedPanelVisible || this.advancedSearchEnabled || this.searchCategory !== GalleryCategory.None ||
        this.minRating > 0,
      advanceSearch: this.advanceSearch,
      minRating: this.minRating
    };
  }

  private applyDownloadSearch(): void {
    this.query = normalizeSubmittedSearchKeyword(this.query);
    this.searchSubmitted = true;
    recordSearchHistory(this.query);
    this.downloadJumpPageIndex = 0;
    this.downloadScrollOffset = 0;
    this.refreshDownloadRows();
  }

  private openDownloadSearchSuggestions(): void {
    this.searchSubmitted = false;
    this.downloadJumpPageIndex = 0;
    this.refreshSearchSuggestions();
  }

  private openDownloadSearchBar(): void {
    this.searchBarVisible = true;
    this.openDownloadSearchSuggestions();
  }

  private closeDownloadSearchBar(): void {
    this.searchBarVisible = false;
    this.searchSubmitted = true;
    this.advancedPanelVisible = false;
    this.clearDownloadSearchFilters();
    this.downloadJumpPageIndex = 0;
    this.refreshDownloadRows();
  }

  private showDownloadStatusHint(): void {
    this.statusHintText = uiText('Current status filter') + ': ' + this.downloadStatusSummary(this.statusFilters);
    this.statusHintVisible = true;
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
        this.statusHintVisible = false;
      });
    }, 1500);
  }

  private downloadStatusSummary(statuses: string[]): string {
    if (statuses.length === DOWNLOAD_STATUS_FILTER_OPTIONS.length) {
      return uiText('All');
    }
    if (statuses.length === 0) {
      return '—';
    }
    const labels: string[] = [];
    for (let i = 0; i < DOWNLOAD_STATUS_FILTER_OPTIONS.length; i++) {
      const status = DOWNLOAD_STATUS_FILTER_OPTIONS[i];
      if (statuses.indexOf(status) >= 0) {
        labels.push(uiText(status));
      }
    }
    return labels.join(', ');
  }

  private openDownloadStatusPanel(): void {
    this.downloadActionsExpanded = false;
    this.downloadJumpPanelVisible = false;
    this.statusFilterDraft = this.statusFilters.slice();
    this.statusFilterPanelVisible = true;
  }

  private closeDownloadStatusPanel(): void {
    this.statusFilterPanelVisible = false;
  }

  private applyDownloadStatusFilter(): void {
    this.statusFilters = this.statusFilterDraft.slice();
    this.statusFilterPanelVisible = false;
    this.downloadJumpPageIndex = 0;
    this.downloadScrollOffset = 0;
    this.refreshDownloadRows();
    this.showDownloadStatusHint();
  }

  private clearDownloadSearchFilters(): void {
    this.query = '';
    this.searchMode = ListMode.Normal;
    this.searchCategory = GalleryCategory.None;
    this.advancedSearchEnabled = false;
    this.advanceSearch = DEFAULT_ADVANCE_SEARCH;
    this.minRating = -1;
    this.selectedTagNamespaces = [];
    this.refreshSearchSuggestions([]);
  }

  private updateDownloadKeyword(value: string): void {
    this.query = value;
    this.searchSubmitted = false;
    this.downloadJumpPageIndex = 0;
    this.refreshSearchSuggestions();
    this.refreshDownloadRows();
  }

  private refreshSearchSuggestions(namespaces: string[] = this.selectedTagNamespaces): void {
    this.searchSuggestionItems = buildSearchSuggestions(this.query, 0, namespaces);
    this.searchSuggestionRevision++;
  }

  private selectedTagNamespaceKey(): string {
    return sortedStringKey(this.selectedTagNamespaces);
  }

  private toggleTagNamespace(namespace: string): void {
    const next = toggleStringValue(this.selectedTagNamespaces, namespace);
    this.selectedTagNamespaces = next;
    this.refreshSearchSuggestions(next);
  }

  private applySearchSuggestion(suggestion: SearchSuggestionItem): void {
    if (suggestion.kind === 'tag') {
      this.updateDownloadKeyword(applyTagSuggestionToKeyword(this.query, suggestion.query, suggestion.namespace));
      this.searchMode = ListMode.Tag;
      return;
    }
    this.updateDownloadKeyword(suggestion.query);
  }

  private downloadJumpTotalPages(): number {
    const count = this.visibleItems.length;
    return count <= 0 ? 0 : Math.ceil(count / DOWNLOAD_JUMP_PAGE_SIZE);
  }

  private syncDownloadJumpDraft(): void {
    const total = this.downloadJumpTotalPages();
    const safeIndex = total > 0 ? Math.max(0, Math.min(this.downloadJumpPageIndex, total - 1)) : 0;
    this.downloadJumpPageIndex = safeIndex;
    this.downloadJumpDraft = (safeIndex + 1).toString();
  }

  private openDownloadJumpPanel(): void {
    if (this.downloadJumpTotalPages() <= 1) {
      this.statusText = 'No other page to jump to';
      return;
    }
    this.downloadActionsExpanded = false;
    this.syncDownloadJumpDraft();
    this.downloadJumpPanelVisible = true;
  }

  private closeDownloadJumpPanel(): void {
    this.downloadJumpPanelVisible = false;
  }

  private submitDownloadJump(): void {
    const parsed = Number.parseInt(this.downloadJumpDraft);
    const total = this.downloadJumpTotalPages();
    if (Number.isNaN(parsed) || parsed <= 0 || total <= 0) {
      this.syncDownloadJumpDraft();
      return;
    }
    const targetPage = Math.max(1, Math.min(parsed, total));
    const targetItemIndex = (targetPage - 1) * DOWNLOAD_JUMP_PAGE_SIZE;
    const rowIndex = Math.floor(targetItemIndex / Math.max(1, this.downloadColumnCount()));
    this.downloadJumpPageIndex = targetPage - 1;
    this.downloadJumpDraft = targetPage.toString();
    this.downloadScrollOffset = 0;
    this.toolbarOffsetY = 0;
    this.syncToolbarOffsetState();
    try {
      this.downloadScroller.scrollToIndex(rowIndex + 1);
      this.statusText = 'Page ' + targetPage.toString() + '/' + total.toString();
    } catch (error) {
      this.statusText = 'Jump failed: ' + String(error);
    }
  }

  private selectedKey(gid: number): string {
    return '|' + gid.toString() + '|';
  }

  private downloadSelectionCount(): number {
    if (this.selectedDownloadGids.length === 0) {
      return 0;
    }
    const parts = this.selectedDownloadGids.split('|');
    let count = 0;
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].length > 0) {
        count++;
      }
    }
    return count;
  }

  private isDownloadSelected(gid: number): boolean {
    return this.selectedDownloadGids.indexOf(this.selectedKey(gid)) >= 0;
  }

  private toggleDownloadSelection(gid: number): void {
    const key = this.selectedKey(gid);
    if (this.selectedDownloadGids.indexOf(key) >= 0) {
      this.selectedDownloadGids = this.selectedDownloadGids.replace(key, '|');
      if (this.selectedDownloadGids === '|') {
        this.selectedDownloadGids = '';
        this.downloadActionsExpanded = false;
      }
      return;
    }
    if (this.selectedDownloadGids.length === 0) {
      this.selectedDownloadGids = key;
    } else {
      this.selectedDownloadGids += gid.toString() + '|';
    }
    this.downloadActionsExpanded = true;
  }

  private handleDownloadCardTap(item: DownloadInfo, event?: ClickEvent): void {
    if (this.downloadSelectionCount() > 0) {
      this.toggleDownloadSelection(item.gid);
      return;
    }
    if (event !== undefined) {
      this.cardScrollAnchor.capture(item.gid.toString(), this.downloadColumnCount(),
        this.downloadCardWindowY(event.target.area));
    }
    this.openDetail(item);
  }

  private downloadCardWindowY(area: Area): number {
    const value = area.globalPosition.y;
    return value === undefined ? Number.NaN : Number.parseFloat(value.toString());
  }

  private observeDownloadCardAnchor(item: DownloadInfo, area: Area): void {
    this.cardScrollAnchor.observe(item.gid.toString(), this.downloadColumnCount(),
      this.downloadCardWindowY(area), (deltaY: number) => {
        this.downloadScroller.scrollBy(0, deltaY);
        setTimeout(() => {
          this.rememberDownloadScrollOffset();
        }, 0);
      });
  }

  private selectedDownloadItems(): DownloadInfo[] {
    const selected: DownloadInfo[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.isDownloadSelected(this.items[i].gid)) {
        selected.push(this.items[i]);
      }
    }
    return selected;
  }

  private selectAllVisibleFinishedDownloads(): void {
    let selected = '';
    let count = 0;
    for (let i = 0; i < this.visibleItems.length; i++) {
      const item = this.visibleItems[i];
      if (item.state === DownloadState.Finish) {
        if (selected.length === 0) {
          selected = this.selectedKey(item.gid);
        } else {
          selected += item.gid.toString() + '|';
        }
        count++;
      }
    }
    if (count <= 0) {
      this.statusText = 'No downloaded galleries to select';
      return;
    }
    this.selectedDownloadGids = selected;
    this.downloadActionsExpanded = true;
    this.statusText = 'Selected ' + count.toString() + ' downloaded galleries';
  }

  private downloadCardPreferredWidth(): number {
    if (galleryListMode() === 'Thumb') {
      return galleryThumbnailPreferredColumnWidth();
    }
    return galleryDetailCardPreferredWidth();
  }

  private downloadCardGap(): number {
    return uiListGap();
  }

  private downloadContentPadding(): number {
    return galleryListHorizontalPadding(this.downloadContentWidth);
  }

  private downloadColumnCount(): number {
    return this.downloadColumnCountForWidth(this.downloadContentWidth);
  }

  private downloadColumnCountForWidth(width: number): number {
    const availableWidth = Math.max(0, width - this.downloadContentPadding() * 2);
    if (availableWidth <= 0 || Number.isNaN(availableWidth)) {
      return 1;
    }
    const preferred = this.downloadCardPreferredWidth();
    const gap = this.downloadCardGap();
    return galleryListColumnCount(width, preferred, gap);
  }

  private downloadWaterFlowColumnsTemplate(): string {
    return galleryListColumnsTemplate(this.downloadColumnCount());
  }

  private updateDownloadContentWidth(width: number): void {
    const normalizedWidth = Math.floor(width);
    if (normalizedWidth <= 0 || Number.isNaN(normalizedWidth) ||
      Math.abs(this.downloadContentWidth - normalizedWidth) < 1) {
      return;
    }
    this.downloadContentWidth = normalizedWidth;
  }

  private syncDownloadContentWidthFromWindow(): void {
    if (this.useSplitLayout()) {
      this.syncDownloadContentWidthForCurrentLayout();
      return;
    }
    this.updateDownloadContentWidth(mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value)));
  }

  private syncDownloadContentWidthForCurrentLayout(): void {
    const width = this.useSplitLayout() ? this.splitListPaneWidth() : this.availableSceneWidth();
    if (width >= 240) {
      this.updateDownloadContentWidth(width);
    }
  }

  private updateDownloadContentWidthFromArea(width: number): void {
    const targetWidth = this.useSplitLayout() ? this.splitListPaneWidth() : this.availableSceneWidth();
    this.updateDownloadContentWidth(targetWidth >= 240 ? targetWidth : width);
  }

  private updateSceneContentWidth(width: number): void {
    const normalized = Math.floor(width);
    if (normalized <= 0 || Number.isNaN(normalized) || Math.abs(this.sceneContentWidth - normalized) < 1) {
      return;
    }
    this.sceneContentWidth = normalized;
    rememberMainContentWidthVp(normalized);
    this.syncDownloadContentWidthForCurrentLayout();
    markCurrentRouteRightPane(this.useSplitLayout());
  }

  onSplitPaneRatioRevisionChange(): void {
    if (!this.splitDragging) {
      this.splitListRatio = splitPaneCurrentRatio();
      this.syncDownloadContentWidthForCurrentLayout();
    }
  }

  private useSplitLayout(): boolean {
    return splitPaneModeEnabled() && this.availableSceneWidth() >= SPLIT_PANE_BREAKPOINT &&
      (this.showDetail || this.downloadLabelManagerVisible) && !this.showTagSearch;
  }

  private handleDownloadListDidScroll(): void {
    const yOffset = normalizeSceneScrollOffset(this.downloadScroller.currentOffset().yOffset);
    const delta = yOffset - this.lastToolbarScrollOffset;
    this.lastToolbarScrollOffset = yOffset;
    if (yOffset <= 4) {
      this.toolbarRestoring = false;
      this.toolbarOffsetY = 0;
      this.syncToolbarOffsetState();
    } else if (delta > 0.1) {
      this.toolbarRestoring = false;
      this.toolbarOffsetY = -Math.min(yOffset, this.floatingToolbarHeight());
      this.syncToolbarOffsetState();
    } else if (delta < -0.1) {
      this.restoreToolbarOnReverseScroll();
    }
    this.rememberDownloadScrollOffset();
  }

  private availableSceneWidth(): number {
    const windowWidth = this.windowContentWidthVp();
    if (this.sceneContentWidth > 0) {
      return this.sceneContentWidth;
    }
    return windowWidth;
  }

  private syncSceneContentWidthFromWindow(): void {
    const width = this.windowContentWidthVp();
    if (width >= 240) {
      this.updateSceneContentWidth(width);
    }
  }

  private windowContentWidthVp(): number {
    return mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value));
  }

  private splitListPaneWidth(): number {
    return splitPaneListWidth(this.availableSceneWidth(), this.splitListRatio);
  }

  private splitSidePaneWidth(): number {
    if (!this.useSplitLayout()) {
      return this.availableSceneWidth();
    }
    return splitPaneSideWidth(this.availableSceneWidth(), this.splitListPaneWidth());
  }

  private updateSplitPaneByOffset(offsetX: number): void {
    const sceneWidth = this.availableSceneWidth();
    const targetWidth = splitPaneWidthFromDrag(sceneWidth, this.splitDragStartWidth, offsetX);
    this.splitListRatio = splitPaneRatioForWidth(sceneWidth, targetWidth);
    this.syncDownloadContentWidthForCurrentLayout();
  }

  private finishSplitPaneDrag(): void {
    this.splitDragging = false;
    saveSplitPaneRatio(this.splitListRatio);
  }

  private refreshDownloadRows(): void {
    this.visibleItems = this.computeVisibleDownloadItems();
    this.syncDownloadCardStates();
    if (this.downloadBrowsePositionLoaded && !this.downloadBrowsePositionRestored) {
      setTimeout(() => {
        this.restoreDownloadScrollOffset();
      }, 0);
    }
  }

  private updateVisibleTranslationItem(index: number, visible: boolean): void {
    const existing = this.translationVisibleItems.indexOf(index);
    if (visible && existing < 0) {
      this.translationVisibleItems.push(index);
    } else if (!visible && existing >= 0) {
      this.translationVisibleItems.splice(existing, 1);
    }
    if (this.translationVisibleItems.length === 0) {
      this.translationVisibleStart = -1;
      this.translationVisibleEnd = -1;
      return;
    }
    let start = this.translationVisibleItems[0];
    let end = start;
    for (let i = 1; i < this.translationVisibleItems.length; i++) {
      start = Math.min(start, this.translationVisibleItems[i]);
      end = Math.max(end, this.translationVisibleItems[i]);
    }
    this.translationVisibleStart = start;
    this.translationVisibleEnd = end;
    this.downloadFirstVisibleIndex = start;
  }

  private setVisibleTranslationRange(start: number, end: number): void {
    this.translationVisibleItems = [];
    this.translationVisibleStart = start;
    this.translationVisibleEnd = end;
    if (start >= 0) {
      this.downloadFirstVisibleIndex = start;
    }
  }

  private translationPriorityFor(index: number): number {
    if (!this.translationEnabled) {
      return 0;
    }
    return translationPriorityForIndex(index, this.translationVisibleStart, this.translationVisibleEnd,
      this.downloadColumnCount());
  }

  private syncDownloadCardStates(): void {
    const live: Map<number, DownloadCardState> = new Map<number, DownloadCardState>();
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      let cardState = this.downloadCardStates.get(item.gid);
      if (cardState === undefined) {
        cardState = new DownloadCardState();
      }
      cardState.update(item.state, downloadProgressText(item), this.downloadProgressValue(item),
        this.downloadSpeedLabel(item));
      live.set(item.gid, cardState);
    }
    this.downloadCardStates = live;
  }

  private downloadCardStateFor(gid: number): DownloadCardState {
    let cardState = this.downloadCardStates.get(gid);
    if (cardState === undefined) {
      cardState = new DownloadCardState();
      this.downloadCardStates.set(gid, cardState);
    }
    return cardState;
  }

  private downloadProgressValue(item: DownloadInfo): number {
    const total = item.total > 0 ? item.total : item.pages;
    if (total <= 0) {
      return 0;
    }
    const units = this.downloadProgressUnits(item);
    return Math.max(0, Math.min(100, Math.round(units * 100 / Math.max(1, total * DOWNLOAD_PAGE_PROGRESS_SCALE))));
  }

  private downloadProgressUnits(item: DownloadInfo): number {
    return Math.max(0, item.finished) * DOWNLOAD_PAGE_PROGRESS_SCALE;
  }

  private downloadSpeedLabel(item: DownloadInfo): string {
    if (item.speed <= 0) {
      return '';
    }
    return downloadSizeText(item.speed) + '/s';
  }

  private startSelectedOrFiltered(): void {
    const selected = this.selectedDownloadItems();
    const targets = selected.length > 0 ? selected : this.visibleItems;
    if (targets.length === 0) {
      this.statusText = 'No filtered downloads';
      return;
    }
    for (let i = 0; i < targets.length; i++) {
      ehDownloadStore.startGallery(targets[i].gid);
    }
    this.statusText = 'Queued ' + targets.length.toString() +
      (selected.length > 0 ? ' selected downloads' : ' filtered downloads');
    if (selected.length > 0) {
      this.clearDownloadSelection();
    }
    this.persistDownloads();
    this.startGlobalDownloadQueue();
  }

  private stopSelectedOrFiltered(): void {
    const selected = this.selectedDownloadItems();
    const targets = selected.length > 0 ? selected : this.visibleItems;
    if (targets.length === 0) {
      this.statusText = 'No filtered downloads';
      return;
    }
    for (let i = 0; i < targets.length; i++) {
      ehDownloadManager.stopGallery(targets[i].gid);
    }
    this.statusText = 'Stopped ' + targets.length.toString() +
      (selected.length > 0 ? ' selected downloads' : ' filtered downloads');
    if (selected.length > 0) {
      this.clearDownloadSelection();
    }
    this.persistDownloads();
  }

  private restoreDownloadedItems(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Restore needs app context';
      return;
    }
    const currentLocation = normalizeDownloadSceneLocation(ehSettingsStore.getValue('download_location',
      DOWNLOAD_LOCATION_APP_FILES));
    this.statusText = currentLocation === DOWNLOAD_LOCATION_APP_FILES ? 'Preparing public Downloads access...' :
      'Scanning downloaded folders...';
    Promise.resolve().then(async () => {
      let downloadsAccess = true;
      if (currentLocation === DOWNLOAD_LOCATION_APP_FILES) {
        downloadsAccess = await this.ensurePublicDownloadAccess(context);
      }
      this.statusText = 'Scanning ZIP archives...';
      this.showBlockingBusy('Scanning ZIP archives...');
      const result: DownloadRestoreResult = await restoreDownloadedItemsAndArchives(context, currentGallerySite(),
        downloadsAccess);
      this.hideBlockingBusy();
      const statusParts: string[] = [];
      if (result.restored > 0) {
        statusParts.push('Restored galleries: ' + result.restored.toString());
      }
      if (result.archives.found > 0) {
        if (result.archives.processed > 0) {
          statusParts.push('ZIP archives processed: ' + result.archives.processed.toString() + ', skipped: ' +
            result.archives.skipped.toString());
        } else {
          statusParts.push('Unprocessed ZIP archives: ' + result.archives.skipped.toString());
        }
      }
      if (statusParts.length <= 0) {
        statusParts.push('No downloaded galleries found');
      }
      let message = statusParts.join('. ');
      if (!downloadsAccess) {
        message += '. Downloads access was not granted; scanned app files only';
      }
      this.showFloatingStatus(message);
      if (result.archives.processed > 0) {
        this.showDeleteProcessedZipDialog(result.archives);
      }
    }).catch((error: Error) => {
      this.hideBlockingBusy();
      this.showFloatingStatus('Restore failed: ' + error.message);
    });
  }

  private async ensurePublicDownloadAccess(context: common.UIAbilityContext): Promise<boolean> {
    if (ehDownloadFileStore.canUseLocation(context, DOWNLOAD_LOCATION_DOWNLOADS)) {
      return true;
    }
    const pickedRoot = await pickDownloadDirectoryRoot(context);
    if (pickedRoot.length > 0) {
      ehDownloadFileStore.rememberPublicDownloadRoot(pickedRoot);
      if (ehDownloadFileStore.canUseLocation(context, DOWNLOAD_LOCATION_DOWNLOADS)) {
        return true;
      }
    }
    return false;
  }

  private cycleItemState(item: DownloadInfo): void {
    if (item.state === DownloadState.Wait || item.state === DownloadState.Downloading) {
      this.stopItem(item);
      return;
    }
    this.startItem(item);
  }

  private toggleItemFromProgress(item: DownloadInfo): void {
    if (item.state === DownloadState.Finish) {
      return;
    }
    this.cycleItemState(item);
  }

  private findActiveItem(gid: number): DownloadInfo | undefined {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid === gid) {
        return this.items[i];
      }
    }
    return undefined;
  }

  private startItem(item: DownloadInfo): void {
    ehDownloadManager.resumeGallery(item.gid);
    this.statusText = 'Queued: ' + item.title;
    this.persistDownloads();
    if (!ehDownloadManager.isQueueProcessing()) {
      this.startGlobalDownloadQueue();
    }
  }

  private stopItem(item: DownloadInfo): void {
    ehDownloadManager.stopGallery(item.gid);
    this.statusText = 'Stopped: ' + item.title;
    this.persistDownloads();
  }

  private startGlobalDownloadQueue(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Download needs app context';
      return;
    }
    if (shouldConfirmCellularNetworkOperation()) {
      this.confirmMobileDataDownload(() => {
        ehDownloadManager.startQueue(context);
      });
      return;
    }
    ehDownloadManager.startQueue(context);
  }

  private confirmMobileDataDownload(onContinue: () => void): void {
    if (this.cellularWarningDialogOpen) {
      return;
    }
    this.cellularWarningDialogOpen = true;
    this.getUIContext().getPromptAction().showDialog({
      title: uiText('Mobile data warning'),
      message: uiText('You are using mobile data. Continue downloading?'),
      buttons: [
        {
          text: uiText('Cancel'),
          color: themeSecondaryText()
        },
        {
          text: uiText('Continue'),
          color: themeAccentTextColor()
        }
      ]
    }).then((data) => {
      this.cellularWarningDialogOpen = false;
      if (data.index === 1) {
        confirmCellularNetworkWarningForSession();
        onContinue();
      } else {
        this.statusText = 'Download waits for Wi-Fi or confirmation';
      }
    }).catch(() => {
      this.cellularWarningDialogOpen = false;
      this.statusText = 'Download waits for Wi-Fi or confirmation';
    });
  }

  private removeItem(item: DownloadInfo): void {
    const context = getAbilityContext();
    if (context !== undefined) {
      ehDownloadFileStore.removeGalleryDirectory(context, item);
    }
    ehDownloadStore.removeGallery(item.gid);
  }

  private deleteSelectedDownloads(): void {
    const selected = this.selectedDownloadItems();
    if (selected.length === 0) {
      this.statusText = 'Long press cards to select downloads';
      return;
    }
    if (this.deleteConfirmationDialogOpen) {
      return;
    }
    this.deleteConfirmationDialogOpen = true;
    this.getUIContext().getPromptAction().showDialog({
      title: uiText('Delete'),
      message: uiStatusText('Delete ' + selected.length.toString() + ' selected downloads and their files?'),
      buttons: [
        {
          text: uiText('Cancel'),
          color: themeSecondaryText()
        },
        {
          text: uiText('Delete'),
          color: themeAccentTextColor()
        }
      ]
    }).then((data) => {
      this.deleteConfirmationDialogOpen = false;
      if (data.index === 1) {
        this.removeSelectedDownloads(selected);
      }
    }).catch(() => {
      this.deleteConfirmationDialogOpen = false;
    });
  }

  private removeSelectedDownloads(selected: DownloadInfo[]): void {
    for (let i = 0; i < selected.length; i++) {
      this.removeItem(selected[i]);
    }
    this.clearDownloadSelection();
    this.statusText = 'Removed ' + selected.length.toString() + ' download items';
    this.persistDownloads();
  }

  private exportSelectedDownloadsZip(): void {
    const selected = this.selectedDownloadItems();
    if (selected.length === 0) {
      this.statusText = 'Long press cards to select downloads';
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Export needs app context';
      return;
    }
    this.statusText = 'Exporting ' + selected.length.toString() + ' selected downloads...';
    this.ensurePublicDownloadAccess(context).then((ready: boolean) => {
      if (!ready) {
        throw new Error('Downloads access was not granted');
      }
      this.showBlockingBusy('Creating download archive...');
      return ehDownloadFileStore.exportGalleriesZip(context, selected);
    }).then((result) => {
      this.hideBlockingBusy();
      if (result === undefined) {
        return;
      }
      this.clearDownloadSelection();
      this.showFloatingStatus('Exported ' + result.folders.toString() + ' folders to ' + result.path + ' (' +
        downloadSizeText(result.bytes) + ')');
    }).catch((error: Error) => {
      this.hideBlockingBusy();
      this.showFloatingStatus('Export failed: ' + error.message);
    });
  }

  private openDetail(item: DownloadInfo): void {
    this.restoreDetailWithFade = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.showDetail = true;
    this.syncDownloadContentWidthForCurrentLayout();
    markCurrentRouteRightPane(this.useSplitLayout());
    const detailLink = createGalleryDetailLinkFromGallery(item, currentGallerySite(),
      EhUrl.getReferer(currentGallerySite()));
    this.detailLink = detailLink;
    this.detail = initialDetailForLink(detailLink);
    this.detailRequestUrl = detailLink.url;
    this.saveNavigationCache();
  }

  private openRandomDownload(): void {
    if (this.visibleItems.length === 0) {
      this.showFloatingStatus('Random needs a loaded gallery list');
      return;
    }
    const index = Math.floor(Math.random() * this.visibleItems.length);
    this.openDetail(this.visibleItems[index]);
  }

  private closeDetail(): void {
    this.restoreDetailWithFade = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
    this.showDetail = false;
    this.syncDownloadContentWidthForCurrentLayout();
    markCurrentRouteRightPane(false);
    this.detailLink = createEmptyGalleryDetailLink();
    this.detail = createEmptyDetail();
    this.detailRequestUrl = '';
    this.saveNavigationCache();
  }

  private closeTagSearch(): void {
    this.showTagSearch = false;
    this.tagSearchTitle = 'Search';
    this.tagSearchKeyword = '';
    this.tagSearchMode = ListMode.Tag;
    this.tagSearchCategory = GalleryCategory.None;
    this.tagSearchImagePath = '';
    this.tagSearchImageUseSimilarity = false;
    this.tagSearchImageOnlyCovers = false;
    this.tagSearchImageShowExpunged = false;
    this.saveNavigationCache();
    setTimeout(() => {
      setActiveBackHandler(() => this.handleSystemBack());
    }, 0);
  }

  private openRemoteSearch(request: DetailSearchRequest): void {
    this.tagSearchTitle = request.title;
    this.tagSearchKeyword = request.keyword;
    this.tagSearchMode = request.mode;
    this.tagSearchCategory = request.category;
    this.tagSearchImagePath = request.imagePath;
    this.tagSearchImageUseSimilarity = request.useSimilarityScan;
    this.tagSearchImageOnlyCovers = request.onlySearchCovers;
    this.tagSearchImageShowExpunged = request.showExpunged;
    this.showReader = false;
    this.showTagSearch = true;
    this.saveNavigationCache();
  }

  private closeEmbeddedReader(): void {
    if (this.readerClosing) {
      return;
    }
    this.readerClosing = true;
    this.restoreDetailWithFade = this.showDetail;
    if (!isEmbeddedReaderActive()) {
      this.showReader = false;
      this.restoreBackHandler();
      this.clearRestoreDetailFadeLater();
      this.readerClosing = false;
      return;
    }
    leaveEmbeddedReaderFullscreen().then(() => {
      this.showReader = false;
      this.restoreBackHandler();
      this.clearRestoreDetailFadeLater();
    }).finally(() => {
      this.readerClosing = false;
    });
  }

  private clearRestoreDetailFadeLater(): void {
    setTimeout(() => {
      if (!this.showReader) {
        this.restoreDetailWithFade = false;
      }
    }, 260);
  }

  private restoreBackHandler(): void {
    setTimeout(() => {
      setActiveBackHandler(() => this.handleSystemBack());
    }, 0);
  }

  @Builder
  private downloadSearchSuggestionPlaceholder() {
    Column({ space: 4 }) {
      SearchSummaryStrip({
        selectedTagNamespaces: this.selectedTagNamespaces,
        selectedTagNamespaceKey: this.selectedTagNamespaceKey(),
        revision: this.searchSuggestionRevision,
        onToggleTagNamespace: (namespace: string) => {
          this.toggleTagNamespace(namespace);
        }
      })
      if (this.searchSuggestionItems.length > 0) {
        SearchSuggestionList({
          suggestions: this.searchSuggestionItems,
          revision: this.searchSuggestionRevision,
          onSelect: (suggestion: SearchSuggestionItem) => {
            this.applySearchSuggestion(suggestion);
          }
        })
          .height(Math.max(240, this.downloadListViewportHeight() - 58))
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(28)
            .fontColor([themeTertiaryText()])
          Text(uiText('Search history appears before typing; tag tips appear while typing'))
            .fontSize(12)
            .fontColor(themeTertiaryText())
        }
        .width('100%')
        .height(180)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(themeSurface())
        .borderRadius(uiRadius(6))
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4 })
  }

  @Builder
  private downloadCardContent(item: DownloadInfo, index: number) {
    Column() {
      if (galleryListMode() === 'Thumb') {
        // Long-press selection is injected per page; keep the reusable card contract as-is.
        // eslint-disable-next-line @performance/hp-arkui-no-func-as-arg-for-reusable-component
        GalleryThumbCard({
          gallery: item,
          selected: this.isDownloadSelected(item.gid),
          translateTitle: this.translationEnabled,
          translationPriority: this.translationPriorityFor(index),
          onLongPress: (pressed: GalleryInfo) => {
            this.toggleDownloadSelection(pressed.gid);
          }
        })
          .width('100%')
          .zIndex(2)
          .onClick((event?: ClickEvent) => {
            this.handleDownloadCardTap(item, event);
          })
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.observeDownloadCardAnchor(item, newArea);
          })
      } else {
        // eslint-disable-next-line @performance/hp-arkui-no-func-as-arg-for-reusable-component
        GalleryListRow({
          gallery: item,
          selected: this.isDownloadSelected(item.gid),
          translateTitle: this.translationEnabled,
          translationPriority: this.translationPriorityFor(index),
          onLongPress: (pressed: GalleryInfo) => {
            this.toggleDownloadSelection(pressed.gid);
          }
        })
          .width('100%')
          .zIndex(2)
          .onClick((event?: ClickEvent) => {
            this.handleDownloadCardTap(item, event);
          })
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.observeDownloadCardAnchor(item, newArea);
          })
      }
      if (item.state !== DownloadState.Finish) {
        DownloadCardStatus({
          item: item,
          cardState: this.downloadCardStateFor(item.gid),
          onStatusTap: (downloadItem: DownloadInfo) => {
            const current = this.findActiveItem(downloadItem.gid);
            if (current !== undefined) {
              this.toggleItemFromProgress(current);
            }
          }
        })
          .margin({ top: 4 })
          .zIndex(1)
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }),
            TransitionEffect.move(TransitionEdge.TOP)
              .animation({ duration: 180, curve: Curve.EaseIn })))
      }
    }
    .width('100%')
    .animation({ duration: 220, curve: Curve.EaseOut })
  }

  @Builder
  private downloadListEdgeSpacer() {
    Row()
      .width('100%')
      .height(this.downloadCardGap())
      .backgroundColor(themePageBackground())
  }

  @Builder
  private downloadListTopPlaceholder() {
    Row()
      .width('100%')
      .height(this.downloadContentStartOffset())
  }

  @Builder
  private downloadStandardList() {
    List({ space: 0, scroller: this.downloadScroller }) {
      ListItemGroup({ header: this.downloadListTopPlaceholder() }) {
        ForEach(this.visibleItems, (item: DownloadInfo, index: number) => {
          ListItem() {
            this.downloadCardContent(item, index)
          }
          .margin({ bottom: this.downloadCardGap() })
          .reuseId('download-card-item')
          .onVisibleAreaChange([0.0, 0.01], (visible: boolean, _ratio: number) => {
            this.updateVisibleTranslationItem(index, visible);
          })
          .animation({ duration: 220, curve: Curve.EaseOut })
          .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseInOut }))
        }, (item: DownloadInfo) => item.gid.toString())
      }
    }
    .width('100%')
    .height('100%')
    .lanes(this.downloadColumnCount(), this.downloadCardGap())
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true, effectEdge: EffectEdge.START | EffectEdge.END })
    .cachedCount(10)
    .scrollBar(BarState.Auto)
    .padding({
      left: this.downloadContentPadding(),
      right: this.downloadContentPadding()
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateDownloadContentWidthFromArea(newArea.width as number);
    })
    .onAppear(() => {
      this.restoreDownloadScrollOffset();
    })
    .onScrollFrameBegin((offset: number, _state: ScrollState) => {
      return { offsetRemain: this.updateToolbarForScrollFrame(offset) };
    })
    .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
      this.handleDownloadListDidScroll();
    })
    .onScrollStop(() => {
      this.rememberDownloadScrollOffset();
    })
  }

  @Builder
  private downloadThumbnailWaterFlow() {
    WaterFlow({
      footer: this.downloadListEdgeSpacer(),
      scroller: this.downloadScroller,
      layoutMode: WaterFlowLayoutMode.SLIDING_WINDOW
    }) {
      ForEach(this.visibleItems, (item: DownloadInfo, index: number) => {
        FlowItem() {
          this.downloadCardContent(item, index)
        }
        .width('100%')
        .margin({ top: index < this.downloadColumnCount() ? this.downloadContentStartOffset() : 0 })
        .reuseId('download-thumb-flow-item')
        .onVisibleAreaChange([0.0, 0.01], (visible: boolean, _ratio: number) => {
          this.updateVisibleTranslationItem(index, visible);
        })
        .animation({ duration: 220, curve: Curve.EaseOut })
        .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseInOut }))
      }, (item: DownloadInfo) => item.gid.toString() + ':' + this.downloadColumnCount().toString())
    }
    .columnsTemplate(this.downloadWaterFlowColumnsTemplate())
    .columnsGap(this.downloadCardGap())
    .rowsGap(this.downloadCardGap())
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true, effectEdge: EffectEdge.START | EffectEdge.END })
    .scrollBar(BarState.Auto)
    .width('100%')
    .height('100%')
    .cachedCount(10)
    .padding({
      left: this.downloadContentPadding(),
      right: this.downloadContentPadding()
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateDownloadContentWidthFromArea(newArea.width as number);
    })
    .onAppear(() => {
      this.restoreDownloadScrollOffset();
    })
    .onScrollFrameBegin((offset: number, _state: ScrollState) => {
      return { offsetRemain: this.updateToolbarForScrollFrame(offset) };
    })
    .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
      this.handleDownloadListDidScroll();
    })
    .onScrollIndex((first: number, last: number) => {
      this.setVisibleTranslationRange(first, last);
    })
    .onScrollStop(() => {
      this.rememberDownloadScrollOffset();
    })
  }

  private restoreDownloadScrollOffset(): void {
    this.syncDownloadContentWidthFromWindow();
    if (!this.downloadBrowsePositionLoaded || this.downloadBrowsePositionRestored || this.visibleItems.length === 0) {
      return;
    }
    const position: BrowsePosition = ehBrowsePositionStore.getDownloadPosition();
    let targetIndex = -1;
    if (position.anchorId.length > 0) {
      for (let i = 0; i < this.visibleItems.length; i++) {
        if (this.visibleItems[i].gid.toString() === position.anchorId) {
          targetIndex = i;
          break;
        }
      }
    }
    if (targetIndex < 0) {
      targetIndex = Math.min(position.anchorIndex, this.visibleItems.length - 1);
    }
    this.downloadFirstVisibleIndex = targetIndex;
    this.downloadBrowsePositionRestored = true;
    this.restoringDownloadBrowsePosition = true;
    setTimeout(() => {
      if (targetIndex === position.anchorIndex && position.offset > 0) {
        this.downloadScroller.scrollTo({ xOffset: 0, yOffset: position.offset });
      } else if (targetIndex > 0) {
        const scrollIndex = galleryListMode() === 'Thumb' ? targetIndex :
          Math.floor(targetIndex / Math.max(1, this.downloadColumnCount())) + 1;
        this.downloadScroller.scrollToIndex(scrollIndex);
      }
      setTimeout(() => {
        this.restoringDownloadBrowsePosition = false;
      }, 80);
    }, 0);
  }

  private rememberDownloadScrollOffset(): void {
    if (this.restoringDownloadBrowsePosition) {
      return;
    }
    if (this.visibleItems.length === 0) {
      this.downloadScrollOffset = 0;
      if (this.downloadBrowsePositionLoaded) {
        ehBrowsePositionStore.updateDownloadPosition('', 0, 0);
      }
      return;
    }
    this.downloadScrollOffset = normalizeSceneScrollOffset(this.downloadScroller.currentOffset().yOffset);
    if (!this.downloadBrowsePositionLoaded) {
      return;
    }
    const index = Math.max(0, Math.min(this.downloadFirstVisibleIndex, this.visibleItems.length - 1));
    const anchorId = this.visibleItems.length > 0 ? this.visibleItems[index].gid.toString() : '';
    ehBrowsePositionStore.updateDownloadPosition(anchorId, index, this.downloadScrollOffset);
  }

  build() {
    if (this.showTagSearch) {
      GalleryListScene({
        sceneTitle: this.tagSearchTitle.length > 0 ? this.tagSearchTitle : 'Search',
        listMode: 'Search',
        sourceRoute: GalleryRoute.Home,
        initialKeyword: this.tagSearchKeyword,
        initialSearchMode: this.tagSearchMode,
        initialSearchCategory: this.tagSearchCategory,
        initialAdvancedSearchEnabled: false,
        initialAdvanceSearch: DEFAULT_ADVANCE_SEARCH,
        initialSearchSubmitted: true,
        initialImagePath: this.tagSearchImagePath,
        initialImageUseSimilarityScan: this.tagSearchImageUseSimilarity,
        initialImageOnlySearchCovers: this.tagSearchImageOnlyCovers,
        initialImageShowExpunged: this.tagSearchImageShowExpunged,
        isSearchResultScene: true,
        onBack: () => {
          this.closeTagSearch();
        }
      })
        .transition(this.restoreDetailWithFade ?
          TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }) :
          TransitionEffect.move(TransitionEdge.END).animation({ duration: 300, curve: Curve.EaseOut }))
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          if (!this.searchSubmitted) {
            List({ space: 0 }) {
              ListItem() {
                Row().width('100%').height(this.floatingToolbarHeight() + 8)
              }
              ListItem() {
                this.downloadSearchSuggestionPlaceholder()
              }
            }
            .width('100%')
            .height('100%')
            .padding({
              left: this.downloadContentPadding(),
              right: this.downloadContentPadding()
            })
          } else if (this.visibleItems.length === 0) {
            Column() {
              Text(uiText('Downloads'))
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(themePrimaryText())
              Text(this.items.length === 0 ? uiText('Download items will be shown here') :
                uiText('No items match the current filter'))
                .fontSize(14)
                .fontColor(themeSecondaryText())
                .margin({ top: 10 })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            if (galleryListMode() === 'Thumb') {
              this.downloadThumbnailWaterFlow()
            } else {
              this.downloadStandardList()
            }
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(themePageBackground())
        .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }),
          TransitionEffect.OPACITY.animation({ duration: 1, delay: 300, curve: Curve.Linear })))
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.updateDownloadContentWidthFromArea(newArea.width as number);
          const height = newArea.height as number;
          if (height > 0 && !Number.isNaN(height)) {
            this.viewportHeight = height;
          }
        })

        GalleryHomeNavBarHost({
          toolbarState: this.toolbarState(),
          statusBarHeight: this.statusBarVp(),
          title: this.selectedDownloadLabel === DOWNLOAD_LABEL_FILTER_ALL ? 'Downloads' :
            (this.selectedDownloadLabel.length === 0 ? 'Default' : this.selectedDownloadLabel),
          keyword: this.query,
          filterActive: this.advancedPanelVisible || this.advancedSearchEnabled ||
            this.searchCategory !== GalleryCategory.None || this.minRating > 0,
          showSearchButton: !this.searchBarVisible,
          showFavoriteButton: !this.searchBarVisible,
          showBackButton: this.searchBarVisible,
          searchMode: this.searchBarVisible,
          searchPlaceholder: 'Search downloads',
          searchShowsAdvancedButton: true,
          toolbarHeight: uiAdaptiveToolbarHeight(this.downloadContentWidth),
          onMenu: () => {
            if (this.searchBarVisible) {
              this.closeDownloadSearchBar();
            } else {
              this.onMenu();
            }
          },
          onBack: () => {
            this.closeDownloadSearchBar();
          },
          onKeywordChange: (value: string) => {
            this.updateDownloadKeyword(value);
          },
          onSearchFocus: () => {
            this.openDownloadSearchSuggestions();
          },
          onSearch: () => {
            if (this.searchBarVisible) {
              this.applyDownloadSearch();
            } else {
              this.openDownloadSearchBar();
            }
          },
          onAdvanced: () => {
            this.toggleAdvancedPanel();
          },
          onFavoriteButton: () => {
            this.openDownloadLabelDrawer();
          }
        })

        if (this.advancedPanelVisible) {
          PopupScrim({
            showCutout: this.downloadContentWidth > 20 && this.advancedPopupHeight > 0,
            positionedCutout: true,
            cutoutX: 10,
            cutoutY: this.statusBarVp() + uiAdaptiveToolbarHeight(this.downloadContentWidth) + 8,
            cutoutWidth: Math.max(0, this.downloadContentWidth - 20),
            cutoutHeight: this.advancedPopupHeight,
            cutoutRadius: uiRadius(8),
            onDismiss: () => {
              this.closeAdvancedPanel();
            }
          })
            .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseInOut }))
            .zIndex(15)

          Stack({ alignContent: Alignment.Top }) {
            SearchAdvancedPanel({
              searchModeValue: this.searchMode,
              searchCategory: this.searchCategory,
              advancedSearchEnabled: this.advancedSearchEnabled,
              advanceSearch: this.advanceSearch,
              searchFilterEnabled: true,
              minRating: this.minRating,
              pageFrom: -1,
              pageTo: -1,
              panelMaxHeight: this.advancedPanelMaxHeight(),
              onSearchModeChange: (mode: ListMode) => {
                this.searchMode = mode;
                this.searchSubmitted = false;
                this.refreshDownloadRows();
              },
              onSearchCategoryChange: (category: number) => {
                this.searchCategory = category;
                this.searchSubmitted = false;
                this.refreshDownloadRows();
              },
              onAdvancedEnabledChange: (enabled: boolean) => {
                this.advancedSearchEnabled = enabled;
                this.searchSubmitted = false;
                this.refreshDownloadRows();
              },
              onAdvanceSearchChange: (flags: number) => {
                this.advanceSearch = flags;
                this.searchSubmitted = false;
                this.refreshDownloadRows();
              },
              onMinRatingChange: (rating: number) => {
                this.minRating = rating;
                this.searchSubmitted = false;
                this.refreshDownloadRows();
              },
              onClose: () => {
                this.closeAdvancedPanel();
              },
              onSearch: () => {
                this.closeAdvancedPanel();
                this.applyDownloadSearch();
              }
            })
              .constraintSize({ maxHeight: this.advancedPanelMaxHeight() })
              .onAreaChange((_oldArea: Area, newArea: Area) => {
                this.advancedPopupHeight = Number.parseFloat(newArea.height.toString());
              })
              .transition(TransitionEffect.move(TransitionEdge.TOP)
                .animation({ duration: 180, curve: Curve.EaseOut }))
          }
            .width('100%')
            .height('100%')
            .padding({
              top: this.statusBarVp() + uiAdaptiveToolbarHeight(this.downloadContentWidth) + 8,
              left: 10,
              right: 10
            })
            .hitTestBehavior(HitTestMode.Transparent)
            .zIndex(16)
        }

        FloatingActionDock({ side: this.floatingActionSide }) {
          if (this.searchBarVisible && !this.searchSubmitted) {
            SearchActionColumn({
              side: this.floatingActionSide,
              onSearch: () => {
                this.applyDownloadSearch();
              },
              onSideChange: (side: string) => {
                this.floatingActionSideController.handleManualSide(side);
              }
            })
          } else {
            DownloadToolColumn({
              expanded: this.downloadActionsExpanded,
              hasSelection: this.downloadSelectionCount() > 0,
              canOperate: this.downloadSelectionCount() > 0 || this.visibleItems.length > 0,
              canJump: this.downloadJumpTotalPages() > 1,
              canRandom: this.visibleItems.length > 0,
              maxExpandedHeight: this.downloadToolActionsMaxHeight(),
              showTranslationButton: this.translationButtonsVisible,
              translationEnabled: this.translationEnabled,
              side: this.floatingActionSide,
              onToggle: () => {
                this.downloadActionsExpanded = !this.downloadActionsExpanded;
              },
              onStatus: () => {
                this.openDownloadStatusPanel();
              },
              onJump: () => {
                this.openDownloadJumpPanel();
              },
              onStart: () => {
                this.startSelectedOrFiltered();
              },
              onStop: () => {
                this.stopSelectedOrFiltered();
              },
              onRestore: () => {
                this.restoreDownloadedItems();
              },
              onRandom: () => {
                this.openRandomDownload();
              },
              onTranslate: () => {
                ehTranslationService.setEnabled(!this.translationEnabled);
              },
              onSelectAll: () => {
                this.selectAllVisibleFinishedDownloads();
              },
              onDelete: () => {
                this.deleteSelectedDownloads();
              },
              onExportZip: () => {
                this.exportSelectedDownloadsZip();
              },
              onLabel: () => {
                this.openMoveSelectedDownloadLabel();
              },
              onSideChange: (side: string) => {
                this.floatingActionSideController.handleManualSide(side);
              }
            })
          }
        }

        if (this.statusHintVisible) {
          Text(this.statusHintText)
            .fontSize(12)
            .fontColor(themePrimaryText())
            .textAlign(TextAlign.Center)
            .backgroundColor(themeSurface())
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(uiRadius(15))
            .shadow({ radius: 8, color: themeShadowColor(), offsetX: 0, offsetY: 2 })
            .maxLines(1)
            .position({
              x: this.downloadContentWidth > 0 ? Math.max(16, this.downloadContentWidth / 2 - 96) : 72,
              y: this.viewportHeight > 0 ? Math.max(180, this.viewportHeight * 0.62) : 420
            })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ y: 12 }))
              .animation({ duration: 140, curve: Curve.EaseOut }))
            .zIndex(18)
        }

        if (this.downloadJumpPanelVisible) {
          PopupScrim({
            showCutout: this.downloadJumpPopupHeight > 0,
            positionedCutout: true,
            cutoutX: this.downloadContentWidth > 0 ? Math.max(12, this.downloadContentWidth - 244) : 100,
            cutoutY: this.viewportHeight > 0 ? Math.max(96, this.viewportHeight - 210) : 360,
            cutoutWidth: 220,
            cutoutHeight: this.downloadJumpPopupHeight,
            cutoutRadius: uiRadius(8),
            onDismiss: () => {
              this.closeDownloadJumpPanel();
            }
          })
            .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
            .zIndex(20)

          Column({ space: 10 }) {
            Text(uiText('Jump'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(themePrimaryText())
              .width('100%')
            Row({ space: 8 }) {
              TextInput({ text: this.downloadJumpDraft, placeholder: (this.downloadJumpPageIndex + 1).toString() })
                .height(uiSearchFieldHeight())
                .layoutWeight(1)
                .type(InputType.Number)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .padding({ left: 10, right: 10 })
                .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
                .onChange((value: string) => {
                  this.downloadJumpDraft = value;
                })
                .onSubmit(() => {
                  this.submitDownloadJump();
                  this.closeDownloadJumpPanel();
                })
              Text('/ ' + this.downloadJumpTotalPages().toString())
                .fontSize(13)
                .fontColor(themeSecondaryText())
            }

            Button(uiText('Jump'))
              .height(36)
              .width('100%')
              .fontSize(13)
              .fontColor(uiMaterialForegroundColor(themeOnPrimaryText()))
              .backgroundColor(uiMaterialBackground(themePrimaryColor()))
              .borderRadius(uiRadius(4))
              .backgroundEffect(uiTransparentButtonBackgroundEffect())
              .systemMaterial(uiButtonMaterial())
              .onClick(() => {
                this.submitDownloadJump();
                this.closeDownloadJumpPanel();
              })
          }
          .width(220)
          .padding(12)
          .backgroundColor(themeSurface())
          .borderRadius(uiRadius(8))
          .shadow({
            radius: 12,
            color: themeShadowColor(),
            offsetX: 0,
            offsetY: 4
          })
          .position({
            x: this.downloadContentWidth > 0 ? Math.max(12, this.downloadContentWidth - 244) : 100,
            y: this.viewportHeight > 0 ? Math.max(96, this.viewportHeight - 210) : 360
          })
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.downloadJumpPopupHeight = Number.parseFloat(newArea.height.toString());
          })
          .zIndex(21)
        }

        if (this.statusFilterPanelVisible) {
          DownloadStatusFilterOverlay({
            selectedStatuses: $statusFilterDraft,
            onCancel: () => {
              this.closeDownloadStatusPanel();
            },
            onApply: () => {
              this.applyDownloadStatusFilter();
            }
          })
            .zIndex(24)
            .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
        }

        if (this.blockingBusyVisible) {
          BlockingBusyOverlay({ message: this.blockingBusyMessage })
            .zIndex(40)
            .transition(TransitionEffect.OPACITY.animation({ duration: 140, curve: Curve.EaseOut }))
        }

        if (this.showReader) {
          ReaderSessionScene({
            restoreAppChromeOnExit: true,
            onBack: () => {
              this.closeEmbeddedReader();
            }
          })
            .width('100%')
            .height('100%')
            .zIndex(50)
        }
      if (this.showDetail || this.downloadLabelManagerVisible) {
        SplitPaneDivider({
          x: this.useSplitLayout() ? this.splitListPaneWidth() : 0,
          dividerVisible: this.useSplitLayout(),
          dragging: this.splitDragging,
          fadeTransition: this.restoreDetailWithFade,
          onSplitDragStart: () => {
            this.splitDragging = true;
            this.splitDragStartWidth = this.splitListPaneWidth();
          },
          onSplitDragUpdate: (offsetX: number) => {
            this.updateSplitPaneByOffset(offsetX);
          },
          onSplitDragEnd: () => {
            this.finishSplitPaneDrag();
          }
        })

      }

      if (this.showDetail) {
        GalleryDetailHostScene({
          detailLink: this.detailLink,
          listRequestUrl: '',
          onBack: () => {
            this.closeDetail();
          },
          onShowEmbeddedReader: () => {
            this.showReader = true;
          },
          onOpenSearch: (request: DetailSearchRequest) => {
            this.openRemoteSearch(request);
          },
          onDetailLoaded: (detail: GalleryDetail) => {
            this.detail = detail;
            ehDownloadStore.updateGallery(detail);
            this.persistDownloads();
          }
        })
          .width(this.useSplitLayout() ? this.splitSidePaneWidth() : '100%')
          .height('100%')
          .position({ x: this.useSplitLayout() ? this.splitListPaneWidth() + 1 : 0, y: 0 })
          .onTouch((event: TouchEvent) => {
            if (shouldUpdateSplitPaneFocus(event)) {
              this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
            }
          })
          .zIndex(5)
          .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
          .transition(this.restoreDetailWithFade ?
            TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }) :
            TransitionEffect.move(TransitionEdge.END).animation({ duration: 300, curve: Curve.EaseOut }))
      }

      if (this.downloadLabelManagerVisible) {
        DownloadLabelManagerScene({
          labels: this.labels,
          statusBarHeight: this.statusBarVp(),
          onBack: () => {
            this.closeDownloadLabelManager();
          },
          onAdd: () => {
            this.openAddDownloadLabel();
          },
          onRename: (label: string, value: string) => {
            this.renameDownloadLabel(label, value);
          },
          onDelete: (label: string) => {
            this.confirmDeleteDownloadLabel(label);
          },
          onMove: (from: number, to: number) => {
            this.moveDownloadLabel(from, to);
          }
        })
          .width(this.useSplitLayout() ? this.splitSidePaneWidth() : '100%')
          .height('100%')
          .position({ x: this.useSplitLayout() ? this.splitListPaneWidth() + 1 : 0, y: 0 })
          .onTouch((event: TouchEvent) => {
            if (shouldUpdateSplitPaneFocus(event)) {
              this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
            }
          })
          .zIndex(29)
          .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.move(TransitionEdge.END).animation({ duration: 260, curve: Curve.EaseOut }),
            TransitionEffect.move(TransitionEdge.END).animation({ duration: 220, curve: Curve.EaseIn })))
      }

      if (this.downloadLabelDrawerVisible) {
        RightSidePanelLayer({
          layerWidth: this.downloadListOverlayWidth(),
          drawerLeft: this.downloadLabelDrawerLeft(),
          drawerOffsetX: this.downloadLabelDrawerOffsetX,
          overlayOpacity: this.downloadLabelDrawerOverlayOpacity,
          layerZIndex: 30,
          onClose: () => {
            this.closeDownloadLabelDrawer();
          }
        }) {
          DownloadLabelDrawer({
            statusBarHeight: this.statusBarVp(),
            labels: this.labels,
            items: this.items,
            selectedLabel: this.selectedDownloadLabel,
            onSelect: (label: string) => {
              this.selectDownloadLabel(label);
            },
            onDefaultLabel: () => {
              this.openDefaultDownloadLabelDialog();
            },
            onSettings: () => {
              this.openDownloadLabelManager();
            }
          })
        }
      }

      if (this.defaultDownloadLabelDialogVisible) {
        DownloadLabelSelectionDialog({
          title: 'Default download label',
          labels: this.labels,
          selectedLabel: defaultDownloadLabelChoice() === DOWNLOAD_LABEL_OPTION_ASK ?
            DOWNLOAD_LABEL_OPTION_ASK : defaultDownloadLabelChoice(),
          includeAsk: true,
          panelMaxHeight: Math.max(320, this.viewportHeight - 24),
          onSelect: (label: string) => {
            this.selectDefaultDownloadLabel(label);
          },
          onClose: () => {
            this.defaultDownloadLabelDialogVisible = false;
          }
        })
          .width(this.downloadListOverlayWidth())
          .height('100%')
          .position({ x: 0, y: 0 })
          .zIndex(35)
      }

      if (this.moveDownloadLabelDialogVisible) {
        DownloadLabelSelectionDialog({
          title: 'Move to label',
          labels: this.labels,
          selectedLabel: '',
          includeAsk: false,
          showAddButton: true,
          panelMaxHeight: Math.max(320, this.viewportHeight - 24),
          onSelect: (label: string) => {
            this.moveSelectedDownloadsToLabel(label);
          },
          onAdd: () => {
            this.openAddDownloadLabel();
          },
          onClose: () => {
            this.moveDownloadLabelDialogVisible = false;
          }
        })
          .width(this.downloadListOverlayWidth())
          .height('100%')
          .position({ x: 0, y: 0 })
          .zIndex(35)
      }

      if (this.downloadLabelEditDialogVisible) {
        DownloadLabelEditDialog({
          title: 'New label',
          value: $downloadLabelEditValue,
          onConfirm: () => {
            this.confirmDownloadLabelEdit();
          },
          onClose: () => {
            this.downloadLabelEditDialogVisible = false;
          }
        })
          .width(this.moveDownloadLabelDialogVisible ?
            this.downloadListOverlayWidth() : this.downloadSideOverlayWidth())
          .height('100%')
          .position({
            x: this.moveDownloadLabelDialogVisible ? 0 : this.downloadSideOverlayLeft(),
            y: 0
          })
          .zIndex(36)
      }
      }
      .width(this.useSplitLayout() ? this.splitListPaneWidth() : '100%')
      .height('100%')
      .backgroundColor(themePageBackground())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .onTouch((event: TouchEvent) => {
        if (shouldUpdateSplitPaneFocus(event)) {
          this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
        }
      })
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Left, distance: 28 })
          .onActionEnd((event: GestureEvent | undefined) => {
            this.handleOpenDownloadLabelDrawerPan(event);
          })
      )
      .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.updateSceneContentWidth(areaDimensionToVp(newArea.width, (value: number) => this.getUIContext().px2vp(value)));
      })
    }
  }

  private showDeleteProcessedZipDialog(result: DownloadZipImportResult): void {
    const message = uiStatusText('ZIP import summary: processed ' + result.processed.toString() + ', skipped ' +
      result.skipped.toString() + '. Delete processed archives?');
    this.getUIContext().getPromptAction().showDialog({
      title: uiText('ZIP archives processed'),
      message: message,
      buttons: [
        {
          text: uiText('Keep'),
          color: themeSecondaryText()
        },
        {
          text: uiText('Delete'),
          color: themeAccentTextColor()
        }
      ]
    }).then((data) => {
      if (data.index !== 1) {
        return;
      }
      const removed = ehDownloadFileStore.removeFiles(result.processedPaths);
      this.showFloatingStatus('Deleted processed ZIP archives: ' + removed.toString());
    }).catch(() => {});
  }
}

