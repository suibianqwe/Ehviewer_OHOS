import { GalleryCategory, GalleryDetail, GalleryRoute, GallerySite, TopListBucket, TopListDetail, TopListInfo, TopListItem, TopListKind } from '../model/GalleryModels';
import { EhHttpClient, TopListLoadResult } from '../services/EhHttpClient';
import { AsyncRequestGate } from '../services/AsyncRequestGate';
import {
  TRANSLATION_ENABLED_KEY,
  ehTranslationService,
  translationPriorityForIndex
} from '../services/EhTranslationService';
import { TRANSLATION_BUTTONS_VISIBLE_KEY } from '../services/EhSettingsStore';
import { DEFAULT_ADVANCE_SEARCH, ListMode } from '../services/EhUrl';
import { DetailSearchRequest } from '../services/GalleryDetailActionSupport';
import {
  createGalleryDetailLink,
  createEmptyGalleryDetailLink,
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
import {
  themeDividerColor,
  themePageBackground,
  themeAccentTextColor,
  themePrimaryText,
  themeSecondaryText,
  themeSurface,
  themeSurfaceVariant,
  themeTransparentColor
} from '../shared/EhTheme';
import {
  uiAdaptiveToolbarHeight,
  uiRadius,
  uiTabHeight
} from '../shared/EhUiStyle';
import { LANGUAGE_REVISION_KEY, STATUS_BAR_HEIGHT_KEY, setActiveBackHandler, runDetailBackHandler, createEmptyDetail, createEmptyTopListDetail, createEmptyTopListInfo, createEmptyTopListBucket, createEmptyTopListItem, cloneGalleryDetail, cloneGalleryInfo, cloneTopListDetail, nextFloatingToolbarOffset, currentGallerySite, uiText } from '../shared/EhShared';
import { ActionBubble, GalleryListScene, GalleryListStateView } from './GalleryScenes';
import { GalleryDetailHostScene } from './GalleryDetailHostScene';
import { ReaderSessionScene } from './ReaderHostScene';
import { FloatingToolbarHost } from './NavigationComponents';
import { TranslationText } from './TranslationComponents';
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

interface TopListNavigationCache {
  activeSplitPane: string;
  selectedIndex: number;
  showGalleryList: boolean;
  galleryListTitle: string;
  galleryListModeLabel: string;
  galleryFollow: string;
  galleryKeyword: string;
  gallerySearchMode: ListMode;
  galleryRoute: GalleryRoute;
  galleryUseForcedMode: boolean;
  galleryForcedMode: ListMode;
  showDetail: boolean;
  restoreDetailWithFade: boolean;
  detailLink: GalleryDetailLink;
  detail: GalleryDetail;
  detailStatus: string;
  detailRequestUrl: string;
  detailScrollOffset: number;
  showTagSearch: boolean;
  tagSearchTitle: string;
  tagSearchKeyword: string;
  tagSearchMode: ListMode;
  tagSearchCategory?: number;
  tagSearchImagePath: string;
  tagSearchImageUseSimilarity: boolean;
  tagSearchImageOnlyCovers: boolean;
  tagSearchImageShowExpunged: boolean;
  toolbarOffsetY: number;
}

let topListNavigationCache: TopListNavigationCache | null = null;

function cloneTopListDetailLink(link: GalleryDetailLink): GalleryDetailLink {
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
export struct TopListScene {
  private client: EhHttpClient = new EhHttpClient();
  private loadRequestGate: AsyncRequestGate = new AsyncRequestGate();
  @Prop @Watch('onResetVersionChanged') resetVersion: number = 0;
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
  @State gallerySearchMode: ListMode = ListMode.Normal;
  @State galleryRoute: GalleryRoute = GalleryRoute.TopLists;
  @State galleryUseForcedMode: boolean = false;
  @State galleryForcedMode: ListMode = ListMode.Normal;
  @State showDetail: boolean = false;
  @State showReader: boolean = false;
  private readerClosing: boolean = false;
  @State restoreDetailWithFade: boolean = false;
  @State detailLink: GalleryDetailLink = createEmptyGalleryDetailLink();
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = 'Tap a ranking item to load detail';
  @State detailRequestUrl: string = '';
  @State renderVersion: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @State toolbarOffsetY: number = 0;
  @State showTagSearch: boolean = false;
  @State tagSearchTitle: string = 'Search';
  @State tagSearchKeyword: string = '';
  @State tagSearchMode: ListMode = ListMode.Tag;
  @State tagSearchCategory: number = GalleryCategory.None;
  @State tagSearchImagePath: string = '';
  @State tagSearchImageUseSimilarity: boolean = false;
  @State tagSearchImageOnlyCovers: boolean = false;
  @State tagSearchImageShowExpunged: boolean = false;
  @State sceneContentWidth: number = 0;
  @State splitListRatio: number = splitPaneCurrentRatio();
  @State splitDragging: boolean = false;
  @State activeSplitPane: string = SPLIT_PANE_FOCUS_LEFT;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  @StorageProp(SPLIT_PANE_RATIO_REVISION_KEY) @Watch('onSplitPaneRatioRevisionChange') splitPaneRatioRevision: number = 0;
  @StorageLink(TRANSLATION_ENABLED_KEY) translationEnabled: boolean = false;
  @StorageProp(TRANSLATION_BUTTONS_VISIBLE_KEY) translationButtonsVisible: boolean = true;
  private topListScrollOffset: number = 0;
  private detailScrollOffset: number = 0;
  private toolbarRestoring: boolean = false;
  private splitDragStartWidth: number = 0;

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    this.restoreNavigationCache();
    this.syncSceneContentWidthFromWindow();
    markCurrentRouteRightPane(this.useSplitLayout());
    setActiveBackHandler(() => this.handleSystemBack());
    this.loadTopList();
    setTimeout(() => {
      this.syncSceneContentWidthFromWindow();
    }, 0);
  }

  aboutToDisappear(): void {
    this.saveNavigationCache();
  }

  onResetVersionChanged(): void {
    this.resetToTopLevel();
  }

  private handleSystemBack(): boolean {
    if (this.useSplitLayout() && this.activeSplitPane === SPLIT_PANE_FOCUS_LEFT) {
      if (this.showGalleryList) { this.closeGalleryList(); return true; }
      if (this.showTagSearch) { this.closeTagSearch(); return true; }
    }
    if (this.showTagSearch) { this.closeTagSearch(); return true; }
    if (this.showReader) { this.closeReader(); return true; }
    if (this.showDetail) {
      if (runDetailBackHandler()) { return true; }
      this.closeDetail();
      return true;
    }
    if (this.showGalleryList) { this.closeGalleryList(); return true; }
    return false;
  }

  private resetToTopLevel(): void {
    if (this.showReader) {
      leaveEmbeddedReaderFullscreen();
    }
    this.showTagSearch = false;
    this.showReader = false;
    this.showDetail = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
    this.showGalleryList = false;
    this.restoreDetailWithFade = false;
    this.detailLink = createEmptyGalleryDetailLink();
    this.detail = createEmptyDetail();
    this.detailStatus = 'Tap a ranking item to load detail';
    this.detailRequestUrl = '';
    this.detailScrollOffset = 0;
    this.galleryFollow = '';
    this.galleryKeyword = '';
    this.gallerySearchMode = ListMode.Normal;
    this.galleryUseForcedMode = false;
    this.tagSearchTitle = 'Search';
    this.tagSearchKeyword = '';
    this.tagSearchMode = ListMode.Tag;
    this.tagSearchCategory = GalleryCategory.None;
    this.tagSearchImagePath = '';
    this.tagSearchImageUseSimilarity = false;
    this.tagSearchImageOnlyCovers = false;
    this.tagSearchImageShowExpunged = false;
    this.restoreBackHandler();
    this.renderVersion++;
    this.clearNavigationCache();
  }

  private restoreNavigationCache(): void {
    if (topListNavigationCache === null) {
      return;
    }
    const cache = topListNavigationCache;
    this.selectedIndex = cache.selectedIndex;
    this.showGalleryList = cache.showGalleryList;
    this.galleryListTitle = cache.galleryListTitle;
    this.galleryListModeLabel = cache.galleryListModeLabel;
    this.galleryFollow = cache.galleryFollow;
    this.galleryKeyword = cache.galleryKeyword;
    this.gallerySearchMode = cache.gallerySearchMode;
    this.galleryRoute = cache.galleryRoute;
    this.galleryUseForcedMode = cache.galleryUseForcedMode;
    this.galleryForcedMode = cache.galleryForcedMode;
    this.showDetail = cache.showDetail;
    this.activeSplitPane = normalizeSplitPaneFocus(cache.activeSplitPane, cache.showDetail);
    this.restoreDetailWithFade = cache.showDetail && shouldFadeRestoredRightPane();
    this.detailLink = cloneTopListDetailLink(cache.detailLink);
    this.detail = cloneGalleryDetail(cache.detail);
    this.detailStatus = cache.detailStatus;
    this.detailRequestUrl = cache.detailRequestUrl;
    this.detailScrollOffset = cache.detailScrollOffset;
    this.showTagSearch = cache.showTagSearch;
    this.tagSearchTitle = cache.tagSearchTitle;
    this.tagSearchKeyword = cache.tagSearchKeyword;
    this.tagSearchMode = cache.tagSearchMode;
    this.tagSearchCategory = cache.tagSearchCategory === undefined ? GalleryCategory.None : cache.tagSearchCategory;
    this.tagSearchImagePath = cache.tagSearchImagePath;
    this.tagSearchImageUseSimilarity = cache.tagSearchImageUseSimilarity;
    this.tagSearchImageOnlyCovers = cache.tagSearchImageOnlyCovers;
    this.tagSearchImageShowExpunged = cache.tagSearchImageShowExpunged;
    this.toolbarOffsetY = cache.toolbarOffsetY;
  }

  private saveNavigationCache(): void {
    topListNavigationCache = {
      activeSplitPane: this.activeSplitPane,
      selectedIndex: this.selectedIndex,
      showGalleryList: this.showGalleryList,
      galleryListTitle: this.galleryListTitle,
      galleryListModeLabel: this.galleryListModeLabel,
      galleryFollow: this.galleryFollow,
      galleryKeyword: this.galleryKeyword,
      gallerySearchMode: this.gallerySearchMode,
      galleryRoute: this.galleryRoute,
      galleryUseForcedMode: this.galleryUseForcedMode,
      galleryForcedMode: this.galleryForcedMode,
      showDetail: this.showDetail,
      restoreDetailWithFade: this.restoreDetailWithFade,
      detailLink: cloneTopListDetailLink(this.detailLink),
      detail: cloneGalleryDetail(this.detail),
      detailStatus: this.detailStatus,
      detailRequestUrl: this.detailRequestUrl,
      detailScrollOffset: this.detailScrollOffset,
      showTagSearch: this.showTagSearch,
      tagSearchTitle: this.tagSearchTitle,
      tagSearchKeyword: this.tagSearchKeyword,
      tagSearchMode: this.tagSearchMode,
      tagSearchCategory: this.tagSearchCategory,
      tagSearchImagePath: this.tagSearchImagePath,
      tagSearchImageUseSimilarity: this.tagSearchImageUseSimilarity,
      tagSearchImageOnlyCovers: this.tagSearchImageOnlyCovers,
      tagSearchImageShowExpunged: this.tagSearchImageShowExpunged,
      toolbarOffsetY: this.toolbarOffsetY
    };
  }

  private clearNavigationCache(): void {
    topListNavigationCache = null;
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
    this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
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

  private gallerySite(): GallerySite {
    return currentGallerySite();
  }

  private loadTopList(): void {
    const generation = this.loadRequestGate.begin();
    this.statusText = 'Loading top lists...';
    this.renderVersion++;
    this.client.loadTopList(GallerySite.E).then((result: TopListLoadResult) => {
      if (!this.loadRequestGate.isCurrent(generation)) {
        return;
      }
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
      if (!this.loadRequestGate.isCurrent(generation)) {
        return;
      }
      this.statusText = 'Load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private openBucket(bucket: TopListBucket): void {
    this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
    this.galleryListTitle = 'Gallery Toplists';
    this.galleryListModeLabel = bucket.title;
    this.galleryFollow = bucket.follow;
    this.galleryKeyword = '';
    this.gallerySearchMode = ListMode.Normal;
    this.galleryRoute = GalleryRoute.TopLists;
    this.galleryUseForcedMode = false;
    this.showGalleryList = true;
    this.saveNavigationCache();
  }

  private openTopListItem(item: TopListItem, info: TopListInfo): void {
    if (info.kind === TopListKind.Gallery && item.gid.length > 0 && item.token.length > 0) {
      this.loadDetailFromItem(item);
      return;
    }

    this.galleryListTitle = info.title;
    this.galleryListModeLabel = 'Related galleries';
    this.galleryFollow = '';
    this.gallerySearchMode = this.searchModeForTopListItem(item, info);
    this.galleryKeyword = this.searchKeywordForTopListItem(item, this.gallerySearchMode);
    this.galleryRoute = GalleryRoute.Home;
    this.galleryUseForcedMode = false;
    this.galleryForcedMode = ListMode.Normal;
    this.showGalleryList = true;
    this.saveNavigationCache();
  }

  private searchModeForTopListItem(_item: TopListItem, info: TopListInfo): ListMode {
    if (info.kind !== TopListKind.Gallery) {
      return ListMode.Uploader;
    }
    if (_item.tag.length > 0) {
      return ListMode.Tag;
    }
    return ListMode.Normal;
  }

  private searchKeywordForTopListItem(item: TopListItem, mode: ListMode): string {
    if (mode === ListMode.Tag && item.tag.length > 0) {
      return item.tag;
    }
    return item.value;
  }

  private closeGalleryList(): void {
    this.showGalleryList = false;
    this.galleryFollow = '';
    this.galleryKeyword = '';
    this.gallerySearchMode = ListMode.Normal;
    this.galleryUseForcedMode = false;
    this.saveNavigationCache();
    setTimeout(() => {
      setActiveBackHandler(() => this.handleSystemBack());
    }, 0);
  }

  private loadDetailFromItem(item: TopListItem): void {
    const gid = Number.parseInt(item.gid);
    if (Number.isNaN(gid)) {
      this.statusText = 'Invalid gallery id: ' + item.gid;
      return;
    }

    this.restoreDetailWithFade = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.showDetail = true;
    markCurrentRouteRightPane(this.useSplitLayout());
    const site = this.gallerySite();
    const detailLink = createGalleryDetailLink(gid, item.token, item.value, site, this.requestUrl);
    this.detailLink = detailLink;
    this.detail = initialDetailForLink(detailLink);
    this.detailStatus = '';
    this.detailRequestUrl = detailLink.url;
    this.renderVersion++;
    this.saveNavigationCache();
  }

  private closeDetail(): void {
    this.restoreDetailWithFade = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
    this.showDetail = false;
    this.showReader = false;
    markCurrentRouteRightPane(false);
    this.detailLink = createEmptyGalleryDetailLink();
    this.detail = createEmptyDetail();
    this.detailStatus = 'Tap a ranking item to load detail';
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
      setActiveBackHandler(() => this.handleSystemBack());
    }, 0);
  }

  private currentInfo(): TopListInfo {
    if (this.topList.lists.length === 0 || this.selectedIndex < 0 || this.selectedIndex >= this.topList.lists.length) {
      return createEmptyTopListInfo();
    }
    return this.topList.lists[this.selectedIndex];
  }

  private updateToolbarForScroll(contentOffset: number, scrollOffset: number): number {
    if (scrollOffset === 0) {
      return scrollOffset;
    }
    if (contentOffset <= 4) {
      this.toolbarRestoring = false;
      this.toolbarOffsetY = 0;
      return scrollOffset;
    }
    if (scrollOffset > 0 && this.toolbarVisibleHeight() > 0) {
      const previousOffsetY = this.toolbarOffsetY;
      this.toolbarRestoring = false;
      this.toolbarOffsetY = nextFloatingToolbarOffset(this.toolbarOffsetY, scrollOffset, contentOffset, this.floatingToolbarHeight());
      const consumedOffset = Math.max(0, previousOffsetY - this.toolbarOffsetY);
      return Math.max(0, scrollOffset - consumedOffset);
    }
    if (scrollOffset < 0 && this.toolbarOffsetY < 0) {
      this.restoreToolbarOnReverseScroll();
    }
    return scrollOffset;
  }

  private toolbarVisibleHeight(): number {
    return Math.max(0, Math.min(this.floatingToolbarHeight(), this.floatingToolbarHeight() + this.toolbarOffsetY));
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

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  private floatingToolbarHeight(): number {
    return this.statusBarVp() + uiAdaptiveToolbarHeight(this.sceneContentWidth);
  }

  private updateSceneContentWidth(width: number): void {
    const normalized = Math.floor(width);
    if (normalized <= 0 || Number.isNaN(normalized) || Math.abs(this.sceneContentWidth - normalized) < 1) {
      return;
    }
    this.sceneContentWidth = normalized;
    rememberMainContentWidthVp(normalized);
    markCurrentRouteRightPane(this.useSplitLayout());
  }

  onSplitPaneRatioRevisionChange(): void {
    if (!this.splitDragging) {
      this.splitListRatio = splitPaneCurrentRatio();
    }
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

  private useSplitLayout(): boolean {
    return splitPaneModeEnabled() && this.availableSceneWidth() >= SPLIT_PANE_BREAKPOINT &&
      this.showDetail && !this.showReader && !this.showTagSearch && !this.showGalleryList;
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
  }

  private finishSplitPaneDrag(): void {
    this.splitDragging = false;
    saveSplitPaneRatio(this.splitListRatio);
  }

  @Builder
  private topListMainContent() {
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
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
      } else {
        Column() {
          TopListBoard({
            lists: this.topList.lists,
            selectedIndex: this.selectedIndex,
            info: this.currentInfo(),
            toolbarOffsetY: this.toolbarOffsetY,
            topPadding: this.floatingToolbarHeight(),
            statusBarHeight: this.statusBarVp(),
            renderVersion: this.renderVersion,
            translateTitles: this.translationEnabled,
            onSelectList: (index: number) => {
              if (this.selectedIndex === index) {
                return;
              }
              this.selectedIndex = index;
              this.topListScrollOffset = 0;
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
              const offsetRemain = this.updateToolbarForScroll(offset, scrollOffset);
              this.topListScrollOffset = offset;
              return offsetRemain;
            }
          })
            .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
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
          this.closeReader();
        }
      })
    } else if (this.showGalleryList) {
      GalleryListScene({
        sceneTitle: this.galleryListTitle,
        listMode: this.galleryListModeLabel,
        sourceRoute: this.galleryRoute,
        follow: this.galleryFollow,
        initialKeyword: this.galleryKeyword,
        initialSearchMode: this.gallerySearchMode,
        initialSearchCategory: GalleryCategory.None,
        initialAdvancedSearchEnabled: false,
        initialAdvanceSearch: DEFAULT_ADVANCE_SEARCH,
        initialSearchSubmitted: true,
        useForcedMode: this.galleryUseForcedMode,
        forcedMode: this.galleryForcedMode,
        isSearchResultScene: true,
        onBack: () => {
          this.closeGalleryList();
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          FloatingToolbarHost({
            kind: 'title',
            title: 'Top Lists',
            requestUrl: '',
            showRefreshButton: false,
            toolbarOffsetY: this.toolbarOffsetY,
            toolbarHeight: uiAdaptiveToolbarHeight(this.sceneContentWidth),
            onMenu: this.onMenu,
            onRefresh: () => {
              this.loadTopList();
            }
          }) {
            this.topListMainContent()
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
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }),
          TransitionEffect.OPACITY.animation({ duration: 1, delay: 300, curve: Curve.Linear })))

        if (this.showDetail) {
          SplitPaneDivider({
            x: this.useSplitLayout() ? this.splitListPaneWidth() : 0,
            dividerVisible: this.useSplitLayout(),
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

        Column() {
          if (this.translationButtonsVisible) {
            ActionBubble({
              label: this.translationEnabled ? uiText('Show original titles') : uiText('Translate titles'),
              symbolIcon: $r('sys.symbol.translate'),
              isEnabled: true,
              checked: this.translationEnabled,
              primary: true,
              directTap: true,
              onTapAction: () => {
                ehTranslationService.setEnabled(!this.translationEnabled);
              }
            })
          }
        }
        .width(this.useSplitLayout() ? this.splitListPaneWidth() : '100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.End)
        .padding({ right: 16, bottom: 24 })
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(4)

        if (this.showDetail) {
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
              this.openRemoteSearch(request);
            },
            onDetailLoaded: (detail: GalleryDetail) => {
              this.detail = detail;
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
            .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
            .transition(this.restoreDetailWithFade ?
              TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }) :
              TransitionEffect.move(TransitionEdge.END).animation({ duration: 300, curve: Curve.EaseOut }))
        }
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.updateSceneContentWidth(areaDimensionToVp(newArea.width, (value: number) => this.getUIContext().px2vp(value)));
      })
    }
  }
}

@Component
export struct TopListTabs {
  @Prop lists: TopListInfo[] = [];
  @Prop selectedIndex: number = 0;
  onSelect: (index: number) => void = () => {};

  build() {
    Tabs({ barPosition: BarPosition.Start, index: this.selectedIndex }) {
      ForEach(this.lists, (info: TopListInfo, index: number) => {
        TabContent() {
          Column()
            .height(0)
        }
        .tabBar(uiText(info.title))
      }, (info: TopListInfo, index: number) => info.kind.toString() + ':' + index.toString())
    }
    .barMode(BarMode.Scrollable)
    .barHeight(uiTabHeight() + 4)
    .barBackgroundColor(Color.Transparent)
    .barBackgroundBlurStyle(BlurStyle.NONE)
    .animationDuration(180)
    .divider({ strokeWidth: 0, color: Color.Transparent })
    .onChange((index: number) => {
      this.onSelect(index);
    })
    .width('100%')
    .height(uiTabHeight() + 4)
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
  @Prop translateTitles: boolean = false;
  @State translationVisibleStart: number = -1;
  @State translationVisibleEnd: number = -1;
  @State boardWidth: number = 360;
  onSelectList: (index: number) => void = () => {};
  onOpenBucket: (bucket: TopListBucket) => void = () => {};
  onOpenItem: (item: TopListItem, info: TopListInfo) => void = () => {};
  initialScrollOffset: number = 0;
  onScrollUpdate: (offset: number, scrollOffset: number) => number = (_offset: number, scrollOffset: number) => {
    return scrollOffset;
  };
  private boardScroller: Scroller = new Scroller();

  private tabsBarHeight(): number {
    return uiTabHeight() + 4;
  }

  private translationPriorityFor(index: number): number {
    if (!this.translateTitles) {
      return 0;
    }
    return translationPriorityForIndex(index, this.translationVisibleStart, this.translationVisibleEnd);
  }

  private tabsVisualTop(): number {
    return Math.max(this.statusBarHeight, this.topPadding + this.toolbarOffsetY);
  }

  private contentTopPadding(): number {
    return this.tabsVisualTop() + this.tabsBarHeight() + 2;
  }

  private bucketContentWidth(): number {
    return Math.max(220, this.boardWidth - 48);
  }

  @Builder
  private TabsBar() {
    Column() {
      TopListTabs({
        lists: this.lists,
        selectedIndex: this.selectedIndex,
        onSelect: (index: number) => {
          this.onSelectList(index);
          this.boardScroller.scrollTo({ xOffset: 0, yOffset: 0 });
        }
      })
        .width('100%')
        .backgroundColor(themeTransparentColor())
    }
      .width('100%')
      .height(this.tabsBarHeight())
      .backgroundColor(themeTransparentColor())
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      List({ space: 10, scroller: this.boardScroller }) {
        ForEach(this.info.buckets, (bucket: TopListBucket, index: number) => {
          ListItem() {
            TopListBucketCard({
              bucket: bucket,
              info: this.info,
              contentWidth: this.bucketContentWidth(),
              translateTitles: this.translateTitles,
              translationPriority: this.translationPriorityFor(index),
              canOpenBucket: this.info.kind === TopListKind.Gallery,
              onOpenBucket: this.onOpenBucket,
              onOpenItem: this.onOpenItem
            })
          }
          .reuseId('top-list-bucket')
        }, (bucket: TopListBucket) => this.selectedIndex.toString() + ':' + this.info.kind.toString() + ':' + bucket.title)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 12, right: 12, top: this.contentTopPadding(), bottom: 0 })
      .backgroundColor(themePageBackground())
      .scrollBar(BarState.Auto)
      .cachedCount(3)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true, effectEdge: EffectEdge.START | EffectEdge.END })
      .onAppear(() => {
        if (this.initialScrollOffset > 0) {
          this.boardScroller.scrollTo({ xOffset: 0, yOffset: this.initialScrollOffset });
        }
      })
      .onScrollFrameBegin((offset: number, _state: ScrollState) => {
        return {
          offsetRemain: this.onScrollUpdate(normalizeSceneScrollOffset(this.boardScroller.currentOffset().yOffset), offset)
        };
      })
      .onScrollIndex((first: number, last: number) => {
        this.translationVisibleStart = first;
        this.translationVisibleEnd = last;
      })
      .onScrollStop(() => {
        const offset = normalizeSceneScrollOffset(this.boardScroller.currentOffset().yOffset);
        this.onScrollUpdate(offset, 0);
      })

      Column() {
        this.TabsBar()
      }
      .width('100%')
      .height(this.tabsBarHeight())
      .padding({ left: 12, right: 12 })
      .position({ x: 0, y: this.tabsVisualTop() })
      .backgroundColor(themeTransparentColor())
      .zIndex(8)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width = areaDimensionToVp(newArea.width, (value: number) => this.getUIContext().px2vp(value));
      if (width >= 240 && Math.abs(width - this.boardWidth) >= 1) {
        this.boardWidth = width;
      }
    })
  }
}

