import { ALL_CATEGORY, GalleryCategory, GalleryDetail, GalleryInfo, GalleryRoute, GallerySite } from '../model/GalleryModels';
import { ehCookieStore } from '../services/EhCookieStore';
import {
  EhHttpClient,
  GalleryListLoadResult,
} from '../services/EhHttpClient';
import { DEFAULT_ADVANCE_SEARCH, EhUrl, FavListUrlBuilder, ListMode, ListUrlBuilder, buildJumpSeekUrl } from '../services/EhUrl';
import { ehFilterStore } from '../services/EhFilterStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { DetailSearchRequest } from '../services/GalleryDetailActionSupport';
import {
  createGalleryDetailLink,
  createGalleryDetailLinkFromGallery,
  createEmptyGalleryDetailLink,
  GalleryDetailLink,
  initialDetailForLink
} from '../services/GalleryDetailModule';
import { LocalGallerySearchOptions } from '../services/LocalGallerySearch';
import {
  applyAppChromeImmersiveMode,
  enterEmbeddedReaderFullscreen,
  leaveEmbeddedReaderFullscreen,
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
  themeTertiaryText,
  themeTransparentColor
} from '../shared/EhTheme';
import { ArrayDataSource } from '../shared/ListDataSource';
import { EhNavBar } from '../components/NavigationComponents';
import { CategoryBadge, GalleryListRow, GalleryThumb, GalleryThumbCard } from './GalleryCards';
import { GalleryDetailHostScene } from './GalleryDetailHostScene';
import { ReaderSessionScene } from './ReaderHostScene';
import {
  addSearchTagToken,
  buildSearchSuggestions,
  composeSearchKeywordWithInput,
  gallerySuggestionUrl,
  QuickActionColumn,
  removeSearchTagToken,
  SearchAdvancedPanel,
  SearchSuggestionItem,
  SearchSuggestionList,
  SearchSummaryStrip,
  searchKeywordWithoutTagTokens,
  searchTagTokens,
  recordSearchHistory
} from './GallerySearchScenes';
import {
  uiText,
  uiStatusText,
  setActiveBackHandler,
  createEmptyDetail,
  cloneGalleryInfos,
  applyGalleryFilters,
  getAbilityContext,
  immersiveChromeHeightFromOffset,
  nextFloatingToolbarOffset,
  saveGalleryToHistory,
  listModeForRoute,
  routeUsesKeyword,
  defaultKeywordForRoute,
  gallerySearchTitle,
  effectiveListSite,
  galleryListFailureMessage,
  galleryListMode,
  galleryThumbWidth,
  galleryThumbHeight,
  cacheThumbnailImage
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
  accountFilterEnabled: boolean;
  searchMode: ListMode;
  searchCategory: number;
  advancedSearchEnabled: boolean;
  advanceSearch: number;
  minRating: number;
  pageFrom: number;
  pageTo: number;
  searchFilterEnabled: boolean;
  searchAdvancedPanelOpened: boolean;
  searchSubmitted: boolean;
  listScrollOffset: number;
  appendExhausted?: boolean;
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
  filterActive: boolean;
  searchFilterEnabled: boolean;
  searchAdvancedPanelOpened: boolean;
  submitted: boolean;
  sourceRoute: GalleryRoute;
  imagePath: string;
  imageUseSimilarityScan: boolean;
  imageOnlySearchCovers: boolean;
  imageShowExpunged: boolean;
}

