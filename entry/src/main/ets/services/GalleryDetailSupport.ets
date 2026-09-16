import {
  GalleryDetail,
  GalleryInfo,
  GallerySite,
  GalleryCategory,
  GalleryTagGroup,
  GalleryPage,
  GalleryPreview,
} from '../model/GalleryModels';
import {
  createDetailFromGallery,
  createEmptyGallery,
  cloneGalleryDetail,
  cloneGalleryInfo,
  cloneGalleryPreviews,
  createEmptyPage,
  downloadStateLabel,
  getAbilityContext,
  saveDownloadsQuietly,
} from '../shared/EhShared';
import {
  EhHttpClient,
  GalleryDetailLoadResult,
} from './EhHttpClient';
import {
  EhUrl,
  ListMode,
} from './EhUrl';
import {
  ehDownloadManager,
} from './EhDownloadManager';
import {
  DownloadInfo,
  DownloadState,
  ehDownloadStore,
} from './EhDownloadStore';
import {
  createReaderSessionState,
  ReaderSessionState,
} from './ReaderSessionStore';
import { cloudGalleryPageService } from './CloudGalleryPageService';
import { remoteStorageDownloadDeletionService } from './RemoteStorageDownloadDeletionService';

export interface GalleryDetailLink {
  gid: number;
  token: string;
  url: string;
  referer: string;
  site: GallerySite;
  seed: GalleryInfo;
}

export interface GalleryDetailModuleLoadResult {
  ok: boolean;
  url: string;
  statusText: string;
  detail: GalleryDetail;
}

interface ParsedGalleryDetailUrl {
  gid: number;
  token: string;
}

export function createEmptyGalleryDetailLink(): GalleryDetailLink {
  return {
    gid: 0,
    token: '',
    url: '',
    referer: '',
    site: GallerySite.E,
    seed: createEmptyGallery()
  };
}

export function createGalleryDetailLinkFromGallery(gallery: GalleryInfo, site: GallerySite,
  referer: string = ''): GalleryDetailLink {
  const url = EhUrl.getGalleryDetailUrl(gallery.gid, gallery.token, 0, false, site);
  return {
    gid: gallery.gid,
    token: gallery.token,
    url: url,
    referer: referer.length > 0 ? referer : EhUrl.getReferer(site),
    site: site,
    seed: gallery
  };
}

export function createGalleryDetailLink(gid: number, token: string, title: string, site: GallerySite,
  referer: string = ''): GalleryDetailLink {
  const seed = createEmptyGallery();
  seed.gid = gid;
  seed.token = token;
  seed.title = title;
  return createGalleryDetailLinkFromGallery(seed, site, referer);
}

export function createGalleryDetailLinkFromUrl(url: string, site: GallerySite, referer: string = '',
  seed?: GalleryInfo): GalleryDetailLink | null {
  const parsed = parseGalleryDetailUrl(url);
  if (parsed === null) {
    return null;
  }
  const source = seed === undefined ? createEmptyGallery() : cloneGalleryInfo(seed);
  source.gid = parsed.gid;
  source.token = parsed.token;
  return {
    gid: parsed.gid,
    token: parsed.token,
    url: url,
    referer: referer.length > 0 ? referer : EhUrl.getReferer(site),
    site: site,
    seed: source
  };
}

export function initialDetailForLink(link: GalleryDetailLink): GalleryDetail {
  return createDetailFromGallery(link.seed);
}

export async function loadGalleryDetailModule(client: EhHttpClient,
  link: GalleryDetailLink): Promise<GalleryDetailModuleLoadResult> {
  const initial = initialDetailForLink(link);
  const result: GalleryDetailLoadResult = await client.loadGalleryDetail(link.gid, link.token, 0, link.site,
    link.referer);
  if (!result.ok || result.detail === null) {
    return {
      ok: false,
      url: result.url.length > 0 ? result.url : link.url,
      statusText: 'Detail load failed: ' + result.message,
      detail: initial
    };
  }
  return {
    ok: true,
    url: result.url.length > 0 ? result.url : link.url,
    statusText: 'Detail loaded',
    detail: mergeLoadedGalleryDetail(result.detail, initial)
  };
}

function mergeLoadedGalleryDetail(loaded: GalleryDetail, previous: GalleryDetail): GalleryDetail {
  const next = cloneGalleryDetail(loaded);
  if (next.title.length === 0 && previous.title.length > 0) {
    next.title = previous.title;
  }
  if ((next.titleJpn === undefined || next.titleJpn.length === 0) && previous.titleJpn !== undefined &&
    previous.titleJpn.length > 0) {
    next.titleJpn = previous.titleJpn;
  }
  if ((next.thumb === undefined || next.thumb.length === 0) && previous.thumb !== undefined &&
    previous.thumb.length > 0) {
    next.thumb = previous.thumb;
  }
  if ((next.thumb === undefined || next.thumb.length === 0) && next.previewSet.length > 0) {
    next.thumb = next.previewSet[0].imageUrl;
  }
  return next;
}

