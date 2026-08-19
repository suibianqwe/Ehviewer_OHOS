import { common } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import {
  GalleryCategory,
  GalleryDetail,
  GalleryInfo,
  GalleryRoute
} from '../model/GalleryModels';
import {
  DOWNLOAD_LOCATION_APP_FILES,
  DOWNLOAD_LOCATION_DOWNLOADS,
  ehDownloadFileStore
} from '../services/EhDownloadFileStore';
import { ehDownloadManager } from '../services/EhDownloadManager';
import { DownloadInfo, DownloadLabel, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
import { TRANSLATION_BUTTONS_VISIBLE_KEY, ehSettingsStore } from '../services/EhSettingsStore';
import {
  TRANSLATION_ENABLED_KEY,
  ehTranslationService,
  translationPriorityForIndex
} from '../services/EhTranslationService';
import {
  DownloadRestoreResult,
  DownloadZipImportResult,
  restoreDownloadedItemsAndArchives
} from '../services/DownloadZipImportService';
import {
  confirmCellularNetworkWarningForSession,
  shouldConfirmCellularNetworkOperation
} from '../services/EhCellularNetworkGuard';
import { DEFAULT_ADVANCE_SEARCH, EhUrl, ListMode } from '../services/EhUrl';
import { galleryMatchesLocalSearch, LocalGallerySearchOptions } from '../services/LocalGallerySearch';
import { DetailSearchRequest } from '../services/GalleryDetailActionSupport';
import {
  createEmptyGalleryDetailLink,
  createGalleryDetailLinkFromGallery,
  GalleryDetailLink,
  initialDetailForLink
} from '../services/GalleryDetailModule';
import {
  applyAppChromeImmersiveMode,
  isEmbeddedReaderActive,
  leaveEmbeddedReaderFullscreen,
  mainContentWidthFallbackVp,
  rememberMainContentWidthVp
} from '../services/EhWindowImmersive';
import { LANGUAGE_REVISION_KEY, STATUS_BAR_HEIGHT_KEY, nextFloatingToolbarOffset, runDetailBackHandler, setActiveBackHandler } from '../shared/EhShared';
import { sortedStringKey, toggleStringValue } from '../shared/StringCollectionSupport';
import { GalleryCardScrollAnchor } from '../shared/GalleryCardScrollAnchor';
import {
  cloneGalleryDetail,
  cloneGalleryInfo,
  createEmptyDownloadInfo,
  createEmptyDetail,
  currentGallerySite,
  defaultDownloadLabelChoice,
  downloadProgressText,
  downloadSizeText,
  downloadStateColor,
  downloadStateLabel,
  DOWNLOAD_STATUS_FILTER_OPTIONS,
  filterDownloadItems,
  galleryDetailCardPreferredWidth,
  galleryListMode,
  galleryThumbnailPreferredColumnWidth,
  getAbilityContext,
  saveDefaultDownloadLabelChoice,
  uiText,
  uiStatusText,
  uiValue
} from '../shared/EhShared';
import {
  themeDividerColor,
  themeFieldBackground,
  themeOnPrimaryText,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeScrimColor,
  themeSecondaryText,
  themeSelectedBackground,
  themeSelectedText,
  themeShadowColor,
  themeSurface,
  themeTertiaryText
} from '../shared/EhTheme';
import { FloatingToolbarHost } from './NavigationComponents';
import { GalleryListRow, GalleryThumbCard } from './GalleryCards';
import { ActionBubble, GalleryListScene } from './GalleryScenes';
import { GalleryDetailHostScene } from './GalleryDetailHostScene';
import { ReaderSessionScene } from './ReaderHostScene';
import { BlockingBusyOverlay } from './BlockingBusyOverlay';
import {
  DOWNLOAD_LABEL_FILTER_ALL,
  DOWNLOAD_LABEL_OPTION_ASK,
  DownloadLabelDrawer,
  DownloadLabelEditDialog,
  DownloadLabelManagerScene,
  DownloadLabelSelectionDialog
} from './DownloadLabelComponents';
import {
  RightSidePanelLayer,
  SIDE_PANEL_WIDTH,
  sidePanelLeft,
  shouldOpenSidePanel
} from './SidePanelComponents';
import {
  applyTagSuggestionToKeyword,
  buildSearchSuggestions,
  recordSearchHistory,
  SearchAdvancedPanel,
  SearchSuggestionItem,
  SearchSuggestionList,
  SearchSummaryStrip
} from './GallerySearchScenes';
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
  shouldUpdateSplitPaneFocus
} from './SplitPaneSupport';

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
const ACTION_BUBBLE_SIZE: number = 44;
const ACTION_BUBBLE_GAP: number = 8;
const ACTION_BUBBLE_PRIMARY_SIZE: number = 54;
const ACTION_BUBBLE_PRIMARY_GAP: number = 10;
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
  @State toolbarOffsetY: number = 0;
  @State downloadActionsExpanded: boolean = false;
  @State statusHintText: string = '';
  @State statusHintVisible: boolean = false;
  @State blockingBusyVisible: boolean = false;
  @State blockingBusyMessage: string = 'Loading...';
  @State downloadJumpPanelVisible: boolean = false;
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
  private downloadScroller: Scroller = new Scroller();
  private cardScrollAnchor: GalleryCardScrollAnchor = new GalleryCardScrollAnchor();
  private splitDragStartWidth: number = 0;
  private downloadScrollOffset: number = 0;
  private toolbarRestoring: boolean = false;
  private cellularWarningDialogOpen: boolean = false;
  private deleteConfirmationDialogOpen: boolean = false;
  private downloadCardStates: Map<number, DownloadCardState> = new Map<number, DownloadCardState>();
  private translationVisibleItems: number[] = [];

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
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
    this.loadDownloads();
    setTimeout(() => {
      this.syncSceneContentWidthFromWindow();
      this.syncDownloadContentWidthFromWindow();
    }, 0);
  }

  aboutToDisappear(): void {
    this.cardScrollAnchor.clear();
    this.saveNavigationCache();
    this.unsubscribeStore();
    this.unsubscribeDownloadManager();
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
    return this.statusBarVp() + 56;
  }

  private toolbarVisibleHeight(): number {
    return Math.max(0, Math.min(this.floatingToolbarHeight(), this.floatingToolbarHeight() + this.toolbarOffsetY));
  }

  private downloadContentStartOffset(): number {
    return this.toolbarVisibleHeight();
  }

  private downloadListViewportHeight(): number {
    if (this.viewportHeight <= 0) {
      return 1;
    }
    return Math.max(1, this.viewportHeight - this.downloadContentStartOffset());
  }

  private advancedPanelMaxHeight(): number {
    if (this.viewportHeight <= 0) {
      return 520;
    }
    return Math.max(360, this.viewportHeight - this.statusBarVp() - 56 - 28);
  }

  private downloadToolActionsMaxHeight(): number {
    if (this.viewportHeight <= 0) {
      return 360;
    }
    const reservedTop = this.statusBarVp() + 56 + 8;
    const reservedBottom = 24 + ACTION_BUBBLE_PRIMARY_SIZE + ACTION_BUBBLE_PRIMARY_GAP;
    return Math.max(ACTION_BUBBLE_SIZE, this.viewportHeight - reservedTop - reservedBottom);
  }

  private updateToolbarForScrollFrame(scrollOffset: number): number {
    const offset = normalizeSceneScrollOffset(this.downloadScroller.currentOffset().yOffset);
    if (offset <= 4) {
      this.toolbarRestoring = false;
      this.toolbarOffsetY = 0;
      return scrollOffset;
    }
    if (scrollOffset > 0 && this.toolbarVisibleHeight() > 0) {
      const previousOffsetY = this.toolbarOffsetY;
      this.toolbarRestoring = false;
      this.toolbarOffsetY = nextFloatingToolbarOffset(this.toolbarOffsetY, scrollOffset, offset, this.floatingToolbarHeight());
      const consumedOffset = Math.max(0, previousOffsetY - this.toolbarOffsetY);
      return Math.max(0, scrollOffset - consumedOffset);
    }
    if (scrollOffset < 0 && this.toolbarOffsetY < 0) {
      this.restoreToolbarOnReverseScroll();
    }
    return scrollOffset;
  }

  private restoreToolbarOnReverseScroll(): void {
    if (this.toolbarRestoring) {
      return;
    }
    this.toolbarRestoring = true;
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.toolbarOffsetY = 0;
    });
    setTimeout(() => {
      this.toolbarRestoring = false;
    }, 320);
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
        { text: uiText('Delete'), color: themePrimaryColor() }
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
    for (let i = 0; i < visible.length; i++) {
      if (galleryMatchesLocalSearch(visible[i], this.query, options)) {
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
      this.updateDownloadKeyword(applyTagSuggestionToKeyword(this.query, suggestion.query));
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

  private selectAllFinishedDownloads(): void {
    let selected = '';
    let count = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].state === DownloadState.Finish) {
        if (selected.length === 0) {
          selected = this.selectedKey(this.items[i].gid);
        } else {
          selected += this.items[i].gid.toString() + '|';
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
    return 8;
  }

  private downloadContentPadding(): number {
    return 8;
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
    return Math.max(1, Math.floor((availableWidth + gap) / (preferred + gap)));
  }

  private downloadWaterFlowColumnsTemplate(): string {
    const columns = Math.max(1, this.downloadColumnCount());
    let template = '';
    for (let i = 0; i < columns; i++) {
      template += '1fr ';
    }
    return template.trim();
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
      (this.showDetail || this.downloadLabelManagerVisible) && !this.showReader && !this.showTagSearch;
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
  }

  private setVisibleTranslationRange(start: number, end: number): void {
    this.translationVisibleItems = [];
    this.translationVisibleStart = start;
    this.translationVisibleEnd = end;
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
          color: themePrimaryColor()
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
          color: themePrimaryColor()
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
        .borderRadius(6)
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4 })
  }

  @Builder
  private downloadCardContent(item: DownloadInfo, index: number) {
    Column() {
      if (galleryListMode() === 'Thumb') {
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
  private downloadStandardList() {
    List({ space: 0, scroller: this.downloadScroller }) {
      ListItemGroup({ header: this.downloadListEdgeSpacer() }) {
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
    .height(this.downloadListViewportHeight())
    .lanes(this.downloadColumnCount(), this.downloadCardGap())
    .cachedCount(4)
    .padding({
      left: this.downloadContentPadding(),
      right: this.downloadContentPadding()
    })
    .translate({ y: this.downloadContentStartOffset() })
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
      this.rememberDownloadScrollOffset();
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
        .margin({ top: index < this.downloadColumnCount() ? this.downloadCardGap() : 0 })
        .reuseId('download-thumb-flow-item')
        .animation({ duration: 220, curve: Curve.EaseOut })
        .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseInOut }))
      }, (item: DownloadInfo) => item.gid.toString())
    }
    .columnsTemplate(this.downloadWaterFlowColumnsTemplate())
    .columnsGap(this.downloadCardGap())
    .rowsGap(this.downloadCardGap())
    .width('100%')
    .height(this.downloadListViewportHeight())
    .cachedCount(4)
    .padding({
      left: this.downloadContentPadding(),
      right: this.downloadContentPadding()
    })
    .translate({ y: this.downloadContentStartOffset() })
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
      this.rememberDownloadScrollOffset();
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
    if (this.downloadScrollOffset > 0) {
      setTimeout(() => {
        this.downloadScroller.scrollTo({ xOffset: 0, yOffset: this.downloadScrollOffset });
      }, 0);
    }
  }

  private rememberDownloadScrollOffset(): void {
    this.downloadScrollOffset = normalizeSceneScrollOffset(this.downloadScroller.currentOffset().yOffset);
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
    } else if (this.showReader) {
      ReaderSessionScene({
        restoreAppChromeOnExit: true,
        onBack: () => {
          this.closeEmbeddedReader();
        }
      })
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
      Column() {
      FloatingToolbarHost({
        kind: this.searchBarVisible ? 'search' : 'title',
        title: this.selectedDownloadLabel === DOWNLOAD_LABEL_FILTER_ALL ? 'Downloads' :
          (this.selectedDownloadLabel.length === 0 ? 'Default' : this.selectedDownloadLabel),
        keyword: this.query,
        searchPlaceholder: 'Search downloads',
        filterActive: this.advancedPanelVisible || this.advancedSearchEnabled ||
          this.searchCategory !== GalleryCategory.None || this.minRating > 0,
        showSearchButton: !this.searchBarVisible,
        showBackButton: this.searchBarVisible,
        showRefreshButton: false,
        showFavoriteButton: !this.searchBarVisible,
        searchShowsAdvancedButton: true,
        toolbarOffsetY: this.toolbarOffsetY,
        toolbarHeight: 56,
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
      }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          if (!this.searchSubmitted) {
            List({ space: 0 }) {
              ListItem() {
                this.downloadSearchSuggestionPlaceholder()
              }
            }
            .width('100%')
            .height(this.downloadListViewportHeight())
            .padding({
              left: this.downloadContentPadding(),
              right: this.downloadContentPadding()
            })
            .translate({ y: this.downloadContentStartOffset() })
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
            .height(this.downloadListViewportHeight())
            .justifyContent(FlexAlign.Center)
            .translate({ y: this.downloadContentStartOffset() })
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
        .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.updateDownloadContentWidthFromArea(newArea.width as number);
          const height = newArea.height as number;
          if (height > 0 && !Number.isNaN(height)) {
            this.viewportHeight = height;
          }
        })

        if (this.advancedPanelVisible) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(themeScrimColor())
            .onClick(() => {
              this.closeAdvancedPanel();
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
              .transition(TransitionEffect.move(TransitionEdge.TOP)
                .animation({ duration: 180, curve: Curve.EaseOut }))
          }
            .width('100%')
            .height('100%')
            .padding({ top: this.statusBarVp() + 56 + 8, left: 10, right: 10 })
            .hitTestBehavior(HitTestMode.Transparent)
            .zIndex(16)
        }

        Column() {
          if (this.searchBarVisible && !this.searchSubmitted) {
            ActionBubble({
              label: uiText('Search'),
              symbolIcon: $r('sys.symbol.magnifyingglass'),
              isEnabled: true,
              primary: true,
              directTap: true,
              onTapAction: () => {
                this.applyDownloadSearch();
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
                this.selectAllFinishedDownloads();
              },
              onDelete: () => {
                this.deleteSelectedDownloads();
              },
              onExportZip: () => {
                this.exportSelectedDownloadsZip();
              },
              onLabel: () => {
                this.openMoveSelectedDownloadLabel();
              }
            })
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.End)
        .padding({ right: 16, bottom: 24 })
        .hitTestBehavior(HitTestMode.Transparent)

        if (this.statusHintVisible) {
          Text(this.statusHintText)
            .fontSize(12)
            .fontColor(themePrimaryText())
            .textAlign(TextAlign.Center)
            .backgroundColor(themeSurface())
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(15)
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
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(themeScrimColor())
            .onClick(() => {
              this.closeDownloadJumpPanel();
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
                .height(38)
                .layoutWeight(1)
                .type(InputType.Number)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .borderRadius(4)
                .padding({ left: 10, right: 10 })
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
              .fontColor(themeOnPrimaryText())
              .backgroundColor(themePrimaryColor())
              .borderRadius(4)
              .onClick(() => {
                this.submitDownloadJump();
                this.closeDownloadJumpPanel();
              })
          }
          .width(220)
          .padding(12)
          .backgroundColor(themeSurface())
          .borderRadius(8)
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
      }
      .width('100%')
      .height('100%')
      .backgroundColor(themePageBackground())
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }),
        TransitionEffect.OPACITY.animation({ duration: 1, delay: 300, curve: Curve.Linear })))
      }
      }
      .width(this.useSplitLayout() ? this.splitListPaneWidth() : '100%')
      .height('100%')
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
      .width('100%')
      .height('100%')
      .backgroundColor(themePageBackground())
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
          color: themePrimaryColor()
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

