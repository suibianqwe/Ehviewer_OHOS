import { common } from '@kit.AbilityKit';
import { GalleryCategory, GalleryDetail, GalleryPage, GalleryPreview, GalleryRoute, GallerySite } from '../model/GalleryModels';
import { ehDownloadFileStore, RestoredDownloadGallery } from '../services/EhDownloadFileStore';
import { ehDownloadManager } from '../services/EhDownloadManager';
import { DownloadInfo, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
import { EhHttpClient } from '../services/EhHttpClient';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { DEFAULT_ADVANCE_SEARCH, EhUrl, ListMode } from '../services/EhUrl';
import { galleryMatchesLocalSearch, LocalGallerySearchOptions } from '../services/LocalGallerySearch';
import { galleryPageCache } from '../services/GalleryPageCache';
import { mergeGalleryPreviewSets } from '../services/GalleryPreviewLoader';
import { ImageDownloadProgress, readerImageCache } from '../services/ReaderImageCache';
import { createReaderSessionState, readerSessionStore } from '../services/ReaderSessionStore';
import { ehAppLog } from '../services/EhAppLog';
import {
  applyAppChromeImmersiveMode,
  enterEmbeddedReaderFullscreen,
  leaveEmbeddedReaderFullscreen,
  mainContentWidthFallbackVp,
  rememberMainContentWidthVp
} from '../services/EhWindowImmersive';
import { LANGUAGE_REVISION_KEY, STATUS_BAR_HEIGHT_KEY, nextFloatingToolbarOffset, setActiveBackHandler } from '../shared/EhShared';
import {
  cloneGalleryPage,
  createEmptyDownloadInfo,
  cloneGalleryDetail,
  createDetailFromGallery,
  createEmptyDetail,
  createEmptyPage,
  createReaderLoadingPage,
  currentGallerySite,
  downloadButtonText,
  downloadImageUrlForPage,
  downloadPageIndexes,
  downloadProgressText,
  downloadSizeText,
  downloadStateColor,
  downloadStateLabel,
  downloadThreadLimit,
  filterDownloadItems,
  galleryListMode,
  galleryThumbWidth,
  getAbilityContext,
  nextDownloadStatusFilter,
  readerPageReferer,
  readerPreloadCount,
  readerStartIndexAsync,
  saveGalleryReadPosition,
  uiText,
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
  themeShadowColor,
  themeSurface,
  themeTertiaryText
} from '../shared/EhTheme';
import { ArrayDataSource } from '../shared/ListDataSource';
import { FloatingToolbarHost } from './NavigationComponents';
import { ActionBubble, GalleryListRow, GalleryListScene, GalleryThumbCard, ReaderPageState, ReaderScene } from './GalleryScenes';
import { GalleryDetailOverlayScene } from './GalleryDetailScenes';
import {
  applyTagSuggestionToKeyword,
  buildSearchSuggestions,
  recordSearchHistory,
  SearchAdvancedPanel,
  SearchSuggestionItem,
  SearchSuggestionList,
  SearchSummaryStrip
} from './GallerySearchScenes';

function normalizeSceneScrollOffset(offset: number): number {
  if (offset <= 1 || Number.isNaN(offset)) {
    return 0;
  }
  return offset;
}

const DOWNLOAD_PAGE_PROGRESS_SCALE: number = 1000;
const DOWNLOAD_PROGRESS_UPDATE_INTERVAL_MS: number = 250;
const DOWNLOAD_PAGE_RETRY_LIMIT: number = 3;
const ACTION_BUBBLE_SIZE: number = 44;
const ACTION_BUBBLE_GAP: number = 8;
const ACTION_BUBBLE_PRIMARY_SIZE: number = 54;
const ACTION_BUBBLE_PRIMARY_GAP: number = 10;
const DOWNLOAD_JUMP_PAGE_SIZE: number = 25;

function mergeDownloadDetailTitles(detail: GalleryDetail, item: DownloadInfo): GalleryDetail {
  const next = cloneGalleryDetail(detail);
  if (next.title.length === 0 && item.title.length > 0) {
    next.title = item.title;
  }
  if ((next.titleJpn === undefined || next.titleJpn.length === 0) && item.titleJpn !== undefined &&
    item.titleJpn.length > 0) {
    next.titleJpn = item.titleJpn;
  }
  return next;
}

function wait(ms: number): Promise<void> {
  return new Promise((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

interface DownloadWorkerState {
  cursor: number;
  finished: number;
  fileSize: number;
  lastBytes: number;
  lastTime: number;
  failedMessage: string;
}

interface DownloadedPageResult {
  page: GalleryPage;
  cachedPath: string;
}

@Component
export struct DownloadScene {
  private client: EhHttpClient = new EhHttpClient();
  private shouldStop: boolean = false;
  private stoppedGids: number[] = [];
  private unsubscribeStore: () => void = () => {};
  private unsubscribeDownloadManager: () => void = () => {};
  onMenu: () => void = () => {};

  @State items: DownloadInfo[] = [];
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
  @State statusFilter: string = 'All';
  @State sortMode: string = 'Default';
  @State categoryFilter: string = 'All';
  @State statusText: string = 'Downloads: idle';
  @State isProcessing: boolean = false;
  @State showDetail: boolean = false;
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = '';
  @State detailRequestUrl: string = '';
  @State detailLoaded: boolean = false;
  @State detailRenderVersion: number = 0;
  @State showReader: boolean = false;
  @State showComments: boolean = false;
  @State restoreDetailWithFade: boolean = false;
  @State localReaderDetail: GalleryDetail = createEmptyDetail();
  @State localReaderPage: GalleryPage = createEmptyPage();
  @State localReaderPages: ReaderPageState[] = [];
  @State localReaderIndex: number = 0;
  @State localReaderStatus: string = 'Page loaded from downloads';
  @State localReaderRenderVersion: number = 0;
  @State showTagSearch: boolean = false;
  @State tagSearchKeyword: string = '';
  @State downloadContentWidth: number = 0;
  @State selectedDownloadGids: string = '';
  @State toolbarOffsetY: number = 0;
  @State downloadActionsExpanded: boolean = false;
  @State downloadJumpPanelVisible: boolean = false;
  @State downloadJumpDraft: string = '1';
  @State downloadJumpPageIndex: number = 0;
  @State viewportHeight: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  private detailItem: DownloadInfo | null = null;
  private downloadScroller: Scroller = new Scroller();
  private downloadScrollOffset: number = 0;
  private toolbarRestoring: boolean = false;
  private localReaderPreviewPageSize: number = 0;
  private localReaderLoadingIndexes: number[] = [];
  private downloadRowsDataSource: ArrayDataSource<DownloadInfo[]> = new ArrayDataSource<DownloadInfo[]>([]);
  private downloadRowStructureKeys: string[] = [];
  private downloadCardStates: Map<number, DownloadCardState> = new Map<number, DownloadCardState>();

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    this.syncDownloadContentWidthFromWindow();
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
      this.syncDownloadContentWidthFromWindow();
    }, 0);
  }

  aboutToDisappear(): void {
    this.unsubscribeStore();
    this.unsubscribeDownloadManager();
  }

  private handleSystemBack(): boolean {
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
    if (this.showReader) {
      this.closeLocalReader();
      return true;
    }
    if (this.showComments) {
      this.closeComments();
      return true;
    }
    if (this.showDetail) {
      this.closeDetail();
      return true;
    }
    return false;
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
      return;
    }

    ehDownloadStore.load(context).then(() => {
      this.statusText = this.items.length.toString() + ' download items';
      if (ehDownloadManager.hasWaitingDownloads()) {
        ehDownloadManager.startQueue(context);
      }
    }).catch((error: Error) => {
      this.statusText = 'Download load failed: ' + error.message;
      this.items = ehDownloadStore.getItems();
    });
  }

  private hasWaitingDownloads(): boolean {
    const items = ehDownloadStore.getItems();
    for (let i = 0; i < items.length; i++) {
      if (items[i].state === DownloadState.Wait) {
        return true;
      }
    }
    return false;
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

  private visibleDownloadItems(): DownloadInfo[] {
    const visible = filterDownloadItems(this.items, '', this.statusFilter, 'All', this.sortMode, this.categoryFilter);
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
    return this.selectedTagNamespaces.slice().sort().join('|');
  }

  private toggleTagNamespace(namespace: string): void {
    const next = this.selectedTagNamespaces.slice();
    const index = next.indexOf(namespace);
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(namespace);
    }
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
    const count = this.visibleDownloadItems().length;
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

  private toggleDownloadSelection(item: DownloadInfo): void {
    const key = this.selectedKey(item.gid);
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
      this.selectedDownloadGids += item.gid.toString() + '|';
    }
    this.downloadActionsExpanded = true;
  }

  private handleDownloadCardTap(item: DownloadInfo): void {
    if (this.downloadSelectionCount() > 0) {
      this.toggleDownloadSelection(item);
      return;
    }
    this.openDetail(item);
  }

  private selectedDownloadItems(): DownloadInfo[] {
    const selected: DownloadInfo[] = [];
    const visible = this.visibleDownloadItems();
    for (let i = 0; i < visible.length; i++) {
      if (this.isDownloadSelected(visible[i].gid)) {
        selected.push(visible[i]);
      }
    }
    return selected;
  }

  private downloadCardPreferredWidth(): number {
    if (galleryListMode() === 'Thumb') {
      const value = galleryThumbWidth();
      if (value <= 70) {
        return 116;
      }
      if (value >= 104) {
        return 164;
      }
      return 136;
    }
    return 340;
  }

  private downloadCardGap(): number {
    return 8;
  }

  private downloadContentPadding(): number {
    return 8;
  }

  private downloadCardMinWidth(): number {
    return galleryListMode() === 'Thumb' ? 104 : 300;
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

  private downloadCardWidth(): number {
    const availableWidth = Math.max(0, this.downloadContentWidth - this.downloadContentPadding() * 2);
    if (availableWidth <= 0 || Number.isNaN(availableWidth)) {
      return this.downloadCardPreferredWidth();
    }
    const columns = this.downloadColumnCount();
    const gap = this.downloadCardGap();
    return Math.max(this.downloadCardMinWidth(), Math.floor((availableWidth - gap * (columns - 1)) / columns));
  }

  private updateDownloadContentWidth(width: number): void {
    const normalizedWidth = Math.floor(width);
    if (normalizedWidth <= 0 || Number.isNaN(normalizedWidth) ||
      Math.abs(this.downloadContentWidth - normalizedWidth) < 1) {
      return;
    }
    this.downloadContentWidth = normalizedWidth;
    rememberMainContentWidthVp(normalizedWidth);
    this.refreshDownloadRows();
  }

  private syncDownloadContentWidthFromWindow(): void {
    if (this.downloadContentWidth >= 240) {
      return;
    }
    this.updateDownloadContentWidth(mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value)));
  }

  private buildDownloadRows(): DownloadInfo[][] {
    const visible = this.visibleDownloadItems();
    const columns = this.downloadColumnCount();
    const rows: DownloadInfo[][] = [];
    for (let i = 0; i < visible.length; i += columns) {
      rows.push(visible.slice(i, i + columns));
    }
    return rows;
  }

  private downloadRowsSource(): ArrayDataSource<DownloadInfo[]> {
    return this.downloadRowsDataSource;
  }

  private refreshDownloadRows(): void {
    const rows = this.buildDownloadRows();
    const newKeys: string[] = [];
    for (let i = 0; i < rows.length; i++) {
      newKeys.push(this.downloadRowKey(rows[i]));
    }

    const prevCount = this.downloadRowStructureKeys.length;
    const newCount = rows.length;

    // 纯追加：已有行结构不变，只在末尾新增 → 精确通知，避免全量 reload 闪烁
    if (newCount > prevCount && prevCount > 0) {
      let isAppend = true;
      for (let i = 0; i < prevCount; i++) {
        if (newKeys[i] !== this.downloadRowStructureKeys[i]) {
          isAppend = false;
          break;
        }
      }
      if (isAppend) {
        this.syncDownloadCardStates();
        this.downloadRowStructureKeys = newKeys;
        for (let i = prevCount; i < newCount; i++) {
          this.downloadRowsDataSource.appendAndNotify(rows[i]);
        }
        return;
      }
    }

    // 全量刷新
    let structureChanged = newCount !== prevCount;
    for (let i = 0; i < newCount && !structureChanged; i++) {
      if (newKeys[i] !== this.downloadRowStructureKeys[i]) {
        structureChanged = true;
      }
    }
    this.syncDownloadCardStates();
    this.downloadRowsDataSource.replaceItems(rows);
    if (structureChanged) {
      this.downloadRowStructureKeys = newKeys;
      this.downloadRowsDataSource.notifyReload();
      return;
    }
    this.downloadRowStructureKeys = newKeys;
    for (let i = 0; i < newCount; i++) {
      this.downloadRowsDataSource.notifyChange(i);
    }
  }

  private downloadRowKey(row: DownloadInfo[]): string {
    return row.map((item: DownloadInfo) => item.gid.toString() + '@' + item.state).join('-');
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
    const finishedUnits = Math.max(0, item.finished) * DOWNLOAD_PAGE_PROGRESS_SCALE;
    if (item.downloaded > item.total && item.downloaded >= finishedUnits) {
      return item.downloaded;
    }
    return finishedUnits;
  }

  private downloadSpeedLabel(item: DownloadInfo): string {
    if (item.speed <= 0) {
      return '';
    }
    return downloadSizeText(item.speed) + '/s';
  }

  private startAll(): void {
    this.shouldStop = false;
    this.stoppedGids = [];
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
    this.shouldStop = false;
    for (let i = 0; i < selected.length; i++) {
      this.removeStoppedGid(selected[i].gid);
      ehDownloadStore.startGallery(selected[i].gid);
    }
    this.statusText = 'Queued ' + selected.length.toString() + ' selected downloads';
    this.clearDownloadSelection();
    this.persistDownloads();
    this.startGlobalDownloadQueue();
  }

  private stopAll(): void {
    this.shouldStop = true;
    this.stoppedGids = [];
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
      this.addStoppedGid(selected[i].gid);
      ehDownloadManager.stopGallery(selected[i].gid);
    }
    this.statusText = 'Stopped ' + selected.length.toString() + ' selected downloads';
    this.clearDownloadSelection();
    this.persistDownloads();
  }

  private clearFinished(): void {
    ehDownloadStore.clearFinished();
    this.statusText = 'Cleared finished downloads';
    this.persistDownloads();
  }

  private restoreDownloadedItems(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Restore needs app context';
      return;
    }
    const restored: RestoredDownloadGallery[] = ehDownloadFileStore.restoreDownloadedGalleries(context);
    let added = 0;
    for (let i = 0; i < restored.length; i++) {
      if (!ehDownloadStore.contains(restored[i].gallery.gid)) {
        const item = ehDownloadStore.addGallery(restored[i].gallery, '');
        if (item !== null) {
          ehDownloadStore.setState(item.gid, restored[i].finished >= restored[i].total && restored[i].total > 0 ?
            DownloadState.Finish : DownloadState.None);
          ehDownloadStore.setProgress(item.gid, restored[i].finished, restored[i].total,
            restored[i].finished * DOWNLOAD_PAGE_PROGRESS_SCALE);
          ehDownloadStore.setStorage(item.gid, restored[i].directory, restored[i].fileSize);
          added++;
        }
      }
    }
    this.statusText = 'Restored ' + added.toString() + '/' + restored.length.toString() + ' downloaded galleries';
    this.persistDownloads();
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
    this.shouldStop = false;
    this.removeStoppedGid(item.gid);
    ehDownloadManager.resumeGallery(item.gid);
    this.statusText = 'Queued: ' + item.title;
    this.persistDownloads();
    this.startGlobalDownloadQueue();
  }

  private stopItem(item: DownloadInfo): void {
    this.addStoppedGid(item.gid);
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
    ehDownloadManager.startQueue(context);
  }

  private removeItem(item: DownloadInfo): void {
    const context = getAbilityContext();
    if (context !== undefined) {
      ehDownloadFileStore.removeGalleryDirectory(context, item);
    }
    ehDownloadStore.removeGallery(item.gid);
    this.statusText = 'Removed: ' + item.title;
    this.persistDownloads();
  }

  private deleteSelectedDownloads(): void {
    const selected = this.selectedDownloadItems();
    if (selected.length === 0) {
      this.statusText = 'Long press cards to select downloads';
      return;
    }
    for (let i = 0; i < selected.length; i++) {
      this.removeItem(selected[i]);
    }
    this.clearDownloadSelection();
    this.statusText = 'Removed ' + selected.length.toString() + ' downloads';
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
    ehDownloadFileStore.exportGalleriesZip(context, selected).then((result) => {
      this.clearDownloadSelection();
      this.statusText = 'Exported ' + result.folders.toString() + ' folders to ' + result.path + ' (' +
        downloadSizeText(result.bytes) + ')';
    }).catch((error: Error) => {
      this.statusText = 'Export failed: ' + error.message;
    });
  }

  private openDetail(item: DownloadInfo): void {
    this.detailItem = item;
    this.restoreDetailWithFade = false;
    this.showDetail = true;
    this.detail = createDetailFromGallery(item);
    this.detailStatus = 'Loading gallery detail...';
    this.detailRequestUrl = '';
    this.detailLoaded = false;
    this.detailRenderVersion++;
    this.client.loadGalleryDetail(item.gid, item.token, 0, currentGallerySite(), EhUrl.getReferer(currentGallerySite()))
      .then((result) => {
        if (!result.ok || result.detail === null) {
          this.detailStatus = 'Detail load failed: ' + result.message;
          ehAppLog.warn(getAbilityContext(), 'DownloadDetail', this.detailStatus);
          this.detailRenderVersion++;
          return;
        }
        this.detail = mergeDownloadDetailTitles(result.detail, item);
        this.detailRequestUrl = result.url;
        this.detailStatus = 'Gallery detail loaded';
        this.detailLoaded = true;
        ehDownloadStore.updateGallery(this.detail);
        this.persistDownloads();
        this.detailRenderVersion++;
      }).catch((error: Error) => {
        this.detailStatus = 'Detail load failed: ' + error.message;
        ehAppLog.error(getAbilityContext(), 'DownloadDetail', this.detailStatus);
        this.detailRenderVersion++;
      });
  }

  private closeDetail(): void {
    this.restoreDetailWithFade = false;
    this.showDetail = false;
    this.showComments = false;
    this.detailStatus = '';
  }

  private openComments(): void {
    if (!this.detailLoaded || this.detail.comments.length === 0) {
      return;
    }
    this.showComments = true;
    this.detailRenderVersion++;
  }

  private closeComments(): void {
    this.showComments = false;
    this.detailRenderVersion++;
  }

  private openTagSearch(namespace: string, tag: string): void {
    const keyword = this.buildTagSearchKeyword(namespace, tag);
    if (keyword.length === 0) {
      return;
    }
    this.tagSearchKeyword = keyword;
    this.showTagSearch = true;
  }

  private closeTagSearch(): void {
    this.showTagSearch = false;
    setTimeout(() => {
      setActiveBackHandler(() => this.handleSystemBack());
    }, 0);
  }

  private buildTagSearchKeyword(namespace: string, tag: string): string {
    const trimmedNamespace = namespace.trim();
    const trimmedTag = tag.trim();
    if (trimmedNamespace.length === 0 || trimmedTag.length === 0) {
      return '';
    }
    const tagQuery = trimmedTag.indexOf(' ') >= 0 ? '"' + trimmedTag.replace(/"/g, '\\"') + '"' : trimmedTag;
    return trimmedNamespace + ':' + tagQuery;
  }

  private readDetail(): void {
    if (this.detailItem !== null) {
      readerStartIndexAsync(this.detail).then((index: number) => {
        if (this.detailItem !== null) {
          this.openDownloadedItemAt(this.detailItem, index);
        }
      }).catch(() => {
        if (this.detailItem !== null) {
          this.openDownloadedItem(this.detailItem);
        }
      });
    }
  }

  private async runDownloadQueue(): Promise<void> {
    if (this.isProcessing) {
      return;
    }

    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Download needs app context';
      return;
    }

    this.isProcessing = true;
    try {
      const workerCount = downloadThreadLimit();
      this.statusText = 'Download workers: ' + workerCount.toString();
      while (!this.shouldStop) {
        const queue = ehDownloadStore.getItems();
        let nextItem: DownloadInfo | null = null;
        for (let i = 0; i < queue.length; i++) {
          if (queue[i].state === DownloadState.Wait) {
            nextItem = queue[i];
            break;
          }
        }
        if (nextItem === null) {
          break;
        }

        await this.downloadOne(context, nextItem);
      }
    } finally {
      this.isProcessing = false;
      this.persistDownloads();
    }
  }

  private async downloadOne(context: common.UIAbilityContext, item: DownloadInfo): Promise<void> {
    ehDownloadStore.setState(item.gid, DownloadState.Downloading);
    ehDownloadStore.setTransfer(item.gid, 0, 0);
    this.statusText = 'Downloading: ' + item.title;
    this.persistDownloads();

    try {
      const detailResult = await this.client.loadGalleryDetail(item.gid, item.token, 0, currentGallerySite(),
        EhUrl.getReferer(currentGallerySite()));
      if (!detailResult.ok || detailResult.detail === null) {
        throw new Error(detailResult.message);
      }

      const detail = mergeDownloadDetailTitles(await this.loadCompleteDownloadDetail(detailResult.detail, detailResult.url), item);
      ehDownloadStore.updateGallery(detail);
      const total = Math.max(detail.pages, detail.previewSet.length);
      const downloadDirectory = ehDownloadFileStore.prepareGallery(context, detail);
      ehDownloadStore.setProgress(item.gid, 0, total, 0);
      ehDownloadStore.setStorage(item.gid, downloadDirectory, 0);

      let finished = 0;
      let fileSize = ehDownloadFileStore.directorySize(context, detail);
      for (let i = 0; i < detail.previewSet.length; i++) {
        if (ehDownloadFileStore.findPageImage(context, detail, i).length > 0) {
          finished++;
        }
      }
      if (finished > 0) {
        ehDownloadStore.setProgress(item.gid, finished, total, finished * DOWNLOAD_PAGE_PROGRESS_SCALE);
        ehDownloadStore.setStorage(item.gid, downloadDirectory, fileSize);
        this.statusText = 'Resumed ' + finished.toString() + '/' + total.toString() + ': ' + item.title;
        this.persistDownloads();
      }

      const pageIndexes = downloadPageIndexes(detail.previewSet.length);
      const workerState: DownloadWorkerState = {
        cursor: 0,
        finished: finished,
        fileSize: fileSize,
        lastBytes: fileSize,
        lastTime: Date.now(),
        failedMessage: ''
      };
      const workerCount = Math.max(1, Math.min(downloadThreadLimit(), Math.max(1, pageIndexes.length)));
      const tasks: Promise<void>[] = [];
      for (let i = 0; i < workerCount; i++) {
        tasks.push(this.downloadPageWorker(context, item, detail, detailResult.url, pageIndexes, total,
          downloadDirectory, workerState));
      }
      await Promise.all(tasks);

      if (this.shouldStop || this.isStopped(item.gid)) {
        ehDownloadStore.setState(item.gid, DownloadState.None);
        ehDownloadStore.setTransfer(item.gid, 0, 0);
        this.statusText = 'Stopped: ' + item.title;
        return;
      }

      if (workerState.failedMessage.length > 0) {
        throw new Error(workerState.failedMessage);
      }

      ehDownloadStore.setState(item.gid, DownloadState.Finish);
      ehDownloadStore.setProgress(item.gid, total, total, total * DOWNLOAD_PAGE_PROGRESS_SCALE);
      ehDownloadStore.setStorage(item.gid, downloadDirectory, workerState.fileSize);
      ehDownloadStore.setTransfer(item.gid, 0, 0);
      this.statusText = 'Download finished: ' + item.title;
      this.persistDownloads();
    } catch (error) {
      ehDownloadStore.setState(item.gid, DownloadState.Failed);
      ehDownloadStore.setTransfer(item.gid, 0, 0);
      this.statusText = 'Download failed: ' + String(error);
      ehAppLog.error(getAbilityContext(), 'Download', this.statusText);
      this.persistDownloads();
    }
  }

  private async downloadPageWorker(context: common.UIAbilityContext, item: DownloadInfo, detail: GalleryDetail,
    detailUrl: string, pageIndexes: number[], total: number, downloadDirectory: string,
    state: DownloadWorkerState): Promise<void> {
    while (!this.shouldStop && !this.isStopped(item.gid) && state.failedMessage.length === 0) {
      const orderIndex = state.cursor;
      state.cursor++;
      if (orderIndex >= pageIndexes.length) {
        return;
      }

      const pageIndex = pageIndexes[orderIndex];
      const preview = detail.previewSet[pageIndex];
      if (preview.pageUrl.length === 0 || ehDownloadFileStore.findPageImage(context, detail, pageIndex).length > 0) {
        continue;
      }

      try {
        const downloaded = await this.downloadPageWithRetry(context, item, detail, detailUrl, pageIndex, total, state);

        const savedPath = ehDownloadFileStore.savePageImage(context, detail, downloaded.page, pageIndex,
          downloaded.cachedPath);
        state.fileSize += ehDownloadFileStore.statFileSize(savedPath);
        state.finished++;

        const now = Date.now();
        const speed = Math.round(Math.max(0, state.fileSize - state.lastBytes) * 1000 /
          Math.max(1, now - state.lastTime));
        state.lastBytes = state.fileSize;
        state.lastTime = now;
        const averageBytes = state.finished > 0 ? Math.round(state.fileSize / state.finished) : 0;
        const remaining = speed > 0 ? Math.round(Math.max(0, total - state.finished) * averageBytes / speed) : 0;

        ehDownloadStore.setProgress(item.gid, state.finished, total, state.finished * DOWNLOAD_PAGE_PROGRESS_SCALE);
        ehDownloadStore.setStorage(item.gid, downloadDirectory, state.fileSize);
        ehDownloadStore.setTransfer(item.gid, speed, remaining);
        this.statusText = 'Downloaded ' + state.finished.toString() + '/' + total.toString() + ': ' + item.title;
        this.persistDownloads();
      } catch (error) {
        state.failedMessage = String(error);
      }
    }
  }

  private async downloadPageWithRetry(context: common.UIAbilityContext, item: DownloadInfo, detail: GalleryDetail,
    detailUrl: string, pageIndex: number, total: number, state: DownloadWorkerState): Promise<DownloadedPageResult> {
    let lastError = '';
    for (let attempt = 0; attempt <= DOWNLOAD_PAGE_RETRY_LIMIT; attempt++) {
      if (this.shouldStop || this.isStopped(item.gid)) {
        throw new Error('Download stopped');
      }
      try {
        return await this.downloadPageOnce(context, item, detail, detailUrl, pageIndex, total, state);
      } catch (error) {
        lastError = String(error);
        if (attempt >= DOWNLOAD_PAGE_RETRY_LIMIT) {
          break;
        }
        this.statusText = 'Retry ' + (attempt + 1).toString() + '/' + DOWNLOAD_PAGE_RETRY_LIMIT.toString() +
          ' page ' + (pageIndex + 1).toString() + ': ' + item.title;
        await wait(500 * (attempt + 1));
      }
    }
    throw new Error('Page ' + (pageIndex + 1).toString() + ' failed after ' +
      (DOWNLOAD_PAGE_RETRY_LIMIT + 1).toString() + ' attempts: ' + lastError);
  }

  private async downloadPageOnce(context: common.UIAbilityContext, item: DownloadInfo, detail: GalleryDetail,
    detailUrl: string, pageIndex: number, total: number, state: DownloadWorkerState): Promise<DownloadedPageResult> {
    const preview = detail.previewSet[pageIndex];
    const pageResult = await this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
      readerPageReferer(detailUrl, detail.previewSet, pageIndex, currentGallerySite()));
    if (!pageResult.ok || pageResult.page === null) {
      throw new Error(pageResult.message);
    }

    const imageUrl = downloadImageUrlForPage(pageResult.page);
    if (imageUrl.length === 0) {
      throw new Error('Image URL missing');
    }

    let progressBytes = 0;
    let progressTime = Date.now();
    let progressUiTime = 0;
    const existingCachedPath = readerImageCache.getCachedPath(context, imageUrl);
    const cachedPath = existingCachedPath.length > 0 ? existingCachedPath :
      await readerImageCache.ensureCached(context, imageUrl, pageResult.page.pageUrl, false,
        (progress: ImageDownloadProgress) => {
          const now = Date.now();
          const receivedBytes = Math.max(0, progress.receivedBytes);
          const totalBytes = Math.max(0, progress.totalBytes);
          const isCompleteProgress = totalBytes > 0 && receivedBytes >= totalBytes;
          if (now - progressUiTime < DOWNLOAD_PROGRESS_UPDATE_INTERVAL_MS && !isCompleteProgress) {
            return;
          }
          const deltaBytes = Math.max(0, receivedBytes - progressBytes);
          const deltaMs = Math.max(1, now - progressTime);
          const speed = Math.round(deltaBytes * 1000 / deltaMs);
          progressBytes = receivedBytes;
          progressTime = now;
          progressUiTime = now;

          const pageUnits = totalBytes > 0 ?
            Math.min(DOWNLOAD_PAGE_PROGRESS_SCALE - 1,
              Math.floor(receivedBytes * DOWNLOAD_PAGE_PROGRESS_SCALE / totalBytes)) : 0;
          const currentProgress = state.finished * DOWNLOAD_PAGE_PROGRESS_SCALE + pageUnits;
          const averageBytes = state.finished > 0 ? Math.max(1, Math.round(state.fileSize / state.finished)) :
            Math.max(1, totalBytes);
          const currentRemainingBytes = totalBytes > receivedBytes ? totalBytes - receivedBytes : 0;
          const remainingBytes = currentRemainingBytes + Math.max(0, total - state.finished - 1) * averageBytes;
          ehDownloadStore.setProgress(item.gid, state.finished, total, currentProgress);
          ehDownloadStore.setTransfer(item.gid, speed, speed > 0 ? Math.round(remainingBytes / speed) : 0);
        });
    return {
      page: pageResult.page,
      cachedPath: cachedPath
    };
  }

  private async loadCompleteDownloadDetail(initial: GalleryDetail, referer: string): Promise<GalleryDetail> {
    let detail = cloneGalleryDetail(initial);
    if (detail.previewPages <= 1 || detail.gid <= 0 || detail.token.length === 0) {
      return detail;
    }
    for (let pageIndex = 1; pageIndex < detail.previewPages; pageIndex++) {
      const result = await this.client.loadGalleryDetail(detail.gid, detail.token, pageIndex, currentGallerySite(),
        referer);
      if (!result.ok || result.detail === null) {
        throw new Error('Preview page ' + (pageIndex + 1).toString() + ' load failed: ' + result.message);
      }
      detail = mergeGalleryPreviewSets(detail, result.detail).detail;
      this.statusText = 'Loaded preview page ' + (pageIndex + 1).toString() + '/' + detail.previewPages.toString() +
        ': ' + detail.title;
    }
    return detail;
  }

  private openDownloadedItem(item: DownloadInfo): void {
    this.openDownloadedItemAt(item, ehHistoryStore.getReadPage(item.gid));
  }

  private openDownloadedItemAt(item: DownloadInfo, requestedIndex: number): void {
    this.openDownloadedItemAtAsync(item, requestedIndex).catch((error: Error) => {
      this.statusText = 'Reader launch failed: ' + error.message;
    });
  }

  private async openDownloadedItemAtAsync(item: DownloadInfo, requestedIndex: number): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Reader launch failed: Ability context is not ready';
      return;
    }
    const total = Math.max(item.total, item.pages, item.finished);
    const images = ehDownloadFileStore.listPageImageSlots(context, item, total);
    if (!this.hasAnyImage(images)) {
      this.statusText = item.state === DownloadState.Finish ? 'Downloaded files are missing: ' + item.title :
        'Download is not ready: ' + item.title;
      return;
    }

    const session = await this.createLocalReaderSession(context, item, images, requestedIndex);
    readerSessionStore.setSession(createReaderSessionState(session.detail, session.page, session.status,
      session.detailRequestUrl, '', currentGallerySite(), session.index));

    if (ehSettingsStore.getValue('reader_standalone', 'On') !== 'On') {
      this.localReaderDetail = session.detail;
      this.localReaderPage = session.page;
      this.localReaderPages = session.pages;
      this.localReaderIndex = session.index;
      this.localReaderStatus = session.status;
      this.localReaderRenderVersion++;
      enterEmbeddedReaderFullscreen();
      this.showReader = true;
      if (!this.pageHasLocalImage(this.localReaderPage)) {
        this.loadMissingLocalReaderPage(session.index);
      } else {
        this.preloadLocalReaderPages(session.index);
      }
      return;
    }

    context.startAbility({
      bundleName: 'yt.ehviewer.huawei',
      moduleName: 'entry',
      abilityName: 'ReaderAbility'
    }).catch((error: Error) => {
      this.statusText = 'Reader launch failed: ' + error.message;
    });
  }

  private async createLocalReaderSession(context: common.UIAbilityContext, item: DownloadInfo, images: string[],
    requestedIndex: number): Promise<LocalReaderSession> {
    let detail = createDetailFromGallery(item);
    let detailRequestUrl = '';
    this.localReaderPreviewPageSize = 0;
    try {
      const result = await this.client.loadGalleryDetail(item.gid, item.token, 0, currentGallerySite(),
        EhUrl.getReferer(currentGallerySite()));
      if (result.ok && result.detail !== null) {
        detail = mergeDownloadDetailTitles(result.detail, item);
        this.localReaderPreviewPageSize = detail.previewSet.length;
        detailRequestUrl = result.url;
        ehDownloadStore.updateGallery(detail);
        this.persistDownloads();
      }
    } catch (error) {
    }

    const total = Math.max(detail.pages, item.total, item.pages, images.length);
    const previews: GalleryPreview[] = [];
    const pages: ReaderPageState[] = [];
    const slots = images.length >= total ? images : ehDownloadFileStore.listPageImageSlots(context, item, total);
    for (let i = 0; i < total; i++) {
      const preview = this.previewForIndex(detail, i);
      const pageUrl = preview.pageUrl.length > 0 ? preview.pageUrl : this.localPageUrl(item.gid, i);
      previews.push({
        index: i,
        pageUrl: pageUrl,
        imageUrl: preview.imageUrl,
        width: preview.width,
        height: preview.height,
        xOffset: preview.xOffset,
        yOffset: preview.yOffset
      });
      const path = i < slots.length ? slots[i] : '';
      const page = path.length > 0 ? this.createLocalReaderPage(pageUrl, preview.imageUrl, path) :
        createReaderLoadingPage(pageUrl);
      if (pageUrl.length > 0) {
        galleryPageCache.put(pageUrl, page);
      }
      pages.push({ index: i, page: cloneGalleryPage(page) });
    }
    detail.pages = total;
    detail.previewPages = Math.max(detail.previewPages, 1);
    detail.previewSet = previews;
    const index = requestedIndex >= 0 && requestedIndex < total ? requestedIndex : 0;
    return {
      detail: detail,
      page: cloneGalleryPage(pages[index].page),
      pages: pages,
      index: index,
      status: this.pageHasLocalImage(pages[index].page) ?
        'Page loaded from downloads' : 'Page is not downloaded yet',
      detailRequestUrl: detailRequestUrl
    };
  }

  private pageHasLocalImage(page: GalleryPage): boolean {
    return page.cachedImagePath !== undefined && page.cachedImagePath.length > 0;
  }

  private hasAnyImage(images: string[]): boolean {
    for (let i = 0; i < images.length; i++) {
      if (images[i].length > 0) {
        return true;
      }
    }
    return false;
  }

  private previewForIndex(detail: GalleryDetail, index: number): GalleryPreview {
    for (let i = 0; i < detail.previewSet.length; i++) {
      if (detail.previewSet[i].index === index) {
        return detail.previewSet[i];
      }
    }
    return {
      index: index,
      pageUrl: '',
      imageUrl: '',
      width: 0,
      height: 0,
      xOffset: 0,
      yOffset: 0
    };
  }

  private createLocalReaderPage(pageUrl: string, imageUrl: string, path: string): GalleryPage {
    return {
      pageUrl: pageUrl,
      imageUrl: imageUrl,
      skipHathKey: '',
      originImageUrl: '',
      showKey: '',
      cachedImagePath: path
    };
  }

  private closeLocalReader(): void {
    this.restoreDetailWithFade = this.showDetail;
    this.showReader = false;
    this.localReaderStatus = 'Page loaded from downloads';
    leaveEmbeddedReaderFullscreen();
    this.restoreBackHandler();
    this.clearRestoreDetailFadeLater();
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

  private jumpLocalReader(index: number): void {
    if (index < 0 || index >= this.localReaderPages.length) {
      return;
    }
    this.localReaderIndex = index;
    this.localReaderPage = cloneGalleryPage(this.localReaderPages[index].page);
    this.localReaderStatus = this.pageHasLocalImage(this.localReaderPage) ? 'Page loaded from downloads' :
      'Page is not downloaded yet';
    saveGalleryReadPosition(this.localReaderDetail.gid, index, this.localReaderDetail);
    this.localReaderRenderVersion++;
    readerSessionStore.updateSession(createReaderSessionState(this.localReaderDetail, this.localReaderPage,
      this.localReaderStatus, '', '', GallerySite.E, this.localReaderIndex));
    if (this.pageHasLocalImage(this.localReaderPage)) {
      this.preloadLocalReaderPages(index);
      return;
    }
    this.loadMissingLocalReaderPage(index);
  }

  private loadMissingLocalReaderPage(index: number): void {
    this.loadMissingLocalReaderPageAsync(index).catch((error: Error) => {
      if (this.localReaderIndex === index) {
        this.localReaderStatus = 'Page load failed: ' + error.message;
        this.localReaderRenderVersion++;
      }
    });
  }

  private async loadMissingLocalReaderPageAsync(index: number): Promise<void> {
    await this.loadAndSaveLocalReaderPage(index, false, true);
    this.preloadLocalReaderPages(index);
  }

  private refreshLocalReaderPage(index: number): void {
    this.refreshLocalReaderPageAsync(index).catch((error: Error) => {
      if (this.localReaderIndex === index) {
        this.localReaderStatus = 'Page refresh failed: ' + error.message;
        this.localReaderRenderVersion++;
      }
    });
  }

  private async refreshLocalReaderPageAsync(index: number): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined || index < 0 || index >= this.localReaderPages.length) {
      return;
    }
    const current = this.localReaderPages[index].page;
    const loadingUrl = current.pageUrl.length > 0 ? current.pageUrl : this.previewForIndex(this.localReaderDetail, index).pageUrl;
    this.setLocalReaderPage(index, createReaderLoadingPage(loadingUrl), 'Refreshing page ' +
      (index + 1).toString() + '...');
    ehDownloadFileStore.removePageImage(context, this.localReaderDetail, index);
    if (current.pageUrl.length > 0) {
      galleryPageCache.remove(current.pageUrl);
    }
    await this.loadAndSaveLocalReaderPage(index, true, true);
    this.preloadLocalReaderPages(index);
  }

  private preloadLocalReaderPages(index: number): void {
    this.preloadLocalReaderPagesAsync(index).catch(() => {});
  }

  private async preloadLocalReaderPagesAsync(index: number): Promise<void> {
    const count = Math.max(2, readerPreloadCount());
    if (count <= 0) {
      return;
    }
    for (let offset = 1; offset <= count; offset++) {
      const targets: number[] = [index - offset, index + offset];
      for (let i = 0; i < targets.length; i++) {
        const nextIndex = targets[i];
        if (nextIndex < 0 || nextIndex >= this.localReaderPages.length) {
          continue;
        }
        if (this.pageHasLocalImage(this.localReaderPages[nextIndex].page) ||
          this.isLocalReaderPageLoading(nextIndex)) {
          continue;
        }
        try {
          await this.loadAndSaveLocalReaderPage(nextIndex, false, false);
        } catch (error) {
        }
      }
    }
  }

  private async loadAndSaveLocalReaderPage(index: number, forceRefresh: boolean,
    updateVisibleStatus: boolean): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined || index < 0 || index >= this.localReaderPages.length) {
      return;
    }
    if (!forceRefresh && this.isLocalReaderPageLoading(index)) {
      return;
    }
    this.markLocalReaderPageLoading(index);
    try {
      if (!forceRefresh) {
        const downloadedPath = ehDownloadFileStore.findPageImage(context, this.localReaderDetail, index);
        if (downloadedPath.length > 0) {
          const existing = this.localReaderPages[index].page;
          this.setLocalReaderPage(index, this.createLocalReaderPage(existing.pageUrl, existing.imageUrl, downloadedPath),
            'Page loaded from downloads');
          return;
        }
      }

      const preview = forceRefresh ? await this.refreshLocalReaderPreview(index) :
        await this.resolveLocalReaderPreview(index);
      if (preview.pageUrl.length === 0) {
        throw new Error('Page URL is unavailable');
      }

      if (updateVisibleStatus && this.localReaderIndex === index) {
        this.localReaderStatus = (forceRefresh ? 'Refreshing page ' : 'Loading page ') +
          (index + 1).toString() + '...';
        this.localReaderRenderVersion++;
      }

      const result = await this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
        readerPageReferer('', this.localReaderDetail.previewSet, index, currentGallerySite()));
      if (!result.ok || result.page === null) {
        throw new Error(result.message);
      }

      const imageUrl = downloadImageUrlForPage(result.page);
      if (imageUrl.length === 0) {
        throw new Error('Image URL missing');
      }

      const cachedPath = forceRefresh ? '' : readerImageCache.getCachedPath(context, imageUrl);
      const readyPath = cachedPath.length > 0 ? cachedPath :
        await readerImageCache.ensureCached(context, imageUrl, result.page.pageUrl, false);
      const savedPath = ehDownloadFileStore.savePageImage(context, this.localReaderDetail, result.page, index, readyPath);
      const pageUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
      const page = this.createLocalReaderPage(pageUrl, result.page.imageUrl, savedPath);
      galleryPageCache.put(page.pageUrl, page);
      galleryPageCache.put(preview.pageUrl, page);
      this.updateLocalReaderPreview(index, pageUrl, preview.imageUrl);
      ehDownloadFileStore.rewriteGalleryMetadata(context, this.localReaderDetail);
      this.refreshDownloadProgressAfterRead(context, this.localReaderDetail);
      this.setLocalReaderPage(index, page, 'Page loaded from downloads');
    } finally {
      this.unmarkLocalReaderPageLoading(index);
    }
  }

  private isLocalReaderPageLoading(index: number): boolean {
    for (let i = 0; i < this.localReaderLoadingIndexes.length; i++) {
      if (this.localReaderLoadingIndexes[i] === index) {
        return true;
      }
    }
    return false;
  }

  private markLocalReaderPageLoading(index: number): void {
    if (!this.isLocalReaderPageLoading(index)) {
      this.localReaderLoadingIndexes.push(index);
    }
  }

  private unmarkLocalReaderPageLoading(index: number): void {
    const next: number[] = [];
    for (let i = 0; i < this.localReaderLoadingIndexes.length; i++) {
      if (this.localReaderLoadingIndexes[i] !== index) {
        next.push(this.localReaderLoadingIndexes[i]);
      }
    }
    this.localReaderLoadingIndexes = next;
  }

  private setLocalReaderPage(index: number, page: GalleryPage, status: string): void {
    const next: ReaderPageState[] = [];
    for (let i = 0; i < this.localReaderPages.length; i++) {
      if (this.localReaderPages[i].index === index) {
        next.push({ index: index, page: cloneGalleryPage(page) });
      } else {
        next.push({ index: this.localReaderPages[i].index, page: cloneGalleryPage(this.localReaderPages[i].page) });
      }
    }
    this.localReaderPages = next;
    if (this.localReaderIndex === index) {
      this.localReaderPage = cloneGalleryPage(page);
      this.localReaderStatus = status;
      this.localReaderRenderVersion++;
      readerSessionStore.updateSession(createReaderSessionState(this.localReaderDetail, this.localReaderPage,
        this.localReaderStatus, '', '', GallerySite.E, this.localReaderIndex));
    }
  }

  private refreshDownloadProgressAfterRead(context: common.UIAbilityContext, detail: GalleryDetail): void {
    const total = Math.max(detail.pages, 0);
    const images = ehDownloadFileStore.listPageImageSlots(context, detail, total);
    let finished = 0;
    for (let i = 0; i < images.length; i++) {
      if (images[i].length > 0) {
        finished++;
      }
    }
    ehDownloadStore.setProgress(detail.gid, finished, total, finished * DOWNLOAD_PAGE_PROGRESS_SCALE);
    ehDownloadStore.setStorage(detail.gid, ehDownloadFileStore.galleryDirectory(context, detail),
      ehDownloadFileStore.directorySize(context, detail));
    this.persistDownloads();
  }

  private async resolveLocalReaderPreview(index: number): Promise<GalleryPreview> {
    let preview = this.previewForIndex(this.localReaderDetail, index);
    if (preview.pageUrl.length > 0 || this.localReaderDetail.gid <= 0 || this.localReaderDetail.token.length === 0) {
      return preview;
    }

    const pageSize = this.localReaderPreviewPageSizeForRefresh();
    const previewPageIndex = Math.floor(index / pageSize);
    const result = await this.client.loadGalleryDetail(this.localReaderDetail.gid, this.localReaderDetail.token,
      previewPageIndex, currentGallerySite(), EhUrl.getReferer(currentGallerySite()));
    if (result.ok && result.detail !== null) {
      this.mergeLocalReaderPreviews(result.detail);
      preview = this.previewForIndex(this.localReaderDetail, index);
      if (preview.pageUrl.length > 0) {
        const current = this.localReaderPages[index].page;
        const cachedPath = current.cachedImagePath === undefined ? '' : current.cachedImagePath;
        const page = this.pageHasLocalImage(current) ?
          this.createLocalReaderPage(preview.pageUrl, preview.imageUrl, cachedPath) :
          createReaderLoadingPage(preview.pageUrl);
        this.setLocalReaderPage(index, page, this.pageHasLocalImage(page) ? 'Page loaded from downloads' :
          'Page is not downloaded yet');
      }
    }
    return preview;
  }

  private async refreshLocalReaderPreview(index: number): Promise<GalleryPreview> {
    if (this.localReaderDetail.gid <= 0 || this.localReaderDetail.token.length === 0) {
      return this.previewForIndex(this.localReaderDetail, index);
    }
    const pageSize = this.localReaderPreviewPageSizeForRefresh();
    const previewPageIndex = Math.floor(index / pageSize);
    const result = await this.client.loadGalleryDetail(this.localReaderDetail.gid, this.localReaderDetail.token,
      previewPageIndex, currentGallerySite(), EhUrl.getReferer(currentGallerySite()));
    if (!result.ok || result.detail === null) {
      throw new Error(result.message);
    }
    this.mergeLocalReaderPreviews(result.detail);
    return this.previewForIndex(this.localReaderDetail, index);
  }

  private localReaderPreviewPageSizeForRefresh(): number {
    if (this.localReaderPreviewPageSize > 0) {
      return this.localReaderPreviewPageSize;
    }
    if (this.localReaderDetail.previewPages > 1 && this.localReaderDetail.pages > 0) {
      return Math.max(1, Math.ceil(this.localReaderDetail.pages / this.localReaderDetail.previewPages));
    }
    return Math.max(1, this.localReaderDetail.previewSet.length);
  }

  private updateLocalReaderPreview(index: number, pageUrl: string, imageUrl: string): void {
    const nextDetail = cloneGalleryDetail(this.localReaderDetail);
    let replaced = false;
    const previews: GalleryPreview[] = [];
    for (let i = 0; i < nextDetail.previewSet.length; i++) {
      if (nextDetail.previewSet[i].index === index) {
        previews.push({
          index: index,
          pageUrl: pageUrl,
          imageUrl: imageUrl,
          width: nextDetail.previewSet[i].width,
          height: nextDetail.previewSet[i].height,
          xOffset: nextDetail.previewSet[i].xOffset,
          yOffset: nextDetail.previewSet[i].yOffset
        });
        replaced = true;
      } else {
        previews.push(nextDetail.previewSet[i]);
      }
    }
    if (!replaced) {
      previews.push({ index: index, pageUrl: pageUrl, imageUrl: imageUrl, width: 0, height: 0, xOffset: 0, yOffset: 0 });
    }
    previews.sort((left: GalleryPreview, right: GalleryPreview) => left.index - right.index);
    nextDetail.previewSet = previews;
    this.localReaderDetail = nextDetail;
  }

  private mergeLocalReaderPreviews(loaded: GalleryDetail): void {
    if (this.localReaderPreviewPageSize <= 0 && loaded.previewSet.length > 0) {
      this.localReaderPreviewPageSize = loaded.previewSet.length;
    }
    const merged: GalleryPreview[] = [];
    for (let i = 0; i < this.localReaderDetail.previewSet.length; i++) {
      merged.push(this.localReaderDetail.previewSet[i]);
    }
    for (let i = 0; i < loaded.previewSet.length; i++) {
      let replaced = false;
      for (let j = 0; j < merged.length; j++) {
        if (merged[j].index === loaded.previewSet[i].index) {
          merged[j] = loaded.previewSet[i];
          replaced = true;
          break;
        }
      }
      if (!replaced) {
        merged.push(loaded.previewSet[i]);
      }
    }
    merged.sort((left: GalleryPreview, right: GalleryPreview) => left.index - right.index);
    const nextDetail = cloneGalleryDetail(this.localReaderDetail);
    nextDetail.previewSet = merged;
    nextDetail.previewPages = Math.max(nextDetail.previewPages, loaded.previewPages);
    nextDetail.pages = Math.max(nextDetail.pages, loaded.pages);
    this.localReaderDetail = nextDetail;
  }

  private localPageUrl(gid: number, index: number): string {
    return 'ehviewer://download/' + gid.toString() + '/' + index.toString();
  }

  private isStopped(gid: number): boolean {
    for (let i = 0; i < this.stoppedGids.length; i++) {
      if (this.stoppedGids[i] === gid) {
        return true;
      }
    }
    return false;
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
          Text(uiText('Search history'))
            .fontSize(15)
            .fontColor(themeSecondaryText())
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

  private addStoppedGid(gid: number): void {
    if (!this.isStopped(gid)) {
      this.stoppedGids.push(gid);
    }
  }

  private removeStoppedGid(gid: number): void {
    const next: number[] = [];
    for (let i = 0; i < this.stoppedGids.length; i++) {
      if (this.stoppedGids[i] !== gid) {
        next.push(this.stoppedGids[i]);
      }
    }
    this.stoppedGids = next;
  }

  build() {
    if (this.showTagSearch) {
      GalleryListScene({
        sceneTitle: this.tagSearchKeyword.length > 0 ? this.tagSearchKeyword : 'Search',
        listMode: 'Search',
        sourceRoute: GalleryRoute.Home,
        initialKeyword: this.tagSearchKeyword,
        initialSearchMode: ListMode.Tag,
        initialSearchCategory: GalleryCategory.None,
        initialAdvancedSearchEnabled: false,
        initialAdvanceSearch: DEFAULT_ADVANCE_SEARCH,
        initialSearchSubmitted: true,
        isSearchResultScene: true,
        onBack: () => {
          this.closeTagSearch();
        }
      })
        .transition(this.restoreDetailWithFade ?
          TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }) :
          TransitionEffect.move(TransitionEdge.END).animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showReader) {
      ReaderScene({
        renderVersion: this.localReaderRenderVersion,
        page: this.localReaderPage,
        readerPages: this.localReaderPages,
        statusText: this.localReaderStatus,
        pageIndex: this.localReaderIndex,
        totalPages: this.localReaderPages.length,
        restoreAppChromeOnExit: true,
        onBack: () => {
          this.closeLocalReader();
        },
        onPrev: () => {
          this.jumpLocalReader(this.localReaderIndex - 1);
        },
        onNext: () => {
          this.jumpLocalReader(this.localReaderIndex + 1);
        },
        onJump: (index: number) => {
          this.jumpLocalReader(index);
        },
        onRetry: () => {
          this.jumpLocalReader(this.localReaderIndex);
        },
        onRefreshPage: (index: number) => {
          this.refreshLocalReaderPage(index);
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showDetail) {
      GalleryDetailOverlayScene({
        renderVersion: this.detailRenderVersion,
        showComments: this.showComments,
        detail: this.detail,
        isDetailLoaded: this.detailLoaded,
        isFavorited: this.detail.isFavorited,
        statusText: this.detailStatus,
        requestUrl: this.detailRequestUrl,
        downloadText: downloadButtonText(this.detail.gid),
        onBack: () => {
          this.closeDetail();
        },
        onCloseComments: () => {
          this.closeComments();
        },
        onDownload: () => {
          if (this.detailItem !== null) {
            this.cycleItemState(this.detailItem);
          }
        },
        onRead: () => {
          this.readDetail();
        },
        onSelectPreview: (preview: GalleryPreview) => {
          if (this.detailItem !== null) {
            this.openDownloadedItemAt(this.detailItem, preview.index);
          }
        },
        onComments: () => {
          this.openComments();
        },
        onFavorite: () => {},
        onShare: () => {},
        onRate: (_rating: number) => {},
        onTorrent: () => {},
        onArchive: () => {},
        onLoadMorePreviews: () => {},
        onTagSearch: (namespace: string, tag: string) => {
          this.openTagSearch(namespace, tag);
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else {
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
              this.advancedPanelVisible = !this.advancedPanelVisible;
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
          } else if (this.visibleDownloadItems().length === 0) {
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
            List({ space: 0, scroller: this.downloadScroller }) {
              ListItem() {
                Column()
                  .height(this.downloadCardGap())
                  .width('100%')
                  .backgroundColor(Color.Transparent)
              }
              LazyForEach(this.downloadRowsSource(), (row: DownloadInfo[]) => {
                ListItem() {
                  Row() {
                    ForEach(row, (item: DownloadInfo, colIndex: number) => {
                      Column() {
                      if (galleryListMode() === 'Thumb') {
                        GalleryThumbCard({ gallery: item, selected: this.isDownloadSelected(item.gid) })
                          .width('100%')
                          .zIndex(2)
                          .onClick(() => {
                            this.handleDownloadCardTap(item);
                          })
                            .gesture(LongPressGesture({ repeat: false }).onAction(() => {
                              this.toggleDownloadSelection(item);
                            }))
                      } else {
                        GalleryListRow({ gallery: item, selected: this.isDownloadSelected(item.gid) })
                          .width('100%')
                          .zIndex(2)
                          .onClick(() => {
                            this.handleDownloadCardTap(item);
                          })
                            .gesture(LongPressGesture({ repeat: false }).onAction(() => {
                              this.toggleDownloadSelection(item);
                            }))
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
                      .width(this.downloadCardWidth())
                      .margin({ right: colIndex < row.length - 1 ? this.downloadCardGap() : 0 })
                      .animation({ duration: 220, curve: Curve.EaseOut })
                    }, (item: DownloadInfo) => item.gid.toString())
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.Start)
                  .animation({ duration: 220, curve: Curve.EaseOut })
                }
                .margin({ bottom: this.downloadCardGap() })
              }, (row: DownloadInfo[], rowIndex: number) => {
                return this.downloadColumnCount().toString() + ':' + rowIndex.toString() + ':' + this.downloadRowKey(row);
              })
            }
            .width('100%')
            .height(this.downloadListViewportHeight())
            .cachedCount(4)
            .padding({
              left: this.downloadContentPadding(),
              right: this.downloadContentPadding()
            })
            .translate({ y: this.downloadContentStartOffset() })
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.updateDownloadContentWidth(newArea.width as number);
        })
            .onAppear(() => {
              this.syncDownloadContentWidthFromWindow();
              if (this.downloadScrollOffset > 0) {
                setTimeout(() => {
                  this.downloadScroller.scrollTo({ xOffset: 0, yOffset: this.downloadScrollOffset });
                }, 0);
              }
            })
            .onScrollFrameBegin((offset: number, _state: ScrollState) => {
              return { offsetRemain: this.updateToolbarForScrollFrame(offset) };
            })
            .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
              this.downloadScrollOffset = normalizeSceneScrollOffset(this.downloadScroller.currentOffset().yOffset);
            })
            .onScrollStop(() => {
              this.downloadScrollOffset = normalizeSceneScrollOffset(this.downloadScroller.currentOffset().yOffset);
            })
          }
        }
        .width('100%')
        .height('100%')
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.updateDownloadContentWidth(newArea.width as number);
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
              this.advancedPanelVisible = false;
            })
            .zIndex(15)

          SearchAdvancedPanel({
            searchModeValue: this.searchMode,
            searchCategory: this.searchCategory,
            advancedSearchEnabled: this.advancedSearchEnabled,
            advanceSearch: this.advanceSearch,
            searchFilterEnabled: true,
            minRating: this.minRating,
            pageFrom: -1,
            pageTo: -1,
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
            },
            onMinRatingChange: (rating: number) => {
              this.minRating = rating;
              this.searchSubmitted = false;
              this.refreshDownloadRows();
            },
            onClose: () => {
              this.advancedPanelVisible = false;
            },
            onSearch: () => {
              this.advancedPanelVisible = false;
              this.applyDownloadSearch();
            }
          })
            .margin({ top: this.statusBarVp() + 56 + 8, left: 10, right: 10 })
            .alignSelf(ItemAlign.Start)
            .transition(TransitionEffect.move(TransitionEdge.TOP)
              .animation({ duration: 180, curve: Curve.EaseOut }))
            .zIndex(16)
        }

        Column() {
          DownloadToolColumn({
            expanded: this.downloadActionsExpanded,
            hasSelection: this.downloadSelectionCount() > 0,
            canOperate: this.items.length > 0,
            canJump: this.downloadJumpTotalPages() > 1,
            statusFilter: this.statusFilter,
            onToggle: () => {
              this.downloadActionsExpanded = !this.downloadActionsExpanded;
            },
            onStatus: () => {
              this.statusFilter = nextDownloadStatusFilter(this.statusFilter);
              this.downloadJumpPageIndex = 0;
              this.refreshDownloadRows();
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
            onDelete: () => {
              this.deleteSelectedDownloads();
            },
            onExportZip: () => {
              this.exportSelectedDownloadsZip();
            }
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.End)
        .padding({ right: 16, bottom: 24 })
        .hitTestBehavior(HitTestMode.Transparent)

        if (this.downloadJumpPanelVisible) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(themeScrimColor())
            .onClick(() => {
              this.closeDownloadJumpPanel();
            })
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
      }
      .width('100%')
      .height('100%')
      .backgroundColor(themePageBackground())
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }),
        TransitionEffect.OPACITY.animation({ duration: 1, delay: 300, curve: Curve.Linear })))
    }
  }
}

}