function parseGalleryDetailUrl(url: string): ParsedGalleryDetailUrl | null {
  const match = /\/g\/(\d+)\/([^\/?#]+)/i.exec(url);
  if (match === null) {
    return null;
  }
  const gid = Number.parseInt(match[1], 10);
  const token = match[2];
  if (!Number.isFinite(gid) || gid <= 0 || token.length === 0) {
    return null;
  }
  return { gid: gid, token: token };
}

export interface DetailSearchRequest {
  title: string;
  keyword: string;
  mode: ListMode;
  category: number;
  imagePath: string;
  useSimilarityScan: boolean;
  onlySearchCovers: boolean;
  showExpunged: boolean;
}

export function createTagSearchRequest(namespace: string, tag: string): DetailSearchRequest | null {
  const trimmedNamespace = namespace.trim();
  const trimmedTag = tag.trim();
  if (trimmedNamespace.length === 0 || trimmedTag.length === 0) {
    return null;
  }
  const keyword = trimmedNamespace + ':' + trimmedTag.replace(/\$+$/, '').trim() + '$';
  return createKeywordSearchRequest(keyword, ListMode.Tag, trimmedNamespace + ':' + trimmedTag);
}

export function createSimilarGallerySearch(detail: GalleryDetail): DetailSearchRequest | null {
  const title = extractSimilarTitle(detail.title);
  if (title.length > 0) {
    return createKeywordSearchRequest('"' + title + '"', ListMode.Normal, 'Similar');
  }
  const artist = firstArtistTag(detail.tags);
  if (artist.length > 0) {
    return createKeywordSearchRequest('artist:' + artist.replace(/\$+$/, '').trim() + '$', ListMode.Tag, 'Similar');
  }
  if (detail.uploader !== undefined && detail.uploader.length > 0) {
    return createKeywordSearchRequest(detail.uploader, ListMode.Uploader, 'Similar');
  }
  return null;
}

export function createCoverSearchRequest(imagePath: string): DetailSearchRequest {
  return {
    title: 'Search cover',
    keyword: '',
    mode: ListMode.ImageSearch,
    category: GalleryCategory.None,
    imagePath: imagePath,
    useSimilarityScan: true,
    onlySearchCovers: false,
    showExpunged: true
  };
}

export function createKeywordSearchRequest(keyword: string, mode: ListMode, title: string): DetailSearchRequest {
  return {
    title: title.length > 0 ? title : 'Search',
    keyword: keyword,
    mode: mode,
    category: GalleryCategory.None,
    imagePath: '',
    useSimilarityScan: false,
    onlySearchCovers: false,
    showExpunged: false
  };
}

export function createUploaderSearchRequest(uploader: string): DetailSearchRequest | null {
  const value = uploader.trim();
  if (value.length === 0) {
    return null;
  }
  return createKeywordSearchRequest(value, ListMode.Uploader, value);
}

export function createCategorySearchRequest(category: number, title: string): DetailSearchRequest {
  return {
    title: title.length > 0 ? title : 'Search',
    keyword: '',
    mode: ListMode.Normal,
    category: category,
    imagePath: '',
    useSimilarityScan: false,
    onlySearchCovers: false,
    showExpunged: false
  };
}

export function archiveUnavailableReason(detailLoaded: boolean, detail: GalleryDetail): string {
  if (!detailLoaded || detail.gid <= 0 || detail.archiveUrl.length === 0) {
    return 'Archive needs a loaded gallery';
  }
  if (detail.apiUid < 0) {
    return 'Sign in first';
  }
  return '';
}

export function detailArchiveReferer(detail: GalleryDetail, site: GallerySite): string {
  return detail.archiveUrl.length > 0 ? detail.archiveUrl :
    EhUrl.getGalleryDetailUrl(detail.gid, detail.token, 0, false, site);
}

export function detailCoverCacheKey(detail: GalleryDetail): string {
  return 'cover-search-' + detail.gid.toString();
}

function extractSimilarTitle(title: string): string {
  let value = title
    .replace(/^(?:(?:\([^\)]*\))|(?:\[[^\]]*\])|(?:\{[^\}]*\})|(?:~[^~]*~)|\s+)*/g, '')
    .replace(/(?:\s+ch\.[\s\d-]+)?(?:(?:\([^\)]*\))|(?:\[[^\]]*\])|(?:\{[^\}]*\})|(?:~[^~]*~)|\s+)*$/gi, '');
  const splitIndex = value.indexOf('|');
  if (splitIndex >= 0) {
    value = value.substring(0, splitIndex);
  }
  return value.trim();
}

function firstArtistTag(groups: GalleryTagGroup[]): string {
  for (let i = 0; i < groups.length; i++) {
    if (groups[i].namespace === 'artist' && groups[i].tags.length > 0) {
      return groups[i].tags[0];
    }
  }
  return '';
}

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

export function isDetailCloudOnlyDownload(gid: number): boolean {
  if (gid <= 0 || !ehDownloadStore.contains(gid) || !cloudGalleryPageService.hasDownloadsProfile()) {
    return false;
  }
  const context = getAbilityContext();
  if (context === undefined) {
    return false;
  }
  return !remoteStorageDownloadDeletionService.hasLocalCopy(context, gid);
}

export function detailDownloadButtonText(gid: number): string {
  const item = findDetailDownloadItem(gid);
  if (item === null) {
    return 'Download';
  }
  if (isDetailCloudOnlyDownload(gid)) {
    return 'Download to local';
  }
  return downloadStateLabel(item.state);
}

export function toggleDetailDownloadTask(gallery: GalleryInfo, label: string = ''): DetailDownloadToggleResult {
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
    const added = ehDownloadStore.addGallery(gallery, label);
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
