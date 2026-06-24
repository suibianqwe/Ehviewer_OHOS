import { common } from '@kit.AbilityKit';
import { GalleryDetail, GalleryPage, GalleryPreview, GallerySite } from '../model/GalleryModels';
import { READER_ABILITY_CONTEXT_KEY } from '../entryability/ReaderAbility';
import { EhHttpClient, GalleryDetailLoadResult, GalleryPageLoadResult } from '../services/EhHttpClient';
import { galleryPageCache } from '../services/GalleryPageCache';
import { createReaderSessionState, readerSessionStore, READER_SESSION_REVISION_KEY } from '../services/ReaderSessionStore';
import {
  cacheReaderImageForPage,
  cloneGalleryDetail,
  cloneGalleryPage,
  cloneGalleryPreviews,
  createEmptyDetail,
  createEmptyPage,
  createReaderLoadingPage,
  readerPageReferer,
  readerPreloadCount,
  readerStartIndex,
  saveGalleryReadPosition,
  setReaderActiveBackHandler
} from '../shared/EhShared';
import { ReaderPageState, ReaderScene } from './ReaderScenes';

@Component
export struct ReaderHostScene {
  private client: EhHttpClient = new EhHttpClient();

  @State detail: GalleryDetail = createEmptyDetail();
  @State page: GalleryPage = createEmptyPage();
  @State statusText: string = 'Reader is ready';
  @State detailRequestUrl: string = '';
  @State listRequestUrl: string = '';
  @State site: GallerySite = GallerySite.E;
  @State pageIndex: number = 0;
  @State renderVersion: number = 0;
  @State readerPages: ReaderPageState[] = [];
  @StorageProp(READER_SESSION_REVISION_KEY) @Watch('onSessionRevisionChange') sessionRevision: number = 0;
  private loadedSessionRevision: number = -1;
  private readerPreviewMap: Map<number, GalleryPreview> = new Map();
  private readerPreviewPageRequests: Map<number, Promise<GalleryPreview | null>> = new Map();
  private readerPreviewPageSize: number = 0;

  aboutToAppear(): void {
    setReaderActiveBackHandler(() => this.handleSystemBack());
    this.loadCurrentSession();
  }

  onSessionRevisionChange(): void {
    if (this.sessionRevision === this.loadedSessionRevision) {
      return;
    }
    this.loadCurrentSession();
  }

  private loadCurrentSession(): void {
    const session = readerSessionStore.getSession();
    if (session === null || session.detail.gid <= 0) {
      this.statusText = 'Reader session is empty';
      this.renderVersion++;
      return;
    }
    this.loadedSessionRevision = this.sessionRevision;
    this.readerPreviewMap.clear();
    this.readerPreviewPageRequests.clear();
    this.readerPreviewPageSize = 0;
    this.readerPages = [];
    this.detail = cloneGalleryDetail(session.detail);
    this.statusText = session.statusText;
    this.detailRequestUrl = session.detailRequestUrl;
    this.listRequestUrl = session.listRequestUrl;
    this.site = session.site;
    this.pageIndex = session.pageIndex >= 0 ? session.pageIndex : readerStartIndex(this.detail);
    this.seedReaderPreviewCache(this.detail.previewSet);
    this.page = this.isPageForIndex(session.page, this.pageIndex) ? cloneGalleryPage(session.page) : createEmptyPage();
    if (this.page.imageUrl.length > 0 || this.page.pageUrl.length > 0 ||
      (this.page.cachedImagePath !== undefined && this.page.cachedImagePath.length > 0)) {
      this.setReaderPage(this.pageIndex, this.page);
    }
    this.renderVersion++;
    if (this.page.imageUrl.length === 0 &&
      (this.page.cachedImagePath === undefined || this.page.cachedImagePath.length === 0)) {
      this.loadReaderPageByIndex(this.pageIndex);
    } else {
      this.cacheReaderImage(this.pageIndex, this.page);
      this.preloadReaderPages(this.pageIndex);
    }
  }

