import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { ImageDownloadProgress, readerImageCache } from './ReaderImageCache';
import { ehDownloadFileStore } from './EhDownloadFileStore';
import { DownloadInfo, DownloadState, ehDownloadStore } from './EhDownloadStore';
import { EhHttpClient } from './EhHttpClient';
import { galleryPageCache } from './GalleryPageCache';
import { GalleryDetail, GalleryPage, GallerySite } from '../model/GalleryModels';
import {
  cloneGalleryDetail,
  currentGallerySite,
  downloadImageUrlForPage,
  downloadPageIndexes,
  downloadThreadLimit,
  readerPageImageCacheKey,
  readerPageReferer
} from '../shared/EhShared';
import { EhUrl } from './EhUrl';
import { mergeGalleryPreviewSets } from './GalleryPreviewLoader';
import { ehAppLog } from './EhAppLog';

const DOWNLOAD_PAGE_PROGRESS_SCALE: number = 1000;
const DOWNLOAD_PAGE_RETRY_LIMIT: number = 3;
const DOWNLOAD_NOTIFICATION_ID: number = 8001;
const DOWNLOAD_NOTIFICATION_TEMPLATE: string = 'downloadTemplate';

interface DownloadWorkerState {
  cursor: number;
  finished: number;
  fileSize: number;
  lastBytes: number;
  lastTime: number;
  speedWindowBytes: number;
  speedWindowStartedAt: number;
  currentSpeed: number;
  averagePageBytes: number;
  speedTimer: number;
  failedMessage: string;
}

interface DownloadedPageResult {
  page: GalleryPage;
  cachedPath: string;
}

type DownloadStatusListener = (status: string) => void;

