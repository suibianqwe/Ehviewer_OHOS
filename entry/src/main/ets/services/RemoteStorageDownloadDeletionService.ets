import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ehDownloadFileStore } from './EhDownloadFileStore';
import { DownloadInfo, ehDownloadStore } from './EhDownloadStore';

import { logRemoteStorageInfo } from './RemoteStorageLog';
import { RemoteStorageProfile, remoteStorageProfileStore, REMOTE_STORAGE_PURPOSE_DOWNLOADS } from './RemoteStorageProfiles';
import { WebDavClient } from './WebDavClient';

const PREFERENCES_NAME: string = 'ehviewer_download_deletions';
const PENDING_KEY: string = 'pending';
const TOMBSTONES_FILE: string = 'sync/download_tombstones.json';
const DOWNLOAD_FOLDER: string = 'download';
const MANIFEST_FILE: string = 'download/manifest.json';
const DOWNLOAD_MANIFEST_INDEX: string = 'download/manifests.json';

export interface PendingCloudDeletion {
  gid: number;
  deletedAt: number;
  directoryName: string;
}

interface DownloadTombstone {
  gid: number;
  deletedAt: number;
  deviceId: string;
}

/**
 * Local deletion queue for download items. Local removal happens immediately and a tombstone is
 * recorded locally; the cloud directory removal and the tombstone upload are retried on every
 * sync cycle until the server confirms them.
 */
export class RemoteStorageDownloadDeletionService {
  private pending: PendingCloudDeletion[] = [];
  private loaded: boolean = false;
  private context: common.UIAbilityContext | null = null;

