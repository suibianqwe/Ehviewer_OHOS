import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { HdsNavigation, HideMode, HdsNavigationTitleMode, BottomBuilderShowType } from '@kit.UIDesignKit';
import { GalleryCategory, GalleryComment, GalleryDetail, GalleryInfo, GalleryPage, GalleryPreview, GalleryRoute, GallerySite, GalleryTagGroup, TopListBucket, TopListDetail, TopListInfo, TopListItem, TopListKind } from '../model/GalleryModels';
import { ehCookieStore } from '../services/EhCookieStore';
import { DownloadDirectoryScanResult, RestoredDownloadGallery, ehDownloadFileStore } from '../services/EhDownloadFileStore';
import { DownloadInfo, DownloadLabel, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehSettingsStore, SettingEntry, defaultSettingEntries } from '../services/EhSettingsStore';
import { EhHttpClient, GalleryDetailLoadResult, GalleryListLoadResult, GalleryPageLoadResult, NetworkDiagnosticResult, RateGalleryResult, SignInResult, ToggleFavoriteResult, TopListLoadResult } from '../services/EhHttpClient';
import { EhUrl, FavListUrlBuilder, ListMode, ListUrlBuilder } from '../services/EhUrl';
import { galleryPageCache } from '../services/GalleryPageCache';
import { CacheClearResult, readerImageCache } from '../services/ReaderImageCache';
import { ehSpiderInfoStore } from '../services/EhSpiderInfoStore';
import { MigrationTask, migrationTasks } from '../services/MigrationStatus';
import { FilterRule, FILTER_MODE_TITLE, FILTER_MODE_UPLOADER, FILTER_MODE_TAG, FILTER_MODE_TAG_NAMESPACE, ehFilterStore } from '../services/EhFilterStore';
import { LANGUAGE_REVISION_KEY, APP_THEME_COLOR, themeSurfaceColor } from '../shared/EhShared';
import { EhNavBar } from '../components/NavigationComponents';
import { EhBackupBundle, DrawerItem, SettingsHeaderItem, SettingsRowItem, SessionMode, SettingsPanel, DRAWER_ITEMS, SETTINGS_HEADERS, STATUS_BAR_HEIGHT_KEY, ON_OFF_OPTIONS, shouldUseChineseUi, uiText, uiValue, uiStatusText, uiPageText, zhText, setActiveBackHandler, runActiveBackHandler, createEmptyGallery, createEmptyDownloadInfo, createDetailFromGallery, createEmptyDetail, createEmptyPreview, createEmptyPage, createEmptyTopListDetail, createEmptyTopListInfo, createEmptyTopListBucket, createEmptyTopListItem, cloneStringArray, cloneRequiredStringArray, cloneGalleryInfo, cloneGalleryInfos, padTwo, applyGalleryFilters, cloneGalleryTagGroups, cloneGalleryComments, cloneGalleryPreviews, cloneGalleryDetail, cloneGalleryPage, createReaderLoadingPage, cloneTopListItem, cloneTopListBucket, cloneTopListInfo, cloneTopListDetail, getAbilityContext, saveGalleryToHistory, saveGalleryReadPosition, readerStartIndex, downloadButtonText, toggleGalleryDownload, saveDownloadsQuietly, filterDownloadItems, downloadItemMatches, sortDownloadItems, nextDownloadStatusFilter, nextDownloadLabelFilter, nextDownloadSortMode, nextStringOption, nextDownloadState, nextDownloadLabel, downloadLabelName, downloadStateLabel, downloadStateColor, downloadProgressText, downloadSizeText, downloadImageUrlForPage, downloadThreadLimit, downloadPageIndexes, downloadQueueSummary, parseHistoryMaxSize, routeTitle, routeSubtitle, launchRouteFromSetting, settingsPanelTitle, settingsRowsForPanel, optionSettingsRow, textSettingsRow, staticSettingsRow, settingEntryValue, cloneStringOptions, settingMigrationMessage, nextOption, isValidProxyPortText, formatNetworkDiagnostics, listModeForRoute, routeUsesKeyword, usesGallerySearchToolbar, usesEmbeddedToolbar, defaultKeywordForRoute, gallerySearchTitle, currentGallerySite, effectiveListSite, gallerySiteName, galleryListFailureMessage, shouldRetryGalleryListOnE, withGalleryListMessage, readerPageReferer, readerDisplayImageUrl, cacheReaderImageForPage, cacheThumbnailImage, cloneGalleryPageWithCache, readerLocalImageSource, readerZoomSize, readerFullImageWidth, readerFullImageHeight, readerImageFit, readerShortUrl, readerPreloadCount, readerIsRightToLeft, categoryName, categoryColor, ratingText, galleryDisplayTitle, showGalleryPages, galleryListMode, galleryThumbWidth, galleryThumbHeight, galleryRowHeight, galleryTagPreview, detailTitleFontSize, detailTitleMaxLines, detailHeadingFontSize, readerShowProgress, readerShowClock, readerClockText, padTimeNumber, topListChipColor } from '../shared/EhShared';

interface GalleryListSceneCache {
  keyword: string;
  statusText: string;
  requestUrl: string;
  activeSite: GallerySite;
  pageIndex: number;
  totalPages: number;
  nextUrl: string;
  resultCount: string;
  galleries: GalleryInfo[];
  hasFirstRefresh: boolean;
  filterActive: boolean;
  listScrollOffset: number;
}

const galleryListSceneCache: Map<string, GalleryListSceneCache> = new Map();

function updateGalleryListScrollCache(key: string, offset: number): void {
  const cache = galleryListSceneCache.get(key);
  if (cache === undefined) {
    return;
  }
  cache.listScrollOffset = normalizeGalleryListScrollOffset(offset);
}

function normalizeGalleryListScrollOffset(offset: number): number {
  if (offset <= 1 || Number.isNaN(offset)) {
    return 0;
  }
  return offset;
}

@Component
export struct HomeGalleryScene {
  onMenu: () => void = () => {};

  build() {
    GalleryListScene({
      sceneTitle: 'Homepage',
      listMode: 'Search',
      sourceRoute: GalleryRoute.Home,
      onMenu: this.onMenu
    })
  }
}

@Component
export struct SubscriptionGalleryScene {
  onMenu: () => void = () => {};

  build() {
    GalleryListScene({
      sceneTitle: 'Subscription',
      listMode: 'Watched tags',
      sourceRoute: GalleryRoute.Subscription,
      onMenu: this.onMenu
    })
  }
}

@Component
export struct HotGalleryScene {
  onMenu: () => void = () => {};

  build() {
    GalleryListScene({
      sceneTitle: 'What\'s Hot',
      listMode: 'Popular',
      sourceRoute: GalleryRoute.WhatsHot,
      onMenu: this.onMenu
    })
  }
}

@Component
export struct FavoriteGalleryScene {
  onMenu: () => void = () => {};

  build() {
    GalleryListScene({
      sceneTitle: 'Favourite',
      listMode: 'Favorites',
      sourceRoute: GalleryRoute.Favorites,
      onMenu: this.onMenu
    })
  }
}


@Component
export struct GalleryListScene {
  private client: EhHttpClient = new EhHttpClient();

  sceneTitle: string = 'Homepage';
  listMode: string = 'Search';
  sourceRoute: GalleryRoute = GalleryRoute.Home;
  follow: string = '';
  initialKeyword: string = '';
  useForcedMode: boolean = false;
  forcedMode: ListMode = ListMode.Normal;
  onMenu: () => void = () => {};

  @State keyword: string = '';
  @State statusText: string = 'Loading galleries...';
  @State requestUrl: string = '';
  @State activeSite: GallerySite = GallerySite.E;
  @State pageIndex: number = 0;
  @State totalPages: number = 0;
  @State nextUrl: string = '';
  @State resultCount: string = '';
  @State galleries: GalleryInfo[] = [];
  @State hasFirstRefresh: boolean = false;
  @State scrollResetVersion: number = 0;
  @State fabExpanded: boolean = false;
  @State filterActive: boolean = false;
  @State showDetail: boolean = false;
  @State showReader: boolean = false;
  @State showComments: boolean = false;
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = 'Tap a gallery row to load detail';
  @State detailRequestUrl: string = '';
  @State detailDownloadText: string = 'Download';
  @State readerStatus: string = 'Reader is ready';
  @State readerPage: GalleryPage = createEmptyPage();
  @State readerPreviewIndex: number = 0;
  @State renderVersion: number = 0;
  @State isLoadingMore: boolean = false;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  private listScrollOffset: number = 0;
  private detailScrollOffset: number = 0;

  private cacheKey(): string {
    const mode = this.useForcedMode ? this.forcedMode.toString() : listModeForRoute(this.sourceRoute).toString();
    return this.sourceRoute.toString() + '|' + mode + '|' + this.follow + '|' + this.initialKeyword;
  }

  private restoreListCache(): boolean {
    const cache = galleryListSceneCache.get(this.cacheKey());
    if (cache === undefined) {
      return false;
    }
    this.keyword = cache.keyword;
    this.statusText = cache.statusText;
    this.requestUrl = cache.requestUrl;
    this.activeSite = cache.activeSite;
    this.pageIndex = cache.pageIndex;
    this.totalPages = cache.totalPages;
    this.nextUrl = cache.nextUrl;
    this.resultCount = cache.resultCount;
    this.galleries = cloneGalleryInfos(cache.galleries);
    this.hasFirstRefresh = cache.hasFirstRefresh;
    this.filterActive = cache.filterActive;
    this.listScrollOffset = cache.listScrollOffset;
    return true;
  }

