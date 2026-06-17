import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { GalleryCategory, GalleryComment, GalleryDetail, GalleryInfo, GalleryPage, GalleryPreview, GalleryRoute, GallerySite, GalleryTagGroup, TopListBucket, TopListDetail, TopListInfo, TopListItem, TopListKind } from '../model/GalleryModels';
import { ehCookieStore } from '../services/EhCookieStore';
import { DownloadDirectoryScanResult, RestoredDownloadGallery, ehDownloadFileStore } from '../services/EhDownloadFileStore';
import { DownloadInfo, DownloadLabel, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehSettingsStore, SettingEntry, defaultSettingEntries } from '../services/EhSettingsStore';
import { EhHttpClient, GalleryDetailLoadResult, GalleryListLoadResult, GalleryPageLoadResult, NetworkDiagnosticResult, RateGalleryResult, SignInResult, ToggleFavoriteResult, TopListLoadResult } from '../services/EhHttpClient';
import { EhUrl, FavListUrlBuilder, ListMode, ListUrlBuilder } from '../services/EhUrl';
import { galleryPageCache } from '../services/GalleryPageCache';
import { createReaderSessionState, readerSessionStore } from '../services/ReaderSessionStore';
import { CacheClearResult, readerImageCache } from '../services/ReaderImageCache';
import { ehSpiderInfoStore } from '../services/EhSpiderInfoStore';
import { MigrationTask, migrationTasks } from '../services/MigrationStatus';
import { FilterRule, FILTER_MODE_TITLE, FILTER_MODE_UPLOADER, FILTER_MODE_TAG, FILTER_MODE_TAG_NAMESPACE, ehFilterStore } from '../services/EhFilterStore';
import { APP_THEME_COLOR, LANGUAGE_REVISION_KEY, nextFloatingToolbarOffset } from '../shared/EhShared';
import { EhBackupBundle, DrawerItem, SettingsHeaderItem, SettingsRowItem, SessionMode, SettingsPanel, DRAWER_ITEMS, SETTINGS_HEADERS, STATUS_BAR_HEIGHT_KEY, ON_OFF_OPTIONS, shouldUseChineseUi, uiText, uiValue, uiStatusText, uiPageText, zhText, setActiveBackHandler, runActiveBackHandler, createEmptyGallery, createEmptyDownloadInfo, createDetailFromGallery, createEmptyDetail, createEmptyPreview, createEmptyPage, createEmptyTopListDetail, createEmptyTopListInfo, createEmptyTopListBucket, createEmptyTopListItem, cloneStringArray, cloneRequiredStringArray, cloneGalleryInfo, cloneGalleryInfos, padTwo, applyGalleryFilters, cloneGalleryTagGroups, cloneGalleryComments, cloneGalleryPreviews, cloneGalleryDetail, cloneGalleryPage, createReaderLoadingPage, cloneTopListItem, cloneTopListBucket, cloneTopListInfo, cloneTopListDetail, getAbilityContext, saveGalleryToHistory, saveGalleryReadPosition, readerStartIndex, downloadButtonText, toggleGalleryDownload, saveDownloadsQuietly, filterDownloadItems, downloadItemMatches, sortDownloadItems, nextDownloadStatusFilter, nextDownloadLabelFilter, nextDownloadSortMode, nextStringOption, nextDownloadState, nextDownloadLabel, downloadLabelName, downloadStateLabel, downloadStateColor, downloadProgressText, downloadSizeText, downloadImageUrlForPage, downloadThreadLimit, downloadPageIndexes, downloadQueueSummary, parseHistoryMaxSize, routeTitle, routeSubtitle, launchRouteFromSetting, settingsPanelTitle, settingsRowsForPanel, optionSettingsRow, textSettingsRow, staticSettingsRow, settingEntryValue, cloneStringOptions, settingMigrationMessage, nextOption, isValidProxyPortText, formatNetworkDiagnostics, listModeForRoute, routeUsesKeyword, usesGallerySearchToolbar, usesEmbeddedToolbar, defaultKeywordForRoute, gallerySearchTitle, currentGallerySite, effectiveListSite, gallerySiteName, galleryListFailureMessage, withGalleryListMessage, readerPageReferer, readerDisplayImageUrl, cacheReaderImageForPage, cacheThumbnailImage, cloneGalleryPageWithCache, readerLocalImageSource, readerZoomSize, readerFullImageWidth, readerFullImageHeight, readerImageFit, readerShortUrl, readerPreloadCount, readerIsRightToLeft, categoryName, categoryColor, ratingText, galleryDisplayTitle, showGalleryPages, galleryListMode, galleryThumbWidth, galleryThumbHeight, galleryRowHeight, galleryTagPreview, detailTitleFontSize, detailTitleMaxLines, detailHeadingFontSize, readerShowProgress, readerShowClock, readerClockText, padTimeNumber, topListChipColor } from '../shared/EhShared';
import { CommentsScene, GalleryDetailScene, GalleryListRow, GalleryListScene, GalleryListStateView, PlaceholderScene, ReaderScene } from './GalleryScenes';
import { FloatingToolbarHost } from './NavigationComponents';

function normalizeSceneScrollOffset(offset: number): number {
  if (offset <= 1 || Number.isNaN(offset)) {
    return 0;
  }
  return offset;
}

function mergeLoadedSceneDetail(loaded: GalleryDetail, previous: GalleryDetail): GalleryDetail {
  const next = cloneGalleryDetail(loaded);
  if ((next.thumb === undefined || next.thumb.length === 0) && previous.thumb !== undefined && previous.thumb.length > 0) {
    next.thumb = previous.thumb;
  }
  if ((next.thumb === undefined || next.thumb.length === 0) && next.previewSet.length > 0) {
    next.thumb = next.previewSet[0].imageUrl;
  }
  return next;
}

@Component
export struct HistoryScene {
  private client: EhHttpClient = new EhHttpClient();
  onMenu: () => void = () => {};

  @State histories: GalleryInfo[] = [];
  @State statusText: string = 'Loading history...';
  @State showDetail: boolean = false;
  @State showReader: boolean = false;
  @State showComments: boolean = false;
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = 'Tap a history item to load detail';
  @State detailRequestUrl: string = '';
  @State detailDownloadText: string = 'Download';
  @State detailLoaded: boolean = false;
  @State optimisticFavorite: boolean = false;
  @State favoriteBusy: boolean = false;
  @State readerStatus: string = 'Reader is ready';
  @State readerPage: GalleryPage = createEmptyPage();
  @State readerPreviewIndex: number = 0;
  @State renderVersion: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @State toolbarOffsetY: number = 0;
  @State historyRefreshing: boolean = false;
  @State historyRefreshScaleNum: number = 0;
  @State historyRefreshShowLogo: boolean = true;
  @State historyRefreshMsg: string = '';
  private readonly HISTORY_REFRESH_OFFSET: number = 42;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  @State historyContentWidth: number = 0;
  private historyScroller: Scroller = new Scroller();
  private historyScrollOffset: number = 0;
  private historyToolbarScrollOffset: number = 0;
  private detailScrollOffset: number = 0;
  private readerPreviewMap: Map<number, GalleryPreview> = new Map();
  private readerPreviewPageRequests: Map<number, Promise<GalleryPreview | null>> = new Map();
  private readerPreviewPageSize: number = 0;

  aboutToAppear(): void {
    setActiveBackHandler(() => this.handleSystemBack());
    this.loadHistory();
  }

  aboutToDisappear(): void {
    setActiveBackHandler(null);
  }

  private handleSystemBack(): boolean {
    if (this.showReader) { this.closeReader(); return true; }
    if (this.showComments) { this.closeComments(); return true; }
    if (this.showDetail) { this.closeDetail(); return true; }
    return false;
  }

  private loadHistory(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.histories = cloneGalleryInfos(ehHistoryStore.getItems());
      this.statusText = this.histories.length.toString() + ' local history items';
      this.historyRefreshing = false;
      this.renderVersion++;
      return;
    }