  async ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.context = context;
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const raw = await prefs.get(PENDING_KEY, '[]');
      const parsed = JSON.parse(typeof raw === 'string' ? raw : '[]') as PendingCloudDeletion[];
      this.pending = Array.isArray(parsed) ? parsed : [];
    } catch (error) {
      this.pending = [];
    }
    this.loaded = true;
  }

  getPendingCount(): number {
    return this.pending.length;
  }

  hasLocalCopy(context: common.UIAbilityContext, gid: number): boolean {
    return this.findLocalDirectoryName(context, gid).length > 0;
  }

  localDirectoryName(context: common.UIAbilityContext, gid: number): string {
    return this.findLocalDirectoryName(context, gid);
  }

  async recordCloudDeletion(context: common.UIAbilityContext, gid: number, directoryName: string): Promise<void> {
    await this.ensureLoaded(context);
    this.context = context;
    const next: PendingCloudDeletion[] = [];
    for (let i = 0; i < this.pending.length; i++) {
      if (this.pending[i].gid !== gid) {
        next.push(this.pending[i]);
      }
    }
    next.push({ gid: gid, deletedAt: Date.now(), directoryName: directoryName });
    this.pending = next;
    await this.persist();
  }

  async processPendingDeletions(context: common.UIAbilityContext): Promise<void> {
    await this.ensureLoaded(context);
    if (this.pending.length === 0) {
      return;
    }
    const profile = remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_DOWNLOADS);
    if (profile === null) {
      return;
    }
    const client = new WebDavClient(profile);
    await this.processPendingWithClient(context, client, profile);
  }

  async processPendingWithClient(context: common.UIAbilityContext, client: WebDavClient,
    profile: RemoteStorageProfile): Promise<void> {
    if (this.pending.length === 0) {
      return;
    }
    const remaining: PendingCloudDeletion[] = [];
    for (let i = 0; i < this.pending.length; i++) {
      const deletion = this.pending[i];
      const directoryName = deletion.directoryName.length > 0 ? deletion.directoryName : this.findLocalDirectoryName(context, deletion.gid);
      if (directoryName.length > 0) {
        const removed = await client.deleteFile(DOWNLOAD_FOLDER + '/' + directoryName);
        if (!removed.ok) {
          remaining.push(deletion);
          continue;
        }
        await this.removeManifestEntries(client, directoryName);
      }
      const uploaded = await this.mergeRemoteTombstone(client, deletion, profile);
      if (!uploaded) {
        remaining.push(deletion);
      }
    }
    this.pending = remaining;
    await this.persist();
  }

  async applyRemoteTombstones(context: common.UIAbilityContext, client: WebDavClient): Promise<void> {
    const text = await client.getText(TOMBSTONES_FILE);
    if (!text.ok || text.text.length === 0) {
      return;
    }
    let tombstones: DownloadTombstone[] = [];
    try {
      tombstones = JSON.parse(text.text) as DownloadTombstone[];
    } catch (error) {
      return;
    }
    if (!Array.isArray(tombstones) || tombstones.length === 0) {
      return;
    }
    let changed = false;
    const kept: DownloadTombstone[] = [];
    for (let i = 0; i < tombstones.length; i++) {
      const tombstone = tombstones[i];
      if (typeof tombstone.gid !== 'number' || typeof tombstone.deletedAt !== 'number') {
        continue;
      }
      let item: DownloadInfo | null = null;
      const items = ehDownloadStore.getItems();
      for (let k = 0; k < items.length; k++) {
        if (items[k].gid === tombstone.gid) {
          item = items[k];
          break;
        }
      }
      if (item === null) {
        kept.push(tombstone);
        continue;
      }
      if (tombstone.deletedAt > item.time) {
        ehDownloadFileStore.removeGalleryDirectory(context, item);
        ehDownloadStore.removeGallery(tombstone.gid);
        changed = true;
        logRemoteStorageInfo('download deletion applied gid=' + tombstone.gid.toString());
      } else {
        // Re-downloaded after the deletion: drop the tombstone and re-upload the gallery later.
        changed = true;
        logRemoteStorageInfo('download deletion discarded (newer local) gid=' + tombstone.gid.toString());
      }
    }
    if (changed) {
      await ehDownloadStore.save(context);
      await client.putText(TOMBSTONES_FILE, JSON.stringify(kept));
    }
  }

  private async removeManifestEntries(client: WebDavClient, directoryName: string): Promise<void> {
    // 新版分片索引：删除该画廊的分片并重写索引。
    const indexText = await client.getText(DOWNLOAD_MANIFEST_INDEX);
    if (indexText.ok && indexText.text.length > 0) {
      try {
        const index = JSON.parse(indexText.text) as ManifestIndexShape;
        if (Array.isArray(index.shards)) {
          const kept: ManifestShardShape[] = [];
          let removed = false;
          const prefix = 'manifests/' + directoryName + '~';
          for (let i = 0; i < index.shards.length; i++) {
            if (index.shards[i].path.indexOf(prefix) >= 0) {
              await client.deleteFile(index.shards[i].path);
              removed = true;
            } else {
              kept.push(index.shards[i]);
            }
          }
          if (removed) {
            const nextIndex: ManifestIndexShape = { version: 2, updatedAt: Date.now(), shards: kept };
            await client.putText(DOWNLOAD_MANIFEST_INDEX, JSON.stringify(nextIndex));
          }
          return;
        }
      } catch (error) {
      }
    }
    const manifestText = await client.getText(MANIFEST_FILE);
    if (!manifestText.ok || manifestText.text.length === 0) {
      return;
    }
    try {
      const parsed = JSON.parse(manifestText.text) as ManifestShape;
      if (!Array.isArray(parsed.files)) {
        return;
      }
      const prefix = directoryName + '/';
      const kept: ManifestEntryShape[] = [];
      for (let i = 0; i < parsed.files.length; i++) {
        if (parsed.files[i].path.indexOf(prefix) !== 0) {
          kept.push(parsed.files[i]);
        }
      }
      const nextManifest: ManifestShape = { version: 1, updatedAt: Date.now(), files: kept };
      await client.putText(MANIFEST_FILE, JSON.stringify(nextManifest));
    } catch (error) {
    }
  }

  private async mergeRemoteTombstone(client: WebDavClient, deletion: PendingCloudDeletion,
    profile: RemoteStorageProfile): Promise<boolean> {
    const deviceId = '';
    const text = await client.getText(TOMBSTONES_FILE);
    let tombstones: DownloadTombstone[] = [];
    if (text.ok && text.text.length > 0) {
      try {
        const parsed = JSON.parse(text.text) as DownloadTombstone[];
        if (Array.isArray(parsed)) {
          tombstones = parsed;
        }
      } catch (error) {
      }
    }
    const next: DownloadTombstone[] = [];
    let replaced = false;
    for (let i = 0; i < tombstones.length; i++) {
      if (tombstones[i].gid === deletion.gid) {
        if (tombstones[i].deletedAt >= deletion.deletedAt) {
          return true;
        }
        replaced = true;
        next.push({ gid: deletion.gid, deletedAt: deletion.deletedAt, deviceId: deviceId });
      } else {
        next.push(tombstones[i]);
      }
    }
    if (!replaced) {
      next.push({ gid: deletion.gid, deletedAt: deletion.deletedAt, deviceId: deviceId });
    }
    const uploaded = await client.putText(TOMBSTONES_FILE, JSON.stringify(next));
    return uploaded.ok;
  }

  private directoryCache: string[] = [];
  private directoryCacheAt: number = 0;

  private findLocalDirectoryName(context: common.UIAbilityContext, gid: number): string {
    if (Date.now() - this.directoryCacheAt > 2000) {
      try {
        this.directoryCache = fs.listFileSync(ehDownloadFileStore.appDownloadRoot(context));
      } catch (error) {
        this.directoryCache = [];
      }
      this.directoryCacheAt = Date.now();
    }
    const prefix = gid.toString() + '-';
    for (let i = 0; i < this.directoryCache.length; i++) {
      if (this.directoryCache[i].indexOf(prefix) === 0) {
        return this.directoryCache[i];
      }
    }
    return '';
  }

  invalidateDirectoryCache(): void {
    this.directoryCacheAt = 0;
  }

  private async persist(): Promise<void> {
    const context = this.context;
    if (context === null) {
      return;
    }
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(PENDING_KEY, JSON.stringify(this.pending));
      await prefs.flush();
    } catch (error) {
    }
  }
}

interface ManifestEntryShape {
  path: string;
  size: number;
  mtime: number;
}

interface ManifestShape {
  version: number;
  updatedAt: number;
  files: ManifestEntryShape[];
}

interface ManifestShardShape {
  path: string;
  time: number;
}

interface ManifestIndexShape {
  version: number;
  updatedAt: number;
  shards: ManifestShardShape[];
}

export const remoteStorageDownloadDeletionService = new RemoteStorageDownloadDeletionService();