@Component
export struct TopListBucketCard {
  @Prop bucket: TopListBucket = createEmptyTopListBucket();
  @Prop info: TopListInfo = createEmptyTopListInfo();
  @Prop contentWidth: number = 312;
  @Prop canOpenBucket: boolean = false;
  @Prop translateTitles: boolean = false;
  @Prop translationPriority: number = 2;
  onOpenBucket: (bucket: TopListBucket) => void = () => {};
  onOpenItem: (item: TopListItem, info: TopListInfo) => void = () => {};

  private columnCount(): number {
    const targetWidth = this.info.kind === TopListKind.Gallery ? 300 : 210;
    const calculated = Math.max(1, Math.floor((this.contentWidth + 8) / (targetWidth + 8)));
    if (this.bucket.items.length <= 0) {
      return 1;
    }
    return Math.min(this.bucket.items.length, calculated);
  }

  private columnsTemplate(): string {
    const columns = this.columnCount();
    let value = '1fr';
    for (let i = 1; i < columns; i++) {
      value += ' 1fr';
    }
    return value;
  }

  private gridHeight(): number {
    const rows = Math.ceil(this.bucket.items.length / this.columnCount());
    if (rows <= 0) {
      return 0;
    }
    return rows * 56 + (rows - 1) * 8;
  }