  aboutToDisappear(): void {
    this.persistSession();
    setReaderActiveBackHandler(null);
  }

  private handleSystemBack(): boolean {
    this.closeReader();
    return true;
  }

  private persistSession(): void {
    readerSessionStore.updateSession(createReaderSessionState(this.detail, this.page, this.statusText,
      this.detailRequestUrl, this.listRequestUrl, this.site, this.pageIndex));
  }

  private closeReader(): void {
    const context = AppStorage.get<common.UIAbilityContext>(READER_ABILITY_CONTEXT_KEY);
    if (context !== undefined) {
      context.terminateSelf().catch(() => {});
    }
  }

  private loadReaderPage(preview: GalleryPreview): void {
    if (preview.pageUrl.length === 0) {
      this.statusText = 'Preview has no page URL';
      this.renderVersion++;
      return;
    }

    this.readerPreviewMap.set(preview.index, preview);
    this.pageIndex = preview.index;
    saveGalleryReadPosition(this.detail.gid, preview.index, this.detail);
    this.statusText = 'Loading page ' + (preview.index + 1).toString() + '...';
    this.page = createReaderLoadingPage(preview.pageUrl);
    this.setReaderPage(preview.index, this.page);
    this.renderVersion++;

    const cached = galleryPageCache.get(preview.pageUrl);
    if (cached !== null) {
      this.statusText = 'Page loaded from cache';
      this.page = cloneGalleryPage(cached);
      this.setReaderPage(preview.index, cached);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, cached);
      this.preloadReaderPages(preview.index);
      this.persistSession();
      return;
    }

    this.client.loadGalleryPage(preview.pageUrl, this.site,
      readerPageReferer(this.detailRequestUrl, this.detail.previewSet, preview.index, this.site))
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
        this.preloadReaderPages(preview.index);
        this.persistSession();
      }).catch((error: Error) => {
        this.statusText = 'Page load failed: ' + error.message;
        this.renderVersion++;
        this.persistSession();
      });
  }

  private cacheReaderImage(index: number, page: GalleryPage): void {
    cacheReaderImageForPage(page, (cachedPage: GalleryPage) => {
      galleryPageCache.put(cachedPage.pageUrl.length > 0 ? cachedPage.pageUrl : page.pageUrl, cachedPage);
      this.setReaderPage(index, cachedPage);
      if (this.pageIndex === index) {
        this.page = cloneGalleryPage(cachedPage);
        this.statusText = 'Page loaded from local cache';
        this.renderVersion++;
        this.persistSession();
      }
    }, this.detail, index);
  }

  private async preloadReaderPages(index: number): Promise<void> {
    const count = Math.max(2, readerPreloadCount());
    if (count <= 0) {
      return;
    }
    for (let offset = 1; offset <= count; offset++) {
      const targets: number[] = [index - offset, index + offset];
      for (let i = 0; i < targets.length; i++) {
        const nextIndex = targets[i];
        if (nextIndex < 0 || nextIndex >= this.readerTotalPages()) {
          continue;
        }
        const preview = await this.ensureReaderPreview(nextIndex, true);
        if (preview === null || preview.pageUrl.length === 0) {
          continue;
        }
        const cached = galleryPageCache.get(preview.pageUrl);
        if (cached !== null) {
          this.setReaderPage(nextIndex, cached);
          this.cacheReaderImage(nextIndex, cached);
          continue;
        }
        try {
          const result = await this.client.loadGalleryPage(preview.pageUrl, this.site,
            readerPageReferer(this.detailRequestUrl, this.detail.previewSet, nextIndex, this.site));
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
      statusText: this.statusText,
      pageIndex: this.pageIndex,
      totalPages: this.readerTotalPages(),
      restoreAppChromeOnExit: false,
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
      }
    })
  }
}