    ehHistoryStore.load(context).then(() => {
      this.histories = cloneGalleryInfos(ehHistoryStore.getItems());
      this.statusText = this.histories.length.toString() + ' history items';
      this.historyRefreshing = false;
      this.renderVersion++;
    }).catch((error: Error) => {
      this.statusText = 'History load failed: ' + error.message;
      this.historyRefreshing = false;
      this.renderVersion++;
    });
  }


  private clearHistory(): void {
    ehHistoryStore.clear();
    this.histories = [];
    this.statusText = 'History cleared';
    this.renderVersion++;
    this.persistHistory();
  }

  private removeHistory(gallery: GalleryInfo): void {
    ehHistoryStore.removeGallery(gallery.gid);
    this.histories = cloneGalleryInfos(ehHistoryStore.getItems());
    this.statusText = 'Removed from history: ' + gallery.title;
    this.renderVersion++;
    this.persistHistory();
  }

  private persistHistory(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehHistoryStore.save(context).catch((error: Error) => {
      this.statusText = 'History save failed: ' + error.message;
    });
  }

  private loadDetail(gallery: GalleryInfo): void {
    this.showDetail = true;
    this.detail = createDetailFromGallery(gallery);
    this.resetReaderPreviewCache();
    this.detailStatus = 'Loading detail for gid ' + gallery.gid.toString() + '...';
    this.detailRequestUrl = '';
    this.detailDownloadText = downloadButtonText(gallery.gid);
    this.detailLoaded = false;
    this.optimisticFavorite = gallery.favoriteSlot >= 0;
    this.favoriteBusy = false;
    this.renderVersion++;

    this.client.loadGalleryDetail(gallery.gid, gallery.token, 0, currentGallerySite(), '').then((result: GalleryDetailLoadResult) => {
      this.detailRequestUrl = result.url;
      if (!result.ok || result.detail === null) {
        this.detailStatus = 'Detail load failed: ' + result.message;
        this.renderVersion++;
        return;
      }

      this.detailStatus = 'Detail loaded';
      this.detail = mergeLoadedSceneDetail(result.detail, this.detail);
      this.seedReaderPreviewCache(this.detail.previewSet);
      this.detailDownloadText = downloadButtonText(result.detail.gid);
      this.detailLoaded = true;
      this.optimisticFavorite = this.detail.isFavorited;
      this.favoriteBusy = false;
      this.renderVersion++;
      saveGalleryToHistory(result.detail);
      this.loadHistory();
      this.prewarmReader();
    }).catch((error: Error) => {
      this.detailStatus = 'Detail load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private closeDetail(): void {
    this.showDetail = false;
    this.showReader = false;
    this.showComments = false;
    this.detail = createEmptyDetail();
    this.resetReaderPreviewCache();
    this.detailStatus = 'Tap a history item to load detail';
    this.detailRequestUrl = '';
    this.detailDownloadText = 'Download';
    this.detailLoaded = false;
    this.optimisticFavorite = false;
    this.favoriteBusy = false;
    this.readerStatus = 'Reader is ready';
    this.readerPage = createEmptyPage();
    this.readerPreviewIndex = 0;
    this.detailScrollOffset = 0;
    this.renderVersion++;
    this.loadHistory();
  }

  private openComments(): void {
    this.showComments = true;
    this.renderVersion++;
  }

  private closeComments(): void {
    this.showComments = false;
    this.renderVersion++;
  }

  private closeReader(): void {
    this.showReader = false;
    this.readerStatus = 'Reader is ready';
    this.readerPage = createEmptyPage();
    this.readerPreviewIndex = 0;
    this.renderVersion++;
  }

  private loadReaderPage(preview: GalleryPreview): void {
    if (preview.pageUrl.length === 0) {
      this.readerStatus = 'Preview has no page URL';
      return;
    }

    this.readerPreviewMap.set(preview.index, preview);
    this.readerPreviewIndex = preview.index;
    saveGalleryReadPosition(this.detail.gid, preview.index);
    this.readerStatus = 'Loading page ' + (preview.index + 1).toString() + '...';
    this.readerPage = createReaderLoadingPage(preview.pageUrl);
    this.renderVersion++;
    this.openReaderAbility(currentGallerySite());

    const cached = galleryPageCache.get(preview.pageUrl);
    if (cached !== null) {
      this.readerStatus = 'Page loaded from cache';
      this.readerPage = cloneGalleryPage(cached);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, cached);
      this.preloadReaderPages(preview.index);
      this.persistReaderSession(currentGallerySite());
      return;
    }

    this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
      readerPageReferer(this.detailRequestUrl, this.detail.previewSet, preview.index, currentGallerySite())).then((result: GalleryPageLoadResult) => {
      if (!result.ok || result.page === null) {
        this.readerStatus = 'Page load failed: ' + result.message;
        return;
      }
      const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
      galleryPageCache.put(cacheUrl, result.page);
      galleryPageCache.put(preview.pageUrl, result.page);
      this.readerStatus = 'Page loaded';
      this.readerPage = cloneGalleryPage(result.page);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, result.page);
      this.preloadReaderPages(preview.index);
      this.persistReaderSession(currentGallerySite());
    }).catch((error: Error) => {
      this.readerStatus = 'Page load failed: ' + error.message;
      this.renderVersion++;
      this.persistReaderSession(currentGallerySite());
    });
  }

  private updateToolbarForScroll(): void {
    const offset = normalizeSceneScrollOffset(this.historyScroller.currentOffset().yOffset);
    const delta = offset - this.historyToolbarScrollOffset;
    this.toolbarOffsetY = nextFloatingToolbarOffset(this.toolbarOffsetY, delta, offset, this.floatingToolbarHeight());
    this.historyToolbarScrollOffset = offset;
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  private floatingToolbarHeight(): number {
    return this.statusBarVp() + 56;
  }

  private historyContentTopPadding(): number {
    return this.floatingToolbarHeight() + 8;
  }

  private historyCardPreferredWidth(): number {
    return 340;
  }

  private historyCardGap(): number {
    return 8;
  }

  private historyContentHorizontalPadding(): number {
    return 8;
  }

  private historyColumnCount(): number {
    return this.historyColumnCountForWidth(this.historyContentWidth);
  }

  private historyColumnCountForWidth(width: number): number {
    const availableWidth = Math.max(0, width - this.historyContentHorizontalPadding() * 2);
    if (availableWidth <= 0 || Number.isNaN(availableWidth)) {
      return 1;
    }
    return Math.max(1, Math.floor((availableWidth + this.historyCardGap()) /
      (this.historyCardPreferredWidth() + this.historyCardGap())));
  }

  private historyCardWidth(): number {
    const availableWidth = Math.max(0, this.historyContentWidth - this.historyContentHorizontalPadding() * 2);
    if (availableWidth <= 0 || Number.isNaN(availableWidth)) {
      return this.historyCardPreferredWidth();
    }
    const columns = this.historyColumnCount();
    return Math.max(300, Math.floor((availableWidth - this.historyCardGap() * (columns - 1)) / columns));
  }

  private updateHistoryContentWidth(width: number): void {
    if (width <= 0 || Number.isNaN(width) || this.historyContentWidth === width) {
      return;
    }
    const oldColumns = this.historyColumnCount();
    const nextColumns = this.historyColumnCountForWidth(width);
    if (this.historyContentWidth <= 0 || oldColumns === nextColumns) {
      this.historyContentWidth = width;
      return;
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.historyContentWidth = width;
    });
  }

  private buildHistoryRows(): GalleryInfo[][] {
    const columns = this.historyColumnCount();
    const rows: GalleryInfo[][] = [];
    for (let i = 0; i < this.histories.length; i += columns) {
      rows.push(this.histories.slice(i, i + columns));
    }
    return rows;
  }

  private historyRowKey(row: GalleryInfo[]): string {
    return row.map((gallery: GalleryInfo) => gallery.gid.toString()).join('-');
  }

  private cacheReaderImage(index: number, page: GalleryPage): void {
    cacheReaderImageForPage(page, (cachedPage: GalleryPage) => {
      galleryPageCache.put(cachedPage.pageUrl.length > 0 ? cachedPage.pageUrl : page.pageUrl, cachedPage);
      if (this.showReader && this.readerPreviewIndex === index) {
        this.readerPage = cloneGalleryPage(cachedPage);
        this.readerStatus = 'Page loaded from local cache';
        this.renderVersion++;
      }
    });
  }

  private async preloadReaderPages(index: number): Promise<void> {
    const count = readerPreloadCount();
    if (count <= 0) {
      return;
    }

    for (let offset = 1; offset <= count; offset++) {
      const nextIndex = index + offset;
      if (nextIndex < 0 || nextIndex >= this.readerTotalPages()) {
        return;
      }

      const preview = await this.ensureReaderPreview(nextIndex, true);
      if (preview === null) {
        continue;
      }
      if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
        continue;
      }

      try {
        const result = await this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
          readerPageReferer(this.detailRequestUrl, this.detail.previewSet, nextIndex, currentGallerySite()));
        if (result.ok && result.page !== null) {
          const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
          galleryPageCache.put(cacheUrl, result.page);
          galleryPageCache.put(preview.pageUrl, result.page);
          this.cacheReaderImage(nextIndex, result.page);
        }
      } catch (error) {
      }
    }
  }

  private async prewarmReader(): Promise<void> {
    if (this.readerTotalPages() <= 0) {
      return;
    }

    const preview = await this.ensureReaderPreview(0, true);
    if (preview === null) {
      return;
    }
    if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
      return;
    }

    try {
      const result = await this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
        readerPageReferer(this.detailRequestUrl, this.detail.previewSet, 0, currentGallerySite()));
      if (result.ok && result.page !== null) {
        const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
        galleryPageCache.put(cacheUrl, result.page);
        galleryPageCache.put(preview.pageUrl, result.page);
        this.cacheReaderImage(0, result.page);
        this.preloadReaderPages(0);
      }
    } catch (error) {
    }
  }

  private loadReaderPageByIndex(index: number): void {
    if (index < 0 || index >= this.readerTotalPages()) {
      return;
    }
    const preview = this.readerPreviewForIndex(index);
    if (preview !== null) {
      this.loadReaderPage(preview);
      return;
    }

    this.readerPreviewIndex = index;
    saveGalleryReadPosition(this.detail.gid, index);
    this.readerStatus = 'Resolving page ' + (index + 1).toString() + '...';
    this.readerPage = createReaderLoadingPage('');
    this.renderVersion++;
    this.openReaderAbility(currentGallerySite());
    this.ensureReaderPreview(index, false).then((resolved: GalleryPreview | null) => {
      if (resolved !== null && this.readerPreviewIndex === index) {
        this.loadReaderPage(resolved);
      }
    });
  }

  private readDetail(): void {
    if (this.readerTotalPages() <= 0) {
      this.detailStatus = 'Read is waiting for preview pages';
      return;
    }
    this.loadReaderPageByIndex(readerStartIndex(this.detail));
  }

  private persistReaderSession(site: GallerySite): void {
    readerSessionStore.updateSession(createReaderSessionState(this.detail, this.readerPage, this.readerStatus,
      this.detailRequestUrl, '', site, this.readerPreviewIndex));
  }

  private publishReaderSession(site: GallerySite): void {
    readerSessionStore.setSession(createReaderSessionState(this.detail, this.readerPage, this.readerStatus,
      this.detailRequestUrl, '', site, this.readerPreviewIndex));
  }

  private openReaderAbility(site: GallerySite): void {
    this.publishReaderSession(site);
    if (ehSettingsStore.getValue('reader_standalone', 'On') !== 'On') {
      this.showReader = true;
      return;
    }
    this.showReader = false;
    const context = getAbilityContext();
    if (context === undefined) {
      this.showReader = true;
      return;
    }
    context.startAbility({
      bundleName: 'yt.ehviewer.huawei',
      moduleName: 'entry',
      abilityName: 'ReaderAbility'
    }).catch((error: Error) => {
      this.readerStatus = 'Reader launch failed: ' + error.message;
      this.renderVersion++;
      this.persistReaderSession(site);
    });
  }

  private resetReaderPreviewCache(): void {
    this.readerPreviewMap.clear();
    this.readerPreviewPageRequests.clear();
    this.readerPreviewPageSize = 0;
  }

  private seedReaderPreviewCache(previews: GalleryPreview[]): void {
    if (previews.length > 0 && (this.readerPreviewPageSize <= 0 || previews.length > this.readerPreviewPageSize)) {
      this.readerPreviewPageSize = previews.length;
    }
    for (let i = 0; i < previews.length; i++) {
      this.readerPreviewMap.set(previews[i].index, previews[i]);
    }
  }

  private readerTotalPages(): number {
    return this.detail.pages > 0 ? this.detail.pages : Math.max(this.detail.previewSet.length, this.readerPreviewMap.size);
  }

  private readerPreviewForIndex(index: number): GalleryPreview | null {
    const cached = this.readerPreviewMap.get(index);
    if (cached !== undefined) {
      return cached;
    }
    for (let i = 0; i < this.detail.previewSet.length; i++) {
      if (this.detail.previewSet[i].index === index) {
        this.readerPreviewMap.set(index, this.detail.previewSet[i]);
        return this.detail.previewSet[i];
      }
    }
    return null;
  }

  private readerPreviewPageIndex(index: number): number {
    const pageSize = this.readerPreviewPageSize > 0 ? this.readerPreviewPageSize : Math.max(1, this.detail.previewSet.length);
    return Math.floor(index / pageSize);
  }

  private ensureReaderPreview(index: number, silent: boolean): Promise<GalleryPreview | null> {
    const cached = this.readerPreviewForIndex(index);
    if (cached !== null) {
      return Promise.resolve(cached);
    }
    if (this.detail.gid <= 0 || this.detail.token.length === 0 || index < 0 || index >= this.readerTotalPages()) {
      return Promise.resolve(null);
    }
    const previewPageIndex = this.readerPreviewPageIndex(index);
    const pending = this.readerPreviewPageRequests.get(previewPageIndex);
    if (pending !== undefined) {
      return pending;
    }
    const request = this.client.loadGalleryDetail(this.detail.gid, this.detail.token, previewPageIndex,
      currentGallerySite(), this.detailRequestUrl).then((result: GalleryDetailLoadResult) => {
      this.readerPreviewPageRequests.delete(previewPageIndex);
      if (!result.ok || result.detail === null) {
        if (!silent) {
          this.readerStatus = 'Preview page load failed: ' + result.message;
          this.renderVersion++;
        }
        return null;
      }
      this.mergeReaderPreviewSet(result.detail);
      return this.readerPreviewForIndex(index);
    });
    this.readerPreviewPageRequests.set(previewPageIndex, request);
    return request;
  }

  private mergeReaderPreviewSet(loaded: GalleryDetail): void {
    this.seedReaderPreviewCache(loaded.previewSet);
    const byIndex: Map<number, GalleryPreview> = new Map();
    for (let i = 0; i < this.detail.previewSet.length; i++) {
      byIndex.set(this.detail.previewSet[i].index, this.detail.previewSet[i]);
    }
    for (let i = 0; i < loaded.previewSet.length; i++) {
      byIndex.set(loaded.previewSet[i].index, loaded.previewSet[i]);
    }
    const merged: GalleryPreview[] = Array.from(byIndex.values());
    merged.sort((left: GalleryPreview, right: GalleryPreview) => left.index - right.index);
    const nextDetail = cloneGalleryDetail(this.detail);
    nextDetail.previewSet = cloneGalleryPreviews(merged);
    nextDetail.previewPages = Math.max(nextDetail.previewPages, loaded.previewPages);
    nextDetail.pages = Math.max(nextDetail.pages, loaded.pages);
    this.detail = nextDetail;
    this.seedReaderPreviewCache(this.detail.previewSet);
    this.renderVersion++;
  }

  private toggleDownloadDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'Download needs a loaded gallery';
      return;
    }
    const queued = toggleGalleryDownload(this.detail);
    this.detailDownloadText = queued ? 'Queued' : 'Download';
    this.detailStatus = queued ? 'Added to download queue' : 'Removed from download queue';
    this.renderVersion++;
  }

  private toggleFavoriteDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      return;
    }
    if (this.favoriteBusy) {
      return;
    }
    const wasFavorited = this.detail.isFavorited;
    this.detailStatus = wasFavorited ? 'Removing from favorites...' : 'Adding to favorites...';
    this.favoriteBusy = true;
    this.optimisticFavorite = !wasFavorited;
    this.applyDetailFavoriteState(this.optimisticFavorite);
    this.renderVersion++;
    this.client.toggleFavorite(this.detail.gid, this.detail.token, wasFavorited,
      GallerySite.E).then((result: ToggleFavoriteResult) => {
      this.detailStatus = result.message;
      if (result.ok) {
        this.optimisticFavorite = result.nowFavorited;
        this.applyDetailFavoriteState(result.nowFavorited);
      } else {
        this.optimisticFavorite = wasFavorited;
        this.applyDetailFavoriteState(wasFavorited);
      }
      this.favoriteBusy = false;
      this.renderVersion++;
    }).catch((error: Error) => {
      this.detailStatus = 'Favorite failed: ' + error.message;
      this.optimisticFavorite = wasFavorited;
      this.applyDetailFavoriteState(wasFavorited);
      this.favoriteBusy = false;
      this.renderVersion++;
    });
  }

  private applyDetailFavoriteState(isFavorited: boolean): void {
    const nextDetail = cloneGalleryDetail(this.detail);
    nextDetail.isFavorited = isFavorited;
    nextDetail.favoriteSlot = isFavorited ? Math.max(0, nextDetail.favoriteSlot) : -2;
    this.detail = nextDetail;
  }

  private shareDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      this.renderVersion++;
      return;
    }
    const url = EhUrl.getGalleryDetailUrl(this.detail.gid, this.detail.token, 0, false, GallerySite.E);
    this.copyDetailLink(url, 'Gallery URL');
  }

  private rateDetail(rating: number): void {
    if (this.detail.gid <= 0 || this.detail.apiUid < 0 || this.detail.apiKey.length === 0) {
      this.detailStatus = 'Rating needs a loaded gallery session';
      this.renderVersion++;
      return;
    }
    this.detailStatus = 'Submitting rating...';
    this.renderVersion++;
    this.client.rateGallery(this.detail.gid, this.detail.token, this.detail.apiUid, this.detail.apiKey, rating,
      GallerySite.E).then((result: RateGalleryResult) => {
      this.detailStatus = result.message;
      if (result.ok) {
        const nextDetail = cloneGalleryDetail(this.detail);
        nextDetail.rating = result.rating;
        nextDetail.ratingCount = result.ratingCount > 0 ? result.ratingCount : nextDetail.ratingCount;
        nextDetail.rated = true;
        this.detail = nextDetail;
      }
      this.renderVersion++;
    }).catch((error: Error) => {
      this.detailStatus = 'Rating failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private copyDetailLink(url: string, label: string): void {
    if (url.length === 0) {
      this.detailStatus = label + ' link is unavailable';
      this.renderVersion++;
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data);
      this.detailStatus = label + ' link copied to clipboard';
    } catch (error) {
      this.detailStatus = label + ' copy failed: ' + String(error);
    }
    this.renderVersion++;
  }


  @Builder
  private historyRefreshComponent() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 2 }) {
        Image($r('app.media.app_icon'))
          .width(26)
          .height(26)
          .scale({ x: this.historyRefreshScaleNum, y: this.historyRefreshScaleNum })
          .visibility(this.historyRefreshShowLogo ? Visibility.Visible : Visibility.None)
        LoadingProgress()
          .width(26)
          .height(26)
          .color(APP_THEME_COLOR)
          .visibility(this.historyRefreshShowLogo ? Visibility.None : Visibility.Visible)
        if (this.historyRefreshMsg.length > 0) {
          Text(this.historyRefreshMsg)
            .fontSize(10)
            .fontColor($r('app.color.secondary_text'))
        }
      }
      .alignItems(HorizontalAlign.Center)
      .margin({ bottom: 4 })
    }
    .width('100%')
    .height(52)
    .clip(true)
  }

  build() {
    if (this.showReader) {
      ReaderScene({
        renderVersion: this.renderVersion,
        page: this.readerPage,
        statusText: this.readerStatus,
        pageIndex: this.readerPreviewIndex,
        totalPages: this.readerTotalPages(),
        onBack: () => {
          this.closeReader();
        },
        onPrev: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex - 1);
        },
        onNext: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex + 1);
        },
        onJump: (index: number) => {
          this.loadReaderPageByIndex(index);
        },
        onRetry: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex);
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showComments) {
      CommentsScene({
        renderVersion: this.renderVersion,
        comments: this.detail.comments,
        galleryTitle: galleryDisplayTitle(this.detail),
        onBack: () => {
          this.closeComments();
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showDetail) {
      GalleryDetailScene({
        renderVersion: this.renderVersion,
        detail: this.detail,
        isDetailLoaded: this.detailLoaded,
        isFavorited: this.optimisticFavorite,
        statusText: this.detailStatus,
        requestUrl: this.detailRequestUrl,
        downloadText: this.detailDownloadText,
        onBack: () => {
          this.closeDetail();
        },
        onDownload: () => {
          this.toggleDownloadDetail();
        },
        onRead: () => {
          this.readDetail();
        },
        onSelectPreview: (preview: GalleryPreview) => {
          this.loadReaderPage(preview);
        },
        onComments: () => {
          this.openComments();
        },
        onFavorite: () => {
          this.toggleFavoriteDetail();
        },
        onShare: () => {
          this.shareDetail();
        },
        onRate: (rating: number) => {
          this.rateDetail(rating);
        },
        onTorrent: () => {
          this.copyDetailLink(this.detail.torrentUrl, 'Torrent');
        },
        onArchive: () => {
          this.copyDetailLink(this.detail.archiveUrl, 'Archive');
        },
        initialDetailScrollOffset: this.detailScrollOffset,
        onDetailScrollUpdate: (offset: number) => {
          this.detailScrollOffset = offset;
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else {
      FloatingToolbarHost({
        kind: 'title',
        title: 'History',
        requestUrl: '',
        showClear: true,
        canClear: this.histories.length > 0,
        toolbarOffsetY: this.toolbarOffsetY,
        toolbarHeight: 56,
        onMenu: this.onMenu,
        onRefresh: () => {
          this.historyRefreshShowLogo = false;
          this.historyRefreshMsg = uiText('Refreshing...');
          this.historyRefreshing = true;
          this.loadHistory();
        },
        onClear: () => {
          this.clearHistory();
        }
      }) {
        Column() {
          Refresh({ refreshing: $$this.historyRefreshing, builder: this.historyRefreshComponent() }) {
            Scroll(this.historyScroller) {
              Column({ space: 8 }) {
                if (this.histories.length === 0) {
                  PlaceholderScene({
                    title: 'History',
                    detail: 'Viewed gallery details will appear here. Open a gallery from Homepage, Favorites or Top Lists to add it.'
                  })
                    .layoutWeight(1)
                } else {
                  ForEach(this.buildHistoryRows(), (row: GalleryInfo[], rowIndex: number) => {
                    Row() {
                      ForEach(row, (gallery: GalleryInfo, colIndex: number) => {
                        Column() {
                          GalleryListRow({ gallery: gallery })
                            .onClick(() => {
                              this.loadDetail(gallery);
                            })
                          Row() {
                            Text(uiText('Remove'))
                              .fontSize(12)
                              .fontColor('#C33A2C')
                              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                              .onClick(() => {
                                this.removeHistory(gallery);
                              })
                            Blank()
                          }
                          .width('100%')
                          .padding({ right: 8, bottom: 6 })
                          .backgroundColor(Color.White)
                        }
                        .width(this.historyCardWidth())
                        .borderRadius(6)
                        .margin({ right: colIndex < row.length - 1 ? this.historyCardGap() : 0 })
                        .animation({ duration: 220, curve: Curve.EaseOut })
                      }, (gallery: GalleryInfo) => gallery.gid.toString())
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.Start)
                    .animation({ duration: 220, curve: Curve.EaseOut })
                  }, (row: GalleryInfo[], rowIndex: number) => {
                    return this.historyColumnCount().toString() + ':' + rowIndex.toString() + ':' + this.historyRowKey(row);
                  })
                }
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Start)
              .alignItems(HorizontalAlign.Start)
              .padding({
                left: this.historyContentHorizontalPadding(),
                right: this.historyContentHorizontalPadding(),
                top: this.historyContentTopPadding(),
                bottom: 0
              })
              .onAreaChange((_oldArea: Area, newArea: Area) => {
                this.updateHistoryContentWidth(newArea.width as number);
              })
            }
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false, effectEdge: EffectEdge.START })
            .width('100%')
            .height('100%')
            .onAppear(() => {
              if (this.historyScrollOffset > 0) {
                setTimeout(() => {
                  this.historyScroller.scrollTo({ xOffset: 0, yOffset: this.historyScrollOffset });
                }, 0);
              }
            })
            .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
              this.updateToolbarForScroll();
            })
            .onScrollStop(() => {
              const offset = normalizeSceneScrollOffset(this.historyScroller.currentOffset().yOffset);
              if (offset <= 4) {
                this.toolbarOffsetY = 0;
              }
              this.historyScrollOffset = offset;
              this.historyToolbarScrollOffset = offset;
            })
          }
          .refreshOffset(this.HISTORY_REFRESH_OFFSET)
          .pullToRefresh(true)
          .onOffsetChange((value: number) => {
            if (value < this.HISTORY_REFRESH_OFFSET) {
              this.historyRefreshShowLogo = true;
              this.historyRefreshMsg = uiText('Pull down to refresh');
              this.historyRefreshScaleNum = value / this.HISTORY_REFRESH_OFFSET;
            } else {
              this.historyRefreshMsg = uiText('Release to refresh');
              this.historyRefreshScaleNum = this.HISTORY_REFRESH_OFFSET / value;
            }
          })
          .onStateChange((refreshStatus: RefreshStatus) => {
            if (refreshStatus === RefreshStatus.Refresh) {
              this.historyRefreshShowLogo = false;
              this.historyRefreshMsg = uiText('Refreshing...');
            }
          })
          .onRefreshing(() => {
            this.historyRefreshScaleNum = 0;
            this.historyRefreshShowLogo = false;
            this.historyRefreshMsg = uiText('Refreshing...');
            this.historyRefreshing = true;
            this.loadHistory();
          })
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F3F5F7')
      }
    }
  }
}

@Component
export struct TopListScene {
  private client: EhHttpClient = new EhHttpClient();
  onMenu: () => void = () => {};

  @State statusText: string = 'Loading top lists...';
  @State requestUrl: string = '';
  @State selectedIndex: number = 0;
  @State topList: TopListDetail = createEmptyTopListDetail();
  @State showGalleryList: boolean = false;
  @State galleryListTitle: string = 'Top List';
  @State galleryListModeLabel: string = 'Top List';
  @State galleryFollow: string = '';
  @State galleryKeyword: string = '';
  @State galleryRoute: GalleryRoute = GalleryRoute.TopLists;
  @State galleryUseForcedMode: boolean = false;
  @State galleryForcedMode: ListMode = ListMode.Normal;
  @State showDetail: boolean = false;
  @State showReader: boolean = false;
  @State showComments: boolean = false;
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = 'Tap a ranking item to load detail';
  @State detailRequestUrl: string = '';
  @State detailDownloadText: string = 'Download';
  @State detailLoaded: boolean = false;
  @State optimisticFavorite: boolean = false;
  @State favoriteBusy: boolean = false;
  @State readerStatus: string = 'Reader is ready';
  @State readerPage: GalleryPage = createEmptyPage();
  @State readerPreviewIndex: number = 0;
  @State renderVersion: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @State toolbarOffsetY: number = 0;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  private topListScroller: Scroller = new Scroller();
  private topListScrollOffset: number = 0;
  private topListToolbarScrollOffset: number = 0;
  private detailScrollOffset: number = 0;
  private readerPreviewMap: Map<number, GalleryPreview> = new Map();
  private readerPreviewPageRequests: Map<number, Promise<GalleryPreview | null>> = new Map();
  private readerPreviewPageSize: number = 0;

  aboutToAppear(): void {
    setActiveBackHandler(() => this.handleSystemBack());
    this.loadTopList();
  }

  aboutToDisappear(): void {
    setActiveBackHandler(null);
  }

  private handleSystemBack(): boolean {
    if (this.showReader) { this.closeReader(); return true; }
    if (this.showComments) { this.closeComments(); return true; }
    if (this.showDetail) { this.closeDetail(); return true; }
    if (this.showGalleryList) { this.closeGalleryList(); return true; }
    return false;
  }

  private loadTopList(): void {
    this.statusText = 'Loading top lists...';
    this.renderVersion++;
    this.client.loadTopList(GallerySite.E).then((result: TopListLoadResult) => {
      this.requestUrl = result.url;
      if (!result.ok || result.detail === null) {
        this.statusText = 'Load failed: ' + result.message;
        this.renderVersion++;
        return;
      }
      this.topList = cloneTopListDetail(result.detail);
      this.statusText = result.message + ': ' + result.detail.lists.length.toString() + ' sections';
      if (this.selectedIndex >= result.detail.lists.length) {
        this.selectedIndex = 0;
      }
      this.renderVersion++;
    }).catch((error: Error) => {
      this.statusText = 'Load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private openBucket(bucket: TopListBucket): void {
    this.galleryListTitle = 'Gallery Toplists';
    this.galleryListModeLabel = bucket.title;
    this.galleryFollow = bucket.follow;
    this.galleryKeyword = '';
    this.galleryRoute = GalleryRoute.TopLists;
    this.galleryUseForcedMode = false;
    this.showGalleryList = true;
  }

  private openTopListItem(item: TopListItem, info: TopListInfo): void {
    if (item.gid.length > 0 && item.token.length > 0) {
      this.loadDetailFromItem(item);
      return;
    }

    this.galleryListTitle = info.title;
    this.galleryListModeLabel = 'Related galleries';
    this.galleryFollow = '';
    this.galleryKeyword = item.value;
    this.galleryRoute = GalleryRoute.Home;
    this.galleryUseForcedMode = true;
    this.galleryForcedMode = info.kind === TopListKind.Uploader ? ListMode.Uploader : ListMode.Normal;
    this.showGalleryList = true;
  }

  private closeGalleryList(): void {
    this.showGalleryList = false;
    this.galleryFollow = '';
    this.galleryKeyword = '';
    this.galleryUseForcedMode = false;
  }

  private loadDetailFromItem(item: TopListItem): void {
    const gid = Number.parseInt(item.gid);
    if (Number.isNaN(gid)) {
      this.statusText = 'Invalid gallery id: ' + item.gid;
      return;
    }

    this.showDetail = true;
    const loadingDetail = createEmptyDetail();
    loadingDetail.gid = gid;
    loadingDetail.token = item.token;
    loadingDetail.title = item.value;
    this.detail = loadingDetail;
    this.resetReaderPreviewCache();
    this.detailStatus = 'Loading detail for gid ' + item.gid + '...';
    this.detailRequestUrl = '';
    this.detailDownloadText = downloadButtonText(gid);
    this.detailLoaded = false;
    this.optimisticFavorite = false;
    this.favoriteBusy = false;
    this.renderVersion++;

    this.client.loadGalleryDetail(gid, item.token, 0, GallerySite.E, this.requestUrl).then((result: GalleryDetailLoadResult) => {
      this.detailRequestUrl = result.url;
      if (!result.ok || result.detail === null) {
        this.detailStatus = 'Detail load failed: ' + result.message;
        this.renderVersion++;
        return;
      }
      this.detailStatus = 'Detail loaded';
      this.detail = mergeLoadedSceneDetail(result.detail, this.detail);
      this.seedReaderPreviewCache(this.detail.previewSet);
      this.detailDownloadText = downloadButtonText(result.detail.gid);
      this.detailLoaded = true;
      this.optimisticFavorite = this.detail.isFavorited;
      this.favoriteBusy = false;
      this.renderVersion++;
      saveGalleryToHistory(result.detail);
      this.prewarmReader();
    }).catch((error: Error) => {
      this.detailStatus = 'Detail load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private closeDetail(): void {
    this.showDetail = false;
    this.showReader = false;
    this.showComments = false;
    this.detail = createEmptyDetail();
    this.resetReaderPreviewCache();
    this.detailStatus = 'Tap a ranking item to load detail';
    this.detailRequestUrl = '';
    this.detailDownloadText = 'Download';
    this.detailLoaded = false;
    this.optimisticFavorite = false;
    this.favoriteBusy = false;
    this.readerStatus = 'Reader is ready';
    this.readerPage = createEmptyPage();
    this.readerPreviewIndex = 0;
    this.detailScrollOffset = 0;
    this.renderVersion++;
  }

  private openComments(): void {
    this.showComments = true;
    this.renderVersion++;
  }

  private closeComments(): void {
    this.showComments = false;
    this.renderVersion++;
  }

  private closeReader(): void {
    this.showReader = false;
    this.readerStatus = 'Reader is ready';
    this.readerPage = createEmptyPage();
    this.readerPreviewIndex = 0;
    this.renderVersion++;
  }

  private loadReaderPage(preview: GalleryPreview): void {
    if (preview.pageUrl.length === 0) {
      this.readerStatus = 'Preview has no page URL';
      return;
    }

    this.readerPreviewMap.set(preview.index, preview);
    this.readerPreviewIndex = preview.index;
    saveGalleryReadPosition(this.detail.gid, preview.index);
    this.readerStatus = 'Loading page ' + (preview.index + 1).toString() + '...';
    this.readerPage = createReaderLoadingPage(preview.pageUrl);
    this.renderVersion++;
    this.openReaderAbility(GallerySite.E);

    const cached = galleryPageCache.get(preview.pageUrl);
    if (cached !== null) {
      this.readerStatus = 'Page loaded from cache';
      this.readerPage = cloneGalleryPage(cached);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, cached);
      this.preloadReaderPages(preview.index);
      this.persistReaderSession(GallerySite.E);
      return;
    }

    this.client.loadGalleryPage(preview.pageUrl, GallerySite.E,
      readerPageReferer(this.detailRequestUrl, this.detail.previewSet, preview.index, GallerySite.E)).then((result: GalleryPageLoadResult) => {
      if (!result.ok || result.page === null) {
        this.readerStatus = 'Page load failed: ' + result.message;
        return;
      }
      const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
      galleryPageCache.put(cacheUrl, result.page);
      galleryPageCache.put(preview.pageUrl, result.page);
      this.readerStatus = 'Page loaded';
      this.readerPage = cloneGalleryPage(result.page);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, result.page);
      this.preloadReaderPages(preview.index);
      this.persistReaderSession(GallerySite.E);
    }).catch((error: Error) => {
      this.readerStatus = 'Page load failed: ' + error.message;
      this.renderVersion++;
      this.persistReaderSession(GallerySite.E);
    });
  }

  private cacheReaderImage(index: number, page: GalleryPage): void {
    cacheReaderImageForPage(page, (cachedPage: GalleryPage) => {
      galleryPageCache.put(cachedPage.pageUrl.length > 0 ? cachedPage.pageUrl : page.pageUrl, cachedPage);
      if (this.showReader && this.readerPreviewIndex === index) {
        this.readerPage = cloneGalleryPage(cachedPage);
        this.readerStatus = 'Page loaded from local cache';
        this.renderVersion++;
      }
    });
  }

  private async preloadReaderPages(index: number): Promise<void> {
    const count = readerPreloadCount();
    if (count <= 0) {
      return;
    }

    for (let offset = 1; offset <= count; offset++) {
      const nextIndex = index + offset;
      if (nextIndex < 0 || nextIndex >= this.readerTotalPages()) {
        return;
      }

      const preview = await this.ensureReaderPreview(nextIndex, true);
      if (preview === null) {
        continue;
      }
      if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
        continue;
      }

      try {
        const result = await this.client.loadGalleryPage(preview.pageUrl, GallerySite.E,
          readerPageReferer(this.detailRequestUrl, this.detail.previewSet, nextIndex, GallerySite.E));
        if (result.ok && result.page !== null) {
          const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
          galleryPageCache.put(cacheUrl, result.page);
          galleryPageCache.put(preview.pageUrl, result.page);
          this.cacheReaderImage(nextIndex, result.page);
        }
      } catch (error) {
      }
    }
  }

  private async prewarmReader(): Promise<void> {
    if (this.readerTotalPages() <= 0) {
      return;
    }

    const preview = await this.ensureReaderPreview(0, true);
    if (preview === null) {
      return;
    }
    if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
      return;
    }

    try {
      const result = await this.client.loadGalleryPage(preview.pageUrl, GallerySite.E,
        readerPageReferer(this.detailRequestUrl, this.detail.previewSet, 0, GallerySite.E));
      if (result.ok && result.page !== null) {
        const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
        galleryPageCache.put(cacheUrl, result.page);
        galleryPageCache.put(preview.pageUrl, result.page);
        this.cacheReaderImage(0, result.page);
        this.preloadReaderPages(0);
      }
    } catch (error) {
    }
  }

  private loadReaderPageByIndex(index: number): void {
    if (index < 0 || index >= this.readerTotalPages()) {
      return;
    }
    const preview = this.readerPreviewForIndex(index);
    if (preview !== null) {
      this.loadReaderPage(preview);
      return;
    }

    this.readerPreviewIndex = index;
    saveGalleryReadPosition(this.detail.gid, index);
    this.readerStatus = 'Resolving page ' + (index + 1).toString() + '...';
    this.readerPage = createReaderLoadingPage('');
    this.renderVersion++;
    this.openReaderAbility(GallerySite.E);
    this.ensureReaderPreview(index, false).then((resolved: GalleryPreview | null) => {
      if (resolved !== null && this.readerPreviewIndex === index) {
        this.loadReaderPage(resolved);
      }
    });
  }

  private readDetail(): void {
    if (this.readerTotalPages() <= 0) {
      this.detailStatus = 'Read is waiting for preview pages';
      return;
    }
    this.loadReaderPageByIndex(readerStartIndex(this.detail));
  }

  private persistReaderSession(site: GallerySite): void {
    readerSessionStore.updateSession(createReaderSessionState(this.detail, this.readerPage, this.readerStatus,
      this.detailRequestUrl, this.requestUrl, site, this.readerPreviewIndex));
  }

  private publishReaderSession(site: GallerySite): void {
    readerSessionStore.setSession(createReaderSessionState(this.detail, this.readerPage, this.readerStatus,
      this.detailRequestUrl, this.requestUrl, site, this.readerPreviewIndex));
  }

  private openReaderAbility(site: GallerySite): void {
    this.publishReaderSession(site);
    if (ehSettingsStore.getValue('reader_standalone', 'On') !== 'On') {
      this.showReader = true;
      return;
    }
    this.showReader = false;
    const context = getAbilityContext();
    if (context === undefined) {
      this.showReader = true;
      return;
    }
    context.startAbility({
      bundleName: 'yt.ehviewer.huawei',
      moduleName: 'entry',
      abilityName: 'ReaderAbility'
    }).catch((error: Error) => {
      this.readerStatus = 'Reader launch failed: ' + error.message;
      this.renderVersion++;
      this.persistReaderSession(site);
    });
  }

  private resetReaderPreviewCache(): void {
    this.readerPreviewMap.clear();
    this.readerPreviewPageRequests.clear();
    this.readerPreviewPageSize = 0;
  }

  private seedReaderPreviewCache(previews: GalleryPreview[]): void {
    if (previews.length > 0 && (this.readerPreviewPageSize <= 0 || previews.length > this.readerPreviewPageSize)) {
      this.readerPreviewPageSize = previews.length;
    }
    for (let i = 0; i < previews.length; i++) {
      this.readerPreviewMap.set(previews[i].index, previews[i]);
    }
  }

  private readerTotalPages(): number {
    return this.detail.pages > 0 ? this.detail.pages : Math.max(this.detail.previewSet.length, this.readerPreviewMap.size);
  }

  private readerPreviewForIndex(index: number): GalleryPreview | null {
    const cached = this.readerPreviewMap.get(index);
    if (cached !== undefined) {
      return cached;
    }
    for (let i = 0; i < this.detail.previewSet.length; i++) {
      if (this.detail.previewSet[i].index === index) {
        this.readerPreviewMap.set(index, this.detail.previewSet[i]);
        return this.detail.previewSet[i];
      }
    }
    return null;
  }

  private readerPreviewPageIndex(index: number): number {
    const pageSize = this.readerPreviewPageSize > 0 ? this.readerPreviewPageSize : Math.max(1, this.detail.previewSet.length);
    return Math.floor(index / pageSize);
  }

  private ensureReaderPreview(index: number, silent: boolean): Promise<GalleryPreview | null> {
    const cached = this.readerPreviewForIndex(index);
    if (cached !== null) {
      return Promise.resolve(cached);
    }
    if (this.detail.gid <= 0 || this.detail.token.length === 0 || index < 0 || index >= this.readerTotalPages()) {
      return Promise.resolve(null);
    }
    const previewPageIndex = this.readerPreviewPageIndex(index);
    const pending = this.readerPreviewPageRequests.get(previewPageIndex);
    if (pending !== undefined) {
      return pending;
    }
    const request = this.client.loadGalleryDetail(this.detail.gid, this.detail.token, previewPageIndex,
      GallerySite.E, this.detailRequestUrl).then((result: GalleryDetailLoadResult) => {
      this.readerPreviewPageRequests.delete(previewPageIndex);
      if (!result.ok || result.detail === null) {
        if (!silent) {
          this.readerStatus = 'Preview page load failed: ' + result.message;
          this.renderVersion++;
        }
        return null;
      }
      this.mergeReaderPreviewSet(result.detail);
      return this.readerPreviewForIndex(index);
    });
    this.readerPreviewPageRequests.set(previewPageIndex, request);
    return request;
  }

  private mergeReaderPreviewSet(loaded: GalleryDetail): void {
    this.seedReaderPreviewCache(loaded.previewSet);
    const byIndex: Map<number, GalleryPreview> = new Map();
    for (let i = 0; i < this.detail.previewSet.length; i++) {
      byIndex.set(this.detail.previewSet[i].index, this.detail.previewSet[i]);
    }
    for (let i = 0; i < loaded.previewSet.length; i++) {
      byIndex.set(loaded.previewSet[i].index, loaded.previewSet[i]);
    }
    const merged: GalleryPreview[] = Array.from(byIndex.values());
    merged.sort((left: GalleryPreview, right: GalleryPreview) => left.index - right.index);
    const nextDetail = cloneGalleryDetail(this.detail);
    nextDetail.previewSet = cloneGalleryPreviews(merged);
    nextDetail.previewPages = Math.max(nextDetail.previewPages, loaded.previewPages);
    nextDetail.pages = Math.max(nextDetail.pages, loaded.pages);
    this.detail = nextDetail;
    this.seedReaderPreviewCache(this.detail.previewSet);
    this.renderVersion++;
  }

  private toggleDownloadDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'Download needs a loaded gallery';
      return;
    }
    const queued = toggleGalleryDownload(this.detail);
    this.detailDownloadText = queued ? 'Queued' : 'Download';
    this.detailStatus = queued ? 'Added to download queue' : 'Removed from download queue';
    this.renderVersion++;
  }

  private toggleFavoriteDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      return;
    }
    if (this.favoriteBusy) {
      return;
    }
    const wasFavorited = this.detail.isFavorited;
    this.detailStatus = wasFavorited ? 'Removing from favorites...' : 'Adding to favorites...';
    this.favoriteBusy = true;
    this.optimisticFavorite = !wasFavorited;
    this.applyDetailFavoriteState(this.optimisticFavorite);
    this.renderVersion++;
    this.client.toggleFavorite(this.detail.gid, this.detail.token, wasFavorited,
      GallerySite.E).then((result: ToggleFavoriteResult) => {
      this.detailStatus = result.message;
      if (result.ok) {
        this.optimisticFavorite = result.nowFavorited;
        this.applyDetailFavoriteState(result.nowFavorited);
      } else {
        this.optimisticFavorite = wasFavorited;
        this.applyDetailFavoriteState(wasFavorited);
      }
      this.favoriteBusy = false;
      this.renderVersion++;
    }).catch((error: Error) => {
      this.detailStatus = 'Favorite failed: ' + error.message;
      this.optimisticFavorite = wasFavorited;
      this.applyDetailFavoriteState(wasFavorited);
      this.favoriteBusy = false;
      this.renderVersion++;
    });
  }

  private applyDetailFavoriteState(isFavorited: boolean): void {
    const nextDetail = cloneGalleryDetail(this.detail);
    nextDetail.isFavorited = isFavorited;
    nextDetail.favoriteSlot = isFavorited ? Math.max(0, nextDetail.favoriteSlot) : -2;
    this.detail = nextDetail;
  }

  private shareDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      this.renderVersion++;
      return;
    }
    const url = EhUrl.getGalleryDetailUrl(this.detail.gid, this.detail.token, 0, false, GallerySite.E);
    this.copyDetailLink(url, 'Gallery URL');
  }

  private rateDetail(rating: number): void {
    if (this.detail.gid <= 0 || this.detail.apiUid < 0 || this.detail.apiKey.length === 0) {
      this.detailStatus = 'Rating needs a loaded gallery session';
      this.renderVersion++;
      return;
    }
    this.detailStatus = 'Submitting rating...';
    this.renderVersion++;
    this.client.rateGallery(this.detail.gid, this.detail.token, this.detail.apiUid, this.detail.apiKey, rating,
      GallerySite.E).then((result: RateGalleryResult) => {
      this.detailStatus = result.message;
      if (result.ok) {
        const nextDetail = cloneGalleryDetail(this.detail);
        nextDetail.rating = result.rating;
        nextDetail.ratingCount = result.ratingCount > 0 ? result.ratingCount : nextDetail.ratingCount;
        nextDetail.rated = true;
        this.detail = nextDetail;
      }
      this.renderVersion++;
    }).catch((error: Error) => {
      this.detailStatus = 'Rating failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private copyDetailLink(url: string, label: string): void {
    if (url.length === 0) {
      this.detailStatus = label + ' link is unavailable';
      this.renderVersion++;
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data);
      this.detailStatus = label + ' link copied to clipboard';
    } catch (error) {
      this.detailStatus = label + ' copy failed: ' + String(error);
    }
    this.renderVersion++;
  }

  private currentInfo(): TopListInfo {
    if (this.topList.lists.length === 0 || this.selectedIndex < 0 || this.selectedIndex >= this.topList.lists.length) {
      return createEmptyTopListInfo();
    }
    return this.topList.lists[this.selectedIndex];
  }

  private updateToolbarForScroll(contentOffset: number): void {
    const delta = contentOffset - this.topListToolbarScrollOffset;
    this.toolbarOffsetY = nextFloatingToolbarOffset(this.toolbarOffsetY, delta, contentOffset, this.floatingToolbarHeight());
    this.topListToolbarScrollOffset = contentOffset;
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  private floatingToolbarHeight(): number {
    return this.statusBarVp() + 56;
  }

  build() {
    if (this.showReader) {
      ReaderScene({
        renderVersion: this.renderVersion,
        page: this.readerPage,
        statusText: this.readerStatus,
        pageIndex: this.readerPreviewIndex,
        totalPages: this.readerTotalPages(),
        onBack: () => {
          this.closeReader();
        },
        onPrev: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex - 1);
        },
        onNext: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex + 1);
        },
        onJump: (index: number) => {
          this.loadReaderPageByIndex(index);
        },
        onRetry: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex);
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showComments) {
      CommentsScene({
        renderVersion: this.renderVersion,
        comments: this.detail.comments,
        galleryTitle: galleryDisplayTitle(this.detail),
        onBack: () => {
          this.closeComments();
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showDetail) {
      GalleryDetailScene({
        renderVersion: this.renderVersion,
        detail: this.detail,
        isDetailLoaded: this.detailLoaded,
        isFavorited: this.optimisticFavorite,
        statusText: this.detailStatus,
        requestUrl: this.detailRequestUrl,
        downloadText: this.detailDownloadText,
        onBack: () => {
          this.closeDetail();
        },
        onDownload: () => {
          this.toggleDownloadDetail();
        },
        onRead: () => {
          this.readDetail();
        },
        onSelectPreview: (preview: GalleryPreview) => {
          this.loadReaderPage(preview);
        },
        onComments: () => {
          this.openComments();
        },
        onFavorite: () => {
          this.toggleFavoriteDetail();
        },
        onShare: () => {
          this.shareDetail();
        },
        onRate: (rating: number) => {
          this.rateDetail(rating);
        },
        onTorrent: () => {
          this.copyDetailLink(this.detail.torrentUrl, 'Torrent');
        },
        onArchive: () => {
          this.copyDetailLink(this.detail.archiveUrl, 'Archive');
        },
        initialDetailScrollOffset: this.detailScrollOffset,
        onDetailScrollUpdate: (offset: number) => {
          this.detailScrollOffset = offset;
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showGalleryList) {
      Column() {
        Row() {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(20)
              .fontColor([Color.White])
          }
          .width(36)
          .height(36)
          .backgroundColor(APP_THEME_COLOR)
          .onClick(() => {
            this.closeGalleryList();
          })
          Text(uiText(this.galleryListTitle) + ' / ' + uiText(this.galleryListModeLabel))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#17202A')
            .margin({ left: 12 })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: this.statusBarVp() + 10, bottom: 8 })
        .backgroundColor(Color.White)

        GalleryListScene({
          sceneTitle: this.galleryListTitle,
          listMode: this.galleryListModeLabel,
          sourceRoute: this.galleryRoute,
          follow: this.galleryFollow,
          initialKeyword: this.galleryKeyword,
          useForcedMode: this.galleryUseForcedMode,
          forcedMode: this.galleryForcedMode
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .transition(TransitionEffect.move(TransitionEdge.END)
        .animation({ duration: 300, curve: Curve.EaseOut }))
    } else {
      FloatingToolbarHost({
        kind: 'title',
        title: '排行',
        requestUrl: '',
        toolbarOffsetY: this.toolbarOffsetY,
        toolbarHeight: 56,
        onMenu: this.onMenu,
        onRefresh: () => {
          this.loadTopList();
        }
      }) {
        Column() {
          if (this.topList.lists.length === 0) {
            Column() {
              GalleryListStateView({
                statusText: this.statusText,
                requestUrl: this.requestUrl,
                onRefresh: () => {
                  this.loadTopList();
                }
              })
                .layoutWeight(1)
            }
            .width('100%')
            .height('100%')
            .padding({ top: this.floatingToolbarHeight() + 12 })
          } else {
            Column() {
              TopListBoard({
                lists: this.topList.lists,
                selectedIndex: this.selectedIndex,
                info: this.currentInfo(),
                toolbarOffsetY: this.toolbarOffsetY,
                topPadding: this.floatingToolbarHeight() + 4,
                statusBarHeight: this.statusBarVp(),
                renderVersion: this.renderVersion,
                onSelectList: (index: number) => {
                  if (this.selectedIndex === index) {
                    return;
                  }
                  this.selectedIndex = index;
                  this.topListScrollOffset = 0;
                  this.topListToolbarScrollOffset = 0;
                  this.toolbarOffsetY = 0;
                  this.renderVersion++;
                },
                onOpenBucket: (bucket: TopListBucket) => {
                  this.openBucket(bucket);
                },
                onOpenItem: (item: TopListItem, info: TopListInfo) => {
                  this.openTopListItem(item, info);
                },
                initialScrollOffset: this.topListScrollOffset,
                onScrollUpdate: (offset: number, scrollOffset: number) => {
                  this.updateToolbarForScroll(offset);
                  this.topListScrollOffset = offset;
                }
              })
              .layoutWeight(1)
            }
            .width('100%')
            .height('100%')
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F3F5F7')
      }
    }
  }
}

@Component
export struct TopListTabs {
  @Prop lists: TopListInfo[] = [];
  @Prop selectedIndex: number = 0;
  onSelect: (index: number) => void = () => {};

  build() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.lists, (info: TopListInfo, index: number) => {
          Button(info.title)
            .type(ButtonType.Normal)
            .stateEffect(false)
            .height(34)
            .fontSize(12)
            .fontColor(index === this.selectedIndex ? Color.White : '#2F6F8F')
            .backgroundColor(index === this.selectedIndex ? '#2F6F8F' : Color.Transparent)
            .border({ width: 1, color: index === this.selectedIndex ? '#2F6F8F' : '#B8CDD8' })
            .onClick(() => {
              this.onSelect(index);
            })
        }, (info: TopListInfo, index: number) => info.kind.toString() + ':' + index.toString() + ':' + this.selectedIndex.toString())
      }
      .padding({ left: 2, right: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }
}

@Component
export struct TopListBoard {
  @Prop lists: TopListInfo[] = [];
  @Prop selectedIndex: number = 0;
  @Prop info: TopListInfo = createEmptyTopListInfo();
  @Prop toolbarOffsetY: number = 0;
  @Prop topPadding: number = 74;
  @Prop statusBarHeight: number = 0;
  @Prop renderVersion: number = 0;
  onSelectList: (index: number) => void = () => {};
  onOpenBucket: (bucket: TopListBucket) => void = () => {};
  onOpenItem: (item: TopListItem, info: TopListInfo) => void = () => {};
  initialScrollOffset: number = 0;
  onScrollUpdate: (offset: number, scrollOffset: number) => void = () => {};
  private boardScroller: Scroller = new Scroller();
  private readonly TABS_BAR_HEIGHT: number = 42;

  private tabsVisualTop(): number {
    return Math.max(this.statusBarHeight, this.topPadding + this.toolbarOffsetY);
  }

  private contentTopPadding(): number {
    return this.tabsVisualTop() + this.TABS_BAR_HEIGHT + 8;
  }

  @Builder
  private TabsBar() {
    Column() {
      TopListTabs({
        lists: this.lists,
        selectedIndex: this.selectedIndex,
        onSelect: this.onSelectList
      })
        .width('100%')
        .padding({ top: 4, bottom: 4 })
        .backgroundColor(Color.Transparent)
    }
      .width('100%')
      .height(this.TABS_BAR_HEIGHT)
      .backgroundColor(Color.Transparent)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      List({ space: 10, scroller: this.boardScroller }) {
        ForEach(this.info.buckets, (bucket: TopListBucket) => {
          ListItem() {
            TopListBucketCard({
              bucket: bucket,
              info: this.info,
              canOpenBucket: this.info.kind === TopListKind.Gallery,
              onOpenBucket: this.onOpenBucket,
              onOpenItem: this.onOpenItem
            })
          }
        }, (bucket: TopListBucket) => this.selectedIndex.toString() + ':' + bucket.title)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 12, right: 12, top: this.contentTopPadding(), bottom: 0 })
      .backgroundColor('#F3F5F7')
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false, effectEdge: EffectEdge.START })
      .onAppear(() => {
        if (this.initialScrollOffset > 0) {
          this.boardScroller.scrollTo({ xOffset: 0, yOffset: this.initialScrollOffset });
        }
      })
      .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
        this.onScrollUpdate(normalizeSceneScrollOffset(this.boardScroller.currentOffset().yOffset), scrollOffset);
      })
      .onScrollStop(() => {
        this.onScrollUpdate(normalizeSceneScrollOffset(this.boardScroller.currentOffset().yOffset), 0);
      })

      Column() {
        this.TabsBar()
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: this.tabsVisualTop() })
      .backgroundColor(Color.Transparent)
      .zIndex(8)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F3F5F7')
  }
}