  private saveListCache(): void {
    galleryListSceneCache.set(this.cacheKey(), {
      keyword: this.keyword,
      statusText: this.statusText,
      requestUrl: this.requestUrl,
      activeSite: this.activeSite,
      pageIndex: this.pageIndex,
      totalPages: this.totalPages,
      nextUrl: this.nextUrl,
      resultCount: this.resultCount,
      galleries: cloneGalleryInfos(this.galleries),
      hasFirstRefresh: this.hasFirstRefresh,
      filterActive: this.filterActive,
      listScrollOffset: this.listScrollOffset
    });
  }

  private resetListScroll(): void {
    this.listScrollOffset = 0;
    this.saveListCache();
  }


  aboutToAppear(): void {
    if (!this.restoreListCache()) {
      this.keyword = this.initialKeyword.length > 0 ? this.initialKeyword : defaultKeywordForRoute(this.sourceRoute);
    }
    const context = getAbilityContext();
    if (context !== undefined) {
      ehCookieStore.load(context).catch((error: Error) => {
        this.statusText = 'Cookie load failed, using current session: ' + error.message;
      });
      ehFilterStore.load(context).catch(() => {});
    }
    this.firstRefresh();
    setActiveBackHandler(() => this.handleSystemBack());
  }

  aboutToDisappear(): void {
    this.saveListCache();
    setActiveBackHandler(null);
  }

