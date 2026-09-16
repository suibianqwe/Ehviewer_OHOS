import { curves } from '@kit.ArkUI';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { GalleryCategory, GalleryInfo } from '../model/GalleryModels';
import { SearchBookmarkInfo } from '../services/EhBookmarkStore';
import { DEFAULT_ADVANCE_SEARCH, FavListUrlBuilder, ListMode } from '../services/EhUrl';
import { ehSearchHistoryStore } from '../services/EhSearchHistoryStore';
import { FloatingActionSideController } from '../services/EhFloatingActionSideSupport';
import {
  DEFAULT_FAVORITE_SLOT_ASK,
  DEFAULT_FAVORITE_SLOT_SETTING_KEY,
  FLOATING_ACTION_HOLDING_HAND_REVISION_KEY,
  FLOATING_ACTION_SIDE_REVISION_KEY,
  TRANSLATION_BUTTONS_VISIBLE_KEY,
  defaultFavoriteSlotSettingValue,
  ehSettingsStore,
  parseDefaultFavoriteSlot,
} from '../services/EhSettingsStore';
import {
  TRANSLATION_ENABLED_KEY,
  ehTranslationService,
  translationPriorityForIndex,
} from '../services/EhTranslationService';
import { FavoriteCategoryInfo } from '../services/GalleryListParser';
import {
  mainContentWidthFallbackVp,
} from '../services/EhWindowImmersive';
import { pushActiveBackHandler } from '../shared/EhShared';
import { sortedStringKey, toggleStringValue } from '../shared/EhShared';
import { GalleryCardScrollAnchor } from '../shared/GalleryCardScrollAnchor';
import { ArrayDataSource } from '../shared/ListDataSource';
import { galleryListColumnCount, galleryListHorizontalPadding, galleryListTopInset, galleryListViewportHeight } from '../shared/AdaptiveGalleryListLayout';
import {
  themeFieldBackground,
  themeDangerText,
  themeOnPrimaryActionBackground,
  themeOnPrimaryActionStrongBackground,
  themeOnPrimaryText,
  themePageBackground,
  themePlaceholderColor,
  themeAccentTextColor,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeShadowColor,
  themeSurface,
  themeTertiaryText,
  themeTransparentColor,
} from '../shared/EhTheme';
import {
  uiAdaptiveToolbarHeight,
  uiButtonMaterial,
  uiTransparentButtonBackgroundEffect,
  uiListGap,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiRadius,
  uiSearchFieldHeight,
  uiTitleBarFadeHeight,
} from '../shared/EhUiStyle';
import {
  GalleryListRow,
  GalleryThumbCard,
  galleryThumbnailAspectRatio,
} from './GalleryCards';
import { PopupScrim } from './PopupScrim';
import {
  RightSidePanelLayer,
  SIDE_PANEL_WIDTH,
  sidePanelLeft,
  shouldOpenSidePanel,
} from './SidePanelComponents';
import {
  applyTagSuggestionToKeyword,
  buildSearchSuggestions,
  composeSearchKeywordWithInput,
  FloatingActionDock,
  QuickActionColumn,
  SearchActionColumn,
  removeSearchTagToken,
  normalizeSearchTagToken,
  SearchAdvancedPanel,
  SearchSuggestionItem,
  SearchSuggestionList,
  SearchSummaryStrip,
  searchKeywordWithoutTagTokens,
  searchTagTokenDisplayLabel,
  searchTagTokens,
} from './GallerySearchScenes';
import {
  FLOATING_ACTION_SIDE_RIGHT,
  floatingActionAvailableHeight,
} from './FloatingActionLayoutSupport';
import {
  uiText,
  uiStatusText,
  getAbilityContext,
  immersiveChromeHeightFromOffset,
  nextFloatingToolbarOffset,
  galleryListMode,
  galleryDetailCardHeight,
  galleryDetailCardMinWidth,
  galleryDetailCardPreferredWidth,
  galleryThumbnailPreferredColumnWidth,
  cacheThumbnailImage,
} from '../shared/EhShared';
import {
  FavoriteCategoryDrawer,
  DefaultFavoriteSlotDialog,
  SearchBookmarkDrawer,
} from './GalleryBookmarkScenes';
import {
  ImageSearchPanel,
} from './GalleryOverlayComponents';

import {
  galleryChromeForeground,
  galleryChromeBackground,
  GALLERY_THUMBNAIL_CACHE_COUNT,
  GALLERY_THUMBNAIL_PREFETCH_BEFORE,
  GALLERY_THUMBNAIL_PREFETCH_AFTER,
  readThumbnailImageSize,
  normalizeGalleryListScrollOffset,
} from './GalleryListSupport';
import {
  GalleryHomeNavBarHost,
  GallerySearchNavBarHost,
  GalleryToolbarOffset,
  GalleryToolbarOffsetBinding,
} from './GalleryNavHosts';

