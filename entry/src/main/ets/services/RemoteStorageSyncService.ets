import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { deviceInfo, settings } from '@kit.BasicServicesKit';
import { ehBookmarkStore, SearchBookmarkBackupInfo } from './EhBookmarkStore';
import { ehBrowsePositionStore, BrowsePositionsBackupInfo } from './EhBrowsePositionStore';
import { ehCommentBlacklistStore, CommentBlacklistBackupEntry } from './EhCommentBlacklistStore';
import { ehFilterStore } from './EhFilterStore';
import { ehLocalFavoritesStore, LocalFavoriteBackupInfo } from './EhLocalFavoritesStore';
import { ehHistoryStore, ReadingProgressBackupInfo } from './EhHistoryStore';
import { ehSearchHistoryStore } from './EhSearchHistoryStore';
import {
  ehSettingsStore,
  HISTORY_INFO_SIZE_KEY,
  historyInfoSizeLimitFromValue,
  REMOTE_SYNC_WIFI_ONLY_KEY,
  SettingEntry
} from './EhSettingsStore';
import { isDefaultNetworkCellular } from './EhCellularNetworkGuard';
import {
  REMOTE_STORAGE_PURPOSE_BACKUP,
  REMOTE_STORAGE_PURPOSE_DOWNLOADS,
  REMOTE_STORAGE_PURPOSE_SYNC,
  RemoteStorageProfile,
  remoteStorageProfileStore
} from './RemoteStorageProfiles';
import { logRemoteStorageError, logRemoteStorageInfo, logRemoteStorageWarn } from './RemoteStorageLog';
import { RemoteStorageResult, WebDavClient } from './WebDavClient';
import {
  RemoteStorageListEntry,
  SyncTombstoneLike,
  filterTombstoneKey,
  keywordTombstoneKey,
  pruneSyncTombstoneList,
  syncTombstoneShouldDelete
} from './RemoteStorageSupport';
import { syncTombstoneStore } from './SyncTombstoneStore';
import {
  parseCustomReaderPresetProfiles,
  READER_CUSTOM_PRESETS_SETTING_KEY,
  ReaderPresetProfile,
  serializeCustomReaderPresetProfiles
} from './ReaderPresetSupport';
import {
  parseCustomTranslationPromptProfiles,
  serializeCustomTranslationPromptProfiles,
  TranslationPromptProfile
} from './TranslationSupport';
import { ehDownloadFileStore } from './EhDownloadFileStore';
import { ehDownloadStore } from './EhDownloadStore';
import { remoteStorageDownloadDeletionService } from './RemoteStorageDownloadDeletionService';
import { fileIo as fs } from '@kit.CoreFileKit';
import { GalleryInfo } from '../model/GalleryModels';
import { notifyGalleryTitleChanged, notifyLanguageChanged, notifyThemeChanged, uiText } from '../shared/EhTranslations';

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
const TOMBSTONES_FILE: string = SYNC_FOLDER + '/tombstones.json';
const TOMBSTONE_MAX_AGE_MS: number = 180 * 24 * 60 * 60 * 1000;
const SYNC_SECTION_HISTORY: string = 'history';
const SYNC_SECTION_BOOKMARKS: string = 'bookmarks';
const SYNC_SECTION_LOCAL_FAVORITES: string = 'localFavorites';
const SYNC_SECTION_BLACKLIST: string = 'blacklist';
const SYNC_SECTION_FILTERS: string = 'filters';
const SYNC_SECTION_SEARCH_HISTORY: string = 'searchHistory';
const SYNC_SECTION_READING_PROGRESS: string = 'readingProgress';
const SYNC_SECTION_DOWNLOAD_LABELS: string = 'downloadLabels';
const SYNC_SECTION_REMOTE_STORAGE: string = 'remoteStorage';
const SYNC_SECTION_READER_PRESETS: string = 'readerPresets';
const SYNC_SECTION_TRANSLATION_PROMPTS: string = 'translationPrompts';
const TRANSLATION_CUSTOM_PROMPTS_KEY: string = 'translation_prompt_custom_profiles';
const DOWNLOADS_FOLDER: string = 'download';
const MAX_MIRROR_GALLERIES_PER_CYCLE: number = 6;
const MAX_MIRROR_FILES_PER_CYCLE: number = 300;
const MIRROR_CONCURRENCY: number = 2;
const MIRROR_TIME_BUDGET_MS: number = 25000;
 const RECONCILE_INTERVAL_MS: number = 600000;
