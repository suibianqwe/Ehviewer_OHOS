import { pasteboard } from '@kit.BasicServicesKit';
import {
  GalleryCategory,
  GalleryDetail,
  GalleryInfo,
  GalleryPage,
  GalleryPreview,
  GalleryRoute,
  GallerySite
} from '../model/GalleryModels';
import { ehCookieStore } from '../services/EhCookieStore';
import {
  EhHttpClient,
  GalleryDetailLoadResult,
  GalleryListLoadResult,
  GalleryPageLoadResult,
  RateGalleryResult,
  ToggleFavoriteResult
} from '../services/EhHttpClient';
import { DEFAULT_ADVANCE_SEARCH, EhUrl, FavListUrlBuilder, ListMode, ListUrlBuilder } from '../services/EhUrl';
import { galleryPageCache } from '../services/GalleryPageCache';
import { ehFilterStore } from '../services/EhFilterStore';
import { DetailPreviewPager, mergeGalleryPreviewSets, seedPreviewMap } from '../services/GalleryPreviewLoader';
import { createReaderSessionState, readerSessionStore } from '../services/ReaderSessionStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import {
  applyAppChromeImmersiveMode,
  enterEmbeddedReaderFullscreen,
  mainContentWidthFallbackVp,
  rememberMainContentWidthVp
} from '../services/EhWindowImmersive';
import { LANGUAGE_REVISION_KEY } from '../shared/EhShared';
import {
  themeFieldBackground,
  themeDangerText,
  themeOnPrimaryActionBackground,
  themeOnPrimaryActionStrongBackground,
  themeOnPrimaryText,
  themePageBackground,
  themePlaceholderColor,
  themePrimaryColor,
  themePrimaryText,
  themeScrimColor,
  themeSecondaryText,
  themeShadowColor,
  themeSurface,
  themeTertiaryText
} from '../shared/EhTheme';
import { ArrayDataSource } from '../shared/ListDataSource';
import { EhNavBar } from '../components/NavigationComponents';
import { CategoryBadge, GalleryListRow, GalleryThumb, GalleryThumbCard } from './GalleryCards';
import { GalleryDetailOverlayScene, GalleryDetailScene } from './GalleryDetailScenes';
import {
  applyTagSuggestionToKeyword,
  buildSearchSuggestions,
  gallerySuggestionUrl,
  QuickActionColumn,
  SearchAdvancedPanel,
  SearchSuggestionItem,
  SearchSuggestionList,
  SearchSummaryStrip,
  recordSearchHistory
} from './GallerySearchScenes';
import { CommentsScene, PlaceholderScene, ReaderPageState, ReaderScene } from './ReaderScenes';
import {
  uiText,
  uiStatusText,
  setActiveBackHandler,
  createEmptyGallery,
  createDetailFromGallery,
  createEmptyDetail,
  createEmptyPage,
  cloneGalleryInfos,
  applyGalleryFilters,
  cloneGalleryDetail,
  cloneGalleryPage,
  createReaderLoadingPage,
  getAbilityContext,
  immersiveChromeHeightFromOffset,
  nextFloatingToolbarOffset,
  saveGalleryToHistory,
  saveGalleryReadPosition,
  readerStartIndex,
  downloadButtonText,
  toggleGalleryDownload,
  listModeForRoute,
  routeUsesKeyword,
  defaultKeywordForRoute,
  gallerySearchTitle,
  effectiveListSite,
  galleryListFailureMessage,
  readerPageReferer,
  cacheReaderImageForPage,
  readerPreloadCount,
  galleryListMode,
  galleryThumbWidth,
  galleryThumbHeight
} from '../shared/EhShared';

export { CategoryBadge, GalleryListRow, GalleryTagChip, GalleryThumb, GalleryThumbCard } from './GalleryCards';

export { GalleryDetailOverlayScene, GalleryDetailScene } from './GalleryDetailScenes';