@Component
export struct GalleryListContent {
  @Prop sceneTitle: string = '';
  @Prop listMode: string = '';
  @Prop @Watch('onSearchKeywordChanged') keyword: string = '';
  @Prop searchTitle: string = '';
  @Prop actionsExpanded: boolean = false;
  @Prop filterActive: boolean = false;
  @Prop showFavoriteButton: boolean = false;
  @Prop showBookmarkButton: boolean = false;
  @Prop bookmarks: SearchBookmarkInfo[] = [];
  @Prop favoriteCat: number = FavListUrlBuilder.FAV_CAT_ALL;
  @Prop favoriteCategories: FavoriteCategoryInfo[] = [];
  @Prop favoriteLocalCount: number = -1;
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
  @Prop pageFrom: number = -1;
  @Prop pageTo: number = -1;
  @Prop @Watch('onPageChanged') pageIndex: number = 0;
  @Prop totalPages: number = 0;
  @Prop resultCount: string = '';
  @Prop canJump: boolean = false;
  @Prop canRandom: boolean = false;
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  @Prop isLoadingMore: boolean = false;
  @Prop @Watch('onGalleriesChanged') galleries: GalleryInfo[] = [];
  @Prop @Watch('onLayoutWidthHintChanged') layoutWidthHint: number = 0;
  @Prop @Watch('onScrollReset') scrollResetVersion: number = 0;
  onKeywordChange: (value: string) => void = () => {
  };
  onSearchFocus: () => void = () => {
  };
  onFavoriteCatChange: (favCat: number) => void = (_favCat: number) => {
  };
  onFavoriteDrawerOpen: () => void = () => {
  };
  onBookmarkDrawerOpen: () => void = () => {
  };
  onBookmarkSettings: () => void = () => {
  };
  onAddBookmark: () => void = () => {
  };
  onSelectBookmark: (bookmark: SearchBookmarkInfo) => void = (_bookmark: SearchBookmarkInfo) => {
  };
  onDeleteBookmark: (bookmark: SearchBookmarkInfo) => void = (_bookmark: SearchBookmarkInfo) => {
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
  onPageFromChange: (value: number) => void = (_value: number) => {};
  onPageToChange: (value: number) => void = (_value: number) => {};
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
  onImageSearch: (path: string, useSimilarityScan: boolean, onlySearchCovers: boolean) => void =
    (_path: string, _useSimilarityScan: boolean, _onlySearchCovers: boolean) => {
    };
  onSelectGallery: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  onLongPressGallery: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  shouldHandleLocalBack: () => boolean = () => true;
  initialScrollOffset: number = 0;
  onScrollUpdate: (offset: number) => void = () => {
  };
  @State contentWidth: number = 0;
  private lastToolbarScrollOffset: number = 0;
  @State refreshing: boolean = false;
  @State refreshPullOffset: number = 0;
  @State advancedPanelVisible: boolean = false;
  @State advancedPopupHeight: number = 0;
  @State pageJumpDraft: string = '';
  @State seekYearDraft: string = '';
  @State seekMonthDraft: string = '';
  @State seekDayDraft: string = '';
  @State jumpPanelVisible: boolean = false;
  @State jumpPopupHeight: number = 0;
  @State imageSearchPanelVisible: boolean = false;
  @State imageSearchPopupWidth: number = 0;
  @State imageSearchPopupHeight: number = 0;
  @State selectedTagNamespaces: string[] = [];
  @State searchSuggestionItems: SearchSuggestionItem[] = [];
  @State searchSuggestionRevision: number = 0;
  onRefreshPull: (done: () => void) => void = (done: () => void) => {
    done();
  };
  private readonly REFRESH_OFFSET: number = 42;
  @State viewportHeight: number = 0;
  private listScroller: Scroller = new Scroller();
  private searchTagScroller: Scroller = new Scroller();
  private searchTagTokenCount: number = 0;
  private searchTagEndScrollRequest: number = 0;
  private searchTagEndScrollPending: boolean = false;
  private cardScrollAnchor: GalleryCardScrollAnchor = new GalleryCardScrollAnchor();
  private loadMorePending: boolean = false;
  private lastLoadMoreOffsetCheck: number = 0;
  private topSpacerIndexesCache: number[] = [];
  private topSpacerIndexesCacheColumns: number = -1;
  private restoredScroll: boolean = false;
  private galleryThumbnailAspectRatioAverage: number = 0.75;
  @State thumbnailDimensionsReady: boolean = false;
  private thumbnailDimensionsGeneration: number = 0;
  private galleryThumbnailSource: ArrayDataSource<GalleryInfo> =
    new ArrayDataSource<GalleryInfo>([]);
  private previousGalleryGids: number[] = [];
  private hasRenderedGalleries: boolean = false;
  private toolbarOffsetY: number = 0;
  @State private toolbarOffsetBinding: GalleryToolbarOffsetBinding = new GalleryToolbarOffsetBinding();

  private toolbarState(): GalleryToolbarOffset {
    return this.toolbarOffsetBinding.state();
  }
  @State contentOpacity: number = 1;
  private toolbarRestoring: boolean = false;
  @State translationVisibleStart: number = -1;
  @State translationVisibleEnd: number = -1;
  @State floatingActionSide: string = FLOATING_ACTION_SIDE_RIGHT;
  @State favoriteDrawerVisible: boolean = false;
  @State favoriteDrawerOffsetX: number = 288;
  @State favoriteDrawerOverlayOpacity: number = 0;
  @State favoriteSettingsDialogVisible: boolean = false;
  @State defaultFavoriteSlot: number | null = null;
  @State bookmarkDrawerVisible: boolean = false;
  @State bookmarkDrawerOffsetX: number = 288;
  @State bookmarkDrawerOverlayOpacity: number = 0;
  private floatingActionSideController: FloatingActionSideController = new FloatingActionSideController(
    (side: string): void => {
      this.animateFloatingActionSide(side);
    });
  private translationVisibleItems: number[] = [];
  private unregisterActiveBackHandler: () => void = () => {};
  private barHeight(): number {
    return uiAdaptiveToolbarHeight(this.effectiveContentWidth());
  }
  @StorageProp('statusBarHeight') statusBarHeightPx: number = 0;
  @StorageLink(TRANSLATION_ENABLED_KEY) translationEnabled: boolean = false;
  @StorageProp(TRANSLATION_BUTTONS_VISIBLE_KEY) translationButtonsVisible: boolean = true;
  @StorageProp(FLOATING_ACTION_HOLDING_HAND_REVISION_KEY) @Watch('onHoldingHandSettingChanged')
  holdingHandSettingRevision: number = 0;
  @StorageProp(FLOATING_ACTION_SIDE_REVISION_KEY) @Watch('onFloatingActionSideSettingChanged')
  floatingActionSideRevision: number = 0;

  onScrollReset(): void {
    // Scroll back to the top when scrollResetVersion changes.
    this.snapListToTop();
  }

  onPageChanged(): void {
    this.syncPageJumpDraft();
  }

  onSearchKeywordChanged(): void {
    const tagCount = this.selectedSearchTagTokens().length;
    const tagAdded = tagCount > this.searchTagTokenCount;
    this.searchTagTokenCount = tagCount;
    this.refreshSearchSuggestions();
    if (tagAdded) {
      this.scrollSearchTagsToEnd();
    }
  }

  onGalleriesChanged(): void {
    this.applyGalleriesToSource();
    this.translationVisibleItems = [];
    this.translationVisibleStart = -1;
    this.translationVisibleEnd = -1;
    if (this.galleries.length === 0) {
      this.galleryThumbnailAspectRatioAverage = 0.75;
      this.thumbnailDimensionsReady = true;
      return;
    }
    let ratioSum = 0;
    for (let i = 0; i < this.galleries.length; i++) {
      ratioSum += galleryThumbnailAspectRatio(this.galleries[i]);
    }
    this.galleryThumbnailAspectRatioAverage = ratioSum / this.galleries.length;
    this.prepareThumbnailDimensions();
  }

  private applyGalleriesToSource(): void {
    const previous = this.previousGalleryGids;
    let appendedOnly = previous.length > 0 && this.galleries.length > previous.length;
    if (appendedOnly) {
      for (let i = 0; i < previous.length; i++) {
        if (this.galleries[i].gid !== previous[i]) {
          appendedOnly = false;
          break;
        }
      }
    }
    if (appendedOnly) {
      this.galleryThumbnailSource.appendRange(this.galleries, previous.length);
    } else {
      this.galleryThumbnailSource.setItems(this.galleries);
    }
    const gids: number[] = [];
    for (let i = 0; i < this.galleries.length; i++) {
      gids.push(this.galleries[i].gid);
    }
    this.previousGalleryGids = gids;
    if (this.galleries.length > 0) {
      this.hasRenderedGalleries = true;
    }
  }

  private prepareThumbnailDimensions(): void {
    const generation = ++this.thumbnailDimensionsGeneration;
    const missing: GalleryInfo[] = [];
    for (let i = 0; i < this.galleries.length; i++) {
      const gallery = this.galleries[i];
      if (gallery.thumbWidth <= 0 || gallery.thumbHeight <= 0) {
        missing.push(gallery);
      }
    }
    if (missing.length === 0) {
      this.thumbnailDimensionsReady = true;
      return;
    }

    this.thumbnailDimensionsReady = false;
    let remaining = missing.length;
    const complete = (): void => {
      if (generation !== this.thumbnailDimensionsGeneration) {
        return;
      }
      remaining--;
      if (remaining > 0) {
        return;
      }
      let ratioSum = 0;
      for (let i = 0; i < this.galleries.length; i++) {
        ratioSum += galleryThumbnailAspectRatio(this.galleries[i]);
      }
      this.galleryThumbnailAspectRatioAverage = this.galleries.length > 0 ?
        ratioSum / this.galleries.length : 0.75;
      this.thumbnailDimensionsReady = true;
    };

    for (let i = 0; i < missing.length; i++) {
      const gallery = missing[i];
      const url = gallery.thumb === undefined ? '' : gallery.thumb;
      if (url.length === 0) {
        complete();
        continue;
      }
      cacheThumbnailImage(url, (path: string) => {
        if (generation === this.thumbnailDimensionsGeneration) {
          const size = readThumbnailImageSize(path);
          if (size.width > 0 && size.height > 0) {
            gallery.thumbWidth = size.width;
            gallery.thumbHeight = size.height;
          }
        }
        complete();
      }, () => {
        complete();
      });
    }
  }

  onLayoutWidthHintChanged(): void {
    if (this.layoutWidthHint >= 240) {
      this.updateContentWidth(this.layoutWidthHint);
    }
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  private effectiveContentWidth(): number {
    return this.layoutWidthHint >= 240 ? this.layoutWidthHint : this.contentWidth;
  }

  private favoriteDrawerLeft(): number {
    const effectiveWidth = this.effectiveContentWidth();
    return sidePanelLeft(effectiveWidth,
      mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value)));
  }