  build() {
    Column() {
      Row() {
        Text(uiText(this.bucket.title))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.canOpenBucket ? themeAccentTextColor() : themePrimaryText())
          .layoutWeight(1)
          .decoration({ type: this.canOpenBucket ? TextDecorationType.Underline : TextDecorationType.None })
          .onClick(() => {
            if (this.canOpenBucket) {
              this.onOpenBucket(this.bucket);
            }
          })
        Text(this.bucket.items.length.toString() + ' ' + uiText('entries'))
          .fontSize(12)
          .fontColor(themeSecondaryText())
      }
      .width('100%')

      Grid() {
        ForEach(this.bucket.items, (item: TopListItem, index: number) => {
          GridItem() {
            TopListChip({
              item: item,
              rank: index + 1,
              translateTitle: this.translateTitles && this.info.kind === TopListKind.Gallery,
              translationPriority: this.translationPriority,
              onTap: () => {
                this.onOpenItem(item, this.info);
              }
            })
          }
        }, (item: TopListItem) => item.href + item.value)
      }
      .columnsTemplate(this.columnsTemplate())
      .columnsGap(8)
      .rowsGap(8)
      .width('100%')
      .height(this.gridHeight())
      .margin({ top: 8 })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(themeSurface())
    .borderRadius(uiRadius(6))
  }
}

