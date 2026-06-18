import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { ALL_CATEGORY, GalleryCategory, GalleryDetail, GalleryInfo, GalleryPage, GalleryPreview, GalleryRoute, GallerySite } from '../model/GalleryModels';
import { ehCookieStore } from '../services/EhCookieStore';
import { EhHttpClient, GalleryDetailLoadResult, GalleryListLoadResult, GalleryPageLoadResult, RateGalleryResult, ToggleFavoriteResult } from '../services/EhHttpClient';
import { DEFAULT_ADVANCE_SEARCH, EhUrl, FavListUrlBuilder, ListMode, ListUrlBuilder } from '../services/EhUrl';
import { galleryPageCache } from '../services/GalleryPageCache';
import { ehFilterStore } from '../services/EhFilterStore';
import { DetailPreviewPager, mergeGalleryPreviewSets, seedPreviewMap } from '../services/GalleryPreviewLoader';
import { createReaderSessionState, readerSessionStore } from '../services/ReaderSessionStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { LANGUAGE_REVISION_KEY, APP_THEME_COLOR } from '../shared/EhShared';
import { EhNavBar } from '../components/NavigationComponents';
import { CategoryBadge, GalleryListRow, GalleryThumb, GalleryThumbCard } from './GalleryCards';
import { GalleryDetailOverlayScene, GalleryDetailScene } from './GalleryDetailScenes';
import { QuickActionColumn, SearchAdvancedPanel, recordSearchHistory } from './GallerySearchScenes';
import { CommentsScene, PlaceholderScene, ReaderScene } from './ReaderScenes';
import { uiText, uiStatusText, setActiveBackHandler, createEmptyGallery, createDetailFromGallery, createEmptyDetail, createEmptyPage, cloneGalleryInfos, applyGalleryFilters, cloneGalleryPreviews, cloneGalleryDetail, cloneGalleryPage, createReaderLoadingPage, getAbilityContext, saveGalleryToHistory, saveGalleryReadPosition, readerStartIndex, downloadButtonText, toggleGalleryDownload, listModeForRoute, routeUsesKeyword, defaultKeywordForRoute, gallerySearchTitle, effectiveListSite, galleryListFailureMessage, readerPageReferer, cacheReaderImageForPage, readerPreloadCount, galleryDisplayTitle, galleryListMode, galleryThumbWidth, galleryThumbHeight } from '../shared/EhShared';

export { CategoryBadge, GalleryListRow, GalleryTagChip, GalleryThumb, GalleryThumbCard } from './GalleryCards';
export { GalleryDetailOverlayScene, GalleryDetailScene } from './GalleryDetailScenes';
export { ActionBubble, GallerySearchScene, QuickActionColumn, SearchAdvancedPanel, SearchFlagChip, SearchStatusChip, SearchSuggestionList, SearchSummaryStrip } from './GallerySearchScenes';
export { CommentsScene, PlaceholderScene, ReaderNavButton, ReaderScene, ReaderToolButton } from './ReaderScenes';

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
  searchMode: ListMode;
  searchCategory: number;
  advancedSearchEnabled: boolean;
  advanceSearch: number;
  minRating: number;
  pageFrom: number;
  pageTo: number;
  listScrollOffset: number;
}

interface SearchResultDraft {
  keyword: string;
  mode: ListMode;
  category: number;
  advancedEnabled: boolean;
  advanceSearch: number;
  minRating: number;
  pageFrom: number;
  pageTo: number;
}

const galleryListSceneCache: Map<string, GalleryListSceneCache> = new Map();

function createEmptySearchResultDraft(): SearchResultDraft {
  return {
    keyword: '',
    mode: ListMode.Normal,
    category: GalleryCategory.None,
    advancedEnabled: false,
    advanceSearch: DEFAULT_ADVANCE_SEARCH,
    minRating: -1,
    pageFrom: -1,
    pageTo: -1
  };
}

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

