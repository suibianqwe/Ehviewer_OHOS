import { common } from '@kit.AbilityKit';
import { GalleryCategory, GalleryDetail, GalleryPage, GalleryPreview, GalleryRoute, GallerySite } from '../model/GalleryModels';
import { ehDownloadFileStore, RestoredDownloadGallery } from '../services/EhDownloadFileStore';
import { DownloadInfo, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
import { EhHttpClient } from '../services/EhHttpClient';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { DEFAULT_ADVANCE_SEARCH, EhUrl, ListMode } from '../services/EhUrl';
import { galleryPageCache } from '../services/GalleryPageCache';
import { mergeGalleryPreviewSets } from '../services/GalleryPreviewLoader';
import { ImageDownloadProgress, readerImageCache } from '../services/ReaderImageCache';
import { createReaderSessionState, readerSessionStore } from '../services/ReaderSessionStore';
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
  nextDownloadCategoryFilter,
  nextDownloadSortMode,
  nextDownloadStatusFilter,
  readerPageReferer,
  saveGalleryReadPosition,
  uiText,
  uiValue
} from '../shared/EhShared';
import {
  themeDividerColor,
  themeOnPrimaryText,
  themePageBackground,
  themePrimaryText,
  themeSecondaryText,
  themeSurface,
  themeTertiaryText
} from '../shared/EhTheme';
import { ArrayDataSource } from '../shared/ListDataSource';
import { FloatingToolbarHost } from './NavigationComponents';
import { ActionBubble, GalleryListRow, GalleryListScene, GalleryThumbCard, ReaderPageState, ReaderScene } from './GalleryScenes';
import { GalleryDetailOverlayScene } from './GalleryDetailScenes';

function normalizeSceneScrollOffset(offset: number): number {
  if (offset <= 1 || Number.isNaN(offset)) {
    return 0;
  }
  return offset;
}

const DOWNLOAD_PAGE_PROGRESS_SCALE: number = 1000;
const DOWNLOAD_PROGRESS_UPDATE_INTERVAL_MS: number = 250;

interface DownloadWorkerState {
  cursor: number;
  finished: number;
  fileSize: number;
  lastBytes: number;
  lastTime: number;
  failedMessage: string;
}

@Component
export struct DownloadScene {
  private client: EhHttpClient = new EhHttpClient();
  private shouldStop: boolean = false;
  private stoppedGids: number[] = [];
  private unsubscribeStore: () => void = () => {};
  onMenu: () => void = () => {};

