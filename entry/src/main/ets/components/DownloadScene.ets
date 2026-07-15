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
import { DownloadInfo, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
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
import {
  cloneGalleryDetail,
  cloneGalleryInfo,
  createEmptyDownloadInfo,
  createEmptyDetail,
  currentGallerySite,
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
  @State visibleItems: DownloadInfo[] = [];
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
    this.unsubscribeStore = ehDownloadStore.subscribe((items: DownloadInfo[]) => {
      this.items = items;
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
    this.saveNavigationCache();
    this.unsubscribeStore();
    this.unsubscribeDownloadManager();
  }

  onResetVersionChanged(): void {
    this.resetToTopLevel();
  }

  private handleSystemBack(): boolean {
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

  private showBlockingBusy(message: string): void {
    this.blockingBusyMessage = message;
    this.blockingBusyVisible = true;
  }

  private hideBlockingBusy(): void {
    this.blockingBusyVisible = false;
    this.blockingBusyMessage = 'Loading...';
  }

  private computeVisibleDownloadItems(): DownloadInfo[] {
    const visible = filterDownloadItems(this.items, '', this.statusFilters, 'All', this.sortMode,
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

  private toggleDownloadStatus(status: string): void {
    const next = this.statusFilterDraft.slice();
    const index = next.indexOf(status);
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(status);
    }
    this.statusFilterDraft = next;
  }

  private toggleAllDownloadStatuses(): void {
    this.statusFilterDraft = this.statusFilterDraft.length === DOWNLOAD_STATUS_FILTER_OPTIONS.length ? [] :
      DOWNLOAD_STATUS_FILTER_OPTIONS.slice();
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

  private handleDownloadCardTap(item: DownloadInfo): void {
    if (this.downloadSelectionCount() > 0) {
      this.toggleDownloadSelection(item.gid);
      return;
    }
    this.openDetail(item);
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
      this.showDetail && !this.showReader && !this.showTagSearch;
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

  private startAll(): void {
    ehDownloadStore.startAll();
    this.statusText = 'Queued idle and failed downloads';
    this.persistDownloads();
    this.startGlobalDownloadQueue();
  }

  private startSelectedOrAll(): void {
    const selected = this.selectedDownloadItems();
    if (selected.length === 0) {
      this.startAll();
      return;
    }
    for (let i = 0; i < selected.length; i++) {
      ehDownloadStore.startGallery(selected[i].gid);
    }
    this.statusText = 'Queued ' + selected.length.toString() + ' selected downloads';
    this.clearDownloadSelection();
    this.persistDownloads();
    this.startGlobalDownloadQueue();
  }

  private stopAll(): void {
    ehDownloadManager.stopAll();
    this.statusText = 'Stopped waiting downloads';
    this.persistDownloads();
  }

  private stopSelectedOrAll(): void {
    const selected = this.selectedDownloadItems();
    if (selected.length === 0) {
      this.stopAll();
      return;
    }
    for (let i = 0; i < selected.length; i++) {
      ehDownloadManager.stopGallery(selected[i].gid);
    }
    this.statusText = 'Stopped ' + selected.length.toString() + ' selected downloads';
    this.clearDownloadSelection();
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

  private startItem(item: DownloadInfo): void {
    ehDownloadManager.resumeGallery(item.gid);
    this.statusText = 'Queued: ' + item.title;
    this.persistDownloads();
    this.startGlobalDownloadQueue();
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
          .onClick(() => {
            this.handleDownloadCardTap(item);
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
          .onClick(() => {
            this.handleDownloadCardTap(item);
          })
      }
      if (item.state !== DownloadState.Finish) {
        DownloadCardStatus({
          item: item,
          cardState: this.downloadCardStateFor(item.gid),
          onStatusTap: (downloadItem: DownloadInfo) => {
            this.toggleItemFromProgress(downloadItem);
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
    WaterFlow({ scroller: this.downloadScroller }) {
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
      right: this.downloadContentPadding(),
      bottom: this.downloadCardGap()
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
        title: 'Downloads',
        keyword: this.query,
        searchPlaceholder: 'Search downloads',
        filterActive: this.advancedPanelVisible || this.advancedSearchEnabled ||
          this.searchCategory !== GalleryCategory.None || this.minRating > 0,
        showSearchButton: !this.searchBarVisible,
        showBackButton: this.searchBarVisible,
        showRefreshButton: false,
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
              canOperate: this.items.length > 0,
              canJump: this.downloadJumpTotalPages() > 1,
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
                this.startSelectedOrAll();
              },
              onStop: () => {
                this.stopSelectedOrAll();
              },
              onRestore: () => {
                this.restoreDownloadedItems();
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
            selectedStatuses: this.statusFilterDraft,
            onToggleAll: () => {
              this.toggleAllDownloadStatuses();
            },
            onToggleStatus: (status: string) => {
              this.toggleDownloadStatus(status);
            },
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
      .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })

      if (this.useSplitLayout()) {
        SplitPaneDivider({
          x: this.splitListPaneWidth(),
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
struct DownloadStatusFilterOverlay {
  @Prop selectedStatuses: string[] = [];
  onToggleAll: () => void = () => {};
  onToggleStatus: (status: string) => void = (_status: string) => {};
  onCancel: () => void = () => {};
  onApply: () => void = () => {};

  private isSelected(status: string): boolean {
    return this.selectedStatuses.indexOf(status) >= 0;
  }

  private allSelected(): boolean {
    return this.selectedStatuses.length === DOWNLOAD_STATUS_FILTER_OPTIONS.length;
  }

  @Builder
  private optionRow(label: string, selected: boolean, onTap: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row() {
        Text(uiText(label))
          .fontSize(15)
          .fontColor(selected ? themeSelectedText() : themePrimaryText())
          .layoutWeight(1)
          .textAlign(TextAlign.Start)

        SymbolGlyph(selected ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
          .fontSize(21)
          .fontColor([selected ? themeSelectedText() : themeTertiaryText()])
      }
      .width('100%')
      .padding({ left: 14, right: 14 })
    }
    .width('100%')
    .height(46)
    .backgroundColor(selected ? themeSelectedBackground() : Color.Transparent)
    .borderRadius(8)
    .onClick(onTap)
  }

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
            this.optionRow('All', this.allSelected(), () => {
              this.onToggleAll();
            })
          }

          ForEach(DOWNLOAD_STATUS_FILTER_OPTIONS, (status: string) => {
            ListItem() {
              this.optionRow(status, this.isSelected(status), () => {
                this.onToggleStatus(status);
              })
            }
          }, (status: string) => status)
        }
        .width('100%')
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
  @Prop showTranslationButton: boolean = true;
  @Prop translationEnabled: boolean = false;
  @State activeActionIndex: number = -1;
  onToggle: () => void = () => {};
  onStatus: () => void = () => {};
  onJump: () => void = () => {};
  onStart: () => void = () => {};
  onStop: () => void = () => {};
  onRestore: () => void = () => {};
  onTranslate: () => void = () => {};
  onSelectAll: () => void = () => {};
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
    const baseCount = this.showTranslationButton ? 6 : 5;
    return this.hasSelection ? baseCount + 3 : baseCount;
  }

  private primaryIndex(): number {
    return this.actionCount();
  }

  private expandedActionsHeight(): number {
    const count = this.actionCount();
    if (count <= 0) {
      return 0;
    }
    return count * ACTION_BUBBLE_SIZE + (count - 1) * ACTION_BUBBLE_GAP;
  }

  private hitActionIndex(y: number): number {
    const count = this.actionCount();
    if (count > 0) {
      const actionsHeight = this.expandedActionsHeight();
      if (y >= 0 && y <= actionsHeight) {
        const row = Math.floor(y / (ACTION_BUBBLE_SIZE + ACTION_BUBBLE_GAP));
        const rowTop = row * (ACTION_BUBBLE_SIZE + ACTION_BUBBLE_GAP);
        if (row >= 0 && row < count && y >= rowTop && y <= rowTop + ACTION_BUBBLE_SIZE) {
          return row;
        }
      }
      const primaryTop = actionsHeight + ACTION_BUBBLE_PRIMARY_GAP;
      if (y >= primaryTop && y <= primaryTop + ACTION_BUBBLE_PRIMARY_SIZE) {
        return this.primaryIndex();
      }
      return -1;
    }
    if (y >= 0 && y <= ACTION_BUBBLE_PRIMARY_SIZE) {
      return this.primaryIndex();
    }
    return -1;
  }

  private touchY(event: TouchEvent): number {
    if (event.touches.length > 0) {
      return event.touches[0].y;
    }
    return -1;
  }

  private updateActiveAction(event: TouchEvent): void {
    const index = this.hitActionIndex(this.touchY(event));
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
    const baseIndex = this.hasSelection ? index - 3 : index;
    if (this.hasSelection && index === 0) {
      this.onSelectAll();
    } else if (this.hasSelection && index === 1) {
      this.onExportZip();
    } else if (this.hasSelection && index === 2) {
      this.onDelete();
    } else if (baseIndex === 0) {
      this.onStatus();
    } else if (baseIndex === 1) {
      this.onJump();
    } else if (baseIndex === 2) {
      this.onStart();
    } else if (baseIndex === 3 && this.canOperate) {
      this.onStop();
    } else if (baseIndex === 4) {
      this.onRestore();
    } else if (baseIndex === 5 && this.showTranslationButton) {
      this.onTranslate();
    }
  }

  private handleToolbarTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      this.updateActiveAction(event);
    } else if (event.type === TouchType.Up) {
      const index = this.hitActionIndex(this.touchY(event));
      this.activeActionIndex = -1;
      this.triggerAction(index);
    } else if (event.type === TouchType.Cancel) {
      this.activeActionIndex = -1;
    }
  }

  private baseActionIndex(index: number): number {
    return this.hasSelection ? index + 3 : index;
  }

  build() {
    Column() {
      if (this.expanded) {
        Column({ space: 8 }) {
          if (this.hasSelection) {
            ActionBubble({
              label: uiText('Select all'),
              symbolIcon: $r('sys.symbol.checkmark_circle'),
              isEnabled: true,
              active: this.activeActionIndex === 0,
              directTap: false
            })
            ActionBubble({
              label: uiText('Export'),
              symbolIcon: $r('sys.symbol.archivebox'),
              isEnabled: true,
              active: this.activeActionIndex === 1,
              directTap: false
            })
            ActionBubble({
              label: uiText('Delete'),
              symbolIcon: $r('sys.symbol.trash'),
              isEnabled: true,
              active: this.activeActionIndex === 2,
              directTap: false
            })
          }
          ActionBubble({
            label: uiText('Status'),
            symbolIcon: $r('sys.symbol.funnel'),
            isEnabled: true,
            active: this.activeActionIndex === this.baseActionIndex(0),
            directTap: false
          })
          ActionBubble({
            label: uiText('Jump'),
            symbolIcon: $r('sys.symbol.chevron_forward'),
            isEnabled: this.canJump,
            active: this.activeActionIndex === this.baseActionIndex(1),
            directTap: false
          })
          ActionBubble({
            label: uiText('Start all'),
            symbolIcon: $r('sys.symbol.play_fill'),
            isEnabled: true,
            active: this.activeActionIndex === this.baseActionIndex(2),
            directTap: false
          })
          ActionBubble({
            label: uiText('Stop all'),
            symbolIcon: $r('sys.symbol.pause_fill'),
            isEnabled: this.canOperate,
            active: this.activeActionIndex === this.baseActionIndex(3),
            directTap: false
          })
          ActionBubble({
            label: uiText('Scan'),
            symbolIcon: $r('sys.symbol.play_arrow_triangle_2_circlepath'),
            isEnabled: true,
            active: this.activeActionIndex === this.baseActionIndex(4),
            directTap: false
          })
          if (this.showTranslationButton) {
            ActionBubble({
              label: this.translationEnabled ? uiText('Show original titles') : uiText('Translate titles'),
              symbolIcon: $r('sys.symbol.translate'),
              isEnabled: true,
              checked: this.translationEnabled,
              active: this.activeActionIndex === this.baseActionIndex(5),
              directTap: false
            })
          }
        }
        .alignItems(HorizontalAlign.End)
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
        .height(14)
        .margin({ top: 1 })
        .clip(true)
        .id('download-progress-' + this.item.gid.toString())
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 7 })
    .backgroundColor(themeSurface())
    .borderRadius(6)
    .onClick(() => {
      this.onStatusTap(this.item);
    })
    .animation({ duration: 180, curve: Curve.EaseOut })
  }
}