function wait(ms: number): Promise<void> {
  return new Promise((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

function mergeDownloadDetailTitles(detail: GalleryDetail, item: DownloadInfo): GalleryDetail {
  const next = cloneGalleryDetail(detail);
  if (next.title.length === 0 && item.title.length > 0) {
    next.title = item.title;
  }
  if ((next.titleJpn === undefined || next.titleJpn.length === 0) && item.titleJpn !== undefined &&
    item.titleJpn.length > 0) {
    next.titleJpn = item.titleJpn;
  }
  return next;
}

export class EhDownloadManager {
  private client: EhHttpClient = new EhHttpClient();
  private isProcessing: boolean = false;
  private shouldStop: boolean = false;
  private stoppedGids: number[] = [];
  private listeners: DownloadStatusListener[] = [];
  private backgroundRunning: boolean = false;
  private notificationId: number = DOWNLOAD_NOTIFICATION_ID;
  private templateSupported: boolean = false;
  private templateChecked: boolean = false;

  subscribe(listener: DownloadStatusListener): () => void {
    this.listeners.push(listener);
    return () => {
      const next: DownloadStatusListener[] = [];
      for (let i = 0; i < this.listeners.length; i++) {
        if (this.listeners[i] !== listener) {
          next.push(this.listeners[i]);
        }
      }
      this.listeners = next;
    };
  }

  startQueue(context: common.UIAbilityContext): void {
    this.shouldStop = false;
    this.runDownloadQueue(context);
  }

  stopAll(): void {
    this.shouldStop = true;
    this.stoppedGids = [];
    ehDownloadStore.stopAll();
    this.publishStatus('Stopped waiting downloads');
  }

  stopGallery(gid: number): void {
    this.addStoppedGid(gid);
    ehDownloadStore.stopGallery(gid);
  }

  resumeGallery(gid: number): void {
    this.shouldStop = false;
    this.removeStoppedGid(gid);
    ehDownloadStore.startGallery(gid);
  }

  hasWaitingDownloads(): boolean {
    const items = ehDownloadStore.getItems();
    for (let i = 0; i < items.length; i++) {
      if (items[i].state === DownloadState.Wait) {
        return true;
      }
    }
    return false;
  }

  private async runDownloadQueue(context: common.UIAbilityContext): Promise<void> {
    if (this.isProcessing) {
      return;
    }

    this.isProcessing = true;
    await this.startBackgroundTask(context);
    try {
      const workerCount = downloadThreadLimitSafe();
      this.publishStatus('Download workers: ' + workerCount.toString());
      while (!this.shouldStop) {
        const queue = ehDownloadStore.getItems();
        let nextItem: DownloadInfo | null = null;
        for (let i = 0; i < queue.length; i++) {
          if (queue[i].state === DownloadState.Wait) {
            nextItem = queue[i];
            break;
          }
        }
        if (nextItem === null) {
          break;
        }

        await this.downloadOne(context, nextItem);
      }
    } finally {
      this.isProcessing = false;
      if (!this.hasWaitingDownloads()) {
        await this.stopBackgroundTask(context);
      }
      this.saveDownloads(context);
    }
  }

  private async downloadOne(context: common.UIAbilityContext, item: DownloadInfo): Promise<void> {
    ehDownloadStore.setState(item.gid, DownloadState.Downloading);
    ehDownloadStore.setTransfer(item.gid, 0, 0);
    this.publishStatus('Downloading: ' + item.title);
    this.saveDownloads(context);

    try {
      const detailResult = await this.client.loadGalleryDetail(item.gid, item.token, 0, currentGallerySite(),
        EhUrl.getReferer(currentGallerySite()));
      if (!detailResult.ok || detailResult.detail === null) {
        throw new Error(detailResult.message);
      }

      const detail = mergeDownloadDetailTitles(await this.loadCompleteDownloadDetail(detailResult.detail,
        detailResult.url), item);
      ehDownloadStore.updateGallery(detail);
      const total = Math.max(detail.pages, detail.previewSet.length);
      const downloadDirectory = ehDownloadFileStore.prepareGallery(context, detail);
      ehDownloadStore.setProgress(item.gid, 0, total, 0);
      ehDownloadStore.setStorage(item.gid, downloadDirectory, 0);
      await this.publishProgress(item, 0, total);

      let finished = 0;
      let fileSize = ehDownloadFileStore.directorySize(context, detail);
      for (let i = 0; i < detail.previewSet.length; i++) {
        if (ehDownloadFileStore.findPageImage(context, detail, i).length > 0) {
          finished++;
        }
      }
      if (finished > 0) {
        ehDownloadStore.setProgress(item.gid, finished, total, finished * DOWNLOAD_PAGE_PROGRESS_SCALE);
        ehDownloadStore.setStorage(item.gid, downloadDirectory, fileSize);
        this.publishStatus('Resumed ' + finished.toString() + '/' + total.toString() + ': ' + item.title);
        await this.publishProgress(item, finished, total);
        this.saveDownloads(context);
      }

      const pageIndexes = downloadPageIndexes(detail.previewSet.length);
      const workerState: DownloadWorkerState = {
        cursor: 0,
        finished: finished,
        fileSize: fileSize,
        lastBytes: fileSize,
        lastTime: Date.now(),
        speedWindowBytes: 0,
        speedWindowStartedAt: Date.now(),
        currentSpeed: 0,
        averagePageBytes: finished > 0 ? Math.max(1, Math.round(fileSize / finished)) : 0,
        speedTimer: -1,
        failedMessage: ''
      };
      const workerCount = Math.max(1, Math.min(downloadThreadLimitSafe(), Math.max(1, pageIndexes.length)));
      const tasks: Promise<void>[] = [];
      workerState.speedTimer = setInterval(() => {
        this.recordDownloadSpeed(item, workerState, total, 0, true);
      }, 1000);
      ehAppLog.info(context, 'DownloadManager', 'Start gallery download gid=' + item.gid.toString() +
        ', pages=' + total.toString() + ', workers=' + workerCount.toString());
      for (let i = 0; i < workerCount; i++) {
        tasks.push(this.downloadPageWorker(context, item, detail, detailResult.url, pageIndexes, total,
          downloadDirectory, workerState));
      }
      try {
        await Promise.all(tasks);
      } finally {
        if (workerState.speedTimer >= 0) {
          clearInterval(workerState.speedTimer);
          workerState.speedTimer = -1;
        }
      }

      if (this.shouldStop || this.isStopped(item.gid)) {
        ehDownloadStore.setState(item.gid, DownloadState.None);
        ehDownloadStore.setTransfer(item.gid, 0, 0);
        this.publishStatus('Stopped: ' + item.title);
        return;
      }

      if (workerState.failedMessage.length > 0) {
        throw new Error(workerState.failedMessage);
      }

      ehDownloadStore.setState(item.gid, DownloadState.Finish);
      ehDownloadStore.setProgress(item.gid, total, total, total * DOWNLOAD_PAGE_PROGRESS_SCALE);
      ehDownloadStore.setStorage(item.gid, downloadDirectory, workerState.fileSize);
      ehDownloadStore.setTransfer(item.gid, 0, 0);
      this.publishStatus('Download finished: ' + item.title);
      await this.publishProgress(item, total, total);
      this.saveDownloads(context);
    } catch (error) {
      ehDownloadStore.setState(item.gid, DownloadState.Failed);
      ehDownloadStore.setTransfer(item.gid, 0, 0);
      this.publishStatus('Download failed: ' + String(error));
      ehAppLog.error(context, 'DownloadManager', 'Download failed: ' + String(error));
      this.saveDownloads(context);
    }
  }

  private async downloadPageWorker(context: common.UIAbilityContext, item: DownloadInfo, detail: GalleryDetail,
    detailUrl: string, pageIndexes: number[], total: number, downloadDirectory: string,
    state: DownloadWorkerState): Promise<void> {
    while (!this.shouldStop && !this.isStopped(item.gid) && state.failedMessage.length === 0) {
      const orderIndex = state.cursor;
      state.cursor++;
      if (orderIndex >= pageIndexes.length) {
        return;
      }

      const pageIndex = pageIndexes[orderIndex];
      const preview = detail.previewSet[pageIndex];
      if (preview.pageUrl.length === 0 || ehDownloadFileStore.findPageImage(context, detail, pageIndex).length > 0) {
        continue;
      }

      try {
        const downloaded = await this.downloadPageWithRetry(context, item, detail, detailUrl, pageIndex, total, state);
        const savedPath = ehDownloadFileStore.savePageImage(context, detail, downloaded.page, pageIndex,
          downloaded.cachedPath);
        state.fileSize += ehDownloadFileStore.statFileSize(savedPath);
        state.finished++;
        state.averagePageBytes = state.finished > 0 ? Math.max(1, Math.round(state.fileSize / state.finished)) :
          state.averagePageBytes;

        const remaining = state.currentSpeed > 0 ?
          Math.round(Math.max(0, total - state.finished) * state.averagePageBytes / state.currentSpeed) : 0;

        ehDownloadStore.setProgress(item.gid, state.finished, total, state.finished * DOWNLOAD_PAGE_PROGRESS_SCALE);
        ehDownloadStore.setStorage(item.gid, downloadDirectory, state.fileSize);
        ehDownloadStore.setTransfer(item.gid, state.currentSpeed, remaining);
        this.publishStatus('Downloaded ' + state.finished.toString() + '/' + total.toString() + ': ' + item.title);
        await this.publishProgress(item, state.finished, total);
        this.saveDownloads(context);
      } catch (error) {
        state.failedMessage = String(error);
        ehAppLog.error(context, 'DownloadManager', 'Page worker failed gid=' + item.gid.toString() +
          ', page=' + (pageIndex + 1).toString() + '/' + total.toString() + ': ' + state.failedMessage);
      }
    }
  }

  private async downloadPageWithRetry(context: common.UIAbilityContext, item: DownloadInfo, detail: GalleryDetail,
    detailUrl: string, pageIndex: number, total: number, state: DownloadWorkerState): Promise<DownloadedPageResult> {
    let lastError = '';
    let previousPage: GalleryPage | null = null;
    const preview = detail.previewSet[pageIndex];
    for (let attempt = 0; attempt <= DOWNLOAD_PAGE_RETRY_LIMIT; attempt++) {
      if (this.shouldStop || this.isStopped(item.gid)) {
        throw new Error('Download stopped');
      }
      try {
        const downloaded = await this.downloadPageOnce(context, item, detail, detailUrl, pageIndex, total, state,
          attempt > 0, previousPage);
        return downloaded;
      } catch (error) {
        lastError = String(error);
        previousPage = galleryPageCache.get(preview.pageUrl);
        ehAppLog.warn(context, 'DownloadManager', 'Page attempt failed gid=' + item.gid.toString() +
          ', page=' + (pageIndex + 1).toString() + '/' + total.toString() + ', attempt=' +
          (attempt + 1).toString() + '/' + (DOWNLOAD_PAGE_RETRY_LIMIT + 1).toString() + ': ' + lastError);
        if (attempt >= DOWNLOAD_PAGE_RETRY_LIMIT) {
          break;
        }
        this.publishStatus('Retry ' + (attempt + 1).toString() + '/' + DOWNLOAD_PAGE_RETRY_LIMIT.toString() +
          ' page ' + (pageIndex + 1).toString() + ': ' + item.title);
        await wait(500 * (attempt + 1));
      }
    }
    throw new Error('Page ' + (pageIndex + 1).toString() + ' failed after ' +
      (DOWNLOAD_PAGE_RETRY_LIMIT + 1).toString() + ' attempts: ' + lastError);
  }

  private async downloadPageOnce(context: common.UIAbilityContext, item: DownloadInfo, detail: GalleryDetail,
    detailUrl: string, pageIndex: number, total: number, state: DownloadWorkerState,
    forceReloadPage: boolean = false, previousPage: GalleryPage | null = null): Promise<DownloadedPageResult> {
    const preview = detail.previewSet[pageIndex];
    if (forceReloadPage) {
      galleryPageCache.remove(preview.pageUrl);
    }
    let page = forceReloadPage ? null : galleryPageCache.get(preview.pageUrl);
    if (page === null) {
      const referer = readerPageReferer(detailUrl, detail.previewSet, pageIndex, currentGallerySite());
      const pageResult = previousPage !== null && previousPage.skipHathKey.length > 0 ?
        await this.client.skipHathAndReloadPage(previousPage.pageUrl.length > 0 ? previousPage.pageUrl : preview.pageUrl,
          previousPage.skipHathKey, currentGallerySite(), referer) :
        await this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(), referer);
      if (!pageResult.ok || pageResult.page === null) {
        throw new Error(pageResult.message);
      }
      page = pageResult.page;
      const cacheUrl = page.pageUrl.length > 0 ? page.pageUrl : preview.pageUrl;
      galleryPageCache.put(cacheUrl, page);
      galleryPageCache.put(preview.pageUrl, page);
      ehAppLog.info(context, 'DownloadManager', (forceReloadPage ? 'Reloaded' : 'Loaded') + ' page gid=' +
        item.gid.toString() + ', page=' + (pageIndex + 1).toString() + '/' + total.toString());
    }

    const imageUrl = downloadImageUrlForPage(page);
    if (imageUrl.length === 0) {
      throw new Error('Image URL missing');
    }

    const cacheKey = readerPageImageCacheKey(page, page.originImageUrl.length > 0 && imageUrl === page.originImageUrl);
    const existingCachedPath = readerImageCache.getCachedPath(context, imageUrl, cacheKey);
    let lastProgressBytes = 0;
    const onProgress = (progress: ImageDownloadProgress): void => {
      const receivedBytes = Math.max(0, progress.receivedBytes);
      const deltaBytes = Math.max(0, receivedBytes - lastProgressBytes);
      lastProgressBytes = Math.max(lastProgressBytes, receivedBytes);
      this.recordDownloadSpeed(item, state, total, deltaBytes);
    };
    const cachedPath = existingCachedPath.length > 0 ? existingCachedPath :
      await readerImageCache.ensureCached(context, imageUrl, page.pageUrl, true, onProgress, cacheKey);
    const downloadedBytes = Math.max(readerImageCache.cachedSize(context, imageUrl, cacheKey), lastProgressBytes);
    if (downloadedBytes > lastProgressBytes) {
      this.recordDownloadSpeed(item, state, total, downloadedBytes - lastProgressBytes, true);
    }
    return {
      page: page,
      cachedPath: cachedPath
    };
  }

  private recordDownloadSpeed(item: DownloadInfo, state: DownloadWorkerState, total: number, deltaBytes: number,
    force: boolean = false): void {
    if (deltaBytes > 0) {
      state.speedWindowBytes += deltaBytes;
    }
    const now = Date.now();
    const elapsedMs = Math.max(1, now - state.speedWindowStartedAt);
    if (!force && elapsedMs < 1000) {
      return;
    }
    state.currentSpeed = Math.round(state.speedWindowBytes * 1000 / elapsedMs);
    state.speedWindowBytes = 0;
    state.speedWindowStartedAt = now;
    const averageBytes = state.averagePageBytes > 0 ? state.averagePageBytes : Math.max(1, deltaBytes);
    const remaining = state.currentSpeed > 0 ?
      Math.round(Math.max(0, total - state.finished) * averageBytes / state.currentSpeed) : 0;
    ehDownloadStore.setProgress(item.gid, state.finished, total, state.finished * DOWNLOAD_PAGE_PROGRESS_SCALE);
    ehDownloadStore.setTransfer(item.gid, state.currentSpeed, remaining);
  }

  private async loadCompleteDownloadDetail(initial: GalleryDetail, referer: string): Promise<GalleryDetail> {
    let detail = cloneGalleryDetail(initial);
    if (detail.previewPages <= 1 || detail.gid <= 0 || detail.token.length === 0) {
      return detail;
    }
    for (let pageIndex = 1; pageIndex < detail.previewPages; pageIndex++) {
      const result = await this.client.loadGalleryDetail(detail.gid, detail.token, pageIndex, currentGallerySite(),
        referer);
      if (!result.ok || result.detail === null) {
        throw new Error('Preview page ' + (pageIndex + 1).toString() + ' load failed: ' + result.message);
      }
      detail = mergeGalleryPreviewSets(detail, result.detail).detail;
      this.publishStatus('Loaded preview page ' + (pageIndex + 1).toString() + '/' +
        detail.previewPages.toString() + ': ' + detail.title);
    }
    return detail;
  }

  private async startBackgroundTask(context: common.UIAbilityContext): Promise<void> {
    if (this.backgroundRunning) {
      return;
    }
    try {
      const agentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: 'yt.ehviewer.huawei',
            moduleName: 'entry',
            abilityName: 'EntryAbility'
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: DOWNLOAD_NOTIFICATION_ID,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent: WantAgent = await wantAgent.getWantAgent(agentInfo);
      const notification = await backgroundTaskManager.startBackgroundRunning(context, ['dataTransfer'], agent);
      if (notification.notificationId !== undefined) {
        this.notificationId = notification.notificationId;
      }
      this.backgroundRunning = true;
    } catch (error) {
      this.backgroundRunning = false;
    }
  }

  private async stopBackgroundTask(context: common.UIAbilityContext): Promise<void> {
    if (!this.backgroundRunning) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
    } catch (error) {
    }
    this.backgroundRunning = false;
  }

  private async publishProgress(item: DownloadInfo, finished: number, total: number): Promise<void> {
    const progress = total > 0 ? Math.max(0, Math.min(100, Math.round(finished * 100 / total))) : 0;
    try {
      if (!this.templateChecked) {
        this.templateSupported = await notificationManager.isSupportTemplate(DOWNLOAD_NOTIFICATION_TEMPLATE);
        this.templateChecked = true;
      }
      await notificationManager.addSlot(notificationManager.SlotType.OTHER_TYPES).catch(() => {});
      const request: notificationManager.NotificationRequest = {
        id: this.notificationId,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: 'EhViewer download',
            text: item.title,
            additionalText: finished.toString() + '/' + total.toString()
          }
        },
        notificationSlotType: notificationManager.SlotType.OTHER_TYPES,
        isOngoing: finished < total,
        template: this.templateSupported ? {
          name: DOWNLOAD_NOTIFICATION_TEMPLATE,
          data: {
            title: 'EhViewer download',
            fileName: item.title,
            progressValue: progress
          }
        } : undefined
      };
      await notificationManager.publish(request);
    } catch (error) {
    }
  }

  private publishStatus(status: string): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i](status);
    }
  }

  private saveDownloads(context: common.UIAbilityContext): void {
    ehDownloadStore.save(context).catch(() => {});
  }

  private addStoppedGid(gid: number): void {
    if (this.stoppedGids.indexOf(gid) < 0) {
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

  private isStopped(gid: number): boolean {
    return this.stoppedGids.indexOf(gid) >= 0;
  }
}

function downloadThreadLimitSafe(): number {
  return downloadThreadLimit();
}

export const ehDownloadManager: EhDownloadManager = new EhDownloadManager();
