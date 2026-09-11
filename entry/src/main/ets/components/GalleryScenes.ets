import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { image } from '@kit.ImageKit';
import { systemShare } from '@kit.ShareKit';
import { ALL_CATEGORY, GalleryCategory, GalleryDetail, GalleryInfo, GalleryRoute, GallerySite } from '../model/GalleryModels';
import { SearchBookmarkInfo, ehBookmarkStore } from '../services/EhBookmarkStore';
import { ehCookieStore } from '../services/EhCookieStore';
import {
  EhHttpClient,
  GalleryListLoadResult,
  ToggleFavoriteResult,
} from '../services/EhHttpClient';
import { DEFAULT_ADVANCE_SEARCH, EhUrl, FavListUrlBuilder, ListMode, ListUrlBuilder, buildJumpSeekUrl } from '../services/EhUrl';
import { FILTER_RULE_REVISION_KEY, ehFilterStore } from '../services/EhFilterStore';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehLocalFavoritesStore } from '../services/EhLocalFavoritesStore';
import { DownloadLabel, ehDownloadStore } from '../services/EhDownloadStore';
import {
  ehSettingsStore,
} from '../services/EhSettingsStore';
import { ehTagTranslationStore } from '../services/EhTagTranslationStore';
import { AsyncRequestGate } from '../services/HttpRequestLifecycle';
import { gallerySiteCandidates } from '../services/EhUrl';
import { DetailSearchRequest } from '../services/GalleryDetailSupport';
import {
  createGalleryDetailLink,
  createGalleryDetailLinkFromGallery,
  createEmptyGalleryDetailLink,
  GalleryDetailLink,
  initialDetailForLink,
} from '../services/GalleryDetailSupport';
import { FavoriteCategoryInfo } from '../services/GalleryListParser';
import { LocalGallerySearchOptions } from '../services/LocalGallerySearch';
import {
  applyAppChromeImmersiveMode,
  isEmbeddedReaderActive,
  leaveEmbeddedReaderFullscreen,
  mainContentWidthFallbackVp,
  rememberMainContentWidthVp,
} from '../services/EhWindowImmersive';
import {
  peekPendingContinuationSnapshot,
  takePendingContinuationSnapshot,
} from '../services/DistributedContinuationService';
import { readerSessionStore } from '../services/ReaderSessionStore';
import { LANGUAGE_REVISION_KEY, pushActiveBackHandler, runDetailBackHandler } from '../shared/EhShared';
import {
  themePageBackground,
} from '../shared/EhTheme';
import {
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogMaterial,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow,
  uiMaterialBackground,
} from '../shared/EhUiStyle';
import { GalleryDetailHostScene } from './GalleryDetailHostScene';
import { PopupScrim } from './PopupScrim';
import { BookmarkEditor } from './BookmarkEditor';
import { ReaderSessionScene } from './ReaderHostScene';
import {
  DOWNLOAD_LABEL_OPTION_ASK,
  DownloadLabelSelectionDialog,
} from './DownloadLabelComponents';
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
  shouldUpdateSplitPaneFocus,
} from './SplitPaneSupport';
import {
  gallerySuggestionUrl,
  normalizeSubmittedSearchKeyword,
  searchKeywordForRequest,
  searchKeywordWithoutTagTokens,
  searchTagTokenLabel,
  searchTagTokens,
  recordSearchHistory,
} from './GallerySearchScenes';
import {
  uiText,
  uiStatusText,
  createEmptyGallery,
  createEmptyDetail,
  cloneGalleryDetail,
  cloneGalleryInfos,
  cloneGalleryInfo,
  defaultDownloadLabelChoice,
  applyGalleryFilters,
  getAbilityContext,
  saveDefaultDownloadLabelChoice,
  listModeForRoute,
  routeUsesKeyword,
  defaultKeywordForRoute,
  gallerySearchTitle,
  effectiveListSite,
  galleryListFailureMessage,
  categoryDisplayName,
  galleryDisplayTitle,
  toggleGalleryDownload,
  shouldShowTagTranslations,
} from '../shared/EhShared';
import {
  SearchBookmarkManagerScene,
} from './GalleryBookmarkScenes';
import {
  GalleryCardActionOverlay,
} from './GalleryOverlayComponents';

import {
  SearchResultDraft,
  NestedSearchFrame,
  galleryListSceneCache,
  galleryListNavigationCache,
  ACCOUNT_DEFAULT_FILTER_DISABLE_FLAGS,
  createEmptySearchResultDraft,
  cloneSearchResultDraft,
  cloneNestedSearchFrames,
  cloneFavoriteCategories,
  mergeFavoriteGalleries,
  mergedFavoriteResultCount,
  cloneGalleryDetailLink,
  updateGalleryListScrollCache,
  favoriteCategoryName,
  localGalleryFilterRoute,
} from './GalleryListSupport';
import {
  GalleryListContent,
} from './GalleryListContent';

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
export { GalleryListContent, GalleryListStateView } from './GalleryListContent';

