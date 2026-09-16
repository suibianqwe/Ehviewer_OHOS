import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { GalleryComment } from '../model/GalleryModels';

import { syncTombstoneStore } from './SyncTombstoneStore';

const PREFERENCES_NAME: string = 'ehviewer_comment_blacklist';
const SYNC_SECTION_BLACKLIST: string = 'blacklist';
const VALUES_KEY: string = 'items';

export const COMMENT_BLACKLIST_REVISION_KEY: string = 'ehviewer_comment_blacklist_revision';

export interface CommentBlacklistBackupEntry {
  id?: string;
  user?: string;
  reason?: string;
  sourceComment?: string;
  addedAt?: number;
}

export interface CommentBlacklistEntry {
  id: string;
  user: string;
  reason: string;
  sourceComment: string;
  addedAt: number;
}

export class EhCommentBlacklistStore {
  private entries: CommentBlacklistEntry[] = [];
  private context: common.UIAbilityContext | undefined = undefined;
  private loaded: boolean = false;
  private loadPromise: Promise<void> | null = null;
  private saveChain: Promise<void> = Promise.resolve();

  async ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    if (this.loaded) {
      return;
    }
    if (this.loadPromise !== null) {
      return this.loadPromise;
    }
    this.loadPromise = this.load(context);
    return this.loadPromise;
  }

  getEntries(): CommentBlacklistEntry[] {
    return cloneEntries(this.entries);
  }

  getBackupItems(): CommentBlacklistBackupEntry[] {
    return this.entries.map((entry: CommentBlacklistEntry): CommentBlacklistBackupEntry => ({
      id: entry.id,
      user: entry.user,
      reason: entry.reason,
      sourceComment: entry.sourceComment,
      addedAt: entry.addedAt
    }));
  }

  count(): number {
    return this.entries.length;
  }

  isBlockedUser(user: string): boolean {
    const key = normalizeUserKey(user);
    if (key.length === 0) {
      return false;
    }
    for (let i = 0; i < this.entries.length; i++) {
      if (normalizeUserKey(this.entries[i].user) === key) {
        return true;
      }
    }
    return false;
  }

  filterComments(comments: GalleryComment[]): GalleryComment[] {
    const result: GalleryComment[] = [];
    for (let i = 0; i < comments.length; i++) {
      if (!this.isBlockedUser(comments[i].user)) {
        result.push(comments[i]);
      }
    }
    return result;
  }

  addUser(user: string, reason: string = '', sourceComment: string = '', addedAt: number = Date.now()): boolean {
    const normalizedUser = normalizeUser(user);
    if (normalizedUser.length === 0 || this.isBlockedUser(normalizedUser)) {
      return false;
    }
    const entry: CommentBlacklistEntry = {
      id: createEntryId(),
      user: normalizedUser,
      reason: reason.trim(),
      sourceComment: sourceComment.trim(),
      addedAt: normalizeAddedAt(addedAt)
    };
    const next = cloneEntries(this.entries);
    next.push(entry);
    next.sort(compareEntries);
    this.entries = next;
    syncTombstoneStore.recordClear(this.context, SYNC_SECTION_BLACKLIST, normalizedUser);
    this.changed();
    return true;
  }

  addFromComment(comment: GalleryComment): boolean {
    return this.addUser(comment.user, '', comment.content, Date.now());
  }

  removeEntry(id: string): boolean {
    const next: CommentBlacklistEntry[] = [];
    let removed = false;
    let removedUser = '';
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].id === id) {
        removed = true;
        removedUser = this.entries[i].user;
      } else {
        next.push(cloneEntry(this.entries[i]));
      }
    }
    if (!removed) {
      return false;
    }
    this.entries = next;
    syncTombstoneStore.recordDeletion(this.context, SYNC_SECTION_BLACKLIST, removedUser);
    this.changed();
    return true;
  }

  importBackupItems(items: CommentBlacklistBackupEntry[]): number {
    let count = 0;
    const next = cloneEntries(this.entries);
    for (let i = 0; i < items.length; i++) {
      const normalized = normalizeBackupEntry(items[i]);
      if (normalized === null || containsUser(next, normalized.user)) {
        continue;
      }
      next.push(normalized);
      count++;
    }
    if (count > 0) {
      next.sort(compareEntries);
      this.entries = next;
      this.changed();
    }
    return count;
  }

  async save(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    await this.saveSnapshot(context, this.getBackupItems());
  }

  private async load(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const raw = await prefs.get(VALUES_KEY, '[]');
      const parsed = JSON.parse(typeof raw === 'string' ? raw : '[]') as CommentBlacklistBackupEntry[];
      const next: CommentBlacklistEntry[] = [];
      if (Array.isArray(parsed)) {
        for (let i = 0; i < parsed.length; i++) {
          const entry = normalizeBackupEntry(parsed[i]);
          if (entry !== null && !containsUser(next, entry.user)) {
            next.push(entry);
          }
        }
      }
      next.sort(compareEntries);
      this.entries = next;
    } catch (error) {
      this.entries = [];
    }
    this.loaded = true;
    this.loadPromise = null;
    notifyBlacklistChanged();
  }

  private changed(): void {
    notifyBlacklistChanged();
    this.queueSave();
  }

  private queueSave(): void {
    const context = this.context;
    if (context === undefined || !this.loaded) {
      return;
    }
    const snapshot = this.getBackupItems();
    this.saveChain = this.saveChain.then(async () => {
      await this.saveSnapshot(context, snapshot);
    }).catch(() => {});
  }

  private async saveSnapshot(context: common.UIAbilityContext,
    snapshot: CommentBlacklistBackupEntry[]): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(VALUES_KEY, JSON.stringify(snapshot));
      await prefs.flush();
    } catch (error) {
      throw new Error(String(error));
    }
  }
}