  private handleSystemBack(): boolean {
    if (this.showReader) {
      this.closeReader();
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

  private firstRefresh(): void {
    if (this.hasFirstRefresh) {
      return;
    }
    this.hasFirstRefresh = true;
    this.loadRemote(0);
  }

  private absoluteListUrl(url: string): string {
    if (url.indexOf('http://') === 0 || url.indexOf('https://') === 0) {
      return url;
    }
    if (url.indexOf('//') === 0) {
      return 'https:' + url;
    }
    const host = EhUrl.getHost(this.activeSite);
    if (url.indexOf('/') === 0) {
      return host.substring(0, host.length - 1) + url;
    }
    return host + url;
  }

  private loadRemote(pageIndex: number, preserveExisting: boolean = false, onDone?: () => void): void {
    this.pageIndex = pageIndex;
    this.statusText = 'Loading...';
    if (!preserveExisting) {
      this.resultCount = '';
      this.galleries = [];
    }
    this.nextUrl = '';
    this.isLoadingMore = false;
    if (pageIndex === 0) {
      this.resetListScroll();
      this.scrollResetVersion++;
    }
    this.renderVersion++;
    this.closeDetail();
    this.saveListCache();
    const request = this.loadRoutePageWithFallback(pageIndex);

    request.then((result: GalleryListLoadResult) => {
      this.requestUrl = result.url;
      this.galleries = applyGalleryFilters(cloneGalleryInfos(result.galleries));
      this.statusText = result.ok ? result.message : galleryListFailureMessage(result, this.activeSite);
      this.totalPages = result.pages;
      this.nextUrl = result.nextUrl;
      this.resultCount = result.resultCount;
      this.renderVersion++;
      this.saveListCache();
      if (onDone !== undefined) {
        onDone();
      }
    }).catch((error: Error) => {
      this.statusText = 'Load failed: ' + error.message;
      this.galleries = [];
      this.renderVersion++;
      this.saveListCache();
      if (onDone !== undefined) {
        onDone();
      }
    });
  }

  private loadAppendPage(): void {
    if (this.isLoadingMore) {
      return;
    }
    // Only stop if we have confirmed total page count AND already at the last page
    if (this.nextUrl.length === 0 && this.totalPages > 0 && this.pageIndex >= this.totalPages - 1) {
      this.statusText = uiText('All pages loaded');
      return;
    }
    const nextPage = this.pageIndex + 1;
    this.isLoadingMore = true;

    const request = this.nextUrl.length > 0 ? this.client.loadGalleryListUrl(this.absoluteListUrl(this.nextUrl), this.activeSite) :
      this.loadRoutePageWithFallback(nextPage);

    request.then((result: GalleryListLoadResult) => {
      this.requestUrl = result.url;
      const newGalleries = applyGalleryFilters(cloneGalleryInfos(result.galleries));
      if (newGalleries.length === 0) {
        // Empty page = reached the end even if we don't know total
        this.statusText = uiText('All pages loaded');
        this.isLoadingMore = false;
        this.saveListCache();
        return;
      }
      const existingGids: Set<number> = new Set(this.galleries.map((g: GalleryInfo) => g.gid));
      const unique: GalleryInfo[] = newGalleries.filter((g: GalleryInfo) => !existingGids.has(g.gid));
      this.galleries = this.galleries.concat(unique);
      this.pageIndex = nextPage;
      if (result.pages > 0) {
        this.totalPages = result.pages;
      }
      this.nextUrl = result.nextUrl;
      this.resultCount = result.resultCount;
      this.statusText = result.ok ? result.message : galleryListFailureMessage(result, this.activeSite);
      this.isLoadingMore = false;
      this.saveListCache();
    }).catch((error: Error) => {
      this.statusText = 'Load more failed: ' + error.message;
      this.isLoadingMore = false;
      this.saveListCache();
    });
  }

  private loadRoutePageWithFallback(pageIndex: number): Promise<GalleryListLoadResult> {
    const primarySite = effectiveListSite(this.sourceRoute);
    this.activeSite = primarySite;
    return this.loadRoutePage(pageIndex, primarySite).then((primary: GalleryListLoadResult) => {
      if (!shouldRetryGalleryListOnE(primary, primarySite, this.sourceRoute)) {
        this.activeSite = primarySite;
        return primary;
      }

      return this.loadRoutePage(pageIndex, GallerySite.E).then((fallback: GalleryListLoadResult) => {
        if (fallback.ok || fallback.galleries.length > 0) {
          this.activeSite = GallerySite.E;
          return withGalleryListMessage(fallback,
            fallback.message + ' (ExHentai returned an empty list, retried on E-Hentai)');
        }

        this.activeSite = primarySite;
        return withGalleryListMessage(primary, primary.message + '; E-Hentai fallback: ' + fallback.message);
      }).catch((error: Error) => {
        this.activeSite = primarySite;
        return withGalleryListMessage(primary, primary.message + '; E-Hentai fallback failed: ' + error.message);
      });
    });
  }

  private loadRoutePage(pageIndex: number, site: GallerySite): Promise<GalleryListLoadResult> {
    if (this.sourceRoute === GalleryRoute.Favorites) {
      const builder = new FavListUrlBuilder();
      builder.keyword = this.keyword;
      builder.index = pageIndex;
      this.requestUrl = builder.build(site);
      return this.client.loadFavoritesList(builder, site);
    }

    const builder = new ListUrlBuilder();
    builder.keyword = routeUsesKeyword(this.sourceRoute) ? this.keyword : '';
    builder.pageIndex = pageIndex;
    const routeMode = this.useForcedMode ? this.forcedMode : listModeForRoute(this.sourceRoute);
    builder.mode = this.filterActive && builder.keyword.trim().length > 0 ? ListMode.Filter : routeMode;
    builder.follow = this.follow;
    this.requestUrl = builder.build(site);
    return this.client.loadGalleryList(builder, site);
  }

  private loadPreviousPage(): void {
    if (this.pageIndex > 0) {
      this.loadRemote(this.pageIndex - 1);
    }
  }

  private loadNextPage(): void {
    if (this.totalPages <= 0 || this.pageIndex + 1 < this.totalPages) {
      this.loadRemote(this.pageIndex + 1);
    }
  }

  private applySearch(): void {
    this.fabExpanded = false;
    this.resetListScroll();
    this.loadRemote(0);
  }

  private toggleFilter(): void {
    this.filterActive = !this.filterActive;
    this.fabExpanded = false;
    if (this.keyword.trim().length > 0) {
      this.loadRemote(0);
      return;
    }
    this.statusText = this.filterActive ? 'Filter mode is on; enter a keyword to apply it' : 'Filter mode is off';
    this.saveListCache();
  }

  private jumpGalleryPage(): void {
    this.fabExpanded = false;
    if (this.totalPages <= 1) {
      this.statusText = 'No other page to jump to';
      return;
    }
    const nextPage = this.pageIndex + 1 < this.totalPages ? this.pageIndex + 1 : 0;
    this.loadRemote(nextPage);
  }

  private openRandomGallery(): void {
    this.fabExpanded = false;
    if (this.galleries.length === 0) {
      this.statusText = 'Random needs a loaded gallery list';
      return;
    }
    const index = Math.floor(Math.random() * this.galleries.length);
    this.loadDetail(this.galleries[index]);
  }

  private loadDetail(gallery: GalleryInfo): void {
    this.showDetail = true;
    this.detail = createDetailFromGallery(gallery);
    this.detailStatus = 'Loading detail for gid ' + gallery.gid.toString() + '...';
    this.detailRequestUrl = '';
    this.detailDownloadText = downloadButtonText(gallery.gid);
    this.renderVersion++;

    this.client.loadGalleryDetail(gallery.gid, gallery.token, 0, this.activeSite, this.requestUrl).then((result: GalleryDetailLoadResult) => {
      this.detailRequestUrl = result.url;
      if (!result.ok || result.detail === null) {
        this.detailStatus = 'Detail load failed: ' + result.message;
        this.renderVersion++;
        return;
      }

      this.detailStatus = 'Detail loaded';
      this.detail = cloneGalleryDetail(result.detail);
      this.detailDownloadText = downloadButtonText(result.detail.gid);
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
    this.detailStatus = 'Tap a gallery row to load detail';
    this.detailRequestUrl = '';
    this.detailDownloadText = 'Download';
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

    this.showReader = true;
    this.readerPreviewIndex = preview.index;
    saveGalleryReadPosition(this.detail.gid, preview.index);
    this.readerStatus = 'Loading page ' + (preview.index + 1).toString() + '...';
    this.readerPage = createReaderLoadingPage(preview.pageUrl);
    this.renderVersion++;

    const cached = galleryPageCache.get(preview.pageUrl);
    if (cached !== null) {
      this.readerStatus = 'Page loaded from cache';
      this.readerPage = cloneGalleryPage(cached);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, cached);
      this.preloadReaderPages(preview.index);
      return;
    }

    this.client.loadGalleryPage(preview.pageUrl, this.activeSite,
      readerPageReferer(this.detailRequestUrl, this.detail.previewSet, preview.index, this.activeSite)).then((result: GalleryPageLoadResult) => {
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
    }).catch((error: Error) => {
      this.readerStatus = 'Page load failed: ' + error.message;
      this.renderVersion++;
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
      if (nextIndex < 0 || nextIndex >= this.detail.previewSet.length) {
        return;
      }

      const preview = this.detail.previewSet[nextIndex];
      if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
        continue;
      }

      try {
        const result = await this.client.loadGalleryPage(preview.pageUrl, this.activeSite,
          readerPageReferer(this.detailRequestUrl, this.detail.previewSet, nextIndex, this.activeSite));
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
    if (this.detail.previewSet.length === 0) {
      return;
    }

    const preview = this.detail.previewSet[0];
    if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
      return;
    }

    try {
      const result = await this.client.loadGalleryPage(preview.pageUrl, this.activeSite,
        readerPageReferer(this.detailRequestUrl, this.detail.previewSet, 0, this.activeSite));
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
    if (index < 0 || index >= this.detail.previewSet.length) {
      return;
    }
    this.loadReaderPage(this.detail.previewSet[index]);
  }

  private readDetail(): void {
    if (this.detail.previewSet.length === 0) {
      this.detailStatus = 'Read is waiting for preview pages';
      return;
    }
    this.loadReaderPageByIndex(readerStartIndex(this.detail));
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
    const wasFavorited = this.detail.isFavorited;
    this.detailStatus = wasFavorited ? 'Removing from favorites...' : 'Adding to favorites...';
    this.client.toggleFavorite(this.detail.gid, this.detail.token, wasFavorited,
      this.activeSite).then((result: ToggleFavoriteResult) => {
      this.detailStatus = result.message;
      if (result.ok) {
        this.detail.isFavorited = result.nowFavorited;
      }
      this.renderVersion++;
    }).catch((error: Error) => {
      this.detailStatus = 'Favorite failed: ' + error.message;
    });
  }

  private shareDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      return;
    }
    const url = EhUrl.getGalleryDetailUrl(this.detail.gid, this.detail.token, 0, false, this.activeSite);
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data);
      this.detailStatus = 'Gallery URL copied to clipboard';
    } catch (error) {
      this.detailStatus = 'Copy failed: ' + String(error);
    }
    this.renderVersion++;
  }

  build() {
    Column() {
      if (this.showReader) {
        ReaderScene({
          renderVersion: this.renderVersion,
          page: this.readerPage,
          statusText: this.readerStatus,
          pageIndex: this.readerPreviewIndex,
          totalPages: this.detail.previewSet.length,
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
          isFavorited: this.detail.isFavorited,
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
          initialDetailScrollOffset: this.detailScrollOffset,
          onDetailScrollUpdate: (offset: number) => {
            this.detailScrollOffset = offset;
          }
        })
          .transition(TransitionEffect.move(TransitionEdge.END)
            .animation({ duration: 300, curve: Curve.EaseOut }))
      } else {
        GalleryListContent({
          renderVersion: this.renderVersion,
          sceneTitle: this.sceneTitle,
          listMode: this.listMode,
          keyword: this.keyword,
          searchTitle: gallerySearchTitle(this.sourceRoute, this.keyword, this.filterActive),
          actionsExpanded: this.fabExpanded,
          filterActive: this.filterActive,
          canJump: this.totalPages > 1,
          canRandom: this.galleries.length > 0,
          statusText: this.statusText,
          requestUrl: this.requestUrl,
          isLoadingMore: this.isLoadingMore,
          galleries: this.galleries,
          onKeywordChange: (value: string) => {
            this.keyword = value;
          },
          onMenu: () => {
            this.onMenu();
          },
          onSearch: () => {
            this.applySearch();
          },
          onRefresh: () => {
            this.loadRemote(0, this.galleries.length > 0);
          },
          onRefreshPull: (done: () => void) => {
            this.loadRemote(0, this.galleries.length > 0, done);
          },
          onLoadMore: () => {
            this.loadAppendPage();
          },
          onToggleActions: () => {
            this.fabExpanded = !this.fabExpanded;
          },
          onFilter: () => {
            this.toggleFilter();
          },
          onJump: () => {
            this.jumpGalleryPage();
          },
          onRandom: () => {
            this.openRandomGallery();
          },
          onSelectGallery: (gallery: GalleryInfo) => {
            this.loadDetail(gallery);
          },
          scrollResetVersion: this.scrollResetVersion,
          initialScrollOffset: this.listScrollOffset,
          onScrollUpdate: (offset: number) => {
            this.listScrollOffset = offset;
            updateGalleryListScrollCache(this.cacheKey(), this.listScrollOffset);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct GalleryListContent {
  @Prop renderVersion: number = 0;
  @Prop sceneTitle: string = '';
  @Prop listMode: string = '';
  @Prop keyword: string = '';
  @Prop searchTitle: string = '';
  @Prop actionsExpanded: boolean = false;
  @Prop filterActive: boolean = false;
  @Prop canJump: boolean = false;
  @Prop canRandom: boolean = false;
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  @Prop isLoadingMore: boolean = false;
  @Prop galleries: GalleryInfo[] = [];
  @Prop @Watch('onScrollReset') scrollResetVersion: number = 0;
  private lastResetVersion: number = 0;
  onKeywordChange: (value: string) => void = () => {};
  onMenu: () => void = () => {};
  onSearch: () => void = () => {};
  onRefresh: () => void = () => {};
  onLoadMore: () => void = () => {};
  onToggleActions: () => void = () => {};
  onFilter: () => void = () => {};
  onJump: () => void = () => {};
  onRandom: () => void = () => {};
  onSelectGallery: (gallery: GalleryInfo) => void = () => {};
  initialScrollOffset: number = 0;
  onScrollUpdate: (offset: number) => void = () => {};
  @State contentWidth: number = 0;
  @State layoutVersion: number = 0;
  @State refreshing: boolean = false;
  onRefreshPull: (done: () => void) => void = (done: () => void) => { done(); };
  // 下拉刷新自定义 builder 状态
  @State refreshScaleNum: number = 0;
  @State refreshShowLogo: boolean = true;
  @State refreshMsg: string = '';
  private readonly REFRESH_OFFSET: number = 64;
  private readonly REFRESH_HEADER_HEIGHT: number = 96;
  private readonly LIST_BOTTOM_SPACER: number = 80;
  @State viewportHeight: number = 0;
  private listScroller: Scroller = new Scroller();
  private loadMorePending: boolean = false;
  private restoredScroll: boolean = false;
  @State toolbarOffsetY: number = 0;
  private lastScrollY: number = 0;
  private barHeight: number = 56; // matches EhNavBar body height
  @StorageProp('statusBarHeight') statusBarHeightPx: number = 0;
  
  onScrollReset(): void {
    // scrollResetVersion 变化时滚回顶部
    this.snapListToTop();
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }
  
  private totalBarHeight(): number {
    return this.statusBarVp() + this.barHeight;
  }

  private visibleBarHeight(): number {
    return Math.max(0, this.totalBarHeight() + this.toolbarOffsetY);
  }
  
  private handleScrollMove(yOffset: number): void {
    const delta = yOffset - this.lastScrollY;
    this.lastScrollY = yOffset;
    // Hide toolbar when scrolling down, show when scrolling up or at top
    if (yOffset <= 0) {
      this.toolbarOffsetY = 0;
      return;
    }
    let newOffset = this.toolbarOffsetY - delta;
    newOffset = Math.max(-this.totalBarHeight(), Math.min(0, newOffset));
    this.toolbarOffsetY = newOffset;
  }

  private triggerLoadMoreIfNear(last: number): void {
    if (this.isLoadingMore || this.loadMorePending) {
      return;
    }
    if (this.galleries.length > 0 && last >= this.galleries.length - 12) {
      this.loadMorePending = true;
      this.onLoadMore();
      // Reset local guard after one frame so rapid scroll events don't queue duplicates
      setTimeout(() => { this.loadMorePending = false; }, 500);
    }
  }

  private estimateContentHeight(): number {
    const columns = Math.max(1, this.galleryColumnCount());
    const rows = Math.ceil(this.galleries.length / columns);
    const cardHeight = galleryListMode() === 'Thumb' ? Math.max(0, this.galleryCardWidth() / 0.75 + 54) :
      galleryThumbHeight();
    return 62 + rows * cardHeight + Math.max(0, rows - 1) * this.galleryCardGap() +
      this.galleryContentPadding();
  }

  private triggerLoadMoreByOffset(offset: number): void {
    if (this.viewportHeight <= 0) {
      return;
    }
    const remaining = this.estimateContentHeight() - offset - this.viewportHeight;
    if (remaining <= Math.max(720, this.viewportHeight * 1.3)) {
      this.triggerLoadMoreIfNear(this.galleries.length);
    }
  }


  private contentStartOffset(): number {
    return this.galleryContentPadding();
  }

  private galleryCardPreferredWidth(): number {
    if (galleryListMode() === 'Extended') {
      return 340;
    }
    if (galleryListMode() === 'Detail') {
      return 340;
    }
    const value = galleryThumbWidth();
    if (value <= 70) {
      return 116;
    }
    if (value >= 104) {
      return 164;
    }
    return 136;
  }

  private galleryCardGap(): number {
    return 8;
  }

  private galleryContentPadding(): number {
    return 8;
  }

  private snapListToTop(): void {
    this.listScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.toolbarOffsetY = 0;
    this.lastScrollY = 0;
    this.onScrollUpdate(0);
  }

  private rememberListOffset(yOffset: number): void {
    if (this.refreshing) {
      return;
    }
    this.onScrollUpdate(yOffset);
  }

  private resetRefreshVisual(): void {
    this.refreshShowLogo = true;
    this.refreshMsg = '';
    this.refreshScaleNum = 0;
  }

  private galleryCardWidth(): number {
    const availableWidth = Math.max(0, this.contentWidth - this.galleryContentPadding() * 2);
    if (availableWidth <= 0 || Number.isNaN(availableWidth)) {
      return this.galleryCardPreferredWidth();
    }
    const columns = this.galleryColumnCount();
    const gap = this.galleryCardGap();
    return Math.max(this.galleryCardMinWidth(), Math.floor((availableWidth - gap * (columns - 1)) / columns));
  }

  private galleryColumnCount(): number {
    const availableWidth = Math.max(0, this.contentWidth - this.galleryContentPadding() * 2);
    if (availableWidth <= 0 || Number.isNaN(availableWidth)) {
      return 1;
    }
    const preferred = this.galleryCardPreferredWidth();
    const gap = this.galleryCardGap();
    return Math.max(1, Math.floor((availableWidth + gap) / (preferred + gap)));
  }

  private galleryCardMinWidth(): number {
    if (galleryListMode() === 'Extended') {
      return 300;
    }
    if (galleryListMode() === 'Detail') {
      return 300;
    }
    return 104;
  }

  private updateContentWidth(width: number): void {
    if (width <= 0 || Number.isNaN(width) || this.contentWidth === width) {
      return;
    }
    this.contentWidth = width;
    this.layoutVersion++;
  }


  @Builder
  private customRefreshComponent() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 6 }) {
        Image($r('app.media.app_icon'))
          .width(32)
          .height(32)
          .scale({ x: this.refreshScaleNum, y: this.refreshScaleNum })
          .visibility(this.refreshShowLogo ? Visibility.Visible : Visibility.None)
        LoadingProgress()
          .width(30)
          .height(30)
          .color(APP_THEME_COLOR)
          .visibility(this.refreshShowLogo ? Visibility.None : Visibility.Visible)
        if (this.refreshMsg.length > 0) {
          Text(this.refreshMsg)
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
        }
      }
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height(this.REFRESH_HEADER_HEIGHT)
    .clip(true)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Blank()
          .height(this.visibleBarHeight())
          .width('100%')

        Refresh({ refreshing: $$this.refreshing, builder: this.customRefreshComponent() }) {
          List({ space: 0, scroller: this.listScroller }) {
            // 空状态或画廊列表
            if (this.galleries.length === 0) {
              ListItem() {
                GalleryListStateView({
                  statusText: this.statusText,
                  requestUrl: this.requestUrl,
                  onRefresh: this.onRefresh
                })
                .width('100%')
                .height('100%')
              }
            } else {
              // 画廊卡片按行分组，每行 galleryColumnCount() 张
              ForEach(this.buildRows(), (row: GalleryInfo[], rowIndex: number) => {
                ListItem() {
                  Row() {
                    ForEach(row, (gallery: GalleryInfo, colIndex: number) => {
                      if (galleryListMode() === 'Thumb') {
                        GalleryThumbCard({ gallery: gallery })
                          .width(this.galleryCardWidth())
                          .margin({
                            right: colIndex < row.length - 1 ? this.galleryCardGap() : 0
                          })
                          .onClick(() => { this.onSelectGallery(gallery); })
                      } else {
                        GalleryListRow({ gallery: gallery })
                          .width(this.galleryCardWidth())
                          .margin({
                            right: colIndex < row.length - 1 ? this.galleryCardGap() : 0
                          })
                          .onClick(() => { this.onSelectGallery(gallery); })
                      }
                    }, (gallery: GalleryInfo) => gallery.gid.toString())
                  }
                  .width('100%')
                  .padding({ left: this.galleryContentPadding(), right: this.galleryContentPadding() })
                  .justifyContent(FlexAlign.Start)
                }
                .margin({ bottom: this.galleryCardGap() })
              }, (_row: GalleryInfo[], rowIndex: number) => {
                return this.galleryColumnCount().toString() + ':' + this.layoutVersion.toString() + ':' +
                  this.renderVersion.toString() + ':' + rowIndex.toString();
              })

              // 加载更多指示器
              if (this.isLoadingMore) {
                ListItem() {
                  Row() {
                    LoadingProgress().width(20).height(20).color('#9BB8CB')
                    Text(uiText('Loading...')).fontSize(12).fontColor('#9BB8CB').margin({ left: 6 })
                  }
                  .width('100%')
                  .height(40)
                  .justifyContent(FlexAlign.Center)
                }
              }

              ListItem() {
                Column()
                  .width('100%')
                  .height(this.LIST_BOTTOM_SPACER)
              }
            }
          }
          .contentStartOffset(this.contentStartOffset())
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .width('100%')
          .height('100%')
          .onAppear(() => {
            if (!this.restoredScroll && this.initialScrollOffset > 0) {
              this.restoredScroll = true;
              setTimeout(() => {
                this.listScroller.scrollTo({ xOffset: 0, yOffset: this.initialScrollOffset });
              }, 80);
            }
          })
          .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
            const yOff = normalizeGalleryListScrollOffset(this.listScroller.currentOffset().yOffset);
            this.handleScrollMove(yOff);
            this.rememberListOffset(yOff);
            this.triggerLoadMoreByOffset(yOff);
          })
          .onScrollStop(() => {
            const yOff = normalizeGalleryListScrollOffset(this.listScroller.currentOffset().yOffset);
            this.rememberListOffset(yOff);
            if (this.toolbarOffsetY < -this.totalBarHeight() / 2) {
              this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
                this.toolbarOffsetY = -this.totalBarHeight();
              });
            } else {
              this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
                this.toolbarOffsetY = 0;
              });
            }
          })
          .onReachEnd(() => {
            this.triggerLoadMoreIfNear(this.galleries.length);
          })
        }
        .refreshOffset(this.REFRESH_OFFSET)
        .pullToRefresh(true)
        .onOffsetChange((value: number) => {
          const offset = Math.max(0, value);
          if (this.refreshing) {
            return;
          }
          if (offset <= 0) {
            this.resetRefreshVisual();
          } else if (offset < this.REFRESH_OFFSET) {
            this.refreshShowLogo = true;
            this.refreshMsg = uiText('Pull down to refresh');
            this.refreshScaleNum = offset / this.REFRESH_OFFSET;
          } else {
            this.refreshShowLogo = true;
            this.refreshMsg = uiText('Release to refresh');
            this.refreshScaleNum = Math.max(0.5, this.REFRESH_OFFSET / offset);
          }
        })
        .onStateChange((refreshStatus: RefreshStatus) => {
          if (refreshStatus === RefreshStatus.Refresh) {
            this.refreshShowLogo = false;
            this.refreshMsg = uiText('Refreshing...');
            this.refreshScaleNum = 1;
          } else if (!this.refreshing && (refreshStatus === RefreshStatus.Inactive || refreshStatus === RefreshStatus.Done)) {
            this.resetRefreshVisual();
          }
        })
        .onRefreshing(() => {
          this.refreshShowLogo = false;
          this.refreshMsg = uiText('Refreshing...');
          this.refreshScaleNum = 1;
          this.onRefreshPull(() => {
            this.refreshing = false;
            setTimeout(() => {
              this.resetRefreshVisual();
            }, 120);
          });
        })
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.page_background'))
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.updateContentWidth(newArea.width as number);
        const h = newArea.height as number;
        if (h > 0 && !Number.isNaN(h)) {
          this.viewportHeight = h;
        }
      })
      .backgroundColor($r('app.color.page_background'))

      // FAB 悬浮按钮
      Column() {
        QuickActionColumn({
          expanded: this.actionsExpanded,
          filterActive: this.filterActive,
          canJump: this.canJump,
          canRandom: this.canRandom,
          onToggle: this.onToggleActions,
          onFilter: this.onFilter,
          onJump: this.onJump,
          onRefresh: this.onRefresh,
          onRandom: this.onRandom
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.End)
      .padding({ right: 16, bottom: 24 })
      .hitTestBehavior(HitTestMode.Transparent)

      // 浮动导航栏
      EhNavBar({
        statusBarHeight: this.statusBarVp(),
        title: this.sceneTitle,
        searchMode: this.searchMode(),
        keyword: this.keyword,
        filterActive: this.filterActive,
        translateY: this.toolbarOffsetY,
        onMenu: () => { this.onMenu(); },
        onSearch: () => { this.onSearch(); },
        onKeywordChange: (v: string) => { this.onKeywordChange(v); },
        onRefresh: () => { this.onRefresh(); }
      })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }

  // 把 galleries 按列数分组成行数组
  private buildRows(): GalleryInfo[][] {
    const cols = this.galleryColumnCount();
    const rows: GalleryInfo[][] = [];
    for (let i = 0; i < this.galleries.length; i += cols) {
      rows.push(this.galleries.slice(i, i + cols));
    }
    return rows;
  }

  private searchMode(): boolean {
    return this.listMode === 'Search' || this.listMode === 'Favorites';
  }
}
@Component
export struct GalleryListStateView {
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  onRefresh: () => void = () => {};