@Component
export struct TopListChip {
  item: TopListItem = createEmptyTopListItem();
  @Prop rank: number = 0;
  @Prop translateTitle: boolean = false;
  @Prop translationPriority: number = 2;
  onTap: () => void = () => {};

  build() {
    Row() {
      Text(this.rank.toString())
        .width(30)
        .height(30)
        .fontSize(13)
        .fontWeight(this.rank <= 3 ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(themeAccentTextColor())
        .textAlign(TextAlign.Center)
        .textVerticalAlign(TextVerticalAlign.CENTER)
        .backgroundColor(themeSurface())
        .borderRadius(uiRadius(15))

      Column() {
        TranslationText({
          sourceText: this.item.value,
          translationEnabled: this.translateTitle,
          translationPriority: this.translationPriority,
          fontSizeValue: 13,
          lineHeightValue: 18,
          fontColorValue: themePrimaryText(),
          maxLinesValue: 2
        })
      }
      .layoutWeight(1)
      .margin({ left: 10 })

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontColor([themeSecondaryText()])
        .margin({ left: 6 })
    }
    .width('100%')
    .height(56)
    .padding({ left: 10, right: 10 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(themeSurfaceVariant())
    .border({ width: 0.5, color: themeDividerColor() })
    .borderRadius(uiRadius(6))
    .onClick(() => {
      this.onTap();
    })
  }
}
