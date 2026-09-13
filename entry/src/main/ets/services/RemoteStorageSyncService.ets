import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ehBookmarkStore, SearchBookmarkBackupInfo } from './EhBookmarkStore';
import { ehBrowsePositionStore, BrowsePositionsBackupInfo } from './EhBrowsePositionStore';
import { ehCommentBlacklistStore, CommentBlacklistBackupEntry } from './EhCommentBlacklistStore';
import { ehFilterStore } from './EhFilterStore';
import { ehLocalFavoritesStore, LocalFavoriteBackupInfo } from './EhLocalFavoritesStore';
import { ehHistoryStore, ReadingProgressBackupInfo } from './EhHistoryStore';
import { ehSearchHistoryStore } from './EhSearchHistoryStore';
import { ehSettingsStore, HISTORY_INFO_SIZE_KEY, historyInfoSizeLimitFromValue, SettingEntry } from './EhSettingsStore';
import { REMOTE_STORAGE_PURPOSE_SYNC, RemoteStorageProfile, remoteStorageProfileStore } from './RemoteStorageProfiles';
import { logRemoteStorageError, logRemoteStorageInfo, logRemoteStorageWarn } from './RemoteStorageLog';
import { RemoteStorageResult, WebDavClient } from './WebDavClient';
import { RemoteStorageListEntry } from './RemoteStorageSupport';
import { ehDownloadFileStore } from './EhDownloadFileStore';
import { fileIo as fs } from '@kit.CoreFileKit';
import { GalleryInfo } from '../model/GalleryModels';
import { uiText } from '../shared/EhTranslations';

export const REMOTE_SYNC_STATUS_TEXT_KEY: string = 'remoteSyncStatusText';
export const REMOTE_SYNC_STATUS_DETAIL_KEY: string = 'remoteSyncStatusDetail';
export const REMOTE_SYNC_STATUS_REVISION_KEY: string = 'remoteSyncStatusRevision';
export const REMOTE_SYNC_ACTIVE_KEY: string = 'remoteSyncActive';
export const REMOTE_SYNC_PROGRESS_TITLE_KEY: string = 'remoteSyncProgressTitle';
export const REMOTE_SYNC_PROGRESS_DETAIL_KEY: string = 'remoteSyncProgressDetail';
export const REMOTE_SYNC_PROGRESS_PERCENT_KEY: string = 'remoteSyncProgressPercent';
export const REMOTE_SYNC_PROGRESS_SPEED_KEY: string = 'remoteSyncProgressSpeed';
export const REMOTE_SYNC_PROGRESS_BYTES_KEY: string = 'remoteSyncProgressBytes';
export const REMOTE_SYNC_DETAIL_VISIBLE_KEY: string = 'remoteSyncDetailVisible';

const PREFERENCES_NAME: string = 'ehviewer_remote_sync';
const LAST_SYNC_KEY: string = 'lastSyncAt';
const LAST_PULL_KEY: string = 'lastPulledAt';
const FINGERPRINT_KEY: string = 'lastFingerprint';
const SERVER_TIMES_KEY: string = 'serverTimes';
const MIRROR_CHECKS_KEY: string = 'mirrorChecks';
const DEVICE_ID_KEY: string = 'deviceId';
const SYNC_FOLDER: string = 'sync';
const MANIFEST_FILE: string = SYNC_FOLDER + '/manifest.json';
const FINGERPRINT_INTERVAL_MS: number = 60000;
const DIRTY_DEBOUNCE_MS: number = 15000;
const RETRY_DELAY_MS: number = 90000;
const MAX_SYNC_HISTORY_ITEMS: number = 1000;
const DOWNLOADS_FOLDER: string = 'download';
const MAX_MIRROR_GALLERIES_PER_CYCLE: number = 6;
const MAX_MIRROR_FILES_PER_CYCLE: number = 300;
const MIRROR_CONCURRENCY: number = 4;
const MIRROR_TIME_BUDGET_MS: number = 25000;

interface RemoteSyncManifest {
  version: number;
  updatedAt: number;
  sections: string[];
}

interface RemoteSyncSection {
  name: string;
  data: string;
}

interface RemoteSyncServerTime {
  name: string;
  time: number;
}

interface MirrorGalleryPlan {
  name: string;
  localDir: string;
  remoteDir: string;
  files: string[];
  mtime: number;
}

interface MirrorCheckRecord {
  name: string;
  mtime: number;
}

interface DownloadManifestEntry {
  path: string;
  size: number;
  mtime: number;
}