@Component
struct DownloadStatusFilterOptionRow {
  @Link selectedStatuses: string[];
  @Prop status: string = '';
  @Prop allOption: boolean = false;

  private isSelected(): boolean {
    return this.allOption ? this.selectedStatuses.length === DOWNLOAD_STATUS_FILTER_OPTIONS.length :
      this.selectedStatuses.indexOf(this.status) >= 0;
  }

  private toggle(): void {
    if (this.allOption) {
      this.selectedStatuses = this.selectedStatuses.length === DOWNLOAD_STATUS_FILTER_OPTIONS.length ? [] :
        DOWNLOAD_STATUS_FILTER_OPTIONS.slice();
      return;
    }
    const next = this.selectedStatuses.slice();
    const index = next.indexOf(this.status);
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(this.status);
    }
    this.selectedStatuses = next;
  }

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row() {
        Text(uiText(this.allOption ? 'All' : this.status))
          .fontSize(15)
          .fontColor(this.isSelected() ? themeSelectedText() : themePrimaryText())
          .layoutWeight(1)
          .textAlign(TextAlign.Start)

        SymbolGlyph(this.isSelected() ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
          .fontSize(21)
          .fontColor([this.isSelected() ? themeSelectedText() : themeTertiaryText()])
      }
      .width('100%')
      .padding({ left: 14, right: 14 })
    }
    .width('100%')
    .height(46)
    .backgroundColor(this.isSelected() ? themeSelectedBackground() : Color.Transparent)
    .borderRadius(8)
    .onClick(() => {
      this.toggle();
    })
  }
}

