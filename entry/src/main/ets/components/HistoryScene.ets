import { pasteboard } from '@kit.BasicServicesKit';
import { GalleryCategory, GalleryDetail, GalleryInfo, GalleryPage, GalleryPreview, GalleryRoute, GallerySite } from '../model/GalleryModels';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { EhHttpClient, GalleryDetailLoadResult, GalleryPageLoadResult, RateGalleryResult, ToggleFavoriteResult } from '../services/EhHttpClient';
import { DEFAULT_ADVANCE_SEARCH, EhUrl, ListMode } from '../services/EhUrl';
import { galleryPageCache } from '../services/GalleryPageCache';
import { DetailPreviewPager, mergeGalleryPreviewSets, seedPreviewMap } from '../services/GalleryPreviewLoader';
import { createReaderSessionState, readerSessionStore } from '../services/ReaderSessionStore';
import { applyAppChromeImmersiveMode, enterEmbeddedReaderFullscreen, getMainWindow } from '../services/EhWindowImmersive';
import { LANGUAGE_REVISION_KEY, nextFloatingToolbarOffset } from '../shared/EhShared';
import { themeOnPrimaryText, themeOnPrimaryDangerBackground, themePageBackground, themeShadowColor } from '../shared/EhTheme';
import { ArrayDataSource } from '../shared/ListDataSource';
import { STATUS_BAR_HEIGHT_KEY, uiText, setActiveBackHandler, createDetailFromGallery, createEmptyDetail, createEmptyPage, cloneGalleryInfos, cloneGalleryDetail, cloneGalleryPage, createReaderLoadingPage, getAbilityContext, saveGalleryToHistory, saveGalleryReadPosition, readerStartIndex, downloadButtonText, toggleGalleryDownload, currentGallerySite, readerPageReferer, cacheReaderImageForPage, readerPreloadCount, galleryListMode, galleryThumbWidth } from '../shared/EhShared';
import { GalleryDetailOverlayScene, GalleryListRow, GalleryListScene, GalleryThumbCard, PlaceholderScene, ReaderPageState, ReaderScene } from './GalleryScenes';
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
export struct HistoryScene {
  private client: EhHttpClient = new EhHttpClient();
  onMenu: () => void = () => {};

