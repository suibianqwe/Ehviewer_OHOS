import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { GalleryInfo } from '../model/GalleryModels';
import { REMOTE_STORAGE_PURPOSE_DOWNLOADS, remoteStorageProfileStore } from './RemoteStorageProfiles';
import { WebDavClient } from './WebDavClient';
import { logRemoteStorageInfo, logRemoteStorageWarn } from './RemoteStorageLog';

const DOWNLOADS_FOLDER: string = 'download';
const CLOUD_PAGES_FOLDER: string = 'cloud_pages';
const PAGE_FILE_PATTERN: RegExp = /^(\d{8})\.(jpg|jpeg|png|webp|gif)$/i;
const INDEX_TTL_MS: number = 5 * 60 * 1000;
const REFRESH_RETRY_MS: number = 5000;

interface CloudGalleryIndex {
  directoryName: string;
  files: Map<number, string>;
  fetchedAt: number;
}

// 仅云端画廊的按页云端读取：把远端镜像页拉取到独立的本地缓存目录，
// 下载目录保持为空，云端失败时由调用方回退到网络获取。
export class CloudGalleryPageService {
  private indexes: Map<number, CloudGalleryIndex> = new Map<number, CloudGalleryIndex>();
  private pending: Map<string, Promise<string>> = new Map<string, Promise<string>>();
  private lastResolveAt: Map<number, number> = new Map<number, number>();

  hasDownloadsProfile(): boolean {
    return remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_DOWNLOADS) !== null;
  }

  async fetchPage(context: common.UIAbilityContext, gallery: GalleryInfo, index: number): Promise<string> {
    if (gallery.gid <= 0 || index < 0) {
      return '';
    }
    const key = gallery.gid.toString() + ':' + index.toString();
    const pending = this.pending.get(key);
    if (pending !== undefined) {
      return pending;
    }
    const request = this.fetchPageInternal(context, gallery, index);
    this.pending.set(key, request);
    try {
      return await request;
    } finally {
      this.pending.delete(key);
    }
  }

  private async fetchPageInternal(context: common.UIAbilityContext, gallery: GalleryInfo,
    index: number): Promise<string> {
    const client = this.client();
    if (client === null) {
      return '';
    }
    let entry = await this.resolveIndex(context, client, gallery.gid, false);
    if (entry === null) {
      return '';
    }
    let fileName = entry.files.get(index);
    if (fileName === undefined) {
      entry = await this.resolveIndex(context, client, gallery.gid, true);
      if (entry === null) {
        return '';
      }
      fileName = entry.files.get(index);
      if (fileName === undefined) {
        return '';
      }
    }
    const localPath = this.localPagePath(context, gallery.gid, fileName);
    if (this.fileUsable(localPath)) {
      return localPath;
    }
    const remotePath = DOWNLOADS_FOLDER + '/' + entry.directoryName + '/' + fileName;
    const data = await client.getBinary(remotePath);
    if (data === null || data.byteLength === 0) {
      logRemoteStorageWarn('cloud page fetch failed gid=' + gallery.gid.toString() + ' index=' +
        index.toString() + ' path=' + remotePath);
      return '';
    }
    if (!this.writeFile(localPath, data)) {
      return '';
    }
    logRemoteStorageInfo('cloud page fetched gid=' + gallery.gid.toString() + ' index=' + index.toString() +
      ' bytes=' + data.byteLength.toString());
    return localPath;
  }

  private async resolveIndex(context: common.UIAbilityContext, client: WebDavClient, gid: number,
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

  private localPagePath(context: common.UIAbilityContext, gid: number, fileName: string): string {
    return context.filesDir + '/' + CLOUD_PAGES_FOLDER + '/' + gid.toString() + '/' + fileName;
  }

  private fileUsable(path: string): boolean {
    try {
      return fs.accessSync(path) && fs.statSync(path).size > 0;
    } catch (error) {
      return false;
    }
  }

  private writeFile(path: string, data: ArrayBuffer): boolean {
    const directory = path.substring(0, path.lastIndexOf('/'));
    const parent = directory.substring(0, directory.lastIndexOf('/'));
    try {
      fs.mkdirSync(parent);
    } catch (error) {
    }
    try {
      fs.mkdirSync(directory);
    } catch (error) {
    }
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
      fs.writeSync(file.fd, data);
      return true;
    } catch (error) {
      return false;
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (error) {
        }
      }
    }
  }
}

export const cloudGalleryPageService: CloudGalleryPageService = new CloudGalleryPageService();
