import { common } from '@kit.AbilityKit';
import { GalleryDetail, GalleryPage, GalleryPreview, GallerySite } from '../model/GalleryModels';
import { ReaderPageTranslation, cloneReaderPageTranslation } from '../model/ReaderTranslationModels';
import { READER_ABILITY_CONTEXT_KEY } from '../entryability/ReaderAbility';
import { EhHttpClient, GalleryDetailLoadResult, GalleryPageLoadResult } from '../services/EhHttpClient';
import { ehDownloadFileStore } from '../services/EhDownloadFileStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { galleryPageCache } from '../services/GalleryPageCache';
import {
  createReaderSessionState,
  readerSessionStore,
  ReaderSessionPageState,
  READER_SESSION_REVISION_KEY
} from '../services/ReaderSessionStore';
import { readerComicTranslationService } from '../services/ReaderComicTranslationService';
import { cancelQueuedReaderImageRequests, IMAGE_DOWNLOAD_PRIORITY_READER } from '../services/ReaderImageCache';
import {
  cacheReaderImageForPage,
  cloneGalleryDetail,
  cloneGalleryPage,
  cloneGalleryPreviews,
  createEmptyDetail,
  createEmptyPage,
  createReaderLoadingPage,
  downloadThreadLimit,
  getAbilityContext,
  readerPageReferer,
  readerPreloadCount,
  readerStartIndex,
  readerStartIndexAsync,
  saveGalleryReadPosition,
  setReaderActiveBackHandler
} from '../shared/EhShared';
import { ReaderPageState, ReaderScene } from './ReaderScenes';

const READER_IMAGE_SERVER_ATTEMPT_LIMIT: number = 5;

@Component
export struct ReaderSessionScene {
  private client: EhHttpClient = new EhHttpClient();
  restoreAppChromeOnExit: boolean = false;
  onBack: () => void = () => {};

  @State detail: GalleryDetail = createEmptyDetail();
  @State page: GalleryPage = createEmptyPage();
  @State statusText: string = 'Reader is ready';
  @State detailRequestUrl: string = '';
  @State listRequestUrl: string = '';
  @State site: GallerySite = GallerySite.E;
  @State pageIndex: number = 0;
  @State renderVersion: number = 0;
  @State readerPages: ReaderPageState[] = [];
  @State readerTranslations: ReaderPageTranslation[] = [];
  @State comicTranslationActive: boolean = false;
  @State comicTranslationNotice: string = '';
  @State comicTranslationNoticeRevision: number = 0;
  @StorageProp(READER_SESSION_REVISION_KEY) @Watch('onSessionRevisionChange') sessionRevision: number = 0;
  private loadedSessionRevision: number = -1;
  private readerPreviewMap: Map<number, GalleryPreview> = new Map();
  private readerPreviewPageRequests: Map<number, Promise<GalleryPreview | null>> = new Map();
  private readerPageLoadRequests: Map<string, Promise<GalleryPageLoadResult>> = new Map();
  private readerImageRecoveryRequests: Map<string, Promise<void>> = new Map();
  private readerPreviewPageSize: number = 0;
  private readerTranslationLoads: string[] = [];
  private readerTranslationLoadPriorities: Map<string, number> = new Map();
  private readerTranslationRefreshing: number[] = [];
  private readerTranslationScope: string = '';
  private readerPreloadRevision: number = 0;
  private readerSceneActive: boolean = false;
  private readerSettingsReady: boolean = false;

  aboutToAppear(): void {
    this.readerSceneActive = true;
    if (!this.restoreAppChromeOnExit) {
      setReaderActiveBackHandler(() => this.handleSystemBack());
    }
    const context = this.readerContext();
    if (context === undefined) {
      this.readerSettingsReady = true;
      this.loadCurrentSession();
      return;
    }
    ehSettingsStore.ensureLoaded(context).finally(() => {
      if (!this.readerSceneActive) {
        return;
      }
      this.readerSettingsReady = true;
      this.loadCurrentSession();
    });
  }