  private isLoading(): boolean {
    const lower = this.statusText.toLowerCase();
    return lower.indexOf('loading') >= 0 || lower.indexOf('加载') >= 0;
  }

  private isError(): boolean {
    const lower = this.statusText.toLowerCase();
    return lower.indexOf('failed') >= 0 || lower.indexOf('error') >= 0 ||
      lower.indexOf('blocked') >= 0 || lower.indexOf('banned') >= 0 ||
      lower.indexOf('required') >= 0 || lower.indexOf('失败') >= 0;
  }

  private titleText(): string {
    if (this.isLoading()) {
      return 'Loading...';
    }
    if (this.isError()) {
      return 'Load failed';
    }
    return 'No galleries';
  }

  build() {
    Column() {
      if (this.isLoading()) {
        LoadingProgress()
          .width(48)
          .height(48)
          .color('#2F6F8F')
      } else {
        SymbolGlyph(this.isError() ? $r('sys.symbol.exclamationmark_triangle') : $r('sys.symbol.magnifyingglass'))
          .fontSize(48)
          .fontColor([this.isError() ? '#B42318' : '#8AA4B5'])
      }

      Text(uiText(this.titleText()))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#17202A')
        .margin({ top: 14 })

      if (this.statusText.length > 0) {
        Text(uiStatusText(this.statusText))
          .fontSize(13)
          .fontColor('#667085')
          .lineHeight(20)
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
          .width('82%')
      }

      if (this.requestUrl.length > 0 && this.isError()) {
        Text(this.requestUrl)
          .fontSize(11)
          .fontColor('#98A2B3')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
          .width('82%')
      }

      if (!this.isLoading()) {
        Button(uiText('Refresh'))
          .height(38)
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor('#2F6F8F')
          .margin({ top: 16 })
          .onClick(() => {
            this.onRefresh();
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 24, right: 24, bottom: 48 })
    .backgroundColor('#F3F5F7')
  }
}

@Component
export struct QuickActionColumn {
  @Prop expanded: boolean = false;
  @Prop filterActive: boolean = false;
  @Prop canJump: boolean = false;
  @Prop canRandom: boolean = false;
  onToggle: () => void = () => {};
  onFilter: () => void = () => {};
  onJump: () => void = () => {};
  onRefresh: () => void = () => {};
  onRandom: () => void = () => {};

  build() {
    Column() {
      if (this.expanded) {
        Column({ space: 8 }) {
          ActionBubble({
            label: this.filterActive ? uiText('Filter On') : uiText('Filter'),
            symbolIcon: $r('sys.symbol.magnifyingglass'),
            isEnabled: true,
            onTapAction: () => {
              this.onFilter();
            }
          })
          ActionBubble({
            label: uiText('Jump'),
            symbolIcon: $r('sys.symbol.chevron_forward'),
            isEnabled: this.canJump,
            onTapAction: () => {
              this.onJump();
            }
          })
          ActionBubble({
            label: uiText('Refresh'),
            symbolIcon: $r('sys.symbol.play_arrow_triangle_2_circlepath'),
            isEnabled: true,
            onTapAction: () => {
              this.onRefresh();
            }
          })
          ActionBubble({
            label: uiText('Random'),
            symbolIcon: $r('sys.symbol.play_fill'),
            isEnabled: this.canRandom,
            onTapAction: () => {
              this.onRandom();
            }
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
        onTapAction: () => {
          this.onToggle();
        }
      })
    }
    .alignItems(HorizontalAlign.End)
  }
}

@Component
export struct ActionBubble {
  @Prop label: string = '';
  @Prop symbolIcon: Resource = $r('sys.symbol.plus');
  @Prop isEnabled: boolean = true;
  primary: boolean = false;
  onTapAction: () => void = () => {};

  build() {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph(this.symbolIcon)
          .fontSize(this.primary ? 26 : 20)
          .fontColor([this.isEnabled ? Color.White : '#A0BFCC'])
      }
      .width(this.primary ? 54 : 44)
      .height(this.primary ? 54 : 44)
      .enabled(this.isEnabled)
      .backgroundColor(this.isEnabled ? (this.primary ? '#2F6F8F' : '#5A8FA8') : '#A8C0CC')
      .shadow({ radius: this.primary ? 14 : 8, color: '#33000000', offsetX: 0, offsetY: 3 })
      .onClick(() => {
        this.onTapAction();
      })

      if (!this.primary && this.label.length > 0) {
        Text(this.label)
          .fontSize(10)
          .fontColor('#2F6F8F')
          .textAlign(TextAlign.Center)
          .backgroundColor('#DEEAF2')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .maxLines(1)
      }
    }
    .alignItems(HorizontalAlign.Center)
  }
}

@Component
export struct GalleryListRow {
  gallery: GalleryInfo = createEmptyGallery();

  private cardHeight(): number {
    return galleryThumbHeight();
  }

  private cardGap(): number {
    return 6;
  }

  private metaGap(): number {
    return 2;
  }

  private titleMaxLines(): number {
    return galleryListMode() === 'Extended' ? 2 : 3;
  }

  private hasTags(): boolean {
    return galleryListMode() === 'Extended' && this.previewTags().length > 0;
  }

  private previewTags(): string[] {
    if (this.gallery.simpleTags === undefined) {
      return [];
    }
    const tags: string[] = [];
    for (let i = 0; i < this.gallery.simpleTags.length; i++) {
      const normalized = this.gallery.simpleTags[i].toLowerCase();
      if (normalized.indexOf('language:') !== 0) {
        tags.push(this.gallery.simpleTags[i]);
      }
      if (tags.length >= 6) {
        break;
      }
    }
    return tags;
  }

  private readPageText(): string {
    const readIndex = ehHistoryStore.getReadPage(this.gallery.gid);
    const readPages = readIndex >= 0 ? Math.min(this.gallery.pages, readIndex + 1) : 0;
    return readPages.toString() + '/' + this.gallery.pages.toString() + ' P';
  }

  private languageText(): string {
    if (this.gallery.simpleLanguage !== undefined && this.gallery.simpleLanguage.length > 0) {
      return this.gallery.simpleLanguage;
    }
    return '-';
  }

  private tagColor(index: number): string {
    const colors: string[] = ['#D8EEF7', '#E6E0F4', '#DDEFD9', '#F7E3C7', '#F6DDE7', '#DDE7F5'];
    return colors[index % colors.length];
  }

  private tagTextColor(index: number): string {
    const colors: string[] = ['#205E78', '#594596', '#2F6841', '#8A5A1F', '#8A3858', '#3A567D'];
    return colors[index % colors.length];
  }

  private tagDisplayText(tag: string): string {
    const colon = tag.indexOf(':');
    if (colon >= 0 && colon < tag.length - 1) {
      return tag.substring(colon + 1);
    }
    return tag;
  }

  build() {
    Row() {
      GalleryThumb({
        url: this.gallery.thumb === undefined ? '' : this.gallery.thumb,
        widthValue: galleryThumbWidth(),
        heightValue: this.cardHeight(),
        radiusValue: 6
      })
        .height('100%')

      Column() {
        Column() {
          Text(galleryDisplayTitle(this.gallery))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#17202A')
            .maxLines(this.titleMaxLines())
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Text(this.gallery.uploader === undefined || this.gallery.uploader.length === 0 ? uiText('unknown uploader') :
            this.gallery.uploader)
            .fontSize(12)
            .fontColor('#667085')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 3 })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row() {
          Column() {
            Row() {
              Text(this.languageText())
                .fontSize(13)
                .fontColor('#40566F')
                .fontWeight(FontWeight.Medium)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (showGalleryPages()) {
                Text(this.readPageText())
                  .fontSize(13)
                  .fontColor('#40566F')
                  .fontWeight(FontWeight.Medium)
                  .margin({ left: 8 })
              }
            }
            .width('100%')

            Text(this.gallery.posted === undefined ? '' : this.gallery.posted)
              .fontSize(13)
              .fontColor('#98A2B3')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: this.metaGap() })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column() {
            Rating({ rating: this.gallery.rating, indicator: true })
              .stars(5)
              .stepSize(0.5)
              .height(14)
              .width(74)
            CategoryBadge({ category: this.gallery.category })
              .margin({ top: 1 })
          }
          .alignItems(HorizontalAlign.End)
          .margin({ left: 8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
        .margin({ top: this.metaGap() })

        if (this.hasTags()) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.previewTags(), (tag: string, index: number) => {
              GalleryTagChip({
                text: this.tagDisplayText(tag),
                backgroundColorValue: this.tagColor(index),
                color: this.tagTextColor(index)
              })
                .margin({ right: 4 })
            }, (tag: string, index: number) => tag + ':' + index.toString())
          }
          .width('100%')
          .height(21)
          .clip(true)
          .margin({ top: this.metaGap() })
        }
      }
      .height('100%')
      .layoutWeight(1)
      .padding({ left: 10, right: 8, top: this.cardGap(), bottom: this.cardGap() })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(this.cardHeight())
      .backgroundColor(Color.White)
      .borderRadius(6)
      .clip(true)
  }
}

@Component
export struct GalleryTagChip {
  text: string = '';
  backgroundColorValue: string = '#D8EEF7';
  color: string = '#205E78';