@Component
struct DownloadStatusFilterOverlay {
  @Link selectedStatuses: string[];
  onCancel: () => void = () => {};
  onApply: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(themeScrimColor())
        .onClick(() => {
          this.onCancel();
        })

      Column({ space: 10 }) {
        Text(uiText('Download status'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .width('100%')

        Text(uiText('Select statuses to display'))
          .fontSize(13)
          .fontColor(themeSecondaryText())
          .width('100%')

        List({ space: 6 }) {
          ListItem() {
            DownloadStatusFilterOptionRow({
              selectedStatuses: $selectedStatuses,
              allOption: true
            })
          }

          ForEach(DOWNLOAD_STATUS_FILTER_OPTIONS, (status: string) => {
            ListItem() {
              DownloadStatusFilterOptionRow({
                selectedStatuses: $selectedStatuses,
                status: status
              })
            }
          }, (status: string) => status)
        }
        .width('100%')
        .height(0)
        .layoutWeight(1)
        .scrollBar(BarState.Auto)

        Row({ space: 10 }) {
          Button(uiText('Cancel'))
            .height(40)
            .layoutWeight(1)
            .fontSize(14)
            .fontColor(themePrimaryText())
            .backgroundColor(themeFieldBackground())
            .borderRadius(8)
            .onClick(() => {
              this.onCancel();
            })

          Button(uiText('OK'))
            .height(40)
            .layoutWeight(1)
            .fontSize(14)
            .fontColor(themeOnPrimaryText())
            .backgroundColor(themePrimaryColor())
            .borderRadius(8)
            .onClick(() => {
              this.onApply();
            })
        }
        .width('100%')
      }
      .width('82%')
      .height('72%')
      .constraintSize({ maxWidth: 380, maxHeight: 560 })
      .padding(16)
      .backgroundColor(themeSurface())
      .borderRadius(12)
      .shadow({ radius: 18, color: themeShadowColor(), offsetY: 8 })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct DownloadToolColumn {
  @Prop expanded: boolean = false;
  @Prop hasSelection: boolean = false;
  @Prop canOperate: boolean = false;
  @Prop canJump: boolean = false;
  @Prop canRandom: boolean = false;
  @Prop maxExpandedHeight: number = 360;
  @Prop showTranslationButton: boolean = true;
  @Prop translationEnabled: boolean = false;
  @State activeActionIndex: number = -1;
  onToggle: () => void = () => {};
  onStatus: () => void = () => {};
  onJump: () => void = () => {};
  onStart: () => void = () => {};
  onStop: () => void = () => {};
  onRestore: () => void = () => {};
  onRandom: () => void = () => {};
  onTranslate: () => void = () => {};
  onSelectAll: () => void = () => {};
  onLabel: () => void = () => {};
  onDelete: () => void = () => {};
  onExportZip: () => void = () => {};

  private toggleExpanded(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.onToggle();
    });
  }

  private actionCount(): number {
    if (!this.expanded) {
      return 0;
    }
    if (this.hasSelection) {
      return this.showTranslationButton ? 8 : 7;
    }
    return this.showTranslationButton ? 7 : 6;
  }

  private primaryIndex(): number {
    return this.actionCount();
  }

  private maxActionRows(): number {
    return Math.max(1, Math.floor((Math.max(ACTION_BUBBLE_SIZE, this.maxExpandedHeight) +
      ACTION_BUBBLE_GAP) / (ACTION_BUBBLE_SIZE + ACTION_BUBBLE_GAP)));
  }

  private actionColumnCount(): number {
    const count = this.actionCount();
    if (count <= 0) {
      return 0;
    }
    return Math.ceil(count / this.maxActionRows());
  }

  private actionRows(): number {
    return Math.min(this.actionCount(), this.maxActionRows());
  }

  private expandedActionsHeight(): number {
    const rows = this.actionRows();
    if (rows <= 0) {
      return 0;
    }
    return rows * ACTION_BUBBLE_SIZE + (rows - 1) * ACTION_BUBBLE_GAP;
  }

  private expandedActionsWidth(): number {
    const columns = this.actionColumnCount();
    if (columns <= 0) {
      return 0;
    }
    return columns * ACTION_BUBBLE_SIZE + (columns - 1) * ACTION_BUBBLE_GAP;
  }

  private toolbarWidth(): number {
    return Math.max(ACTION_BUBBLE_PRIMARY_SIZE, this.expandedActionsWidth());
  }

  private visualActionColumns(): number[] {
    const columns: number[] = [];
    for (let column = this.actionColumnCount() - 1; column >= 0; column--) {
      columns.push(column);
    }
    return columns;
  }

  private actionIndexesForColumn(column: number): number[] {
    const indexes: number[] = [];
    const start = column * this.maxActionRows();
    const end = Math.min(this.actionCount(), start + this.maxActionRows());
    for (let index = start; index < end; index++) {
      indexes.push(index);
    }
    return indexes;
  }

  private actionKind(index: number): string {
    if (this.hasSelection) {
      if (index === 0) return 'select';
      if (index === 1) return 'label';
      if (index === 2) return 'export';
      if (index === 3) return 'delete';
      if (index === 4) return 'jump';
      if (index === 5) return 'start';
      if (index === 6) return 'stop';
      if (index === 7 && this.showTranslationButton) return 'translate';
      return '';
    }
    if (index === 0) return 'status';
    if (index === 1) return 'jump';
    if (index === 2) return 'start';
    if (index === 3) return 'stop';
    if (index === 4) return 'scan';
    if (index === 5 && this.showTranslationButton) return 'translate';
    if (index === (this.showTranslationButton ? 6 : 5)) return 'random';
    return '';
  }

  private actionLabel(index: number): string {
    const kind = this.actionKind(index);
    if (kind === 'select') return uiText('Select all');
    if (kind === 'label') return uiText('Label');
    if (kind === 'export') return uiText('Export');
    if (kind === 'delete') return uiText('Delete');
    if (kind === 'status') return uiText('Status');
    if (kind === 'jump') return uiText('Jump');
    if (kind === 'start') return this.hasSelection ? uiText('Start selected') : uiText('Start filtered');
    if (kind === 'stop') return this.hasSelection ? uiText('Stop selected') : uiText('Stop filtered');
    if (kind === 'scan') return uiText('Scan');
    if (kind === 'translate') {
      return this.translationEnabled ? uiText('Show original titles') : uiText('Translate titles');
    }
    if (kind === 'random') return uiText('Random');
    return '';
  }

  private actionIcon(index: number): Resource {
    const kind = this.actionKind(index);
    if (kind === 'select') return $r('sys.symbol.checkmark_circle');
    if (kind === 'label') return $r('sys.symbol.folder');
    if (kind === 'export') return $r('sys.symbol.archivebox');
    if (kind === 'delete') return $r('sys.symbol.trash');
    if (kind === 'status') return $r('sys.symbol.funnel');
    if (kind === 'jump') return $r('sys.symbol.chevron_forward');
    if (kind === 'start') return $r('sys.symbol.play_fill');
    if (kind === 'stop') return $r('sys.symbol.pause_fill');
    if (kind === 'scan') return $r('sys.symbol.play_arrow_triangle_2_circlepath');
    if (kind === 'translate') return $r('sys.symbol.translate');
    if (kind === 'random') return $r('sys.symbol.shuffle');
    return $r('sys.symbol.more');
  }

  private actionEnabled(index: number): boolean {
    const kind = this.actionKind(index);
    if (kind === 'jump') {
      return this.canJump;
    }
    if (kind === 'start' || kind === 'stop') {
      return this.canOperate;
    }
    if (kind === 'random') {
      return this.canRandom;
    }
    return kind.length > 0;
  }

  private hitActionIndex(x: number, y: number): number {
    const count = this.actionCount();
    if (count > 0) {
      const actionsHeight = this.expandedActionsHeight();
      const actionsWidth = this.expandedActionsWidth();
      const actionsLeft = this.toolbarWidth() - actionsWidth;
      if (x >= actionsLeft && x <= this.toolbarWidth() && y >= 0 && y <= actionsHeight) {
        const relativeX = x - actionsLeft;
        const visualColumn = Math.floor(relativeX / (ACTION_BUBBLE_SIZE + ACTION_BUBBLE_GAP));
        const columnLeft = visualColumn * (ACTION_BUBBLE_SIZE + ACTION_BUBBLE_GAP);
        const row = Math.floor(y / (ACTION_BUBBLE_SIZE + ACTION_BUBBLE_GAP));
        const rowTop = row * (ACTION_BUBBLE_SIZE + ACTION_BUBBLE_GAP);
        if (visualColumn >= 0 && visualColumn < this.actionColumnCount() &&
          relativeX <= columnLeft + ACTION_BUBBLE_SIZE &&
          row >= 0 && row < this.maxActionRows() && y >= rowTop && y <= rowTop + ACTION_BUBBLE_SIZE) {
          const logicalColumn = this.actionColumnCount() - visualColumn - 1;
          const index = logicalColumn * this.maxActionRows() + row;
          return index < count ? index : -1;
        }
      }
      const primaryTop = actionsHeight + ACTION_BUBBLE_PRIMARY_GAP;
      const primaryLeft = this.toolbarWidth() - ACTION_BUBBLE_PRIMARY_SIZE;
      if (x >= primaryLeft && x <= this.toolbarWidth() &&
        y >= primaryTop && y <= primaryTop + ACTION_BUBBLE_PRIMARY_SIZE) {
        return this.primaryIndex();
      }
      return -1;
    }
    if (x >= 0 && x <= ACTION_BUBBLE_PRIMARY_SIZE && y >= 0 && y <= ACTION_BUBBLE_PRIMARY_SIZE) {
      return this.primaryIndex();
    }
    return -1;
  }

  private touchX(event: TouchEvent): number {
    if (event.touches.length > 0) {
      return event.touches[0].x;
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0].x;
    }
    return -1;
  }