function mergeLoadedGalleryDetail(loaded: GalleryDetail, previous: GalleryDetail): GalleryDetail {
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
  initialSearchMode: ListMode = ListMode.Normal;
  initialSearchCategory: number = GalleryCategory.None;
  initialAdvancedSearchEnabled: boolean = false;
  initialAdvanceSearch: number = DEFAULT_ADVANCE_SEARCH;
  initialMinRating: number = -1;
  initialPageFrom: number = -1;
  initialPageTo: number = -1;
  isSearchResultScene: boolean = false;
  useForcedMode: boolean = false;
  forcedMode: ListMode = ListMode.Normal;
  onMenu: () => void = () => {};
  onBack: () => void = () => {};

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
  @State showSearchResultScene: boolean = false;
  @State searchResultDraft: SearchResultDraft = createEmptySearchResultDraft();
  @State searchMode: ListMode = ListMode.Normal;
  @State searchCategory: number = GalleryCategory.None;
  @State advancedSearchEnabled: boolean = false;
  @State advanceSearch: number = DEFAULT_ADVANCE_SEARCH;
  @State minRating: number = -1;
  @State pageFrom: number = -1;
  @State pageTo: number = -1;
  @State showDetail: boolean = false;
  @State showReader: boolean = false;
  @State showComments: boolean = false;
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = 'Tap a gallery row to load detail';
  @State detailRequestUrl: string = '';
  @State detailDownloadText: string = 'Download';
  @State detailLoaded: boolean = false;
  @State optimisticFavorite: boolean = false;
  @State favoriteBusy: boolean = false;
  @State readerStatus: string = 'Reader is ready';
  @State readerPage: GalleryPage = createEmptyPage();
  @State readerPreviewIndex: number = 0;
  @State renderVersion: number = 0;
  @State isLoadingMore: boolean = false;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  private listScrollOffset: number = 0;
  private detailScrollOffset: number = 0;
  private readerPreviewMap: Map<number, GalleryPreview> = new Map();
  private readerPreviewPageRequests: Map<number, Promise<GalleryPreview | null>> = new Map();
  private readerPreviewPageSize: number = 0;
  private detailPreviewPager: DetailPreviewPager = new DetailPreviewPager();

  private cacheKey(): string {
    const mode = this.useForcedMode ? this.forcedMode.toString() : listModeForRoute(this.sourceRoute).toString();
    if (this.isSearchResultScene) {
      return this.sourceRoute.toString() + '|search-result|' + this.keyword + '|' + this.searchMode.toString() + '|' +
        this.searchCategory.toString() + '|' + (this.advancedSearchEnabled ? '1' : '0') + '|' +
        this.advanceSearch.toString() + '|' + this.minRating.toString();
    }
    return this.sourceRoute.toString() + '|' + mode + '|' + this.follow + '|' + this.initialKeyword + '|' +
      this.initialSearchMode.toString() + '|' + this.initialSearchCategory.toString() + '|' +
      (this.initialAdvancedSearchEnabled ? '1' : '0') + '|' + this.initialAdvanceSearch.toString() + '|' +
      this.initialMinRating.toString() + '|' + this.initialPageFrom.toString() + '|' + this.initialPageTo.toString();
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
    this.searchMode = cache.searchMode;
    this.searchCategory = cache.searchCategory;
    this.advancedSearchEnabled = cache.advancedSearchEnabled;
    this.advanceSearch = cache.advanceSearch;
    this.minRating = cache.minRating;
    this.pageFrom = cache.pageFrom;
    this.pageTo = cache.pageTo;
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
      searchMode: this.searchMode,
      searchCategory: this.searchCategory,
      advancedSearchEnabled: this.advancedSearchEnabled,
      advanceSearch: this.advanceSearch,
      minRating: this.minRating,
      pageFrom: this.pageFrom,
      pageTo: this.pageTo,
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
      this.searchMode = this.initialSearchMode;
      this.searchCategory = this.initialSearchCategory;
      this.advancedSearchEnabled = this.initialAdvancedSearchEnabled;
      this.advanceSearch = this.initialAdvanceSearch;
      this.minRating = this.initialMinRating;
      this.pageFrom = this.initialPageFrom;
      this.pageTo = this.initialPageTo;
    }
    const context = getAbilityContext();
    if (context !== undefined) {
      Promise.all([
        ehCookieStore.load(context),
        ehFilterStore.load(context)
      ]).catch((error: Error) => {
        this.statusText = 'Cookie load failed, using current session: ' + error.message;
      }).finally(() => {
        this.firstRefresh();
      });
    } else {
      this.firstRefresh();
    }
    setActiveBackHandler(() => this.handleSystemBack());
  }

  aboutToDisappear(): void {
    this.saveListCache();
    setActiveBackHandler(null);
  }

  private handleSystemBack(): boolean {
    if (this.showSearchResultScene) {
      this.closeSearchResultScene();
      return true;
    }
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
    if (this.isSearchResultScene) {
      this.onBack();
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
    return this.loadRoutePage(pageIndex, primarySite).then((result: GalleryListLoadResult) => {
      this.activeSite = primarySite;
      return result;
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
    builder.mode = this.searchModeForRoute(routeMode, builder.keyword);
    builder.follow = this.follow;
    builder.category = this.searchCategory;
    if (this.advancedSearchEnabled && this.searchSupportsAdvanced(builder.mode)) {
      builder.advanceSearch = this.advanceSearch;
      builder.minRating = this.minRating;
      builder.pageFrom = this.pageFrom;
      builder.pageTo = this.pageTo;
    }
    this.requestUrl = builder.build(site);
    return this.client.loadGalleryList(builder, site);
  }

  private searchModeForRoute(routeMode: ListMode, keyword: string): ListMode {
    if (this.filterActive && keyword.trim().length > 0) {
      return ListMode.Filter;
    }
    if (this.sourceRoute === GalleryRoute.Home) {
      return this.searchMode;
    }
    if (this.sourceRoute === GalleryRoute.Subscription && this.searchMode !== ListMode.Uploader &&
      this.searchMode !== ListMode.Tag) {
      return ListMode.Subscription;
    }
    if (this.searchMode === ListMode.Uploader || this.searchMode === ListMode.Tag) {
      return this.searchMode;
    }
    return routeMode;
  }

  private searchSupportsAdvanced(mode: ListMode): boolean {
    return mode === ListMode.Normal || mode === ListMode.Subscription;
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
    this.rememberSearchKeyword(this.keyword);
    this.resetListScroll();
    this.loadRemote(0);
  }

  private rememberSearchKeyword(keyword: string): void {
    recordSearchHistory(keyword);
  }

  private openSearchScene(): void {
    this.fabExpanded = false;
    this.searchResultDraft = {
      keyword: this.keyword.trim(),
      mode: this.searchMode,
      category: this.searchCategory,
      advancedEnabled: this.advancedSearchEnabled,
      advanceSearch: this.advanceSearch,
      minRating: this.minRating,
      pageFrom: -1,
      pageTo: -1
    };
    this.showSearchResultScene = true;
  }

  private closeSearchResultScene(): void {
    this.showSearchResultScene = false;
    setTimeout(() => {
      setActiveBackHandler(() => this.handleSystemBack());
    }, 0);
  }

  private applySearchDraft(keyword: string, mode: ListMode, category: number, advancedEnabled: boolean, flags: number,
    minRating: number, pageFrom: number, pageTo: number): void {
    const normalizedKeyword = keyword.replace(/\r|\n/g, ' ').trim();
    this.rememberSearchKeyword(normalizedKeyword);
    this.searchResultDraft = {
      keyword: normalizedKeyword,
      mode: mode,
      category: category,
      advancedEnabled: advancedEnabled,
      advanceSearch: flags,
      minRating: minRating,
      pageFrom: -1,
      pageTo: -1
    };
    this.showSearchResultScene = true;
    this.fabExpanded = false;
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
    this.detailPreviewPager.start();
    this.detail = createDetailFromGallery(gallery);
    this.resetReaderPreviewCache();
    this.detailStatus = 'Loading detail for gid ' + gallery.gid.toString() + '...';
    this.detailRequestUrl = '';
    this.detailDownloadText = downloadButtonText(gallery.gid);
    this.detailLoaded = false;
    this.optimisticFavorite = gallery.favoriteSlot >= 0;
    this.favoriteBusy = false;
    this.renderVersion++;

    this.client.loadGalleryDetail(gallery.gid, gallery.token, 0, this.activeSite, this.requestUrl).then((result: GalleryDetailLoadResult) => {
      this.detailRequestUrl = result.url;
      if (!result.ok || result.detail === null) {
        this.detailStatus = 'Detail load failed: ' + result.message;
        this.renderVersion++;
        return;
      }

      this.detailStatus = 'Detail loaded';
      this.detail = mergeLoadedGalleryDetail(result.detail, this.detail);
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
    this.detailStatus = 'Tap a gallery row to load detail';
    this.detailRequestUrl = '';
    this.detailDownloadText = 'Download';
    this.detailLoaded = false;
    this.optimisticFavorite = false;
    this.favoriteBusy = false;
    this.detailPreviewPager.reset();
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
    this.openReaderAbility();

    const cached = galleryPageCache.get(preview.pageUrl);
    if (cached !== null) {
      this.readerStatus = 'Page loaded from cache';
      this.readerPage = cloneGalleryPage(cached);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, cached);
      this.preloadReaderPages(preview.index);
      this.persistReaderSession();
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
      this.persistReaderSession();
    }).catch((error: Error) => {
      this.readerStatus = 'Page load failed: ' + error.message;
      this.renderVersion++;
      this.persistReaderSession();
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
    this.openReaderAbility();
    this.ensureReaderPreview(index, false).then((resolved: GalleryPreview | null) => {
      if (resolved === null) {
        if (this.readerPreviewIndex === index) {
          this.readerStatus = 'Page URL is unavailable';
          this.renderVersion++;
          this.persistReaderSession();
        }
        return;
      }
      if (this.readerPreviewIndex === index) {
        this.loadReaderPage(resolved);
      }
    }).catch((error: Error) => {
      if (this.readerPreviewIndex === index) {
        this.readerStatus = 'Page URL load failed: ' + error.message;
        this.renderVersion++;
        this.persistReaderSession();
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

  private persistReaderSession(): void {
    readerSessionStore.updateSession(createReaderSessionState(this.detail, this.readerPage, this.readerStatus,
      this.detailRequestUrl, this.requestUrl, this.activeSite, this.readerPreviewIndex));
  }

  private publishReaderSession(): void {
    readerSessionStore.setSession(createReaderSessionState(this.detail, this.readerPage, this.readerStatus,
      this.detailRequestUrl, this.requestUrl, this.activeSite, this.readerPreviewIndex));
  }

  private openReaderAbility(): void {
    this.publishReaderSession();
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
      this.persistReaderSession();
    });
  }

  private resetReaderPreviewCache(): void {
    this.readerPreviewMap.clear();
    this.readerPreviewPageRequests.clear();
    this.readerPreviewPageSize = 0;
  }

  private seedReaderPreviewCache(previews: GalleryPreview[]): void {
    this.readerPreviewPageSize = seedPreviewMap(this.readerPreviewMap, previews, this.readerPreviewPageSize);
  }

  private readerTotalPages(): number {
    if (this.detail.pages > 0) {
      return this.detail.pages;
    }
    return Math.max(this.detail.previewSet.length, this.readerPreviewMap.size);
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
    const pageSize = this.readerPreviewPageSize > 0 ? this.readerPreviewPageSize :
      Math.max(1, this.detail.previewSet.length);
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

    const referer = this.detailRequestUrl.length > 0 ? this.detailRequestUrl : this.requestUrl;
    const request = this.client.loadGalleryDetail(this.detail.gid, this.detail.token, previewPageIndex,
      this.activeSite, referer).then((result: GalleryDetailLoadResult) => {
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
    }).catch((error: Error) => {
      this.readerPreviewPageRequests.delete(previewPageIndex);
      if (!silent) {
        this.readerStatus = 'Preview page load failed: ' + error.message;
        this.renderVersion++;
      }
      return null;
    });
    this.readerPreviewPageRequests.set(previewPageIndex, request);
    return request;
  }

  private mergeReaderPreviewSet(loaded: GalleryDetail): void {
    const merged = mergeGalleryPreviewSets(this.detail, loaded, this.readerPreviewMap, this.readerPreviewPageSize);
    this.detail = merged.detail;
    this.readerPreviewPageSize = merged.previewPageSize;
    this.renderVersion++;
  }

  private async loadNextDetailPreviewPage(): Promise<void> {
    const referer = this.detailRequestUrl.length > 0 ? this.detailRequestUrl : this.requestUrl;
    await this.detailPreviewPager.loadNext({
      client: this.client,
      site: this.activeSite,
      referer: referer,
      getDetail: () => this.detail,
      isVisible: () => this.showDetail,
      onMerge: (detail: GalleryDetail) => {
        this.mergeReaderPreviewSet(detail);
      },
      onError: (message: string) => {
        this.detailStatus = 'Preview page load failed: ' + message;
        this.renderVersion++;
      }
    });
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
      this.activeSite).then((result: ToggleFavoriteResult) => {
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

  private loadDetailByToken(gid: number, token: string): void {
    const gallery = createEmptyGallery();
    gallery.gid = gid;
    gallery.token = token;
    gallery.title = 'Gallery ' + gid.toString();
    this.loadDetail(gallery);
  }

  private applyDetailFavoriteState(isFavorited: boolean): void {
    const nextDetail = cloneGalleryDetail(this.detail);
    nextDetail.isFavorited = isFavorited;
    nextDetail.favoriteSlot = isFavorited ? Math.max(0, nextDetail.favoriteSlot) : -2;
    this.detail = nextDetail;
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
      this.activeSite).then((result: RateGalleryResult) => {
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

  private shareDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      this.renderVersion++;
      return;
    }
    const url = EhUrl.getGalleryDetailUrl(this.detail.gid, this.detail.token, 0, false, this.activeSite);
    this.copyDetailLink(url, 'Gallery URL');
  }

  build() {
    Column() {
      if (this.showSearchResultScene) {
        GalleryListScene({
          sceneTitle: this.searchResultDraft.keyword.length > 0 ? this.searchResultDraft.keyword : 'Search',
          listMode: 'Search',
          sourceRoute: this.sourceRoute,
          initialKeyword: this.searchResultDraft.keyword,
          initialSearchMode: this.searchResultDraft.mode,
          initialSearchCategory: this.searchResultDraft.category,
          initialAdvancedSearchEnabled: this.searchResultDraft.advancedEnabled,
          initialAdvanceSearch: this.searchResultDraft.advanceSearch,
          initialMinRating: this.searchResultDraft.minRating,
          initialPageFrom: this.searchResultDraft.pageFrom,
          initialPageTo: this.searchResultDraft.pageTo,
          isSearchResultScene: true,
          onBack: () => {
            this.closeSearchResultScene();
          }
        })
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.move(TransitionEdge.END).animation({ duration: 260, curve: Curve.EaseOut }),
            TransitionEffect.move(TransitionEdge.END).animation({ duration: 220, curve: Curve.EaseIn })))
      } else if (this.showReader) {
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
      } else if (this.showDetail) {
        GalleryDetailOverlayScene({
          renderVersion: this.renderVersion,
          showComments: this.showComments,
          detail: this.detail,
          isDetailLoaded: this.detailLoaded,
          isFavorited: this.optimisticFavorite,
          statusText: this.detailStatus,
          requestUrl: this.detailRequestUrl,
          downloadText: this.detailDownloadText,
          onBack: () => {
            this.closeDetail();
          },
          onCloseComments: () => {
            this.closeComments();
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
          onLoadMorePreviews: () => {
            this.loadNextDetailPreviewPage();
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
          sceneTitle: this.sceneTitle,
          listMode: this.listMode,
          keyword: this.keyword,
          searchTitle: gallerySearchTitle(this.sourceRoute, this.keyword, this.filterActive),
          actionsExpanded: this.fabExpanded,
          filterActive: this.filterActive,
          showSearchButton: routeUsesKeyword(this.sourceRoute) && !this.isSearchResultScene,
          showBackButton: this.isSearchResultScene,
          isSearchResultScene: this.isSearchResultScene,
          searchModeValue: this.searchMode,
          searchCategory: this.searchCategory,
          advancedSearchEnabled: this.advancedSearchEnabled,
          advanceSearch: this.advanceSearch,
          minRating: this.minRating,
          pageIndex: this.pageIndex,
          totalPages: this.totalPages,
          canJump: this.totalPages > 1,
          canRandom: this.galleries.length > 0,
          statusText: this.statusText,
          requestUrl: this.requestUrl,
          isLoadingMore: this.isLoadingMore,
          galleries: this.galleries,
          onKeywordChange: (value: string) => {
            this.keyword = value;
          },
          onSearchModeChange: (mode: ListMode) => {
            this.searchMode = mode;
          },
          onSearchCategoryChange: (category: number) => {
            this.searchCategory = category;
          },
          onAdvancedEnabledChange: (enabled: boolean) => {
            this.advancedSearchEnabled = enabled;
          },
          onAdvanceSearchChange: (flags: number) => {
            this.advanceSearch = flags;
          },
          onMinRatingChange: (rating: number) => {
            this.minRating = rating;
          },
          onPageJump: (page: number) => {
            this.loadRemote(Math.max(0, page - 1));
          },
          onMenu: () => {
            this.onMenu();
          },
          onBack: () => {
            this.onBack();
          },
          onSearch: () => {
            if (this.isSearchResultScene) {
              this.applySearch();
            } else {
              this.openSearchScene();
            }
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
  @Prop sceneTitle: string = '';
  @Prop listMode: string = '';
  @Prop keyword: string = '';
  @Prop searchTitle: string = '';
  @Prop actionsExpanded: boolean = false;
  @Prop filterActive: boolean = false;
  @Prop showSearchButton: boolean = false;
  @Prop showBackButton: boolean = false;
  @Prop isSearchResultScene: boolean = false;
  @Prop searchModeValue: ListMode = ListMode.Normal;
  @Prop searchCategory: number = GalleryCategory.None;
  @Prop advancedSearchEnabled: boolean = false;
  @Prop advanceSearch: number = DEFAULT_ADVANCE_SEARCH;
  @Prop minRating: number = -1;
  @Prop @Watch('onPageChanged') pageIndex: number = 0;
  @Prop totalPages: number = 0;
  @Prop canJump: boolean = false;
  @Prop canRandom: boolean = false;
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  @Prop isLoadingMore: boolean = false;
  @Prop galleries: GalleryInfo[] = [];
  @Prop @Watch('onScrollReset') scrollResetVersion: number = 0;
  onKeywordChange: (value: string) => void = () => {};
  onSearchModeChange: (mode: ListMode) => void = (_mode: ListMode) => {};
  onSearchCategoryChange: (category: number) => void = (_category: number) => {};
  onAdvancedEnabledChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onAdvanceSearchChange: (flags: number) => void = (_flags: number) => {};
  onMinRatingChange: (rating: number) => void = (_rating: number) => {};
  onPageJump: (page: number) => void = (_page: number) => {};
  onMenu: () => void = () => {};
  onBack: () => void = () => {};
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
  @State refreshing: boolean = false;
  @State advancedPanelVisible: boolean = false;
  @State pageJumpDraft: string = '';
  onRefreshPull: (done: () => void) => void = (done: () => void) => { done(); };
  // 下拉刷新自定义 builder 状态
  @State refreshScaleNum: number = 0;
  @State refreshShowLogo: boolean = true;
  @State refreshMsg: string = '';
  private readonly REFRESH_OFFSET: number = 42;
  private readonly REFRESH_HEADER_HEIGHT: number = 52;
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

  onPageChanged(): void {
    this.syncPageJumpDraft();
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  aboutToAppear(): void {
    this.syncPageJumpDraft();
  }

  private syncPageJumpDraft(): void {
    this.pageJumpDraft = (this.pageIndex + 1).toString();
  }

  private submitPageJump(): void {
    const parsed = Number.parseInt(this.pageJumpDraft);
    if (Number.isNaN(parsed) || parsed <= 0) {
      this.syncPageJumpDraft();
      return;
    }
    const maxPage = this.totalPages > 0 ? this.totalPages : parsed;
    this.onPageJump(Math.max(1, Math.min(parsed, maxPage)));
  }

  private toggleAdvancedPanel(): void {
    this.advancedPanelVisible = !this.advancedPanelVisible;
  }

  private closeAdvancedPanel(): void {
    this.advancedPanelVisible = false;
  }

  private searchResultSubtitle(): string {
    if (this.totalPages > 0) {
      return (this.pageIndex + 1).toString() + ' / ' + this.totalPages.toString();
    }
    return (this.pageIndex + 1).toString() + ' / -';
  }
  
  private totalBarHeight(): number {
    return this.statusBarVp() + this.barHeight;
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
    return this.totalBarHeight() + this.searchResultStripHeight() + rows * cardHeight + Math.max(0, rows - 1) * this.galleryCardGap() +
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

  private searchResultStripHeight(): number {
    return this.isSearchResultScene ? 42 : 0;
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
    return this.galleryColumnCountForWidth(this.contentWidth);
  }

  private galleryColumnCountForWidth(width: number): number {
    const availableWidth = Math.max(0, width - this.galleryContentPadding() * 2);
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
    const oldColumns = this.galleryColumnCount();
    const nextColumns = this.galleryColumnCountForWidth(width);
    if (this.contentWidth <= 0 || oldColumns === nextColumns) {
      this.contentWidth = width;
      return;
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.contentWidth = width;
    });
  }


  @Builder
  private customRefreshComponent() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 2 }) {
        Image($r('app.media.app_icon'))
          .width(26)
          .height(26)
          .scale({ x: this.refreshScaleNum, y: this.refreshScaleNum })
          .visibility(this.refreshShowLogo ? Visibility.Visible : Visibility.None)
        LoadingProgress()
          .width(26)
          .height(26)
          .color(APP_THEME_COLOR)
          .visibility(this.refreshShowLogo ? Visibility.None : Visibility.Visible)
        if (this.refreshMsg.length > 0) {
          Text(this.refreshMsg)
            .fontSize(10)
            .fontColor($r('app.color.secondary_text'))
        }
      }
      .alignItems(HorizontalAlign.Center)
      .margin({ bottom: 4 })
    }
    .width('100%')
    .height(this.REFRESH_HEADER_HEIGHT)
    .clip(true)
  }

  @Builder
  private searchResultNavBar() {
    Column() {
      Column()
        .height(this.statusBarVp())
        .width('100%')
        .backgroundColor(APP_THEME_COLOR)

      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([Color.White])
        }
        .width(40)
        .height(40)
        .backgroundColor('rgba(255,255,255,0.14)')
        .flexShrink(0)
        .onClick(() => {
          this.onBack();
        })

        TextInput({ text: this.keyword, placeholder: uiText('Search galleries') })
          .height(38)
          .layoutWeight(1)
          .backgroundColor('#F4F7F9')
          .borderRadius(19)
          .placeholderColor('#5D7183')
          .fontColor('#17202A')
          .caretColor(APP_THEME_COLOR)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.onKeywordChange(value);
          })
          .onSubmit(() => {
            this.closeAdvancedPanel();
            this.onSearch();
          })

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(22)
            .fontColor([Color.White])
        }
        .width(40)
        .height(40)
        .backgroundColor(this.advancedPanelVisible || this.advancedSearchEnabled ? 'rgba(255,255,255,0.28)' :
          'rgba(255,255,255,0.14)')
        .flexShrink(0)
        .onClick(() => {
          this.toggleAdvancedPanel();
        })
      }
      .width('100%')
      .height(this.barHeight)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(APP_THEME_COLOR)
    }
    .width('100%')
    .translate({ y: this.toolbarOffsetY })
    .animation({ duration: 200, curve: Curve.EaseOut })
    .zIndex(10)
  }

  @Builder
  private searchPageStrip() {
    Row({ space: 8 }) {
      Text(uiText('Page'))
        .fontSize(12)
        .fontColor('#40566F')
      TextInput({ text: this.pageJumpDraft, placeholder: '1' })
        .width(64)
        .height(30)
        .type(InputType.Number)
        .fontSize(13)
        .fontColor('#17202A')
        .backgroundColor('#EEF2F6')
        .borderRadius(4)
        .textAlign(TextAlign.Center)
        .onChange((value: string) => {
          this.pageJumpDraft = value;
        })
        .onSubmit(() => {
          this.submitPageJump();
        })
      Text('/ ' + (this.totalPages > 0 ? this.totalPages.toString() : '-'))
        .fontSize(12)
        .fontColor('#667085')
      Text(this.resultSummaryText())
        .fontSize(12)
        .fontColor('#667085')
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([Color.White])
      }
      .width(32)
      .height(32)
      .backgroundColor(APP_THEME_COLOR)
      .onClick(() => {
        this.closeAdvancedPanel();
        this.onSearch();
      })
    }
    .width('100%')
    .height(42)
    .padding({ left: 10, right: 10 })
    .backgroundColor(Color.White)
  }

  private resultSummaryText(): string {
    if (this.statusText.length > 0) {
      return uiStatusText(this.statusText);
    }
    return this.searchResultSubtitle();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Refresh({ refreshing: $$this.refreshing, builder: this.customRefreshComponent() }) {
          List({ space: 0, scroller: this.listScroller }) {
            ListItem() {
              Column() {
                Blank()
                  .width('100%')
                  .height(this.totalBarHeight())
              }
                .width('100%')
            }

            if (this.isSearchResultScene) {
              ListItem() {
                this.searchPageStrip()
              }
            }

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
                          .animation({ duration: 220, curve: Curve.EaseOut })
                          .onClick(() => { this.onSelectGallery(gallery); })
                      } else {
                        GalleryListRow({ gallery: gallery })
                          .width(this.galleryCardWidth())
                          .margin({
                            right: colIndex < row.length - 1 ? this.galleryCardGap() : 0
                          })
                          .animation({ duration: 220, curve: Curve.EaseOut })
                          .onClick(() => { this.onSelectGallery(gallery); })
                      }
                    }, (gallery: GalleryInfo) => gallery.gid.toString())
                  }
                  .width('100%')
                  .padding({ left: this.galleryContentPadding(), right: this.galleryContentPadding() })
                  .justifyContent(FlexAlign.Start)
                  .animation({ duration: 220, curve: Curve.EaseOut })
                }
              .margin({ bottom: this.galleryCardGap() })
              }, (_row: GalleryInfo[], rowIndex: number) => {
                return this.galleryColumnCount().toString() + ':' + rowIndex.toString() + ':' + this.galleryRowKey(_row);
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

            }
          }
          .contentStartOffset(this.contentStartOffset())
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false, effectEdge: EffectEdge.START })
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

      if (this.advancedPanelVisible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.18)')
          .onClick(() => {
            this.closeAdvancedPanel();
          })
          .zIndex(11)

        SearchAdvancedPanel({
          searchModeValue: this.searchModeValue,
          searchCategory: this.searchCategory,
          advancedSearchEnabled: this.advancedSearchEnabled,
          advanceSearch: this.advanceSearch,
          minRating: this.minRating,
          onSearchModeChange: this.onSearchModeChange,
          onSearchCategoryChange: this.onSearchCategoryChange,
          onAdvancedEnabledChange: this.onAdvancedEnabledChange,
          onAdvanceSearchChange: this.onAdvanceSearchChange,
          onMinRatingChange: this.onMinRatingChange,
          onClose: () => {
            this.closeAdvancedPanel();
          },
          onSearch: () => {
            this.closeAdvancedPanel();
            this.onSearch();
          }
        })
          .margin({ top: this.statusBarVp() + this.barHeight + 8, left: 10, right: 10 })
          .transition(TransitionEffect.move(TransitionEdge.TOP)
            .animation({ duration: 180, curve: Curve.EaseOut }))
          .zIndex(12)
      }

      // 浮动导航栏
      Column() {
        if (this.isSearchResultScene) {
          this.searchResultNavBar()
        } else {
          EhNavBar({
            statusBarHeight: this.statusBarVp(),
            title: this.searchTitle.length > 0 ? this.searchTitle : this.sceneTitle,
            searchMode: false,
            keyword: this.keyword,
            filterActive: this.filterActive,
            showSearchButton: this.showSearchButton,
            showBackButton: this.showBackButton,
            translateY: this.toolbarOffsetY,
            onMenu: () => { this.onMenu(); },
            onBack: () => { this.onBack(); },
            onSearch: () => { this.onSearch(); },
            onKeywordChange: (v: string) => { this.onKeywordChange(v); },
            onRefresh: () => { this.onRefresh(); }
          })
        }
      }
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

  private galleryRowKey(row: GalleryInfo[]): string {
    return row.map((gallery: GalleryInfo) => gallery.gid.toString()).join('-');
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
