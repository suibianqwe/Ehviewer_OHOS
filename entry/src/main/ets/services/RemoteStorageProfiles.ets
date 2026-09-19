import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  createRemoteStorageProfileId,
  isValidRemoteStorageUrl,
  normalizeRemoteStorageBasePath,
  normalizeRemoteStoragePort,
  normalizeRemoteStorageUrl,
  remoteStorageApplyPort,
  remoteStorageHost,
  remoteStoragePortFromUrl
} from './RemoteStorageSupport';
import { syncTombstoneStore } from './SyncTombstoneStore';

const SYNC_SECTION_REMOTE_STORAGE: string = 'remoteStorage';

export const REMOTE_STORAGE_KIND_WEBDAV: string = 'webdav';
export const REMOTE_STORAGE_PURPOSE_BACKUP: string = 'backup';
export const REMOTE_STORAGE_PURPOSE_SYNC: string = 'sync';
export const REMOTE_STORAGE_PURPOSE_DOWNLOADS: string = 'downloads';
export const REMOTE_STORAGE_REVISION_KEY: string = 'remoteStorageRevision';

const PREFERENCES_NAME: string = 'ehviewer_remote_storage';
const PROFILES_KEY: string = 'profiles';
const MAX_REMOTE_STORAGE_PROFILES: number = 12;

export interface RemoteStorageProfile {
  id: string;
  name: string;
  kind: string;
  url: string;
  port: string;
  username: string;
  password: string;
  basePath: string;
  useForBackup: boolean;
  useForSync: boolean;
  useForDownloads: boolean;
  ignoreCertificate: boolean;
  updatedAt: number;
}

export function remoteStorageKindLabel(kind: string): string {
  return kind === REMOTE_STORAGE_KIND_WEBDAV ? 'WebDAV' : kind;
}

export function normalizeRemoteStorageProfile(profile: RemoteStorageProfile): RemoteStorageProfile {
  const url = normalizeRemoteStorageUrl(profile.url);
  let port = typeof profile.port === 'string' ? normalizeRemoteStoragePort(profile.port) : '';
  // HTTPS 未显式填写端口时使用 5006 作为默认端口（本项目的服务端约定）。
  if (port.length === 0 && remoteStoragePortFromUrl(url).length === 0 &&
    url.toLowerCase().indexOf('https://') === 0) {
    port = '5006';
  }
  return {
    id: profile.id.trim().length > 0 ? profile.id.trim() : createRemoteStorageProfileId(),
    name: profile.name.trim(),
    kind: profile.kind === REMOTE_STORAGE_KIND_WEBDAV ? profile.kind : REMOTE_STORAGE_KIND_WEBDAV,
    url: url,
    port: port,
    username: profile.username.trim(),
    password: profile.password,
    basePath: normalizeRemoteStorageBasePath(profile.basePath),
    useForBackup: profile.useForBackup,
    useForSync: profile.useForSync,
    useForDownloads: profile.useForDownloads,
    ignoreCertificate: profile.ignoreCertificate === true,
    updatedAt: profile.updatedAt > 0 ? profile.updatedAt : Date.now()
  };
}

export function remoteStorageProfileDisplayName(profile: RemoteStorageProfile): string {
  if (profile.name.length > 0) {
    return profile.name;
  }
  const host = remoteStorageHost(profile.url);
  return host.length > 0 ? host : remoteStorageKindLabel(profile.kind);
}

export function remoteStorageProfilePurposeLabels(profile: RemoteStorageProfile): string {
  const labels: string[] = [];
  if (profile.useForBackup) {
    labels.push('Backup');
  }
  if (profile.useForSync) {
    labels.push('Sync');
  }
  if (profile.useForDownloads) {
    labels.push('Downloads');
  }
  return labels.join(' · ');
}

export function remoteStorageProfileSummary(profile: RemoteStorageProfile): string {
  const host = remoteStorageHost(remoteStorageApplyPort(profile.url, profile.port));
  const base = profile.basePath.length > 0 ? profile.basePath : '/';
  return host.length > 0 ? host + ' · ' + base : base;
}

export function remoteStorageProfileForPurpose(profiles: RemoteStorageProfile[], purpose: string): RemoteStorageProfile | null {
  for (let i = 0; i < profiles.length; i++) {
    const profile = profiles[i];
    if ((purpose === REMOTE_STORAGE_PURPOSE_BACKUP && profile.useForBackup) ||
      (purpose === REMOTE_STORAGE_PURPOSE_SYNC && profile.useForSync) ||
      (purpose === REMOTE_STORAGE_PURPOSE_DOWNLOADS && profile.useForDownloads)) {
      return profile;
    }
  }
  return null;
}