interface DownloadManifest {
  version: number;
  updatedAt: number;
  files: DownloadManifestEntry[];
}

interface SyncSectionEnvelope {
  deviceId?: string;
  updatedAt?: number;
  payload?: string;
}

const DOWNLOAD_MANIFEST_FILE: string = 'download/manifest.json';

export class RemoteStorageSyncService {
  private context: common.UIAbilityContext | null = null;
  private timer: number = -1;
  private busy: boolean = false;
  private dirty: boolean = false;
  private started: boolean = false;
  private lastSyncAt: number = 0;
  private lastPulledAt: number = 0;
  private fingerprint: string = '';
  private serverTimes: RemoteSyncServerTime[] = [];
  private mirrorChecks: MirrorCheckRecord[] = [];
  private downloadManifestEntries: DownloadManifestEntry[] = [];
  private downloadManifestMtime: number = 0;
  private deviceId: string = '';

  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    this.started = true;
    await this.loadState(context);
    await remoteStorageProfileStore.ensureLoaded(context);
    const profile = remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_SYNC);
    if (profile === null) {
      this.setStatus(uiText('Sync disabled'), uiText('Enable a sync folder in Download settings'));
      return;
    }
    this.publishSyncedOrPending(profile);
    this.pullIfNewer(context, profile);
    this.schedule(FINGERPRINT_INTERVAL_MS);
  }

  pause(): void {
    this.started = false;
    this.clearTimer();
  }

  markDirty(): void {
    this.dirty = true;
    if (!this.started || this.busy) {
      return;
    }
    this.schedule(DIRTY_DEBOUNCE_MS);
  }

  async syncNow(): Promise<void> {
    const context = this.context;
    if (context === null || this.busy) {
      return;
    }
    const profile = remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_SYNC);
    if (profile === null) {
      this.setStatus(uiText('Sync disabled'), uiText('Enable a sync folder in Download settings'));
      return;
    }
    await this.performSync(context, profile, new WebDavClient(profile), true);
  }

  private async performSync(context: common.UIAbilityContext, profile: RemoteStorageProfile,
    client: WebDavClient, pullRemote: boolean): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.publishStatus(profile, uiText('Syncing...'), '', true);
    try {
      const directory = await client.ensureDirectory(SYNC_FOLDER);
      if (!directory.ok) {
        throw new Error(directory.message);
      }
      if (pullRemote) {
        const listing = await client.list(SYNC_FOLDER);
        if (listing.ok) {
          for (let i = 0; i < listing.entries.length; i++) {
            const entry = listing.entries[i];
            if (entry.isDirectory || !entry.name.endsWith('.json') || entry.name === 'manifest.json') {
              continue;
            }
            const sectionName = entry.name.substring(0, entry.name.length - 5);
            if (sectionName.indexOf('settings') === 0) {
              // Settings stay per device: never apply another device's preferences.
              continue;
            }
            await this.applySection(context, client, sectionName);
          }
          this.recordServerTimes(listing.entries);
        }
      }
      const sections = await this.buildSections(context);
      for (let i = 0; i < sections.length; i++) {
        this.publishProgress(uiText('Syncing configuration…'), this.sectionLabel(sections[i].name),
          Math.round(i * 30 / sections.length));
        const uploaded = await client.putText(SYNC_FOLDER + '/' + sections[i].name + '.json', sections[i].data);
        if (!uploaded.ok) {
          throw new Error(sections[i].name + ': ' + uploaded.message);
        }
        this.publishProgress(uiText('Syncing configuration…'), this.sectionLabel(sections[i].name),
          Math.round((i + 1) * 30 / sections.length));
      }
      const manifest: RemoteSyncManifest = {
        version: 1,
        updatedAt: Date.now(),
        sections: sections.map((section: RemoteSyncSection): string => section.name)
      };
      const manifestUpload = await client.putText(MANIFEST_FILE, JSON.stringify(manifest));
      if (!manifestUpload.ok) {
        throw new Error(manifestUpload.message);
      }
      const afterListing = await client.list(SYNC_FOLDER);
      if (afterListing.ok) {
        this.recordServerTimes(afterListing.entries);
      }
      this.lastSyncAt = manifest.updatedAt;
      this.lastPulledAt = manifest.updatedAt;
      this.fingerprint = await this.computeFingerprint(context);
      await this.syncDownloadFiles(context, profile, client);
      await this.persistState(context);
      this.busy = false;
      this.dirty = false;
      this.publishProgress('', '', -1);
      logRemoteStorageInfo('sync completed sections=' + sections.length.toString());
      this.publishStatus(profile, uiText('Synced at') + ' ' + syncTimeText(this.lastSyncAt), '');
      this.schedule(FINGERPRINT_INTERVAL_MS);
    } catch (error) {
      this.busy = false;
      this.publishProgress('', '', -1);
      const message = error instanceof Error ? error.message : String(error);
      logRemoteStorageWarn('sync failed: ' + message);
      this.publishStatus(profile, uiText('Offline, retrying soon'), message);
      this.schedule(RETRY_DELAY_MS);
    }
  }

  private schedule(delayMs: number): void {
    if (!this.started) {
      return;
    }
    this.clearTimer();
    this.timer = setTimeout(() => {
      this.timer = -1;
      this.tick();
    }, delayMs) as number;
  }

  private clearTimer(): void {
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private async tick(): Promise<void> {
    const context = this.context;
    if (context === null || !this.started) {
      return;
    }
    const profile = remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_SYNC);
    if (profile === null) {
      this.setStatus(uiText('Sync disabled'), uiText('Enable a sync folder in Download settings'));
      return;
    }
    const client = new WebDavClient(profile);
    const listing = await client.list(SYNC_FOLDER);
    const fingerprint = await this.computeFingerprint(context);
    const localChanged = this.dirty || fingerprint !== this.fingerprint;
    if (!listing.ok) {
      this.schedule(localChanged ? RETRY_DELAY_MS : FINGERPRINT_INTERVAL_MS);
      return;
    }
    const remoteChanged = this.listingHasNewer(listing.entries);
    if (remoteChanged || localChanged) {
      await this.performSync(context, profile, client, true);
      return;
    }
    // Downloads mirror on every poll so newly finished galleries are uploaded even when the
    // JSON sync sections did not change.
    await this.syncDownloadFiles(context, profile, client);
    this.publishSyncedOrPending(profile);
    this.schedule(FINGERPRINT_INTERVAL_MS);
  }

  private publishSyncedOrPending(profile: RemoteStorageProfile): void {
    if (this.busy) {
      this.publishStatus(profile, uiText('Syncing...'), '', true);
      return;
    }
    if (this.lastSyncAt > 0) {
      this.publishStatus(profile, uiText('Synced at') + ' ' + syncTimeText(this.lastSyncAt), '');
      return;
    }
    this.publishStatus(profile, uiText('Pending sync'), '');
  }

  private listingHasNewer(entries: RemoteStorageListEntry[]): boolean {
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      if (entry.isDirectory || !entry.name.endsWith('.json') || entry.name === 'manifest.json') {
        continue;
      }
      const name = entry.name.substring(0, entry.name.length - 5);
      if (entry.modifiedAt > 0 && entry.modifiedAt > this.serverTimeFor(name)) {
        return true;
      }
    }
    return false;
  }

  private serverTimeFor(name: string): number {
    for (let i = 0; i < this.serverTimes.length; i++) {
      if (this.serverTimes[i].name === name) {
        return this.serverTimes[i].time;
      }
    }
    return 0;
  }

  private recordServerTimes(entries: RemoteStorageListEntry[]): void {
    const next: RemoteSyncServerTime[] = [];
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      if (entry.isDirectory || !entry.name.endsWith('.json')) {
        continue;
      }
      next.push({ name: entry.name.substring(0, entry.name.length - 5), time: entry.modifiedAt });
    }
    this.serverTimes = next;
  }

  private async buildSections(context: common.UIAbilityContext): Promise<RemoteSyncSection[]> {
    await Promise.all([
      ehSettingsStore.ensureLoaded(context),
      ehBookmarkStore.ensureLoaded(context),
      ehFilterStore.ensureLoaded(context),
      ehCommentBlacklistStore.ensureLoaded(context),
      ehSearchHistoryStore.load(context),
      ehBrowsePositionStore.ensureLoaded(context),
      ehHistoryStore.ensureLoaded(context),
      ehLocalFavoritesStore.ensureLoaded(context)
    ]);
    const history: GalleryInfo[] = ehHistoryStore.getItems();
    const historySlice = history.length > MAX_SYNC_HISTORY_ITEMS ?
      history.slice(history.length - MAX_SYNC_HISTORY_ITEMS) : history;
    const sections: RemoteSyncSection[] = [
      { name: 'settings_' + this.deviceId, data: JSON.stringify(ehSettingsStore.getTransferEntries()) },
      { name: 'bookmarks', data: this.wrapSection(ehBookmarkStore.getBackupItems()) },
      { name: 'localFavorites', data: this.wrapSection(ehLocalFavoritesStore.getBackupItems()) },
      { name: 'blacklist', data: this.wrapSection(ehCommentBlacklistStore.getBackupItems()) },
      { name: 'filters', data: JSON.stringify(ehFilterStore.getRules()) },
      { name: 'searchHistory', data: JSON.stringify(ehSearchHistoryStore.getKeywords()) },
      { name: 'browsePositions', data: JSON.stringify(ehBrowsePositionStore.getBackupInfo()) },
      { name: 'readingProgress', data: JSON.stringify(ehHistoryStore.getReadingProgressBackupItems()) },
      { name: 'history', data: this.wrapSection(historySlice) }
    ];
    return sections;
  }

  // Shared lists are wrapped with the writing device and timestamp: the same device can just
  // overwrite its own copy, while other devices merge before writing back.
  private wrapSection(payload: Object): string {
    const envelope: SyncSectionEnvelope = {
      deviceId: this.deviceId,
      updatedAt: Date.now(),
      payload: JSON.stringify(payload)
    };
    return JSON.stringify(envelope);
  }

  private async pullIfNewer(context: common.UIAbilityContext, profile: RemoteStorageProfile): Promise<void> {
    try {
      const client = new WebDavClient(profile);
      const manifestResult = await client.getText(MANIFEST_FILE);
      if (!manifestResult.ok || manifestResult.text.length === 0) {
        return;
      }
      const manifest = JSON.parse(manifestResult.text) as RemoteSyncManifest;
      if (typeof manifest.updatedAt !== 'number' || manifest.updatedAt <= this.lastPulledAt) {
        return;
      }
      await Promise.all([
        ehSettingsStore.ensureLoaded(context),
        ehBookmarkStore.ensureLoaded(context),
        ehFilterStore.ensureLoaded(context),
        ehCommentBlacklistStore.ensureLoaded(context),
        ehSearchHistoryStore.load(context),
        ehBrowsePositionStore.ensureLoaded(context),
        ehHistoryStore.ensureLoaded(context)
      ]);
      for (let i = 0; i < manifest.sections.length; i++) {
        await this.applySection(context, client, manifest.sections[i]);
      }
      this.lastPulledAt = manifest.updatedAt;
      if (this.lastSyncAt <= 0) {
        this.lastSyncAt = manifest.updatedAt;
      }
      await this.persistState(context);
      logRemoteStorageInfo('sync pulled sections=' + manifest.sections.length.toString());
      this.publishStatus(profile, uiText('Synced at') + ' ' + syncTimeText(this.lastSyncAt), '');
    } catch (error) {
      logRemoteStorageWarn('sync pull failed: ' + (error instanceof Error ? error.message : String(error)));
    }
  }

  private async applySection(context: common.UIAbilityContext, client: WebDavClient, name: string): Promise<void> {
    const file = await client.getText(SYNC_FOLDER + '/' + name + '.json');
    if (!file.ok || file.text.length === 0) {
      return;
    }
    let content = file.text;
    let remoteDevice = '';
    try {
      const envelope = JSON.parse(content) as SyncSectionEnvelope;
      if (envelope !== null && typeof envelope.deviceId === 'string' && typeof envelope.payload === 'string') {
        remoteDevice = envelope.deviceId;
        content = envelope.payload;
      }
    } catch (error) {
      content = file.text;
    }
    if (remoteDevice.length > 0 && remoteDevice === this.deviceId) {
      // Our own copy: local data is authoritative, the merged result is uploaded afterwards.
      return;
    }
    try {
      if (name === 'settings') {
        ehSettingsStore.importEntries(JSON.parse(content) as SettingEntry[]);
        await ehSettingsStore.save(context);
      } else if (name === 'bookmarks') {
        ehBookmarkStore.importBackupItems(JSON.parse(content) as SearchBookmarkBackupInfo[]);
        await ehBookmarkStore.save(context);
      } else if (name === 'filters') {
        const rules = JSON.parse(content) as FilterRuleLike[];
        for (let i = 0; i < rules.length; i++) {
          const ruleMode = rules[i].mode;
          const ruleText = rules[i].text;
          if (typeof ruleText === 'string' && typeof ruleMode === 'number') {
            ehFilterStore.addRule(ruleMode, ruleText, rules[i].enabled !== false);
          }
        }
        await ehFilterStore.save(context);
      } else if (name === 'blacklist') {
        ehCommentBlacklistStore.importBackupItems(JSON.parse(content) as CommentBlacklistBackupEntry[]);
        await ehCommentBlacklistStore.save(context);
      } else if (name === 'localFavorites') {
        ehLocalFavoritesStore.importBackupItems(JSON.parse(content) as LocalFavoriteBackupInfo[]);
        await ehLocalFavoritesStore.save(context);
      } else if (name === 'searchHistory') {
        ehSearchHistoryStore.importKeywords(JSON.parse(content) as string[]);
        await ehSearchHistoryStore.save(context);
      } else if (name === 'browsePositions') {
        ehBrowsePositionStore.importBackupInfo(JSON.parse(content) as BrowsePositionsBackupInfo);
        await ehBrowsePositionStore.save(context);
      } else if (name === 'readingProgress') {
        ehHistoryStore.importReadingProgressBackupItems(JSON.parse(content) as ReadingProgressBackupInfo[]);
        await ehHistoryStore.save(context);
      } else if (name === 'history') {
        const items = JSON.parse(content) as GalleryInfo[];
        const limit = historyInfoSizeLimitFromValue(ehSettingsStore.getValue(HISTORY_INFO_SIZE_KEY, '100'));
        ehHistoryStore.importHistoryBackupItems(items, limit);
        await ehHistoryStore.save(context);
      }
    } catch (error) {
      logRemoteStorageError('sync section ' + name + ' apply failed: ' +
        (error instanceof Error ? error.message : String(error)));
    }
  }

  private async syncDownloadFiles(context: common.UIAbilityContext, profile: RemoteStorageProfile,
    client: WebDavClient): Promise<void> {
    if (!profile.useForDownloads) {
      return;
    }
    logRemoteStorageInfo('download mirror start profile=' +
      (profile.name.length > 0 ? profile.name : profile.url));
    const root = ehDownloadFileStore.appDownloadRoot(context);
    let galleryNames: string[] = [];
    try {
      galleryNames = fs.listFileSync(root);
    } catch (error) {
      return;
    }
    logRemoteStorageInfo('download mirror scan root=' + root + ' entries=' + galleryNames.length.toString());
    const startedAt = Date.now();
    this.publishStatus(profile, uiText('Syncing...'), '', true);
    this.publishProgress(uiText('Scanning download files…'), '', -1);
    // Remote manifest keeps the mirrored file tree (path, size, mtime). When its server mtime is
    // unchanged the cached copy is reused, so a cycle costs at most one PROPFIND and one GET.
    const manifestInfo = await client.list(DOWNLOAD_MANIFEST_FILE);
    const manifestMtime = manifestInfo.ok && manifestInfo.entries.length > 0 ?
      manifestInfo.entries[0].modifiedAt : 0;
    if (manifestMtime === 0 || manifestMtime !== this.downloadManifestMtime) {
      const manifestText = await client.getText(DOWNLOAD_MANIFEST_FILE);
      if (manifestText.ok && manifestText.text.length > 0) {
        try {
          const parsed = JSON.parse(manifestText.text) as DownloadManifest;
          this.downloadManifestEntries = Array.isArray(parsed.files) ? parsed.files : [];
        } catch (error) {
          this.downloadManifestEntries = [];
        }
      } else {
        this.downloadManifestEntries = [];
      }
      this.downloadManifestMtime = manifestMtime;
    }
    const manifestByPath = new Map<string, DownloadManifestEntry>();
    for (let i = 0; i < this.downloadManifestEntries.length; i++) {
      manifestByPath.set(this.downloadManifestEntries[i].path, this.downloadManifestEntries[i]);
    }
    // Plan first so the total progress bar and transfer rate cover the whole batch.
    const plan: MirrorGalleryPlan[] = [];
    const uploadedUpdates: DownloadManifestEntry[] = [];
    let totalFiles = 0;
    let totalBytes = 0;
    for (let i = 0; i < galleryNames.length; i++) {
      if (plan.length >= MAX_MIRROR_GALLERIES_PER_CYCLE || totalFiles >= MAX_MIRROR_FILES_PER_CYCLE ||
        Date.now() - startedAt >= MIRROR_TIME_BUDGET_MS) {
        break;
      }
      const galleryName = galleryNames[i];
      const localDir = root + '/' + galleryName;
      let directory = false;
      let dirMtime = 0;
      try {
        const dirStat = fs.statSync(localDir);
        directory = dirStat.isDirectory();
        dirMtime = dirStat.mtime;
      } catch (error) {
        directory = false;
      }
      if (!directory) {
        continue;
      }
      this.publishProgress(uiText('Scanning download files…'), galleryName, -1);
      const remoteDir = DOWNLOADS_FOLDER + '/' + galleryName;
      let fileNames: string[] = [];
      try {
        fileNames = fs.listFileSync(localDir);
      } catch (error) {
        continue;
      }
      const pending: string[] = [];
      let pendingBytes = 0;
      for (let j = 0; j < fileNames.length; j++) {
        if (totalFiles + pending.length >= MAX_MIRROR_FILES_PER_CYCLE) {
          break;
        }
        const fileName = fileNames[j];
        const localPath = localDir + '/' + fileName;
        let size = 0;
        let mtime = 0;
        let isFile = false;
        try {
          const fileStat = fs.statSync(localPath);
          isFile = fileStat.isFile();
          size = fileStat.size;
          mtime = Math.round(fileStat.mtime * 1000);
        } catch (error) {
          isFile = false;
        }
        if (!isFile) {
          continue;
        }
        const remoteEntry = manifestByPath.get(galleryName + '/' + fileName);
        if (remoteEntry !== undefined) {
          if (remoteEntry.size === size) {
            continue;
          }
          // Size differs: keep whichever side is newer, never overwrite a newer remote file.
          if (remoteEntry.mtime > mtime) {
            continue;
          }
        }
        pending.push(fileName);
        pendingBytes += size;
      }
      if (pending.length > 0) {
        plan.push({
          name: galleryName, localDir: localDir, remoteDir: remoteDir, files: pending, mtime: dirMtime
        });
        totalFiles += pending.length;
        totalBytes += pendingBytes;
      }
    }
    if (totalFiles === 0) {
      this.publishProgress('', '', -1);
      return;
    }
    let uploadedFiles = 0;
    let uploadedBytes = 0;
    let speedSampleAt = startedAt;
    let speedSampleBytes = 0;
    let speedText = '';
    for (let i = 0; i < plan.length; i++) {
      const gallery = plan[i];
      let uploadedHere = 0;
      for (let j = 0; j < gallery.files.length; j += MIRROR_CONCURRENCY) {
        if (Date.now() - startedAt >= MIRROR_TIME_BUDGET_MS) {
          break;
        }
        const batch: string[] = gallery.files.slice(j, j + MIRROR_CONCURRENCY);
        const results = await Promise.all(batch.map((fileName: string): Promise<number> => {
          const data = readFileBuffer(gallery.localDir + '/' + fileName);
          if (data === null) {
            return Promise.resolve(-1);
          }
          const byteLength = data.byteLength;
          return client.putBinary(gallery.remoteDir + '/' + fileName, data)
            .then((result: RemoteStorageResult): number => result.ok ? byteLength : -1);
        }));
        for (let k = 0; k < results.length; k++) {
          if (results[k] >= 0) {
            uploadedFiles++;
            uploadedHere++;
            uploadedBytes += results[k];
            const uploadedName = batch[k];
            uploadedUpdates.push({
              path: gallery.name + '/' + uploadedName,
              size: results[k],
              mtime: fileMtimeMsOrZero(gallery.localDir + '/' + uploadedName)
            });
          }
        }
        const now = Date.now();
        const sampleElapsed = now - speedSampleAt;
        if (sampleElapsed >= 1000) {
          speedText = formatTransferRate((uploadedBytes - speedSampleBytes) / (sampleElapsed / 1000));
          speedSampleAt = now;
          speedSampleBytes = uploadedBytes;
        }
        const percent = 30 + Math.round(70 * uploadedFiles / Math.max(1, totalFiles));
        const progressDetail = gallery.name + ' · ' + batch[batch.length - 1];
        const byteText = formatTransferBytes(uploadedBytes) + ' / ' + formatTransferBytes(totalBytes) +
          ' · ' + uploadedFiles.toString() + '/' + totalFiles.toString();
        this.publishProgress(uiText('Downloading files'), progressDetail, percent, speedText, byteText);
      }
    }
    if (uploadedFiles > 0) {
      logRemoteStorageInfo('download mirror uploaded files=' + uploadedFiles.toString() +
        ' bytes=' + uploadedBytes.toString());
    }
    if (uploadedUpdates.length > 0) {
      const merged: DownloadManifestEntry[] = [];
      const indexByPath = new Map<string, number>();
      for (let i = 0; i < this.downloadManifestEntries.length; i++) {
        indexByPath.set(this.downloadManifestEntries[i].path, merged.length);
        merged.push(this.downloadManifestEntries[i]);
      }
      for (let i = 0; i < uploadedUpdates.length; i++) {
        const index = indexByPath.get(uploadedUpdates[i].path);
        if (index === undefined) {
          indexByPath.set(uploadedUpdates[i].path, merged.length);
          merged.push(uploadedUpdates[i]);
        } else {
          merged[index] = uploadedUpdates[i];
        }
      }
      const manifest: DownloadManifest = { version: 1, updatedAt: Date.now(), files: merged };
      const uploadedManifest = await client.putText(DOWNLOAD_MANIFEST_FILE, JSON.stringify(manifest));
      if (uploadedManifest.ok) {
        this.downloadManifestEntries = merged;
        const refreshed = await client.list(DOWNLOAD_MANIFEST_FILE);
        this.downloadManifestMtime = refreshed.ok && refreshed.entries.length > 0 ?
          refreshed.entries[0].modifiedAt : Date.now();
      }
    }
  }

  private mirrorCheckFor(name: string): MirrorCheckRecord | null {
    for (let i = 0; i < this.mirrorChecks.length; i++) {
      if (this.mirrorChecks[i].name === name) {
        return this.mirrorChecks[i];
      }
    }
    return null;
  }

  private rememberMirrorCheck(name: string, mtime: number): void {
    const next: MirrorCheckRecord[] = [];
    for (let i = 0; i < this.mirrorChecks.length; i++) {
      if (this.mirrorChecks[i].name !== name) {
        next.push(this.mirrorChecks[i]);
      }
    }
    if (mtime > 0) {
      next.push({ name: name, mtime: mtime });
    }
    this.mirrorChecks = next;
  }

  private async computeFingerprint(context: common.UIAbilityContext): Promise<string> {
    const historyLength = ehHistoryStore.getItems().length;
    const parts: string[] = [
      ehSettingsStore.getTransferEntries().length.toString(),
      ehBookmarkStore.getBackupItems().length.toString(),
      ehFilterStore.getRules().length.toString(),
      ehCommentBlacklistStore.getBackupItems().length.toString(),
      ehSearchHistoryStore.getKeywords().length.toString(),
      historyLength.toString(),
      remoteStorageProfileStore.getProfiles().length.toString()
    ];
    return parts.join(':');
  }

  private async loadState(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const lastSync = await prefs.get(LAST_SYNC_KEY, 0);
      const lastPull = await prefs.get(LAST_PULL_KEY, 0);
      const fingerprint = await prefs.get(FINGERPRINT_KEY, '');
      const serverTimes = await prefs.get(SERVER_TIMES_KEY, '[]');
      const mirrorChecks = await prefs.get(MIRROR_CHECKS_KEY, '[]');
      const deviceId = await prefs.get(DEVICE_ID_KEY, '');
      this.lastSyncAt = typeof lastSync === 'number' ? lastSync : 0;
      this.lastPulledAt = typeof lastPull === 'number' ? lastPull : 0;
      this.fingerprint = typeof fingerprint === 'string' ? fingerprint : '';
      if (typeof serverTimes === 'string') {
        try {
          this.serverTimes = JSON.parse(serverTimes) as RemoteSyncServerTime[];
        } catch (parseError) {
          this.serverTimes = [];
        }
      }
      if (typeof mirrorChecks === 'string') {
        try {
          this.mirrorChecks = JSON.parse(mirrorChecks) as MirrorCheckRecord[];
        } catch (parseError) {
          this.mirrorChecks = [];
        }
      }
      this.deviceId = typeof deviceId === 'string' && deviceId.length > 0 ? deviceId :
        ('device_' + Date.now().toString() + '_' + Math.floor(Math.random() * 100000).toString());
    } catch (error) {
    }
  }

  private async persistState(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(LAST_SYNC_KEY, this.lastSyncAt);
      await prefs.put(LAST_PULL_KEY, this.lastPulledAt);
      await prefs.put(FINGERPRINT_KEY, this.fingerprint);
      await prefs.put(SERVER_TIMES_KEY, JSON.stringify(this.serverTimes));
      await prefs.put(MIRROR_CHECKS_KEY, JSON.stringify(this.mirrorChecks));
      await prefs.put(DEVICE_ID_KEY, this.deviceId);
      await prefs.flush();
    } catch (error) {
    }
  }

  refreshConfiguration(): void {
    const profile = remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_SYNC);
    if (profile === null) {
      this.setStatus(uiText('Sync disabled'), uiText('Enable a sync folder in Download settings'), false);
      return;
    }
    this.publishStatus(profile, uiText('Pending sync'), '');
    this.dirty = true;
    if (this.started && !this.busy) {
      this.schedule(DIRTY_DEBOUNCE_MS);
    }
  }

  private publishStatus(profile: RemoteStorageProfile, text: string, detail: string,
    active: boolean = false): void {
    const serverDetail = detail.length > 0 ? detail :
      (uiText('Server: ') + (profile.name.length > 0 ? profile.name + ' · ' : '') + profile.url);
    this.setStatus(text, serverDetail, active);
  }

  private publishProgress(title: string, detail: string, percent: number, speed: string = '',
    bytes: string = ''): void {
    AppStorage.setOrCreate<string>(REMOTE_SYNC_PROGRESS_TITLE_KEY, title);
    AppStorage.setOrCreate<string>(REMOTE_SYNC_PROGRESS_DETAIL_KEY, detail);
    AppStorage.setOrCreate<number>(REMOTE_SYNC_PROGRESS_PERCENT_KEY, percent);
    AppStorage.setOrCreate<string>(REMOTE_SYNC_PROGRESS_SPEED_KEY, speed);
    AppStorage.setOrCreate<string>(REMOTE_SYNC_PROGRESS_BYTES_KEY, bytes);
  }

  private sectionLabel(name: string): string {
    if (name === 'settings') {
      return uiText('Settings');
    }
    if (name === 'bookmarks') {
      return uiText('Bookmarks');
    }
    if (name === 'filters') {
      return uiText('Filter rules');
    }
    if (name === 'blacklist') {
      return uiText('Comment blacklist');
    }
    if (name === 'searchHistory') {
      return uiText('Search history');
    }
    if (name === 'browsePositions') {
      return uiText('Browse positions');
    }
    if (name === 'readingProgress') {
      return uiText('Reading progress');
    }
    if (name === 'history') {
      return uiText('History');
    }
    return name;
  }

  private setStatus(text: string, detail: string, active: boolean = false): void {
    const revision = AppStorage.get<number>(REMOTE_SYNC_STATUS_REVISION_KEY) ?? 0;
    AppStorage.setOrCreate<string>(REMOTE_SYNC_STATUS_TEXT_KEY, text);
    AppStorage.setOrCreate<string>(REMOTE_SYNC_STATUS_DETAIL_KEY, detail);
    AppStorage.setOrCreate<boolean>(REMOTE_SYNC_ACTIVE_KEY, active);
    AppStorage.setOrCreate<number>(REMOTE_SYNC_STATUS_REVISION_KEY, revision + 1);
  }
}

