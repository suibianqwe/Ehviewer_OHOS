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
import { CacheClearResult, readerImageCache } from '../services/ReaderImageCache';
import { ehSpiderInfoStore } from '../services/EhSpiderInfoStore';
import { MigrationTask, migrationTasks } from '../services/MigrationStatus';
import { FilterRule, FILTER_MODE_TITLE, FILTER_MODE_UPLOADER, FILTER_MODE_TAG, FILTER_MODE_TAG_NAMESPACE, ehFilterStore } from '../services/EhFilterStore';
import { APP_THEME_COLOR, LANGUAGE_REVISION_KEY, themeSurfaceColor } from '../shared/EhShared';
import { EhBackupBundle, DrawerItem, SettingsHeaderItem, SettingsRowItem, SessionMode, SettingsPanel, DRAWER_ITEMS, SETTINGS_HEADERS, STATUS_BAR_HEIGHT_KEY, ON_OFF_OPTIONS, shouldUseChineseUi, uiText, uiValue, uiStatusText, uiPageText, zhText, setActiveBackHandler, runActiveBackHandler, createEmptyGallery, createEmptyDownloadInfo, createDetailFromGallery, createEmptyDetail, createEmptyPreview, createEmptyPage, createEmptyTopListDetail, createEmptyTopListInfo, createEmptyTopListBucket, createEmptyTopListItem, cloneStringArray, cloneRequiredStringArray, cloneGalleryInfo, cloneGalleryInfos, padTwo, applyGalleryFilters, cloneGalleryTagGroups, cloneGalleryComments, cloneGalleryPreviews, cloneGalleryDetail, cloneGalleryPage, createReaderLoadingPage, cloneTopListItem, cloneTopListBucket, cloneTopListInfo, cloneTopListDetail, getAbilityContext, saveGalleryToHistory, saveGalleryReadPosition, readerStartIndex, downloadButtonText, toggleGalleryDownload, saveDownloadsQuietly, filterDownloadItems, downloadItemMatches, sortDownloadItems, nextDownloadStatusFilter, nextDownloadLabelFilter, nextDownloadSortMode, nextStringOption, nextDownloadState, nextDownloadLabel, downloadLabelName, downloadStateLabel, downloadStateColor, downloadProgressText, downloadSizeText, downloadImageUrlForPage, downloadThreadLimit, downloadPageIndexes, downloadQueueSummary, parseHistoryMaxSize, routeTitle, routeSubtitle, launchRouteFromSetting, settingsPanelTitle, settingsRowsForPanel, optionSettingsRow, textSettingsRow, staticSettingsRow, settingEntryValue, cloneStringOptions, settingMigrationMessage, nextOption, isValidProxyPortText, formatNetworkDiagnostics, listModeForRoute, routeUsesKeyword, usesGallerySearchToolbar, usesEmbeddedToolbar, defaultKeywordForRoute, gallerySearchTitle, currentGallerySite, effectiveListSite, gallerySiteName, galleryListFailureMessage, shouldRetryGalleryListOnE, withGalleryListMessage, readerPageReferer, readerDisplayImageUrl, cacheReaderImageForPage, cacheThumbnailImage, cloneGalleryPageWithCache, readerLocalImageSource, readerZoomSize, readerFullImageWidth, readerFullImageHeight, readerImageFit, readerShortUrl, readerPreloadCount, readerIsRightToLeft, categoryName, categoryColor, ratingText, galleryDisplayTitle, showGalleryPages, galleryListMode, galleryThumbWidth, galleryThumbHeight, galleryRowHeight, galleryTagPreview, detailTitleFontSize, detailTitleMaxLines, detailHeadingFontSize, readerShowProgress, readerShowClock, readerClockText, padTimeNumber, topListChipColor } from '../shared/EhShared';
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
  @State resultCount: string = '';
  @State galleries: GalleryInfo[] = [];
  @State hasFirstRefresh: boolean = false;
  @State searchActive: boolean = false;
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

  aboutToAppear(): void {
    this.keyword = this.initialKeyword.length > 0 ? this.initialKeyword : defaultKeywordForRoute(this.sourceRoute);
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

  private loadRemote(pageIndex: number): void {
    this.pageIndex = pageIndex;
    this.statusText = 'Loading...';
    this.resultCount = '';
    this.galleries = [];
    this.isLoadingMore = false;
    this.renderVersion++;
    this.closeDetail();
    const request = this.loadRoutePageWithFallback(pageIndex);

    request.then((result: GalleryListLoadResult) => {
      this.requestUrl = result.url;
      this.galleries = applyGalleryFilters(cloneGalleryInfos(result.galleries));
      this.statusText = result.ok ? result.message : galleryListFailureMessage(result, this.activeSite);
      this.totalPages = result.pages;
      this.resultCount = result.resultCount;
      this.renderVersion++;
    }).catch((error: Error) => {
      this.statusText = 'Load failed: ' + error.message;
      this.galleries = [];
      this.renderVersion++;
    });
  }

  private loadAppendPage(): void {
    if (this.isLoadingMore) {
      return;
    }
    // Only stop if we have confirmed total page count AND already at the last page
    if (this.totalPages > 0 && this.pageIndex >= this.totalPages - 1) {
      this.statusText = uiText('All pages loaded');
      return;
    }
    const nextPage = this.pageIndex + 1;
    this.isLoadingMore = true;
    this.renderVersion++;

    this.loadRoutePageWithFallback(nextPage).then((result: GalleryListLoadResult) => {
      this.requestUrl = result.url;
      const newGalleries = applyGalleryFilters(cloneGalleryInfos(result.galleries));
      if (newGalleries.length === 0) {
        // Empty page = reached the end even if we don't know total
        this.statusText = uiText('All pages loaded');
        this.isLoadingMore = false;
        this.renderVersion++;
        return;
      }
      const existingGids: Set<number> = new Set(this.galleries.map((g: GalleryInfo) => g.gid));
      const unique: GalleryInfo[] = newGalleries.filter((g: GalleryInfo) => !existingGids.has(g.gid));
      this.galleries = this.galleries.concat(unique);
      this.pageIndex = nextPage;
      if (result.pages > 0) {
        this.totalPages = result.pages;
      }
      this.resultCount = result.resultCount;
      this.statusText = result.ok ? result.message : galleryListFailureMessage(result, this.activeSite);
      this.isLoadingMore = false;
      this.renderVersion++;
    }).catch((error: Error) => {
      this.statusText = 'Load more failed: ' + error.message;
      this.isLoadingMore = false;
      this.renderVersion++;
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

  private toggleSearchBar(): void {
    this.searchActive = !this.searchActive;
  }

  private applySearch(): void {
    this.searchActive = false;
    this.fabExpanded = false;
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
          searchActive: this.searchActive,
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
          onToggleSearch: () => {
            this.toggleSearchBar();
          },
          onSearch: () => {
            this.applySearch();
          },
          onRefresh: () => {
            this.loadRemote(0);
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
          initialScrollOffset: this.listScrollOffset,
          onScrollUpdate: (offset: number) => {
            this.listScrollOffset = offset;
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
  @Prop searchActive: boolean = false;
  @Prop actionsExpanded: boolean = false;
  @Prop filterActive: boolean = false;
  @Prop canJump: boolean = false;
  @Prop canRandom: boolean = false;
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  @Prop isLoadingMore: boolean = false;
  @Prop galleries: GalleryInfo[] = [];
  onKeywordChange: (value: string) => void = () => {};
  onMenu: () => void = () => {};
  onToggleSearch: () => void = () => {};
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
  @State toolbarVisible: boolean = true;
  private listScroller: Scroller = new Scroller();
  private loadMorePending: boolean = false;
  private lastScrollOffset: number = 0;

  private triggerLoadMoreIfNear(last: number): void {
    if (this.isLoadingMore || this.loadMorePending) {
      return;
    }
    if (this.galleries.length > 0 && last >= this.galleries.length - 6) {
      this.loadMorePending = true;
      this.onLoadMore();
      // Reset local guard after one frame so rapid scroll events don't queue duplicates
      setTimeout(() => { this.loadMorePending = false; }, 500);
    }
  }

  private updateToolbarForScroll(offset: number): void {
    if (offset <= 4) {
      this.toolbarVisible = true;
    } else if (offset > this.lastScrollOffset + 8) {
      this.toolbarVisible = false;
    } else if (offset < this.lastScrollOffset - 8) {
      this.toolbarVisible = true;
    }
    this.lastScrollOffset = Math.max(0, offset);
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.galleries.length === 0) {
          Column() {
            GalleryListStateView({
              statusText: this.statusText,
              requestUrl: this.requestUrl,
              onRefresh: this.onRefresh
            })
              .layoutWeight(1)
          }
          .width('100%')
          .height('100%')
          .padding({ top: this.requestUrl.length > 0 ? 88 : 62 })
        } else {
          Grid(this.listScroller) {
            ForEach(this.galleries, (gallery: GalleryInfo) => {
              GridItem() {
                if (galleryListMode() === 'Thumb') {
                  GalleryThumbCard({ gallery: gallery })
                    .onClick(() => { this.onSelectGallery(gallery); })
                } else {
                  GalleryListRow({ gallery: gallery })
                    .onClick(() => { this.onSelectGallery(gallery); })
                }
              }
            }, (gallery: GalleryInfo) => gallery.gid.toString() + ':' + this.renderVersion.toString())
          }
          .columnsTemplate(galleryListMode() === 'Thumb' ? 'repeat(auto-fit, 120vp)' : 'repeat(auto-fit, 320vp)')
          .columnsGap(galleryListMode() === 'Thumb' ? 6 : 8)
          .rowsGap(galleryListMode() === 'Thumb' ? 6 : 8)
          .width('100%')
          .height('100%')
          .padding({ left: 8, right: 8, top: this.requestUrl.length > 0 ? 96 : 70, bottom: 0 })
          .onAppear(() => {
            if (this.initialScrollOffset > 0) {
              this.listScroller.scrollTo({ xOffset: 0, yOffset: this.initialScrollOffset });
              this.lastScrollOffset = this.initialScrollOffset;
            }
          })
          .onScrollStop(() => {
            const offset = this.listScroller.currentOffset().yOffset;
            this.updateToolbarForScroll(offset);
            this.onScrollUpdate(offset);
          })
          .onScrollIndex((first: number, last: number) => {
            this.updateToolbarForScroll(this.listScroller.currentOffset().yOffset);
            this.triggerLoadMoreIfNear(last);
          })
        }

        FloatingToolbar({ visible: this.toolbarVisible, barHeight: this.requestUrl.length > 0 ? 88 : 62 }) {
          SearchBarCard({
            keyword: this.keyword,
            title: this.searchTitle,
            searchActive: this.searchActive,
            filterActive: this.filterActive,
            requestUrl: this.requestUrl,
            onKeywordChange: this.onKeywordChange,
            onMenu: this.onMenu,
            onToggleSearch: this.onToggleSearch,
            onSearch: this.onSearch
          })
        }
      }
      .width('100%')
      .height('100%')

      if (this.isLoadingMore) {
        Row() {
          LoadingProgress().width(20).height(20).color('#9BB8CB')
          Text(uiText('Loading...')).fontSize(12).fontColor('#9BB8CB').margin({ left: 6 })
        }
        .width('100%')
        .height(36)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#F3F5F7')
      }

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
        .margin({ right: 18, bottom: 18 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F3F5F7')
  }
}

@Component
export struct FloatingToolbar {
  visible: boolean = true;
  barHeight: number = 62;
  @BuilderParam content: () => void = this.EmptyContent;

  @Builder
  private EmptyContent() {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .translate({ y: this.visible ? 0 : -this.barHeight })
    .animation({ duration: 180, curve: Curve.EaseOut })
  }
}

@Component
export struct SearchBarCard {
  @Prop keyword: string = '';
  @Prop title: string = '';
  @Prop searchActive: boolean = false;
  @Prop filterActive: boolean = false;
  @Prop requestUrl: string = '';
  onKeywordChange: (value: string) => void = () => {};
  onMenu: () => void = () => {};
  onToggleSearch: () => void = () => {};
  onSearch: () => void = () => {};

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.open_sidebar'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(38)
        .height(38)
        .backgroundColor('rgba(255,255,255,0.15)')
        .flexShrink(0)
        .onClick(() => {
          this.onMenu();
        })

        Stack({ alignContent: Alignment.BottomStart }) {
          TextInput({ text: this.keyword, placeholder: this.title.length === 0 ? uiText('Search galleries') : uiText(this.title) })
            .height(38)
            .width('100%')
            .backgroundColor(themeSurfaceColor())
            .borderRadius(19)
            .placeholderColor('rgba(47,111,143,0.5)')
            .fontColor('#17202A')
            .caretColor(APP_THEME_COLOR)
            .padding({ left: 16, right: 16 })
            .onChange((value: string) => {
              this.onKeywordChange(value);
            })
          if (this.filterActive) {
            Text(uiText('Filter mode'))
              .fontSize(9)
              .fontColor(Color.White)
              .backgroundColor('rgba(255,255,255,0.3)')
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .borderRadius(4)
              .margin({ left: 10, bottom: 6 })
          }
        }
        .height(38)
        .layoutWeight(1)
        .margin({ left: 10 })

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(38)
        .height(38)
        .backgroundColor('rgba(255,255,255,0.15)')
        .flexShrink(0)
        .margin({ left: 10 })
        .onClick(() => {
          this.onSearch();
        })
      }
      .width('100%')
      .height(62)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)

    }
    .width('100%')
    .backgroundColor(APP_THEME_COLOR)
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

  build() {
    Row() {
      GalleryThumb({
        url: this.gallery.thumb === undefined ? '' : this.gallery.thumb,
        widthValue: galleryThumbWidth(),
        heightValue: galleryThumbHeight()
      })

      Column() {
        Text(galleryDisplayTitle(this.gallery))
          .fontSize(galleryListMode() === 'Thumb' ? 14 : 15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#17202A')
          .maxLines(galleryListMode() === 'Extended' ? 3 : 2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (galleryListMode() !== 'Thumb') {
          Text(this.gallery.uploader === undefined || this.gallery.uploader.length === 0 ? uiText('unknown uploader') :
            this.gallery.uploader)
            .fontSize(12)
            .fontColor('#667085')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 5 })
        }

        Blank()

        Row() {
          CategoryBadge({ category: this.gallery.category })
          Blank()
          if (showGalleryPages()) {
            Text(this.gallery.pages.toString() + 'p')
              .fontSize(12)
              .fontColor('#667085')
          }
          Text(this.gallery.posted === undefined ? '' : this.gallery.posted)
            .fontSize(12)
            .fontColor('#98A2B3')
            .margin({ left: 8 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        if (galleryListMode() !== 'Thumb') {
          Rating({ rating: this.gallery.rating, indicator: true })
            .stars(5)
            .stepSize(0.5)
            .height(12)
            .width(60)
            .margin({ top: 2 })
        }

        if (galleryListMode() === 'Extended' && this.gallery.simpleTags !== undefined && this.gallery.simpleTags.length > 0) {
          Text(galleryTagPreview(this.gallery))
            .fontSize(11)
            .fontColor('#40566F')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 6 })
        }
      }
      .height(galleryRowHeight())
      .layoutWeight(1)
      .margin({ left: 10 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(8)
    .backgroundColor(Color.White)
    .borderRadius(6)
  }
}

@Component
export struct GalleryThumb {
  url: string = '';
  widthValue: number = 86;
  heightValue: number = 118;

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
        .borderRadius(4)

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
          .borderRadius(4)
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
      .fontSize(11)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
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