  private bookmarkDrawerLeft(): number {
    const effectiveWidth = this.effectiveContentWidth();
    return sidePanelLeft(effectiveWidth,
      mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value)));
  }

  private openFavoriteDrawer(): void {
    if (!this.showFavoriteButton || this.favoriteDrawerVisible) {
      return;
    }
    this.onFavoriteDrawerOpen();
    this.favoriteDrawerVisible = true;
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.favoriteDrawerOffsetX = 0;
      this.favoriteDrawerOverlayOpacity = 0.45;
    });
  }

  private closeFavoriteDrawer(): void {
    if (!this.favoriteDrawerVisible) {
      return;
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.favoriteDrawerOffsetX = SIDE_PANEL_WIDTH;
      this.favoriteDrawerOverlayOpacity = 0;
    });
    setTimeout(() => {
      if (this.favoriteDrawerOffsetX > SIDE_PANEL_WIDTH - 40) {
        this.favoriteDrawerVisible = false;
      }
    }, 220);
  }

  private openFavoriteSettingsDialog(): void {
    this.defaultFavoriteSlot = parseDefaultFavoriteSlot(ehSettingsStore.getValue(
      DEFAULT_FAVORITE_SLOT_SETTING_KEY, DEFAULT_FAVORITE_SLOT_ASK));
    this.favoriteSettingsDialogVisible = true;
  }

  private closeFavoriteSettingsDialog(): void {
    this.favoriteSettingsDialogVisible = false;
  }

  private selectDefaultFavoriteSlot(slot: number | null): void {
    this.defaultFavoriteSlot = slot;
    ehSettingsStore.setValue(DEFAULT_FAVORITE_SLOT_SETTING_KEY, defaultFavoriteSlotSettingValue(slot));
    this.favoriteSettingsDialogVisible = false;
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch(() => {
      });
    }
  }

  private favoriteSettingsDialogMaxHeight(): number {
    if (this.viewportHeight <= 0) {
      return 620;
    }
    return Math.max(280, this.viewportHeight - 96);
  }

  private handleOpenFavoriteDrawerPan(event: GestureEvent | undefined): void {
    if (!this.showFavoriteButton || this.favoriteDrawerVisible || event === undefined) {
      return;
    }
    if (shouldOpenSidePanel(event)) {
      this.openFavoriteDrawer();
    }
  }

  private handleOpenBookmarkDrawerPan(event: GestureEvent | undefined): void {
    if (!this.showBookmarkButton || this.showFavoriteButton || this.bookmarkDrawerVisible || event === undefined) {
      return;
    }
    if (shouldOpenSidePanel(event)) {
      this.openBookmarkDrawer();
    }
  }

  aboutToAppear(): void {
    // Search scenes are mounted as an overlay and must start fully visible.
    // Their list position is local to the still-mounted scene; applying a
    // parent/cache offset here can leave the content at opacity 0 when the
    // nested List does not emit onAppear again.
    this.contentOpacity = 1;
    this.toolbarOffsetY = 0;
    this.unregisterActiveBackHandler();
    this.unregisterActiveBackHandler = pushActiveBackHandler(() => this.handleContentBack());
    this.onGalleriesChanged();
    this.galleryThumbnailSource.setPrefetchCallback((gallery: GalleryInfo) => {
      this.prefetchGalleryThumbnail(gallery);
    });
    this.onLayoutWidthHintChanged();
    this.floatingActionSideController.syncFromSettings();
    this.syncContentWidthFromWindow();
    this.syncPageJumpDraft();
    this.searchTagTokenCount = this.selectedSearchTagTokens().length;
    this.refreshSearchSuggestions();
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSearchHistoryStore.load(context).then(() => {
        this.refreshSearchSuggestions();
      }).catch(() => {});
    }
    if (!this.isSearchResultScene && this.initialScrollOffset > 0) {
      this.contentOpacity = 0;
      this.toolbarOffsetY = -Math.min(this.initialScrollOffset, this.totalBarHeight());
    }
    this.syncToolbarOffsetState();
    setTimeout(() => {
      this.syncContentWidthFromWindow();
    }, 0);
  }

  private updateVisibleTranslationItem(index: number, visible: boolean): void {
    const existing = this.translationVisibleItems.indexOf(index);
    if (visible && existing < 0) {
      this.translationVisibleItems.push(index);
    } else if (!visible && existing >= 0) {
      this.translationVisibleItems.splice(existing, 1);
    }
    if (this.translationVisibleItems.length === 0) {
      if (this.translationVisibleStart !== -1 || this.translationVisibleEnd !== -1) {
        this.translationVisibleStart = -1;
        this.translationVisibleEnd = -1;
      }
      return;
    }
    let start = this.translationVisibleItems[0];
    let end = start;
    for (let i = 1; i < this.translationVisibleItems.length; i++) {
      start = Math.min(start, this.translationVisibleItems[i]);
      end = Math.max(end, this.translationVisibleItems[i]);
    }
    if (this.translationVisibleStart !== start || this.translationVisibleEnd !== end) {
      this.translationVisibleStart = start;
      this.translationVisibleEnd = end;
    }
  }

  private setVisibleTranslationRange(start: number, end: number): void {
    this.translationVisibleItems = [];
    if (this.translationVisibleStart !== start || this.translationVisibleEnd !== end) {
      this.translationVisibleStart = start;
      this.translationVisibleEnd = end;
    }
  }

  private translationPriorityFor(index: number): number {
    if (!this.translationEnabled) {
      return 0;
    }
    return translationPriorityForIndex(index, this.translationVisibleStart, this.translationVisibleEnd,
      this.galleryColumnCount());
  }

  private galleryCardTransition(): TransitionEffect {
    return TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut });
  }

  aboutToDisappear(): void {
    this.searchTagEndScrollRequest++;
    this.searchTagEndScrollPending = false;
    this.cardScrollAnchor.clear();
    this.unregisterActiveBackHandler();
    this.unregisterActiveBackHandler = () => {};
    this.floatingActionSideController.dispose();
  }

  private handleContentBack(): boolean {
    if (this.shouldHandleLocalBack()) {
      if (this.favoriteSettingsDialogVisible) {
        this.closeFavoriteSettingsDialog();
        return true;
      }
      if (this.bookmarkDrawerVisible) {
        this.closeBookmarkDrawer();
        return true;
      }
      if (this.favoriteDrawerVisible) {
        this.closeFavoriteDrawer();
        return true;
      }
      if (this.advancedPanelVisible) {
        this.closeAdvancedPanel();
        return true;
      }
      if (this.imageSearchPanelVisible) {
        this.closeImageSearchPanel();
        return true;
      }
      if (this.jumpPanelVisible) {
        this.closeJumpPanel();
        return true;
      }
    }
    return false;
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
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
      this.advancedPanelVisible = !this.advancedPanelVisible;
    });
  }

  private closeAdvancedPanel(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
      this.advancedPanelVisible = false;
    });
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

  private openImageSearchPanel(): void {
    this.advancedPanelVisible = false;
    this.jumpPanelVisible = false;
    this.imageSearchPanelVisible = true;
  }

  private closeImageSearchPanel(): void {
    this.imageSearchPanelVisible = false;
  }

  private totalBarHeight(): number {
    return this.statusBarVp() + this.barHeight();
  }

  private expandedTitleContentInset(): number {
    return galleryListTopInset(this.totalBarHeight());
  }

  private titleContentInset(): number {
    const visibleHeight = this.visibleBarHeight();
    if (visibleHeight <= 0) {
      return 0;
    }
    return visibleHeight + uiTitleBarFadeHeight() * 0.68;
  }

  private searchSuggestionTopInset(): number {
    // Keep the suggestion chips close to the search field while preserving
    // enough room for the status bar and toolbar.
    return this.totalBarHeight() + 8;
  }

  private imageSearchPanelWidth(): number {
    const width = this.effectiveContentWidth();
    if (width <= 0) {
      return 320;
    }
    return Math.min(320, Math.max(260, width - 24));
  }

  private imageSearchPanelMaxHeight(): number {
    if (this.viewportHeight <= 0) {
      return 420;
    }
    return Math.max(280, this.viewportHeight - 48);
  }

  private advancedPanelMaxHeight(): number {
    if (this.viewportHeight <= 0) {
      return 520;
    }
    return Math.max(360, this.viewportHeight - this.statusBarVp() - this.barHeight() - 28);
  }

  private quickActionsMaxHeight(): number {
    return floatingActionAvailableHeight(this.viewportHeight, this.statusBarVp() + this.barHeight() + 8);
  }

  onHoldingHandSettingChanged(): void {
    this.floatingActionSideController.syncFromSettings();
  }

  onFloatingActionSideSettingChanged(): void {
    this.floatingActionSideController.handleManualSettingChanged();
  }

  private animateFloatingActionSide(side: string): void {
    if (side === this.floatingActionSide) {
      return;
    }
    // 临界阻尼平滑停靠边缘，连续换手时由系统衔接当前动画速度。
    this.getUIContext().animateTo({ curve: curves.springMotion(0.35, 1) }, () => {
      this.floatingActionSide = side;
    });
  }

  private visibleBarHeight(): number {
    return immersiveChromeHeightFromOffset(this.toolbarState().offsetY, this.totalBarHeight());
  }

  private syncToolbarOffsetState(): void {
    this.toolbarOffsetBinding.set(this.toolbarOffsetY);
  }

  private isInitialLoadingState(): boolean {
    return this.galleries.length === 0 && !this.shouldShowSearchSuggestions() &&
      this.statusText.toLowerCase().indexOf('loading') >= 0;
  }

  private handleScrollFrame(scrollOffset: number): number {
    const yOffset = normalizeGalleryListScrollOffset(this.listScroller.currentOffset().yOffset);
    if (yOffset <= 4) {
      this.restoreToolbarOnReverseScroll();
      return scrollOffset;
    }
    if (scrollOffset > 0 && this.visibleBarHeight() > 0) {
      this.toolbarOffsetY = nextFloatingToolbarOffset(this.toolbarOffsetY, scrollOffset, yOffset, this.totalBarHeight());
      return scrollOffset;
    }
    if (scrollOffset < 0 && this.toolbarOffsetY < 0) {
      this.restoreToolbarOnReverseScroll();
    }
    return scrollOffset;
  }

  private restoreToolbarOnReverseScroll(): void {
    if (this.toolbarOffsetY >= 0) {
      return;
    }
    // 从当前收起位置展开；状态同步置为终点，后续下滑帧不会重复启动动画。
    this.toolbarOffsetY = 0;
    this.getUIContext().animateTo({ curve: curves.springMotion(0.35, 1) }, () => {
      this.toolbarState().offsetY = 0;
    });
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
    const cardHeight = galleryListMode() === 'Thumb' ?
      Math.max(0, this.galleryCardWidth() / this.galleryThumbnailAspectRatioAverage + 69) :
      galleryDetailCardHeight();
    return this.searchResultStripHeight() + rows * cardHeight +
      Math.max(0, rows - 1) * this.galleryCardGap() +
      this.expandedTitleContentInset() + this.galleryCardGap() * 2 + (this.isLoadingMore ? 40 : 0);
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
    return 0;
  }

  private listViewportHeight(): number {
    return galleryListViewportHeight(this.viewportHeight - this.contentStartOffset());
  }

  private searchResultStripHeight(): number {
    return 0;
  }

  private galleryCardPreferredWidth(): number {
    if (galleryListMode() !== 'Thumb') {
      return galleryDetailCardPreferredWidth();
    }
    return galleryThumbnailPreferredColumnWidth();
  }

  private galleryCardGap(): number {
    return uiListGap();
  }

  private galleryTopSpacerIndexes(): number[] {
    const columns = Math.max(1, this.galleryColumnCount());
    if (columns === this.topSpacerIndexesCacheColumns) {
      return this.topSpacerIndexesCache;
    }
    const indexes: number[] = [];
    for (let index = 0; index < columns; index++) {
      indexes.push(index);
    }
    this.topSpacerIndexesCache = indexes;
    this.topSpacerIndexesCacheColumns = columns;
    return indexes;
  }

  private galleryContentPadding(): number {
    // Keep gallery edges visually stable across phone and wide layouts. The
    // page-level padding remains responsive for settings and other surfaces.
    return galleryListHorizontalPadding(this.effectiveContentWidth());
  }

  private snapListToTop(): void {
    this.listScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.toolbarOffsetY = 0;
    this.syncToolbarOffsetState();
    this.onScrollUpdate(0);
  }

  private rememberListOffset(yOffset: number): void {
    if (this.refreshing) {
      return;
    }
    this.onScrollUpdate(yOffset);
  }

  private galleryColumnCount(): number {
    return this.galleryColumnCountForWidth(this.effectiveContentWidth());
  }

  private galleryCardWidth(): number {
    const availableWidth = Math.max(0, this.effectiveContentWidth() - this.galleryContentPadding() * 2);
    if (availableWidth <= 0 || Number.isNaN(availableWidth)) {
      return this.galleryCardPreferredWidth();
    }
    const columns = this.galleryColumnCount();
    const gap = this.galleryCardGap();
    return Math.max(this.galleryCardMinWidth(), Math.floor((availableWidth - gap * (columns - 1)) / columns));
  }

  private galleryListLanes(): number {
    if (this.shouldShowSearchSuggestions() || this.galleries.length === 0) {
      return 1;
    }
    return this.galleryColumnCount();
  }

  private galleryWaterFlowColumnsTemplate(): string {
    const columns = Math.max(1, this.galleryColumnCount());
    let template = '';
    for (let i = 0; i < columns; i++) {
      template += '1fr ';
    }
    return template.trim();
  }

  private useThumbnailWaterFlow(): boolean {
    return galleryListMode() === 'Thumb' &&
      !this.shouldShowSearchSuggestions() && this.galleries.length > 0;
  }

  private galleryColumnCountForWidth(width: number): number {
    const availableWidth = Math.max(0, width - this.galleryContentPadding() * 2);
    if (availableWidth <= 0 || Number.isNaN(availableWidth)) {
      return 1;
    }
    const preferred = this.galleryCardPreferredWidth();
    const gap = this.galleryCardGap();
    return galleryListColumnCount(width, preferred, gap);
  }

  private galleryCardMinWidth(): number {
    if (galleryListMode() !== 'Thumb') {
      return galleryDetailCardMinWidth();
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

  private scrollSearchTagsToEnd(): void {
    this.searchTagEndScrollPending = true;
    const request = ++this.searchTagEndScrollRequest;
    setTimeout(() => {
      this.alignSearchTagsToEnd(request, false);
    }, 0);
    setTimeout(() => {
      this.alignSearchTagsToEnd(request, false);
    }, 40);
    setTimeout(() => {
      this.alignSearchTagsToEnd(request, true);
    }, 100);
  }

  private alignSearchTagsToEnd(request: number, finish: boolean): void {
    if (request !== this.searchTagEndScrollRequest) {
      return;
    }
    this.searchTagScroller.scrollEdge(Edge.End);
    if (finish) {
      this.searchTagEndScrollPending = false;
    }
  }

  private alignPendingSearchTagsAfterLayout(): void {
    if (!this.searchTagEndScrollPending) {
      return;
    }
    const request = this.searchTagEndScrollRequest;
    setTimeout(() => {
      this.alignSearchTagsToEnd(request, false);
    }, 0);
  }

  private searchTagStripMaxWidth(): number {
    const width = this.effectiveContentWidth();
    if (width <= 0) {
      return 160;
    }
    return Math.max(80, width - 240);
  }

  private removeLastSearchTagFromEmptyInput(): boolean {
    if (this.searchInputText().length > 0) {
      return false;
    }
    const tokens = this.selectedSearchTagTokens();
    if (tokens.length === 0) {
      return false;
    }
    this.removeSearchTag(tokens[tokens.length - 1]);
    return true;
  }

  @Builder
  private searchTagChip(token: string) {
    Row({ space: 4 }) {
      Text(searchTagTokenDisplayLabel(token))
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
    .borderRadius(uiRadius(14))
    .flexShrink(0)
  }

  @Builder
  private searchKeywordEditor() {
    Row({ space: this.selectedSearchTagTokens().length > 0 ? 4 : 0 }) {
      if (this.selectedSearchTagTokens().length > 0) {
        Scroll(this.searchTagScroller) {
          Row({ space: 6 }) {
            ForEach(this.selectedSearchTagTokens(), (token: string) => {
              this.searchTagChip(token)
            }, (token: string) => token)
          }
          .onAreaChange((_oldArea: Area, _newArea: Area) => {
            this.alignPendingSearchTagsAfterLayout();
          })
        }
        .height(30)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .constraintSize({ maxWidth: this.searchTagStripMaxWidth() })
        .flexShrink(1)
      }

      TextInput({ text: this.searchInputText(), placeholder: uiText(this.searchPlaceholder) })
        .height(uiSearchFieldHeight())
        .layoutWeight(1)
        .constraintSize({ minWidth: 96 })
        .backgroundColor(themeTransparentColor())
        .placeholderColor(themeSecondaryText())
        .fontSize(16)
        .lineHeight(22)
        .fontColor(themePrimaryText())
        .caretColor(themeAccentTextColor())
        .padding({ left: this.selectedSearchTagTokens().length > 0 ? 4 : 8, right: 8, top: 0, bottom: 0 })
        .onFocus(() => {
          this.refreshSearchSuggestions();
          this.onSearchFocus();
        })
        .onChange((value: string) => {
          this.updateSearchInputText(value);
        })
        .onWillDelete((value: DeleteValue): boolean => {
          if (value.direction === TextDeleteDirection.BACKWARD && this.removeLastSearchTagFromEmptyInput()) {
            return false;
          }
          return true;
        })
        .onKeyEvent((event: KeyEvent): boolean => {
          if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_DEL) {
            return this.removeLastSearchTagFromEmptyInput();
          }
          return false;
        })
        .onSubmit(() => {
          this.closeAdvancedPanel();
          this.onSearch();
        })
    }
    .height(uiSearchFieldHeight())
    .layoutWeight(1)
    .padding({ left: 8, right: 8 })
    .backgroundColor(themeFieldBackground())
    .alignItems(VerticalAlign.Center)
    .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
  }

  private syncContentWidthFromWindow(): void {
    if (this.layoutWidthHint >= 240) {
      this.updateContentWidth(this.layoutWidthHint);
      return;
    }
    this.updateContentWidth(mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value)));
  }

  @Builder
  private searchResultNavContent() {
    Column() {
      Column()
        .height(this.statusBarVp())
        .width('100%')
        .backgroundColor(Color.Transparent)

      Row({ space: 8 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([galleryChromeForeground()])
      }
      .width(40)
      .height(40)
      .backgroundColor(uiMaterialBackground(galleryChromeBackground(themeOnPrimaryActionBackground())))
      .flexShrink(0)
      .backgroundEffect(uiTransparentButtonBackgroundEffect())
      .systemMaterial(uiButtonMaterial())
      .onClick(() => {
        this.onBack();
      })

      this.searchKeywordEditor()

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(22)
          .fontColor([galleryChromeForeground()])
      }
      .width(40)
      .height(40)
      .backgroundColor(uiMaterialBackground(galleryChromeBackground(
        this.advancedPanelVisible || this.advancedSearchEnabled ? themeOnPrimaryActionStrongBackground() :
          themeOnPrimaryActionBackground())))
      .flexShrink(0)
      .backgroundEffect(uiTransparentButtonBackgroundEffect())
      .systemMaterial(uiButtonMaterial())
      .onClick(() => {
        this.toggleAdvancedPanel();
      })
      }
      .width('100%')
      .height(this.barHeight())
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
  }

  private shouldShowSearchSuggestions(): boolean {
    return (this.isSearchResultScene || this.useLocalSearchBar) && !this.searchSubmitted;
  }

  private galleryCardWindowY(area: Area): number {
    const value = area.globalPosition.y;
    return value === undefined ? Number.NaN : Number.parseFloat(value.toString());
  }

  private captureGalleryCardAnchor(gallery: GalleryInfo, event?: ClickEvent): void {
    if (event === undefined) {
      return;
    }
    this.cardScrollAnchor.capture(this.galleryCardKey(gallery), this.galleryColumnCount(),
      this.galleryCardWindowY(event.target.area));
  }

  private observeGalleryCardAnchor(gallery: GalleryInfo, area: Area): void {
    this.cardScrollAnchor.observe(this.galleryCardKey(gallery), this.galleryColumnCount(),
      this.galleryCardWindowY(area), (deltaY: number) => {
        this.listScroller.scrollBy(0, deltaY);
        setTimeout(() => {
          this.rememberListOffset(normalizeGalleryListScrollOffset(this.listScroller.currentOffset().yOffset));
        }, 0);
      });
  }

  private shouldShowSearchOnlyFab(): boolean {
    return (this.isSearchResultScene || this.useLocalSearchBar) && !this.searchSubmitted;
  }

  private shouldShowTranslationAction(): boolean {
    return this.translationButtonsVisible && !this.shouldShowSearchSuggestions();
  }

  private refreshSearchSuggestions(namespaces: string[] = this.selectedTagNamespaces): void {
    this.searchSuggestionItems = buildSearchSuggestions(this.keyword, 0, namespaces);
    this.searchSuggestionRevision++;
  }

  private selectedTagNamespaceKey(): string {
    return sortedStringKey(this.selectedTagNamespaces);
  }

  private applySearchSuggestion(suggestion: SearchSuggestionItem): void {
    if (suggestion.kind === 'tag') {
      // query already contains the English namespace; title is only the translated label.
      this.onKeywordChange(applyTagSuggestionToKeyword(this.keyword,
        normalizeSearchTagToken(suggestion.query)));
      this.onSearchModeChange(ListMode.Normal);
      return;
    }
    this.onKeywordChange(suggestion.query);
  }

  private toggleTagNamespace(namespace: string): void {
    const next = toggleStringValue(this.selectedTagNamespaces, namespace);
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
          .layoutWeight(1)
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(28)
            .fontColor([themePlaceholderColor()])
          Text(uiText('Search history appears before typing; tag tips appear while typing'))
            .fontSize(12)
            .fontColor(themeTertiaryText())
        }
        .width('100%')
        .height(180)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(themeSurface())
        .borderRadius(uiRadius(6))
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 8, right: 8, top: 4 })
  }

  private openBookmarkDrawer(): void {
    if (!this.showBookmarkButton || this.bookmarkDrawerVisible) {
      return;
    }
    this.onBookmarkDrawerOpen();
    this.bookmarkDrawerVisible = true;
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.bookmarkDrawerOffsetX = 0;
      this.bookmarkDrawerOverlayOpacity = 0.45;
    });
  }

  private closeBookmarkDrawer(): void {
    if (!this.bookmarkDrawerVisible) {
      return;
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.bookmarkDrawerOffsetX = SIDE_PANEL_WIDTH;
      this.bookmarkDrawerOverlayOpacity = 0;
    });
    setTimeout(() => {
      if (this.bookmarkDrawerOffsetX > SIDE_PANEL_WIDTH - 40) {
        this.bookmarkDrawerVisible = false;
      }
    }, 220);
  }

  private startPullRefresh(): void {
    this.refreshing = true;
    let finished = false;
    const finish = () => {
      if (finished) {
        return;
      }
      finished = true;
      this.refreshing = false;
      setTimeout(() => {
        this.refreshing = false;
      }, 0);
    };
    setTimeout(() => {
      finish();
    }, 30000);
    try {
      this.onRefreshPull(finish);
    } catch (_error) {
      finish();
    }
  }

  @Builder
  private galleryRefreshIndicator() {
    Row()
      .width('100%')
      .height(this.titleContentInset())
  }

  private refreshIndicatorTop(): number {
    return this.titleContentInset() + Math.min(20, this.refreshPullOffset * 0.25);
  }

  @Builder
  private galleryItem(gallery: GalleryInfo, index: number) {
    ListItem() {
      if (galleryListMode() === 'Thumb') {
        GalleryThumbCard({
          gallery: gallery,
          translateTitle: this.translationEnabled,
          translationPriority: this.translationPriorityFor(index),
          onLongPress: (pressed: GalleryInfo) => {
            this.onLongPressGallery(pressed);
          }
        })
          .width('100%')
          .animation({ duration: 220, curve: Curve.EaseOut })
          .onClick((event?: ClickEvent) => {
            this.captureGalleryCardAnchor(gallery, event);
            this.onSelectGallery(gallery);
          })
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.observeGalleryCardAnchor(gallery, newArea);
          })
      } else {
        GalleryListRow({
          gallery: gallery,
          translateTitle: this.translationEnabled,
          translationPriority: this.translationPriorityFor(index),
          onLongPress: (pressed: GalleryInfo) => {
            this.onLongPressGallery(pressed);
          }
        })
          .width('100%')
          .animation({ duration: 220, curve: Curve.EaseOut })
          .onClick((event?: ClickEvent) => {
            this.captureGalleryCardAnchor(gallery, event);
            this.onSelectGallery(gallery);
          })
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.observeGalleryCardAnchor(gallery, newArea);
          })
      }
    }
    .reuseId('gallery-card-item')
    .onVisibleAreaChange([0.0, 0.01], (visible: boolean, _ratio: number) => {
      this.updateVisibleTranslationItem(index, visible);
    })
    .animation({ duration: 220, curve: Curve.EaseOut })
    .transition(this.galleryCardTransition())
  }

  @Builder
  private galleryFlowItem(gallery: GalleryInfo, index: number) {
    FlowItem() {
      GalleryThumbCard({
        gallery: gallery,
        translateTitle: this.translationEnabled,
        translationPriority: this.translationPriorityFor(index),
        onLongPress: (pressed: GalleryInfo) => {
          this.onLongPressGallery(pressed);
        }
      })
        .width('100%')
        .animation({ duration: 220, curve: Curve.EaseOut })
        .onClick((event?: ClickEvent) => {
          this.captureGalleryCardAnchor(gallery, event);
          this.onSelectGallery(gallery);
        })
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.observeGalleryCardAnchor(gallery, newArea);
        })
    }
    .width('100%')
    .reuseId('gallery-thumb-flow-item')
    .animation({ duration: 220, curve: Curve.EaseOut })
    .transition(this.galleryCardTransition())
  }

  @Builder
  private galleryListEdgeSpacer() {
    Row()
      .width('100%')
      .height(this.expandedTitleContentInset())
  }

  @Builder
  private galleryListFooter() {
    Column() {
      if (this.isLoadingMore) {
        Row() {
          LoadingProgress().width(20).height(20).color(themePlaceholderColor())
          Text(uiText('Loading...')).fontSize(12).fontColor(themePlaceholderColor()).margin({ left: 6 })
        }
        .width('100%')
        .height(40)
        .justifyContent(FlexAlign.Center)
      }
      Row()
        .width('100%')
        .height(this.galleryCardGap())
    }
    .width('100%')
  }

  @Builder
  private galleryStandardList() {
    List({ space: 0, scroller: this.listScroller }) {
      if (this.shouldShowSearchSuggestions()) {
        ListItem() {
          Row().width('100%').height(this.searchSuggestionTopInset())
        }
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
        ListItemGroup({
          header: this.galleryListEdgeSpacer(),
          footer: this.galleryListFooter(),
          space: this.galleryCardGap()
        }) {
          LazyForEach(this.galleryThumbnailSource, (gallery: GalleryInfo, index: number) => {
            this.galleryItem(gallery, index)
          }, (gallery: GalleryInfo) => this.galleryCardKey(gallery))
        }
      }
    }
    .scrollBar(BarState.Auto)
    .lanes(this.galleryListLanes(), this.galleryCardGap())
    .enableScrollInteraction(!this.isInitialLoadingState())
    .edgeEffect(this.isInitialLoadingState() ? EdgeEffect.None : EdgeEffect.Spring,
      { alwaysEnabled: !this.isInitialLoadingState(), effectEdge: EffectEdge.START | EffectEdge.END })
    .cachedCount(10)
    .padding({
      top: this.galleries.length > 0 ? 0 : this.expandedTitleContentInset(),
      left: this.galleries.length > 0 ? this.galleryContentPadding() : 0,
      right: this.galleries.length > 0 ? this.galleryContentPadding() : 0
    })
    .width('100%')
    .height('100%')
    .onAppear(() => {
      this.restoreInitialListOffset();
    })
    .onScrollFrameBegin((offset: number, _state: ScrollState) => {
      const remaining = this.handleScrollFrame(offset);
      this.syncToolbarOffsetState();
      return { offsetRemain: remaining };
    })
    .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
      this.handleGalleryListDidScroll();
    })
    .onScrollStop(() => {
      this.rememberListOffset(normalizeGalleryListScrollOffset(this.listScroller.currentOffset().yOffset));
    })
    .onReachEnd(() => {
      if (!this.shouldShowSearchSuggestions()) {
        this.triggerLoadMoreIfNear(this.galleries.length);
      }
    })
  }

  @Builder
  private galleryThumbnailWaterFlow() {
    WaterFlow({
      footer: this.galleryListFooter(),
      scroller: this.listScroller,
      layoutMode: WaterFlowLayoutMode.SLIDING_WINDOW
    }) {
      ForEach(this.galleryTopSpacerIndexes(), (index: number) => {
        FlowItem() {
          Row()
            .width('100%')
            .height(this.expandedTitleContentInset())
        }
        .width('100%')
      }, (index: number) => 'gallery-top-spacer-' + index.toString())
      LazyForEach(this.galleryThumbnailSource, (gallery: GalleryInfo, index: number) => {
        this.galleryFlowItem(gallery, index)
      }, (gallery: GalleryInfo) => this.galleryCardKey(gallery))
    }
    .columnsTemplate(this.galleryWaterFlowColumnsTemplate())
    .columnsGap(this.galleryCardGap())
    .rowsGap(this.galleryCardGap())
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true, effectEdge: EffectEdge.START | EffectEdge.END })
    // 挂载屏外缓存节点，配合本地缩略图同步加载，在入屏前完成布局和解码。
    .cachedCount(GALLERY_THUMBNAIL_CACHE_COUNT, true)
    .clip(true)
    .padding({
      left: this.galleryContentPadding(),
      right: this.galleryContentPadding()
    })
    .width('100%')
    .height('100%')
    .onAppear(() => {
      this.restoreInitialListOffset();
    })
    .onScrollFrameBegin((offset: number, _state: ScrollState) => {
      const remaining = this.handleScrollFrame(offset);
      this.syncToolbarOffsetState();
      return { offsetRemain: remaining };
    })
    .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
      this.handleGalleryListDidScroll();
    })
    .onScrollIndex((first: number, last: number) => {
      // 每列的顶部占位块也占用 FlowItem 索引，需先换算为画廊索引。
      const spacerCount = this.galleryTopSpacerIndexes().length;
      const galleryFirst = Math.max(0, first - spacerCount);
      const galleryLast = Math.min(this.galleries.length - 1, last - spacerCount);
      this.setVisibleTranslationRange(galleryFirst, galleryLast);
      this.prefetchGalleryThumbnailRange(galleryFirst, galleryLast);
    })
    .onScrollStop(() => {
      this.rememberListOffset(normalizeGalleryListScrollOffset(this.listScroller.currentOffset().yOffset));
    })
    .onReachEnd(() => {
      this.triggerLoadMoreIfNear(this.galleries.length);
    })
  }

  private prefetchGalleryThumbnail(gallery: GalleryInfo): void {
    const url = gallery.thumb === undefined ? '' : gallery.thumb;
    if (url.length === 0) {
      return;
    }
    cacheThumbnailImage(url);
  }

  private prefetchGalleryThumbnailRange(first: number, last: number): void {
    if (this.galleries.length === 0 || first < 0 || last < first) {
      return;
    }
    const start = Math.max(0, first - GALLERY_THUMBNAIL_PREFETCH_BEFORE);
    const end = Math.min(this.galleries.length - 1, last + GALLERY_THUMBNAIL_PREFETCH_AFTER);
    for (let index = start; index <= end; index++) {
      this.prefetchGalleryThumbnail(this.galleries[index]);
    }
  }

  private restoreInitialListOffset(): void {
    this.syncContentWidthFromWindow();
    if (!this.restoredScroll && this.initialScrollOffset > 0) {
      this.restoredScroll = true;
      setTimeout(() => {
        this.listScroller.scrollTo({ xOffset: 0, yOffset: this.initialScrollOffset });
      }, 80);
    }
  }

  private handleGalleryListDidScroll(): void {
    const yOffset = normalizeGalleryListScrollOffset(this.listScroller.currentOffset().yOffset);
    const delta = yOffset - this.lastToolbarScrollOffset;
    this.lastToolbarScrollOffset = yOffset;
    if (yOffset <= 4) {
      this.toolbarRestoring = false;
      this.toolbarOffsetY = 0;
    } else if (delta > 0.1) {
      this.toolbarRestoring = false;
      this.toolbarOffsetY = -Math.min(yOffset, this.totalBarHeight());
    } else if (delta < -0.1) {
      this.restoreToolbarOnReverseScroll();
    }
    this.syncToolbarOffsetState();
    this.rememberListOffset(yOffset);
    if (!this.shouldShowSearchSuggestions()) {
      const now = Date.now();
      if (now - this.lastLoadMoreOffsetCheck >= 200) {
        this.lastLoadMoreOffsetCheck = now;
        this.triggerLoadMoreByOffset(yOffset);
      }
    }
  }

  @Builder
  private galleryListContent() {
    if (this.useThumbnailWaterFlow() && (this.thumbnailDimensionsReady || this.hasRenderedGalleries)) {
      this.galleryThumbnailWaterFlow()
    } else if (galleryListMode() === 'Thumb' && !this.shouldShowSearchSuggestions() && this.galleries.length > 0 &&
      !this.thumbnailDimensionsReady) {
      Stack({ alignContent: Alignment.Center }) {
        LoadingProgress()
          .width(36)
          .height(36)
          .color(themePlaceholderColor())
      }
      .width('100%')
      .height('100%')
    } else {
      this.galleryStandardList()
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (this.shouldShowSearchSuggestions()) {
          Row()
            .width('100%')
            .height(this.searchSuggestionTopInset())
          this.searchSuggestionPlaceholder()
        } else if (this.isInitialLoadingState()) {
          Stack({ alignContent: Alignment.TopStart }) {
            this.galleryListContent()
          }
          .width('100%')
          .height('100%')
          .translate({ y: this.contentStartOffset() })
          .backgroundColor(themePageBackground())
        } else {
          Refresh({ refreshing: this.refreshing, builder: this.galleryRefreshIndicator }) {
            this.galleryListContent()
          }
          .refreshOffset(this.REFRESH_OFFSET)
          .pullToRefresh(true)
          .onOffsetChange((offset: number) => {
            this.refreshPullOffset = Math.max(0, offset);
          })
          .onRefreshing(() => {
            this.startPullRefresh();
          })
          .width('100%')
          .height('100%')
          .translate({ y: this.contentStartOffset() })
          .backgroundColor(themePageBackground())
        }
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.updateContentWidth(this.layoutWidthHint >= 240 ? this.layoutWidthHint : newArea.width as number);
        const h = newArea.height as number;
        if (h > 0 && !Number.isNaN(h)) {
          this.viewportHeight = h;
        }
      })

      if (this.favoriteDrawerVisible) {
        RightSidePanelLayer({
          drawerLeft: this.favoriteDrawerLeft(),
          drawerOffsetX: this.favoriteDrawerOffsetX,
          overlayOpacity: this.favoriteDrawerOverlayOpacity,
          layerZIndex: 15,
          onClose: () => {
            this.closeFavoriteDrawer();
          }
        }) {
          FavoriteCategoryDrawer({
            statusBarHeight: this.statusBarVp(),
            selectedFavCat: this.favoriteCat,
            categories: this.favoriteCategories,
            localFavoriteCount: this.favoriteLocalCount,
            onSelect: (favCat: number) => {
              this.closeFavoriteDrawer();
              this.onFavoriteCatChange(favCat);
            },
            onSettings: () => {
              this.openFavoriteSettingsDialog();
            }
          })
        }
      }

      if (this.bookmarkDrawerVisible) {
        RightSidePanelLayer({
          drawerLeft: this.bookmarkDrawerLeft(),
          drawerOffsetX: this.bookmarkDrawerOffsetX,
          overlayOpacity: this.bookmarkDrawerOverlayOpacity,
          layerZIndex: 17,
          onClose: () => {
            this.closeBookmarkDrawer();
          }
        }) {
          SearchBookmarkDrawer({
            statusBarHeight: this.statusBarVp(),
            bookmarks: this.bookmarks,
            onSelect: (bookmark: SearchBookmarkInfo) => {
              this.closeBookmarkDrawer();
              this.onSelectBookmark(bookmark);
            },
            onAdd: () => {
              this.closeBookmarkDrawer();
              this.onAddBookmark();
            },
            onSettings: () => {
              this.closeBookmarkDrawer();
              this.onBookmarkSettings();
            },
            onDelete: (bookmark: SearchBookmarkInfo) => {
              this.onDeleteBookmark(bookmark);
            }
          })
        }
      }

      if (this.favoriteSettingsDialogVisible) {
        DefaultFavoriteSlotDialog({
          selectedSlot: this.defaultFavoriteSlot,
          categories: this.favoriteCategories,
          panelMaxHeight: this.favoriteSettingsDialogMaxHeight(),
          onSelect: (slot: number | null) => {
            this.selectDefaultFavoriteSlot(slot);
          },
          onClose: () => {
            this.closeFavoriteSettingsDialog();
          }
        })
          .zIndex(30)
          .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
      }

      // FAB 悬浮按钮
      FloatingActionDock({ side: this.floatingActionSide }) {
        if (this.shouldShowSearchOnlyFab()) {
          SearchActionColumn({
            showTranslationButton: this.shouldShowTranslationAction(),
            translationEnabled: this.translationEnabled,
            side: this.floatingActionSide,
            onSearch: () => {
              this.onSearch();
            },
            onTranslate: () => {
              ehTranslationService.setEnabled(!this.translationEnabled);
            },
            onSideChange: (side: string) => {
              this.floatingActionSideController.handleManualSide(side);
            }
          })
        } else {
          QuickActionColumn({
            expanded: this.actionsExpanded,
            filterActive: this.filterActive,
            accountFilterEnabled: this.isSearchResultScene ? this.searchFilterEnabled : this.accountFilterEnabled,
            canJump: this.canJump,
            canRandom: this.canRandom,
            canImageSearch: !this.useLocalSearchBar,
            canBookmark: this.showBookmarkButton,
            showTranslationButton: this.shouldShowTranslationAction(),
            translationEnabled: this.translationEnabled,
            maxExpandedHeight: this.quickActionsMaxHeight(),
            side: this.floatingActionSide,
            onToggle: this.onToggleActions,
            onFilter: this.onFilter,
            onJump: () => {
              this.openJumpPanel();
            },
            onRefresh: this.onRefresh,
            onTranslate: () => {
              ehTranslationService.setEnabled(!this.translationEnabled);
            },
            onRandom: this.onRandom,
            onImageSearch: () => {
              this.openImageSearchPanel();
            },
            onBookmark: () => {
              this.onAddBookmark();
            },
            onSideChange: (side: string) => {
              this.floatingActionSideController.handleManualSide(side);
            }
          })
        }
      }

      if (this.advancedPanelVisible) {
        PopupScrim({
          showCutout: this.effectiveContentWidth() > 20 && this.advancedPopupHeight > 0,
          positionedCutout: true,
          cutoutX: 10,
          cutoutY: this.statusBarVp() + this.barHeight() + 8,
          cutoutWidth: Math.max(0, this.effectiveContentWidth() - 20),
          cutoutHeight: this.advancedPopupHeight,
          cutoutRadius: uiRadius(8),
          onDismiss: () => {
            this.closeAdvancedPanel();
          }
        })
          .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseInOut }))
          .zIndex(11)

        Stack({ alignContent: Alignment.Top }) {
          SearchAdvancedPanel({
            searchModeValue: this.searchModeValue,
            searchCategory: this.searchCategory,
            advancedSearchEnabled: this.advancedSearchEnabled,
            advanceSearch: this.advanceSearch,
            searchFilterEnabled: this.searchFilterEnabled,
            minRating: this.minRating,
            pageFrom: this.pageFrom,
            pageTo: this.pageTo,
            panelMaxHeight: this.advancedPanelMaxHeight(),
            onSearchModeChange: this.onSearchModeChange,
            onSearchCategoryChange: this.onSearchCategoryChange,
            onAdvancedEnabledChange: this.onAdvancedEnabledChange,
            onAdvanceSearchChange: this.onAdvanceSearchChange,
            onMinRatingChange: this.onMinRatingChange,
            onPageFromChange: this.onPageFromChange,
            onPageToChange: this.onPageToChange,
            onClose: () => {
              this.closeAdvancedPanel();
            },
            onSearch: () => {
              this.closeAdvancedPanel();
              this.onSearch();
            }
          })
            .constraintSize({ maxHeight: this.advancedPanelMaxHeight() })
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              this.advancedPopupHeight = Number.parseFloat(newArea.height.toString());
            })
            .transition(TransitionEffect.move(TransitionEdge.TOP)
              .animation({ duration: 180, curve: Curve.EaseOut }))
        }
          .width('100%')
          .height('100%')
          .padding({ top: this.statusBarVp() + this.barHeight() + 8, left: 10, right: 10 })
          .hitTestBehavior(HitTestMode.Transparent)
          .zIndex(12)
      }

      if (this.imageSearchPanelVisible) {
        Stack({ alignContent: Alignment.Center }) {
          PopupScrim({
            showCutout: this.imageSearchPopupWidth > 0 && this.imageSearchPopupHeight > 0,
            cutoutWidth: this.imageSearchPopupWidth,
            cutoutHeight: this.imageSearchPopupHeight,
            cutoutRadius: uiRadius(8),
            onDismiss: () => {
              this.closeImageSearchPanel();
            }
          })

          ImageSearchPanel({
            panelWidth: this.imageSearchPanelWidth(),
            panelMaxHeight: this.imageSearchPanelMaxHeight(),
            onClose: () => {
              this.closeImageSearchPanel();
            },
            onSearch: (path: string, useSimilarityScan: boolean, onlySearchCovers: boolean) => {
              this.closeImageSearchPanel();
              this.onImageSearch(path, useSimilarityScan, onlySearchCovers);
            }
          })
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.imageSearchPopupWidth = Number.parseFloat(newArea.width.toString());
            this.imageSearchPopupHeight = Number.parseFloat(newArea.height.toString());
          })
        }
          .width('100%')
          .height('100%')
          .zIndex(13)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
      }

      if (this.jumpPanelVisible) {
        PopupScrim({
          showCutout: this.jumpPopupHeight > 0,
          positionedCutout: true,
          cutoutX: this.effectiveContentWidth() > 0 ? Math.max(12,
            this.effectiveContentWidth() - (this.useSeekJumpPanel() ? 304 : 244)) : 100,
          cutoutY: this.viewportHeight > 0 ? Math.max(96,
            this.viewportHeight - (this.useSeekJumpPanel() ? 310 : 210)) : 360,
          cutoutWidth: this.useSeekJumpPanel() ? 280 : 220,
          cutoutHeight: this.jumpPopupHeight,
          cutoutRadius: uiRadius(8),
          onDismiss: () => {
            this.closeJumpPanel();
          }
        })
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
          .zIndex(13)

        Column({ space: 10 }) {
          if (this.useSeekJumpPanel()) {
            Text(uiText('Jump/Seek'))
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
                    .fontColor(uiMaterialForegroundColor(themeAccentTextColor()))
                    .backgroundColor(uiMaterialBackground(themeFieldBackground()))
                    .borderRadius(uiRadius(4))
                    .backgroundEffect(uiTransparentButtonBackgroundEffect())
                    .systemMaterial(uiButtonMaterial())
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
                .height(uiSearchFieldHeight())
                .layoutWeight(1.4)
                .type(InputType.Number)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .padding({ left: 8, right: 8 })
                .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
                .onChange((value: string) => {
                  this.seekYearDraft = value;
                })
              TextInput({ text: this.seekMonthDraft, placeholder: '6' })
                .height(uiSearchFieldHeight())
                .layoutWeight(1)
                .type(InputType.Number)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .padding({ left: 8, right: 8 })
                .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
                .onChange((value: string) => {
                  this.seekMonthDraft = value;
                })
              TextInput({ text: this.seekDayDraft, placeholder: '26' })
                .height(uiSearchFieldHeight())
                .layoutWeight(1)
                .type(InputType.Number)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .padding({ left: 8, right: 8 })
                .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
                .onChange((value: string) => {
                  this.seekDayDraft = value;
                })
            }

            Button(uiText('Seek date'))
              .height(36)
              .width('100%')
              .fontSize(13)
              .fontColor(uiMaterialForegroundColor(themeOnPrimaryText()))
              .backgroundColor(uiMaterialBackground(themePrimaryColor()))
              .borderRadius(uiRadius(4))
              .backgroundEffect(uiTransparentButtonBackgroundEffect())
              .systemMaterial(uiButtonMaterial())
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
                .height(uiSearchFieldHeight())
                .layoutWeight(1)
                .type(InputType.Number)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .padding({ left: 10, right: 10 })
                .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
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
              .fontColor(uiMaterialForegroundColor(themeOnPrimaryText()))
              .backgroundColor(uiMaterialBackground(themePrimaryColor()))
              .borderRadius(uiRadius(4))
              .backgroundEffect(uiTransparentButtonBackgroundEffect())
              .systemMaterial(uiButtonMaterial())
              .onClick(() => {
                this.submitPageJump();
                this.closeJumpPanel();
              })
          }
        }
        .width(this.useSeekJumpPanel() ? 280 : 220)
        .padding(12)
        .backgroundColor(themeSurface())
        .borderRadius(uiRadius(8))
        .shadow({
          radius: 12,
          color: themeShadowColor(),
          offsetX: 0,
          offsetY: 4
        })
        .position({
          x: this.effectiveContentWidth() > 0 ? Math.max(12,
            this.effectiveContentWidth() - (this.useSeekJumpPanel() ? 304 : 244)) : 100,
          y: this.viewportHeight > 0 ? Math.max(96, this.viewportHeight - (this.useSeekJumpPanel() ? 310 : 210)) : 360
        })
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.jumpPopupHeight = Number.parseFloat(newArea.height.toString());
        })
        .zIndex(14)
      }

      // 浮动导航栏
      if (this.isSearchResultScene || this.useLocalSearchBar) {
        GallerySearchNavBarHost({
          toolbarState: this.toolbarState(),
          searchSubmitted: this.searchSubmitted,
          showBackdrop: this.searchSubmitted,
          statusBarHeight: this.statusBarVp(),
          totalBarHeight: this.totalBarHeight()
        }) {
          this.searchResultNavContent()
        }
      } else {
        GalleryHomeNavBarHost({
          toolbarState: this.toolbarState(),
          statusBarHeight: this.statusBarVp(),
          title: this.searchTitle.length > 0 ? this.searchTitle : this.sceneTitle,
          keyword: this.keyword,
          filterActive: this.filterActive,
          showSearchButton: this.showSearchButton,
          showFavoriteButton: this.showFavoriteButton,
          showBookmarkButton: this.showBookmarkButton,
          showBackButton: this.showBackButton,
          onMenu: () => {
            this.onMenu();
          },
          onBack: () => {
            this.onBack();
          },
          onSearch: () => {
            this.onSearch();
          },
          onFavoriteButton: () => {
            this.openFavoriteDrawer();
          },
          onBookmarkButton: () => {
            this.openBookmarkDrawer();
          },
          onKeywordChange: (v: string) => {
            this.onKeywordChange(v);
          },
          onRefresh: () => {
            this.onRefresh();
          }
        })
      }

      if (!this.isInitialLoadingState() && (this.refreshPullOffset > 0 || this.refreshing)) {
        Row() {
          LoadingProgress()
            .width(24)
            .height(24)
            .color(themeAccentTextColor())
        }
        .width('100%')
        .height(24)
        .justifyContent(FlexAlign.Center)
        .position({ x: 0, y: this.refreshIndicatorTop() })
        .opacity(this.refreshing ? 1 : Math.min(1, this.refreshPullOffset / this.REFRESH_OFFSET))
        .hitTestBehavior(HitTestMode.None)
        .zIndex(16)
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Left, distance: 28 })
        .onActionEnd((event: GestureEvent | undefined) => {
          this.handleOpenFavoriteDrawerPan(event);
          this.handleOpenBookmarkDrawerPan(event);
        })
    )
  }

  private galleryCardKey(gallery: GalleryInfo): string {
    return gallery.gid.toString() + ':' + gallery.token + ':' + gallery.title;
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
    return lower.indexOf('loading') >= 0;
  }

  private isError(): boolean {
    const lower = this.statusText.toLowerCase();
    return lower.indexOf('failed') >= 0 || lower.indexOf('error') >= 0 ||
      lower.indexOf('blocked') >= 0 || lower.indexOf('banned') >= 0 ||
      lower.indexOf('required') >= 0;
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
          .color(themeAccentTextColor())
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
          .fontColor(uiMaterialForegroundColor(themeOnPrimaryText()))
          .backgroundColor(uiMaterialBackground(themePrimaryColor()))
          .margin({ top: 16 })
          .backgroundEffect(uiTransparentButtonBackgroundEffect())
          .systemMaterial(uiButtonMaterial())
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