  build() {
    Text(this.text)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.color)
      .height(21)
      .padding({ left: 7, right: 7 })
      .backgroundColor(this.backgroundColorValue)
      .borderRadius(3)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }
}

@Component
export struct GalleryThumb {
  url: string = '';
  widthValue: number = 86;
  heightValue: number = 118;
  radiusValue: number = 4;

  @State localUrl: string = '';
  @State loadFailed: boolean = false;

  aboutToAppear(): void {
    if (this.url.length > 0) {
      this.cacheThumb();
    } else {
      this.loadFailed = true;
    }
  }

  private cacheThumb(): void {
    cacheThumbnailImage(this.url, (path: string) => {
      this.localUrl = readerLocalImageSource(path);
    });
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#E7ECF1')
        .borderRadius(this.radiusValue)

      if (this.loadFailed) {
        Column({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(22)
            .fontColor(['#9BB8CB'])
          Text('EH')
            .fontSize(10)
            .fontColor('#9BB8CB')
        }
        .justifyContent(FlexAlign.Center)
      } else if (this.localUrl.length > 0) {
        Image(this.localUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(this.radiusValue)
          .onError(() => {
            this.loadFailed = true;
          })
      } else {
        LoadingProgress()
          .width(32)
          .height(32)
          .color('#9BB8CB')
      }
    }
    .width(this.widthValue > 0 ? this.widthValue : '100%')
    .height(this.heightValue > 0 ? this.heightValue : '100%')
  }
}

@Component
export struct GalleryThumbCard {
  gallery: GalleryInfo = createEmptyGallery();