interface FilterRuleLike {
  mode?: number;
  text?: string;
  enabled?: boolean;
}

function syncTimeText(timestamp: number): string {
  if (timestamp <= 0) {
    return '';
  }
  const date = new Date(timestamp);
  const hours = date.getHours();
  const minutes = date.getMinutes();
  return (hours < 10 ? '0' + hours.toString() : hours.toString()) + ':' +
    (minutes < 10 ? '0' + minutes.toString() : minutes.toString());
}

function fileMtimeMsOrZero(path: string): number {
  try {
    const mtime = fs.statSync(path).mtime;
    return mtime > 0 ? Math.round(mtime * 1000) : 0;
  } catch (error) {
    return 0;
  }
}

function fileSizeOrZero(path: string): number {
  try {
    const size = fs.statSync(path).size;
    return size > 0 ? size : 0;
  } catch (error) {
    return 0;
  }
}

function formatTransferBytes(bytes: number): string {
  if (bytes >= 1024 * 1024 * 1024) {
    return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
  }
  if (bytes >= 1024 * 1024) {
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }
  if (bytes >= 1024) {
    return (bytes / 1024).toFixed(0) + ' KB';
  }
  return Math.max(0, Math.round(bytes)).toString() + ' B';
}

function formatTransferRate(bytesPerSecond: number): string {
  if (bytesPerSecond <= 0) {
    return '';
  }
  return formatTransferBytes(bytesPerSecond) + '/s';
}

function readFileBuffer(path: string): ArrayBuffer | null {
  let fd = -1;
  try {
    const size = fs.statSync(path).size;
    if (size <= 0) {
      return null;
    }
    const buffer = new ArrayBuffer(size);
    fd = fs.openSync(path, fs.OpenMode.READ_ONLY).fd;
    fs.readSync(fd, buffer);
    return buffer;
  } catch (error) {
    return null;
  } finally {
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (error) {
      }
    }
  }
}

export const remoteStorageSyncService = new RemoteStorageSyncService();
