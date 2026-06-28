import { GalleryDetail, GalleryInfo, GalleryPage, GalleryPreview, GallerySite } from '../model/GalleryModels';
import { ehDownloadManager } from './EhDownloadManager';
import { DownloadInfo, DownloadState, ehDownloadStore } from './EhDownloadStore';
import { createReaderSessionState, ReaderSessionState } from './ReaderSessionStore';
import {
  cloneGalleryDetail,
  cloneGalleryPreviews,
  createDetailFromGallery,
  createEmptyPage,
  downloadStateLabel,
  saveDownloadsQuietly
} from '../shared/EhShared';

export interface DetailDownloadToggleResult {
  item: DownloadInfo | null;
  buttonText: string;
  statusText: string;
  shouldStartQueue: boolean;
}

export function findDetailDownloadItem(gid: number): DownloadInfo | null {
  const items = ehDownloadStore.getItems();
  for (let i = 0; i < items.length; i++) {
    if (items[i].gid === gid) {
      return items[i];
    }
  }
  return null;
}

export function detailDownloadButtonText(gid: number): string {
  const item = findDetailDownloadItem(gid);
  if (item === null) {
    return 'Download';
  }
  return downloadStateLabel(item.state);
}

export function toggleDetailDownloadTask(gallery: GalleryInfo): DetailDownloadToggleResult {
  if (gallery.gid <= 0 || gallery.token.length === 0) {
    return {
      item: null,
      buttonText: 'Download',
      statusText: 'Download needs a loaded gallery',
      shouldStartQueue: false
    };
  }

  const current = findDetailDownloadItem(gallery.gid);
  if (current === null) {
    const added = ehDownloadStore.addGallery(gallery, '');
    if (added === null) {
      return {
        item: null,
        buttonText: 'Download',
        statusText: 'Download needs a loaded gallery',
        shouldStartQueue: false
      };
    }
    ehDownloadManager.resumeGallery(added.gid);
    saveDownloadsQuietly();
    return {
      item: findDetailDownloadItem(added.gid),
      buttonText: detailDownloadButtonText(added.gid),
      statusText: 'Added to download list and started',
      shouldStartQueue: true
    };
  }

  if (current.state === DownloadState.Wait || current.state === DownloadState.Downloading) {
    ehDownloadManager.stopGallery(current.gid);
    saveDownloadsQuietly();
    return {
      item: findDetailDownloadItem(current.gid),
      buttonText: detailDownloadButtonText(current.gid),
      statusText: 'Download stopped',
      shouldStartQueue: false
    };
  }

  ehDownloadStore.updateGallery(gallery);
  ehDownloadManager.resumeGallery(current.gid);
  saveDownloadsQuietly();
  return {
    item: findDetailDownloadItem(current.gid),
    buttonText: detailDownloadButtonText(current.gid),
    statusText: current.state === DownloadState.Finish ? 'Download queued for update' : 'Download queued',
    shouldStartQueue: true
  };
}

export function refreshDetailDownloadItem(detail: GalleryDetail): void {
  if (findDetailDownloadItem(detail.gid) === null) {
    return;
  }
  ehDownloadStore.updateGallery(detail);
  saveDownloadsQuietly();
}

export function createDownloadReaderSessionState(item: DownloadInfo, requestedIndex: number, site: GallerySite,
  detailRequestUrl: string = '', listRequestUrl: string = '', loadedDetail?: GalleryDetail): ReaderSessionState {
  const detail = createReaderDetailForDownload(item, loadedDetail);
  const total = Math.max(detail.pages, detail.previewSet.length, 1);
  const index = requestedIndex >= 0 && requestedIndex < total ? requestedIndex : 0;
  const page: GalleryPage = createEmptyPage();
  return createReaderSessionState(detail, page, 'Reader is ready', detailRequestUrl, listRequestUrl, site, index);
}

function createReaderDetailForDownload(item: DownloadInfo, loadedDetail?: GalleryDetail): GalleryDetail {
  let detail = loadedDetail === undefined || loadedDetail.gid !== item.gid ? createDetailFromGallery(item) :
    mergeDownloadedDetail(loadedDetail, item);
  const total = Math.max(detail.pages, item.total, item.pages, item.finished, detail.previewSet.length, 1);
  detail.pages = total;
  detail.previewPages = Math.max(detail.previewPages, 1);
  detail.previewSet = createDownloadReaderPreviews(detail, total);
  return detail;
}

function mergeDownloadedDetail(detail: GalleryDetail, item: DownloadInfo): GalleryDetail {
  const next = cloneGalleryDetail(detail);
  if (next.title.length === 0 && item.title.length > 0) {
    next.title = item.title;
  }
  if ((next.titleJpn === undefined || next.titleJpn.length === 0) && item.titleJpn !== undefined &&
    item.titleJpn.length > 0) {
    next.titleJpn = item.titleJpn;
  }
  if ((next.thumb === undefined || next.thumb.length === 0) && item.thumb !== undefined && item.thumb.length > 0) {
    next.thumb = item.thumb;
  }
  return next;
}

function createDownloadReaderPreviews(detail: GalleryDetail, total: number): GalleryPreview[] {
  const existing = cloneGalleryPreviews(detail.previewSet);
  const previews: GalleryPreview[] = [];
  for (let i = 0; i < total; i++) {
    const preview = previewForIndex(existing, i);
    previews.push({
      index: i,
      pageUrl: preview === null ? 'ehviewer://download/' + detail.gid.toString() + '/' + i.toString() : preview.pageUrl,
      imageUrl: preview === null ? '' : preview.imageUrl,
      width: preview === null ? 0 : preview.width,
      height: preview === null ? 0 : preview.height,
      xOffset: preview === null ? 0 : preview.xOffset,
      yOffset: preview === null ? 0 : preview.yOffset
    });
  }
  return previews;
}

function previewForIndex(previews: GalleryPreview[], index: number): GalleryPreview | null {
  for (let i = 0; i < previews.length; i++) {
    if (previews[i].index === index) {
      return previews[i];
    }
  }
  return null;
}