  build() {
    Column() {
      // 3:4 portrait ratio image area that fills column width
      GalleryThumb({
        url: this.gallery.thumb === undefined ? '' : this.gallery.thumb,
        widthValue: 0,
        heightValue: 0
      })
        .width('100%')
        .aspectRatio(0.75)

      Column() {
        Text(galleryDisplayTitle(this.gallery))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#17202A')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row() {
          CategoryBadge({ category: this.gallery.category })
          Blank()
          Text(this.gallery.pages.toString() + 'p')
            .fontSize(11)
            .fontColor('#98A2B3')
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
      .alignItems(HorizontalAlign.Start)
    }
    .backgroundColor(Color.White)
    .borderRadius(6)
    .clip(true)
  }
}

@Component
export struct CategoryBadge {
  category: number = GalleryCategory.Unknown;

  build() {
    Text(categoryName(this.category))
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .height(21)
      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      .backgroundColor(categoryColor(this.category))
      .borderRadius(3)
  }
}

@Component
export struct GalleryDetailScene {
  @Prop renderVersion: number = 0;
  @Prop detail: GalleryDetail = createEmptyDetail();
  @Prop isFavorited: boolean = false;
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  @Prop downloadText: string = 'Download';
  onBack: () => void = () => {};
  onDownload: () => void = () => {};
  onRead: () => void = () => {};
  onSelectPreview: (preview: GalleryPreview) => void = () => {};
  onComments: () => void = () => {};
  onFavorite: () => void = () => {};
  onShare: () => void = () => {};
  initialDetailScrollOffset: number = 0;
  onDetailScrollUpdate: (offset: number) => void = () => {};
  private detailScroller: Scroller = new Scroller();
  private client: EhHttpClient = new EhHttpClient();
  @State showRatingDialog: boolean = false;
  @State pendingRating: number = 0;

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(36)
        .height(36)
        .backgroundColor('#2F6F8F')
        .onClick(() => {
          this.onBack();
        })
        Text(galleryDisplayTitle(this.detail))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#17202A')
          .margin({ left: 12 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 8 })

      if (this.statusText.length > 0) {
        Text(uiStatusText(this.statusText))
          .fontSize(12)
          .fontColor('#0A6B45')
          .width('100%')
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor('#F0FBF6')
      }