interface LocalReaderSession {
  detail: GalleryDetail;
  page: GalleryPage;
  pages: ReaderPageState[];
  index: number;
  status: string;
  detailRequestUrl: string;
}

@Component
struct DownloadToolColumn {
  @Prop expanded: boolean = false;
  @Prop hasSelection: boolean = false;
  @Prop canOperate: boolean = false;
  @Prop canJump: boolean = false;
  @Prop statusFilter: string = 'All';
  @State activeActionIndex: number = -1;
  @State statusHintVisible: boolean = false;
  private statusHintTimer: number = -1;
  onToggle: () => void = () => {};
  onStatus: () => void = () => {};
  onJump: () => void = () => {};
  onStart: () => void = () => {};
  onStop: () => void = () => {};
  onRestore: () => void = () => {};
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
    return this.hasSelection ? 7 : 5;
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
    const baseIndex = this.hasSelection ? index - 2 : index;
    if (this.hasSelection && index === 0) {
      this.onExportZip();
    } else if (this.hasSelection && index === 1) {
      this.onDelete();
    } else if (baseIndex === 0) {
      this.onStatus();
      this.showStatusHint();
    } else if (baseIndex === 1) {
      this.onJump();
    } else if (baseIndex === 2) {
      this.onStart();
    } else if (baseIndex === 3 && this.canOperate) {
      this.onStop();
    } else if (baseIndex === 4) {
      this.onRestore();
    }
  }

  private showStatusHint(): void {
    this.statusHintVisible = true;
    if (this.statusHintTimer >= 0) {
      clearTimeout(this.statusHintTimer);
    }
    this.statusHintTimer = setTimeout(() => {
      this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
        this.statusHintVisible = false;
      });
      this.statusHintTimer = -1;
    }, 1500);
  }

  private statusHintText(): string {
    return uiText('Current status filter') + ': ' + uiText(this.statusFilter);
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
    return this.hasSelection ? index + 2 : index;
  }

  build() {
    Column() {
      if (this.expanded) {
        Column({ space: 8 }) {
          if (this.hasSelection) {
            ActionBubble({
              label: uiText('Export'),
              symbolIcon: $r('sys.symbol.archivebox'),
              isEnabled: true,
              active: this.activeActionIndex === 0,
              directTap: false
            })
            ActionBubble({
              label: uiText('Delete'),
              symbolIcon: $r('sys.symbol.trash'),
              isEnabled: true,
              active: this.activeActionIndex === 1,
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
        }
        .alignItems(HorizontalAlign.End)
        .margin({ bottom: 10 })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: 12 }))
          .animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.statusHintVisible) {
        Text(this.statusHintText())
          .fontSize(12)
          .fontColor(themePrimaryText())
          .textAlign(TextAlign.End)
          .backgroundColor(themeSurface())
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(14)
          .shadow({ radius: 8, color: themeShadowColor(), offsetX: 0, offsetY: 2 })
          .maxLines(1)
          .margin({ bottom: 8 })
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ x: 8 }))
            .animation({ duration: 140, curve: Curve.EaseOut }))
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
