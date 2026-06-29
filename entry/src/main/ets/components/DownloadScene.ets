import { common } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import {
  GalleryCategory,
  GalleryDetail,
  GalleryRoute
} from '../model/GalleryModels';
import { ehDownloadFileStore, RestoredDownloadGallery } from '../services/EhDownloadFileStore';
import { ehDownloadManager } from '../services/EhDownloadManager';
import { DownloadInfo, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
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
  EMBEDDED_READER_ACTIVE_KEY,
  enterEmbeddedReaderFullscreen,
  leaveEmbeddedReaderFullscreen,
  mainContentWidthFallbackVp,
  rememberMainContentWidthVp
} from '../services/EhWindowImmersive';
import { LANGUAGE_REVISION_KEY, STATUS_BAR_HEIGHT_KEY, nextFloatingToolbarOffset, setActiveBackHandler } from '../shared/EhShared';
import {
  createEmptyDownloadInfo,
  createEmptyDetail,
  currentGallerySite,
  downloadProgressText,
  downloadSizeText,
  downloadStateColor,
  downloadStateLabel,
  filterDownloadItems,
  galleryListMode,
  galleryThumbWidth,
  getAbilityContext,
  nextDownloadStatusFilter,
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
import { ActionBubble, GalleryListRow, GalleryListScene, GalleryThumbCard } from './GalleryScenes';
import { GalleryDetailHostScene } from './GalleryDetailHostScene';
import { ReaderSessionScene } from './ReaderHostScene';
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

async function pickDownloadsOutputPath(context: common.UIAbilityContext, fileName: string): Promise<string> {
  const saveOptions = new picker.DocumentSaveOptions();
  saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
  const documentPicker = new picker.DocumentViewPicker(context);
  const result = await documentPicker.save(saveOptions);
  if (result.length === 0 || result[0].length === 0) {
    return '';
  }
  return new fileUri.FileUri(result[0] + '/' + sanitizeExportFileName(fileName)).path;
}

function sanitizeExportFileName(fileName: string): string {
  return fileName.replace(/[\\/:*?"<>|]/g, '_');
}

function downloadExportTimestamp(now: Date): string {
  return now.getFullYear().toString() + padDownloadExportTwo(now.getMonth() + 1) + padDownloadExportTwo(now.getDate()) +
    '_' + padDownloadExportTwo(now.getHours()) + padDownloadExportTwo(now.getMinutes()) +
    padDownloadExportTwo(now.getSeconds());
}

function padDownloadExportTwo(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

const DOWNLOAD_PAGE_PROGRESS_SCALE: number = 1000;
const ACTION_BUBBLE_SIZE: number = 44;
const ACTION_BUBBLE_GAP: number = 8;
const ACTION_BUBBLE_PRIMARY_SIZE: number = 54;
const ACTION_BUBBLE_PRIMARY_GAP: number = 10;
const DOWNLOAD_JUMP_PAGE_SIZE: number = 25;

@Component
export struct DownloadScene {
  private unsubscribeStore: () => void = () => {};
  private unsubscribeDownloadManager: () => void = () => {};
  @Prop @Watch('onResetVersionChanged') resetVersion: number = 0;
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
  @State showDetail: boolean = false;
  @State detailLink: GalleryDetailLink = createEmptyGalleryDetailLink();
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailRequestUrl: string = '';
  @StorageLink(EMBEDDED_READER_ACTIVE_KEY) showReader: boolean = false;
  @State restoreDetailWithFade: boolean = false;
  @State showTagSearch: boolean = false;
  @State tagSearchTitle: string = 'Search';
  @State tagSearchKeyword: string = '';
  @State tagSearchMode: ListMode = ListMode.Tag;
  @State tagSearchImagePath: string = '';
  @State tagSearchImageUseSimilarity: boolean = false;
  @State tagSearchImageOnlyCovers: boolean = false;
  @State tagSearchImageShowExpunged: boolean = false;
  @State downloadContentWidth: number = 0;
  @State selectedDownloadGids: string = '';
  @State toolbarOffsetY: number = 0;
  @State downloadActionsExpanded: boolean = false;
  @State statusHintText: string = '';
  @State statusHintVisible: boolean = false;
  @State downloadJumpPanelVisible: boolean = false;
  @State downloadJumpDraft: string = '1';
  @State downloadJumpPageIndex: number = 0;
  @State viewportHeight: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  private downloadScroller: Scroller = new Scroller();
  private downloadScrollOffset: number = 0;
  private toolbarRestoring: boolean = false;
  private cellularWarningDialogOpen: boolean = false;
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

  onResetVersionChanged(): void {
    this.resetToTopLevel();
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
      this.closeEmbeddedReader();
      return true;
    }
    if (this.showDetail) {
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
    this.downloadJumpPanelVisible = false;
    this.showTagSearch = false;
    this.showReader = false;
    this.showDetail = false;
    this.restoreDetailWithFade = false;
    this.detailLink = createEmptyGalleryDetailLink();
    this.detail = createEmptyDetail();
    this.detailRequestUrl = '';
    this.tagSearchTitle = 'Search';
    this.tagSearchKeyword = '';
    this.tagSearchMode = ListMode.Tag;
    this.tagSearchImagePath = '';
    this.tagSearchImageUseSimilarity = false;
    this.tagSearchImageOnlyCovers = false;
    this.tagSearchImageShowExpunged = false;
    this.restoreBackHandler();
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
        this.startGlobalDownloadQueue();
      }
    }).catch((error: Error) => {
      this.statusText = 'Download load failed: ' + error.message;
      this.items = ehDownloadStore.getItems();
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

  private showDownloadStatusHint(): void {
    this.statusHintText = uiText('Current status filter') + ': ' + uiText(this.statusFilter);
    this.statusHintVisible = true;
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
        this.statusHintVisible = false;
      });
    }, 1500);
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
    pickDownloadsOutputPath(context, 'EhViewer_downloads_' + downloadExportTimestamp(new Date()) + '.zip').then((path: string) => {
      if (path.length === 0) {
        this.statusText = 'Export cancelled';
        return;
      }
      return ehDownloadFileStore.exportGalleriesZip(context, selected, path);
    }).then((result) => {
      if (result === undefined) {
        return;
      }
      this.clearDownloadSelection();
      this.statusText = 'Exported ' + result.folders.toString() + ' folders to ' + result.path + ' (' +
        downloadSizeText(result.bytes) + ')';
    }).catch((error: Error) => {
      this.statusText = 'Export failed: ' + error.message;
    });
  }

  private openDetail(item: DownloadInfo): void {
    this.restoreDetailWithFade = false;
    this.showDetail = true;
    const detailLink = createGalleryDetailLinkFromGallery(item, currentGallerySite(),
      EhUrl.getReferer(currentGallerySite()));
    this.detailLink = detailLink;
    this.detail = initialDetailForLink(detailLink);
    this.detailRequestUrl = detailLink.url;
  }

  private closeDetail(): void {
    this.restoreDetailWithFade = false;
    this.showDetail = false;
    this.detailLink = createEmptyGalleryDetailLink();
    this.detail = createEmptyDetail();
    this.detailRequestUrl = '';
  }

  private closeTagSearch(): void {
    this.showTagSearch = false;
    this.tagSearchTitle = 'Search';
    this.tagSearchKeyword = '';
    this.tagSearchMode = ListMode.Tag;
    this.tagSearchImagePath = '';
    this.tagSearchImageUseSimilarity = false;
    this.tagSearchImageOnlyCovers = false;
    this.tagSearchImageShowExpunged = false;
    setTimeout(() => {
      setActiveBackHandler(() => this.handleSystemBack());
    }, 0);
  }

  private openRemoteSearch(request: DetailSearchRequest): void {
    this.tagSearchTitle = request.title;
    this.tagSearchKeyword = request.keyword;
    this.tagSearchMode = request.mode;
    this.tagSearchImagePath = request.imagePath;
    this.tagSearchImageUseSimilarity = request.useSimilarityScan;
    this.tagSearchImageOnlyCovers = request.onlySearchCovers;
    this.tagSearchImageShowExpunged = request.showExpunged;
    this.showReader = false;
    this.showTagSearch = true;
  }

  private closeEmbeddedReader(): void {
    this.restoreDetailWithFade = this.showDetail;
    this.showReader = false;
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

  build() {
    if (this.showTagSearch) {
      GalleryListScene({
        sceneTitle: this.tagSearchTitle.length > 0 ? this.tagSearchTitle : 'Search',
        listMode: 'Search',
        sourceRoute: GalleryRoute.Home,
        initialKeyword: this.tagSearchKeyword,
        initialSearchMode: this.tagSearchMode,
        initialSearchCategory: GalleryCategory.None,
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
        .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showDetail) {
      GalleryDetailHostScene({
        detailLink: this.detailLink,
        listRequestUrl: '',
        onBack: () => {
          this.closeDetail();
        },
        onShowEmbeddedReader: () => {
          enterEmbeddedReaderFullscreen();
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
            onToggle: () => {
              this.downloadActionsExpanded = !this.downloadActionsExpanded;
            },
            onStatus: () => {
              this.statusFilter = nextDownloadStatusFilter(this.statusFilter);
              this.downloadJumpPageIndex = 0;
              this.refreshDownloadRows();
              this.showDownloadStatusHint();
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

@Component
struct DownloadToolColumn {
  @Prop expanded: boolean = false;
  @Prop hasSelection: boolean = false;
  @Prop canOperate: boolean = false;
  @Prop canJump: boolean = false;
  @State activeActionIndex: number = -1;
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
