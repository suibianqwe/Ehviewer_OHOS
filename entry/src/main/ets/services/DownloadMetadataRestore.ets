import { common } from '@kit.AbilityKit';
import { GalleryDetail, GalleryInfo, GallerySite } from '../model/GalleryModels';
import { RestoredDownloadGallery, ehDownloadFileStore } from './EhDownloadFileStore';
import { DownloadInfo, ehDownloadStore } from './EhDownloadStore';
import { ehHistoryStore } from './EhHistoryStore';
import { EhHttpClient, GalleryDetailLoadResult } from './EhHttpClient';
import { EhUrl } from './EhUrl';

export interface DownloadMetadataRestoreResult {
  rebuilt: number;
  fetched: number;
  failed: number;
}

export async function rebuildRestoredDownloadMetadata(context: common.UIAbilityContext,
  restored: RestoredDownloadGallery[], site: GallerySite): Promise<DownloadMetadataRestoreResult> {
  const result: DownloadMetadataRestoreResult = { rebuilt: 0, fetched: 0, failed: 0 };
  await ehHistoryStore.ensureLoaded(context);
  const downloadItems = ehDownloadStore.getItems();
  const historyItems = ehHistoryStore.getItems();
  const client = new EhHttpClient();

  for (let i = 0; i < restored.length; i++) {
    let gallery: GalleryInfo = bestLocalMetadata(restored[i].gallery, downloadItems, historyItems);
    if (!hasGalleryTags(gallery)) {
      const detail = await fetchDetail(client, gallery, site);
      if (detail !== null) {
        gallery = mergeGalleryMetadata(detail, gallery);
        result.fetched++;
      } else {
        result.failed++;
      }
    }

    try {
      ehDownloadFileStore.rewriteGalleryMetadataForDirectory(restored[i].directory, gallery);
      restored[i].gallery = gallery;
      result.rebuilt++;
    } catch (error) {
      result.failed++;
    }
  }
  return result;
}

export async function rebuildImportedHistoryMetadata(context: common.UIAbilityContext, imported: GalleryInfo[],
  site: GallerySite): Promise<DownloadMetadataRestoreResult> {
  const result: DownloadMetadataRestoreResult = { rebuilt: 0, fetched: 0, failed: 0 };
  if (imported.length <= 0) {
    return result;
  }
  await ehHistoryStore.ensureLoaded(context);
  const downloadItems = ehDownloadStore.getItems();
  const historyItems = ehHistoryStore.getItems();
  const client = new EhHttpClient();

  for (let i = 0; i < imported.length; i++) {
    if (imported[i].gid <= 0 || imported[i].token.length === 0) {
      continue;
    }
    let gallery: GalleryInfo = bestLocalMetadata(imported[i], downloadItems, historyItems);
    if (!hasGalleryTags(gallery)) {
      const detail = await fetchDetail(client, gallery, site);
      if (detail !== null) {
        gallery = mergeGalleryMetadata(detail, gallery);
        result.fetched++;
      } else {
        result.failed++;
      }
    }
    if (ehHistoryStore.updateGallery(gallery)) {
      result.rebuilt++;
    } else {
      result.failed++;
    }
  }
  await ehHistoryStore.save(context);
  return result;
}

function bestLocalMetadata(seed: GalleryInfo, downloadItems: DownloadInfo[], historyItems: GalleryInfo[]): GalleryInfo {
  let best: GalleryInfo = seed;
  const download = findGallery(downloadItems, seed.gid);
  if (download !== null && metadataScore(download) > metadataScore(best)) {
    best = mergeGalleryMetadata(download, best);
  }
  const history = findGallery(historyItems, seed.gid);
  if (history !== null && metadataScore(history) > metadataScore(best)) {
    best = mergeGalleryMetadata(history, best);
  }
  return mergeGalleryMetadata(best, seed);
}

async function fetchDetail(client: EhHttpClient, gallery: GalleryInfo, site: GallerySite): Promise<GalleryDetail | null> {
  const response: GalleryDetailLoadResult = await client.loadGalleryDetail(gallery.gid, gallery.token, 0, site,
    EhUrl.getReferer(site));
  if (!response.ok || response.detail === null) {
    return null;
  }
  return response.detail;
}

function findGallery(items: GalleryInfo[], gid: number): GalleryInfo | null {
  for (let i = 0; i < items.length; i++) {
    if (items[i].gid === gid) {
      return items[i];
    }
  }
  return null;
}

function metadataScore(gallery: GalleryInfo): number {
  let score = 0;
  if (gallery.title.length > 0) {
    score += 1;
  }
  if (gallery.thumb !== undefined && gallery.thumb.length > 0) {
    score += 2;
  }
  if (gallery.uploader !== undefined && gallery.uploader.length > 0) {
    score += 2;
  }
  if (gallery.simpleTags !== undefined) {
    score += gallery.simpleTags.length * 4;
  }
  if (gallery.tagList !== undefined) {
    score += gallery.tagList.length * 6;
  }
  const tags = detailTags(gallery);
  if (tags !== undefined) {
    for (let i = 0; i < tags.length; i++) {
      score += 10 + tags[i].tags.length * 8;
    }
  }
  return score;
}

function hasGalleryTags(gallery: GalleryInfo): boolean {
  if (gallery.simpleTags !== undefined && gallery.simpleTags.length > 0) {
    return true;
  }
  if (gallery.tagList !== undefined && gallery.tagList.length > 0) {
    return true;
  }
  const tags = detailTags(gallery);
  if (tags === undefined) {
    return false;
  }
  for (let i = 0; i < tags.length; i++) {
    if (tags[i].tags.length > 0) {
      return true;
    }
  }
  return false;
}

function detailTags(gallery: GalleryInfo) {
  const detail = gallery as GalleryDetail;
  if (detail.tags !== undefined && detail.tags.length > 0) {
    return detail.tags;
  }
  return gallery.detailTags;
}

function mergeGalleryMetadata(primary: GalleryInfo, fallback: GalleryInfo): GalleryInfo {
  const merged = primary as GalleryDetail;
  if (merged.title.length === 0) {
    merged.title = fallback.title;
  }
  if ((merged.titleJpn === undefined || merged.titleJpn.length === 0) && fallback.titleJpn !== undefined) {
    merged.titleJpn = fallback.titleJpn;
  }
  if ((merged.thumb === undefined || merged.thumb.length === 0) && fallback.thumb !== undefined) {
    merged.thumb = fallback.thumb;
  }
  if ((merged.posted === undefined || merged.posted.length === 0) && fallback.posted !== undefined) {
    merged.posted = fallback.posted;
  }
  if ((merged.uploader === undefined || merged.uploader.length === 0) && fallback.uploader !== undefined) {
    merged.uploader = fallback.uploader;
  }
  if (merged.pages <= 0) {
    merged.pages = fallback.pages;
  }
  if ((merged.simpleTags === undefined || merged.simpleTags.length === 0) && fallback.simpleTags !== undefined) {
    merged.simpleTags = fallback.simpleTags;
  }
  if ((merged.tagList === undefined || merged.tagList.length === 0) && fallback.tagList !== undefined) {
    merged.tagList = fallback.tagList;
  }
  if ((merged.detailTags === undefined || merged.detailTags.length === 0) && fallback.detailTags !== undefined) {
    merged.detailTags = fallback.detailTags;
  }
  if ((merged.detailLanguage === undefined || merged.detailLanguage.length === 0) &&
    fallback.detailLanguage !== undefined) {
    merged.detailLanguage = fallback.detailLanguage;
  }
  return merged;
}