  onSessionRevisionChange(): void {
    if (!this.readerSettingsReady || this.sessionRevision === this.loadedSessionRevision) {
      return;
    }
    this.loadCurrentSession();
  }

  private loadCurrentSession(): void {
    this.readerPreloadRevision++;
    this.renewReaderTranslationScope();
    const session = readerSessionStore.getSession();
    if (session === null || session.detail.gid <= 0) {
      this.statusText = 'Reader session is empty';
      this.renderVersion++;
      return;
    }
    this.loadedSessionRevision = this.sessionRevision;
    this.readerPreviewMap.clear();
    this.readerPreviewPageRequests.clear();
    this.readerPageLoadRequests.clear();
    this.readerImageRecoveryRequests.clear();
    this.readerPreviewPageSize = 0;
    this.readerTranslationLoads = [];
    this.readerTranslationLoadPriorities.clear();
    this.readerTranslationRefreshing = [];
    this.readerTranslations = [];
    this.comicTranslationActive = false;
    this.detail = cloneGalleryDetail(session.detail);
    this.statusText = session.statusText;
    this.detailRequestUrl = session.detailRequestUrl;
    this.listRequestUrl = session.listRequestUrl;
    this.site = session.site;
    const usesSavedPosition = session.pageIndex < 0;
    this.pageIndex = usesSavedPosition ? readerStartIndex(this.detail) : session.pageIndex;
    this.seedReaderPreviewCache(this.detail.previewSet);
    this.readerPages = this.cloneSessionReaderPages(session.pages);
    const restoredPage = this.restoredPageForIndex(session.page, this.pageIndex);
    this.page = restoredPage === null ? createEmptyPage() : restoredPage;
    if (this.page.imageUrl.length > 0 || this.page.pageUrl.length > 0 ||
      (this.page.cachedImagePath !== undefined && this.page.cachedImagePath.length > 0)) {
      this.setReaderPage(this.pageIndex, this.page);
    }
    this.renderVersion++;
    if (usesSavedPosition) {
      readerStartIndexAsync(this.detail).then((index: number) => {
        if (index !== this.pageIndex) {
          this.pageIndex = index;
          this.page = createEmptyPage();
          this.renderVersion++;
        }
        this.loadReaderPageByIndex(index);
      }).catch(() => {
        this.loadReaderPageByIndex(this.pageIndex);
      });
      return;
    }
    if (this.page.imageUrl.length === 0 &&
      (this.page.cachedImagePath === undefined || this.page.cachedImagePath.length === 0)) {
      this.loadReaderPageByIndex(this.pageIndex);
    } else {
      this.cacheReaderImage(this.pageIndex, this.page);
      this.preloadReaderPages(this.pageIndex);
    }
  }

  aboutToDisappear(): void {
    this.readerSceneActive = false;
    this.readerPreloadRevision++;
    cancelQueuedReaderImageRequests();
    this.cancelReaderTranslationScope();
    this.persistSession();
    if (!this.restoreAppChromeOnExit) {
      setReaderActiveBackHandler(null);
    }
  }

  private handleSystemBack(): boolean {
    this.closeReader();
    return true;
  }

  private persistSession(): void {
    readerSessionStore.updateSession(createReaderSessionState(this.detail, this.page, this.statusText,
      this.detailRequestUrl, this.listRequestUrl, this.site, this.pageIndex, this.readerPages));
  }

  private closeReader(): void {
    if (this.restoreAppChromeOnExit) {
      this.onBack();
      return;
    }
    const context = AppStorage.get<common.UIAbilityContext>(READER_ABILITY_CONTEXT_KEY);
    if (context !== undefined) {
      context.terminateSelf().catch(() => {});
    }
  }

  private readerContext(): common.UIAbilityContext | undefined {
    const readerContext = AppStorage.get<common.UIAbilityContext>(READER_ABILITY_CONTEXT_KEY);
    if (readerContext !== undefined) {
      return readerContext;
    }
    return getAbilityContext();
  }

