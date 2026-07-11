import { GalleryCategory, GalleryDetail, GalleryRoute, GallerySite, TopListBucket, TopListDetail, TopListInfo, TopListItem, TopListKind } from '../model/GalleryModels';
import { EhHttpClient, TopListLoadResult } from '../services/EhHttpClient';
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
  getMainWindow,
  isEmbeddedReaderActive,
  leaveEmbeddedReaderFullscreen
} from '../services/EhWindowImmersive';
import {
  themeOnPrimaryText,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSurface,
  themeTransparentColor
} from '../shared/EhTheme';
import { LANGUAGE_REVISION_KEY, STATUS_BAR_HEIGHT_KEY, setActiveBackHandler, runDetailBackHandler, createEmptyDetail, createEmptyTopListDetail, createEmptyTopListInfo, createEmptyTopListBucket, createEmptyTopListItem, cloneGalleryDetail, cloneGalleryInfo, cloneTopListDetail, nextFloatingToolbarOffset, topListChipColor, currentGallerySite } from '../shared/EhShared';
import { GalleryListScene, GalleryListStateView } from './GalleryScenes';
import { GalleryDetailHostScene } from './GalleryDetailHostScene';
import { ReaderSessionScene } from './ReaderHostScene';
import { FloatingToolbarHost } from './NavigationComponents';
import {
  areaDimensionToVp,
  markPreviousRouteRightPane,
  saveSplitPaneRatio,
  SPLIT_PANE_BREAKPOINT,
  SPLIT_PANE_RATIO_REVISION_KEY,
  shouldFadeRestoredRightPane,
  splitPaneCurrentRatio,
  SplitPaneDivider,
  splitPaneListWidth,
  splitPaneModeEnabled,
  splitPaneRatioForWidth,
  splitPaneSideWidth,
  splitPaneWidthFromDrag
} from './SplitPaneSupport';

function normalizeSceneScrollOffset(offset: number): number {
  if (offset <= 1 || Number.isNaN(offset)) {
    return 0;
  }
  return offset;
}