  private touchY(event: TouchEvent): number {
    if (event.touches.length > 0) {
      return event.touches[0].y;
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0].y;
    }
    return -1;
  }

  private updateActiveAction(event: TouchEvent): void {
    const index = this.hitActionIndex(this.touchX(event), this.touchY(event));
    if (index !== this.activeActionIndex) {
      this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
        this.activeActionIndex = index;
      });
    }
  }

  private triggerAction(index: number): void {
    if (index < 0) {
      return;
    }
    if (index === this.primaryIndex()) {
      this.toggleExpanded();
      return;
    }
    const kind = this.actionKind(index);
    if (kind === 'select') {
      this.onSelectAll();
    } else if (kind === 'label') {
      this.onLabel();
    } else if (kind === 'export') {
      this.onExportZip();
    } else if (kind === 'delete') {
      this.onDelete();
    } else if (kind === 'status') {
      this.onStatus();
    } else if (kind === 'jump' && this.canJump) {
      this.onJump();
    } else if (kind === 'start' && this.canOperate) {
      this.onStart();
    } else if (kind === 'stop' && this.canOperate) {
      this.onStop();
    } else if (kind === 'scan') {
      this.onRestore();
    } else if (kind === 'translate') {
      this.onTranslate();
    } else if (kind === 'random' && this.canRandom) {
      this.onRandom();
    }
  }

  private handleToolbarTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      this.updateActiveAction(event);
    } else if (event.type === TouchType.Up) {
      const index = this.hitActionIndex(this.touchX(event), this.touchY(event));
      const fallbackIndex = index >= 0 ? index : this.activeActionIndex;
      this.activeActionIndex = -1;
      this.triggerAction(fallbackIndex);
    } else if (event.type === TouchType.Cancel) {
      this.activeActionIndex = -1;
    }
  }

  @Builder
  private actionBubble(index: number) {
    ActionBubble({
      label: this.actionLabel(index),
      symbolIcon: this.actionIcon(index),
      isEnabled: this.actionEnabled(index),
      checked: this.actionKind(index) === 'translate' && this.translationEnabled,
      active: this.activeActionIndex === index,
      directTap: false
    })
  }

  build() {
    Column() {
      if (this.expanded) {
        Row({ space: ACTION_BUBBLE_GAP }) {
          ForEach(this.visualActionColumns(), (column: number) => {
            Column({ space: ACTION_BUBBLE_GAP }) {
              ForEach(this.actionIndexesForColumn(column), (index: number) => {
                Row() {
                  this.actionBubble(index)
                }
                .width(ACTION_BUBBLE_SIZE)
                .height(ACTION_BUBBLE_SIZE)
                .justifyContent(FlexAlign.End)
                .clip(false)
              }, (index: number) => index.toString())
            }
            .width(ACTION_BUBBLE_SIZE)
            .alignItems(HorizontalAlign.End)
          }, (column: number) => column.toString())
        }
        .width(this.expandedActionsWidth())
        .height(this.expandedActionsHeight())
        .alignItems(VerticalAlign.Top)
        .margin({ bottom: 10 })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: 12 }))
          .animation({ duration: 180, curve: Curve.EaseOut }))
      }

      ActionBubble({
        label: uiText('Actions'),
        symbolIcon: this.expanded ? $r('sys.symbol.xmark') : $r('sys.symbol.more'),
        isEnabled: true,
        primary: true,
        active: this.activeActionIndex === this.primaryIndex(),
        directTap: false
      })
    }
    .width(this.toolbarWidth())
    .alignItems(HorizontalAlign.End)
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .onTouch((event: TouchEvent) => {
      this.handleToolbarTouch(event);
    })
  }
}

