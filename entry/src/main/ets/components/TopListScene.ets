import { pasteboard } from '@kit.BasicServicesKit';
import { GalleryDetail, GalleryPage, GalleryPreview, GalleryRoute, GallerySite, TopListBucket, TopListDetail, TopListInfo, TopListItem, TopListKind } from '../model/GalleryModels';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { EhHttpClient, GalleryDetailLoadResult, GalleryPageLoadResult, RateGalleryResult, ToggleFavoriteResult, TopListLoadResult } from '../services/EhHttpClient';
import { EhUrl, ListMode } from '../services/EhUrl';
import { galleryPageCache } from '../services/GalleryPageCache';
import { DetailPreviewPager, mergeGalleryPreviewSets, seedPreviewMap } from '../services/GalleryPreviewLoader';
import { createReaderSessionState, readerSessionStore } from '../services/ReaderSessionStore';
import { applyAppChromeImmersiveMode, enterEmbeddedReaderFullscreen } from '../services/EhWindowImmersive';
import { LANGUAGE_REVISION_KEY, nextFloatingToolbarOffset } from '../shared/EhShared';
import {
  themeOnPrimaryText,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSurface,
  themeTransparentColor
} from '../shared/EhTheme';
import { STATUS_BAR_HEIGHT_KEY, uiText, setActiveBackHandler, createEmptyDetail, createEmptyPage, createEmptyTopListDetail, createEmptyTopListInfo, createEmptyTopListBucket, createEmptyTopListItem, cloneGalleryDetail, cloneGalleryPage, createReaderLoadingPage, cloneTopListDetail, getAbilityContext, saveGalleryToHistory, saveGalleryReadPosition, readerStartIndex, downloadButtonText, toggleGalleryDownload, readerPageReferer, cacheReaderImageForPage, readerPreloadCount, topListChipColor } from '../shared/EhShared';
import { GalleryDetailOverlayScene, GalleryListScene, GalleryListStateView, ReaderPageState, ReaderScene } from './GalleryScenes';
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
  @State readerPages: ReaderPageState[] = [];
  @State readerPreviewIndex: number = 0;
  @State renderVersion: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @State toolbarOffsetY: number = 0;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  private topListScrollOffset: number = 0;
  private detailScrollOffset: number = 0;
  private toolbarRestoring: boolean = false;
  private readerPreviewMap: Map<number, GalleryPreview> = new Map();
  private readerPreviewPageRequests: Map<number, Promise<GalleryPreview | null>> = new Map();
  private readerPreviewPageSize: number = 0;
  private detailPreviewPager: DetailPreviewPager = new DetailPreviewPager();

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
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
    this.detailPreviewPager.start();
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
    this.openReaderAbility(GallerySite.E);

    const cached = galleryPageCache.get(preview.pageUrl);
    if (cached !== null) {
      this.readerStatus = 'Page loaded from cache';
      this.readerPage = cloneGalleryPage(cached);
      this.setReaderPage(preview.index, cached);
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
        const result = await this.client.loadGalleryPage(preview.pageUrl, GallerySite.E,
          readerPageReferer(this.detailRequestUrl, this.detail.previewSet, nextIndex, GallerySite.E));
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
      const result = await this.client.loadGalleryPage(preview.pageUrl, GallerySite.E,
        readerPageReferer(this.detailRequestUrl, this.detail.previewSet, 0, GallerySite.E));
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
      enterEmbeddedReaderFullscreen();
      this.showReader = true;
      return;
    }
    this.showReader = false;
    const context = getAbilityContext();
    if (context === undefined) {
      this.readerStatus = 'Reader launch failed: Ability context is not ready';
      this.renderVersion++;
      this.persistReaderSession(site);
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
    this.readerPreviewPageSize = seedPreviewMap(this.readerPreviewMap, previews, this.readerPreviewPageSize);
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
    const merged = mergeGalleryPreviewSets(this.detail, loaded, this.readerPreviewMap, this.readerPreviewPageSize);
    this.detail = merged.detail;
    this.readerPreviewPageSize = merged.previewPageSize;
    this.renderVersion++;
  }

  private async loadNextDetailPreviewPage(): Promise<void> {
    const referer = this.detailRequestUrl.length > 0 ? this.detailRequestUrl : this.requestUrl;
    await this.detailPreviewPager.loadNext({
      client: this.client,
      site: GallerySite.E,
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

  private currentInfo(): TopListInfo {
    if (this.topList.lists.length === 0 || this.selectedIndex < 0 || this.selectedIndex >= this.topList.lists.length) {
      return createEmptyTopListInfo();
    }
    return this.topList.lists[this.selectedIndex];
  }

  private updateToolbarForScroll(contentOffset: number, scrollOffset: number): void {
    if (scrollOffset === 0) {
      return;
    }
    if (contentOffset <= 4) {
      this.toolbarRestoring = false;
      this.toolbarOffsetY = 0;
      return;
    }
    if (scrollOffset > 0 && this.toolbarVisibleHeight() > 0) {
      this.toolbarRestoring = false;
      this.toolbarOffsetY = nextFloatingToolbarOffset(this.toolbarOffsetY, scrollOffset, contentOffset, this.floatingToolbarHeight());
      return;
    }
    if (scrollOffset < 0 && this.toolbarVisibleHeight() <= 1) {
      this.restoreToolbarOnReverseScroll();
    }
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

  build() {
    if (this.showReader) {
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
              .fontColor([themeOnPrimaryText()])
          }
          .width(36)
          .height(36)
          .backgroundColor(themePrimaryColor())
          .onClick(() => {
            this.closeGalleryList();
          })
          Text(uiText(this.galleryListTitle) + ' / ' + uiText(this.galleryListModeLabel))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(themePrimaryText())
            .margin({ left: 12 })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: this.statusBarVp() + 10, bottom: 8 })
        .backgroundColor(themeSurface())

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
                  this.updateToolbarForScroll(offset, scrollOffset);
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
        .backgroundColor(themePageBackground())
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
            .fontColor(index === this.selectedIndex ? themeOnPrimaryText() : themePrimaryColor())
            .backgroundColor(index === this.selectedIndex ? themePrimaryColor() : themeTransparentColor())
            .border({ width: 1, color: index === this.selectedIndex ? themePrimaryColor() : themeSecondaryText() })
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
        }, (bucket: TopListBucket) => this.selectedIndex.toString() + ':' + bucket.title)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 12, right: 12, top: this.contentTopPadding(), bottom: 0 })
      .backgroundColor(themePageBackground())
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false, effectEdge: EffectEdge.START })
      .onAppear(() => {
        if (this.initialScrollOffset > 0) {
          this.boardScroller.scrollTo({ xOffset: 0, yOffset: this.initialScrollOffset });
        }
      })
      .onScrollFrameBegin((offset: number, _state: ScrollState) => {
        this.onScrollUpdate(normalizeSceneScrollOffset(this.boardScroller.currentOffset().yOffset), offset);
        return { offsetRemain: offset };
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