const RECONCILE_GALLERIES_PER_CYCLE: number = 3;

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
  etag?: string;
}

interface DownloadManifest {
  version: number;
  updatedAt: number;
  files: DownloadManifestEntry[];
}

interface SyncSectionEnvelope {
  deviceId?: string;
  deviceName?: string;
  updatedAt?: number;
  payload?: string;
}

export interface RemoteSettingsCandidate {
  file: string;
  deviceId: string;
  deviceName: string;
  updatedAt: number;
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
  private lastReconcileAt: number = 0;
  private reconcileIndex: number = 0;
  private deviceId: string = '';
  private deviceName: string = '';

  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    this.started = true;
    await this.loadState(context);
    await remoteStorageProfileStore.ensureLoaded(context);
    const profile = remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_SYNC);
    if (profile === null) {
      this.setStatus('', '', false);
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
      this.setStatus('', '', false);
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
        await this.mergeRemoteTombstones(context, client);
        const listing = await client.list(SYNC_FOLDER);
        if (listing.ok) {
          for (let i = 0; i < listing.entries.length; i++) {
            const entry = listing.entries[i];
            if (entry.isDirectory || !entry.name.endsWith('.json') || entry.name === 'manifest.json' ||
              entry.name === 'tombstones.json') {
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
        await this.applyTombstones(context);
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
      syncTombstoneStore.prune(TOMBSTONE_MAX_AGE_MS);
      if (!syncTombstoneStore.isEmpty()) {
        await client.putText(TOMBSTONES_FILE, syncTombstoneStore.serialize());
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
      this.setStatus('', '', false);
      return;
    }
    if (!this.networkAllowsSync()) {
      this.publishStatus(profile, uiText('Waiting for Wi-Fi'), '');
      this.schedule(FINGERPRINT_INTERVAL_MS);
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

  private networkAllowsSync(): boolean {
    if (ehSettingsStore.getValue(REMOTE_SYNC_WIFI_ONLY_KEY, 'Off') !== 'On') {
      return true;
    }
    try {
      return !isDefaultNetworkCellular();
    } catch (error) {
      return true;
    }
  }

  private profileForSettingsRestore(): RemoteStorageProfile | null {
    const syncProfile = remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_SYNC);
    if (syncProfile !== null) {
      return syncProfile;
    }
    const backupProfile = remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_BACKUP);
    if (backupProfile !== null) {
      return backupProfile;
    }
    const profiles = remoteStorageProfileStore.getProfiles();
    return profiles.length > 0 ? profiles[0] : null;
  }

  async listRemoteSettings(context: common.UIAbilityContext): Promise<RemoteSettingsCandidate[]> {
    const profile = this.profileForSettingsRestore();
    if (profile === null) {
      return [];
    }
    const client = new WebDavClient(profile);
    const listing = await client.list(SYNC_FOLDER);
    if (!listing.ok) {
      return [];
    }
    const candidates: RemoteSettingsCandidate[] = [];
    for (let i = 0; i < listing.entries.length; i++) {
      const entry = listing.entries[i];
      if (entry.isDirectory || !entry.name.startsWith('settings_') || !entry.name.endsWith('.json')) {
        continue;
      }
      let deviceId = entry.name.substring('settings_'.length, entry.name.length - 5);
      let deviceName = deviceId;
      let updatedAt = entry.modifiedAt;
      const text = await client.getText(SYNC_FOLDER + '/' + entry.name);
      if (text.ok && text.text.length > 0) {
        try {
          const envelope = JSON.parse(text.text) as SyncSectionEnvelope;
          if (typeof envelope.deviceId === 'string' && typeof envelope.payload === 'string') {
            deviceId = envelope.deviceId;
            if (typeof envelope.deviceName === 'string' && envelope.deviceName.length > 0) {
              deviceName = envelope.deviceName;
            }
            if (typeof envelope.updatedAt === 'number' && envelope.updatedAt > 0) {
              updatedAt = envelope.updatedAt;
            }
          }
        } catch (error) {
        }
      }
      candidates.push({ file: entry.name, deviceId: deviceId, deviceName: deviceName, updatedAt: updatedAt });
    }
    candidates.sort((left: RemoteSettingsCandidate, right: RemoteSettingsCandidate): number =>
      right.updatedAt - left.updatedAt);
    return candidates;
  }

  async applyRemoteSettings(context: common.UIAbilityContext, file: string): Promise<boolean> {
    const profile = this.profileForSettingsRestore();
    if (profile === null) {
      return false;
    }
    const client = new WebDavClient(profile);
    const text = await client.getText(SYNC_FOLDER + '/' + file);
    if (!text.ok || text.text.length === 0) {
      return false;
    }
    let payload = text.text;
    try {
      const envelope = JSON.parse(text.text) as SyncSectionEnvelope;
      if (typeof envelope.payload === 'string') {
        payload = envelope.payload;
      }
    } catch (error) {
    }
    try {
      const entries = JSON.parse(payload) as SettingEntry[];
      const result = ehSettingsStore.importEntries(entries);
      await ehSettingsStore.save(context);
      if (result.languageChanged) {
        notifyLanguageChanged();
      }
      if (result.themeChanged) {
        notifyThemeChanged();
      }
      if (result.titleChanged) {
        notifyGalleryTitleChanged();
      }
      return true;
    } catch (error) {
      logRemoteStorageWarn('apply remote settings failed: ' + (error instanceof Error ? error.message : String(error)));
      return false;
    }
  }

  async restoreCloudGallery(context: common.UIAbilityContext, gid: number): Promise<boolean> {
    const profile = remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_DOWNLOADS);
    if (profile === null) {
      return false;
    }
    const client = new WebDavClient(profile);
    const listing = await client.list(DOWNLOADS_FOLDER);
    if (!listing.ok) {
      return false;
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
      return false;
    }
    const remoteDir = DOWNLOADS_FOLDER + '/' + directoryName;
    const files = await client.list(remoteDir);
    if (!files.ok) {
      return false;
    }
    const localDir = ehDownloadFileStore.appDownloadRoot(context) + '/' + directoryName;
    try {
      fs.mkdirSync(localDir);
    } catch (error) {
    }
    let total = 0;
    for (let i = 0; i < files.entries.length; i++) {
      if (!files.entries[i].isDirectory) {
        total++;
      }
    }
    let done = 0;
    for (let i = 0; i < files.entries.length; i++) {
      const entry = files.entries[i];
      if (entry.isDirectory) {
        continue;
      }
      const localPath = localDir + '/' + entry.name;
      let exists = false;
      try {
        exists = fs.statSync(localPath).size > 0;
      } catch (error) {
        exists = false;
      }
      if (!exists) {
        const data = await client.getBinary(remoteDir + '/' + entry.name);
        if (data !== null) {
          let fd = -1;
          try {
            fd = fs.openSync(localPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC).fd;
            fs.writeSync(fd, data);
          } catch (error) {
          } finally {
            if (fd >= 0) {
              try {
                fs.closeSync(fd);
              } catch (error) {
              }
            }
          }
        }
      }
      done++;
      this.publishProgress(uiText('Restoring from cloud…'), directoryName + ' · ' + entry.name,
        Math.round(done * 100 / Math.max(1, total)));
    }
    this.publishProgress('', '', -1);
    remoteStorageDownloadDeletionService.invalidateDirectoryCache();
    return true;
  }

  // Periodic ground-truth check: PROPFIND a rotating slice of the remote download tree and
  // repair the manifest for external changes, ghosts and drifted files (ETag/size, no download).
  private async reconcileManifestIfDue(client: WebDavClient): Promise<void> {
    const now = Date.now();
    if (now - this.lastReconcileAt < RECONCILE_INTERVAL_MS) {
      return;
    }
    this.lastReconcileAt = now;
    const galleryListing = await client.list(DOWNLOADS_FOLDER);
    if (!galleryListing.ok) {
      return;
    }
    const directories: string[] = [];
    for (let i = 0; i < galleryListing.entries.length; i++) {
      if (galleryListing.entries[i].isDirectory) {
        directories.push(galleryListing.entries[i].name);
      }
    }
    if (directories.length === 0) {
      return;
    }
    const checked: string[] = [];
    for (let count = 0; count < RECONCILE_GALLERIES_PER_CYCLE && count < directories.length; count++) {
      checked.push(directories[(this.reconcileIndex + count) % directories.length]);
    }
    this.reconcileIndex = (this.reconcileIndex + RECONCILE_GALLERIES_PER_CYCLE) % directories.length;
    const oldByPath = new Map<string, DownloadManifestEntry>();
    for (let i = 0; i < this.downloadManifestEntries.length; i++) {
      oldByPath.set(this.downloadManifestEntries[i].path, this.downloadManifestEntries[i]);
    }
    const next: DownloadManifestEntry[] = [];
    for (let i = 0; i < this.downloadManifestEntries.length; i++) {
      const entryPath = this.downloadManifestEntries[i].path;
      let belongsToChecked = false;
      for (let j = 0; j < checked.length; j++) {
        if (entryPath.indexOf(checked[j] + '/') === 0) {
          belongsToChecked = true;
          break;
        }
      }
      if (!belongsToChecked) {
        next.push(this.downloadManifestEntries[i]);
      }
    }
    let drift = 0;
    for (let j = 0; j < checked.length; j++) {
      const listing = await client.list(DOWNLOADS_FOLDER + '/' + checked[j]);
      if (!listing.ok) {
        continue;
      }
      for (let k = 0; k < listing.entries.length; k++) {
        const entry = listing.entries[k];
        if (entry.isDirectory) {
          continue;
        }
        const path = checked[j] + '/' + entry.name;
        const known = oldByPath.get(path);
        if (known === undefined || known.size !== entry.size ||
          (entry.etag !== undefined && known.etag !== undefined && known.etag !== entry.etag)) {
          drift++;
        }
        next.push({
          path: path,
          size: entry.size,
          mtime: entry.modifiedAt,
          etag: entry.etag
        });
      }
    }
    if (drift > 0 || checked.length > 0) {
      this.downloadManifestEntries = next;
      const manifest: DownloadManifest = { version: 1, updatedAt: now, files: next };
      const uploaded = await client.putText(DOWNLOAD_MANIFEST_FILE, JSON.stringify(manifest));
      if (uploaded.ok) {
        const refreshed = await client.list(DOWNLOAD_MANIFEST_FILE);
        this.downloadManifestMtime = refreshed.ok && refreshed.entries.length > 0 ?
          refreshed.entries[0].modifiedAt : now;
      }
      logRemoteStorageInfo('manifest reconcile checked=' + checked.length.toString() +
        ' drift=' + drift.toString());
    }
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
      ehLocalFavoritesStore.ensureLoaded(context),
      ehDownloadStore.load(context)
    ]);
    const history: GalleryInfo[] = ehHistoryStore.getItems();
    const historySlice = history.length > MAX_SYNC_HISTORY_ITEMS ?
      history.slice(history.length - MAX_SYNC_HISTORY_ITEMS) : history;
    const sections: RemoteSyncSection[] = [
      { name: 'settings_' + this.deviceId, data: this.wrapSection(ehSettingsStore.getTransferEntries()) },
      { name: 'bookmarks', data: this.wrapSection(ehBookmarkStore.getBackupItems()) },
      { name: 'localFavorites', data: this.wrapSection(ehLocalFavoritesStore.getBackupItems()) },
      { name: 'blacklist', data: this.wrapSection(ehCommentBlacklistStore.getBackupItems()) },
      { name: 'filters', data: JSON.stringify(ehFilterStore.getRules()) },
      { name: 'searchHistory', data: JSON.stringify(ehSearchHistoryStore.getKeywords()) },
      { name: 'browsePositions', data: JSON.stringify(ehBrowsePositionStore.getBackupInfo()) },
      { name: 'readingProgress', data: JSON.stringify(ehHistoryStore.getReadingProgressBackupItems()) },
      { name: 'history', data: this.wrapSection(historySlice) },
      { name: 'downloadLabels', data: JSON.stringify(ehDownloadStore.getLabels()) },
      { name: 'remoteStorage', data: JSON.stringify(profilesWithoutPasswords(remoteStorageProfileStore.getProfiles())) },
      {
        name: SYNC_SECTION_READER_PRESETS,
        data: JSON.stringify(parseCustomReaderPresetProfiles(
          ehSettingsStore.getValue(READER_CUSTOM_PRESETS_SETTING_KEY, '[]')))
      },
      {
        name: SYNC_SECTION_TRANSLATION_PROMPTS,
        data: JSON.stringify(parseCustomTranslationPromptProfiles(
          ehSettingsStore.getValue(TRANSLATION_CUSTOM_PROMPTS_KEY, '[]')))
      }
    ];
    await syncTombstoneStore.ensureLoaded(context);
    return sections;
  }

  // Shared lists are wrapped with the writing device and timestamp: the same device can just
  // overwrite its own copy, while other devices merge before writing back.
  private wrapSection(payload: Object): string {
    const envelope: SyncSectionEnvelope = {
      deviceId: this.deviceId,
      deviceName: this.deviceName,
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
        ehHistoryStore.ensureLoaded(context),
        ehDownloadStore.ensureLoaded(context),
        ehLocalFavoritesStore.ensureLoaded(context),
        syncTombstoneStore.ensureLoaded(context)
      ]);
      await this.mergeRemoteTombstones(context, client);
      for (let i = 0; i < manifest.sections.length; i++) {
        await this.applySection(context, client, manifest.sections[i]);
      }
      await this.applyTombstones(context);
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
            ehFilterStore.addRule(ruleMode, ruleText, rules[i].enabled !== false, false);
          }
        }
        await ehFilterStore.save(context);
      } else if (name === 'blacklist') {
        ehCommentBlacklistStore.importBackupItems(JSON.parse(content) as CommentBlacklistBackupEntry[]);
        await ehCommentBlacklistStore.save(context);
      } else if (name === 'downloadLabels') {
        const labels = JSON.parse(content) as string[];
        for (let i = 0; i < labels.length; i++) {
          if (typeof labels[i] === 'string') {
            ehDownloadStore.addLabel(labels[i], false);
          }
        }
        await ehDownloadStore.save(context);
      } else if (name === 'remoteStorage') {
        const profiles = JSON.parse(content) as RemoteStorageProfile[];
        for (let i = 0; i < profiles.length; i++) {
          if (remoteStorageProfileStore.getProfile(profiles[i].id) === null) {
            await remoteStorageProfileStore.upsert(context, profiles[i], false);
          }
        }
      } else if (name === SYNC_SECTION_READER_PRESETS) {
        const remoteProfiles = parseCustomReaderPresetProfiles(content);
        const localProfiles = parseCustomReaderPresetProfiles(
          ehSettingsStore.getValue(READER_CUSTOM_PRESETS_SETTING_KEY, '[]'));
        const merged = mergeCustomProfiles(localProfiles, remoteProfiles);
        ehSettingsStore.setValue(READER_CUSTOM_PRESETS_SETTING_KEY, serializeCustomReaderPresetProfiles(merged));
        await ehSettingsStore.save(context);
      } else if (name === SYNC_SECTION_TRANSLATION_PROMPTS) {
        const remoteProfiles = parseCustomTranslationPromptProfiles(content);
        const localProfiles = parseCustomTranslationPromptProfiles(
          ehSettingsStore.getValue(TRANSLATION_CUSTOM_PROMPTS_KEY, '[]'));
        const merged = mergeCustomProfiles(localProfiles, remoteProfiles);
        ehSettingsStore.setValue(TRANSLATION_CUSTOM_PROMPTS_KEY, serializeCustomTranslationPromptProfiles(merged));
        await ehSettingsStore.save(context);
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

  private async mergeRemoteTombstones(context: common.UIAbilityContext, client: WebDavClient): Promise<void> {
    await syncTombstoneStore.ensureLoaded(context);
    const file = await client.getText(TOMBSTONES_FILE);
    if (file.ok && file.text.length > 0) {
      const merged = syncTombstoneStore.mergeRemoteText(file.text);
      if (merged > 0) {
        logRemoteStorageInfo('sync tombstones merged sections=' + merged.toString());
      }
    }
    syncTombstoneStore.prune(TOMBSTONE_MAX_AGE_MS);
  }

  private tombstoneRecords(section: string): SyncTombstoneLike[] {
    const records: SyncTombstoneLike[] = [];
    const all = syncTombstoneStore.list(section);
    for (let i = 0; i < all.length; i++) {
      if (all[i].cleared !== true) {
        records.push(all[i]);
      }
    }
    return records;
  }

  private async applyTombstones(context: common.UIAbilityContext): Promise<void> {
    await syncTombstoneStore.ensureLoaded(context);
    let historyChanged = false;
    const historyRecords = this.tombstoneRecords(SYNC_SECTION_HISTORY);
    if (historyRecords.length > 0) {
      const items = ehHistoryStore.getItems();
      for (let i = 0; i < historyRecords.length; i++) {
        const key = historyRecords[i].key;
        for (let j = 0; j < items.length; j++) {
          const historyTime = typeof items[j].historyTime === 'number' ? items[j].historyTime as number : 0;
          if (items[j].gid.toString() === key && syncTombstoneShouldDelete(historyRecords[i], historyTime)) {
            ehHistoryStore.removeGallery(items[j].gid);
            historyChanged = true;
            break;
          }
        }
      }
    }
    let progressChanged = false;
    const progressRecords = this.tombstoneRecords(SYNC_SECTION_READING_PROGRESS);
    if (progressRecords.length > 0) {
      const positions = ehHistoryStore.getReadingProgressBackupItems();
      for (let i = 0; i < progressRecords.length; i++) {
        const key = progressRecords[i].key;
        for (let j = 0; j < positions.length; j++) {
          if (positions[j].gid.toString() === key &&
            syncTombstoneShouldDelete(progressRecords[i], positions[j].progressUpdatedAt)) {
            ehHistoryStore.removeReadingProgress(positions[j].gid);
            progressChanged = true;
            break;
          }
        }
      }
    }
    if (historyChanged || progressChanged) {
      await ehHistoryStore.save(context);
    }

    let bookmarksChanged = false;
    const bookmarkRecords = this.tombstoneRecords(SYNC_SECTION_BOOKMARKS);
    if (bookmarkRecords.length > 0) {
      const bookmarks = ehBookmarkStore.getBackupItems();
      for (let i = 0; i < bookmarkRecords.length; i++) {
        const key = bookmarkRecords[i].key;
        for (let j = 0; j < bookmarks.length; j++) {
          const id = bookmarks[j].id === undefined ? '' : bookmarks[j].id;
          const time = typeof bookmarks[j].time === 'number' ? bookmarks[j].time as number : 0;
          if (id === key && syncTombstoneShouldDelete(bookmarkRecords[i], time)) {
            ehBookmarkStore.removeBookmark(id);
            bookmarksChanged = true;
            break;
          }
        }
      }
    }
    if (bookmarksChanged) {
      await ehBookmarkStore.save(context);
    }

    let favoritesChanged = false;
    const favoriteRecords = this.tombstoneRecords(SYNC_SECTION_LOCAL_FAVORITES);
    if (favoriteRecords.length > 0) {
      const favorites = ehLocalFavoritesStore.getBackupItems();
      for (let i = 0; i < favoriteRecords.length; i++) {
        const key = favoriteRecords[i].key;
        for (let j = 0; j < favorites.length; j++) {
          const gid = typeof favorites[j].gid === 'number' ? favorites[j].gid as number : 0;
          const time = typeof favorites[j].time === 'number' ? favorites[j].time as number : 0;
          if (gid > 0 && gid.toString() === key && syncTombstoneShouldDelete(favoriteRecords[i], time)) {
            ehLocalFavoritesStore.removeGallery(gid);
            favoritesChanged = true;
            break;
          }
        }
      }
    }
    if (favoritesChanged) {
      await ehLocalFavoritesStore.save(context);
    }

    let blacklistChanged = false;
    const blacklistRecords = this.tombstoneRecords(SYNC_SECTION_BLACKLIST);
    if (blacklistRecords.length > 0) {
      const entries = ehCommentBlacklistStore.getBackupItems();
      for (let i = 0; i < blacklistRecords.length; i++) {
        const key = blacklistRecords[i].key;
        for (let j = 0; j < entries.length; j++) {
          const user = typeof entries[j].user === 'string' ? entries[j].user as string : '';
          const id = typeof entries[j].id === 'string' ? entries[j].id as string : '';
          const addedAt = typeof entries[j].addedAt === 'number' ? entries[j].addedAt as number : 0;
          if (user === key && id.length > 0 && syncTombstoneShouldDelete(blacklistRecords[i], addedAt)) {
            ehCommentBlacklistStore.removeEntry(id);
            blacklistChanged = true;
            break;
          }
        }
      }
    }
    if (blacklistChanged) {
      await ehCommentBlacklistStore.save(context);
    }

    let filtersChanged = false;
    const filterRecords = this.tombstoneRecords(SYNC_SECTION_FILTERS);
    if (filterRecords.length > 0) {
      const rules = ehFilterStore.getRules();
      for (let i = 0; i < filterRecords.length; i++) {
        const key = filterRecords[i].key;
        for (let j = 0; j < rules.length; j++) {
          if (filterTombstoneKey(rules[j].mode, rules[j].text) === key &&
            syncTombstoneShouldDelete(filterRecords[i], 0)) {
            ehFilterStore.removeRule(rules[j].id);
            filtersChanged = true;
            break;
          }
        }
      }
    }
    if (filtersChanged) {
      await ehFilterStore.save(context);
    }

    let searchHistoryChanged = false;
    const searchRecords = this.tombstoneRecords(SYNC_SECTION_SEARCH_HISTORY);
    if (searchRecords.length > 0) {
      const keywords = ehSearchHistoryStore.getKeywords();
      for (let i = 0; i < searchRecords.length; i++) {
        const key = searchRecords[i].key;
        for (let j = 0; j < keywords.length; j++) {
          if (keywordTombstoneKey(keywords[j]) === key && syncTombstoneShouldDelete(searchRecords[i], 0)) {
            ehSearchHistoryStore.removeKeyword(keywords[j]);
            searchHistoryChanged = true;
            break;
          }
        }
      }
    }
    if (searchHistoryChanged) {
      await ehSearchHistoryStore.save(context);
    }

    let labelsChanged = false;
    const labelRecords = this.tombstoneRecords(SYNC_SECTION_DOWNLOAD_LABELS);
    if (labelRecords.length > 0) {
      const labels = ehDownloadStore.getLabels();
      for (let i = 0; i < labelRecords.length; i++) {
        const key = labelRecords[i].key;
        for (let j = 0; j < labels.length; j++) {
          if (labels[j].label === key && syncTombstoneShouldDelete(labelRecords[i], labels[j].time)) {
            ehDownloadStore.removeLabel(labels[j].label);
            labelsChanged = true;
            break;
          }
        }
      }
    }
    if (labelsChanged) {
      await ehDownloadStore.save(context);
    }

    const profileRecords = this.tombstoneRecords(SYNC_SECTION_REMOTE_STORAGE);
    for (let i = 0; i < profileRecords.length; i++) {
      const profile = remoteStorageProfileStore.getProfile(profileRecords[i].key);
      if (profile !== null && syncTombstoneShouldDelete(profileRecords[i], profile.updatedAt)) {
        await remoteStorageProfileStore.remove(context, profile.id);
      }
    }

    this.applyCustomProfileTombstones(context, READER_CUSTOM_PRESETS_SETTING_KEY,
      (raw: string): CustomProfileLike[] => parseCustomReaderPresetProfiles(raw),
      (profiles: CustomProfileLike[]): string =>
        serializeCustomReaderPresetProfiles(profiles as ReaderPresetProfile[]),
      SYNC_SECTION_READER_PRESETS);
    this.applyCustomProfileTombstones(context, TRANSLATION_CUSTOM_PROMPTS_KEY,
      (raw: string): CustomProfileLike[] => parseCustomTranslationPromptProfiles(raw),
      (profiles: CustomProfileLike[]): string =>
        serializeCustomTranslationPromptProfiles(profiles as TranslationPromptProfile[]),
      SYNC_SECTION_TRANSLATION_PROMPTS);
  }

  private applyCustomProfileTombstones(context: common.UIAbilityContext, settingKey: string,
    parse: (raw: string) => CustomProfileLike[], serialize: (profiles: CustomProfileLike[]) => string,
    section: string): void {
    const records = this.tombstoneRecords(section);
    if (records.length === 0) {
      return;
    }
    const localProfiles = parse(ehSettingsStore.getValue(settingKey, '[]'));
    const kept: CustomProfileLike[] = [];
    let changed = false;
    for (let i = 0; i < localProfiles.length; i++) {
      let deleted = false;
      for (let j = 0; j < records.length; j++) {
        if (records[j].key === localProfiles[i].id &&
          syncTombstoneShouldDelete(records[j], 0)) {
          deleted = true;
          break;
        }
      }
      if (deleted) {
        changed = true;
      } else {
        kept.push(localProfiles[i]);
      }
    }
    if (changed) {
      ehSettingsStore.setValue(settingKey, serialize(kept));
      ehSettingsStore.save(context).catch(() => {
      });
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
    // Pending cloud deletions first, then other devices' deletion tombstones; both run even when
    // nothing new needs to be mirrored.
    await remoteStorageDownloadDeletionService.processPendingWithClient(context, client, profile);
    await remoteStorageDownloadDeletionService.applyRemoteTombstones(context, client);
    await this.reconcileManifestIfDue(client);
    // Plan first so the total progress bar and transfer rate cover the whole batch.
    const plan: MirrorGalleryPlan[] = [];
    const uploadedUpdates: DownloadManifestEntry[] = [];
    const galleryComplete: boolean[] = [];
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
          return client.putBinaryResumable(gallery.remoteDir + '/' + fileName, data)
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
        await new Promise<void>((resolve: () => void) => {
          setTimeout(resolve, 30);
        });
      }
      galleryComplete.push(uploadedHere >= gallery.files.length);
    }
    if (uploadedFiles > 0) {
      logRemoteStorageInfo('download mirror uploaded files=' + uploadedFiles.toString() +
        ' bytes=' + uploadedBytes.toString());
    }
    const etagByPath = new Map<string, string>();
    for (let i = 0; i < plan.length; i++) {
      const galleryListing = await client.list(plan[i].remoteDir);
      if (!galleryListing.ok) {
        continue;
      }
      for (let j = 0; j < galleryListing.entries.length; j++) {
        const galleryEntry = galleryListing.entries[j];
        if (galleryEntry.etag !== undefined && galleryEntry.etag.length > 0) {
          etagByPath.set(plan[i].name + '/' + galleryEntry.name, galleryEntry.etag);
        }
      }
    }
    for (let i = 0; i < uploadedUpdates.length; i++) {
      const entryEtag = etagByPath.get(uploadedUpdates[i].path);
      if (entryEtag !== undefined) {
        uploadedUpdates[i].etag = entryEtag;
      }
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
    if (ehSettingsStore.getValue('download_location', 'App files') === 'Remote server') {
      for (let i = 0; i < plan.length; i++) {
        if (galleryComplete[i]) {
          try {
            fs.rmdirSync(plan[i].localDir);
          } catch (error) {
          }
        }
      }
      remoteStorageDownloadDeletionService.invalidateDirectoryCache();
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
      const nameId = resolveDeviceIdentity(context);
      this.deviceName = resolveDeviceDisplayName(context);
      this.deviceId = nameId.length > 0 ? nameId :
        (typeof deviceId === 'string' && deviceId.length > 0 ? deviceId :
          ('device_' + Date.now().toString() + '_' + Math.floor(Math.random() * 100000).toString()));
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

interface CustomProfileLike {
  id: string;
}

interface FilterRuleLike {
  mode?: number;
  text?: string;
  enabled?: boolean;
}

function mergeCustomProfiles<T extends CustomProfileLike>(local: T[], remote: T[]): T[] {
  const localIds: string[] = [];
  for (let i = 0; i < local.length; i++) {
    localIds.push(local[i].id);
  }
  const merged: T[] = local.slice();
  for (let i = 0; i < remote.length; i++) {
    const id = remote[i].id;
    if (typeof id === 'string' && id.length > 0 && localIds.indexOf(id) < 0) {
      merged.push(remote[i]);
      localIds.push(id);
    }
  }
  return merged;
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

// Device name is user visible and stable across reinstalls (renaming produces a new identity and
// one extra merge). Falls back to the market/model pair when the setting is not readable.
function resolveDeviceDisplayName(context: common.UIAbilityContext): string {
  let name = '';
  try {
    name = settings.getValueSync(context, settings.general.DEVICE_NAME, '');
  } catch (error) {
    name = '';
  }
  if (name.length === 0) {
    name = deviceInfo.marketName;
  }
  const model = deviceInfo.productModel.length > 0 ? deviceInfo.productModel : deviceInfo.hardwareModel;
  const parts: string[] = [];
  if (name.length > 0) {
    parts.push(name);
  }
  if (model.length > 0) {
    parts.push(model);
  }
  return parts.join(' ');
}

function resolveDeviceIdentity(context: common.UIAbilityContext): string {
  const display = resolveDeviceDisplayName(context);
  if (display.length === 0) {
    return '';
  }
  const model = deviceInfo.productModel.length > 0 ? deviceInfo.productModel : deviceInfo.hardwareModel;
  let name = '';
  try {
    name = settings.getValueSync(context, settings.general.DEVICE_NAME, '');
  } catch (error) {
    name = '';
  }
  if (name.length === 0) {
    name = deviceInfo.marketName;
  }
  if (name.length === 0) {
    name = display;
  }
  return 'device_' + sanitizeDeviceToken(name) + '_' + sanitizeDeviceToken(model);
}

function sanitizeDeviceToken(value: string): string {
  const trimmed = value.trim().replace(/\s+/g, '-');
  const safe = trimmed.replace(/[^A-Za-z0-9_-]/g, '');
  return safe.length > 0 ? safe.substring(0, 48) : 'unknown';
}

function profilesWithoutPasswords(profiles: RemoteStorageProfile[]): RemoteStorageProfile[] {
  const result: RemoteStorageProfile[] = [];
  for (let i = 0; i < profiles.length; i++) {
    const profile = profiles[i];
    result.push({
      id: profile.id,
      name: profile.name,
      kind: profile.kind,
      url: profile.url,
      port: profile.port,
      username: profile.username,
      password: '',
      basePath: profile.basePath,
      useForBackup: profile.useForBackup,
      useForSync: profile.useForSync,
      useForDownloads: profile.useForDownloads,
      updatedAt: profile.updatedAt
    });
  }
  return result;
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