@ObservedV2
class DownloadCardState {
  @Trace state: DownloadState = DownloadState.None;
  @Trace progressText: string = '';
  @Trace progressValue: number = 0;
  @Trace speedText: string = '';

  update(state: DownloadState, progressText: string, progressValue: number, speedText: string): void {
    if (this.state !== state) {
      this.state = state;
    }
    if (this.progressText !== progressText) {
      this.progressText = progressText;
    }
    if (this.progressValue !== progressValue) {
      this.progressValue = progressValue;
    }
    if (this.speedText !== speedText) {
      this.speedText = speedText;
    }
  }
}

@ComponentV2
struct DownloadCardStatus {
  @Param item: DownloadInfo = createEmptyDownloadInfo();
  @Require @Param cardState: DownloadCardState = new DownloadCardState();
  @Event onStatusTap: (item: DownloadInfo) => void = (_item: DownloadInfo) => {};

  private isDownloading(): boolean {
    return this.cardState.state === DownloadState.Downloading;
  }

  build() {
    Column() {
      Row() {
        Text(uiValue(downloadStateLabel(this.cardState.state)))
          .fontSize(10)
          .fontColor(themeOnPrimaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(downloadStateColor(this.cardState.state))
          .borderRadius(3)
        Text(this.cardState.progressText)
          .fontSize(11)
          .fontColor(themeSecondaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 6 })
          .layoutWeight(1)
        if (this.isDownloading() && this.cardState.speedText.length > 0) {
          Text(this.cardState.speedText)
            .fontSize(11)
            .fontColor(themeTertiaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')

      Row() {
        Progress({ value: this.cardState.progressValue, total: 100, type: ProgressType.Linear })
          .value(this.cardState.progressValue)
          .width('100%')
          .height(4)
          .color(downloadStateColor(this.cardState.state))
          .backgroundColor(themeDividerColor())
      }
        .width('100%')
        .height(4)
        .margin({ top: 6 })
        .clip(true)
        .id('download-progress-' + this.item.gid.toString())
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .backgroundColor(themeSurface())
    .borderRadius(6)
    .onClick(() => {
      this.onStatusTap(this.item);
    })
    .animation({ duration: 180, curve: Curve.EaseOut })
  }
}