export { ActionBubble,
  QuickActionColumn,
  SearchAdvancedPanel,
  SearchFlagChip,
  SearchSuggestionList,
  SearchSummaryStrip } from './GallerySearchScenes';

export { CommentsScene,
  PlaceholderScene,
  ReaderNavButton,
  ReaderPageState,
  ReaderScene,
  ReaderToolButton } from './ReaderScenes';

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
  searchSubmitted: boolean;
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
  submitted: boolean;
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
    pageTo: -1,
    submitted: false
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
  if ((next.thumb === undefined || next.thumb.length === 0) && previous.thumb !== undefined &&
    previous.thumb.length > 0) {
    next.thumb = previous.thumb;
  }
  if ((next.thumb === undefined || next.thumb.length === 0) && next.previewSet.length > 0) {
    next.thumb = next.previewSet[0].imageUrl;
  }
  return next;
}

export { HomeGalleryScene } from './HomeGalleryScene';

export { SubscriptionGalleryScene } from './SubscriptionGalleryScene';

export { HotGalleryScene } from './HotGalleryScene';

export { FavoriteGalleryScene } from './FavoriteGalleryScene';

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
  initialSearchSubmitted: boolean = false;
  isSearchResultScene: boolean = false;
  useForcedMode: boolean = false;
  forcedMode: ListMode = ListMode.Normal;
  onMenu: () => void = () => {
  };
  onBack: () => void = () => {
  };
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
  @State searchSubmitted: boolean = false;
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
  @State readerPages: ReaderPageState[] = [];
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
    this.searchSubmitted = cache.searchSubmitted === true;
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
      searchSubmitted: this.searchSubmitted,
      listScrollOffset: this.listScrollOffset
    });
  }

  private resetListScroll(): void {
    this.listScrollOffset = 0;
    this.saveListCache();
  }

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    if (!this.restoreListCache()) {
      this.keyword = this.initialKeyword.length > 0 ? this.initialKeyword : defaultKeywordForRoute(this.sourceRoute);
      this.searchMode = this.initialSearchMode;
      this.searchCategory = this.initialSearchCategory;
      this.advancedSearchEnabled = this.initialAdvancedSearchEnabled;
      this.advanceSearch = this.initialAdvanceSearch;
      this.minRating = this.initialMinRating;
      this.pageFrom = this.initialPageFrom;
      this.pageTo = this.initialPageTo;
      this.searchSubmitted = !this.isSearchResultScene || this.initialSearchSubmitted;
    }
    const context = getAbilityContext();
    if (context !== undefined) {
      Promise.all([
        ehCookieStore.load(context),
        ehFilterStore.load(context)
      ]).catch((error: Error) => {
        this.statusText = 'Cookie load failed, using current session: ' + error.message;
      }).finally(() => {
        if (!this.isSearchResultScene || this.searchSubmitted) {
          this.firstRefresh();
        }
      });
    } else {
      if (!this.isSearchResultScene || this.searchSubmitted) {
        this.firstRefresh();
      }
    }
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
    if (this.showSearchResultScene) {
      this.closeSearchResultScene();
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
    if (this.isSearchResultScene && !this.searchSubmitted) {
      return;
    }
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

    const request =
      this.nextUrl.length > 0 ? this.client.loadGalleryListUrl(this.absoluteListUrl(this.nextUrl), this.activeSite) :
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

  private applySearch(): void {
    this.fabExpanded = false;
    this.rememberSearchKeyword(this.keyword);
    const directGallery = gallerySuggestionUrl(this.keyword);
    if (directGallery !== null) {
      this.searchSubmitted = true;
      this.hasFirstRefresh = true;
      this.resetListScroll();
      this.loadDetailByToken(directGallery.gid, directGallery.token);
      return;
    }
    this.searchSubmitted = true;
    this.hasFirstRefresh = true;
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
      pageTo: -1,
      submitted: false
    };
    this.showSearchResultScene = true;
  }

  private closeSearchResultScene(): void {
    this.showSearchResultScene = false;
    setTimeout(() => {
      setActiveBackHandler(() => this.handleSystemBack());
    }, 0);
  }

  private openTagSearch(namespace: string, tag: string): void {
    const trimmedNamespace = namespace.trim();
    const trimmedTag = tag.trim();
    if (trimmedNamespace.length === 0 || trimmedTag.length === 0) {
      return;
    }
    const tagQuery = trimmedTag.indexOf(' ') >= 0 ? '"' + trimmedTag.replace(/"/g, '\\"') + '"' : trimmedTag;
    this.showComments = false;
    this.showReader = false;
    this.searchResultDraft = {
      keyword: trimmedNamespace + ':' + tagQuery,
      mode: ListMode.Tag,
      category: GalleryCategory.None,
      advancedEnabled: false,
      advanceSearch: DEFAULT_ADVANCE_SEARCH,
      minRating: -1,
      pageFrom: -1,
      pageTo: -1,
      submitted: true
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

    this.client.loadGalleryDetail(gallery.gid, gallery.token, 0, this.activeSite, this.requestUrl)
      .then((result: GalleryDetailLoadResult) => {
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
      })
      .catch((error: Error) => {
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
    this.readerPages = [];
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
    this.readerPages = [];
    this.readerPreviewIndex = 0;
    applyAppChromeImmersiveMode();
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
    this.setReaderPage(preview.index, this.readerPage);
    this.renderVersion++;
    this.openReaderAbility();

    const cached = galleryPageCache.get(preview.pageUrl);
    if (cached !== null) {
      this.readerStatus = 'Page loaded from cache';
      this.readerPage = cloneGalleryPage(cached);
      this.setReaderPage(preview.index, cached);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, cached);
      this.preloadReaderPages(preview.index);
      this.persistReaderSession();
      return;
    }

    this.client.loadGalleryPage(preview.pageUrl, this.activeSite,
      readerPageReferer(this.detailRequestUrl, this.detail.previewSet, preview.index, this.activeSite))
      .then((result: GalleryPageLoadResult) => {
        if (!result.ok || result.page === null) {
          this.readerStatus = 'Page load failed: ' + result.message;
          return;
        }
        const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
        galleryPageCache.put(cacheUrl, result.page);
        galleryPageCache.put(preview.pageUrl, result.page);
        if (this.readerPreviewIndex !== preview.index) {
          this.setReaderPage(preview.index, result.page);
          this.cacheReaderImage(preview.index, result.page);
          return;
        }
        this.readerStatus = 'Page loaded';
        this.readerPage = cloneGalleryPage(result.page);
        this.setReaderPage(preview.index, result.page);
        this.renderVersion++;
        this.cacheReaderImage(preview.index, result.page);
        this.preloadReaderPages(preview.index);
        this.persistReaderSession();
      })
      .catch((error: Error) => {
        this.readerStatus = 'Page load failed: ' + error.message;
        this.renderVersion++;
        this.persistReaderSession();
      });
  }

  private cacheReaderImage(index: number, page: GalleryPage): void {
    cacheReaderImageForPage(page, (cachedPage: GalleryPage) => {
      galleryPageCache.put(cachedPage.pageUrl.length > 0 ? cachedPage.pageUrl : page.pageUrl, cachedPage);
      this.setReaderPage(index, cachedPage);
      if (this.showReader && this.readerPreviewIndex === index) {
        this.readerPage = cloneGalleryPage(cachedPage);
        this.readerStatus = 'Page loaded from local cache';
        this.renderVersion++;
      }
    }, this.detail, index);
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
          this.setReaderPage(nextIndex, result.page);
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
        this.setReaderPage(0, result.page);
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
    this.setReaderPage(index, this.readerPage);
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
      enterEmbeddedReaderFullscreen();
      this.showReader = true;
      return;
    }
    this.showReader = false;
    const context = getAbilityContext();
    if (context === undefined) {
      this.readerStatus = 'Reader launch failed: Ability context is not ready';
      this.renderVersion++;
      this.persistReaderSession();
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

  private setReaderPage(index: number, page: GalleryPage): void {
    const next: ReaderPageState[] = [];
    let replaced = false;
    for (let i = 0; i < this.readerPages.length; i++) {
      if (this.readerPages[i].index === index) {
        next.push({ index: index, page: cloneGalleryPage(page) });
        replaced = true;
      } else {
        next.push({ index: this.readerPages[i].index, page: cloneGalleryPage(this.readerPages[i].page) });
      }
    }
    if (!replaced) {
      next.push({ index: index, page: cloneGalleryPage(page) });
    }
    next.sort((left: ReaderPageState, right: ReaderPageState) => left.index - right.index);
    this.readerPages = next;
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
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.detailStatus = label + ' link copied to clipboard';
        this.renderVersion++;
      }).catch((error: Error) => {
        this.detailStatus = label + ' copy failed: ' + error.message;
        this.renderVersion++;
      });
      return;
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
          initialSearchSubmitted: this.searchResultDraft.submitted,
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
          readerPages: this.readerPages,
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
          },
          onTagSearch: (namespace: string, tag: string) => {
            this.openTagSearch(namespace, tag);
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
          searchSubmitted: this.searchSubmitted,
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
            if (this.isSearchResultScene) {
              this.searchSubmitted = false;
              this.galleries = [];
              this.resultCount = '';
              this.nextUrl = '';
              this.statusText = '';
              this.saveListCache();
            }
          },
          onSearchModeChange: (mode: ListMode) => {
            this.searchMode = mode;
            if (this.isSearchResultScene) {
              this.searchSubmitted = false;
            }
          },
          onSearchCategoryChange: (category: number) => {
            this.searchCategory = category;
            if (this.isSearchResultScene) {
              this.searchSubmitted = false;
            }
          },
          onAdvancedEnabledChange: (enabled: boolean) => {
            this.advancedSearchEnabled = enabled;
            if (this.isSearchResultScene) {
              this.searchSubmitted = false;
            }
          },
          onAdvanceSearchChange: (flags: number) => {
            this.advanceSearch = flags;
            if (this.isSearchResultScene) {
              this.searchSubmitted = false;
            }
          },
          onMinRatingChange: (rating: number) => {
            this.minRating = rating;
            if (this.isSearchResultScene) {
              this.searchSubmitted = false;
            }
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
            if (this.isSearchResultScene && !this.searchSubmitted) {
              this.applySearch();
              return;
            }
            this.loadRemote(0, this.galleries.length > 0);
          },
          onRefreshPull: (done: () => void) => {
            if (this.isSearchResultScene && !this.searchSubmitted) {
              this.applySearch();
              done();
              return;
            }
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
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }),
            TransitionEffect.OPACITY.animation({ duration: 1, delay: 300, curve: Curve.Linear })))
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
  @Prop @Watch('onSearchKeywordChanged') keyword: string = '';
  @Prop searchTitle: string = '';
  @Prop actionsExpanded: boolean = false;
  @Prop filterActive: boolean = false;
  @Prop showSearchButton: boolean = false;
  @Prop showBackButton: boolean = false;
  @Prop isSearchResultScene: boolean = false;
  @Prop searchSubmitted: boolean = true;
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
  onKeywordChange: (value: string) => void = () => {
  };
  onSearchModeChange: (mode: ListMode) => void = (_mode: ListMode) => {
  };
  onSearchCategoryChange: (category: number) => void = (_category: number) => {
  };
  onAdvancedEnabledChange: (enabled: boolean) => void = (_enabled: boolean) => {
  };
  onAdvanceSearchChange: (flags: number) => void = (_flags: number) => {
  };
  onMinRatingChange: (rating: number) => void = (_rating: number) => {
  };
  onPageJump: (page: number) => void = (_page: number) => {
  };
  onMenu: () => void = () => {
  };
  onBack: () => void = () => {
  };
  onSearch: () => void = () => {
  };
  onRefresh: () => void = () => {
  };
  onLoadMore: () => void = () => {
  };
  onToggleActions: () => void = () => {
  };
  onFilter: () => void = () => {
  };
  onJump: () => void = () => {
  };
  onRandom: () => void = () => {
  };
  onSelectGallery: (gallery: GalleryInfo) => void = () => {
  };
  initialScrollOffset: number = 0;
  onScrollUpdate: (offset: number) => void = () => {
  };
  @State contentWidth: number = 0;
  @State refreshing: boolean = false;
  @State advancedPanelVisible: boolean = false;
  @State pageJumpDraft: string = '';
  @State jumpPanelVisible: boolean = false;
  @State selectedTagNamespaces: string[] = [];
  @State searchSuggestionItems: SearchSuggestionItem[] = [];
  @State searchSuggestionRevision: number = 0;
  onRefreshPull: (done: () => void) => void = (done: () => void) => {
    done();
  };
  private readonly REFRESH_OFFSET: number = 42;
  @State viewportHeight: number = 0;
  private listScroller: Scroller = new Scroller();
  private loadMorePending: boolean = false;
  private restoredScroll: boolean = false;
  @State toolbarOffsetY: number = 0;
  private toolbarRestoring: boolean = false;
  private galleryRowsDataSource: ArrayDataSource<GalleryInfo[]> = new ArrayDataSource<GalleryInfo[]>([]);
  private barHeight: number = 56; // matches EhNavBar body height
  @StorageProp('statusBarHeight') statusBarHeightPx: number = 0;

  onScrollReset(): void {
    // scrollResetVersion 变化时滚回顶部
    this.snapListToTop();
  }

  onPageChanged(): void {
    this.syncPageJumpDraft();
  }

  onSearchKeywordChanged(): void {
    this.refreshSearchSuggestions();
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  aboutToAppear(): void {
    this.syncContentWidthFromWindow();
    this.syncPageJumpDraft();
    this.refreshSearchSuggestions();
    setTimeout(() => {
      this.syncContentWidthFromWindow();
    }, 0);
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

  private openJumpPanel(): void {
    if (!this.canJump) {
      return;
    }
    this.syncPageJumpDraft();
    this.jumpPanelVisible = true;
  }

  private closeJumpPanel(): void {
    this.jumpPanelVisible = false;
  }

  private totalBarHeight(): number {
    return this.statusBarVp() + this.barHeight;
  }

  private visibleBarHeight(): number {
    return immersiveChromeHeightFromOffset(this.toolbarOffsetY, this.totalBarHeight());
  }

  private toolbarVisible(): boolean {
    return this.visibleBarHeight() > 0;
  }

  private handleScrollFrame(scrollOffset: number): number {
    const yOffset = normalizeGalleryListScrollOffset(this.listScroller.currentOffset().yOffset);
    if (yOffset <= 4) {
      this.toolbarRestoring = false;
      this.toolbarOffsetY = 0;
      return scrollOffset;
    }
    if (scrollOffset > 0 && this.visibleBarHeight() > 0) {
      const previousOffsetY = this.toolbarOffsetY;
      this.toolbarRestoring = false;
      this.toolbarOffsetY = nextFloatingToolbarOffset(this.toolbarOffsetY, scrollOffset, yOffset, this.totalBarHeight());
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

  private triggerLoadMoreIfNear(last: number): void {
    if (this.isLoadingMore || this.loadMorePending) {
      return;
    }
    if (this.galleries.length > 0 && last >= this.galleries.length - 12) {
      this.loadMorePending = true;
      this.onLoadMore();
      // Reset local guard after one frame so rapid scroll events don't queue duplicates
      setTimeout(() => {
        this.loadMorePending = false;
      }, 500);
    }
  }

  private estimateContentHeight(): number {
    const columns = Math.max(1, this.galleryColumnCount());
    const rows = Math.ceil(this.galleries.length / columns);
    const cardHeight = galleryListMode() === 'Thumb' ? Math.max(0, this.galleryCardWidth() / 0.75 + 54) :
      galleryThumbHeight();
    return this.searchResultStripHeight() + rows * cardHeight +
      Math.max(0, rows - 1) * this.galleryCardGap() +
      this.galleryContentPadding();
  }

  private triggerLoadMoreByOffset(offset: number): void {
    const viewportHeight = this.listViewportHeight();
    if (viewportHeight <= 0) {
      return;
    }
    const remaining = this.estimateContentHeight() - offset - viewportHeight;
    if (remaining <= Math.max(720, viewportHeight * 1.3)) {
      this.triggerLoadMoreIfNear(this.galleries.length);
    }
  }

  private contentStartOffset(): number {
    return this.visibleBarHeight();
  }

  private listViewportHeight(): number {
    if (this.viewportHeight <= 0) {
      return 1;
    }
    return Math.max(1, this.viewportHeight - this.contentStartOffset());
  }

  private searchResultStripHeight(): number {
    return 0;
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
    this.onScrollUpdate(0);
  }

  private rememberListOffset(yOffset: number): void {
    if (this.refreshing) {
      return;
    }
    this.onScrollUpdate(yOffset);
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
    const normalizedWidth = Math.floor(width);
    if (normalizedWidth <= 0 || Number.isNaN(normalizedWidth) ||
      Math.abs(this.contentWidth - normalizedWidth) < 1) {
      return;
    }
    this.contentWidth = normalizedWidth;
    rememberMainContentWidthVp(normalizedWidth);
  }

  private syncContentWidthFromWindow(): void {
    if (this.contentWidth >= 240) {
      return;
    }
    this.updateContentWidth(mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value)));
  }

  @Builder
  private searchResultNavBar() {
    Column() {
      Column()
        .height(this.statusBarVp())
        .width('100%')
        .backgroundColor(themePrimaryColor())

      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([themeOnPrimaryText()])
        }
        .width(40)
        .height(40)
        .backgroundColor(themeOnPrimaryActionBackground())
        .flexShrink(0)
        .onClick(() => {
          this.onBack();
        })

        TextInput({ text: this.keyword, placeholder: uiText('Search galleries') })
          .height(38)
          .layoutWeight(1)
          .backgroundColor(themeFieldBackground())
          .borderRadius(19)
          .placeholderColor(themeSecondaryText())
          .fontColor(themePrimaryText())
          .caretColor(themePrimaryColor())
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
            .fontColor([themeOnPrimaryText()])
        }
        .width(40)
        .height(40)
        .backgroundColor(
          this.advancedPanelVisible || this.advancedSearchEnabled ? themeOnPrimaryActionStrongBackground() :
            themeOnPrimaryActionBackground())
        .flexShrink(0)
        .onClick(() => {
          this.toggleAdvancedPanel();
        })
      }
      .width('100%')
      .height(this.barHeight)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(themePrimaryColor())
    }
    .width('100%')
    .translate({ y: this.toolbarOffsetY })
    .opacity(1)
    .visibility(this.toolbarVisible() ? Visibility.Visible : Visibility.Hidden)
    .animation({ duration: 200, curve: Curve.EaseOut })
    .zIndex(10)
  }

  private shouldShowSearchSuggestions(): boolean {
    return this.isSearchResultScene && !this.searchSubmitted;
  }

  private refreshSearchSuggestions(namespaces: string[] = this.selectedTagNamespaces): void {
    this.searchSuggestionItems = buildSearchSuggestions(this.keyword, 0, namespaces);
    this.searchSuggestionRevision++;
  }

  private selectedTagNamespaceKey(): string {
    return this.selectedTagNamespaces.slice().sort().join('|');
  }

  private applySearchSuggestion(suggestion: SearchSuggestionItem): void {
    if (suggestion.kind === 'tag') {
      this.onKeywordChange(applyTagSuggestionToKeyword(this.keyword, suggestion.query));
      this.onSearchModeChange(ListMode.Tag);
      return;
    }
    this.onKeywordChange(suggestion.query);
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

  @Builder
  private searchSuggestionPlaceholder() {
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
          .height(Math.max(240, this.viewportHeight - this.totalBarHeight() - 58))
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(28)
            .fontColor([themePlaceholderColor()])
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
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Refresh({ refreshing: $$this.refreshing }) {
          List({ space: 0, scroller: this.listScroller }) {
            ListItem() {
              Column()
                .height(this.galleryCardGap())
                .width('100%')
                .backgroundColor(Color.Transparent)
            }
            if (this.shouldShowSearchSuggestions()) {
              ListItem() {
                this.searchSuggestionPlaceholder()
              }
            } else if (this.galleries.length === 0) {
              ListItem() {
                GalleryListStateView({
                  statusText: this.statusText,
                  requestUrl: this.requestUrl,
                  onRefresh: this.onRefresh
                })
                  .width('100%')
                  .height('100%')
              }
              .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
            } else {
              // 画廊卡片按行分组，每行 galleryColumnCount() 张
              LazyForEach(this.galleryRowsSource(), (row: GalleryInfo[]) => {
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
                          .onClick(() => {
                            this.onSelectGallery(gallery);
                          })
                      } else {
                        GalleryListRow({ gallery: gallery })
                          .width(this.galleryCardWidth())
                          .margin({
                            right: colIndex < row.length - 1 ? this.galleryCardGap() : 0
                          })
                          .animation({ duration: 220, curve: Curve.EaseOut })
                          .onClick(() => {
                            this.onSelectGallery(gallery);
                          })
                      }
                    }, (gallery: GalleryInfo) => gallery.gid.toString())
                  }
                  .width('100%')
                  .padding({ left: this.galleryContentPadding(), right: this.galleryContentPadding() })
                  .justifyContent(FlexAlign.Start)
                  .animation({ duration: 220, curve: Curve.EaseOut })
                }
                .margin({ bottom: this.galleryCardGap() })
                .reuseId('gallery-row')
                .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
              }, (_row: GalleryInfo[], rowIndex: number) => {
                return this.galleryColumnCount().toString() + ':' + rowIndex.toString() + ':' +
                  this.galleryRowKey(_row);
              })

              // 加载更多指示器
              if (this.isLoadingMore) {
                ListItem() {
                  Row() {
                    LoadingProgress().width(20).height(20).color(themePlaceholderColor())
                    Text(uiText('Loading...')).fontSize(12).fontColor(themePlaceholderColor()).margin({ left: 6 })
                  }
                  .width('100%')
                  .height(40)
                  .justifyContent(FlexAlign.Center)
                }
              }
            }
          }
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true, effectEdge: EffectEdge.START | EffectEdge.END })
          .cachedCount(4)
          .width('100%')
          .height(this.listViewportHeight())
          .onAppear(() => {
            this.syncContentWidthFromWindow();
            if (!this.restoredScroll && this.initialScrollOffset > 0) {
              this.restoredScroll = true;
              setTimeout(() => {
                this.listScroller.scrollTo({ xOffset: 0, yOffset: this.initialScrollOffset });
              }, 80);
            }
          })
          .onScrollFrameBegin((offset: number, _state: ScrollState) => {
            return { offsetRemain: this.handleScrollFrame(offset) };
          })
          .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
            const yOff = normalizeGalleryListScrollOffset(this.listScroller.currentOffset().yOffset);
            this.rememberListOffset(yOff);
            if (!this.shouldShowSearchSuggestions()) {
              this.triggerLoadMoreByOffset(yOff);
            }
          })
          .onScrollStop(() => {
            const yOff = normalizeGalleryListScrollOffset(this.listScroller.currentOffset().yOffset);
            this.rememberListOffset(yOff);
          })
          .onReachEnd(() => {
            if (!this.shouldShowSearchSuggestions()) {
              this.triggerLoadMoreIfNear(this.galleries.length);
            }
          })
        }
        .refreshOffset(this.REFRESH_OFFSET)
        .pullToRefresh(true)
        .pullUpToCancelRefresh(true)
        .onRefreshing(() => {
          this.onRefreshPull(() => {
            this.refreshing = false;
          });
        })
        .width('100%')
        .height(this.listViewportHeight())
        .translate({ y: this.contentStartOffset() })
        .backgroundColor(themePageBackground())
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
      .backgroundColor(themePageBackground())

      // FAB 悬浮按钮
      Column() {
        QuickActionColumn({
          expanded: this.actionsExpanded,
          filterActive: this.filterActive,
          canJump: this.canJump,
          canRandom: this.canRandom,
          onToggle: this.onToggleActions,
          onFilter: this.onFilter,
          onJump: () => {
            this.openJumpPanel();
          },
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
          .backgroundColor(themeScrimColor())
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
          pageFrom: -1,
          pageTo: -1,
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

      if (this.jumpPanelVisible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(themeScrimColor())
          .onClick(() => {
            this.closeJumpPanel();
          })
          .zIndex(13)

        Column({ space: 10 }) {
          Text(uiText('Jump'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .width('100%')
          Row({ space: 8 }) {
            TextInput({ text: this.pageJumpDraft, placeholder: (this.pageIndex + 1).toString() })
              .height(38)
              .layoutWeight(1)
              .type(InputType.Number)
              .fontColor(themePrimaryText())
              .backgroundColor(themeFieldBackground())
              .borderRadius(4)
              .padding({ left: 10, right: 10 })
              .onChange((value: string) => {
                this.pageJumpDraft = value;
              })
              .onSubmit(() => {
                this.submitPageJump();
                this.closeJumpPanel();
              })
            Text('/ ' + (this.totalPages > 0 ? this.totalPages.toString() : '-'))
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
              this.submitPageJump();
              this.closeJumpPanel();
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
          x: this.contentWidth > 0 ? Math.max(12, this.contentWidth - 244) : 100,
          y: this.viewportHeight > 0 ? Math.max(96, this.viewportHeight - 210) : 360
        })
        .zIndex(14)
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
            onMenu: () => {
              this.onMenu();
            },
            onBack: () => {
              this.onBack();
            },
            onSearch: () => {
              this.onSearch();
            },
            onKeywordChange: (v: string) => {
              this.onKeywordChange(v);
            },
            onRefresh: () => {
              this.onRefresh();
            }
          })
        }
      }
      .hitTestBehavior(HitTestMode.Transparent)
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

  private galleryRowsSource(): ArrayDataSource<GalleryInfo[]> {
    this.galleryRowsDataSource.setItems(this.buildRows());
    return this.galleryRowsDataSource;
  }

  private galleryRowKey(row: GalleryInfo[]): string {
    return row.map((gallery: GalleryInfo) => gallery.gid.toString()).join('-');
  }
}

@Component
export struct GalleryListStateView {
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  onRefresh: () => void = () => {
  };

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
          .color(themePrimaryColor())
      } else {
        SymbolGlyph(this.isError() ? $r('sys.symbol.exclamationmark_triangle') : $r('sys.symbol.magnifyingglass'))
          .fontSize(48)
          .fontColor([this.isError() ? themeDangerText() : themeTertiaryText()])
      }

      Text(uiText(this.titleText()))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(themePrimaryText())
        .margin({ top: 14 })

      if (this.statusText.length > 0) {
        Text(uiStatusText(this.statusText))
          .fontSize(13)
          .fontColor(themeSecondaryText())
          .lineHeight(20)
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
          .width('82%')
      }

      if (this.requestUrl.length > 0 && this.isError()) {
        Text(this.requestUrl)
          .fontSize(11)
          .fontColor(themeTertiaryText())
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
          .fontColor(themeOnPrimaryText())
          .backgroundColor(themePrimaryColor())
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
    .backgroundColor(themePageBackground())
  }
}
