import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ehBookmarkStore, SearchBookmarkBackupInfo } from './EhBookmarkStore';
import { ehBrowsePositionStore, BrowsePositionsBackupInfo } from './EhBrowsePositionStore';
import { ehCommentBlacklistStore, CommentBlacklistBackupEntry } from './EhCommentBlacklistStore';
import { ehFilterStore } from './EhFilterStore';
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
export const REMOTE_SYNC_DETAIL_VISIBLE_KEY: string = 'remoteSyncDetailVisible';

const PREFERENCES_NAME: string = 'ehviewer_remote_sync';
const LAST_SYNC_KEY: string = 'lastSyncAt';
const LAST_PULL_KEY: string = 'lastPulledAt';
const FINGERPRINT_KEY: string = 'lastFingerprint';
const SERVER_TIMES_KEY: string = 'serverTimes';
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
    this.publishStatus(profile, uiText('Pending sync'), '');
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
            await this.applySection(context, client, entry.name.substring(0, entry.name.length - 5));
          }
          this.recordServerTimes(listing.entries);
        }
      }
      const sections = await this.buildSections(context);
      for (let i = 0; i < sections.length; i++) {
        this.publishProgress(uiText('Syncing configuration…'), this.sectionLabel(sections[i].name),
          Math.round(i * 100 / sections.length));
        const uploaded = await client.putText(SYNC_FOLDER + '/' + sections[i].name + '.json', sections[i].data);
        if (!uploaded.ok) {
          throw new Error(sections[i].name + ': ' + uploaded.message);
        }
        this.publishProgress(uiText('Syncing configuration…'), this.sectionLabel(sections[i].name),
          Math.round((i + 1) * 100 / sections.length));
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
    this.schedule(FINGERPRINT_INTERVAL_MS);
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
      ehHistoryStore.ensureLoaded(context)
    ]);
    const history: GalleryInfo[] = ehHistoryStore.getItems();
    const historySlice = history.length > MAX_SYNC_HISTORY_ITEMS ?
      history.slice(history.length - MAX_SYNC_HISTORY_ITEMS) : history;
    const sections: RemoteSyncSection[] = [
      { name: 'settings', data: JSON.stringify(ehSettingsStore.getTransferEntries()) },
      { name: 'bookmarks', data: JSON.stringify(ehBookmarkStore.getBackupItems()) },
      { name: 'filters', data: JSON.stringify(ehFilterStore.getRules()) },
      { name: 'blacklist', data: JSON.stringify(ehCommentBlacklistStore.getBackupItems()) },
      { name: 'searchHistory', data: JSON.stringify(ehSearchHistoryStore.getKeywords()) },
      { name: 'browsePositions', data: JSON.stringify(ehBrowsePositionStore.getBackupInfo()) },
      { name: 'readingProgress', data: JSON.stringify(ehHistoryStore.getReadingProgressBackupItems()) },
      { name: 'history', data: JSON.stringify(historySlice) }
    ];
    return sections;
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
    try {
      if (name === 'settings') {
        ehSettingsStore.importEntries(JSON.parse(file.text) as SettingEntry[]);
        await ehSettingsStore.save(context);
      } else if (name === 'bookmarks') {
        ehBookmarkStore.importBackupItems(JSON.parse(file.text) as SearchBookmarkBackupInfo[]);
        await ehBookmarkStore.save(context);
      } else if (name === 'filters') {
        const rules = JSON.parse(file.text) as FilterRuleLike[];
        for (let i = 0; i < rules.length; i++) {
          const ruleMode = rules[i].mode;
          const ruleText = rules[i].text;
          if (typeof ruleText === 'string' && typeof ruleMode === 'number') {
            ehFilterStore.addRule(ruleMode, ruleText, rules[i].enabled !== false);
          }
        }
        await ehFilterStore.save(context);
      } else if (name === 'blacklist') {
        ehCommentBlacklistStore.importBackupItems(JSON.parse(file.text) as CommentBlacklistBackupEntry[]);
        await ehCommentBlacklistStore.save(context);
      } else if (name === 'searchHistory') {
        ehSearchHistoryStore.importKeywords(JSON.parse(file.text) as string[]);
        await ehSearchHistoryStore.save(context);
      } else if (name === 'browsePositions') {
        ehBrowsePositionStore.importBackupInfo(JSON.parse(file.text) as BrowsePositionsBackupInfo);
        await ehBrowsePositionStore.save(context);
      } else if (name === 'readingProgress') {
        ehHistoryStore.importReadingProgressBackupItems(JSON.parse(file.text) as ReadingProgressBackupInfo[]);
        await ehHistoryStore.save(context);
      } else if (name === 'history') {
        const items = JSON.parse(file.text) as GalleryInfo[];
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
    let uploaded = 0;
    let galleries = 0;
    const startedAt = Date.now();
    for (let i = 0; i < galleryNames.length; i++) {
      if (galleries >= MAX_MIRROR_GALLERIES_PER_CYCLE || uploaded >= MAX_MIRROR_FILES_PER_CYCLE ||
        Date.now() - startedAt >= MIRROR_TIME_BUDGET_MS) {
        break;
      }
      const galleryName = galleryNames[i];
      const localDir = root + '/' + galleryName;
      let directory = false;
      try {
        directory = fs.statSync(localDir).isDirectory();
      } catch (error) {
        directory = false;
      }
      if (!directory) {
        continue;
      }
      const remoteDir = DOWNLOADS_FOLDER + '/' + galleryName;
      const existing: string[] = [];
      const listing = await client.list(remoteDir);
      if (listing.ok) {
        for (let j = 0; j < listing.entries.length; j++) {
          if (!listing.entries[j].isDirectory) {
            existing.push(listing.entries[j].name);
          }
        }
      }
      let fileNames: string[] = [];
      try {
        fileNames = fs.listFileSync(localDir);
      } catch (error) {
        continue;
      }
      const pending: string[] = [];
      for (let j = 0; j < fileNames.length; j++) {
        if (existing.indexOf(fileNames[j]) < 0) {
          pending.push(fileNames[j]);
        }
      }
      let uploadedHere = 0;
      if (pending.length > 0) {
        this.publishProgress(uiText('Downloading files'), galleryName, 0);
      }
      for (let j = 0; j < pending.length; j += MIRROR_CONCURRENCY) {
        if (uploaded >= MAX_MIRROR_FILES_PER_CYCLE || Date.now() - startedAt >= MIRROR_TIME_BUDGET_MS) {
          break;
        }
        const batch: string[] = pending.slice(j, j + MIRROR_CONCURRENCY);
        const results = await Promise.all(batch.map((fileName: string): Promise<boolean> => {
          const data = readFileBuffer(localDir + '/' + fileName);
          if (data === null) {
            return Promise.resolve(false);
          }
          return client.putBinary(remoteDir + '/' + fileName, data)
            .then((result: RemoteStorageResult): boolean => result.ok);
        }));
        for (let k = 0; k < results.length; k++) {
          if (results[k]) {
            uploaded++;
            uploadedHere++;
          }
        }
        this.publishProgress(uiText('Downloading files'), galleryName + ' · ' + batch[batch.length - 1],
          Math.min(100, Math.round(uploadedHere * 100 / Math.max(1, pending.length))));
      }
      if (uploadedHere > 0) {
        galleries++;
      }
    }
    if (uploaded > 0) {
      logRemoteStorageInfo('download mirror uploaded files=' + uploaded.toString());
    }
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

  private publishProgress(title: string, detail: string, percent: number): void {
    AppStorage.setOrCreate<string>(REMOTE_SYNC_PROGRESS_TITLE_KEY, title);
    AppStorage.setOrCreate<string>(REMOTE_SYNC_PROGRESS_DETAIL_KEY, detail);
    AppStorage.setOrCreate<number>(REMOTE_SYNC_PROGRESS_PERCENT_KEY, percent);
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