const galleryListSceneCache: Map<string, GalleryListSceneCache> = new Map();
const ACCOUNT_DEFAULT_FILTER_DISABLE_FLAGS: number = 0x100 | 0x200 | 0x400;

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
    filterActive: false,
    searchFilterEnabled: true,
    searchAdvancedPanelOpened: false,
    submitted: false,
    sourceRoute: GalleryRoute.Home,
    imagePath: '',
    imageUseSimilarityScan: false,
    imageOnlySearchCovers: false,
    imageShowExpunged: false
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
  initialSearchAdvancedPanelOpened: boolean = false;
  initialImagePath: string = '';
  initialImageUseSimilarityScan: boolean = false;
  initialImageOnlySearchCovers: boolean = false;
  initialImageShowExpunged: boolean = false;
  isSearchResultScene: boolean = false;
  @Prop @Watch('onResetVersionChanged') resetVersion: number = 0;
  useForcedMode: boolean = false;
  forcedMode: ListMode = ListMode.Normal;
  useLocalProvider: boolean = false;
  localPageSize: number = 25;
  localProvider: (keyword: string, pageIndex: number, pageSize: number,
    options: LocalGallerySearchOptions) => Promise<GalleryListLoadResult> =
    (_keyword: string, _pageIndex: number, _pageSize: number,
      _options: LocalGallerySearchOptions): Promise<GalleryListLoadResult> => {
      const result: GalleryListLoadResult = {
        ok: true,
        url: '',
        statusCode: 200,
        message: '',
        pages: 0,
        nextPage: -1,
        nextUrl: '',
        resultCount: '',
        galleries: []
      };
      return Promise.resolve(result);
    };
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
  @State accountFilterEnabled: boolean = true;
  @State searchFilterEnabled: boolean = true;
  @State showSearchResultScene: boolean = false;
  @State searchResultDraft: SearchResultDraft = createEmptySearchResultDraft();
  @State searchMode: ListMode = ListMode.Normal;
  @State searchCategory: number = GalleryCategory.None;
  @State searchAdvancedPanelOpened: boolean = false;
  @State localSearchBarVisible: boolean = false;
  @State advancedSearchEnabled: boolean = false;
  @State advanceSearch: number = DEFAULT_ADVANCE_SEARCH;
  @State minRating: number = -1;
  @State pageFrom: number = -1;
  @State pageTo: number = -1;
  @State searchSubmitted: boolean = false;
  @State showDetail: boolean = false;
  @State showReader: boolean = false;
  @State restoreDetailWithFade: boolean = false;
  @State detailLink: GalleryDetailLink = createEmptyGalleryDetailLink();
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = 'Tap a gallery row to load detail';
  @State detailRequestUrl: string = '';
  @State renderVersion: number = 0;
  @State isLoadingMore: boolean = false;
  @State appendExhausted: boolean = false;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  private listScrollOffset: number = 0;
  private detailScrollOffset: number = 0;

  private cacheKey(): string {
    const mode = this.useForcedMode ? this.forcedMode.toString() : listModeForRoute(this.sourceRoute).toString();
    if (this.useLocalProvider) {
      return this.sourceRoute.toString() + '|local|' + this.follow + '|' + this.initialKeyword + '|' +
        this.localPageSize.toString();
    }
    if (this.isSearchResultScene) {
      return this.sourceRoute.toString() + '|search-result|' + this.keyword + '|' + this.searchMode.toString() + '|' +
        this.searchCategory.toString() + '|' + (this.advancedSearchEnabled ? '1' : '0') + '|' +
        this.advanceSearch.toString() + '|' + this.minRating.toString() + '|' +
        this.initialImagePath + '|' + (this.initialImageUseSimilarityScan ? 'sim' : 'nosim') + '|' +
        (this.initialImageOnlySearchCovers ? 'covers' : 'all') + '|' +
        (this.initialImageShowExpunged ? 'exp' : 'noexp') + '|' +
        (this.accountFilterEnabled ? 'account-filter-on' : 'account-filter-off') + '|' +
        (this.searchFilterEnabled ? 'search-filter-on' : 'search-filter-off') + '|' +
        (this.searchAdvancedPanelOpened ? 'advanced-panel-opened' : 'advanced-panel-closed');
    }
    return this.sourceRoute.toString() + '|' + mode + '|' + this.follow + '|' + this.initialKeyword + '|' +
      this.initialSearchMode.toString() + '|' + this.initialSearchCategory.toString() + '|' +
      (this.initialAdvancedSearchEnabled ? '1' : '0') + '|' + this.initialAdvanceSearch.toString() + '|' +
      this.initialMinRating.toString() + '|' + this.initialPageFrom.toString() + '|' + this.initialPageTo.toString() +
      '|' + (this.accountFilterEnabled ? 'account-filter-on' : 'account-filter-off');
  }

  private restoreListCache(): boolean {
    if (this.isSearchResultScene) {
      return false;
    }
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
    this.filterActive = this.isSearchResultScene ? false : cache.filterActive;
    this.accountFilterEnabled = cache.accountFilterEnabled !== false;
    this.searchFilterEnabled = cache.searchFilterEnabled !== false;
    this.searchAdvancedPanelOpened = cache.searchAdvancedPanelOpened === true;
    this.localSearchBarVisible = this.useLocalProvider && cache.searchSubmitted !== true;
    this.searchMode = cache.searchMode;
    this.searchCategory = cache.searchCategory;
    this.advancedSearchEnabled = cache.advancedSearchEnabled;
    this.advanceSearch = cache.advanceSearch;
    this.minRating = cache.minRating;
    this.pageFrom = cache.pageFrom;
    this.pageTo = cache.pageTo;
    this.searchSubmitted = cache.searchSubmitted === true;
    this.listScrollOffset = cache.listScrollOffset;
    this.appendExhausted = cache.appendExhausted === true;
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
      accountFilterEnabled: this.accountFilterEnabled,
      searchFilterEnabled: this.searchFilterEnabled,
      searchAdvancedPanelOpened: this.searchAdvancedPanelOpened,
      searchMode: this.searchMode,
      searchCategory: this.searchCategory,
      advancedSearchEnabled: this.advancedSearchEnabled,
      advanceSearch: this.advanceSearch,
      minRating: this.minRating,
      pageFrom: this.pageFrom,
      pageTo: this.pageTo,
      searchSubmitted: this.searchSubmitted,
      listScrollOffset: this.listScrollOffset,
      appendExhausted: this.appendExhausted
    });
  }

  private resetListScroll(): void {
    this.listScrollOffset = 0;
    this.saveListCache();
  }

  private syncAccountFilterSetting(): void {
    this.accountFilterEnabled = ehSettingsStore.getValue('use_account_default_filter', 'On') !== 'Off';
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
      this.filterActive = this.isSearchResultScene ? false : this.searchResultDraft.filterActive;
      this.searchFilterEnabled = this.isSearchResultScene ? this.searchResultDraft.searchFilterEnabled : true;
      this.searchAdvancedPanelOpened = this.isSearchResultScene ?
        (this.searchResultDraft.searchAdvancedPanelOpened || this.initialSearchAdvancedPanelOpened) : false;
      this.searchSubmitted = !this.isSearchResultScene || this.initialSearchSubmitted;
      this.localSearchBarVisible = false;
    }
    const context = getAbilityContext();
    if (context !== undefined) {
      Promise.all([
        ehCookieStore.load(context),
        ehFilterStore.load(context),
        ehSettingsStore.load(context)
      ]).catch((error: Error) => {
        this.statusText = 'Cookie load failed, using current session: ' + error.message;
      }).finally(() => {
        const previousAccountFilterEnabled = this.accountFilterEnabled;
        this.syncAccountFilterSetting();
        if (!this.isSearchResultScene && previousAccountFilterEnabled !== this.accountFilterEnabled && !this.useLocalProvider) {
          this.hasFirstRefresh = false;
        }
        if (this.isSearchResultScene && this.initialSearchSubmitted && !this.hasFirstRefresh) {
          this.searchSubmitted = true;
        }
        if (!this.isSearchResultScene || this.searchSubmitted) {
          this.firstRefresh();
        }
      });
    } else {
      if (this.isSearchResultScene && this.initialSearchSubmitted && !this.hasFirstRefresh) {
        this.searchSubmitted = true;
      }
      if (!this.isSearchResultScene || this.searchSubmitted) {
        this.firstRefresh();
      }
    }
    setActiveBackHandler(() => this.handleSystemBack());
  }

  aboutToDisappear(): void {
    this.saveListCache();
  }

  onResetVersionChanged(): void {
    this.resetToTopLevel();
  }

  private handleSystemBack(): boolean {
    if (this.showReader) {
      this.closeReader();
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
    if (this.useLocalProvider && this.localSearchBarVisible) {
      this.closeLocalSearchBar();
      return true;
    }
    if (this.isSearchResultScene) {
      this.onBack();
      return true;
    }
    return false;
  }

  private resetToTopLevel(): void {
    if (this.showReader) {
      leaveEmbeddedReaderFullscreen();
    }
    this.showReader = false;
    this.showDetail = false;
    this.restoreDetailWithFade = false;
    this.detailLink = createEmptyGalleryDetailLink();
    this.detail = createEmptyDetail();
    this.detailStatus = 'Tap a gallery row to load detail';
    this.detailRequestUrl = '';
    this.detailScrollOffset = 0;
    this.showSearchResultScene = false;
    this.searchResultDraft = createEmptySearchResultDraft();
    this.localSearchBarVisible = false;
    this.fabExpanded = false;
    this.restoreBackHandler();
    this.renderVersion++;
  }

  private firstRefresh(): void {
    if (this.useLocalProvider && (this.showDetail || this.showReader)) {
      return;
    }
    if (this.hasFirstRefresh && !this.useLocalProvider) {
      return;
    }
    this.hasFirstRefresh = true;
    this.loadListPage(0, this.useLocalProvider && this.galleries.length > 0);
  }

  private loadListPage(pageIndex: number, preserveExisting: boolean = false, onDone?: () => void): void {
    if (this.useLocalProvider) {
      this.loadLocal(pageIndex, preserveExisting, onDone);
      return;
    }
    this.loadRemote(pageIndex, preserveExisting, onDone);
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
    this.appendExhausted = false;
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
      this.galleries = this.visibleRemoteGalleries(result.galleries);
      this.statusText = result.ok ? result.message : galleryListFailureMessage(result, this.activeSite);
      this.totalPages = result.pages;
      this.nextUrl = result.nextUrl;
      this.resultCount = result.resultCount;
      this.appendExhausted = this.isAppendExhausted(result, pageIndex, this.galleries.length);
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

  private loadRemoteUrl(url: string, preserveExisting: boolean = false, onDone?: () => void): void {
    const absoluteUrl = this.absoluteListUrl(url);
    if (absoluteUrl.length === 0) {
      this.statusText = 'No other page to jump to';
      if (onDone !== undefined) {
        onDone();
      }
      return;
    }
    this.pageIndex = 0;
    this.statusText = 'Loading...';
    if (!preserveExisting) {
      this.resultCount = '';
      this.galleries = [];
    }
    this.nextUrl = '';
    this.isLoadingMore = false;
    this.appendExhausted = false;
    this.resetListScroll();
    this.scrollResetVersion++;
    this.renderVersion++;
    this.closeDetail();
    this.saveListCache();

    this.client.loadGalleryListUrl(absoluteUrl, this.activeSite, this.includeAccountUConfig()).then((result: GalleryListLoadResult) => {
      this.requestUrl = result.url;
      this.galleries = this.visibleRemoteGalleries(result.galleries);
      this.statusText = result.ok ? result.message : galleryListFailureMessage(result, this.activeSite);
      this.totalPages = result.pages;
      this.nextUrl = result.nextUrl;
      this.resultCount = result.resultCount;
      this.appendExhausted = this.isAppendExhausted(result, this.pageIndex, this.galleries.length);
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

  private loadLocal(pageIndex: number, preserveExisting: boolean = false, onDone?: () => void): void {
    this.activeSite = effectiveListSite(this.sourceRoute);
    this.pageIndex = pageIndex;
    this.statusText = 'Loading...';
    if (!preserveExisting) {
      this.resultCount = '';
      this.galleries = [];
    }
    this.nextUrl = '';
    this.isLoadingMore = false;
    this.appendExhausted = false;
    if (pageIndex === 0) {
      this.resetListScroll();
      this.scrollResetVersion++;
    }
    this.renderVersion++;
    this.closeDetail();
    this.saveListCache();

    this.localProvider(this.keyword.trim(), pageIndex, this.localPageSize, this.localSearchOptions())
      .then((result: GalleryListLoadResult) => {
      this.requestUrl = result.url;
      this.galleries = this.visibleRemoteGalleries(result.galleries);
      this.statusText = result.ok ? result.message : result.message;
      this.totalPages = result.pages;
      this.nextUrl = result.nextUrl;
      this.resultCount = result.resultCount;
      this.appendExhausted = this.isAppendExhausted(result, pageIndex, this.galleries.length);
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
    if (this.appendExhausted) {
      this.statusText = uiText('All pages loaded');
      return;
    }
    if (this.useLocalProvider) {
      this.loadAppendLocalPage();
      return;
    }
    // Only stop if we have confirmed total page count AND already at the last page
    if (this.nextUrl.length === 0 && this.totalPages > 0 && this.pageIndex >= this.totalPages - 1) {
      this.statusText = uiText('All pages loaded');
      this.appendExhausted = true;
      return;
    }
    const nextPage = this.pageIndex + 1;
    this.isLoadingMore = true;

    const request =
      this.nextUrl.length > 0 ?
        this.client.loadGalleryListUrl(this.absoluteListUrl(this.nextUrl), this.activeSite, this.includeAccountUConfig()) :
        this.loadRoutePageWithFallback(nextPage);

    request.then((result: GalleryListLoadResult) => {
      this.requestUrl = result.url;
      const newGalleries = this.visibleRemoteGalleries(result.galleries);
      if (newGalleries.length === 0) {
        // Empty page = reached the end even if we don't know total
        this.statusText = uiText('All pages loaded');
        this.appendExhausted = true;
        this.isLoadingMore = false;
        this.saveListCache();
        return;
      }
      const existingGids: Set<number> = new Set(this.galleries.map((g: GalleryInfo) => g.gid));
      const unique: GalleryInfo[] = newGalleries.filter((g: GalleryInfo) => !existingGids.has(g.gid));
      if (unique.length === 0) {
        this.statusText = uiText('All pages loaded');
        this.appendExhausted = true;
        this.isLoadingMore = false;
        this.saveListCache();
        return;
      }
      this.galleries = this.galleries.concat(unique);
      this.pageIndex = nextPage;
      if (result.pages > 0) {
        this.totalPages = result.pages;
      }
      this.nextUrl = result.nextUrl;
      this.resultCount = result.resultCount;
      this.statusText = result.ok ? result.message : galleryListFailureMessage(result, this.activeSite);
      this.appendExhausted = this.isAppendExhausted(result, nextPage, unique.length);
      this.isLoadingMore = false;
      this.saveListCache();
    }).catch((error: Error) => {
      this.statusText = 'Load more failed: ' + error.message;
      this.isLoadingMore = false;
      this.saveListCache();
    });
  }

  private localSearchOptions(): LocalGallerySearchOptions {
    return {
      mode: this.searchMode,
      category: this.searchCategory,
      advancedEnabled: this.advancedSearchEnabled,
      advancedPanelOpened: this.searchAdvancedPanelOpened,
      advanceSearch: this.advanceSearch,
      minRating: this.minRating
    };
  }

  private loadAppendLocalPage(): void {
    if (this.appendExhausted) {
      this.statusText = uiText('All pages loaded');
      return;
    }
    if (this.nextUrl.length === 0 && this.totalPages > 0 && this.pageIndex >= this.totalPages - 1) {
      this.statusText = uiText('All pages loaded');
      this.appendExhausted = true;
      return;
    }
    const nextPage = this.pageIndex + 1;
    this.isLoadingMore = true;
    this.localProvider(this.keyword.trim(), nextPage, this.localPageSize, this.localSearchOptions())
      .then((result: GalleryListLoadResult) => {
      this.requestUrl = result.url;
      const newGalleries = this.visibleRemoteGalleries(result.galleries);
      if (newGalleries.length === 0) {
        this.statusText = uiText('All pages loaded');
        this.appendExhausted = true;
        this.isLoadingMore = false;
        this.saveListCache();
        return;
      }
      const existingGids: Set<number> = new Set(this.galleries.map((g: GalleryInfo) => g.gid));
      const unique: GalleryInfo[] = newGalleries.filter((g: GalleryInfo) => !existingGids.has(g.gid));
      if (unique.length === 0) {
        this.statusText = uiText('All pages loaded');
        this.appendExhausted = true;
        this.isLoadingMore = false;
        this.saveListCache();
        return;
      }
      this.galleries = this.galleries.concat(unique);
      this.pageIndex = nextPage;
      if (result.pages > 0) {
        this.totalPages = result.pages;
      }
      this.nextUrl = result.nextUrl;
      this.resultCount = result.resultCount;
      this.statusText = result.ok ? result.message : result.message;
      this.appendExhausted = this.isAppendExhausted(result, nextPage, unique.length);
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

  private visibleRemoteGalleries(galleries: GalleryInfo[]): GalleryInfo[] {
    const cloned = cloneGalleryInfos(galleries);
    return this.isSearchResultScene ? cloned : applyGalleryFilters(cloned);
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
    builder.keyword = (this.isSearchResultScene || routeUsesKeyword(this.sourceRoute)) ? this.keyword : '';
    builder.pageIndex = pageIndex;
    const routeMode = this.useForcedMode ? this.forcedMode : listModeForRoute(this.sourceRoute);
    builder.mode = this.searchModeForRoute(routeMode, builder.keyword);
    builder.follow = this.follow;
    builder.category = this.requestCategoryForMode(builder.mode);
    builder.imagePath = this.initialImagePath;
    builder.useSimilarityScan = this.initialImageUseSimilarityScan;
    builder.onlySearchCovers = this.initialImageOnlySearchCovers;
    builder.showExpunged = this.initialImageShowExpunged;
    if (this.shouldApplySearchFilters() && this.advancedSearchEnabled && this.searchSupportsAdvanced(builder.mode)) {
      builder.advanceSearch = this.advanceSearch;
      builder.minRating = this.minRating;
      builder.pageFrom = this.pageFrom;
      builder.pageTo = this.pageTo;
    }
    if (this.isSearchResultScene && !this.searchFilterEnabled && this.searchSupportsAdvanced(builder.mode)) {
      const baseFlags = builder.advanceSearch === -1 ? 0 : builder.advanceSearch;
      builder.advanceSearch = baseFlags | ACCOUNT_DEFAULT_FILTER_DISABLE_FLAGS;
    }
    if (!this.isSearchResultScene && !this.includeAccountUConfig() && this.searchSupportsAdvanced(builder.mode)) {
      builder.advanceSearch =
        (builder.advanceSearch === -1 ? 0 : builder.advanceSearch) | ACCOUNT_DEFAULT_FILTER_DISABLE_FLAGS;
    }
    this.requestUrl = builder.build(site);
    return this.client.loadGalleryList(builder, site, this.includeAccountUConfig());
  }

  private includeAccountUConfig(): boolean {
    return this.isSearchResultScene || this.accountFilterEnabled;
  }

  private searchModeForRoute(routeMode: ListMode, keyword: string): ListMode {
    if (!this.isSearchResultScene && this.filterActive && keyword.trim().length > 0) {
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

  private shouldApplySearchFilters(): boolean {
    return !this.isSearchResultScene || this.searchAdvancedPanelOpened;
  }

  private requestCategoryForMode(mode: ListMode): number {
    if (this.isSearchResultScene && this.searchAdvancedPanelOpened && this.searchSupportsAdvanced(mode)) {
      return this.searchCategory === GalleryCategory.None ? ALL_CATEGORY : this.searchCategory;
    }
    if (!this.isSearchResultScene && this.shouldApplySearchFilters() && this.searchCategory !== GalleryCategory.None) {
      return this.searchCategory;
    }
    if (!this.isSearchResultScene && this.searchSupportsAdvanced(mode) && !this.accountFilterEnabled) {
      return ALL_CATEGORY;
    }
    return GalleryCategory.None;
  }

  private searchSupportsAdvanced(mode: ListMode): boolean {
    return mode === ListMode.Normal || mode === ListMode.Subscription || mode === ListMode.Tag ||
      mode === ListMode.WhatsHot;
  }

  private applySearch(): void {
    this.fabExpanded = false;
    this.rememberSearchKeyword(this.keyword);
    const directGallery = gallerySuggestionUrl(this.keyword);
    if (directGallery !== null) {
      this.searchSubmitted = true;
      this.hasFirstRefresh = true;
      this.resetListScroll();
      this.openDetailByToken(directGallery.gid, directGallery.token);
      return;
    }
    this.searchSubmitted = true;
    this.hasFirstRefresh = true;
    this.resetListScroll();
    this.loadListPage(0);
  }

  private rememberSearchKeyword(keyword: string): void {
    recordSearchHistory(keyword);
  }

  private openSearchScene(): void {
    this.fabExpanded = false;
    if (this.useLocalProvider) {
      this.openLocalSearchBar();
      return;
    }
    this.searchResultDraft = {
      keyword: this.keyword.trim(),
      mode: this.searchMode,
      category: this.searchCategory,
      advancedEnabled: this.advancedSearchEnabled,
      advanceSearch: this.advanceSearch,
      minRating: this.minRating,
      pageFrom: -1,
      pageTo: -1,
      filterActive: false,
      searchFilterEnabled: true,
      searchAdvancedPanelOpened: false,
      submitted: false,
      sourceRoute: this.sourceRoute,
      imagePath: '',
      imageUseSimilarityScan: false,
      imageOnlySearchCovers: false,
      imageShowExpunged: false
    };
    this.showSearchResultScene = true;
  }

  private openLocalSearchBar(): void {
    this.localSearchBarVisible = true;
    this.searchSubmitted = false;
    this.galleries = [];
    this.resultCount = '';
    this.nextUrl = '';
    this.statusText = '';
    this.saveListCache();
  }

  private closeLocalSearchBar(): void {
    this.localSearchBarVisible = false;
    this.searchSubmitted = true;
    this.keyword = '';
    this.searchMode = ListMode.Normal;
    this.searchCategory = GalleryCategory.None;
    this.searchAdvancedPanelOpened = false;
    this.advancedSearchEnabled = false;
    this.advanceSearch = DEFAULT_ADVANCE_SEARCH;
    this.minRating = -1;
    this.hasFirstRefresh = false;
    this.saveListCache();
    this.loadListPage(0);
  }

  private closeSearchResultScene(): void {
    this.showSearchResultScene = false;
    setTimeout(() => {
      setActiveBackHandler(() => this.handleSystemBack());
    }, 0);
  }

  private toggleFilter(): void {
    if (this.isSearchResultScene) {
      this.toggleSearchFilterEnabled();
      return;
    }
    this.accountFilterEnabled = !this.accountFilterEnabled;
    this.fabExpanded = false;
    ehSettingsStore.setValue('use_account_default_filter', this.accountFilterEnabled ? 'On' : 'Off');
    this.statusText = this.accountFilterEnabled ? 'Account filters enabled' : 'Account filters disabled';
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch((error: Error) => {
        this.statusText = 'Save setting failed: ' + error.message;
        this.saveListCache();
      });
    }
    this.saveListCache();
    this.loadListPage(0, false);
  }

  private toggleSearchFilterEnabled(): void {
    const nextEnabled = !this.searchFilterEnabled;
    this.searchFilterEnabled = nextEnabled;
    this.advanceSearch = nextEnabled ? (this.advanceSearch & ~ACCOUNT_DEFAULT_FILTER_DISABLE_FLAGS) :
      (this.advanceSearch | ACCOUNT_DEFAULT_FILTER_DISABLE_FLAGS);
    this.fabExpanded = false;
    this.statusText = this.searchFilterEnabled ? 'Search filters enabled' : 'Search filters disabled';
    this.searchSubmitted = true;
    this.saveListCache();
    this.loadListPage(0, false);
  }

  private jumpGalleryPage(): void {
    this.fabExpanded = false;
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
    this.restoreDetailWithFade = false;
    this.showDetail = true;
    const detailLink = createGalleryDetailLinkFromGallery(gallery, this.activeSite, this.requestUrl);
    this.detailLink = detailLink;
    this.detail = initialDetailForLink(detailLink);
    this.detailStatus = '';
    this.detailRequestUrl = detailLink.url;
    this.renderVersion++;
  }

  private isAppendExhausted(result: GalleryListLoadResult, loadedPageIndex: number, addedCount: number): boolean {
    if (addedCount <= 0) {
      return true;
    }
    if (result.nextUrl.length > 0) {
      return false;
    }
    if (result.nextPage >= 0 && result.nextPage !== loadedPageIndex) {
      return false;
    }
    return result.pages <= 0 || loadedPageIndex >= result.pages - 1;
  }

  private openDetailByToken(gid: number, token: string): void {
    this.restoreDetailWithFade = false;
    this.showDetail = true;
    const detailLink = createGalleryDetailLink(gid, token, 'Gallery ' + gid.toString(), this.activeSite, this.requestUrl);
    this.detailLink = detailLink;
    this.detail = initialDetailForLink(detailLink);
    this.detailStatus = '';
    this.detailRequestUrl = detailLink.url;
    this.renderVersion++;
  }

  private closeDetail(): void {
    this.restoreDetailWithFade = false;
    this.showDetail = false;
    this.showReader = false;
    this.detailLink = createEmptyGalleryDetailLink();
    this.detail = createEmptyDetail();
    this.detailStatus = 'Tap a gallery row to load detail';
    this.detailRequestUrl = '';
    this.detailScrollOffset = 0;
    this.renderVersion++;
  }

  private closeReader(): void {
    this.restoreDetailWithFade = this.showDetail;
    this.showReader = false;
    leaveEmbeddedReaderFullscreen();
    this.restoreBackHandler();
    this.renderVersion++;
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

  private openSearchResult(request: DetailSearchRequest): void {
    this.showReader = false;
    this.showSearchResultScene = false;
    this.searchResultDraft = {
      keyword: request.keyword,
      mode: request.mode,
      category: GalleryCategory.None,
      advancedEnabled: false,
      advanceSearch: DEFAULT_ADVANCE_SEARCH,
      minRating: -1,
      pageFrom: -1,
      pageTo: -1,
      filterActive: false,
      searchFilterEnabled: true,
      searchAdvancedPanelOpened: false,
      submitted: true,
      sourceRoute: GalleryRoute.Home,
      imagePath: request.imagePath,
      imageUseSimilarityScan: request.useSimilarityScan,
      imageOnlySearchCovers: request.onlySearchCovers,
      imageShowExpunged: request.showExpunged
    };
    this.detailStatus = request.title;
    this.fabExpanded = false;
    setTimeout(() => {
      this.showSearchResultScene = true;
    }, 0);
  }

  build() {
    Column() {
      if (this.showSearchResultScene) {
        GalleryListScene({
          sceneTitle: this.searchResultDraft.keyword.length > 0 ? this.searchResultDraft.keyword : 'Search',
          listMode: 'Search',
          sourceRoute: this.searchResultDraft.sourceRoute,
          initialKeyword: this.searchResultDraft.keyword,
          initialSearchMode: this.searchResultDraft.mode,
          initialSearchCategory: this.searchResultDraft.category,
          initialAdvancedSearchEnabled: this.searchResultDraft.advancedEnabled,
          initialAdvanceSearch: this.searchResultDraft.advanceSearch,
          initialMinRating: this.searchResultDraft.minRating,
          initialPageFrom: this.searchResultDraft.pageFrom,
          initialPageTo: this.searchResultDraft.pageTo,
          initialSearchSubmitted: this.searchResultDraft.submitted,
          initialSearchAdvancedPanelOpened: this.searchResultDraft.searchAdvancedPanelOpened,
          initialImagePath: this.searchResultDraft.imagePath,
          initialImageUseSimilarityScan: this.searchResultDraft.imageUseSimilarityScan,
          initialImageOnlySearchCovers: this.searchResultDraft.imageOnlySearchCovers,
          initialImageShowExpunged: this.searchResultDraft.imageShowExpunged,
          isSearchResultScene: true,
          onBack: () => {
            this.closeSearchResultScene();
          }
        })
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.move(TransitionEdge.END).animation({ duration: 260, curve: Curve.EaseOut }),
            TransitionEffect.move(TransitionEdge.END).animation({ duration: 220, curve: Curve.EaseIn })))
      } else if (this.showReader) {
        ReaderSessionScene({
          restoreAppChromeOnExit: true,
          onBack: () => {
            this.closeReader();
          }
        })
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
            .animation({ duration: 300, curve: Curve.EaseOut }))
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          GalleryListContent({
            sceneTitle: this.sceneTitle,
            listMode: this.listMode,
            keyword: this.keyword,
            searchTitle: this.useLocalProvider && this.keyword.trim().length === 0 ? this.sceneTitle :
              gallerySearchTitle(this.sourceRoute, this.keyword, this.filterActive),
            actionsExpanded: this.fabExpanded,
            filterActive: this.filterActive,
            accountFilterEnabled: this.accountFilterEnabled,
            searchFilterEnabled: this.searchFilterEnabled,
            showSearchButton: (routeUsesKeyword(this.sourceRoute) || this.useLocalProvider) && !this.isSearchResultScene,
            showBackButton: this.isSearchResultScene,
            searchPlaceholder: this.useLocalProvider ? 'Search history' : 'Search galleries',
            isSearchResultScene: this.isSearchResultScene,
            useLocalSearchBar: this.useLocalProvider && this.localSearchBarVisible,
            searchSubmitted: this.searchSubmitted,
            searchModeValue: this.searchMode,
            searchCategory: this.searchCategory,
            advancedSearchEnabled: this.advancedSearchEnabled,
            advanceSearch: this.advanceSearch,
            minRating: this.minRating,
            pageIndex: this.pageIndex,
            totalPages: this.totalPages,
            resultCount: this.resultCount,
            canJump: this.totalPages > 1 || this.totalPages < 0 || this.nextUrl.length > 0,
            canRandom: this.galleries.length > 0,
            statusText: this.statusText,
            requestUrl: this.requestUrl,
            isLoadingMore: this.isLoadingMore,
            galleries: this.galleries,
            onKeywordChange: (value: string) => {
              if (value === this.keyword) {
                return;
              }
              this.keyword = value;
              if (this.isSearchResultScene || this.useLocalProvider) {
                this.searchSubmitted = false;
                this.galleries = [];
                this.resultCount = '';
                this.nextUrl = '';
                this.statusText = '';
                this.saveListCache();
              }
            },
            onSearchFocus: () => {
            },
            onSearchModeChange: (mode: ListMode) => {
              if (mode === this.searchMode) {
                return;
              }
              this.searchMode = mode;
              if (this.isSearchResultScene || this.useLocalProvider) {
                this.searchSubmitted = false;
              }
            },
            onSearchCategoryChange: (category: number) => {
              if (category === this.searchCategory) {
                return;
              }
              this.searchAdvancedPanelOpened = true;
              this.searchCategory = category;
              if (this.isSearchResultScene || this.useLocalProvider) {
                this.searchSubmitted = false;
              }
            },
            onAdvancedEnabledChange: (enabled: boolean) => {
              if (enabled === this.advancedSearchEnabled) {
                return;
              }
              this.searchAdvancedPanelOpened = true;
              this.advancedSearchEnabled = enabled;
              if (this.isSearchResultScene || this.useLocalProvider) {
                this.searchSubmitted = false;
              }
            },
            onAdvanceSearchChange: (flags: number) => {
              if (flags === this.advanceSearch) {
                return;
              }
              this.searchAdvancedPanelOpened = true;
              this.advanceSearch = flags;
              if (this.isSearchResultScene || this.useLocalProvider) {
                this.searchSubmitted = false;
              }
            },
            onMinRatingChange: (rating: number) => {
              if (rating === this.minRating) {
                return;
              }
              this.searchAdvancedPanelOpened = true;
              this.minRating = rating;
              if (this.isSearchResultScene || this.useLocalProvider) {
                this.searchSubmitted = false;
              }
            },
            onPageJump: (page: number) => {
              this.loadListPage(Math.max(0, page - 1));
            },
            onSeekJump: (appendParam: string) => {
              const targetUrl = buildJumpSeekUrl(this.nextUrl.length > 0 ? this.absoluteListUrl(this.nextUrl) :
                this.requestUrl, appendParam);
              if (targetUrl.length === 0) {
                this.statusText = 'No other page to jump to';
                return;
              }
              this.fabExpanded = false;
              this.loadRemoteUrl(targetUrl);
            },
            onMenu: () => {
              this.onMenu();
            },
            onBack: () => {
              if (this.useLocalProvider && this.localSearchBarVisible) {
                this.closeLocalSearchBar();
              } else {
                this.onBack();
              }
            },
            onSearch: () => {
              if (this.useLocalProvider && !this.localSearchBarVisible) {
                this.openLocalSearchBar();
              } else if (this.isSearchResultScene || this.useLocalProvider) {
                this.applySearch();
              } else {
                this.openSearchScene();
              }
            },
            onRefresh: () => {
              if ((this.isSearchResultScene || this.useLocalProvider) && !this.searchSubmitted) {
                this.applySearch();
                return;
              }
              this.loadListPage(0, this.galleries.length > 0);
            },
            onRefreshPull: (done: () => void) => {
              if ((this.isSearchResultScene || this.useLocalProvider) && !this.searchSubmitted) {
                this.applySearch();
                done();
                return;
              }
              this.loadListPage(0, this.galleries.length > 0, done);
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
            onAdvancedPanelOpen: () => {
              this.searchAdvancedPanelOpened = true;
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

          if (this.showDetail) {
            GalleryDetailHostScene({
              detailLink: this.detailLink,
              listRequestUrl: this.requestUrl,
              initialDetailScrollOffset: this.detailScrollOffset,
              onBack: () => {
                this.closeDetail();
              },
              onShowEmbeddedReader: () => {
                enterEmbeddedReaderFullscreen();
                this.showReader = true;
              },
              onOpenSearch: (request: DetailSearchRequest) => {
                this.openSearchResult(request);
              },
              onDetailLoaded: (detail: GalleryDetail) => {
                this.detail = detail;
              },
              onDetailScrollUpdate: (offset: number) => {
                this.detailScrollOffset = offset;
              }
            })
              .width('100%')
              .height('100%')
              .transition(this.restoreDetailWithFade ?
                TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }) :
                TransitionEffect.move(TransitionEdge.END).animation({ duration: 300, curve: Curve.EaseOut }))
          }
        }
        .width('100%')
        .height('100%')
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
  @Prop accountFilterEnabled: boolean = true;
  @Prop searchFilterEnabled: boolean = true;
  @Prop showSearchButton: boolean = false;
  @Prop showBackButton: boolean = false;
  @Prop searchPlaceholder: string = 'Search galleries';
  @Prop isSearchResultScene: boolean = false;
  @Prop useLocalSearchBar: boolean = false;
  @Prop searchSubmitted: boolean = true;
  @Prop searchModeValue: ListMode = ListMode.Normal;
  @Prop searchCategory: number = GalleryCategory.None;
  @Prop advancedSearchEnabled: boolean = false;
  @Prop advanceSearch: number = DEFAULT_ADVANCE_SEARCH;
  @Prop minRating: number = -1;
  @Prop @Watch('onPageChanged') pageIndex: number = 0;
  @Prop totalPages: number = 0;
  @Prop resultCount: string = '';
  @Prop canJump: boolean = false;
  @Prop canRandom: boolean = false;
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  @Prop isLoadingMore: boolean = false;
  @Prop @Watch('onGalleriesChanged') galleries: GalleryInfo[] = [];
  @Prop @Watch('onScrollReset') scrollResetVersion: number = 0;
  onKeywordChange: (value: string) => void = () => {
  };
  onSearchFocus: () => void = () => {
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
  onSeekJump: (appendParam: string) => void = (_appendParam: string) => {
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
  onAdvancedPanelOpen: () => void = () => {
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
  @State seekYearDraft: string = '';
  @State seekMonthDraft: string = '';
  @State seekDayDraft: string = '';
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
  @State private contentOpacity: number = 1;
  @State toolbarOffsetY: number = 0;
  private toolbarRestoring: boolean = false;
  private galleryRowsDataSource: ArrayDataSource<GalleryInfo[]> = new ArrayDataSource<GalleryInfo[]>([]);
  private galleryRowStructureKeys: string[] = [];
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

  onGalleriesChanged(): void {
    this.refreshGalleryRows();
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  aboutToAppear(): void {
    this.galleryRowsDataSource.setPrefetchCallback((row: GalleryInfo[]) => {
      for (let i = 0; i < row.length; i++) {
        const thumb = row[i].thumb;
        if (thumb !== undefined && thumb.length > 0) {
          cacheThumbnailImage(thumb, () => {}, () => {});
        }
      }
    });
    this.syncContentWidthFromWindow();
    this.refreshGalleryRows();
    this.syncPageJumpDraft();
    this.refreshSearchSuggestions();
    if (this.initialScrollOffset > 0) {
      this.contentOpacity = 0;
    }
    setTimeout(() => {
      this.syncContentWidthFromWindow();
      this.refreshGalleryRows();
    }, 0);
  }

  private syncPageJumpDraft(): void {
    this.pageJumpDraft = (this.pageIndex + 1).toString();
  }

  private syncSeekDateDraft(): void {
    const now = new Date();
    this.seekYearDraft = now.getFullYear().toString();
    this.seekMonthDraft = (now.getMonth() + 1).toString();
    this.seekDayDraft = now.getDate().toString();
  }

  private submitPageJump(): void {
    if (this.totalPages < 0) {
      return;
    }
    const parsed = Number.parseInt(this.pageJumpDraft);
    if (Number.isNaN(parsed) || parsed <= 0) {
      this.syncPageJumpDraft();
      return;
    }
    const maxPage = this.totalPages > 0 ? this.totalPages : parsed;
    this.onPageJump(Math.max(1, Math.min(parsed, maxPage)));
  }

  private submitSeekDate(): void {
    const year = Number.parseInt(this.seekYearDraft);
    const month = Number.parseInt(this.seekMonthDraft);
    const day = Number.parseInt(this.seekDayDraft);
    if (Number.isNaN(year) || Number.isNaN(month) || Number.isNaN(day) ||
      year < 2000 || month < 1 || month > 12 || day < 1 || day > 31) {
      this.syncSeekDateDraft();
      return;
    }
    this.onSeekJump('seek=' + year.toString() + '-' + month.toString() + '-' + day.toString());
  }

  private useSeekJumpPanel(): boolean {
    return this.totalPages < 0;
  }

  private jumpSeekPresets(): string[] {
    return ['1d', '3d', '1w', '2w', '1m', '6m', '1y', '2y'];
  }

  private toggleAdvancedPanel(): void {
    if (this.isSearchResultScene) {
      this.onAdvancedPanelOpen();
    }
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
    if (this.useSeekJumpPanel() &&
      (this.seekYearDraft.length === 0 || this.seekMonthDraft.length === 0 || this.seekDayDraft.length === 0)) {
      this.syncSeekDateDraft();
    }
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
    if (this.galleries.length > 0 && last >= this.galleries.length - 24) {
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
    if (remaining <= Math.max(viewportHeight * 2.5, 1500)) {
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
    this.refreshGalleryRows();
  }

  private selectedSearchTagTokens(): string[] {
    return searchTagTokens(this.keyword);
  }

  private searchInputText(): string {
    return searchKeywordWithoutTagTokens(this.keyword);
  }

  private updateSearchInputText(value: string): void {
    this.onKeywordChange(composeSearchKeywordWithInput(this.keyword, value));
  }

  private removeSearchTag(token: string): void {
    this.onKeywordChange(removeSearchTagToken(this.keyword, token));
  }

  @Builder
  private searchTagChip(token: string) {
    Row({ space: 4 }) {
      Text(token.endsWith('$') ? token.substring(0, token.length - 1) : token)
        .fontSize(12)
        .fontColor(themeOnPrimaryText())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 132 })

      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(13)
        .fontColor([themeOnPrimaryText()])
        .width(18)
        .height(18)
        .onClick(() => {
          this.removeSearchTag(token);
        })
    }
    .height(28)
    .padding({ left: 9, right: 6 })
    .backgroundColor(themePrimaryColor())
    .borderRadius(14)
    .flexShrink(0)
  }

  @Builder
  private searchKeywordEditor() {
    Row({ space: 6 }) {
      if (this.selectedSearchTagTokens().length > 0) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.selectedSearchTagTokens(), (token: string) => {
              this.searchTagChip(token)
            }, (token: string) => token)
          }
        }
        .width('45%')
        .height(30)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }

      TextInput({ text: this.searchInputText(), placeholder: uiText(this.searchPlaceholder) })
        .height(34)
        .layoutWeight(1)
        .backgroundColor(themeTransparentColor())
        .placeholderColor(themeSecondaryText())
        .fontColor(themePrimaryText())
        .caretColor(themePrimaryColor())
        .padding({ left: this.selectedSearchTagTokens().length > 0 ? 0 : 8, right: 8 })
        .onFocus(() => {
          this.refreshSearchSuggestions();
          this.onSearchFocus();
        })
        .onChange((value: string) => {
          this.updateSearchInputText(value);
        })
        .onSubmit(() => {
          this.closeAdvancedPanel();
          this.onSearch();
        })
    }
    .height(38)
    .layoutWeight(1)
    .padding({ left: 8, right: 8 })
    .backgroundColor(themeFieldBackground())
    .borderRadius(19)
    .alignItems(VerticalAlign.Center)
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

        this.searchKeywordEditor()

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
    return (this.isSearchResultScene || this.useLocalSearchBar) && !this.searchSubmitted;
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
      this.onKeywordChange(addSearchTagToken(this.keyword, suggestion.query));
      this.onSearchModeChange(ListMode.Normal);
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
              ListItem()
                .margin({ bottom: this.galleryCardGap() })
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
                .reuseId('gallery-row-' + this.galleryColumnCount().toString())
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
          .cachedCount(10)
          .width('100%')
          .height(this.listViewportHeight())
          .onAppear(() => {
            this.syncContentWidthFromWindow();
            if (!this.restoredScroll && this.initialScrollOffset > 0) {
              this.restoredScroll = true;
              setTimeout(() => {
                this.listScroller.scrollTo({ xOffset: 0, yOffset: this.initialScrollOffset });
                this.contentOpacity = 1;
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
      .opacity(this.contentOpacity)
      .animation({ duration: 100, curve: Curve.EaseOut })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.updateContentWidth(newArea.width as number);
        const h = newArea.height as number;
        if (h > 0 && !Number.isNaN(h)) {
          this.viewportHeight = h;
        }
      })

      // FAB 悬浮按钮
      Column() {
        QuickActionColumn({
          expanded: this.actionsExpanded,
          filterActive: this.filterActive,
          accountFilterEnabled: this.isSearchResultScene ? this.searchFilterEnabled : this.accountFilterEnabled,
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
          searchFilterEnabled: this.searchFilterEnabled,
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
          if (this.useSeekJumpPanel()) {
            Text('Jump/Seek')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(themePrimaryText())
              .width('100%')
            if (this.resultCount.length > 0) {
              Text(this.resultCount)
                .fontSize(12)
                .fontColor(themeSecondaryText())
                .width('100%')
            }
            Grid() {
              ForEach(this.jumpSeekPresets(), (preset: string) => {
                GridItem() {
                  Button(preset)
                    .height(34)
                    .width('100%')
                    .fontSize(12)
                    .fontColor(themePrimaryColor())
                    .backgroundColor(themeFieldBackground())
                    .borderRadius(4)
                    .onClick(() => {
                      this.onSeekJump('jump=' + preset);
                      this.closeJumpPanel();
                    })
                }
              }, (preset: string) => preset)
            }
            .columnsTemplate('1fr 1fr 1fr 1fr')
            .rowsGap(6)
            .columnsGap(6)
            .height(74)

            Row({ space: 6 }) {
              TextInput({ text: this.seekYearDraft, placeholder: '2026' })
                .height(36)
                .layoutWeight(1.4)
                .type(InputType.Number)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .borderRadius(4)
                .padding({ left: 8, right: 8 })
                .onChange((value: string) => {
                  this.seekYearDraft = value;
                })
              TextInput({ text: this.seekMonthDraft, placeholder: '6' })
                .height(36)
                .layoutWeight(1)
                .type(InputType.Number)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .borderRadius(4)
                .padding({ left: 8, right: 8 })
                .onChange((value: string) => {
                  this.seekMonthDraft = value;
                })
              TextInput({ text: this.seekDayDraft, placeholder: '26' })
                .height(36)
                .layoutWeight(1)
                .type(InputType.Number)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .borderRadius(4)
                .padding({ left: 8, right: 8 })
                .onChange((value: string) => {
                  this.seekDayDraft = value;
                })
            }

            Button(uiText('Seek date'))
              .height(36)
              .width('100%')
              .fontSize(13)
              .fontColor(themeOnPrimaryText())
              .backgroundColor(themePrimaryColor())
              .borderRadius(4)
              .onClick(() => {
                this.submitSeekDate();
                this.closeJumpPanel();
              })
          } else {
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
        }
        .width(this.useSeekJumpPanel() ? 280 : 220)
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
          x: this.contentWidth > 0 ? Math.max(12, this.contentWidth - (this.useSeekJumpPanel() ? 304 : 244)) : 100,
          y: this.viewportHeight > 0 ? Math.max(96, this.viewportHeight - (this.useSeekJumpPanel() ? 310 : 210)) : 360
        })
        .zIndex(14)
      }

      // 浮动导航栏
      Column() {
        if (this.isSearchResultScene || this.useLocalSearchBar) {
          this.searchResultNavBar()
        } else {
          EhNavBar({
            statusBarHeight: this.statusBarVp(),
            title: this.searchTitle.length > 0 ? this.searchTitle : this.sceneTitle,
            searchMode: false,
            keyword: this.keyword,
            filterActive: this.filterActive,
            showSearchButton: this.showSearchButton,
            showRefreshButton: false,
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
    return this.galleryRowsDataSource;
  }

  private refreshGalleryRows(): void {
    const rows = this.buildRows();
    const cols = this.galleryColumnCount();
    const newKeys: string[] = [];
    for (let i = 0; i < rows.length; i++) {
      newKeys.push(cols.toString() + ':' + this.galleryRowKey(rows[i]));
    }

    const prevCount = this.galleryRowStructureKeys.length;
    const newCount = rows.length;

    // 纯追加场景（load-more）：已有行没变化，仅末尾新增 → 逐行 appendAndNotify，不触发全量 reload
    if (newCount > prevCount && prevCount > 0) {
      let isAppend = true;
      for (let i = 0; i < prevCount; i++) {
        if (newKeys[i] !== this.galleryRowStructureKeys[i]) {
          isAppend = false;
          break;
        }
      }
      if (isAppend) {
        this.galleryRowStructureKeys = newKeys;
        for (let i = prevCount; i < newCount; i++) {
          this.galleryRowsDataSource.appendAndNotify(rows[i]);
        }
        return;
      }
    }

    // 其他情况（首次加载、刷新、列数变化等）：全量替换
    let structureChanged = newCount !== prevCount;
    for (let i = 0; i < newCount && !structureChanged; i++) {
      if (newKeys[i] !== this.galleryRowStructureKeys[i]) {
        structureChanged = true;
      }
    }
    this.galleryRowStructureKeys = newKeys;
    this.galleryRowsDataSource.replaceItems(rows);
    if (structureChanged) {
      this.galleryRowsDataSource.notifyReload();
    }
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