let recentFavoriteCat: number = FavListUrlBuilder.FAV_CAT_ALL;

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
  initialSearchFilterEnabled: boolean = true;
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
  delegateDetailToHost: boolean = false;
  onOpenDetailInHost: (link: GalleryDetailLink) => boolean = (_link: GalleryDetailLink) => false;
  @State keyword: string = '';
  @State statusText: string = 'Loading galleries...';
  @State requestUrl: string = '';
  @State activeSite: GallerySite = GallerySite.E;
  @State pageIndex: number = 0;
  @State totalPages: number = 0;
  @State nextUrl: string = '';
  @State resultCount: string = '';
  @State galleries: GalleryInfo[] = [];
  @State favoriteCat: number = FavListUrlBuilder.FAV_CAT_ALL;
  @State favoriteCategories: FavoriteCategoryInfo[] = [];
  @State favoriteLocalCount: number = -1;
  @State hasFirstRefresh: boolean = false;
  @State scrollResetVersion: number = 0;
  @State fabExpanded: boolean = false;
  @State filterActive: boolean = false;
  @State accountFilterEnabled: boolean = true;
  @State searchFilterEnabled: boolean = true;
  @State showSearchResultScene: boolean = false;
  @State searchResultDraft: SearchResultDraft = createEmptySearchResultDraft();
  @State searchResultDetailOpened: boolean = false;
  @State searchResultSceneRevision: number = 0;
  @State searchMode: ListMode = ListMode.Normal;
  @State searchCategory: number = GalleryCategory.None;
  @State searchAdvancedPanelOpened: boolean = false;
  @State localSearchBarVisible: boolean = false;
  @State advancedSearchEnabled: boolean = false;
  @State advanceSearch: number = DEFAULT_ADVANCE_SEARCH;
  @State minRating: number = -1;
  @State pageFrom: number = -1;
  @State pageTo: number = -1;
  @State imageSearchPath: string = '';
  @State imageSearchUseSimilarityScan: boolean = false;
  @State imageSearchOnlyCovers: boolean = false;
  @State imageSearchShowExpunged: boolean = false;
  @State searchSubmitted: boolean = false;
  @State showDetail: boolean = false;
  @State showReader: boolean = false;
  @State sceneContentWidth: number = 0;
  @State splitListRatio: number = splitPaneCurrentRatio();
  @State splitDragging: boolean = false;
  @State activeSplitPane: string = SPLIT_PANE_FOCUS_LEFT;
  private splitDragStartWidth: number = 0;
  private readerClosing: boolean = false;
  private listRequestGate: AsyncRequestGate = new AsyncRequestGate();
  @State restoreDetailWithFade: boolean = false;
  @State detailLink: GalleryDetailLink = createEmptyGalleryDetailLink();
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = 'Tap a gallery row to load detail';
  @State detailRequestUrl: string = '';
  @State cardActionVisible: boolean = false;
  @State cardActionGallery: GalleryInfo = createEmptyGallery();
  @State downloadLabelDialogVisible: boolean = false;
  @State downloadLabelOptions: DownloadLabel[] = [];
  @State pendingDownloadGallery: GalleryInfo = createEmptyGallery();
  @State rememberDownloadLabel: boolean = false;
  @State searchBookmarks: SearchBookmarkInfo[] = [];
  @State addBookmarkDialogVisible: boolean = false;
  @State addBookmarkPopupWidth: number = 0;
  @State addBookmarkPopupHeight: number = 0;
  @State showBookmarkManager: boolean = false;
  @State editingBookmarkId: string = '';
  @State addBookmarkDraft: SearchBookmarkInfo = {
    id: '',
    name: '',
    mode: ListMode.Normal,
    category: GalleryCategory.None,
    keyword: '',
    advanceSearch: -1,
    minRating: -1,
    pageFrom: -1,
    pageTo: -1,
    filterEnabled: true,
    location: GalleryRoute.Home,
    time: 0
  };
  @State renderVersion: number = 0;
  @State isLoadingMore: boolean = false;
  @State appendExhausted: boolean = false;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeightPx: number = 0;
  @StorageProp(SPLIT_PANE_RATIO_REVISION_KEY) @Watch('onSplitPaneRatioRevisionChange') splitPaneRatioRevision: number = 0;
  @StorageProp(FILTER_RULE_REVISION_KEY) @Watch('onFilterRulesRevisionChanged') filterRulesRevision: number = 0;
  private listScrollOffset: number = 0;
  private detailScrollOffset: number = 0;
  private searchOriginShowDetail: boolean = false;
  private searchOriginDetailLink: GalleryDetailLink = createEmptyGalleryDetailLink();
  private searchOriginDetail: GalleryDetail = createEmptyDetail();
  private searchOriginDetailStatus: string = '';
  private searchOriginDetailRequestUrl: string = '';
  private searchOriginDetailScrollOffset: number = 0;
  private navigationCacheSuppressed: boolean = false;
  private nestedSearchFrames: NestedSearchFrame[] = [];
  private unregisterActiveBackHandler: () => void = () => {};
  private activeBackHandlerRegistered: boolean = false;
  private searchBackTransitionPending: boolean = false;

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
        this.imageSearchPath + '|' + (this.imageSearchUseSimilarityScan ? 'sim' : 'nosim') + '|' +
        (this.imageSearchOnlyCovers ? 'covers' : 'all') + '|' +
        (this.imageSearchShowExpunged ? 'exp' : 'noexp') + '|' +
        (this.accountFilterEnabled ? 'account-filter-on' : 'account-filter-off') + '|' +
        (this.searchFilterEnabled ? 'search-filter-on' : 'search-filter-off') + '|' +
        (this.searchAdvancedPanelOpened ? 'advanced-panel-opened' : 'advanced-panel-closed');
    }
    return this.sourceRoute.toString() + '|' + mode + '|' + this.follow + '|' + this.initialKeyword + '|' +
      this.initialSearchMode.toString() + '|' + this.initialSearchCategory.toString() + '|' +
      (this.initialAdvancedSearchEnabled ? '1' : '0') + '|' + this.initialAdvanceSearch.toString() + '|' +
      this.initialMinRating.toString() + '|' + this.initialPageFrom.toString() + '|' + this.initialPageTo.toString() +
      '|' + (this.accountFilterEnabled ? 'account-filter-on' : 'account-filter-off') + '|favcat=' +
      (this.sourceRoute === GalleryRoute.Favorites ? this.favoriteCat.toString() : 'na');
  }

  private navigationCacheKey(): string {
    const mode = this.useForcedMode ? this.forcedMode.toString() : listModeForRoute(this.sourceRoute).toString();
    return this.sourceRoute.toString() + '|' + this.listMode + '|' + mode + '|' + this.follow + '|' +
      this.initialKeyword + '|' + (this.isSearchResultScene ? 'search-result' : 'root') + '|' +
      (this.useLocalProvider ? 'local' : 'remote') + '|favcat=' +
      (this.sourceRoute === GalleryRoute.Favorites ? this.favoriteCat.toString() : 'na');
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
    this.galleries = cache.galleries;
    this.favoriteCat = cache.favoriteCat;
    this.favoriteCategories = cache.favoriteCategories;
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
    this.imageSearchPath = cache.imagePath === undefined ? '' : cache.imagePath;
    this.imageSearchUseSimilarityScan = cache.imageUseSimilarityScan === true;
    this.imageSearchOnlyCovers = cache.imageOnlySearchCovers === true;
    this.imageSearchShowExpunged = cache.imageShowExpunged === true;
    this.searchSubmitted = cache.searchSubmitted === true;
    this.listScrollOffset = cache.listScrollOffset;
    this.appendExhausted = cache.appendExhausted === true;
    return true;
  }

  private restoreNavigationCache(): void {
    const cache = galleryListNavigationCache.get(this.navigationCacheKey());
    if (cache === undefined) {
      return;
    }
    this.showSearchResultScene = this.isSearchResultScene ? false : cache.showSearchResultScene;
    this.searchResultDraft = this.isSearchResultScene ? createEmptySearchResultDraft() :
      cloneSearchResultDraft(cache.searchResultDraft);
    this.nestedSearchFrames = this.isSearchResultScene ? [] : cloneNestedSearchFrames(cache.nestedSearchFrames);
    this.searchResultDetailOpened = this.isSearchResultScene ? false : cache.searchResultDetailOpened;
    this.searchOriginShowDetail = this.isSearchResultScene ? false : cache.searchOriginShowDetail;
    this.searchOriginDetailLink = this.isSearchResultScene ? createEmptyGalleryDetailLink() :
      cloneGalleryDetailLink(cache.searchOriginDetailLink);
    this.searchOriginDetail = this.isSearchResultScene ? createEmptyDetail() :
      cloneGalleryDetail(cache.searchOriginDetail);
    this.searchOriginDetailStatus = this.isSearchResultScene ? '' : cache.searchOriginDetailStatus;
    this.searchOriginDetailRequestUrl = this.isSearchResultScene ? '' : cache.searchOriginDetailRequestUrl;
    this.searchOriginDetailScrollOffset = this.isSearchResultScene ? 0 : cache.searchOriginDetailScrollOffset;
    this.localSearchBarVisible = cache.localSearchBarVisible;
    this.showDetail = cache.showDetail;
    this.activeSplitPane = normalizeSplitPaneFocus(cache.activeSplitPane, cache.showDetail);
    this.restoreDetailWithFade = cache.showDetail && shouldFadeRestoredRightPane();
    this.detailLink = cloneGalleryDetailLink(cache.detailLink);
    this.detail = cloneGalleryDetail(cache.detail);
    this.detailStatus = cache.detailStatus;
    this.detailRequestUrl = cache.detailRequestUrl;
    this.detailScrollOffset = cache.detailScrollOffset;
    this.fabExpanded = cache.fabExpanded;
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
      galleries: this.galleries,
      favoriteCat: this.favoriteCat,
      favoriteCategories: this.favoriteCategories,
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
      imagePath: this.imageSearchPath,
      imageUseSimilarityScan: this.imageSearchUseSimilarityScan,
      imageOnlySearchCovers: this.imageSearchOnlyCovers,
      imageShowExpunged: this.imageSearchShowExpunged,
      searchSubmitted: this.searchSubmitted,
      listScrollOffset: this.listScrollOffset,
      appendExhausted: this.appendExhausted
    });
  }

  private saveNavigationCache(): void {
    if (this.navigationCacheSuppressed) {
      return;
    }
    galleryListNavigationCache.set(this.navigationCacheKey(), {
      activeSplitPane: this.activeSplitPane,
      showSearchResultScene: this.isSearchResultScene ? false : this.showSearchResultScene,
      searchResultDraft: this.isSearchResultScene ? createEmptySearchResultDraft() :
        cloneSearchResultDraft(this.searchResultDraft),
      nestedSearchFrames: this.isSearchResultScene ? [] : cloneNestedSearchFrames(this.nestedSearchFrames),
      searchResultDetailOpened: this.isSearchResultScene ? false : this.searchResultDetailOpened,
      searchOriginShowDetail: this.isSearchResultScene ? false : this.searchOriginShowDetail,
      searchOriginDetailLink: this.isSearchResultScene ? createEmptyGalleryDetailLink() :
        cloneGalleryDetailLink(this.searchOriginDetailLink),
      searchOriginDetail: this.isSearchResultScene ? createEmptyDetail() : cloneGalleryDetail(this.searchOriginDetail),
      searchOriginDetailStatus: this.isSearchResultScene ? '' : this.searchOriginDetailStatus,
      searchOriginDetailRequestUrl: this.isSearchResultScene ? '' : this.searchOriginDetailRequestUrl,
      searchOriginDetailScrollOffset: this.isSearchResultScene ? 0 : this.searchOriginDetailScrollOffset,
      localSearchBarVisible: this.localSearchBarVisible,
      showDetail: this.showDetail,
      restoreDetailWithFade: this.restoreDetailWithFade,
      detailLink: cloneGalleryDetailLink(this.detailLink),
      detail: cloneGalleryDetail(this.detail),
      detailStatus: this.detailStatus,
      detailRequestUrl: this.detailRequestUrl,
      detailScrollOffset: this.detailScrollOffset,
      fabExpanded: this.fabExpanded
    });
  }

  private clearNavigationCache(): void {
    galleryListNavigationCache.delete(this.navigationCacheKey());
  }

  private closeSearchResultToParent(): void {
    this.navigationCacheSuppressed = true;
    this.clearNavigationCache();
    this.onBack();
  }

  private refreshSearchResultNavigationCache(): void {
    if (this.showSearchResultScene) {
      this.saveNavigationCache();
    }
  }

  private presentSearchResultScene(): void {
    this.searchResultSceneRevision++;
    this.showSearchResultScene = true;
    this.saveNavigationCache();
    setTimeout(() => {
      this.refreshSearchResultNavigationCache();
    }, 0);
  }

  private captureSearchOrigin(): void {
    this.searchOriginShowDetail = this.showDetail;
    this.searchOriginDetailLink = cloneGalleryDetailLink(this.detailLink);
    this.searchOriginDetail = cloneGalleryDetail(this.detail);
    this.searchOriginDetailStatus = this.detailStatus;
    this.searchOriginDetailRequestUrl = this.detailRequestUrl;
    this.searchOriginDetailScrollOffset = this.detailScrollOffset;
    this.searchResultDetailOpened = false;
  }

  private clearSearchOrigin(): void {
    this.searchOriginShowDetail = false;
    this.searchOriginDetailLink = createEmptyGalleryDetailLink();
    this.searchOriginDetail = createEmptyDetail();
    this.searchOriginDetailStatus = '';
    this.searchOriginDetailRequestUrl = '';
    this.searchOriginDetailScrollOffset = 0;
    this.nestedSearchFrames = [];
  }

  private restoreSearchOrigin(): void {
    if (this.searchOriginShowDetail) {
      this.showDetail = true;
      this.detailLink = cloneGalleryDetailLink(this.searchOriginDetailLink);
      this.detail = cloneGalleryDetail(this.searchOriginDetail);
      this.detailStatus = this.searchOriginDetailStatus;
      this.detailRequestUrl = this.searchOriginDetailRequestUrl;
      this.detailScrollOffset = this.searchOriginDetailScrollOffset;
    }
    this.searchResultDetailOpened = false;
    this.clearSearchOrigin();
  }

  private resetListScroll(): void {
    this.listScrollOffset = 0;
    this.saveListCache();
  }

  private syncAccountFilterSetting(): void {
    this.accountFilterEnabled = ehSettingsStore.getValue('use_account_default_filter', 'On') !== 'Off';
  }

  private galleryStatusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    this.syncSceneContentWidthFromWindow();
    // The cache key contains the account-filter setting. Root settings are already loaded
    // before gallery scenes are created, so synchronize it before looking up the cache.
    // Otherwise returning from Settings can miss the existing list cache, briefly render an
    // empty page and start another network refresh.
    this.syncAccountFilterSetting();
    if (this.sourceRoute === GalleryRoute.Favorites) {
      this.favoriteCat = recentFavoriteCat;
    }
    if (!this.restoreListCache()) {
      this.keyword = this.initialKeyword.length > 0 ? this.initialKeyword : defaultKeywordForRoute(this.sourceRoute);
      this.searchMode = this.initialSearchMode;
      this.searchCategory = this.initialSearchCategory;
      this.advancedSearchEnabled = this.initialAdvancedSearchEnabled;
      this.advanceSearch = this.initialAdvanceSearch;
      this.minRating = this.initialMinRating;
      this.pageFrom = this.initialPageFrom;
      this.pageTo = this.initialPageTo;
      this.imageSearchPath = this.initialImagePath;
      this.imageSearchUseSimilarityScan = this.initialImageUseSimilarityScan;
      this.imageSearchOnlyCovers = this.initialImageOnlySearchCovers;
      this.imageSearchShowExpunged = this.initialImageShowExpunged;
      this.filterActive = this.isSearchResultScene ? false : this.searchResultDraft.filterActive;
      this.searchFilterEnabled = this.isSearchResultScene ? this.initialSearchFilterEnabled : true;
      this.searchAdvancedPanelOpened = this.isSearchResultScene ?
        (this.searchResultDraft.searchAdvancedPanelOpened || this.initialSearchAdvancedPanelOpened) : false;
      this.searchSubmitted = !this.isSearchResultScene || this.initialSearchSubmitted;
      this.localSearchBarVisible = false;
    }
    this.restoreNavigationCache();
    this.restoreEmbeddedContinuationIfPresent();
    if (this.delegateDetailToHost) {
      this.clearDelegatedDetailLayer();
    } else {
      markCurrentRouteRightPane(this.useSplitLayout());
    }
    const context = getAbilityContext();
    if (context !== undefined) {
      const auxiliaryStores = Promise.all([
        ehBookmarkStore.ensureLoaded(context),
        ehLocalFavoritesStore.ensureLoaded(context),
        ehDownloadStore.ensureLoaded(context)
      ]).catch(() => {});
      Promise.all([
        ehCookieStore.ensureLoaded(context),
        ehFilterStore.ensureLoaded(context),
        ehSettingsStore.ensureLoaded(context)
      ]).catch((error: Error) => {
        this.statusText = 'Cookie load failed, using current session: ' + error.message;
      }).finally(() => {
        this.refreshSearchBookmarks();
        this.refreshLocalFavoriteCount();
        const previousAccountFilterEnabled = this.accountFilterEnabled;
        this.syncAccountFilterSetting();
        if (!this.isSearchResultScene && previousAccountFilterEnabled !== this.accountFilterEnabled && !this.useLocalProvider) {
          this.hasFirstRefresh = false;
        }
        if (this.isSearchResultScene && this.initialSearchSubmitted && !this.hasFirstRefresh) {
          this.searchSubmitted = true;
        }
        if ((!this.isSearchResultScene || this.searchSubmitted) && !this.showReader) {
          this.firstRefresh();
        }
      });
      auxiliaryStores.then(() => {
        this.refreshSearchBookmarks();
        this.refreshLocalFavoriteCount();
      });
    } else {
      if (this.isSearchResultScene && this.initialSearchSubmitted && !this.hasFirstRefresh) {
        this.searchSubmitted = true;
      }
      if ((!this.isSearchResultScene || this.searchSubmitted) && !this.showReader) {
        this.firstRefresh();
      }
    }
    this.activateBackHandler();
  }

  private restoreEmbeddedContinuationIfPresent(): void {
    const pending = peekPendingContinuationSnapshot();
    if (pending === null || pending.kind !== 'embedded_reader' ||
      pending.route !== this.sourceRoute.toString() || pending.readerSession === undefined) {
      return;
    }
    const session = pending.readerSession;
    if (session.detail.gid <= 0 || session.detail.token.length === 0 || session.pageIndex < 0) {
      return;
    }
    readerSessionStore.setSession(session);
    this.detail = cloneGalleryDetail(session.detail);
    this.detailLink = createGalleryDetailLink(session.detail.gid, session.detail.token,
      session.detail.title, session.site, session.detailRequestUrl);
    this.detailRequestUrl = session.detailRequestUrl;
    this.detailStatus = session.statusText;
    this.showDetail = true;
    this.showReader = true;
    takePendingContinuationSnapshot();
    this.renderVersion++;
  }

  onFilterRulesRevisionChanged(): void {
    if (this.galleries.length === 0) {
      return;
    }
    this.galleries = this.visibleRemoteGalleries(this.galleries);
    this.renderVersion++;
    this.saveListCache();
  }

  aboutToDisappear(): void {
    this.unregisterActiveBackHandler();
    this.unregisterActiveBackHandler = () => {};
    this.activeBackHandlerRegistered = false;
    this.saveListCache();
    this.saveNavigationCache();
  }

  onPageHide(): void {
    this.saveListCache();
    this.saveNavigationCache();
  }

  onResetVersionChanged(): void {
    this.resetToTopLevel();
  }

  private handleSystemBack(): boolean {
    if (this.addBookmarkDialogVisible) {
      this.addBookmarkDialogVisible = false;
      this.editingBookmarkId = '';
      return true;
    }
    if (this.downloadLabelDialogVisible) {
      this.downloadLabelDialogVisible = false;
      return true;
    }
    if (this.cardActionVisible) {
      this.closeCardActions();
      return true;
    }
    if (this.showReader) {
      this.closeReader();
      return true;
    }
    if (this.useSplitLayout() && this.activeSplitPane === SPLIT_PANE_FOCUS_RIGHT) {
      if (this.showBookmarkManager) {
        this.closeBookmarkManager();
        return true;
      }
      if (this.showDetail) {
        if (runDetailBackHandler()) {
          return true;
        }
        this.closeDetail();
        return true;
      }
    }
    if (this.useSplitLayout() && this.activeSplitPane === SPLIT_PANE_FOCUS_LEFT) {
      if (this.showSearchResultScene) {
        this.closeSearchResultScene();
        return true;
      }
      if (this.useLocalProvider && this.localSearchBarVisible) {
        this.closeLocalSearchBar();
        return true;
      }
    }
    if (this.showBookmarkManager) {
      this.closeBookmarkManager();
      return true;
    }
    if (this.showDetail) {
      if (runDetailBackHandler()) {
        return true;
      }
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
      this.closeSearchResultToParent();
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
    this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
    this.restoreDetailWithFade = false;
    this.detailLink = createEmptyGalleryDetailLink();
    this.detail = createEmptyDetail();
    this.detailStatus = 'Tap a gallery row to load detail';
    this.detailRequestUrl = '';
    this.detailScrollOffset = 0;
    this.cardActionVisible = false;
    this.cardActionGallery = createEmptyGallery();
    this.downloadLabelDialogVisible = false;
    this.downloadLabelOptions = [];
    this.pendingDownloadGallery = createEmptyGallery();
    this.showBookmarkManager = false;
    this.addBookmarkDialogVisible = false;
    this.showSearchResultScene = false;
    this.searchResultDraft = createEmptySearchResultDraft();
    this.searchResultDetailOpened = false;
    this.searchResultSceneRevision++;
    this.clearSearchOrigin();
    this.localSearchBarVisible = false;
    this.fabExpanded = false;
    this.restoreBackHandler();
    this.renderVersion++;
    this.clearNavigationCache();
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
    const generation = this.beginListReplacement(pageIndex, preserveExisting);
    const request = this.loadRoutePageWithFallback(pageIndex);

    request.then((result: GalleryListLoadResult) => {
      this.applyListReplacementResult(generation, result, pageIndex, true, onDone);
    }).catch((error: Error) => {
      this.applyListReplacementFailure(generation, error, onDone);
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
    const generation = this.beginListReplacement(0, preserveExisting);

    this.client.loadGalleryListUrl(absoluteUrl, this.activeSite, this.includeAccountUConfig()).then((result: GalleryListLoadResult) => {
      this.applyListReplacementResult(generation, result, 0, true, onDone);
    }).catch((error: Error) => {
      this.applyListReplacementFailure(generation, error, onDone);
    });
  }

  private loadLocal(pageIndex: number, preserveExisting: boolean = false, onDone?: () => void): void {
    this.activeSite = effectiveListSite(this.sourceRoute);
    const generation = this.beginListReplacement(pageIndex, preserveExisting);

    this.localProvider(this.keyword.trim(), pageIndex, this.localPageSize, this.localSearchOptions())
      .then((result: GalleryListLoadResult) => {
      this.applyListReplacementResult(generation, result, pageIndex, false, onDone);
    }).catch((error: Error) => {
      this.applyListReplacementFailure(generation, error, onDone);
    });
  }

  private beginListReplacement(pageIndex: number, preserveExisting: boolean): number {
    const generation = this.listRequestGate.begin();
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
    return generation;
  }

  private applyListReplacementResult(generation: number, result: GalleryListLoadResult, pageIndex: number,
    remote: boolean, onDone?: () => void): void {
    if (this.listRequestGate.isCurrent(generation)) {
      this.requestUrl = result.url;
      this.galleries = this.visibleRemoteGalleries(result.galleries);
      if (remote) {
        this.updateFavoriteCategories(result.favoriteCategories);
      }
      this.statusText = result.ok || !remote ? result.message : galleryListFailureMessage(result, this.activeSite);
      this.totalPages = result.pages;
      this.nextUrl = result.nextUrl;
      this.resultCount = result.resultCount;
      this.appendExhausted = this.isAppendExhausted(result, pageIndex, result.galleries.length);
      this.renderVersion++;
      this.saveListCache();
    }
    this.finishListRequest(onDone);
  }

  private applyListReplacementFailure(generation: number, error: Error, onDone?: () => void): void {
    if (this.listRequestGate.isCurrent(generation)) {
      this.statusText = 'Load failed: ' + error.message;
      this.galleries = [];
      this.renderVersion++;
      this.saveListCache();
    }
    this.finishListRequest(onDone);
  }

  private finishListRequest(onDone?: () => void): void {
    if (onDone !== undefined) {
      onDone();
    }
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
    const generation = this.listRequestGate.snapshot();

    let loadUrl: string = this.nextUrl;
    if (loadUrl.length > 0 && (this.searchMode === ListMode.Tag || this.searchMode === ListMode.Uploader)) {
      const extraParams: string[] = [];
      const effectiveCategory = this.requestCategoryForMode(this.searchMode);
      if (effectiveCategory !== GalleryCategory.None) {
        extraParams.push('f_cats=' + ((~effectiveCategory) & ALL_CATEGORY).toString());
      }
      if (this.advancedSearchEnabled && this.advanceSearch !== -1) {
        extraParams.push('advsearch=1');
        if ((this.advanceSearch & 0x1) !== 0) {
          extraParams.push('f_sname=on');
        }
        if ((this.advanceSearch & 0x2) !== 0) {
          extraParams.push('f_stags=on');
        }
        if ((this.advanceSearch & 0x4) !== 0) {
          extraParams.push('f_sdesc=on');
        }
        if ((this.advanceSearch & 0x8) !== 0) {
          extraParams.push('f_storr=on');
        }
        if ((this.advanceSearch & 0x10) !== 0) {
          extraParams.push('f_sto=on');
        }
        if ((this.advanceSearch & 0x20) !== 0) {
          extraParams.push('f_sdt1=on');
        }
        if ((this.advanceSearch & 0x40) !== 0) {
          extraParams.push('f_sdt2=on');
        }
        if ((this.advanceSearch & 0x80) !== 0) {
          extraParams.push('f_sh=on');
        }
        if ((this.advanceSearch & 0x100) !== 0) {
          extraParams.push('f_sfl=on');
        }
        if ((this.advanceSearch & 0x200) !== 0) {
          extraParams.push('f_sfu=on');
        }
        if ((this.advanceSearch & 0x400) !== 0) {
          extraParams.push('f_sft=on');
        }
        if (this.minRating !== -1) {
          extraParams.push('f_sr=on');
          extraParams.push('f_srdd=' + this.minRating.toString());
        }
        if (this.pageFrom !== -1 || this.pageTo !== -1) {
          extraParams.push('f_sp=on');
          extraParams.push('f_spf=' + (this.pageFrom !== -1 ? this.pageFrom.toString() : ''));
          extraParams.push('f_spt=' + (this.pageTo !== -1 ? this.pageTo.toString() : ''));
        }
      }
      if (extraParams.length > 0) {
        loadUrl = loadUrl + (loadUrl.indexOf('?') >= 0 ? '&' : '?') + extraParams.join('&');
      }
    }

    const request =
      loadUrl.length > 0 ?
        this.client.loadGalleryListUrl(this.absoluteListUrl(loadUrl), this.activeSite, this.includeAccountUConfig()) :
        this.loadRoutePageWithFallback(nextPage);

    request.then((result: GalleryListLoadResult) => {
      this.applyAppendResult(generation, result, nextPage, true);
    }).catch((error: Error) => {
      this.applyAppendFailure(generation, error);
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
    const generation = this.listRequestGate.snapshot();
    this.localProvider(this.keyword.trim(), nextPage, this.localPageSize, this.localSearchOptions())
      .then((result: GalleryListLoadResult) => {
      this.applyAppendResult(generation, result, nextPage, false);
    }).catch((error: Error) => {
      this.applyAppendFailure(generation, error);
    });
  }

  private applyAppendResult(generation: number, result: GalleryListLoadResult, nextPage: number,
    remote: boolean): void {
    if (!this.listRequestGate.isCurrent(generation)) {
      return;
    }
    this.requestUrl = result.url;
    const unseen = this.uniqueAppendGalleries(result.galleries);
    const unique = this.visibleRemoteGalleries(unseen);
    if (remote) {
      this.updateFavoriteCategories(result.favoriteCategories);
    }
    this.galleries = this.galleries.concat(unique);
    this.pageIndex = nextPage;
    if (result.pages > 0) {
      this.totalPages = result.pages;
    }
    this.nextUrl = result.nextUrl;
    this.resultCount = result.resultCount;
    this.statusText = result.ok || !remote ? result.message : galleryListFailureMessage(result, this.activeSite);
    this.appendExhausted = this.isAppendExhausted(result, nextPage, unseen.length);
    this.isLoadingMore = false;
    this.saveListCache();
  }

  private uniqueAppendGalleries(incoming: GalleryInfo[]): GalleryInfo[] {
    const existingGids: Set<number> = new Set<number>();
    for (let i = 0; i < this.galleries.length; i++) {
      existingGids.add(this.galleries[i].gid);
    }
    const unique: GalleryInfo[] = [];
    for (let i = 0; i < incoming.length; i++) {
      if (!existingGids.has(incoming[i].gid)) {
        existingGids.add(incoming[i].gid);
        unique.push(incoming[i]);
      }
    }
    return unique;
  }

  private applyAppendFailure(generation: number, error: Error): void {
    if (!this.listRequestGate.isCurrent(generation)) {
      return;
    }
    this.statusText = 'Load more failed: ' + error.message;
    this.isLoadingMore = false;
    this.saveListCache();
  }

  private async loadRoutePageWithFallback(pageIndex: number): Promise<GalleryListLoadResult> {
    const primarySite = effectiveListSite(this.sourceRoute);
    const candidates = this.sourceRoute === GalleryRoute.Favorites ? gallerySiteCandidates(primarySite) :
      [primarySite];
    let result = await this.loadRoutePage(pageIndex, primarySite);
    this.activeSite = primarySite;
    if (!result.ok && candidates.length > 1) {
      const fallback = await this.loadRoutePage(pageIndex, candidates[1]);
      if (fallback.ok) {
        result = fallback;
        this.activeSite = candidates[1];
      }
    }
    if (this.sourceRoute === GalleryRoute.Favorites &&
      this.favoriteCat === FavListUrlBuilder.FAV_CAT_ALL) {
      return this.mergeLocalFavoritesIntoAllFavorites(result, searchKeywordForRequest(this.keyword), pageIndex);
    }
    return result;
  }

  private visibleRemoteGalleries(galleries: GalleryInfo[]): GalleryInfo[] {
    const cloned = cloneGalleryInfos(galleries);
    return this.shouldApplyLocalGalleryFilters() ? applyGalleryFilters(cloned) : cloned;
  }

  private updateFavoriteCategories(categories: FavoriteCategoryInfo[] | undefined): void {
    if (this.sourceRoute !== GalleryRoute.Favorites || categories === undefined || categories.length === 0) {
      return;
    }
    this.favoriteCategories = cloneFavoriteCategories(categories);
  }

  private refreshLocalFavoriteCount(): void {
    if (this.sourceRoute !== GalleryRoute.Favorites) {
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      this.favoriteLocalCount = ehLocalFavoritesStore.count();
      return;
    }
    ehLocalFavoritesStore.ensureLoaded(context).then(() => {
      this.favoriteLocalCount = ehLocalFavoritesStore.count();
      this.renderVersion++;
    }).catch(() => {
      this.favoriteLocalCount = -1;
    });
  }

  private shouldApplyLocalGalleryFilters(): boolean {
    // Local rules are independent from the optional account/UConfig filters.
    // Search results follow their own toggle, regardless of the entry route.
    if (this.isSearchResultScene) {
      return this.searchFilterEnabled;
    }
    return !this.useLocalProvider && localGalleryFilterRoute(this.sourceRoute);
  }

  private loadRoutePage(pageIndex: number, site: GallerySite): Promise<GalleryListLoadResult> {
    const requestKeyword = searchKeywordForRequest(this.keyword);
    const hasSearchTags = searchTagTokens(this.keyword).length > 0;
    if (this.sourceRoute === GalleryRoute.Favorites) {
      if (this.favoriteCat === FavListUrlBuilder.FAV_CAT_LOCAL) {
        return this.loadLocalFavoritePage(requestKeyword, pageIndex);
      }
      const builder = new FavListUrlBuilder();
      builder.keyword = requestKeyword;
      builder.index = pageIndex;
      builder.favCat = this.favoriteCat;
      this.requestUrl = builder.build(site);
      return this.client.loadFavoritesList(builder, site);
    }

    const builder = new ListUrlBuilder();
    builder.keyword = (this.isSearchResultScene || routeUsesKeyword(this.sourceRoute)) ? requestKeyword : '';
    builder.pageIndex = pageIndex;
    const routeMode = hasSearchTags ? ListMode.Normal : (this.useForcedMode ? this.forcedMode : listModeForRoute(this.sourceRoute));
    builder.mode = this.searchModeForRoute(routeMode, builder.keyword);
    if (hasSearchTags) {
      builder.mode = ListMode.Normal;
    }
    builder.follow = this.follow;
    builder.category = this.requestCategoryForMode(builder.mode);
    builder.imagePath = this.imageSearchPath;
    builder.useSimilarityScan = this.imageSearchUseSimilarityScan;
    builder.onlySearchCovers = this.imageSearchOnlyCovers;
    builder.showExpunged = this.imageSearchShowExpunged;
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

  private async loadLocalFavoritePage(keyword: string, pageIndex: number): Promise<GalleryListLoadResult> {
    const context = getAbilityContext();
    if (context === undefined) {
      return {
        ok: false,
        url: 'local:favorites',
        statusCode: 0,
        message: 'Local favorites unavailable',
        pages: 0,
        nextPage: -1,
        nextUrl: '',
        resultCount: '',
        galleries: [],
        favoriteCategories: this.favoriteCategories
      };
    }
    await ehLocalFavoritesStore.ensureLoaded(context);
    const pageSize = 25;
    const all = ehLocalFavoritesStore.getItems(keyword);
    this.favoriteLocalCount = ehLocalFavoritesStore.count();
    const start = Math.max(0, pageIndex) * pageSize;
    const page = all.slice(start, Math.min(all.length, start + pageSize));
    const pages = all.length === 0 ? 0 : Math.ceil(all.length / pageSize);
    return {
      ok: page.length > 0,
      url: 'local:favorites',
      statusCode: 200,
      message: page.length > 0 ? 'Parsed ' + page.length.toString() + ' galleries' : 'No results',
      pages: pages,
      nextPage: pageIndex + 1 < pages ? pageIndex + 1 : -1,
      nextUrl: '',
      resultCount: all.length.toString() + ' local favorites',
      galleries: page,
      favoriteCategories: this.favoriteCategories
    };
  }

  private async mergeLocalFavoritesIntoAllFavorites(result: GalleryListLoadResult, keyword: string,
    pageIndex: number): Promise<GalleryListLoadResult> {
    const context = getAbilityContext();
    if (context === undefined) {
      return result;
    }
    await ehLocalFavoritesStore.ensureLoaded(context);
    this.favoriteLocalCount = ehLocalFavoritesStore.count();
    if (pageIndex !== 0) {
      return result;
    }
    const local = ehLocalFavoritesStore.getItems(keyword);
    if (local.length === 0) {
      return result;
    }
    const merged = mergeFavoriteGalleries(local, result.galleries);
    return {
      ok: result.ok || merged.length > 0,
      url: result.url,
      statusCode: result.statusCode,
      message: result.ok ? result.message + ', local ' + local.length.toString() : 'Parsed ' + merged.length.toString() + ' galleries',
      pages: result.pages,
      nextPage: result.nextPage,
      nextUrl: result.nextUrl,
      resultCount: mergedFavoriteResultCount(result.resultCount, local.length),
      galleries: merged,
      favoriteCategories: result.favoriteCategories
    };
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
    if (this.isSearchResultScene && this.searchAdvancedPanelOpened && this.searchSupportsCategory(mode)) {
      return this.searchCategory === GalleryCategory.None ? ALL_CATEGORY : this.searchCategory;
    }
    if (!this.isSearchResultScene && this.shouldApplySearchFilters() && this.searchSupportsCategory(mode) &&
      this.searchCategory !== GalleryCategory.None) {
      return this.searchCategory;
    }
    if (!this.isSearchResultScene && this.searchSupportsCategory(mode) && !this.accountFilterEnabled) {
      return ALL_CATEGORY;
    }
    return GalleryCategory.None;
  }

  private searchSupportsCategory(mode: ListMode): boolean {
    return mode === ListMode.Normal || mode === ListMode.Subscription || mode === ListMode.Tag ||
      mode === ListMode.Uploader || mode === ListMode.WhatsHot;
  }

  private searchSupportsAdvanced(mode: ListMode): boolean {
    return mode === ListMode.Normal || mode === ListMode.Subscription || mode === ListMode.Tag ||
      mode === ListMode.Uploader || mode === ListMode.WhatsHot;
  }

  private refreshSearchBookmarks(): void {
    this.searchBookmarks = ehBookmarkStore.getItems();
  }

  private canUseBookmarks(): boolean {
    return !this.useLocalProvider && this.sourceRoute !== GalleryRoute.Favorites &&
      (this.sourceRoute === GalleryRoute.Home || this.sourceRoute === GalleryRoute.Subscription ||
        this.sourceRoute === GalleryRoute.WhatsHot);
  }

  private currentBookmarkLocation(): GalleryRoute {
    if (this.sourceRoute === GalleryRoute.Subscription) {
      return GalleryRoute.Subscription;
    }
    if (this.sourceRoute === GalleryRoute.WhatsHot) {
      return GalleryRoute.WhatsHot;
    }
    return GalleryRoute.Home;
  }

  private currentBookmarkMode(): ListMode {
    const requestKeyword = searchKeywordForRequest(this.keyword);
    const hasSearchTags = searchTagTokens(this.keyword).length > 0;
    if (hasSearchTags) {
      return ListMode.Normal;
    }
    const routeMode = this.useForcedMode ? this.forcedMode : listModeForRoute(this.currentBookmarkLocation());
    return this.searchModeForRoute(routeMode, requestKeyword);
  }

  private currentBookmarkFilterEnabled(): boolean {
    return this.isSearchResultScene ? this.searchFilterEnabled : this.accountFilterEnabled;
  }

  private currentBookmarkCategory(mode: ListMode): number {
    return this.requestCategoryForMode(mode);
  }

  private currentBookmarkDefaultName(mode: ListMode, category: number): string {
    const translatedKeyword = this.translatedBookmarkKeyword(this.keyword);
    if (translatedKeyword.length > 0) {
      return translatedKeyword;
    }
    if (mode === ListMode.Subscription && category === GalleryCategory.None && !this.advancedSearchEnabled) {
      return uiText('Subscription');
    }
    if (mode === ListMode.WhatsHot) {
      return uiText('Whats Hot');
    }
    if (category !== GalleryCategory.None && category !== ALL_CATEGORY) {
      return categoryDisplayName(category);
    }
    return uiText('Homepage');
  }

  private translatedBookmarkKeyword(keyword: string): string {
    const parts: string[] = [];
    const tokens = searchTagTokens(keyword);
    for (let i = 0; i < tokens.length; i++) {
      const name = this.translatedBookmarkTag(tokens[i]);
      if (name.length > 0) {
        parts.push(name);
      }
    }
    const text = searchKeywordWithoutTagTokens(keyword).replace(/\$/g, ' ').replace(/\s+/g, ' ').trim();
    if (text.length > 0) {
      parts.push(text);
    }
    if (tokens.length === 0 && parts.length === 0) {
      const fallback = keyword.replace(/\$/g, ' ').replace(/\s+/g, ' ').trim();
      if (fallback.length > 0) {
        parts.push(fallback);
      }
    }
    return parts.join(' ').replace(/\s+/g, ' ').trim();
  }

  private translatedBookmarkTag(token: string): string {
    let value = token.trim();
    if (value.endsWith('$')) {
      value = value.substring(0, value.length - 1).trim();
    }
    const colon = value.indexOf(':');
    let namespace = '';
    let tag = value;
    if (colon > 0 && colon < value.length - 1) {
      namespace = value.substring(0, colon).trim();
      tag = value.substring(colon + 1).trim();
    }
    if (shouldShowTagTranslations()) {
      const translated = ehTagTranslationStore.translate(namespace, tag);
      if (translated.length > 0) {
        return translated;
      }
    }
    return searchTagTokenLabel(token).replace(/_/g, ' ').replace(/\$/g, ' ').trim();
  }

  private bookmarkHasAdvancedParams(bookmark: SearchBookmarkInfo): boolean {
    return bookmark.advanceSearch !== -1 || bookmark.minRating !== -1 || bookmark.pageFrom !== -1 ||
      bookmark.pageTo !== -1;
  }

  private showFloatingStatus(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: uiStatusText(message) });
    } catch (error) {
    }
  }

  private openAddBookmarkDialog(): void {
    if (!this.canUseBookmarks()) {
      return;
    }
    if (this.searchMode === ListMode.ImageSearch) {
      this.statusText = 'Cannot bookmark image search';
      return;
    }
    const bookmarkMode = this.currentBookmarkMode();
    const bookmarkCategory = this.currentBookmarkCategory(bookmarkMode);
    const name = this.currentBookmarkDefaultName(bookmarkMode, bookmarkCategory);
    const draft = ehBookmarkStore.createBookmark(name, bookmarkMode, bookmarkCategory, this.keyword,
      this.advancedSearchEnabled ? this.advanceSearch : -1, this.minRating, this.pageFrom, this.pageTo,
      this.currentBookmarkFilterEnabled(), this.currentBookmarkLocation());
    if (ehBookmarkStore.hasEquivalent(draft)) {
      this.statusText = 'Duplicate bookmark';
      this.showFloatingStatus('Duplicate bookmark');
      return;
    }
    this.addBookmarkDraft = draft;
    this.editingBookmarkId = '';
    this.addBookmarkDialogVisible = true;
  }

  private openEditBookmarkDialog(bookmark: SearchBookmarkInfo): void {
    this.addBookmarkDraft = {
      id: bookmark.id,
      name: bookmark.name,
      mode: bookmark.mode,
      category: bookmark.category,
      keyword: bookmark.keyword,
      advanceSearch: bookmark.advanceSearch,
      minRating: bookmark.minRating,
      pageFrom: bookmark.pageFrom,
      pageTo: bookmark.pageTo,
      filterEnabled: bookmark.filterEnabled,
      location: bookmark.location,
      time: bookmark.time
    };
    this.editingBookmarkId = bookmark.id;
    this.addBookmarkDialogVisible = true;
  }


  private confirmAddBookmark(bookmark: SearchBookmarkInfo): void {
    const name = bookmark.name.trim();
    if (name.length === 0) {
      this.statusText = 'Bookmark name is empty';
      return;
    }
    const wasEditing = this.editingBookmarkId.length > 0;
    const saved = wasEditing ? ehBookmarkStore.updateBookmark(bookmark) :
      ehBookmarkStore.addBookmark(ehBookmarkStore.createBookmark(name, bookmark.mode, bookmark.category,
        bookmark.keyword, bookmark.advanceSearch, bookmark.minRating, bookmark.pageFrom, bookmark.pageTo,
        bookmark.filterEnabled, bookmark.location));
    if (!saved) {
      this.statusText = 'Duplicate bookmark';
      this.showFloatingStatus(this.statusText);
      return;
    }
    this.addBookmarkDialogVisible = false;
    this.editingBookmarkId = '';
    this.refreshSearchBookmarks();
    this.statusText = wasEditing ? 'Bookmark updated' : 'Bookmark added';
  }

  private removeSearchBookmark(bookmark: SearchBookmarkInfo): void {
    ehBookmarkStore.removeBookmark(bookmark.id);
    this.refreshSearchBookmarks();
    this.statusText = 'Bookmark removed';
  }

  private openBookmarkManager(): void {
    this.refreshSearchBookmarks();
    this.showBookmarkManager = true;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
  }

  private closeBookmarkManager(): void {
    this.showBookmarkManager = false;
    this.activeSplitPane = this.showDetail ? SPLIT_PANE_FOCUS_RIGHT : SPLIT_PANE_FOCUS_LEFT;
  }

  private renameSearchBookmark(bookmark: SearchBookmarkInfo, name: string): void {
    if (!ehBookmarkStore.renameBookmark(bookmark.id, name)) {
      this.statusText = name.trim().length === 0 ? 'Bookmark name is empty' : 'Bookmark update failed';
      return;
    }
    this.refreshSearchBookmarks();
    this.statusText = 'Bookmark updated';
  }

  private moveSearchBookmarkToIndex(from: number, to: number): void {
    if (ehBookmarkStore.moveBookmarkToIndex(from, to)) {
      this.refreshSearchBookmarks();
      this.statusText = 'Bookmark updated';
    }
  }

  private openSearchBookmark(bookmark: SearchBookmarkInfo): void {
    const hasAdvancedParams = this.bookmarkHasAdvancedParams(bookmark);
    const showSearchOptions = hasAdvancedParams || bookmark.category !== GalleryCategory.None;
    const draft: SearchResultDraft = {
      keyword: bookmark.keyword,
      mode: bookmark.mode,
      category: bookmark.category,
      advancedEnabled: hasAdvancedParams,
      advanceSearch: bookmark.advanceSearch === -1 ? DEFAULT_ADVANCE_SEARCH : bookmark.advanceSearch,
      minRating: bookmark.minRating,
      pageFrom: bookmark.pageFrom,
      pageTo: bookmark.pageTo,
      filterActive: false,
      searchFilterEnabled: bookmark.filterEnabled,
      searchAdvancedPanelOpened: showSearchOptions,
      submitted: true,
      sourceRoute: bookmark.location,
      imagePath: '',
      imageUseSimilarityScan: false,
      imageOnlySearchCovers: false,
      imageShowExpunged: false
    };
    if (!this.isSearchResultScene) {
      this.captureSearchOrigin();
      this.searchResultDraft = draft;
      this.presentSearchResultScene();
      return;
    }
    this.keyword = draft.keyword;
    this.searchMode = draft.mode;
    this.searchCategory = draft.category;
    this.advancedSearchEnabled = draft.advancedEnabled;
    this.advanceSearch = draft.advanceSearch;
    this.minRating = draft.minRating;
    this.pageFrom = draft.pageFrom;
    this.pageTo = draft.pageTo;
    this.searchFilterEnabled = draft.searchFilterEnabled;
    this.searchAdvancedPanelOpened = draft.searchAdvancedPanelOpened;
    this.searchSubmitted = true;
    this.hasFirstRefresh = true;
    this.resetListScroll();
    this.loadListPage(0);
  }

  private applySearch(): void {
    this.fabExpanded = false;
    this.keyword = normalizeSubmittedSearchKeyword(this.keyword);
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

  private startImageSearch(path: string, useSimilarityScan: boolean, onlySearchCovers: boolean): void {
    if (path.length === 0) {
      this.statusText = 'No image selected for search';
      return;
    }
    this.fabExpanded = false;
    const draft: SearchResultDraft = {
      keyword: '',
      mode: ListMode.ImageSearch,
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
      imagePath: path,
      imageUseSimilarityScan: useSimilarityScan,
      imageOnlySearchCovers: onlySearchCovers,
      imageShowExpunged: true
    };
    if (!this.isSearchResultScene) {
      this.captureSearchOrigin();
      this.searchResultDraft = draft;
      this.presentSearchResultScene();
      return;
    }
    this.keyword = '';
    this.searchMode = ListMode.ImageSearch;
    this.searchCategory = GalleryCategory.None;
    this.advancedSearchEnabled = false;
    this.advanceSearch = DEFAULT_ADVANCE_SEARCH;
    this.minRating = -1;
    this.pageFrom = -1;
    this.pageTo = -1;
    this.imageSearchPath = path;
    this.imageSearchUseSimilarityScan = useSimilarityScan;
    this.imageSearchOnlyCovers = onlySearchCovers;
    this.imageSearchShowExpunged = true;
    this.searchSubmitted = true;
    this.hasFirstRefresh = true;
    this.resetListScroll();
    this.loadListPage(0);
  }

  private rememberSearchKeyword(keyword: string): void {
    recordSearchHistory(keyword);
  }

  private changeFavoriteCat(favCat: number): void {
    if (this.sourceRoute !== GalleryRoute.Favorites || favCat === this.favoriteCat) {
      return;
    }
    this.favoriteCat = favCat;
    recentFavoriteCat = favCat;
    this.hasFirstRefresh = true;
    this.resetListScroll();
    this.loadListPage(0, false);
  }

  private favoriteSceneTitle(): string {
    if (this.sourceRoute !== GalleryRoute.Favorites || this.favoriteCat === FavListUrlBuilder.FAV_CAT_ALL) {
      return gallerySearchTitle(this.sourceRoute, this.keyword, this.filterActive);
    }
    return favoriteCategoryName(this.favoriteCat, this.favoriteCategories);
  }

  private openSearchScene(): void {
    this.fabExpanded = false;
    if (this.useLocalProvider) {
      this.openLocalSearchBar();
      return;
    }
    this.captureSearchOrigin();
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
    this.presentSearchResultScene();
  }

  private openLocalSearchBar(): void {
    this.localSearchBarVisible = true;
    this.searchSubmitted = false;
    this.galleries = [];
    this.resultCount = '';
    this.nextUrl = '';
    this.statusText = '';
    this.saveListCache();
    this.saveNavigationCache();
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
    this.saveNavigationCache();
    this.loadListPage(0);
  }

  private closeSearchResultScene(): void {
    if (this.searchBackTransitionPending) {
      return;
    }
    this.searchBackTransitionPending = true;
    setTimeout(() => {
      this.finishCloseSearchResultScene();
    }, 0);
  }

  private finishCloseSearchResultScene(): void {
    this.searchBackTransitionPending = false;
    const frame = this.nestedSearchFrames.pop();
    if (frame !== undefined) {
      this.searchResultDraft = cloneSearchResultDraft(frame.draft);
      this.showDetail = frame.showDetail;
      this.detailLink = cloneGalleryDetailLink(frame.detailLink);
      this.detail = cloneGalleryDetail(frame.detail);
      this.detailStatus = frame.detailStatus;
      this.detailRequestUrl = frame.detailRequestUrl;
      this.detailScrollOffset = frame.detailScrollOffset;
      this.searchResultDetailOpened = frame.showDetail;
      this.activeSplitPane = frame.showDetail ? SPLIT_PANE_FOCUS_RIGHT : SPLIT_PANE_FOCUS_LEFT;
      this.searchResultSceneRevision++;
      this.saveNavigationCache();
      return;
    }
    this.showSearchResultScene = false;
    this.searchResultDraft = createEmptySearchResultDraft();
    const restoreRightPane = this.searchOriginShowDetail;
    this.restoreSearchOrigin();
    this.activeSplitPane = restoreRightPane ? SPLIT_PANE_FOCUS_RIGHT : SPLIT_PANE_FOCUS_LEFT;
    this.saveNavigationCache();
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
    const detailLink = createGalleryDetailLinkFromGallery(gallery, this.activeSite, this.requestUrl);
    this.openDetailLink(detailLink);
  }

  private updateVisibleLocalFavorite(detail: GalleryDetail): void {
    if (this.sourceRoute !== GalleryRoute.Favorites || !ehLocalFavoritesStore.contains(detail.gid)) {
      return;
    }
    const next: GalleryInfo[] = [];
    let changed = false;
    for (let i = 0; i < this.galleries.length; i++) {
      if (this.galleries[i].gid === detail.gid) {
        const updated = cloneGalleryInfo(detail);
        updated.favoriteSlot = -1;
        updated.favoriteName = undefined;
        next.push(updated);
        changed = true;
      } else {
        next.push(this.galleries[i]);
      }
    }
    if (!changed) {
      return;
    }
    this.galleries = next;
    this.saveListCache();
  }

  private openDetailLink(detailLink: GalleryDetailLink): void {
    if (this.delegateDetailToHost && this.onOpenDetailInHost(detailLink)) {
      return;
    }
    this.restoreDetailWithFade = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    if (this.showSearchResultScene) {
      this.searchResultDetailOpened = true;
    }
    this.showDetail = true;
    if (!this.delegateDetailToHost) {
      markCurrentRouteRightPane(this.useSplitLayout());
    }
    this.detailLink = detailLink;
    this.detail = initialDetailForLink(detailLink);
    this.detailStatus = '';
    this.detailRequestUrl = detailLink.url;
    this.renderVersion++;
    this.saveNavigationCache();
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
    const detailLink = createGalleryDetailLink(gid, token, 'Gallery ' + gid.toString(), this.activeSite, this.requestUrl);
    this.openDetailLink(detailLink);
  }

  private clearDelegatedDetailLayer(): void {
    this.showDetail = false;
    this.showReader = false;
    this.restoreDetailWithFade = false;
    this.detailLink = createEmptyGalleryDetailLink();
    this.detail = createEmptyDetail();
    this.detailRequestUrl = '';
    this.detailScrollOffset = 0;
  }

  private closeDetail(): void {
    this.restoreDetailWithFade = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
    this.searchResultDetailOpened = false;
    this.showDetail = false;
    this.showReader = false;
    if (!this.delegateDetailToHost) {
      markCurrentRouteRightPane(false);
    }
    this.detailLink = createEmptyGalleryDetailLink();
    this.detail = createEmptyDetail();
    this.detailStatus = 'Tap a gallery row to load detail';
    this.detailRequestUrl = '';
    this.detailScrollOffset = 0;
    this.renderVersion++;
    this.saveNavigationCache();
  }

  private closeReader(): void {
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
      this.activateBackHandler();
    }, 0);
  }

  private activateBackHandler(): void {
    if (this.delegateDetailToHost || this.activeBackHandlerRegistered) {
      return;
    }
    this.unregisterActiveBackHandler = pushActiveBackHandler(() => this.handleSystemBack());
    this.activeBackHandlerRegistered = true;
  }

  private openCardActions(gallery: GalleryInfo): void {
    if (gallery.gid <= 0 || gallery.token.length === 0) {
      return;
    }
    this.fabExpanded = false;
    this.cardActionGallery = gallery;
    this.cardActionVisible = true;
  }

  private closeCardActions(): void {
    this.cardActionVisible = false;
    this.cardActionGallery = createEmptyGallery();
  }

  private galleryShareUrl(gallery: GalleryInfo): string {
    return EhUrl.getGalleryDetailUrl(gallery.gid, gallery.token, 0, false, this.activeSite);
  }

  private shareCardGallery(gallery: GalleryInfo): void {
    const context = getAbilityContext();
    const url = this.galleryShareUrl(gallery);
    this.closeCardActions();
    if (context === undefined || url.length === 0) {
      this.statusText = 'Share failed: Ability context is not ready';
      this.renderVersion++;
      return;
    }
    const shareData: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.PLAIN_TEXT,
      content: url,
      title: galleryDisplayTitle(gallery),
      description: 'EhViewer'
    });
    const controller = new systemShare.ShareController(shareData);
    controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DETAIL
    }).then(() => {
      this.statusText = 'Share panel closed';
      this.renderVersion++;
    }).catch((error: Error) => {
      this.statusText = 'Share failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private toggleCardDownload(gallery: GalleryInfo): void {
    this.closeCardActions();
    if (!ehDownloadStore.contains(gallery.gid)) {
      const labels = ehDownloadStore.getLabels();
      const defaultLabel = defaultDownloadLabelChoice();
      if (defaultLabel === DOWNLOAD_LABEL_OPTION_ASK && labels.length > 0) {
        this.pendingDownloadGallery = cloneGalleryInfo(gallery);
        this.downloadLabelOptions = labels;
        this.rememberDownloadLabel = false;
        this.downloadLabelDialogVisible = true;
        return;
      }
      const queued = toggleGalleryDownload(gallery, defaultLabel === DOWNLOAD_LABEL_OPTION_ASK ? '' : defaultLabel);
      this.statusText = queued ? 'Added to download list' : 'Removed from download list';
      this.renderVersion++;
      return;
    }
    const queued = toggleGalleryDownload(gallery);
    this.statusText = queued ? 'Added to download list' : 'Removed from download list';
    this.renderVersion++;
  }

  private confirmCardDownloadLabel(label: string): void {
    if (this.pendingDownloadGallery.gid <= 0) {
      this.downloadLabelDialogVisible = false;
      return;
    }
    const queued = toggleGalleryDownload(this.pendingDownloadGallery, label);
    if (this.rememberDownloadLabel) {
      saveDefaultDownloadLabelChoice(label);
    }
    this.downloadLabelDialogVisible = false;
    this.pendingDownloadGallery = createEmptyGallery();
    this.statusText = queued ? 'Added to download list' : 'Removed from download list';
    this.renderVersion++;
  }

  private deleteHistoryGallery(gallery: GalleryInfo): void {
    const context = getAbilityContext();
    this.closeCardActions();
    if (gallery.gid <= 0) {
      return;
    }
    if (context === undefined) {
      ehHistoryStore.removeGallery(gallery.gid);
      this.galleries = this.galleries.filter((item: GalleryInfo) => item.gid !== gallery.gid);
      this.statusText = 'History deleted';
      this.renderVersion++;
      this.saveListCache();
      return;
    }
    ehHistoryStore.ensureLoaded(context).then(() => {
      ehHistoryStore.removeGallery(gallery.gid);
      return ehHistoryStore.save(context);
    }).then(() => {
      this.statusText = 'History deleted';
      this.loadListPage(0, false);
    }).catch((error: Error) => {
      this.statusText = 'Delete history failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private removeFavoriteGallery(gallery: GalleryInfo): void {
    const context = getAbilityContext();
    this.closeCardActions();
    if (this.sourceRoute !== GalleryRoute.Favorites || gallery.gid <= 0 || gallery.token.length === 0) {
      return;
    }
    if (gallery.favoriteSlot === -1) {
      if (context === undefined) {
        this.statusText = 'Local favorites unavailable';
        this.renderVersion++;
        return;
      }
      this.statusText = 'Removing from local favorites...';
      this.renderVersion++;
      ehLocalFavoritesStore.ensureLoaded(context).then(() => {
        ehLocalFavoritesStore.removeGallery(gallery.gid);
        this.favoriteLocalCount = ehLocalFavoritesStore.count();
        this.galleries = this.galleries.filter((item: GalleryInfo) => item.gid !== gallery.gid);
        this.statusText = 'Removed from local favorites';
        this.showFloatingStatus(this.statusText);
        this.renderVersion++;
        this.saveListCache();
      }).catch((error: Error) => {
        this.statusText = 'Favorite failed: ' + error.message;
        this.renderVersion++;
      });
      return;
    }
    this.statusText = 'Removing from favorites...';
    this.renderVersion++;
    this.client.toggleFavorite(gallery.gid, gallery.token, true, this.activeSite)
      .then((result: ToggleFavoriteResult) => {
        this.statusText = result.message;
        if (result.ok) {
          this.galleries = this.galleries.filter((item: GalleryInfo) => item.gid !== gallery.gid);
          this.saveListCache();
          this.showFloatingStatus(result.message);
        }
        this.renderVersion++;
      }).catch((error: Error) => {
        this.statusText = 'Favorite failed: ' + error.message;
        this.renderVersion++;
      });
  }

  private openSearchResult(request: DetailSearchRequest): void {
    this.showReader = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
    if (this.showSearchResultScene && this.searchResultDetailOpened) {
      this.nestedSearchFrames.push({
        draft: cloneSearchResultDraft(this.searchResultDraft),
        showDetail: this.showDetail,
        detailLink: cloneGalleryDetailLink(this.detailLink),
        detail: cloneGalleryDetail(this.detail),
        detailStatus: this.detailStatus,
        detailRequestUrl: this.detailRequestUrl,
        detailScrollOffset: this.detailScrollOffset
      });
      this.searchResultDetailOpened = false;
    } else {
      this.captureSearchOrigin();
      this.nestedSearchFrames = [];
    }
    this.searchResultDraft = {
      keyword: request.keyword,
      mode: request.mode,
      category: request.category,
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
    this.presentSearchResultScene();
  }

  private updateSceneContentWidth(width: number): void {
    const normalized = Math.floor(width);
    if (normalized <= 0 || Number.isNaN(normalized) || Math.abs(this.sceneContentWidth - normalized) < 1) {
      return;
    }
    this.sceneContentWidth = normalized;
    if (!this.delegateDetailToHost) {
      rememberMainContentWidthVp(normalized);
      markCurrentRouteRightPane(this.useSplitLayout());
    }
  }

  private syncSceneContentWidthFromWindow(): void {
    const width = mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value));
    if (width >= 240) {
      this.updateSceneContentWidth(width);
    }
  }

  onSplitPaneRatioRevisionChange(): void {
    if (!this.splitDragging) {
      this.splitListRatio = splitPaneCurrentRatio();
    }
  }

  private useSplitLayout(): boolean {
    return splitPaneModeEnabled() && this.sceneContentWidth >= SPLIT_PANE_BREAKPOINT &&
      (this.showDetail || this.showBookmarkManager);
  }

  private splitListPaneWidth(): number {
    return splitPaneListWidth(this.sceneContentWidth, this.splitListRatio);
  }

  private splitSidePaneWidth(): number {
    if (!this.useSplitLayout()) {
      return this.sceneContentWidth > 0 ? this.sceneContentWidth : 0;
    }
    return splitPaneSideWidth(this.sceneContentWidth, this.splitListPaneWidth());
  }

  private updateSplitPaneByOffset(offsetX: number): void {
    if (this.sceneContentWidth <= 0) {
      return;
    }
    const targetWidth = splitPaneWidthFromDrag(this.sceneContentWidth, this.splitDragStartWidth, offsetX);
    this.splitListRatio = splitPaneRatioForWidth(this.sceneContentWidth, targetWidth);
  }

  private finishSplitPaneDrag(): void {
    this.splitDragging = false;
    saveSplitPaneRatio(this.splitListRatio);
  }

  private shouldShowSearchResultInLeftPane(): boolean {
    return !this.isSearchResultScene && this.showSearchResultScene && this.useSplitLayout();
  }

  private shouldShowDetailLayer(): boolean {
    return this.showDetail && (!this.showSearchResultScene || this.useSplitLayout() ||
      this.searchResultDetailOpened);
  }

  @Builder
  private searchResultSceneContent() {
    ForEach([this.searchResultSceneRevision], (_revision: number) => {
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
        initialSearchFilterEnabled: this.searchResultDraft.searchFilterEnabled,
        initialSearchSubmitted: this.searchResultDraft.submitted,
        initialSearchAdvancedPanelOpened: this.searchResultDraft.searchAdvancedPanelOpened,
        initialImagePath: this.searchResultDraft.imagePath,
        initialImageUseSimilarityScan: this.searchResultDraft.imageUseSimilarityScan,
        initialImageOnlySearchCovers: this.searchResultDraft.imageOnlySearchCovers,
        initialImageShowExpunged: this.searchResultDraft.imageShowExpunged,
        isSearchResultScene: true,
        delegateDetailToHost: true,
        onOpenDetailInHost: (link: GalleryDetailLink) => {
          this.openDetailLink(link);
          return true;
        },
        onBack: () => {
          this.closeSearchResultScene();
        }
      })
    }, (revision: number) => revision.toString())
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
          GalleryListContent({
            sceneTitle: this.sceneTitle,
            listMode: this.listMode,
            keyword: this.keyword,
            searchTitle: this.useLocalProvider && this.keyword.trim().length === 0 ? this.sceneTitle :
              this.favoriteSceneTitle(),
            actionsExpanded: this.fabExpanded,
            filterActive: this.filterActive,
            showFavoriteButton: this.sourceRoute === GalleryRoute.Favorites && !this.isSearchResultScene,
            showBookmarkButton: this.canUseBookmarks(),
            bookmarks: this.searchBookmarks,
            favoriteCat: this.favoriteCat,
            favoriteCategories: this.favoriteCategories,
            favoriteLocalCount: this.favoriteLocalCount,
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
            pageFrom: this.pageFrom,
            pageTo: this.pageTo,
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
            onFavoriteCatChange: (favCat: number) => {
              this.changeFavoriteCat(favCat);
            },
            onFavoriteDrawerOpen: () => {
              this.refreshLocalFavoriteCount();
            },
            onBookmarkDrawerOpen: () => {
              this.refreshSearchBookmarks();
            },
            onBookmarkSettings: () => {
              this.openBookmarkManager();
            },
            onAddBookmark: () => {
              this.openAddBookmarkDialog();
            },
            onSelectBookmark: (bookmark: SearchBookmarkInfo) => {
              this.openSearchBookmark(bookmark);
            },
            onDeleteBookmark: (bookmark: SearchBookmarkInfo) => {
              this.removeSearchBookmark(bookmark);
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
            onPageFromChange: (value: number) => {
              this.searchAdvancedPanelOpened = true;
              this.pageFrom = value;
              if (this.isSearchResultScene || this.useLocalProvider) {
                this.searchSubmitted = false;
              }
            },
            onPageToChange: (value: number) => {
              this.searchAdvancedPanelOpened = true;
              this.pageTo = value;
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
              } else if (this.isSearchResultScene) {
                this.closeSearchResultToParent();
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
            onImageSearch: (path: string, useSimilarityScan: boolean, onlySearchCovers: boolean) => {
              this.startImageSearch(path, useSimilarityScan, onlySearchCovers);
            },
            onSelectGallery: (gallery: GalleryInfo) => {
              this.loadDetail(gallery);
            },
            onLongPressGallery: (gallery: GalleryInfo) => {
              this.openCardActions(gallery);
            },
            shouldHandleLocalBack: () => {
              return !this.useSplitLayout() || this.activeSplitPane === SPLIT_PANE_FOCUS_LEFT;
            },
            layoutWidthHint: this.useSplitLayout() ? this.splitListPaneWidth() : this.sceneContentWidth,
            scrollResetVersion: this.scrollResetVersion,
            initialScrollOffset: this.isSearchResultScene ? 0 : this.listScrollOffset,
            onScrollUpdate: (offset: number) => {
              this.listScrollOffset = offset;
              updateGalleryListScrollCache(this.cacheKey(), this.listScrollOffset);
            }
            })
              .width(this.useSplitLayout() ? this.splitListPaneWidth() : '100%')
              .height('100%')
              .onTouch((event: TouchEvent) => {
                if (shouldUpdateSplitPaneFocus(event)) {
                  this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
                }
              })
              .animation({
                duration: this.splitDragging ? 0 : 220,
                curve: Curve.EaseOut
              })

          if (!this.isSearchResultScene && this.showSearchResultScene) {
            Column() {
              this.searchResultSceneContent()
            }
              .width(this.shouldShowSearchResultInLeftPane() ? this.splitListPaneWidth() : '100%')
              .height('100%')
              .backgroundColor(themePageBackground())
              .onTouch((event: TouchEvent) => {
                if (shouldUpdateSplitPaneFocus(event)) {
                  this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
                }
              })
              .zIndex(4)
          }

          if (this.showBookmarkManager) {
            SearchBookmarkManagerScene({
              bookmarks: this.searchBookmarks,
              statusBarHeight: this.galleryStatusBarVp(),
              onBack: () => {
                this.closeBookmarkManager();
              },
              onRename: (bookmark: SearchBookmarkInfo, name: string) => {
                this.renameSearchBookmark(bookmark, name);
              },
              onEdit: (bookmark: SearchBookmarkInfo) => {
                this.openEditBookmarkDialog(bookmark);
              },
              onMoveIndex: (from: number, to: number) => {
                this.moveSearchBookmarkToIndex(from, to);
              },
              onDelete: (bookmark: SearchBookmarkInfo) => {
                this.removeSearchBookmark(bookmark);
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
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.move(TransitionEdge.END).animation({ duration: 260, curve: Curve.EaseOut }),
                TransitionEffect.move(TransitionEdge.END).animation({ duration: 220, curve: Curve.EaseIn })))
              .zIndex(29)
          }

          if (this.addBookmarkDialogVisible) {
            Stack({ alignContent: Alignment.Center }) {
              PopupScrim({
                showCutout: this.addBookmarkPopupWidth > 0 && this.addBookmarkPopupHeight > 0,
                cutoutWidth: this.addBookmarkPopupWidth,
                cutoutHeight: this.addBookmarkPopupHeight,
                cutoutRadius: uiDialogSurfaceRadius(),
                onDismiss: () => {
                  this.addBookmarkDialogVisible = false;
                }
              })

              Column() {
                BookmarkEditor({
                  bookmark: this.addBookmarkDraft,
                  editing: this.editingBookmarkId.length > 0,
                  onCancel: () => { this.addBookmarkDialogVisible = false; },
                  onSave: (bookmark: SearchBookmarkInfo) => { this.confirmAddBookmark(bookmark); }
                })
              }
              .width('90%')
              .height('85%')
              .constraintSize({ maxWidth: 560, maxHeight: 780 })
              .padding(18)
              .backgroundColor(uiMaterialBackground(uiDialogSurfaceBackground()))
              .shadow(uiDialogSurfaceShadow())
              .borderRadius(uiDialogSurfaceRadius())
              .backgroundBlurStyle(uiDialogBlurStyle(), uiDialogBlurOptions())
              .systemMaterial(uiDialogMaterial())
              .onAreaChange((_oldArea: Area, newArea: Area) => {
                this.addBookmarkPopupWidth = Number.parseFloat(newArea.width.toString());
                this.addBookmarkPopupHeight = Number.parseFloat(newArea.height.toString());
              })
              .onClick(() => {})
            }
              .width('100%')
              .height('100%')
              .zIndex(30)
              .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
          }

          if ((this.showDetail || this.showBookmarkManager) && !this.showReader) {
            SplitPaneDivider({
              x: this.useSplitLayout() ? this.splitListPaneWidth() : 0,
              dividerVisible: this.useSplitLayout() && !this.addBookmarkDialogVisible,
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

          if (this.shouldShowDetailLayer()) {
            GalleryDetailHostScene({
              detailLink: this.detailLink,
              listRequestUrl: this.requestUrl,
              initialDetailScrollOffset: this.detailScrollOffset,
              onBack: () => {
                this.closeDetail();
              },
              onShowEmbeddedReader: () => {
                this.showReader = true;
              },
              onOpenSearch: (request: DetailSearchRequest) => {
                this.openSearchResult(request);
              },
              onDetailLoaded: (detail: GalleryDetail) => {
                this.detail = detail;
                this.updateVisibleLocalFavorite(detail);
              },
              onDetailScrollUpdate: (offset: number) => {
                this.detailScrollOffset = offset;
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
              .animation({
                duration: this.splitDragging ? 0 : 220,
                curve: Curve.EaseOut
              })
              .transition(this.restoreDetailWithFade ?
                TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }) :
                TransitionEffect.move(TransitionEdge.END).animation({ duration: 300, curve: Curve.EaseOut }))
          }

          if (this.cardActionVisible) {
            GalleryCardActionOverlay({
              gallery: this.cardActionGallery,
              isHistory: this.sourceRoute === GalleryRoute.History,
              isFavorite: this.sourceRoute === GalleryRoute.Favorites,
              onDismiss: () => {
                this.closeCardActions();
              },
              onShare: (gallery: GalleryInfo) => {
                this.shareCardGallery(gallery);
              },
              onDownload: (gallery: GalleryInfo) => {
                this.toggleCardDownload(gallery);
              },
              onDeleteHistory: (gallery: GalleryInfo) => {
                this.deleteHistoryGallery(gallery);
              },
              onRemoveFavorite: (gallery: GalleryInfo) => {
                this.removeFavoriteGallery(gallery);
              }
            })
              .zIndex(30)
              .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
          }

          if (this.downloadLabelDialogVisible) {
            DownloadLabelSelectionDialog({
              title: 'Download labels',
              labels: this.downloadLabelOptions,
              selectedLabel: '',
              includeAsk: false,
              showRemember: true,
              panelMaxHeight: 680,
              onRememberChange: (remember: boolean) => {
                this.rememberDownloadLabel = remember;
              },
              onSelect: (label: string) => {
                this.confirmCardDownloadLabel(label);
              },
              onClose: () => {
                this.downloadLabelDialogVisible = false;
                this.pendingDownloadGallery = createEmptyGallery();
              }
            })
              .zIndex(31)
              .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
          }

          if (this.showReader) {
            ReaderSessionScene({
              restoreAppChromeOnExit: true,
              onBack: () => {
                this.closeReader();
              }
            })
              .width('100%')
              .height('100%')
              .zIndex(50)
          }
        }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.updateSceneContentWidth(areaDimensionToVp(newArea.width, (value: number) => this.getUIContext().px2vp(value)));
      })
  }
}