  @State items: DownloadInfo[] = [];
  @State query: string = '';
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
  @State viewportHeight: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  private detailItem: DownloadInfo | null = null;
  private downloadScroller: Scroller = new Scroller();
  private downloadScrollOffset: number = 0;
  private toolbarRestoring: boolean = false;
  private localReaderPreviewPageSize: number = 0;
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
    this.loadDownloads();
    setTimeout(() => {
      this.syncDownloadContentWidthFromWindow();
    }, 0);
  }

  aboutToDisappear(): void {
    this.unsubscribeStore();
  }

  private handleSystemBack(): boolean {
    if (this.downloadSelectionCount() > 0) {
      this.clearDownloadSelection();
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
    return filterDownloadItems(this.items, this.query, this.statusFilter, 'All', this.sortMode, this.categoryFilter);
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
    this.runDownloadQueue();
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
    this.runDownloadQueue();
  }

  private stopAll(): void {
    this.shouldStop = true;
    this.stoppedGids = [];
    ehDownloadStore.stopAll();
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
      ehDownloadStore.stopGallery(selected[i].gid);
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
    ehDownloadStore.startGallery(item.gid);
    this.statusText = 'Queued: ' + item.title;
    this.persistDownloads();
    this.runDownloadQueue();
  }

  private stopItem(item: DownloadInfo): void {
    this.addStoppedGid(item.gid);
    ehDownloadStore.stopGallery(item.gid);
    this.statusText = 'Stopped: ' + item.title;
    this.persistDownloads();
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

  private openDetail(item: DownloadInfo): void {
    this.detailItem = item;
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
          this.detailRenderVersion++;
          return;
        }
        this.detail = cloneGalleryDetail(result.detail);
        this.detailRequestUrl = result.url;
        this.detailStatus = 'Gallery detail loaded';
        this.detailLoaded = true;
        ehDownloadStore.updateGallery(result.detail);
        this.persistDownloads();
        this.detailRenderVersion++;
      }).catch((error: Error) => {
        this.detailStatus = 'Detail load failed: ' + error.message;
        this.detailRenderVersion++;
      });
  }

  private closeDetail(): void {
    this.showDetail = false;
    this.detailStatus = '';
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
      this.openDownloadedItem(this.detailItem);
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

      const detail = await this.loadCompleteDownloadDetail(detailResult.detail, detailResult.url);
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

        const savedPath = ehDownloadFileStore.savePageImage(context, detail, pageResult.page, pageIndex, cachedPath);
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
        detail = cloneGalleryDetail(result.detail);
        this.localReaderPreviewPageSize = detail.previewSet.length;
        detailRequestUrl = result.url;
        ehDownloadStore.updateGallery(result.detail);
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
    this.showReader = false;
    this.localReaderStatus = 'Page loaded from downloads';
    leaveEmbeddedReaderFullscreen();
    this.restoreBackHandler();
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
    saveGalleryReadPosition(this.localReaderDetail.gid, index);
    this.localReaderRenderVersion++;
    readerSessionStore.updateSession(createReaderSessionState(this.localReaderDetail, this.localReaderPage,
      this.localReaderStatus, '', '', GallerySite.E, this.localReaderIndex));
    if (this.pageHasLocalImage(this.localReaderPage)) {
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
    const context = getAbilityContext();
    if (context === undefined || index < 0 || index >= this.localReaderPages.length) {
      return;
    }
    const downloadedPath = ehDownloadFileStore.findPageImage(context, this.localReaderDetail, index);
    if (downloadedPath.length > 0) {
      const existing = this.localReaderPages[index].page;
      this.setLocalReaderPage(index, this.createLocalReaderPage(existing.pageUrl, existing.imageUrl, downloadedPath),
        'Page loaded from downloads');
      return;
    }

    const preview = await this.resolveLocalReaderPreview(index);
    if (preview.pageUrl.length === 0) {
      throw new Error('Page URL is unavailable');
    }

    if (this.localReaderIndex === index) {
      this.localReaderStatus = 'Loading page ' + (index + 1).toString() + '...';
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

    const cachedPath = readerImageCache.getCachedPath(context, imageUrl);
    const readyPath = cachedPath.length > 0 ? cachedPath :
      await readerImageCache.ensureCached(context, imageUrl, result.page.pageUrl, false);
    const savedPath = ehDownloadFileStore.savePageImage(context, this.localReaderDetail, result.page, index, readyPath);
    this.refreshDownloadProgressAfterRead(context, this.localReaderDetail);
    const page = this.createLocalReaderPage(result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl,
      result.page.imageUrl, savedPath);
    galleryPageCache.put(page.pageUrl, page);
    this.setLocalReaderPage(index, page, 'Page loaded from downloads');
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

    const pageSize = this.localReaderPreviewPageSize > 0 ? this.localReaderPreviewPageSize :
      Math.max(1, this.localReaderDetail.previewSet.length);
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
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
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
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showDetail) {
      GalleryDetailOverlayScene({
        renderVersion: this.detailRenderVersion,
        showComments: false,
        detail: this.detail,
        isDetailLoaded: this.detailLoaded,
        isFavorited: this.detail.isFavorited,
        statusText: this.detailStatus,
        requestUrl: this.detailRequestUrl,
        downloadText: downloadButtonText(this.detail.gid),
        onBack: () => {
          this.closeDetail();
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
        onComments: () => {},
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
        kind: 'search',
        title: 'Downloads',
        keyword: this.query,
        showRefreshButton: false,
        toolbarOffsetY: this.toolbarOffsetY,
        toolbarHeight: 56,
        onMenu: this.onMenu,
        onKeywordChange: (value: string) => {
          this.query = value;
          this.refreshDownloadRows();
        },
        onSearch: () => {}
      }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          if (this.visibleDownloadItems().length === 0) {
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

        Column() {
          DownloadToolColumn({
            expanded: this.downloadActionsExpanded,
            hasSelection: this.downloadSelectionCount() > 0,
            canOperate: this.items.length > 0,
            onToggle: () => {
              this.downloadActionsExpanded = !this.downloadActionsExpanded;
            },
            onStatus: () => {
              this.statusFilter = nextDownloadStatusFilter(this.statusFilter);
              this.refreshDownloadRows();
            },
            onCategory: () => {
              this.categoryFilter = nextDownloadCategoryFilter(this.categoryFilter);
              this.refreshDownloadRows();
            },
            onSort: () => {
              this.sortMode = nextDownloadSortMode(this.sortMode);
              this.refreshDownloadRows();
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
            onClearDone: () => {
              this.clearFinished();
            },
            onDelete: () => {
              this.deleteSelectedDownloads();
            }
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.End)
        .padding({ right: 16, bottom: 24 })
        .hitTestBehavior(HitTestMode.Transparent)
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
  onToggle: () => void = () => {};
  onStatus: () => void = () => {};
  onCategory: () => void = () => {};
  onSort: () => void = () => {};
  onStart: () => void = () => {};
  onStop: () => void = () => {};
  onRestore: () => void = () => {};
  onClearDone: () => void = () => {};
  onDelete: () => void = () => {};

  build() {
    Column() {
      if (this.expanded) {
        Column({ space: 8 }) {
          if (this.hasSelection) {
            ActionBubble({
              label: '',
              symbolIcon: $r('sys.symbol.trash'),
              isEnabled: true,
              onTapAction: this.onDelete
            })
          }
          ActionBubble({
            label: '',
            symbolIcon: $r('sys.symbol.magnifyingglass'),
            isEnabled: true,
            onTapAction: this.onStatus
          })
          ActionBubble({
            label: '',
            symbolIcon: $r('sys.symbol.list_number'),
            isEnabled: true,
            onTapAction: this.onCategory
          })
          ActionBubble({
            label: '',
            symbolIcon: $r('sys.symbol.chevron_forward'),
            isEnabled: true,
            onTapAction: this.onSort
          })
          ActionBubble({
            label: '',
            symbolIcon: $r('sys.symbol.play_fill'),
            isEnabled: true,
            onTapAction: this.onStart
          })
          ActionBubble({
            label: '',
            symbolIcon: $r('sys.symbol.pause_fill'),
            isEnabled: this.canOperate,
            onTapAction: this.onStop
          })
          ActionBubble({
            label: '',
            symbolIcon: $r('sys.symbol.play_arrow_triangle_2_circlepath'),
            isEnabled: true,
            onTapAction: this.onRestore
          })
          ActionBubble({
            label: '',
            symbolIcon: $r('sys.symbol.checkmark_circle'),
            isEnabled: this.canOperate,
            onTapAction: this.onClearDone
          })
        }
        .alignItems(HorizontalAlign.End)
        .margin({ bottom: 10 })
      }

      ActionBubble({
        label: '',
        symbolIcon: this.expanded ? $r('sys.symbol.xmark') : $r('sys.symbol.more'),
        isEnabled: true,
        primary: true,
        onTapAction: this.onToggle
      })
    }
    .alignItems(HorizontalAlign.End)
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
