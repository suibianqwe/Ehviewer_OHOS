import { common } from '@kit.AbilityKit';
import { GalleryCategory, GalleryDetail, GalleryPage, GalleryPreview, GalleryRoute, GallerySite } from '../model/GalleryModels';
import { ehDownloadFileStore, RestoredDownloadGallery } from '../services/EhDownloadFileStore';
import { DownloadInfo, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
import { EhHttpClient } from '../services/EhHttpClient';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { DEFAULT_ADVANCE_SEARCH, EhUrl, ListMode } from '../services/EhUrl';
import { galleryPageCache } from '../services/GalleryPageCache';
import { readerImageCache } from '../services/ReaderImageCache';
import { createReaderSessionState, readerSessionStore } from '../services/ReaderSessionStore';
import { applyAppChromeImmersiveMode, enterEmbeddedReaderFullscreen } from '../services/EhWindowImmersive';
import { LANGUAGE_REVISION_KEY, STATUS_BAR_HEIGHT_KEY, setActiveBackHandler } from '../shared/EhShared';
import {
  cloneGalleryPage,
  cloneGalleryDetail,
  createDetailFromGallery,
  createEmptyDetail,
  createEmptyPage,
  createReaderLoadingPage,
  currentGallerySite,
  downloadButtonText,
  downloadImageUrlForPage,
  downloadPageIndexes,
  downloadThreadLimit,
  filterDownloadItems,
  getAbilityContext,
  nextDownloadCategoryFilter,
  nextDownloadSortMode,
  nextDownloadStatusFilter,
  readerPageReferer,
  saveGalleryReadPosition,
  uiStatusText,
  uiText,
  uiValue
} from '../shared/EhShared';
import {
  themeControlMutedBackground,
  themeControlNeutralBackground,
  themeOnPrimaryText,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSurface
} from '../shared/EhTheme';
import { EhNavBar } from './NavigationComponents';
import { GalleryListScene, ReaderPageState, ReaderScene } from './GalleryScenes';
import { DownloadRow } from './DownloadRow';
import { GalleryDetailOverlayScene } from './GalleryDetailScenes';

@Component
export struct DownloadScene {
  private client: EhHttpClient = new EhHttpClient();
  private shouldStop: boolean = false;
  private stoppedGids: number[] = [];
  private unsubscribeStore: () => void = () => {};
  onMenu: () => void = () => {};

  @State items: DownloadInfo[] = [];
  @State query: string = '';
  @State statusFilter: string = 'All';
  @State sortMode: string = 'Default';
  @State categoryFilter: string = 'All';
  @State statusText: string = 'Downloads: idle';
  @State isProcessing: boolean = false;
  @State showDetail: boolean = false;
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = '';
  @State detailRequestUrl: string = '';
  @State detailLoaded: boolean = false;
  @State detailRenderVersion: number = 0;
  @State showReader: boolean = false;
  @State localReaderDetail: GalleryDetail = createEmptyDetail();
  @State localReaderPage: GalleryPage = createEmptyPage();
  @State localReaderPages: ReaderPageState[] = [];
  @State localReaderIndex: number = 0;
  @State localReaderStatus: string = 'Page loaded from downloads';
  @State localReaderRenderVersion: number = 0;
  @State showTagSearch: boolean = false;
  @State tagSearchKeyword: string = '';
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  private detailItem: DownloadInfo | null = null;

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    setActiveBackHandler(() => this.handleSystemBack());
    this.unsubscribeStore = ehDownloadStore.subscribe((items: DownloadInfo[]) => {
      this.items = items;
    });
    this.loadDownloads();
  }

  aboutToDisappear(): void {
    setActiveBackHandler(null);
    this.unsubscribeStore();
  }

  private handleSystemBack(): boolean {
    if (this.showTagSearch) {
      this.closeTagSearch();
      return true;
    }
    if (this.showReader) {
      this.closeLocalReader();
      return true;
    }
    if (this.showDetail) {
      this.closeDetail();
      return true;
    }
    return false;
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  private loadDownloads(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.items = ehDownloadStore.getItems();
      return;
    }

    ehDownloadStore.load(context).then(() => {
      this.statusText = this.items.length.toString() + ' download items';
    }).catch((error: Error) => {
      this.statusText = 'Download load failed: ' + error.message;
      this.items = ehDownloadStore.getItems();
    });
  }

  private persistDownloads(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehDownloadStore.save(context).catch((error: Error) => {
      this.statusText = 'Download save failed: ' + error.message;
    });
  }

  private visibleDownloadItems(): DownloadInfo[] {
    return filterDownloadItems(this.items, this.query, this.statusFilter, 'All', this.sortMode, this.categoryFilter);
  }

  private activeSummary(): string {
    let wait = 0;
    let active = 0;
    let done = 0;
    let failed = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].state === DownloadState.Wait) {
        wait++;
      } else if (this.items[i].state === DownloadState.Downloading) {
        active++;
      } else if (this.items[i].state === DownloadState.Finish) {
        done++;
      } else if (this.items[i].state === DownloadState.Failed) {
        failed++;
      }
    }
    return wait.toString() + ' waiting  ' + active.toString() + ' active  ' + done.toString() + ' done  ' +
      failed.toString() + ' failed';
  }

  private startAll(): void {
    this.shouldStop = false;
    this.stoppedGids = [];
    ehDownloadStore.startAll();
    this.statusText = 'Queued idle and failed downloads';
    this.persistDownloads();
    this.runDownloadQueue();
  }

  private stopAll(): void {
    this.shouldStop = true;
    this.stoppedGids = [];
    ehDownloadStore.stopAll();
    this.statusText = 'Stopped waiting downloads';
    this.persistDownloads();
  }

  private clearFinished(): void {
    ehDownloadStore.clearFinished();
    this.statusText = 'Cleared finished downloads';
    this.persistDownloads();
  }

  private restoreDownloadedItems(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Restore needs app context';
      return;
    }
    const restored: RestoredDownloadGallery[] = ehDownloadFileStore.restoreDownloadedGalleries(context);
    let added = 0;
    for (let i = 0; i < restored.length; i++) {
      if (!ehDownloadStore.contains(restored[i].gallery.gid)) {
        const item = ehDownloadStore.addGallery(restored[i].gallery, '');
        if (item !== null) {
          ehDownloadStore.setState(item.gid, restored[i].finished >= restored[i].total && restored[i].total > 0 ?
            DownloadState.Finish : DownloadState.None);
          ehDownloadStore.setProgress(item.gid, restored[i].finished, restored[i].total, restored[i].finished);
          ehDownloadStore.setStorage(item.gid, restored[i].directory, restored[i].fileSize);
          added++;
        }
      }
    }
    this.statusText = 'Restored ' + added.toString() + '/' + restored.length.toString() + ' downloaded galleries';
    this.persistDownloads();
  }

  private cycleItemState(item: DownloadInfo): void {
    if (item.state === DownloadState.Wait || item.state === DownloadState.Downloading) {
      this.stopItem(item);
      return;
    }
    this.startItem(item);
  }

  private startItem(item: DownloadInfo): void {
    this.shouldStop = false;
    this.removeStoppedGid(item.gid);
    ehDownloadStore.startGallery(item.gid);
    this.statusText = 'Queued: ' + item.title;
    this.persistDownloads();
    this.runDownloadQueue();
  }

  private stopItem(item: DownloadInfo): void {
    this.addStoppedGid(item.gid);
    ehDownloadStore.stopGallery(item.gid);
    this.statusText = 'Stopped: ' + item.title;
    this.persistDownloads();
  }

  private removeItem(item: DownloadInfo): void {
    const context = getAbilityContext();
    if (context !== undefined) {
      ehDownloadFileStore.removeGalleryDirectory(context, item);
    }
    ehDownloadStore.removeGallery(item.gid);
    this.statusText = 'Removed: ' + item.title;
    this.persistDownloads();
  }

  private openDetail(item: DownloadInfo): void {
    this.detailItem = item;
    this.showDetail = true;
    this.detail = createDetailFromGallery(item);
    this.detailStatus = 'Loading gallery detail...';
    this.detailRequestUrl = '';
    this.detailLoaded = false;
    this.detailRenderVersion++;
    this.client.loadGalleryDetail(item.gid, item.token, 0, currentGallerySite(), EhUrl.getReferer(currentGallerySite()))
      .then((result) => {
        if (!result.ok || result.detail === null) {
          this.detailStatus = 'Detail load failed: ' + result.message;
          this.detailRenderVersion++;
          return;
        }
        this.detail = cloneGalleryDetail(result.detail);
        this.detailRequestUrl = result.url;
        this.detailStatus = 'Gallery detail loaded';
        this.detailLoaded = true;
        ehDownloadStore.updateGallery(result.detail);
        this.persistDownloads();
        this.detailRenderVersion++;
      }).catch((error: Error) => {
        this.detailStatus = 'Detail load failed: ' + error.message;
        this.detailRenderVersion++;
      });
  }

  private closeDetail(): void {
    this.showDetail = false;
    this.detailStatus = '';
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

  private readDetail(): void {
    if (this.detailItem !== null) {
      this.openDownloadedItem(this.detailItem);
    }
  }

  private async runDownloadQueue(): Promise<void> {
    if (this.isProcessing) {
      return;
    }

    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Download needs app context';
      return;
    }

    this.isProcessing = true;
    try {
      const workerCount = downloadThreadLimit();
      this.statusText = 'Download workers: ' + workerCount.toString();
      while (!this.shouldStop) {
        const queue = ehDownloadStore.getItems();
        const batch: DownloadInfo[] = [];
        for (let i = 0; i < queue.length && batch.length < workerCount; i++) {
          if (queue[i].state === DownloadState.Wait) {
            batch.push(queue[i]);
          }
        }
        if (batch.length === 0) {
          break;
        }

        const tasks: Promise<void>[] = [];
        for (let i = 0; i < batch.length; i++) {
          tasks.push(this.downloadOne(context, batch[i]));
        }
        await Promise.all(tasks);
      }
    } finally {
      this.isProcessing = false;
      this.persistDownloads();
    }
  }

  private async downloadOne(context: common.UIAbilityContext, item: DownloadInfo): Promise<void> {
    ehDownloadStore.setState(item.gid, DownloadState.Downloading);
    ehDownloadStore.setTransfer(item.gid, 0, 0);
    this.statusText = 'Downloading: ' + item.title;
    this.persistDownloads();

    try {
      const detailResult = await this.client.loadGalleryDetail(item.gid, item.token, 0, currentGallerySite(),
        EhUrl.getReferer(currentGallerySite()));
      if (!detailResult.ok || detailResult.detail === null) {
        throw new Error(detailResult.message);
      }

      ehDownloadStore.updateGallery(detailResult.detail);
      const total = detailResult.detail.previewSet.length > 0 ? detailResult.detail.previewSet.length :
        detailResult.detail.pages;
      const downloadDirectory = ehDownloadFileStore.prepareGallery(context, detailResult.detail);
      ehDownloadStore.setProgress(item.gid, 0, total, 0);
      ehDownloadStore.setStorage(item.gid, downloadDirectory, 0);

      let finished = 0;
      let fileSize = ehDownloadFileStore.directorySize(context, detailResult.detail);
      for (let i = 0; i < detailResult.detail.previewSet.length; i++) {
        if (ehDownloadFileStore.findPageImage(context, detailResult.detail, i).length > 0) {
          finished++;
        }
      }
      if (finished > 0) {
        ehDownloadStore.setProgress(item.gid, finished, total, finished);
        ehDownloadStore.setStorage(item.gid, downloadDirectory, fileSize);
        this.statusText = 'Resumed ' + finished.toString() + '/' + total.toString() + ': ' + item.title;
        this.persistDownloads();
      }

      let lastBytes = fileSize;
      let lastTime = Date.now();
      const pageIndexes = downloadPageIndexes(detailResult.detail.previewSet.length);
      for (let orderIndex = 0; orderIndex < pageIndexes.length; orderIndex++) {
        const i = pageIndexes[orderIndex];
        if (this.shouldStop || this.isStopped(item.gid)) {
          ehDownloadStore.setState(item.gid, DownloadState.None);
          ehDownloadStore.setTransfer(item.gid, 0, 0);
          this.statusText = 'Stopped: ' + item.title;
          return;
        }

        const preview = detailResult.detail.previewSet[i];
        if (preview.pageUrl.length === 0 || ehDownloadFileStore.findPageImage(context, detailResult.detail, i).length > 0) {
          continue;
        }

        const pageResult = await this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
          readerPageReferer(detailResult.url, detailResult.detail.previewSet, i, currentGallerySite()));
        if (!pageResult.ok || pageResult.page === null) {
          throw new Error(pageResult.message);
        }

        const imageUrl = downloadImageUrlForPage(pageResult.page);
        if (imageUrl.length === 0) {
          throw new Error('Image URL missing');
        }

        const existingCachedPath = readerImageCache.getCachedPath(context, imageUrl);
        const cachedPath = existingCachedPath.length > 0 ? existingCachedPath :
          await readerImageCache.ensureCached(context, imageUrl, pageResult.page.pageUrl, false);
        const savedPath = ehDownloadFileStore.savePageImage(context, detailResult.detail, pageResult.page, i, cachedPath);
        fileSize += ehDownloadFileStore.statFileSize(savedPath);
        finished++;

        const now = Date.now();
        const speed = Math.round(Math.max(0, fileSize - lastBytes) * 1000 / Math.max(1, now - lastTime));
        lastBytes = fileSize;
        lastTime = now;
        const averageBytes = finished > 0 ? Math.round(fileSize / finished) : 0;
        const remaining = speed > 0 ? Math.round(Math.max(0, total - finished) * averageBytes / speed) : 0;

        ehDownloadStore.setProgress(item.gid, finished, total, finished);
        ehDownloadStore.setStorage(item.gid, downloadDirectory, fileSize);
        ehDownloadStore.setTransfer(item.gid, speed, remaining);
        this.statusText = 'Downloaded ' + finished.toString() + '/' + total.toString() + ': ' + item.title;
        this.persistDownloads();
      }

      ehDownloadStore.setState(item.gid, DownloadState.Finish);
      ehDownloadStore.setProgress(item.gid, total, total, total);
      ehDownloadStore.setStorage(item.gid, downloadDirectory, fileSize);
      ehDownloadStore.setTransfer(item.gid, 0, 0);
      this.statusText = 'Download finished: ' + item.title;
      this.persistDownloads();
    } catch (error) {
      ehDownloadStore.setState(item.gid, DownloadState.Failed);
      ehDownloadStore.setTransfer(item.gid, 0, 0);
      this.statusText = 'Download failed: ' + String(error);
      this.persistDownloads();
    }
  }

  private openDownloadedItem(item: DownloadInfo): void {
    this.openDownloadedItemAt(item, ehHistoryStore.getReadPage(item.gid));
  }

  private openDownloadedItemAt(item: DownloadInfo, requestedIndex: number): void {
    this.openDownloadedItemAtAsync(item, requestedIndex).catch((error: Error) => {
      this.statusText = 'Reader launch failed: ' + error.message;
    });
  }

  private async openDownloadedItemAtAsync(item: DownloadInfo, requestedIndex: number): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Reader launch failed: Ability context is not ready';
      return;
    }
    const total = Math.max(item.total, item.pages, item.finished);
    const images = ehDownloadFileStore.listPageImageSlots(context, item, total);
    if (!this.hasAnyImage(images)) {
      this.statusText = item.state === DownloadState.Finish ? 'Downloaded files are missing: ' + item.title :
        'Download is not ready: ' + item.title;
      return;
    }

    const session = await this.createLocalReaderSession(context, item, images, requestedIndex);
    readerSessionStore.setSession(createReaderSessionState(session.detail, session.page, session.status,
      session.detailRequestUrl, '', currentGallerySite(), session.index));

    if (ehSettingsStore.getValue('reader_standalone', 'On') !== 'On') {
      this.localReaderDetail = session.detail;
      this.localReaderPage = session.page;
      this.localReaderPages = session.pages;
      this.localReaderIndex = session.index;
      this.localReaderStatus = session.status;
      this.localReaderRenderVersion++;
      enterEmbeddedReaderFullscreen();
      this.showReader = true;
      if (!this.pageHasLocalImage(this.localReaderPage)) {
        this.loadMissingLocalReaderPage(session.index);
      }
      return;
    }

    context.startAbility({
      bundleName: 'yt.ehviewer.huawei',
      moduleName: 'entry',
      abilityName: 'ReaderAbility'
    }).catch((error: Error) => {
      this.statusText = 'Reader launch failed: ' + error.message;
    });
  }

  private async createLocalReaderSession(context: common.UIAbilityContext, item: DownloadInfo, images: string[],
    requestedIndex: number): Promise<LocalReaderSession> {
    let detail = createDetailFromGallery(item);
    let detailRequestUrl = '';
    try {
      const result = await this.client.loadGalleryDetail(item.gid, item.token, 0, currentGallerySite(),
        EhUrl.getReferer(currentGallerySite()));
      if (result.ok && result.detail !== null) {
        detail = cloneGalleryDetail(result.detail);
        detailRequestUrl = result.url;
        ehDownloadStore.updateGallery(result.detail);
        this.persistDownloads();
      }
    } catch (error) {
    }

    const total = Math.max(detail.pages, item.total, item.pages, images.length);
    const previews: GalleryPreview[] = [];
    const pages: ReaderPageState[] = [];
    const slots = images.length >= total ? images : ehDownloadFileStore.listPageImageSlots(context, item, total);
    for (let i = 0; i < total; i++) {
      const preview = this.previewForIndex(detail, i);
      const pageUrl = preview.pageUrl.length > 0 ? preview.pageUrl : this.localPageUrl(item.gid, i);
      previews.push({
        index: i,
        pageUrl: pageUrl,
        imageUrl: preview.imageUrl,
        width: preview.width,
        height: preview.height,
        xOffset: preview.xOffset,
        yOffset: preview.yOffset
      });
      const path = i < slots.length ? slots[i] : '';
      const page = path.length > 0 ? this.createLocalReaderPage(pageUrl, preview.imageUrl, path) :
        createReaderLoadingPage(pageUrl);
      if (pageUrl.length > 0) {
        galleryPageCache.put(pageUrl, page);
      }
      pages.push({ index: i, page: cloneGalleryPage(page) });
    }
    detail.pages = total;
    detail.previewPages = Math.max(detail.previewPages, 1);
    detail.previewSet = previews;
    const index = requestedIndex >= 0 && requestedIndex < total ? requestedIndex : 0;
    return {
      detail: detail,
      page: cloneGalleryPage(pages[index].page),
      pages: pages,
      index: index,
      status: this.pageHasLocalImage(pages[index].page) ?
        'Page loaded from downloads' : 'Page is not downloaded yet',
      detailRequestUrl: detailRequestUrl
    };
  }

  private pageHasLocalImage(page: GalleryPage): boolean {
    return page.cachedImagePath !== undefined && page.cachedImagePath.length > 0;
  }

  private hasAnyImage(images: string[]): boolean {
    for (let i = 0; i < images.length; i++) {
      if (images[i].length > 0) {
        return true;
      }
    }
    return false;
  }

  private previewForIndex(detail: GalleryDetail, index: number): GalleryPreview {
    for (let i = 0; i < detail.previewSet.length; i++) {
      if (detail.previewSet[i].index === index) {
        return detail.previewSet[i];
      }
    }
    return {
      index: index,
      pageUrl: '',
      imageUrl: '',
      width: 0,
      height: 0,
      xOffset: 0,
      yOffset: 0
    };
  }

  private createLocalReaderPage(pageUrl: string, imageUrl: string, path: string): GalleryPage {
    return {
      pageUrl: pageUrl,
      imageUrl: imageUrl,
      skipHathKey: '',
      originImageUrl: '',
      showKey: '',
      cachedImagePath: path
    };
  }

  private closeLocalReader(): void {
    this.showReader = false;
    this.localReaderStatus = 'Page loaded from downloads';
  }

  private jumpLocalReader(index: number): void {
    if (index < 0 || index >= this.localReaderPages.length) {
      return;
    }
    this.localReaderIndex = index;
    this.localReaderPage = cloneGalleryPage(this.localReaderPages[index].page);
    this.localReaderStatus = this.pageHasLocalImage(this.localReaderPage) ? 'Page loaded from downloads' :
      'Page is not downloaded yet';
    saveGalleryReadPosition(this.localReaderDetail.gid, index);
    this.localReaderRenderVersion++;
    readerSessionStore.updateSession(createReaderSessionState(this.localReaderDetail, this.localReaderPage,
      this.localReaderStatus, '', '', GallerySite.E, this.localReaderIndex));
    if (this.pageHasLocalImage(this.localReaderPage)) {
      return;
    }
    this.loadMissingLocalReaderPage(index);
  }

  private loadMissingLocalReaderPage(index: number): void {
    this.loadMissingLocalReaderPageAsync(index).catch((error: Error) => {
      if (this.localReaderIndex === index) {
        this.localReaderStatus = 'Page load failed: ' + error.message;
        this.localReaderRenderVersion++;
      }
    });
  }

  private async loadMissingLocalReaderPageAsync(index: number): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined || index < 0 || index >= this.localReaderPages.length) {
      return;
    }
    const downloadedPath = ehDownloadFileStore.findPageImage(context, this.localReaderDetail, index);
    if (downloadedPath.length > 0) {
      const existing = this.localReaderPages[index].page;
      this.setLocalReaderPage(index, this.createLocalReaderPage(existing.pageUrl, existing.imageUrl, downloadedPath),
        'Page loaded from downloads');
      return;
    }

    const preview = await this.resolveLocalReaderPreview(index);
    if (preview.pageUrl.length === 0) {
      throw new Error('Page URL is unavailable');
    }

    if (this.localReaderIndex === index) {
      this.localReaderStatus = 'Loading page ' + (index + 1).toString() + '...';
      this.localReaderRenderVersion++;
    }

    const result = await this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
      readerPageReferer('', this.localReaderDetail.previewSet, index, currentGallerySite()));
    if (!result.ok || result.page === null) {
      throw new Error(result.message);
    }

    const imageUrl = downloadImageUrlForPage(result.page);
    if (imageUrl.length === 0) {
      throw new Error('Image URL missing');
    }

    const cachedPath = readerImageCache.getCachedPath(context, imageUrl);
    const readyPath = cachedPath.length > 0 ? cachedPath :
      await readerImageCache.ensureCached(context, imageUrl, result.page.pageUrl, false);
    const savedPath = ehDownloadFileStore.savePageImage(context, this.localReaderDetail, result.page, index, readyPath);
    this.refreshDownloadProgressAfterRead(context, this.localReaderDetail);
    const page = this.createLocalReaderPage(result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl,
      result.page.imageUrl, savedPath);
    galleryPageCache.put(page.pageUrl, page);
    this.setLocalReaderPage(index, page, 'Page loaded from downloads');
  }

  private setLocalReaderPage(index: number, page: GalleryPage, status: string): void {
    const next: ReaderPageState[] = [];
    for (let i = 0; i < this.localReaderPages.length; i++) {
      if (this.localReaderPages[i].index === index) {
        next.push({ index: index, page: cloneGalleryPage(page) });
      } else {
        next.push({ index: this.localReaderPages[i].index, page: cloneGalleryPage(this.localReaderPages[i].page) });
      }
    }
    this.localReaderPages = next;
    if (this.localReaderIndex === index) {
      this.localReaderPage = cloneGalleryPage(page);
      this.localReaderStatus = status;
      this.localReaderRenderVersion++;
      readerSessionStore.updateSession(createReaderSessionState(this.localReaderDetail, this.localReaderPage,
        this.localReaderStatus, '', '', GallerySite.E, this.localReaderIndex));
    }
  }

  private refreshDownloadProgressAfterRead(context: common.UIAbilityContext, detail: GalleryDetail): void {
    const total = Math.max(detail.pages, 0);
    const images = ehDownloadFileStore.listPageImageSlots(context, detail, total);
    let finished = 0;
    for (let i = 0; i < images.length; i++) {
      if (images[i].length > 0) {
        finished++;
      }
    }
    ehDownloadStore.setProgress(detail.gid, finished, total, finished);
    ehDownloadStore.setStorage(detail.gid, ehDownloadFileStore.galleryDirectory(context, detail),
      ehDownloadFileStore.directorySize(context, detail));
    this.persistDownloads();
  }

  private async resolveLocalReaderPreview(index: number): Promise<GalleryPreview> {
    let preview = this.previewForIndex(this.localReaderDetail, index);
    if (preview.pageUrl.length > 0 || this.localReaderDetail.gid <= 0 || this.localReaderDetail.token.length === 0) {
      return preview;
    }

    const pageSize = Math.max(1, this.localReaderDetail.previewSet.length);
    const previewPageIndex = Math.floor(index / pageSize);
    const result = await this.client.loadGalleryDetail(this.localReaderDetail.gid, this.localReaderDetail.token,
      previewPageIndex, currentGallerySite(), EhUrl.getReferer(currentGallerySite()));
    if (result.ok && result.detail !== null) {
      this.mergeLocalReaderPreviews(result.detail);
      preview = this.previewForIndex(this.localReaderDetail, index);
      if (preview.pageUrl.length > 0) {
        const current = this.localReaderPages[index].page;
        const cachedPath = current.cachedImagePath === undefined ? '' : current.cachedImagePath;
        const page = this.pageHasLocalImage(current) ?
          this.createLocalReaderPage(preview.pageUrl, preview.imageUrl, cachedPath) :
          createReaderLoadingPage(preview.pageUrl);
        this.setLocalReaderPage(index, page, this.pageHasLocalImage(page) ? 'Page loaded from downloads' :
          'Page is not downloaded yet');
      }
    }
    return preview;
  }

  private mergeLocalReaderPreviews(loaded: GalleryDetail): void {
    const merged: GalleryPreview[] = [];
    for (let i = 0; i < this.localReaderDetail.previewSet.length; i++) {
      merged.push(this.localReaderDetail.previewSet[i]);
    }
    for (let i = 0; i < loaded.previewSet.length; i++) {
      let replaced = false;
      for (let j = 0; j < merged.length; j++) {
        if (merged[j].index === loaded.previewSet[i].index) {
          merged[j] = loaded.previewSet[i];
          replaced = true;
          break;
        }
      }
      if (!replaced) {
        merged.push(loaded.previewSet[i]);
      }
    }
    merged.sort((left: GalleryPreview, right: GalleryPreview) => left.index - right.index);
    const nextDetail = cloneGalleryDetail(this.localReaderDetail);
    nextDetail.previewSet = merged;
    nextDetail.previewPages = Math.max(nextDetail.previewPages, loaded.previewPages);
    nextDetail.pages = Math.max(nextDetail.pages, loaded.pages);
    this.localReaderDetail = nextDetail;
  }

  private localPageUrl(gid: number, index: number): string {
    return 'ehviewer://download/' + gid.toString() + '/' + index.toString();
  }

  private isStopped(gid: number): boolean {
    for (let i = 0; i < this.stoppedGids.length; i++) {
      if (this.stoppedGids[i] === gid) {
        return true;
      }
    }
    return false;
  }

  private addStoppedGid(gid: number): void {
    if (!this.isStopped(gid)) {
      this.stoppedGids.push(gid);
    }
  }

  private removeStoppedGid(gid: number): void {
    const next: number[] = [];
    for (let i = 0; i < this.stoppedGids.length; i++) {
      if (this.stoppedGids[i] !== gid) {
        next.push(this.stoppedGids[i]);
      }
    }
    this.stoppedGids = next;
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
        renderVersion: this.localReaderRenderVersion,
        page: this.localReaderPage,
        readerPages: this.localReaderPages,
        statusText: this.localReaderStatus,
        pageIndex: this.localReaderIndex,
        totalPages: this.localReaderPages.length,
        restoreAppChromeOnExit: true,
        onBack: () => {
          this.closeLocalReader();
        },
        onPrev: () => {
          this.jumpLocalReader(this.localReaderIndex - 1);
        },
        onNext: () => {
          this.jumpLocalReader(this.localReaderIndex + 1);
        },
        onJump: (index: number) => {
          this.jumpLocalReader(index);
        },
        onRetry: () => {
          this.jumpLocalReader(this.localReaderIndex);
        }
      })
    } else if (this.showDetail) {
      GalleryDetailOverlayScene({
        renderVersion: this.detailRenderVersion,
        showComments: false,
        detail: this.detail,
        isDetailLoaded: this.detailLoaded,
        isFavorited: this.detail.isFavorited,
        statusText: this.detailStatus,
        requestUrl: this.detailRequestUrl,
        downloadText: downloadButtonText(this.detail.gid),
        onBack: () => {
          this.closeDetail();
        },
        onDownload: () => {
          if (this.detailItem !== null) {
            this.cycleItemState(this.detailItem);
          }
        },
        onRead: () => {
          this.readDetail();
        },
        onSelectPreview: (preview: GalleryPreview) => {
          if (this.detailItem !== null) {
            this.openDownloadedItemAt(this.detailItem, preview.index);
          }
        },
        onComments: () => {},
        onFavorite: () => {},
        onShare: () => {},
        onRate: (_rating: number) => {},
        onTorrent: () => {},
        onArchive: () => {},
        onLoadMorePreviews: () => {},
        onTagSearch: (namespace: string, tag: string) => {
          this.openTagSearch(namespace, tag);
        }
      })
    } else {
      Column() {
      EhNavBar({
        statusBarHeight: this.statusBarVp(),
        title: 'Downloads',
        searchMode: true,
        keyword: this.query,
        onMenu: this.onMenu,
        onKeywordChange: (value: string) => {
          this.query = value;
        },
        onSearch: () => {},
        onRefresh: () => {
          this.loadDownloads();
        }
      })

      Column() {
        Row() {
          Button(uiText('Status') + ': ' + uiValue(this.statusFilter))
            .height(30)
            .fontSize(12)
            .onClick(() => {
              this.statusFilter = nextDownloadStatusFilter(this.statusFilter);
            })
          Button(uiText('Category') + ': ' + uiValue(this.categoryFilter))
            .height(30)
            .fontSize(12)
            .margin({ left: 8 })
            .onClick(() => {
              this.categoryFilter = nextDownloadCategoryFilter(this.categoryFilter);
            })
          Button(uiText('Sort') + ': ' + uiValue(this.sortMode))
            .height(30)
            .fontSize(12)
            .margin({ left: 8 })
            .onClick(() => {
              this.sortMode = nextDownloadSortMode(this.sortMode);
            })
        }
        .width('100%')

        Row() {
          Text(uiStatusText(this.statusText))
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.visibleDownloadItems().length.toString() + '/' + this.items.length.toString())
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 8 })

        Text(this.activeSummary())
          .fontSize(11)
          .fontColor(themeSecondaryText())
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(themeSurface())

      if (this.visibleDownloadItems().length === 0) {
        Column() {
          Text(uiText('Downloads'))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(themePrimaryText())
          Text(this.items.length === 0 ? uiText('Download items will be shown here') :
            uiText('No items match the current filter'))
            .fontSize(14)
            .fontColor(themeSecondaryText())
            .margin({ top: 10 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.visibleDownloadItems(), (item: DownloadInfo) => {
            ListItem() {
              DownloadRow({
                item: item,
                onThumb: () => {
                  this.openDetail(item);
                },
                onOpen: () => {
                  this.openDownloadedItem(item);
                },
                onState: () => {
                  this.cycleItemState(item);
                },
                onRemove: () => {
                  this.removeItem(item);
                }
              })
            }
          }, (item: DownloadInfo) => item.gid.toString() + '-' + item.state + '-' + item.finished.toString() + '-' +
            item.total.toString() + '-' + item.speed.toString())
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      }

      Row() {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(20)
            .fontColor([themeOnPrimaryText()])
        }
        .width(46)
        .height(46)
        .backgroundColor(themePrimaryColor())
        .onClick(() => {
          this.startAll();
        })

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.pause_fill'))
            .fontSize(20)
            .fontColor([themeOnPrimaryText()])
        }
        .width(46)
        .height(46)
        .backgroundColor(themeControlMutedBackground())
        .margin({ left: 12 })
        .onClick(() => {
          this.stopAll();
        })

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.play_arrow_triangle_2_circlepath'))
            .fontSize(19)
            .fontColor([themeOnPrimaryText()])
        }
        .width(46)
        .height(46)
        .backgroundColor(themeControlNeutralBackground())
        .margin({ left: 12 })
        .onClick(() => {
          this.restoreDownloadedItems();
        })

        Blank()

        Button(uiText('Clear done'))
          .height(40)
          .fontSize(13)
          .enabled(this.items.length > 0)
          .onClick(() => {
            this.clearFinished();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(themePageBackground())
    }
  }
}

interface LocalReaderSession {
  detail: GalleryDetail;
  page: GalleryPage;
  pages: ReaderPageState[];
  index: number;
  status: string;
  detailRequestUrl: string;
}
