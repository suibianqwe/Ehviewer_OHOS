import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { GalleryInfo } from '../model/GalleryModels';
import { readerImageCache } from './ReaderImageCache';
import { REMOTE_STORAGE_PURPOSE_DOWNLOADS, remoteStorageProfileStore } from './RemoteStorageProfiles';
import { WebDavClient } from './WebDavClient';
import { logRemoteStorageInfo, logRemoteStorageWarn } from './RemoteStorageLog';

const DOWNLOADS_FOLDER: string = 'download';
const LEGACY_CLOUD_PAGES_FOLDER: string = 'cloud_pages';
const PAGE_FILE_PATTERN: RegExp = /^(\d{8})\.(jpg|jpeg|png|webp|gif)$/i;
const INDEX_TTL_MS: number = 5 * 60 * 1000;
const REFRESH_RETRY_MS: number = 5000;

interface CloudGalleryIndex {
  directoryName: string;
  files: Map<number, string>;
  fetchedAt: number;
}

// 仅云端画廊的按页云端读取：远端镜像页拉取后写入统一图片缓存（跟随缓存清理），
// 云端失败时由调用方回退到网络获取。
export class CloudGalleryPageService {
  private indexes: Map<number, CloudGalleryIndex> = new Map<number, CloudGalleryIndex>();
  private pending: Map<string, Promise<string>> = new Map<string, Promise<string>>();
  private lastResolveAt: Map<number, number> = new Map<number, number>();
  private legacyCleaned: boolean = false;

  hasDownloadsProfile(): boolean {
    return remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_DOWNLOADS) !== null;
  }

  async fetchPage(context: common.UIAbilityContext, gallery: GalleryInfo, index: number,
    imageUrl: string, cacheKey: string): Promise<string> {
    if (gallery.gid <= 0 || index < 0 || imageUrl.length === 0) {
      return '';
    }
    const key = gallery.gid.toString() + ':' + index.toString();
    const pending = this.pending.get(key);
    if (pending !== undefined) {
      return pending;
    }
    const request = this.fetchPageInternal(context, gallery, index, imageUrl, cacheKey);
    this.pending.set(key, request);
    try {
      return await request;
    } finally {
      this.pending.delete(key);
    }
  }

  private async fetchPageInternal(context: common.UIAbilityContext, gallery: GalleryInfo, index: number,
    imageUrl: string, cacheKey: string): Promise<string> {
    this.cleanupLegacyCache(context);
    const client = this.client();
    if (client === null) {
      return '';
    }
    let entry = await this.resolveIndex(client, gallery.gid, false);
    if (entry === null) {
      return '';
    }
    let fileName = entry.files.get(index);
    if (fileName === undefined) {
      entry = await this.resolveIndex(client, gallery.gid, true);
      if (entry === null) {
        return '';
      }
      fileName = entry.files.get(index);
      if (fileName === undefined) {
        return '';
      }
    }
    const remotePath = DOWNLOADS_FOLDER + '/' + entry.directoryName + '/' + fileName;
    const data = await client.getBinary(remotePath);
    if (data === null || data.byteLength === 0) {
      logRemoteStorageWarn('cloud page fetch failed gid=' + gallery.gid.toString() + ' index=' +
        index.toString() + ' path=' + remotePath);
      return '';
    }
    const path = readerImageCache.storeBytes(context, imageUrl, cacheKey, data, fileExtension(fileName));
    if (path.length === 0) {
      return '';
    }
    logRemoteStorageInfo('cloud page fetched gid=' + gallery.gid.toString() + ' index=' + index.toString() +
      ' bytes=' + data.byteLength.toString());
    return path;
  }

  private async resolveIndex(client: WebDavClient, gid: number,
    forceRefresh: boolean): Promise<CloudGalleryIndex | null> {
    const cached = this.indexes.get(gid);
    const now = Date.now();
    if (!forceRefresh && cached !== undefined && now - cached.fetchedAt <= INDEX_TTL_MS) {
      return cached;
    }
    const lastResolve = this.lastResolveAt.get(gid);
    if (forceRefresh && lastResolve !== undefined && now - lastResolve < REFRESH_RETRY_MS) {
      return cached !== undefined ? cached : null;
    }
    this.lastResolveAt.set(gid, now);
    const listing = await client.list(DOWNLOADS_FOLDER);
    if (!listing.ok) {
      return cached !== undefined ? cached : null;
    }
    const prefix = gid.toString() + '-';
    let directoryName = '';
    for (let i = 0; i < listing.entries.length; i++) {
      if (listing.entries[i].isDirectory && listing.entries[i].name.indexOf(prefix) === 0) {
        directoryName = listing.entries[i].name;
        break;
      }
    }
    if (directoryName.length === 0) {
      return null;
    }
    const files = await client.list(DOWNLOADS_FOLDER + '/' + directoryName);
    if (!files.ok) {
      return cached !== undefined ? cached : null;
    }
    const byIndex: Map<number, string> = new Map<number, string>();
    for (let i = 0; i < files.entries.length; i++) {
      const entry = files.entries[i];
      if (entry.isDirectory) {
        continue;
      }
      const match = PAGE_FILE_PATTERN.exec(entry.name);
      if (match === null) {
        continue;
      }
      const pageIndex = Number.parseInt(match[1]) - 1;
      if (pageIndex >= 0) {
        byIndex.set(pageIndex, entry.name);
      }
    }
    const resolved: CloudGalleryIndex = {
      directoryName: directoryName,
      files: byIndex,
      fetchedAt: now
    };
    this.indexes.set(gid, resolved);
    return resolved;
  }

  private client(): WebDavClient | null {
    const profile = remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_DOWNLOADS);
    return profile === null ? null : new WebDavClient(profile);
  }

  private cleanupLegacyCache(context: common.UIAbilityContext): void {
    if (this.legacyCleaned) {
      return;
    }
    this.legacyCleaned = true;
    try {
      fs.rmdirSync(context.filesDir + '/' + LEGACY_CLOUD_PAGES_FOLDER);
    } catch (error) {
    }
  }
}

function fileExtension(fileName: string): string {
  const index = fileName.lastIndexOf('.');
  return index >= 0 ? fileName.substring(index).toLowerCase() : '';
}

export const cloudGalleryPageService: CloudGalleryPageService = new CloudGalleryPageService();