export function cloneRemoteStorageProfiles(profiles: RemoteStorageProfile[]): RemoteStorageProfile[] {
  const cloned: RemoteStorageProfile[] = [];
  for (let i = 0; i < profiles.length; i++) {
    cloned.push(normalizeRemoteStorageProfile(profiles[i]));
  }
  return cloned;
}

export function parseRemoteStorageProfiles(raw: string): RemoteStorageProfile[] {
  const parsed: RemoteStorageProfile[] = [];
  if (raw.trim().length === 0) {
    return parsed;
  }
  try {
    const value = JSON.parse(raw) as RemoteStorageProfile[] | null;
    if (value === null || !Array.isArray(value)) {
      return parsed;
    }
    for (let i = 0; i < value.length && parsed.length < MAX_REMOTE_STORAGE_PROFILES; i++) {
      const item = value[i];
      if (item === null || item === undefined || typeof item !== 'object') {
        continue;
      }
      const profile = normalizeRemoteStorageProfile(item);
      if (isValidRemoteStorageUrl(profile.url)) {
        parsed.push(profile);
      }
    }
  } catch (error) {
    return parsed;
  }
  return parsed;
}

export class RemoteStorageProfileStore {
  private items: RemoteStorageProfile[] = [];
  private loaded: boolean = false;
  private context: common.UIAbilityContext | null = null;

  async ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.context = context;
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const raw = await prefs.get(PROFILES_KEY, '[]');
      this.items = parseRemoteStorageProfiles(typeof raw === 'string' ? raw : '[]');
    } catch (error) {
      this.items = [];
    }
    this.loaded = true;
  }

  getProfiles(): RemoteStorageProfile[] {
    return cloneRemoteStorageProfiles(this.items);
  }

  getProfile(id: string): RemoteStorageProfile | null {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        return normalizeRemoteStorageProfile(this.items[i]);
      }
    }
    return null;
  }

  profileForPurpose(purpose: string): RemoteStorageProfile | null {
    return remoteStorageProfileForPurpose(this.items, purpose);
  }

  async upsert(context: common.UIAbilityContext, profile: RemoteStorageProfile,
    recordClear: boolean = true): Promise<RemoteStorageProfile | null> {
    await this.ensureLoaded(context);
    this.context = context;
    const normalized = normalizeRemoteStorageProfile(profile);
    if (!isValidRemoteStorageUrl(normalized.url)) {
      return null;
    }
    if (recordClear) {
      syncTombstoneStore.recordClear(context, SYNC_SECTION_REMOTE_STORAGE, normalized.id);
    }
    let replaced = false;
    const next: RemoteStorageProfile[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === normalized.id) {
        next.push(normalized);
        replaced = true;
      } else {
        next.push(normalizeRemoteStorageProfile(this.items[i]));
      }
    }
    if (!replaced) {
      if (next.length >= MAX_REMOTE_STORAGE_PROFILES) {
        return null;
      }
      next.push(normalized);
    }
    this.items = next;
    await this.persist();
    this.notifyChanged();
    return normalized;
  }

  async remove(context: common.UIAbilityContext, id: string): Promise<boolean> {
    await this.ensureLoaded(context);
    this.context = context;
    const next: RemoteStorageProfile[] = [];
    let removed = false;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        removed = true;
      } else {
        next.push(this.items[i]);
      }
    }
    if (!removed) {
      return false;
    }
    this.items = next;
    syncTombstoneStore.recordDeletion(context, SYNC_SECTION_REMOTE_STORAGE, id);
    await this.persist();
    this.notifyChanged();
    return true;
  }

  private async persist(): Promise<void> {
    const context = this.context;
    if (context === null) {
      return;
    }
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(PROFILES_KEY, JSON.stringify(this.items));
      await prefs.flush();
    } catch (error) {
    }
  }

  private notifyChanged(): void {
    const revision = AppStorage.get<number>(REMOTE_STORAGE_REVISION_KEY) ?? 0;
    AppStorage.setOrCreate<number>(REMOTE_STORAGE_REVISION_KEY, revision + 1);
  }
}

export const remoteStorageProfileStore = new RemoteStorageProfileStore();