@Component
export struct TopListBucketCard {
  bucket: TopListBucket = createEmptyTopListBucket();
  info: TopListInfo = createEmptyTopListInfo();
  canOpenBucket: boolean = false;
  onOpenBucket: (bucket: TopListBucket) => void = () => {};
  onOpenItem: (item: TopListItem, info: TopListInfo) => void = () => {};

  build() {
    Column() {
      Row() {
        Text(this.bucket.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.canOpenBucket ? '#2F6F8F' : '#17202A')
          .layoutWeight(1)
          .decoration({ type: this.canOpenBucket ? TextDecorationType.Underline : TextDecorationType.None })
          .onClick(() => {
            if (this.canOpenBucket) {
              this.onOpenBucket(this.bucket);
            }
          })
        Text(this.bucket.items.length.toString() + ' entries')
          .fontSize(12)
          .fontColor('#667085')
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.bucket.items, (item: TopListItem, index: number) => {
          TopListChip({
            item: item,
            color: topListChipColor(index),
            onTap: () => {
              this.onOpenItem(item, this.info);
            }
          })
        }, (item: TopListItem) => item.href + item.value)
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(6)
  }
}

@Component
export struct TopListChip {
  item: TopListItem = createEmptyTopListItem();
  color: string = '#2F6F8F';
  onTap: () => void = () => {};

  build() {
    Text(this.item.value)
      .fontSize(13)
      .fontColor(Color.White)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .margin({ right: 8, bottom: 8 })
      .backgroundColor(this.color)
      .borderRadius(5)
      .onClick(() => {
        this.onTap();
      })
  }
}