function normalizeBackupEntry(stored: CommentBlacklistBackupEntry): CommentBlacklistEntry | null {
  const user = typeof stored.user === 'string' ? normalizeUser(stored.user) : '';
  if (user.length === 0) {
    return null;
  }
  return {
    id: typeof stored.id === 'string' && stored.id.length > 0 ? stored.id : createEntryId(),
    user: user,
    reason: typeof stored.reason === 'string' ? stored.reason.trim() : '',
    sourceComment: typeof stored.sourceComment === 'string' ? stored.sourceComment.trim() : '',
    addedAt: normalizeAddedAt(typeof stored.addedAt === 'number' ? stored.addedAt : Date.now())
  };
}

function normalizeUser(user: string): string {
  return user.replace(/\s+/g, ' ').trim();
}

function normalizeUserKey(user: string): string {
  return normalizeUser(user).toLocaleLowerCase();
}

function normalizeAddedAt(value: number): number {
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : Date.now();
}

function containsUser(entries: CommentBlacklistEntry[], user: string): boolean {
  const key = normalizeUserKey(user);
  for (let i = 0; i < entries.length; i++) {
    if (normalizeUserKey(entries[i].user) === key) {
      return true;
    }
  }
  return false;
}

function compareEntries(left: CommentBlacklistEntry, right: CommentBlacklistEntry): number {
  if (left.addedAt !== right.addedAt) {
    return left.addedAt - right.addedAt;
  }
  return left.user.localeCompare(right.user);
}

function createEntryId(): string {
  return 'blocked_' + Date.now().toString() + '_' + Math.floor(Math.random() * 1000000).toString();
}

function cloneEntry(entry: CommentBlacklistEntry): CommentBlacklistEntry {
  return {
    id: entry.id,
    user: entry.user,
    reason: entry.reason,
    sourceComment: entry.sourceComment,
    addedAt: entry.addedAt
  };
}

function cloneEntries(entries: CommentBlacklistEntry[]): CommentBlacklistEntry[] {
  return entries.map((entry: CommentBlacklistEntry): CommentBlacklistEntry => cloneEntry(entry));
}

function notifyBlacklistChanged(): void {
  const current = AppStorage.get<number>(COMMENT_BLACKLIST_REVISION_KEY);
  AppStorage.setOrCreate<number>(COMMENT_BLACKLIST_REVISION_KEY, current === undefined ? 1 : current + 1);
}

export const ehCommentBlacklistStore: EhCommentBlacklistStore = new EhCommentBlacklistStore();