      List({ space: 0, scroller: this.detailScroller }) {
        ListItem() {
          DetailHeader({
            detail: this.detail,
            downloadText: this.downloadText,
            onDownload: this.onDownload,
            onRead: this.onRead
          })
        }
        ListItem() {
          DetailInfoBlock({ detail: this.detail, requestUrl: this.requestUrl })
        }
        ListItem() {
          DetailActions({
            detail: this.detail,
            isFavorited: this.isFavorited,
            onFavorite: this.onFavorite,
            onShare: this.onShare,
            onTorrent: () => {},
            onArchive: () => {}
          })
        }
        ListItem() {
          DetailTags({ tags: this.detail.tags })
        }
        ListItem() {
          DetailPreviews({
            previews: this.detail.previewSet,
            previewPages: this.detail.previewPages,
            onSelectPreview: this.onSelectPreview
          })
        }
        ListItem() {
          DetailComments({
            comments: this.detail.comments,
            onComments: this.onComments
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .onAppear(() => {
        if (this.initialDetailScrollOffset > 0) {
          this.detailScroller.scrollTo({ xOffset: 0, yOffset: this.initialDetailScrollOffset });
        }
      })
      .onScrollStop(() => {
        this.onDetailScrollUpdate(this.detailScroller.currentOffset().yOffset);
      })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct DetailHeader {
  @Prop detail: GalleryDetail = createEmptyDetail();
  @Prop downloadText: string = 'Download';
  onDownload: () => void = () => {};
  onRead: () => void = () => {};

  build() {
    Column() {
      Row() {
        GalleryThumb({
          url: this.detail.thumb === undefined ? '' : this.detail.thumb,
          widthValue: galleryThumbWidth(),
          heightValue: galleryThumbHeight()
        })
        Column() {
          Text(galleryDisplayTitle(this.detail))
            .fontSize(detailTitleFontSize())
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .maxLines(detailTitleMaxLines())
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.detail.uploader === undefined || this.detail.uploader.length === 0 ? uiText('unknown uploader') :
            this.detail.uploader)
            .fontSize(12)
            .fontColor('#DDE7F2')
            .margin({ top: 8 })
          CategoryBadge({ category: this.detail.category })
            .margin({ top: 12 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 14 })
      }
      .width('100%')

      Row() {
        HeaderActionButton({
          symbolIcon: this.downloadText === 'Queued' ? $r('sys.symbol.checkmark') : $r('sys.symbol.save'),
          text: uiText(this.downloadText),
          onTap: this.onDownload
        })
          .layoutWeight(1)
        Column()
          .width(1)
          .height(32)
          .backgroundColor('#5E8EA5')
        HeaderActionButton({
          symbolIcon: $r('sys.symbol.play_fill'),
          text: uiText('Read'),
          accent: true,
          onTap: this.onRead
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .margin({ top: 16 })
      .padding(4)
      .backgroundColor('#225A73')
      .borderRadius(6)
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#2F6F8F')
  }
}

@Component
export struct HeaderActionButton {
  symbolIcon: Resource = $r('sys.symbol.play_fill');
  text: string = '';
  accent: boolean = false;
  onTap: () => void = () => {};

  build() {
    Row() {
      SymbolGlyph(this.symbolIcon)
        .fontSize(22)
        .fontColor([this.accent ? '#17202A' : Color.White])
      Text(this.text)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accent ? '#17202A' : Color.White)
        .margin({ left: 10 })
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .height(48)
    .width('100%')
    .backgroundColor(this.accent ? '#F7C948' : '#2B6B87')
    .borderRadius(4)
    .onClick(() => {
      this.onTap();
    })
  }
}

@Component
export struct DetailInfoBlock {
  @Prop detail: GalleryDetail = createEmptyDetail();
  @Prop requestUrl: string = '';

  build() {
    Column() {
      Text(uiText('Information'))
        .fontSize(detailHeadingFontSize())
        .fontWeight(FontWeight.Medium)
        .fontColor('#17202A')
        .width('100%')
      InfoRow({ label: uiText('Posted'), value: this.detail.posted === undefined ? '' : this.detail.posted })
      InfoRow({ label: uiText('Parent'), value: this.detail.parent })
      InfoRow({ label: uiText('Visible'), value: this.detail.visible })
      InfoRow({ label: uiText('Language'), value: this.detail.language })
      InfoRow({ label: uiText('File Size'), value: this.detail.size })
      InfoRow({ label: uiText('Length'), value: this.detail.pages.toString() + (shouldUseChineseUi() ? ' 页' : ' pages') })
      InfoRow({ label: uiText('Rating'), value: ratingText(this.detail.rating) + ' / ' + this.detail.ratingCount.toString() })
      InfoRow({ label: uiText('Favorited'), value: this.detail.favoriteCount.toString() })
      if (this.requestUrl.length > 0) {
        InfoRow({ label: 'URL', value: this.requestUrl })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
  }
}

@Component
export struct InfoRow {
  @Prop label: string = '';
  @Prop value: string = '';

  build() {
    Row() {
      Text(this.label)
        .fontSize(12)
        .fontColor('#667085')
        .width(86)
      Text(this.value.length === 0 ? '-' : this.value)
        .fontSize(12)
        .fontColor('#17202A')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 8 })
  }
}

@Component
export struct DetailActions {
  @Prop detail: GalleryDetail = createEmptyDetail();
  @Prop isFavorited: boolean = false;
  onFavorite: () => void = () => {};
  onShare: () => void = () => {};
  onTorrent: () => void = () => {};
  onArchive: () => void = () => {};

  build() {
    Scroll() {
      Row() {
        DetailActionItem({
          symbolIcon: $r('sys.symbol.heart'),
          label: this.isFavorited ? uiText('Favorited') : uiText('Favorite'),
          isActive: this.detail.gid > 0,
          isFilled: this.isFavorited,
          onTap: this.onFavorite
        })
        DetailActionItem({
          symbolIcon: $r('sys.symbol.share'),
          label: uiText('Share'),
          isActive: this.detail.gid > 0,
          onTap: this.onShare
        })
        DetailActionItem({
          symbolIcon: $r('sys.symbol.save'),
          label: this.detail.torrentCount > 0 ?
            'Torrent (' + this.detail.torrentCount.toString() + ')' : 'Torrent',
          isActive: this.detail.torrentCount > 0 && this.detail.torrentUrl.length > 0,
          onTap: this.onTorrent
        })
        DetailActionItem({
          symbolIcon: $r('sys.symbol.doc_plaintext'),
          label: uiText('Archive'),
          isActive: this.detail.archiveUrl.length > 0,
          onTap: this.onArchive
        })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .backgroundColor(Color.White)
  }
}
@Component
export struct DetailActionItem {
  symbolIcon: Resource = $r('sys.symbol.heart');
  label: string = '';
  isActive: boolean = true;
  isFilled: boolean = false;
  onTap: () => void = () => {};

  build() {
    Column({ space: 6 }) {
      SymbolGlyph(this.symbolIcon)
        .fontSize(26)
        .fontColor([this.isActive ? (this.isFilled ? '#E05C4B' : '#2F6F8F') : '#B8CDD8'])
      Text(this.label)
        .fontSize(11)
        .fontColor(this.isActive ? '#2F6F8F' : '#B8CDD8')
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(72)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.isActive) {
        this.onTap();
      }
    })
  }
}

@Component
export struct DetailTags {
  @Prop tags: GalleryTagGroup[] = [];

  build() {
    Column() {
      Text(uiText('Tags'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#17202A')
        .width('100%')
      if (this.tags.length === 0) {
        Text(uiText('No tags parsed'))
          .fontSize(12)
          .fontColor('#667085')
          .margin({ top: 8 })
      } else {
        ForEach(this.tags, (group: GalleryTagGroup) => {
          TagGroupRow({ namespace: group.namespace, tags: group.tags })
        }, (group: GalleryTagGroup) => group.namespace)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
  }
}

@Component
export struct TagGroupRow {
  namespace: string = '';
  tags: string[] = [];

  build() {
    Row() {
      Text(this.namespace)
        .fontSize(12)
        .fontColor('#40566F')
        .width(86)
      Text(this.tags.join(', '))
        .fontSize(12)
        .fontColor('#667085')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 8 })
  }
}

@Component
export struct DetailPreviews {
  @Prop previews: GalleryPreview[] = [];
  @Prop previewPages: number = 0;
  onSelectPreview: (preview: GalleryPreview) => void = () => {};

  build() {
    Column() {
      Text(uiText('Previews'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#17202A')
        .width('100%')
      Text(shouldUseChineseUi() ? this.previews.length.toString() + ' 个缩略图 / ' + this.previewPages.toString() + ' 页' :
        this.previews.length.toString() + ' thumbnails / ' + this.previewPages.toString() + ' pages')
        .fontSize(12)
        .fontColor('#667085')
        .width('100%')
        .margin({ top: 6, bottom: 8 })
      ForEach(this.previews.slice(0, 12), (preview: GalleryPreview) => {
        PreviewRow({
          preview: preview,
          onSelectPreview: (selected: GalleryPreview) => {
            this.onSelectPreview(selected);
          }
        })
      }, (preview: GalleryPreview) => preview.index.toString())
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
  }
}

@Component
export struct PreviewRow {
  preview: GalleryPreview = createEmptyPreview();
  onSelectPreview: (preview: GalleryPreview) => void = () => {};

  build() {
    Row() {
      GalleryThumb({
        url: this.preview.imageUrl,
        widthValue: 74,
        heightValue: 54
      })
      Column() {
        Text(uiText('Page') + ' ' + (this.preview.index + 1).toString())
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#17202A')
        Text(this.preview.pageUrl)
          .fontSize(11)
          .fontColor('#667085')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 5 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .margin({ top: 8 })
    .onClick(() => {
      this.onSelectPreview(this.preview);
    })
  }
}

function stripHtml(html: string): string {
  let text = html
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/<\/div>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
  return text;
}

@Component
export struct DetailComments {
  @Prop comments: GalleryComment[] = [];
  onComments: () => void = () => {};

  build() {
    Column() {
      Row() {
        Text(uiText('Comments'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#17202A')
          .layoutWeight(1)
        if (this.comments.length > 0) {
          Text(uiText('See all') + ' (' + this.comments.length.toString() + ')')
            .fontSize(13)
            .fontColor('#2F6F8F')
            .onClick(() => {
              this.onComments();
            })
        } else {
          Text('0 ' + uiText('comments'))
            .fontSize(13)
            .fontColor('#667085')
        }
      }
      .width('100%')
      .margin({ bottom: 10 })

      if (this.comments.length === 0) {
        Text(uiText('No comments'))
          .fontSize(13)
          .fontColor('#667085')
      } else {
        ForEach(this.comments.slice(0, 3), (comment: GalleryComment) => {
          Column() {
            Row() {
              Text(comment.user.length > 0 ? comment.user : uiText('Anonymous'))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#17202A')
                .layoutWeight(1)
              Text(comment.posted)
                .fontSize(11)
                .fontColor('#667085')
            }
            .width('100%')
            .margin({ bottom: 4 })

            Text(stripHtml(comment.content))
              .fontSize(13)
              .fontColor('#333333')
              .maxLines(4)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(10)
          .margin({ bottom: 6 })
          .backgroundColor('#F5F8FA')
          .borderRadius(6)
        }, (comment: GalleryComment) => comment.id)

        if (this.comments.length > 3) {
          Text(uiText('View all') + ' ' + this.comments.length.toString() + ' ' + uiText('comments') + ' →')
            .fontSize(13)
            .fontColor('#2F6F8F')
            .margin({ top: 6 })
            .onClick(() => {
              this.onComments();
            })
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
  }
}

@Component
export struct CommentsScene {
  @Prop renderVersion: number = 0;
  @Prop comments: GalleryComment[] = [];
  @Prop galleryTitle: string = '';
  onBack: () => void = () => {};

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(36)
        .height(36)
        .backgroundColor('#2F6F8F')
        .onClick(() => {
          this.onBack();
        })
        Column() {
          Text(uiText('Comments'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#17202A')
          Text(this.galleryTitle)
            .fontSize(11)
            .fontColor('#667085')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })

        Text(this.comments.length.toString() + ' ' + uiText('total'))
          .fontSize(12)
          .fontColor('#667085')
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 8 })
      .backgroundColor(Color.White)

      if (this.comments.length === 0) {
        PlaceholderScene({
          title: 'Comments',
          detail: 'No comments for this gallery.'
        })
      } else {
        List({ space: 0 }) {
          ForEach(this.comments, (comment: GalleryComment) => {
            ListItem() {
              Column() {
                Row() {
                  Text(comment.user.length > 0 ? comment.user : uiText('Anonymous'))
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#17202A')
                    .layoutWeight(1)
                  if (comment.score !== 0) {
                    Text((comment.score > 0 ? '+' : '') + comment.score.toString())
                      .fontSize(12)
                      .fontColor(comment.score > 0 ? '#0A6B45' : '#B03060')
                      .margin({ left: 8 })
                  }
                }
                .width('100%')
                .margin({ bottom: 4 })

                Text(comment.posted)
                  .fontSize(11)
                  .fontColor('#667085')
                  .margin({ bottom: 8 })

                Text(stripHtml(comment.content))
                  .fontSize(14)
                  .fontColor('#17202A')
                  .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .backgroundColor(Color.White)
            }
          }, (comment: GalleryComment) => comment.id)
          ListItem() {
            Divider()
              .height(1)
              .color('#F0F0F0')
          }
        }
        .divider({ strokeWidth: 1, color: '#F0F0F0' })
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}

@Component
export struct ReaderScene {
  @Prop renderVersion: number = 0;
  @Prop page: GalleryPage = createEmptyPage();
  @Prop statusText: string = '';
  @Prop pageIndex: number = 0;
  @Prop totalPages: number = 0;
  onBack: () => void = () => {};
  onPrev: () => void = () => {};
  onNext: () => void = () => {};
  onJump: (index: number) => void = () => {};
  onRetry: () => void = () => {};

  @State zoomPercent: number = 100;
  @State fitMode: string = 'Fit width';
  @State showInfo: boolean = false;
  @State preferOriginal: boolean = false;
  @State controlsVisible: boolean = false;

  aboutToAppear(): void {
    this.fitMode = ehSettingsStore.getValue('page_scaling', 'Fit width');
    this.controlsVisible = false;
    this.applyReaderWindowSettings();
  }

  aboutToDisappear(): void {
    this.restoreWindowSettings();
  }

  private restoreWindowSettings(): void {
    const win = AppStorage.get<window.Window>('mainWindow');
    if (win === undefined) {
      return;
    }
    try {
      win.setWindowKeepScreenOn(false).catch(() => {});
    } catch (e) {}
    try {
      win.setPreferredOrientation(window.Orientation.UNSPECIFIED).catch(() => {});
    } catch (e) {}
  }

  private applyReaderWindowSettings(): void {
    const keepOn = ehSettingsStore.getValue('keep_screen_on', 'Off') === 'On';
    const orientation = ehSettingsStore.getValue('screen_rotation', 'System');
    const win = AppStorage.get<window.Window>('mainWindow');
    if (win !== undefined) {
      try {
        win.setWindowKeepScreenOn(keepOn).catch(() => {});
      } catch (e) {}
      try {
        let o: window.Orientation = window.Orientation.UNSPECIFIED;
        if (orientation === 'Portrait') {
          o = window.Orientation.PORTRAIT;
        } else if (orientation === 'Landscape') {
          o = window.Orientation.LANDSCAPE;
        }
        win.setPreferredOrientation(o).catch(() => {});
      } catch (e) {}
    }
  }

  private zoomOut(): void {
    this.zoomPercent = Math.max(50, this.zoomPercent - 25);
  }

  private zoomIn(): void {
    this.zoomPercent = Math.min(300, this.zoomPercent + 25);
  }

  private resetZoom(): void {
    this.zoomPercent = 100;
  }

  private cycleFitMode(): void {
    const next = nextOption(this.fitMode, ['Fit width', 'Fit height', 'Original', 'Smart fit']);
    this.fitMode = next;
    ehSettingsStore.setValue('page_scaling', next);
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch(() => {});
    }
  }

  private tapLeftPageArea(): void {
    if (readerIsRightToLeft()) {
      if (this.totalPages <= 0 || this.pageIndex + 1 < this.totalPages) {
        this.onNext();
      }
      return;
    }

    if (this.pageIndex > 0) {
      this.onPrev();
    }
  }

  private tapRightPageArea(): void {
    if (readerIsRightToLeft()) {
      if (this.pageIndex > 0) {
        this.onPrev();
      }
      return;
    }

    if (this.totalPages <= 0 || this.pageIndex + 1 < this.totalPages) {
      this.onNext();
    }
  }

  private toggleControls(): void {
    this.controlsVisible = !this.controlsVisible;
  }

  private jumpTo(value: number): void {
    if (this.totalPages <= 0) {
      return;
    }
    const target = Math.max(0, Math.min(this.totalPages - 1, Math.round(value)));
    if (target !== this.pageIndex) {
      this.onJump(target);
    }
  }

  private progressText(): string {
    const total = this.totalPages <= 0 ? 1 : this.totalPages;
    return (this.pageIndex + 1).toString() + '/' + total.toString();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        Stack({ alignContent: Alignment.Center }) {
          if (readerDisplayImageUrl(this.page, this.preferOriginal).length > 0) {
            Image(readerDisplayImageUrl(this.page, this.preferOriginal))
              .width(readerFullImageWidth(this.zoomPercent))
              .height(readerFullImageHeight(this.zoomPercent))
              .objectFit(readerImageFit(this.fitMode))
              .backgroundColor('#050608')
          } else {
            Text(this.statusText.indexOf('failed') >= 0 || this.statusText.indexOf('Failed') >= 0 ?
              uiText('Image page failed to load') : uiText('Image page is loading'))
              .fontSize(16)
              .fontColor('#98A2B3')
          }

          Row() {
            Column() {
              Blank()
            }
            .height('100%')
            .layoutWeight(1)
            .onClick(() => {
              this.tapLeftPageArea();
            })

            Column() {
              Blank()
            }
            .height('100%')
            .layoutWeight(1)
            .onClick(() => {
              this.toggleControls();
            })

            Column() {
              Blank()
            }
            .height('100%')
            .layoutWeight(1)
            .onClick(() => {
              this.tapRightPageArea();
            })
          }
          .width('100%')
          .height('100%')

          if (!this.controlsVisible && readerShowProgress()) {
            Text(this.progressText())
              .fontSize(12)
              .fontColor('#F2F4F7')
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor('#66000000')
              .borderRadius(12)
              .position({ x: 12, y: 12 })
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#050608')
      }
      .width('100%')
      .height('100%')

      if (this.controlsVisible) {
        Column() {
          Row() {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(20)
                .fontColor([Color.White])
            }
            .width(36)
            .height(36)
            .backgroundColor('#CC111827')
            .onClick(() => {
              this.onBack();
            })
            Text(uiStatusText(this.statusText))
              .fontSize(12)
              .fontColor('#E5E7EB')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 10 })
              .layoutWeight(1)
            if (readerShowClock()) {
              Text(readerClockText())
                .fontSize(12)
                .fontColor('#E5E7EB')
                .margin({ left: 8 })
            }
            if (readerShowProgress()) {
              Text(this.progressText())
                .fontSize(12)
                .fontColor('#E5E7EB')
                .margin({ left: 8 })
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 10 })
          .backgroundColor('#99000000')

          Blank()
            .layoutWeight(1)

          if (this.showInfo) {
            Column() {
              InfoRow({ label: uiText('Page URL'), value: this.page.pageUrl })
              InfoRow({ label: uiText('Image URL'), value: this.page.imageUrl })
              InfoRow({ label: uiText('Original'), value: this.page.originImageUrl })
              InfoRow({ label: uiText('Show Key'), value: this.page.showKey })
              InfoRow({ label: uiText('Retry Key'), value: this.page.skipHathKey })
              InfoRow({ label: uiText('Fit'), value: uiValue(this.fitMode) + ', zoom ' + this.zoomPercent.toString() + '%' })
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#EEFFFFFF')
          }

          Column() {
            Row() {
              Text((this.pageIndex + 1).toString())
                .fontSize(12)
                .fontColor('#E5E7EB')
                .width(42)
              Slider({
                value: this.pageIndex,
                min: 0,
                max: Math.max(0, this.totalPages - 1),
                step: 1
              })
                .layoutWeight(1)
                .enabled(this.totalPages > 1)
                .onChange((value: number, mode: SliderChangeMode) => {
                  if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                    this.jumpTo(value);
                  }
                })
              Text((this.totalPages <= 0 ? 1 : this.totalPages).toString())
                .fontSize(12)
                .fontColor('#E5E7EB')
                .textAlign(TextAlign.End)
                .width(42)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Row({ space: 8 }) {
              ReaderNavButton({
                text: uiText('Previous'),
                active: this.pageIndex > 0,
                onTap: this.onPrev
              })
                .layoutWeight(1)
              ReaderNavButton({
                text: uiText('Next'),
                active: this.totalPages <= 0 || this.pageIndex + 1 < this.totalPages,
                onTap: this.onNext
              })
                .layoutWeight(1)
            }
            .width('100%')
            .margin({ top: 10 })

            Row({ space: 8 }) {
              ReaderToolButton({
                text: '-',
                active: this.zoomPercent > 50,
                onTap: () => {
                  this.zoomOut();
                }
              })
              ReaderToolButton({
                text: this.zoomPercent.toString() + '%',
                active: true,
                onTap: () => {
                  this.resetZoom();
                }
              })
              ReaderToolButton({
                text: '+',
                active: this.zoomPercent < 300,
                onTap: () => {
                  this.zoomIn();
                }
              })
              ReaderToolButton({
                text: uiValue(this.fitMode),
                active: true,
                onTap: () => {
                  this.cycleFitMode();
                }
              })
              ReaderToolButton({
                text: this.preferOriginal ? uiText('Original') : uiText('Resampled'),
                active: this.page.originImageUrl.length > 0,
                onTap: () => {
                  this.preferOriginal = !this.preferOriginal;
                }
              })
              ReaderToolButton({
                text: uiText('Info'),
                active: true,
                onTap: () => {
                  this.showInfo = !this.showInfo;
                }
              })
              ReaderToolButton({
                text: uiText('Retry'),
                active: this.page.pageUrl.length > 0,
                onTap: this.onRetry
              })
            }
            .width('100%')
            .margin({ top: 10 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 14 })
          .backgroundColor('#CC111827')
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#050608')
  }
}

@Component
export struct ReaderToolButton {
  text: string = '';
  active: boolean = true;
  onTap: () => void = () => {};

  build() {
    Button(this.text)
      .height(32)
      .fontSize(12)
      .fontColor(this.active ? Color.White : '#6B7280')
      .backgroundColor(this.active ? '#334155' : '#1F2937')
      .enabled(this.active)
      .onClick(() => {
        if (this.active) {
          this.onTap();
        }
      })
  }
}

@Component
export struct ReaderNavButton {
  text: string = '';
  active: boolean = true;
  onTap: () => void = () => {};

  build() {
    Row() {
      Text(this.text)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.active ? Color.White : '#98A2B3')
    }
    .justifyContent(FlexAlign.Center)
    .height(42)
    .width('100%')
    .backgroundColor(this.active ? '#2F6F8F' : '#1F2937')
    .borderRadius(4)
    .onClick(() => {
      if (this.active) {
        this.onTap();
      }
    })
  }
}

@Component
export struct PlaceholderScene {
  title: string = '';
  detail: string = '';

  build() {
    Column() {
      Text(this.title)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#17202A')
      Text(this.detail)
        .fontSize(14)
        .fontColor('#667085')
        .lineHeight(22)
        .textAlign(TextAlign.Center)
        .margin({ top: 10 })
        .width('80%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }
}