  @State histories: GalleryInfo[] = [];
  @State statusText: string = 'Loading history...';
  @State showDetail: boolean = false;
  @State showReader: boolean = false;
  @State showComments: boolean = false;
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = 'Tap a history item to load detail';
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
  @State showTagSearch: boolean = false;
  @State tagSearchKeyword: string = '';
  @State selectedHistoryGids: string = '';
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  @State historyContentWidth: number = 0;
  private historyScroller: Scroller = new Scroller();
  private historyScrollOffset: number = 0;
  private detailScrollOffset: number = 0;
  private toolbarRestoring: boolean = false;
  private readerPreviewMap: Map<number, GalleryPreview> = new Map();
  private readerPreviewPageRequests: Map<number, Promise<GalleryPreview | null>> = new Map();
  private readerPreviewPageSize: number = 0;
  private detailPreviewPager: DetailPreviewPager = new DetailPreviewPager();

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    this.syncHistoryContentWidthFromWindow();
    setActiveBackHandler(() => this.handleSystemBack());
    this.loadHistory();
    setTimeout(() => {
      this.syncHistoryContentWidthFromWindow();
    }, 0);
  }

  aboutToDisappear(): void {
    setActiveBackHandler(null);
  }

  private handleSystemBack(): boolean {
    if (this.historySelectionCount() > 0) {
      this.clearHistorySelection();
      return true;
    }
    if (this.showTagSearch) { this.closeTagSearch(); return true; }
    if (this.showReader) { this.closeReader(); return true; }
    if (this.showComments) { this.closeComments(); return true; }
    if (this.showDetail) { this.closeDetail(); return true; }
    return false;
  }

  private clearHistorySelection(): void {
    this.selectedHistoryGids = '';
  }

  private openTagSearch(namespace: string, tag: string): void {
    const keyword = this.buildTagSearchKeyword(namespace, tag);
    if (keyword.length === 0) {
      return;
    }
    this.tagSearchKeyword = keyword;
    this.showTagSearch = true;
  }

  private closeTagSearch(): void {
    this.showTagSearch = false;
    setTimeout(() => {
      setActiveBackHandler(() => this.handleSystemBack());
    }, 0);
  }

  private buildTagSearchKeyword(namespace: string, tag: string): string {
    const trimmedNamespace = namespace.trim();
    const trimmedTag = tag.trim();
    if (trimmedNamespace.length === 0 || trimmedTag.length === 0) {
      return '';
    }
    const tagQuery = trimmedTag.indexOf(' ') >= 0 ? '"' + trimmedTag.replace(/"/g, '\\"') + '"' : trimmedTag;
    return trimmedNamespace + ':' + tagQuery;
  }

  private loadHistory(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.histories = cloneGalleryInfos(ehHistoryStore.getItems());
      this.statusText = this.histories.length.toString() + ' local history items';
      this.renderVersion++;
      return;
    }

    ehHistoryStore.load(context).then(() => {
      this.histories = cloneGalleryInfos(ehHistoryStore.getItems());
      this.statusText = this.histories.length.toString() + ' history items';
      this.renderVersion++;
    }).catch((error: Error) => {
      this.statusText = 'History load failed: ' + error.message;
      this.renderVersion++;
    });
  }


  private selectedKey(gid: number): string {
    return '|' + gid.toString() + '|';
  }

  private historySelectionCount(): number {
    if (this.selectedHistoryGids.length === 0) {
      return 0;
    }
    const parts = this.selectedHistoryGids.split('|');
    let count = 0;
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].length > 0) {
        count++;
      }
    }
    return count;
  }

  private isHistorySelected(gid: number): boolean {
    return this.selectedHistoryGids.indexOf(this.selectedKey(gid)) >= 0;
  }

  private toggleHistorySelection(gallery: GalleryInfo): void {
    const key = this.selectedKey(gallery.gid);
    if (this.selectedHistoryGids.indexOf(key) >= 0) {
      this.selectedHistoryGids = this.selectedHistoryGids.replace(key, '|');
      if (this.selectedHistoryGids === '|') {
        this.selectedHistoryGids = '';
      }
      return;
    }
    if (this.selectedHistoryGids.length === 0) {
      this.selectedHistoryGids = key;
    } else {
      this.selectedHistoryGids += gallery.gid.toString() + '|';
    }
  }

  private handleHistoryCardTap(gallery: GalleryInfo): void {
    if (this.historySelectionCount() > 0) {
      this.toggleHistorySelection(gallery);
      return;
    }
    this.loadDetail(gallery);
  }

  private deleteSelectedHistory(): void {
    const count = this.historySelectionCount();
    if (count <= 0) {
      this.statusText = 'Long press cards to select history items';
      return;
    }
    for (let i = 0; i < this.histories.length; i++) {
      if (this.isHistorySelected(this.histories[i].gid)) {
        ehHistoryStore.removeGallery(this.histories[i].gid);
      }
    }
    this.histories = cloneGalleryInfos(ehHistoryStore.getItems());
    this.clearHistorySelection();
    this.statusText = 'Removed ' + count.toString() + ' history items';
    this.renderVersion++;
    this.persistHistory();
  }

  private persistHistory(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehHistoryStore.save(context).catch((error: Error) => {
      this.statusText = 'History save failed: ' + error.message;
    });
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

    this.client.loadGalleryDetail(gallery.gid, gallery.token, 0, currentGallerySite(), '').then((result: GalleryDetailLoadResult) => {
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
      this.loadHistory();
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
    this.detailStatus = 'Tap a history item to load detail';
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
    this.loadHistory();
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
    this.openReaderAbility(currentGallerySite());

    const cached = galleryPageCache.get(preview.pageUrl);
    if (cached !== null) {
      this.readerStatus = 'Page loaded from cache';
      this.readerPage = cloneGalleryPage(cached);
      this.setReaderPage(preview.index, cached);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, cached);
      this.preloadReaderPages(preview.index);
      this.persistReaderSession(currentGallerySite());
      return;
    }

    this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
      readerPageReferer(this.detailRequestUrl, this.detail.previewSet, preview.index, currentGallerySite())).then((result: GalleryPageLoadResult) => {
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
      this.persistReaderSession(currentGallerySite());
    }).catch((error: Error) => {
      this.readerStatus = 'Page load failed: ' + error.message;
      this.renderVersion++;
      this.persistReaderSession(currentGallerySite());
    });
  }

  private updateToolbarForScrollFrame(scrollOffset: number): number {
    const offset = normalizeSceneScrollOffset(this.historyScroller.currentOffset().yOffset);
    if (offset <= 4) {
      this.toolbarRestoring = false;
      this.toolbarOffsetY = 0;
      return scrollOffset;
    }
    if (scrollOffset > 0 && this.toolbarVisibleHeight() > 0) {
      const previousOffsetY = this.toolbarOffsetY;
      this.toolbarRestoring = false;
      this.toolbarOffsetY = nextFloatingToolbarOffset(this.toolbarOffsetY, scrollOffset, offset, this.floatingToolbarHeight());
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

  private historyContentTopPadding(): number {
    return this.toolbarVisibleHeight() + 8;
  }

  private historyCardPreferredWidth(): number {
    if (galleryListMode() === 'Thumb') {
      const value = galleryThumbWidth();
      if (value <= 70) {
        return 116;
      }
      if (value >= 104) {
        return 164;
      }
      return 136;
    }
    return 340;
  }

  private historyCardGap(): number {
    return 8;
  }

  private historyContentHorizontalPadding(): number {
    return 8;
  }

  private historyColumnCount(): number {
    return this.historyColumnCountForWidth(this.historyContentWidth);
  }

  private historyColumnCountForWidth(width: number): number {
    const availableWidth = Math.max(0, width - this.historyContentHorizontalPadding() * 2);
    if (availableWidth <= 0 || Number.isNaN(availableWidth)) {
      return 1;
    }
    return Math.max(1, Math.floor((availableWidth + this.historyCardGap()) /
      (this.historyCardPreferredWidth() + this.historyCardGap())));
  }

  private historyCardWidth(): number {
    const availableWidth = Math.max(0, this.historyContentWidth - this.historyContentHorizontalPadding() * 2);
    if (availableWidth <= 0 || Number.isNaN(availableWidth)) {
      return this.historyCardPreferredWidth();
    }
    const columns = this.historyColumnCount();
    return Math.max(this.historyCardMinWidth(), Math.floor((availableWidth - this.historyCardGap() * (columns - 1)) / columns));
  }

  private historyCardMinWidth(): number {
    return galleryListMode() === 'Thumb' ? 104 : 300;
  }

  private updateHistoryContentWidth(width: number): void {
    const normalizedWidth = Math.floor(width);
    if (normalizedWidth <= 0 || Number.isNaN(normalizedWidth) ||
      Math.abs(this.historyContentWidth - normalizedWidth) < 1) {
      return;
    }
    this.historyContentWidth = normalizedWidth;
  }

  private syncHistoryContentWidthFromWindow(): void {
    if (this.historyContentWidth > 0) {
      return;
    }
    const win = getMainWindow();
    if (win === undefined) {
      return;
    }
    try {
      this.updateHistoryContentWidth(this.getUIContext().px2vp(win.getWindowProperties().windowRect.width));
    } catch (_error) {
    }
  }

  private buildHistoryRows(): GalleryInfo[][] {
    const columns = this.historyColumnCount();
    const rows: GalleryInfo[][] = [];
    for (let i = 0; i < this.histories.length; i += columns) {
      rows.push(this.histories.slice(i, i + columns));
    }
    return rows;
  }

  private historyRowKey(row: GalleryInfo[]): string {
    return row.map((gallery: GalleryInfo) => gallery.gid.toString()).join('-');
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
        const result = await this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
          readerPageReferer(this.detailRequestUrl, this.detail.previewSet, nextIndex, currentGallerySite()));
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
      const result = await this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
        readerPageReferer(this.detailRequestUrl, this.detail.previewSet, 0, currentGallerySite()));
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
    this.openReaderAbility(currentGallerySite());
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
      this.detailRequestUrl, '', site, this.readerPreviewIndex));
  }

  private publishReaderSession(site: GallerySite): void {
    readerSessionStore.setSession(createReaderSessionState(this.detail, this.readerPage, this.readerStatus,
      this.detailRequestUrl, '', site, this.readerPreviewIndex));
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
      currentGallerySite(), this.detailRequestUrl).then((result: GalleryDetailLoadResult) => {
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
    const referer = this.detailRequestUrl.length > 0 ? this.detailRequestUrl : '';
    await this.detailPreviewPager.loadNext({
      client: this.client,
      site: currentGallerySite(),
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

  build() {
    if (this.showTagSearch) {
      GalleryListScene({
        sceneTitle: this.tagSearchKeyword.length > 0 ? this.tagSearchKeyword : 'Search',
        listMode: 'Search',
        sourceRoute: GalleryRoute.Home,
        initialKeyword: this.tagSearchKeyword,
        initialSearchMode: ListMode.Tag,
        initialSearchCategory: GalleryCategory.None,
        initialAdvancedSearchEnabled: false,
        initialAdvanceSearch: DEFAULT_ADVANCE_SEARCH,
        initialSearchSubmitted: true,
        isSearchResultScene: true,
        onBack: () => {
          this.closeTagSearch();
        }
      })
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
      FloatingToolbarHost({
        kind: 'title',
        title: 'History',
        requestUrl: '',
        showClear: false,
        canClear: false,
        showRefreshButton: false,
        toolbarOffsetY: this.toolbarOffsetY,
        toolbarHeight: 56,
        onMenu: this.onMenu,
        onRefresh: () => {},
        onClear: () => {}
      }) {
        Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          List({ space: 8, scroller: this.historyScroller }) {
            if (this.histories.length === 0) {
              ListItem() {
                PlaceholderScene({
                  title: 'History',
                  detail: 'Viewed gallery details will appear here. Open a gallery from Homepage, Favorites or Top Lists to add it.'
                })
                  .height('100%')
              }
              .reuseId('history-empty')
            } else {
              LazyForEach(new ArrayDataSource<GalleryInfo[]>(this.buildHistoryRows()), (row: GalleryInfo[]) => {
                ListItem() {
                  Row() {
                    ForEach(row, (gallery: GalleryInfo, colIndex: number) => {
                      if (galleryListMode() === 'Thumb') {
                        GalleryThumbCard({ gallery: gallery, selected: this.isHistorySelected(gallery.gid) })
                          .width(this.historyCardWidth())
                          .margin({ right: colIndex < row.length - 1 ? this.historyCardGap() : 0 })
                          .animation({ duration: 220, curve: Curve.EaseOut })
                          .onClick(() => {
                            this.handleHistoryCardTap(gallery);
                          })
                          .gesture(LongPressGesture({ repeat: false }).onAction(() => {
                            this.toggleHistorySelection(gallery);
                          }))
                      } else {
                        GalleryListRow({ gallery: gallery, selected: this.isHistorySelected(gallery.gid) })
                          .width(this.historyCardWidth())
                          .margin({ right: colIndex < row.length - 1 ? this.historyCardGap() : 0 })
                          .animation({ duration: 220, curve: Curve.EaseOut })
                          .onClick(() => {
                            this.handleHistoryCardTap(gallery);
                          })
                          .gesture(LongPressGesture({ repeat: false }).onAction(() => {
                            this.toggleHistorySelection(gallery);
                          }))
                      }
                    }, (gallery: GalleryInfo) => gallery.gid.toString())
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.Start)
                  .animation({ duration: 220, curve: Curve.EaseOut })
                }
                .margin({ bottom: this.historyCardGap() })
                .reuseId('history-row')
              }, (row: GalleryInfo[], rowIndex: number) => {
                return this.historyColumnCount().toString() + ':' + rowIndex.toString() + ':' + this.historyRowKey(row);
              })
            }
          }
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false, effectEdge: EffectEdge.START | EffectEdge.END })
            .width('100%')
            .height('100%')
            .cachedCount(4)
            .padding({
              left: this.historyContentHorizontalPadding(),
              right: this.historyContentHorizontalPadding(),
              top: this.historyContentTopPadding(),
              bottom: this.historyCardGap()
            })
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              this.updateHistoryContentWidth(newArea.width as number);
            })
            .onAppear(() => {
              this.syncHistoryContentWidthFromWindow();
              if (this.historyScrollOffset > 0) {
                setTimeout(() => {
                  this.historyScroller.scrollTo({ xOffset: 0, yOffset: this.historyScrollOffset });
                }, 0);
              }
            })
            .onScrollFrameBegin((offset: number, _state: ScrollState) => {
              return { offsetRemain: this.updateToolbarForScrollFrame(offset) };
            })
            .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
              this.historyScrollOffset = normalizeSceneScrollOffset(this.historyScroller.currentOffset().yOffset);
            })
            .onScrollStop(() => {
              const offset = normalizeSceneScrollOffset(this.historyScroller.currentOffset().yOffset);
              this.historyScrollOffset = offset;
            })
        }
        Column() {
          if (this.historySelectionCount() > 0) {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(24)
                .fontColor([themeOnPrimaryText()])
            }
            .width(54)
            .height(54)
            .backgroundColor(themeOnPrimaryDangerBackground())
            .shadow({ radius: 14, color: themeShadowColor(), offsetX: 0, offsetY: 3 })
            .onClick(() => {
              this.deleteSelectedHistory();
            })
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.End)
        .padding({ right: 16, bottom: 24 })
        .hitTestBehavior(HitTestMode.Transparent)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(themePageBackground())
      }
    }
  }
}