interface TopListNavigationCache {
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
  @State activeSplitPane: string = 'left';
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  @StorageProp(SPLIT_PANE_RATIO_REVISION_KEY) @Watch('onSplitPaneRatioRevisionChange') splitPaneRatioRevision: number = 0;
  private topListScrollOffset: number = 0;
  private detailScrollOffset: number = 0;
  private toolbarRestoring: boolean = false;
  private splitDragStartWidth: number = 0;

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    this.restoreNavigationCache();
    this.syncSceneContentWidthFromWindow();
    setActiveBackHandler(() => this.handleSystemBack());
    this.loadTopList();
    setTimeout(() => {
      this.syncSceneContentWidthFromWindow();
    }, 0);
  }

  aboutToDisappear(): void {
    markPreviousRouteRightPane(this.useSplitLayout());
    this.saveNavigationCache();
  }

  onResetVersionChanged(): void {
    this.resetToTopLevel();
  }

  private handleSystemBack(): boolean {
    if (this.useSplitLayout() && this.activeSplitPane === 'left') {
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
    this.showDetail = true;
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
    this.showDetail = false;
    this.showReader = false;
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
    return this.statusBarVp() + 56;
  }

  private updateSceneContentWidth(width: number): void {
    const normalized = Math.floor(width);
    if (normalized <= 0 || Number.isNaN(normalized) || Math.abs(this.sceneContentWidth - normalized) < 1) {
      return;
    }
    this.sceneContentWidth = normalized;
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
    const win = getMainWindow();
    if (win === undefined) {
      return 0;
    }
    try {
      const rawWidth = Math.floor(win.getWindowProperties().windowRect.width);
      if (rawWidth <= 0 || Number.isNaN(rawWidth)) {
        return 0;
      }
      const converted = Math.floor(this.getUIContext().px2vp(rawWidth));
      if (converted >= 240) {
        return converted;
      }
      return rawWidth >= 240 && rawWidth <= 1200 ? rawWidth : 0;
    } catch (_error) {
      return 0;
    }
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
            topPadding: this.floatingToolbarHeight() + 4,
            statusBarHeight: this.statusBarVp(),
            renderVersion: this.renderVersion,
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
            title: '排行',
            requestUrl: '',
            showRefreshButton: false,
            toolbarOffsetY: this.toolbarOffsetY,
            toolbarHeight: 56,
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
        .onTouch(() => {
          this.activeSplitPane = 'left';
        })
        .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }),
          TransitionEffect.OPACITY.animation({ duration: 1, delay: 300, curve: Curve.Linear })))

        if (this.useSplitLayout()) {
          SplitPaneDivider({
            x: this.splitListPaneWidth(),
            dragging: this.splitDragging,
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
            .onTouch(() => {
              this.activeSplitPane = 'right';
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
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.lists, (info: TopListInfo, index: number) => {
          Text(info.title)
            .height(34)
            .fontSize(12)
            .fontColor(index === this.selectedIndex ? themeOnPrimaryText() : themePrimaryColor())
            .textAlign(TextAlign.Center)
            .textVerticalAlign(TextVerticalAlign.CENTER)
            .padding({ left: 12, right: 12 })
            .backgroundColor(index === this.selectedIndex ? themePrimaryColor() : themeTransparentColor())
            .border({ width: 1, color: index === this.selectedIndex ? themePrimaryColor() : themeSecondaryText() })
            .borderRadius(6)
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
  onScrollUpdate: (offset: number, scrollOffset: number) => number = (_offset: number, scrollOffset: number) => {
    return scrollOffset;
  };
  private boardScroller: Scroller = new Scroller();
  private readonly TABS_BAR_HEIGHT: number = 42;

  private tabsVisualTop(): number {
    return Math.max(0, this.topPadding + this.toolbarOffsetY);
  }

  private contentTopPadding(): number {
    return this.tabsVisualTop() + this.TABS_BAR_HEIGHT + 5;
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
        .padding({ top: 4, bottom: 4 })
        .backgroundColor(themeTransparentColor())
    }
      .width('100%')
      .height(this.TABS_BAR_HEIGHT)
      .backgroundColor(themeTransparentColor())
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
      .onScrollStop(() => {
        const offset = normalizeSceneScrollOffset(this.boardScroller.currentOffset().yOffset);
        this.onScrollUpdate(offset, 0);
      })

      Column() {
        this.TabsBar()
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: this.tabsVisualTop() })
      .backgroundColor(themeTransparentColor())
      .zIndex(8)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}

@Component
export struct TopListBucketCard {
  @Prop bucket: TopListBucket = createEmptyTopListBucket();
  @Prop info: TopListInfo = createEmptyTopListInfo();
  @Prop canOpenBucket: boolean = false;
  onOpenBucket: (bucket: TopListBucket) => void = () => {};
  onOpenItem: (item: TopListItem, info: TopListInfo) => void = () => {};

  build() {
    Column() {
      Row() {
        Text(this.bucket.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.canOpenBucket ? themePrimaryColor() : themePrimaryText())
          .layoutWeight(1)
          .decoration({ type: this.canOpenBucket ? TextDecorationType.Underline : TextDecorationType.None })
          .onClick(() => {
            if (this.canOpenBucket) {
              this.onOpenBucket(this.bucket);
            }
          })
        Text(this.bucket.items.length.toString() + ' entries')
          .fontSize(12)
          .fontColor(themeSecondaryText())
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
    .backgroundColor(themeSurface())
    .borderRadius(6)
  }
}

@Component
export struct TopListChip {
  item: TopListItem = createEmptyTopListItem();
  color: string = themePrimaryColor();
  onTap: () => void = () => {};

  build() {
    Text(this.item.value)
      .fontSize(13)
      .fontColor(themeOnPrimaryText())
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