  private loadReaderPage(preview: GalleryPreview): void {
    this.readerPreviewMap.set(preview.index, preview);
    this.pageIndex = preview.index;
    saveGalleryReadPosition(this.detail.gid, preview.index, this.detail);
    this.statusText = 'Loading page ' + (preview.index + 1).toString() + '...';
    this.page = createReaderLoadingPage(preview.pageUrl);
    this.setReaderPage(preview.index, this.page);
    this.renderVersion++;
    if (this.comicTranslationActive) {
      this.requestReaderTranslationWindow(false);
    }
    this.preloadReaderPages(preview.index);

    if (this.tryUseDownloadedPage(preview.index, preview)) {
      this.persistSession();
      return;
    }

    if (preview.pageUrl.length === 0 || preview.pageUrl.indexOf('ehviewer://') === 0) {
      this.statusText = 'Preview has no page URL';
      this.renderVersion++;
      this.persistSession();
      return;
    }

    const cached = galleryPageCache.get(preview.pageUrl);
    if (cached !== null) {
      this.statusText = 'Page loaded from cache';
      this.page = cloneGalleryPage(cached);
      this.setReaderPage(preview.index, cached);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, cached);
      this.persistSession();
      return;
    }

    this.requestReaderPage(preview)
      .then((result: GalleryPageLoadResult) => {
        if (!result.ok || result.page === null) {
          this.statusText = 'Page load failed: ' + result.message;
          this.renderVersion++;
          this.persistSession();
          return;
        }
        const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
        galleryPageCache.put(cacheUrl, result.page);
        galleryPageCache.put(preview.pageUrl, result.page);
        if (this.pageIndex !== preview.index) {
          this.setReaderPage(preview.index, result.page);
          this.cacheReaderImage(preview.index, result.page);
          return;
        }
        this.statusText = 'Page loaded';
        this.page = cloneGalleryPage(result.page);
        this.setReaderPage(preview.index, result.page);
        this.renderVersion++;
        this.cacheReaderImage(preview.index, result.page);
        this.persistSession();
      }).catch((error: Error) => {
        this.statusText = 'Page load failed: ' + error.message;
        this.renderVersion++;
        this.persistSession();
      });
  }

  private cacheReaderImage(index: number, page: GalleryPage): Promise<void> {
    if (!this.readerSceneActive) {
      return Promise.resolve();
    }
    const requestKey = index.toString() + ':' + page.pageUrl + ':' + page.imageUrl;
    const pending = this.readerImageRecoveryRequests.get(requestKey);
    if (pending !== undefined) {
      return pending;
    }
    const request = this.cacheReaderImageWithServerFallback(index, page);
    this.readerImageRecoveryRequests.set(requestKey, request);
    request.then(() => {
      if (this.readerImageRecoveryRequests.get(requestKey) === request) {
        this.readerImageRecoveryRequests.delete(requestKey);
      }
    }).catch(() => {
      if (this.readerImageRecoveryRequests.get(requestKey) === request) {
        this.readerImageRecoveryRequests.delete(requestKey);
      }
    });
    return request;
  }

  private async cacheReaderImageWithServerFallback(index: number, page: GalleryPage): Promise<void> {
    const galleryId = this.detail.gid;
    const preview = this.readerPreviewMap.get(index);
    const previewPageUrl = preview !== undefined && preview.pageUrl.length > 0 ? preview.pageUrl : page.pageUrl;
    const referer = readerPageReferer(this.detailRequestUrl, this.detail.previewSet, index, this.site);
    const usedSkipKeys: string[] = [];
    let current = cloneGalleryPage(page);
    let lastError = '';

    for (let attempt = 0; attempt < READER_IMAGE_SERVER_ATTEMPT_LIMIT; attempt++) {
      let ready = false;
      lastError = '';
      await cacheReaderImageForPage(current, (cachedPage: GalleryPage) => {
        ready = true;
        this.applyCachedReaderPage(index, cachedPage, page.pageUrl);
      }, this.detail, index, this.readerContext(), (message: string) => {
        lastError = message;
      }, IMAGE_DOWNLOAD_PRIORITY_READER, { retryLimit: 1 });
      if (ready || !this.readerSceneActive || this.detail.gid !== galleryId) {
        return;
      }

      const skipKey = current.skipHathKey;
      if (skipKey.length === 0 || usedSkipKeys.indexOf(skipKey) >= 0 ||
        attempt >= READER_IMAGE_SERVER_ATTEMPT_LIMIT - 1) {
        break;
      }
      usedSkipKeys.push(skipKey);
      const reloadUrl = current.pageUrl.length > 0 ? current.pageUrl : previewPageUrl;
      if (reloadUrl.length === 0) {
        break;
      }
      const result = await this.client.skipHathAndReloadPage(reloadUrl, skipKey, this.site, referer);
      if (!this.readerSceneActive || this.detail.gid !== galleryId || !result.ok || result.page === null) {
        if (!result.ok && result.message.length > 0) {
          lastError = result.message;
        }
        break;
      }
      current = cloneGalleryPage(result.page);
      const cacheUrl = current.pageUrl.length > 0 ? current.pageUrl : previewPageUrl;
      galleryPageCache.put(cacheUrl, current);
      galleryPageCache.put(previewPageUrl, current);
      this.setReaderPage(index, current);
      if (this.pageIndex === index) {
        this.page = cloneGalleryPage(current);
        this.statusText = 'Switching image server...';
        this.renderVersion++;
        this.persistSession();
      }
    }

    if (this.readerSceneActive && this.pageIndex === index && this.detail.gid === galleryId) {
      this.statusText = 'Page load failed: ' + (lastError.length > 0 ? lastError : 'Image download failed');
      this.renderVersion++;
      this.persistSession();
    }
  }

  private applyCachedReaderPage(index: number, cachedPage: GalleryPage, fallbackPageUrl: string): void {
    galleryPageCache.put(cachedPage.pageUrl.length > 0 ? cachedPage.pageUrl : fallbackPageUrl, cachedPage);
    this.setReaderPage(index, cachedPage);
    if (this.pageIndex === index) {
      this.page = cloneGalleryPage(cachedPage);
      this.statusText = 'Page loaded from local cache';
      this.renderVersion++;
      this.persistSession();
    }
  }

  private tryUseDownloadedPage(index: number, preview: GalleryPreview): boolean {
    const context = this.readerContext();
    if (context === undefined) {
      return false;
    }
    const path = ehDownloadFileStore.findPageImage(context, this.detail, index);
    if (path.length <= 0) {
      return false;
    }
    const page: GalleryPage = {
      pageUrl: preview.pageUrl,
      imageUrl: preview.imageUrl,
      skipHathKey: '',
      originImageUrl: '',
      showKey: '',
      cachedImagePath: path
    };
    galleryPageCache.put(preview.pageUrl, page);
    this.setReaderPage(index, page);
    if (this.pageIndex === index) {
      this.statusText = 'Page loaded from downloads';
      this.page = cloneGalleryPage(page);
      this.renderVersion++;
    }
    return true;
  }

  private requestReaderPage(preview: GalleryPreview): Promise<GalleryPageLoadResult> {
    const key = preview.pageUrl;
    const pending = this.readerPageLoadRequests.get(key);
    if (pending !== undefined) {
      return pending;
    }
    const request = this.client.loadGalleryPage(preview.pageUrl, this.site,
      readerPageReferer(this.detailRequestUrl, this.detail.previewSet, preview.index, this.site));
    this.readerPageLoadRequests.set(key, request);
    request.then(() => {
      if (this.readerPageLoadRequests.get(key) === request) {
        this.readerPageLoadRequests.delete(key);
      }
    }).catch(() => {
      if (this.readerPageLoadRequests.get(key) === request) {
        this.readerPageLoadRequests.delete(key);
      }
    });
    return request;
  }

  private async preloadReaderPage(index: number, galleryId: number): Promise<void> {
    const preview = await this.ensureReaderPreview(index, true);
    if (!this.readerSceneActive || galleryId !== this.detail.gid || preview === null || preview.pageUrl.length === 0) {
      return;
    }
    if (this.tryUseDownloadedPage(index, preview)) {
      return;
    }
    const cached = galleryPageCache.get(preview.pageUrl);
    if (cached !== null) {
      this.setReaderPage(index, cached);
      await this.cacheReaderImage(index, cached);
      return;
    }
    try {
      const result = await this.requestReaderPage(preview);
      if (!this.readerSceneActive || galleryId !== this.detail.gid || !result.ok || result.page === null) {
        return;
      }
      const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
      galleryPageCache.put(cacheUrl, result.page);
      galleryPageCache.put(preview.pageUrl, result.page);
      this.setReaderPage(index, result.page);
      await this.cacheReaderImage(index, result.page);
    } catch (error) {
    }
  }

  private async preloadReaderPages(index: number): Promise<void> {
    const revision = ++this.readerPreloadRevision;
    const configuredCount = readerPreloadCount();
    const dualPageCount = ehSettingsStore.getValue('adaptive_dual_page', 'Off') === 'On' ?
      Math.max(1, configuredCount) : configuredCount;
    const forwardCount = this.comicTranslationActive ? Math.max(2, dualPageCount) : dualPageCount;
    if (forwardCount <= 0) {
      return;
    }
    const galleryId = this.detail.gid;
    const parallelCount = downloadThreadLimit();
    for (let batchStart = 1; batchStart <= forwardCount; batchStart += parallelCount) {
      if (revision !== this.readerPreloadRevision || galleryId !== this.detail.gid) {
        return;
      }
      const batch: Promise<void>[] = [];
      const batchEnd = Math.min(forwardCount, batchStart + parallelCount - 1);
      for (let offset = batchStart; offset <= batchEnd; offset++) {
        const nextIndex = index + offset;
        if (nextIndex < this.readerTotalPages()) {
          batch.push(this.preloadReaderPage(nextIndex, galleryId));
        }
      }
      await Promise.all(batch);
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
    this.pageIndex = index;
    saveGalleryReadPosition(this.detail.gid, index, this.detail);
    this.statusText = 'Resolving page ' + (index + 1).toString() + '...';
    this.page = createReaderLoadingPage('');
    this.setReaderPage(index, this.page);
    this.renderVersion++;
    if (this.comicTranslationActive) {
      this.requestReaderTranslationWindow(false);
    }
    this.ensureReaderPreview(index, false).then((resolved: GalleryPreview | null) => {
      if (resolved === null) {
        if (this.pageIndex === index) {
          this.statusText = 'Page URL is unavailable';
          this.renderVersion++;
          this.persistSession();
        }
        return;
      }
      if (this.pageIndex === index) {
        this.loadReaderPage(resolved);
      }
    }).catch((error: Error) => {
      if (this.pageIndex === index) {
        this.statusText = 'Page URL load failed: ' + error.message;
        this.renderVersion++;
        this.persistSession();
      }
    });
  }

  private seedReaderPreviewCache(previews: GalleryPreview[]): void {
    if (previews.length > 0 && this.readerPreviewPageSize <= 0) {
      this.readerPreviewPageSize = previews.length;
    }
    for (let i = 0; i < previews.length; i++) {
      this.readerPreviewMap.set(previews[i].index, previews[i]);
    }
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

  private isPageForIndex(page: GalleryPage, index: number): boolean {
    if (page.pageUrl.length === 0) {
      return false;
    }
    const preview = this.readerPreviewForIndex(index);
    return preview !== null && preview.pageUrl === page.pageUrl;
  }

  private restoredPageForIndex(sessionPage: GalleryPage, index: number): GalleryPage | null {
    if (this.isPageForIndex(sessionPage, index)) {
      return cloneGalleryPage(sessionPage);
    }
    for (let i = 0; i < this.readerPages.length; i++) {
      if (this.readerPages[i].index === index) {
        return cloneGalleryPage(this.readerPages[i].page);
      }
    }
    return null;
  }

  private cloneSessionReaderPages(pages: ReaderSessionPageState[]): ReaderPageState[] {
    const next: ReaderPageState[] = [];
    for (let i = 0; i < pages.length; i++) {
      next.push({
        index: pages[i].index,
        page: cloneGalleryPage(pages[i].page)
      });
    }
    return next;
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
    this.queueReaderTranslationIfNeeded(index, page, false);
  }

  private readerPageForTranslation(index: number): GalleryPage | null {
    if (index === this.pageIndex) {
      return this.page;
    }
    for (let i = 0; i < this.readerPages.length; i++) {
      if (this.readerPages[i].index === index) {
        return this.readerPages[i].page;
      }
    }
    return null;
  }

  private readerTranslationImagePath(page: GalleryPage): string {
    if (page.cachedOriginImagePath !== undefined && page.cachedOriginImagePath.length > 0) {
      return page.cachedOriginImagePath.replace(/^file:\/\//, '');
    }
    if (page.cachedImagePath !== undefined && page.cachedImagePath.length > 0) {
      return page.cachedImagePath.replace(/^file:\/\//, '');
    }
    return '';
  }

  private translationForPage(index: number): ReaderPageTranslation | null {
    for (let i = 0; i < this.readerTranslations.length; i++) {
      if (this.readerTranslations[i].pageIndex === index) {
        return this.readerTranslations[i];
      }
    }
    return null;
  }

  private setReaderTranslation(value: ReaderPageTranslation): void {
    const next: ReaderPageTranslation[] = [];
    let replaced = false;
    for (let i = 0; i < this.readerTranslations.length; i++) {
      if (this.readerTranslations[i].pageIndex === value.pageIndex) {
        next.push(cloneReaderPageTranslation(value));
        replaced = true;
      } else {
        next.push(cloneReaderPageTranslation(this.readerTranslations[i]));
      }
    }
    if (!replaced) {
      next.push(cloneReaderPageTranslation(value));
    }
    next.sort((left: ReaderPageTranslation, right: ReaderPageTranslation) => left.pageIndex - right.pageIndex);
    this.readerTranslations = next;
  }

  private setComicTranslationNotice(message: string): void {
    this.comicTranslationNotice = message;
    this.comicTranslationNoticeRevision++;
  }

  private requestReaderTranslationWindow(forceCurrent: boolean = false): void {
    const first = Math.max(0, this.pageIndex - 1);
    const last = Math.min(this.readerTotalPages() - 1, this.pageIndex + 2);
    for (let index = first; index <= last; index++) {
      const page = this.readerPageForTranslation(index);
      if (page !== null) {
        this.queueReaderTranslationIfNeeded(index, page, forceCurrent && index === this.pageIndex);
      }
    }
  }

  private readerTranslationPriority(index: number): number {
    const distance = index - this.pageIndex;
    if (distance === 0) {
      return 4;
    }
    if (distance === 1) {
      return 3;
    }
    if (distance === 2) {
      return 2;
    }
    return 1;
  }

  private queueReaderTranslationIfNeeded(index: number, page: GalleryPage, force: boolean): void {
    if (!this.comicTranslationActive || index < this.pageIndex - 1 || index > this.pageIndex + 2) {
      if (force) {
        this.finishReaderTranslationRefresh(index);
      }
      return;
    }
    if (!force && this.translationForPage(index) !== null) {
      return;
    }
    const context = this.readerContext();
    const scope = this.readerTranslationScope;
    if (context === undefined || scope.length === 0) {
      if (force) {
        this.finishReaderTranslationRefresh(index);
      }
      return;
    }
    const loadKey = index.toString() + ':' + (force ? 'force' : 'normal');
    const priority = this.readerTranslationPriority(index);
    if (this.readerTranslationLoads.indexOf(loadKey) >= 0) {
      const previousPriority = this.readerTranslationLoadPriorities.get(loadKey);
      if (previousPriority === undefined || priority > previousPriority) {
        this.readerTranslationLoadPriorities.set(loadKey, priority);
        readerComicTranslationService.promote(this.readerTranslationScope, index, priority);
      }
      return;
    }
    this.readerTranslationLoads.push(loadKey);
    this.readerTranslationLoadPriorities.set(loadKey, priority);
    const imagePath = this.readerTranslationImagePath(page);
    const load = force ? Promise.resolve<ReaderPageTranslation | null>(null) :
      readerComicTranslationService.loadStored(context, this.detail, index);
    load.then((stored: ReaderPageTranslation | null) => {
      if (scope !== this.readerTranslationScope) {
        return;
      }
      if (stored !== null) {
        if (!force && this.readerTranslationRefreshing.indexOf(index) >= 0) {
          return;
        }
        this.setReaderTranslation(stored);
        return;
      }
      if (imagePath.length === 0) {
        if (force) {
          this.finishReaderTranslationRefresh(index);
        }
        return;
      }
      const requestPriority = this.readerTranslationLoadPriorities.get(loadKey);
      return readerComicTranslationService.request(context, this.detail, index, imagePath,
        requestPriority === undefined ? priority : requestPriority, force, scope)
        .then((translation: ReaderPageTranslation) => {
          if (scope !== this.readerTranslationScope) {
            return;
          }
          if (!force && this.readerTranslationRefreshing.indexOf(index) >= 0) {
            return;
          }
          this.setReaderTranslation(translation);
          if (force) {
            this.finishReaderTranslationRefresh(index);
          }
          if (translation.lines.length === 0 && index === this.pageIndex) {
            this.setComicTranslationNotice('No text was recognized on this page');
          }
        });
    }).catch((_error: Error) => {
      if (scope !== this.readerTranslationScope) {
        return;
      }
      if (force) {
        this.finishReaderTranslationRefresh(index);
      }
      if (index === this.pageIndex) {
        this.setComicTranslationNotice('Comic translation failed');
      }
    }).finally(() => {
      if (scope !== this.readerTranslationScope) {
        return;
      }
      const next: string[] = [];
      for (let i = 0; i < this.readerTranslationLoads.length; i++) {
        if (this.readerTranslationLoads[i] !== loadKey) {
          next.push(this.readerTranslationLoads[i]);
        }
      }
      this.readerTranslationLoads = next;
      this.readerTranslationLoadPriorities.delete(loadKey);
    });
  }

  private renewReaderTranslationScope(): void {
    this.cancelReaderTranslationScope();
    this.readerTranslationScope = readerComicTranslationService.beginScope();
  }

  private cancelReaderTranslationScope(): void {
    if (this.readerTranslationScope.length === 0) {
      return;
    }
    readerComicTranslationService.cancelScope(this.readerTranslationScope);
    this.readerTranslationScope = '';
  }

  private toggleComicTranslation(enabled: boolean): void {
    this.comicTranslationActive = enabled;
    if (!enabled) {
      return;
    }
    this.preloadReaderPages(this.pageIndex);
    this.requestReaderTranslationWindow(false);
  }

  private refreshCurrentComicTranslation(): void {
    this.comicTranslationActive = true;
    const page = this.readerPageForTranslation(this.pageIndex);
    if (page !== null) {
      this.removeReaderTranslation(this.pageIndex);
      if (this.readerTranslationRefreshing.indexOf(this.pageIndex) < 0) {
        this.readerTranslationRefreshing.push(this.pageIndex);
      }
      this.queueReaderTranslationIfNeeded(this.pageIndex, page, true);
    }
  }

  private removeReaderTranslation(index: number): void {
    const next: ReaderPageTranslation[] = [];
    for (let i = 0; i < this.readerTranslations.length; i++) {
      if (this.readerTranslations[i].pageIndex !== index) {
        next.push(cloneReaderPageTranslation(this.readerTranslations[i]));
      }
    }
    this.readerTranslations = next;
  }

  private finishReaderTranslationRefresh(index: number): void {
    const next: number[] = [];
    for (let i = 0; i < this.readerTranslationRefreshing.length; i++) {
      if (this.readerTranslationRefreshing[i] !== index) {
        next.push(this.readerTranslationRefreshing[i]);
      }
    }
    this.readerTranslationRefreshing = next;
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
    const referer = this.detailRequestUrl.length > 0 ? this.detailRequestUrl : this.listRequestUrl;
    const request = this.client.loadGalleryDetail(this.detail.gid, this.detail.token, previewPageIndex,
      this.site, referer).then((result: GalleryDetailLoadResult) => {
      this.readerPreviewPageRequests.delete(previewPageIndex);
      if (!result.ok || result.detail === null) {
        if (!silent) {
          this.statusText = 'Preview page load failed: ' + result.message;
          this.renderVersion++;
        }
        return null;
      }
      this.mergeReaderPreviewSet(result.detail);
      return this.readerPreviewForIndex(index);
    }).catch((error: Error) => {
      this.readerPreviewPageRequests.delete(previewPageIndex);
      if (!silent) {
        this.statusText = 'Preview page load failed: ' + error.message;
        this.renderVersion++;
      }
      return null;
    });
    this.readerPreviewPageRequests.set(previewPageIndex, request);
    return request;
  }

  private mergeReaderPreviewSet(loaded: GalleryDetail): void {
    this.seedReaderPreviewCache(loaded.previewSet);
    const byIndex: Map<number, GalleryPreview> = new Map();
    for (let i = 0; i < this.detail.previewSet.length; i++) {
      byIndex.set(this.detail.previewSet[i].index, this.detail.previewSet[i]);
    }
    for (let i = 0; i < loaded.previewSet.length; i++) {
      byIndex.set(loaded.previewSet[i].index, loaded.previewSet[i]);
    }
    const merged: GalleryPreview[] = Array.from(byIndex.values());
    merged.sort((left: GalleryPreview, right: GalleryPreview) => left.index - right.index);
    const nextDetail = cloneGalleryDetail(this.detail);
    nextDetail.previewSet = cloneGalleryPreviews(merged);
    nextDetail.previewPages = Math.max(nextDetail.previewPages, loaded.previewPages);
    nextDetail.pages = Math.max(nextDetail.pages, loaded.pages);
    this.detail = nextDetail;
    for (let i = 0; i < this.detail.previewSet.length; i++) {
      this.readerPreviewMap.set(this.detail.previewSet[i].index, this.detail.previewSet[i]);
    }
    this.renderVersion++;
    this.persistSession();
  }

  build() {
    ReaderScene({
      renderVersion: this.renderVersion,
      page: this.page,
      readerPages: this.readerPages,
      readerPreviews: this.detail.previewSet,
      galleryId: this.detail.gid,
      statusText: this.statusText,
      pageIndex: this.pageIndex,
      totalPages: this.readerTotalPages(),
      readerTranslations: this.readerTranslations,
      comicTranslationActive: this.comicTranslationActive,
      comicTranslationNotice: this.comicTranslationNotice,
      comicTranslationNoticeRevision: this.comicTranslationNoticeRevision,
      restoreAppChromeOnExit: this.restoreAppChromeOnExit,
      onBack: () => {
        this.closeReader();
      },
      onPrev: () => {
        this.loadReaderPageByIndex(this.pageIndex - 1);
      },
      onNext: () => {
        this.loadReaderPageByIndex(this.pageIndex + 1);
      },
      onJump: (index: number) => {
        this.loadReaderPageByIndex(index);
      },
      onRetry: () => {
        this.loadReaderPageByIndex(this.pageIndex);
      },
      onRefreshPage: (index: number) => {
        this.loadReaderPageByIndex(index);
      },
      onAdaptiveDualPageChange: (enabled: boolean) => {
        if (enabled) {
          this.preloadReaderPages(this.pageIndex);
        }
      },
      onComicTranslationToggle: (enabled: boolean) => {
        this.toggleComicTranslation(enabled);
      },
      onComicTranslationRefresh: () => {
        this.refreshCurrentComicTranslation();
      }
    })
  }
}

@Component
export struct ReaderHostScene {
  build() {
    ReaderSessionScene({ restoreAppChromeOnExit: false })
  }
}
