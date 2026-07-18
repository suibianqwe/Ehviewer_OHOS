import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { GalleryCategory, GalleryDetail, GalleryInfo, GalleryTagGroup } from '../model/GalleryModels';
import {
  ReaderPageTranslation,
  cloneReaderPageTranslation,
  cloneReaderPageTranslations
} from '../model/ReaderTranslationModels';
import { EhUrl } from './EhUrl';

const PREFERENCES_NAME: string = 'ehviewer_history';
const VALUES_KEY: string = 'items';
const VALUES_BACKUP_KEY: string = 'items_backup';
const READ_POSITIONS_KEY: string = 'read_positions';
const READ_POSITIONS_BACKUP_KEY: string = 'read_positions_backup';
const FILE_NAME: string = 'ehviewer_history.json';
const FILE_BACKUP_NAME: string = 'ehviewer_history.backup.json';
const HISTORY_DEFAULT_MAX_SIZE: number = 100;
const HISTORY_ABSOLUTE_MAX_SIZE: number = 20000;
const HISTORY_SAVE_DEBOUNCE_MS: number = 300;

interface StoredGalleryInfo {
  galleryUrl?: string;
  gid?: number;
  token?: string;
  title?: string;
  titleJpn?: string;
  thumb?: string;
  category?: number;
  posted?: string;
  uploader?: string;
  rating?: number;
  rated?: boolean;
  simpleLanguage?: string;
  simpleTags?: string[];
  pages?: number;
  thumbWidth?: number;
  thumbHeight?: number;
  favoriteSlot?: number;
  favoriteName?: string;
  tagList?: string[];
  detailTags?: StoredGalleryTagGroup[];
  detailLanguage?: string;
}

interface StoredGalleryTagGroup {
  namespace?: string;
  tags?: string[];
}

interface StoredReadPosition {
  gid?: number;
  pageIndex?: number;
  updatedAt?: number;
  readerTranslations?: ReaderPageTranslation[];
}

interface ReadPosition {
  gid: number;
  pageIndex: number;
  updatedAt: number;
  readerTranslations: ReaderPageTranslation[];
}

interface HistoryBackupFile {
  version?: number;
  items?: StoredGalleryInfo[];
  readPositions?: StoredReadPosition[];
  updatedAt?: number;
}

interface HistoryFileState {
  items: GalleryInfo[];
  readPositions: ReadPosition[];
}

interface StoredGalleryUrlParts {
  gid: number;
  token: string;
}

export class EhHistoryStore {
  private items: GalleryInfo[] = [];
  private readPositions: ReadPosition[] = [];
  private context: common.UIAbilityContext | undefined = undefined;
  private saveChain: Promise<void> = Promise.resolve();
  private saveTimer: number = -1;
  private loaded: boolean = false;
  private loadPromise: Promise<void> | null = null;

  getItems(): GalleryInfo[] {
    return cloneGalleryInfos(this.items);
  }

  addGallery(gallery: GalleryInfo, maxSize: number = HISTORY_DEFAULT_MAX_SIZE): void {
    if (gallery.gid <= 0 || gallery.token.length === 0) {
      return;
    }

    const next: GalleryInfo[] = [cloneGalleryInfo(gallery)];
    const limit = Math.min(HISTORY_ABSOLUTE_MAX_SIZE, Math.max(1, maxSize));
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid !== gallery.gid) {
        next.push(cloneGalleryInfo(this.items[i]));
      }
      if (next.length >= limit) {
        break;
      }
    }
    this.items = next;
    this.queueSave();
  }

  updateGallery(gallery: GalleryInfo): boolean {
    if (gallery.gid <= 0 || gallery.token.length === 0) {
      return false;
    }
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid === gallery.gid) {
        this.items[i] = cloneGalleryInfo(gallery);
        this.queueSave();
        return true;
      }
    }
    return false;
  }

  trim(maxSize: number = HISTORY_DEFAULT_MAX_SIZE): void {
    const limit = Math.min(HISTORY_ABSOLUTE_MAX_SIZE, Math.max(1, maxSize));
    if (this.items.length > limit) {
      this.items.splice(limit);
      this.pruneReadPositions();
      this.queueSave();
    }
  }

  removeGallery(gid: number): void {
    const next: GalleryInfo[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid !== gid) {
        next.push(cloneGalleryInfo(this.items[i]));
      }
    }
    this.items = next;
    this.removeReadPosition(gid);
    this.queueSave();
  }

  clear(): void {
    this.items = [];
    this.readPositions = [];
    this.queueSave();
  }

  resetAllReadPositions(): void {
    this.readPositions = [];
    this.queueSave();
  }

  getReadPage(gid: number): number {
    for (let i = 0; i < this.readPositions.length; i++) {
      if (this.readPositions[i].gid === gid) {
        return this.readPositions[i].pageIndex;
      }
    }
    return -1;
  }

  setReadPage(gid: number, pageIndex: number): void {
    if (gid <= 0 || pageIndex < 0) {
      return;
    }
    for (let i = 0; i < this.readPositions.length; i++) {
      if (this.readPositions[i].gid === gid) {
        this.readPositions[i].pageIndex = pageIndex;
        this.readPositions[i].updatedAt = Date.now();
        this.queueSave();
        return;
      }
    }
    this.readPositions.push({
      gid: gid,
      pageIndex: pageIndex,
      updatedAt: Date.now(),
      readerTranslations: []
    });
    this.queueSave();
  }

  getReaderTranslation(gid: number, pageIndex: number): ReaderPageTranslation | null {
    for (let i = 0; i < this.readPositions.length; i++) {
      if (this.readPositions[i].gid !== gid) {
        continue;
      }
      for (let j = 0; j < this.readPositions[i].readerTranslations.length; j++) {
        if (this.readPositions[i].readerTranslations[j].pageIndex === pageIndex) {
          return cloneReaderPageTranslation(this.readPositions[i].readerTranslations[j]);
        }
      }
    }
    return null;
  }

  setReaderTranslation(gid: number, translation: ReaderPageTranslation): void {
    if (gid <= 0 || translation.pageIndex < 0) {
      return;
    }
    for (let i = 0; i < this.readPositions.length; i++) {
      if (this.readPositions[i].gid === gid) {
        this.replaceReaderTranslation(this.readPositions[i], translation);
        this.readPositions[i].updatedAt = Date.now();
        this.queueSave();
        return;
      }
    }
    this.readPositions.push({
      gid: gid,
      pageIndex: translation.pageIndex,
      updatedAt: Date.now(),
      readerTranslations: [cloneReaderPageTranslation(translation)]
    });
    this.queueSave();
  }

  private replaceReaderTranslation(position: ReadPosition, translation: ReaderPageTranslation): void {
    const next: ReaderPageTranslation[] = [];
    let replaced = false;
    for (let i = 0; i < position.readerTranslations.length; i++) {
      if (position.readerTranslations[i].pageIndex === translation.pageIndex) {
        next.push(cloneReaderPageTranslation(translation));
        replaced = true;
      } else {
        next.push(cloneReaderPageTranslation(position.readerTranslations[i]));
      }
    }
    if (!replaced) {
      next.push(cloneReaderPageTranslation(translation));
    }
    next.sort((left: ReaderPageTranslation, right: ReaderPageTranslation) => left.pageIndex - right.pageIndex);
    position.readerTranslations = next;
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    if (this.loadPromise !== null) {
      await this.loadPromise;
      return;
    }
    this.loadPromise = this.loadNow(context);
    try {
      await this.loadPromise;
    } finally {
      this.loadPromise = null;
    }
  }

  async ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    if (this.loaded) {
      return;
    }
    await this.load(context);
  }

  private async loadNow(context: common.UIAbilityContext): Promise<void> {
    try {
      const main = this.readFile(context.filesDir + '/' + FILE_NAME);
      const backup = this.readFile(context.filesDir + '/' + FILE_BACKUP_NAME);
      const chosen = main.items.length > 0 || main.readPositions.length > 0 ? main : backup;
      this.items = chosen.items;
      this.readPositions = chosen.readPositions;
      if (this.items.length === 0 && this.readPositions.length === 0) {
        await this.restoreFromLegacyPreferences(context);
      }
      this.loaded = true;
      if (this.items.length > 0 || this.readPositions.length > 0) {
        await this.saveNow(context);
      }
    } catch (error) {
      throw new Error(String(error));
    }
  }

  async save(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    const pending = this.saveChain.then(() => this.saveNow(context));
    this.saveChain = pending.catch(() => {});
    await pending;
  }

  private queueSave(): void {
    const context = this.context;
    if (context === undefined) {
      return;
    }
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = -1;
      this.saveChain = this.saveChain.then(() => this.saveNow(context)).catch(() => {});
    }, HISTORY_SAVE_DEBOUNCE_MS) as number;
  }

  private async saveNow(context: common.UIAbilityContext): Promise<void> {
    try {
      await this.saveFile(context, this.serializeStoredItems(), this.serializeReadPositions());
    } catch (error) {
      throw new Error(String(error));
    }
  }

  private async restoreFromLegacyPreferences(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const raw = await prefs.get(VALUES_KEY, '');
      const rawBackup = await prefs.get(VALUES_BACKUP_KEY, '');
      const rawPositions = await prefs.get(READ_POSITIONS_KEY, '');
      const rawPositionsBackup = await prefs.get(READ_POSITIONS_BACKUP_KEY, '');
      this.items = this.parseStoredItems(raw, rawBackup);
      this.readPositions = this.parseReadPositions(rawPositions, rawPositionsBackup);
    } catch (error) {
      this.items = [];
      this.readPositions = [];
    }
  }

  private readFile(path: string): HistoryFileState {
    try {
      const parsed = JSON.parse(fs.readTextSync(path)) as HistoryBackupFile;
      return {
        items: this.parseStoredItemsOnce(JSON.stringify(parsed.items === undefined ? [] : parsed.items)),
        readPositions: this.parseReadPositionsOnce(JSON.stringify(parsed.readPositions === undefined ? [] :
          parsed.readPositions))
      };
    } catch (error) {
      return { items: [], readPositions: [] };
    }
  }

  private async saveFile(context: common.UIAbilityContext, items: StoredGalleryInfo[],
    readPositions: StoredReadPosition[]): Promise<void> {
    const payload = JSON.stringify({
      version: 1,
      items: items,
      readPositions: readPositions,
      updatedAt: Date.now()
    });
    await writeTextFileQuietly(context.filesDir + '/' + FILE_NAME, payload);
    await writeTextFileQuietly(context.filesDir + '/' + FILE_BACKUP_NAME, payload);
  }

  private serializeStoredItems(): StoredGalleryInfo[] {
    const stored: StoredGalleryInfo[] = [];
    const count = Math.min(this.items.length, HISTORY_ABSOLUTE_MAX_SIZE);
    for (let i = 0; i < count; i++) {
      stored.push(galleryInfoToStored(this.items[i]));
    }
    return stored;
  }

  private serializeReadPositions(): StoredReadPosition[] {
    const positions: StoredReadPosition[] = [];
    for (let i = 0; i < this.readPositions.length; i++) {
      positions.push({
        gid: this.readPositions[i].gid,
        pageIndex: this.readPositions[i].pageIndex,
        updatedAt: this.readPositions[i].updatedAt,
        readerTranslations: cloneReaderPageTranslations(this.readPositions[i].readerTranslations)
      });
    }
    return positions;
  }

  private parseStoredItems(raw: preferences.ValueType, backup: preferences.ValueType): GalleryInfo[] {
    const fromMain = this.parseStoredItemsOnce(raw);
    if (fromMain.length > 0 || typeof backup !== 'string' || backup.length === 0) {
      return fromMain;
    }
    return this.parseStoredItemsOnce(backup);
  }

  private parseStoredItemsOnce(raw: preferences.ValueType): GalleryInfo[] {
    const items: GalleryInfo[] = [];
    if (typeof raw !== 'string' || raw.length === 0) {
      return items;
    }
    try {
      const parsed = JSON.parse(raw) as StoredGalleryInfo[];
      if (!Array.isArray(parsed)) {
        return items;
      }
      for (let i = 0; i < parsed.length; i++) {
        const item = storedToGalleryInfo(parsed[i]);
        if (item.gid > 0 && item.token.length > 0) {
          items.push(item);
        }
      }
    } catch (error) {
    }
    return items;
  }

  private parseReadPositions(raw: preferences.ValueType, backup: preferences.ValueType): ReadPosition[] {
    const fromMain = this.parseReadPositionsOnce(raw);
    if (fromMain.length > 0 || typeof backup !== 'string' || backup.length === 0) {
      return fromMain;
    }
    return this.parseReadPositionsOnce(backup);
  }

  private parseReadPositionsOnce(raw: preferences.ValueType): ReadPosition[] {
    const positions: ReadPosition[] = [];
    if (typeof raw !== 'string' || raw.length === 0) {
      return positions;
    }
    try {
      const parsed = JSON.parse(raw) as StoredReadPosition[];
      if (!Array.isArray(parsed)) {
        return positions;
      }
      for (let i = 0; i < parsed.length; i++) {
        const item = storedToReadPosition(parsed[i]);
        if (item.gid > 0 && item.pageIndex >= 0) {
          positions.push(item);
        }
      }
    } catch (error) {
    }
    return positions;
  }

  private removeReadPosition(gid: number): void {
    const next: ReadPosition[] = [];
    for (let i = 0; i < this.readPositions.length; i++) {
      if (this.readPositions[i].gid !== gid) {
        next.push(this.readPositions[i]);
      }
    }
    this.readPositions = next;
  }

  private pruneReadPositions(): void {
    const gids: number[] = [];
    for (let i = 0; i < this.items.length; i++) {
      gids.push(this.items[i].gid);
    }
    const next: ReadPosition[] = [];
    for (let i = 0; i < this.readPositions.length; i++) {
      if (gids.indexOf(this.readPositions[i].gid) >= 0) {
        next.push(this.readPositions[i]);
      }
    }
    this.readPositions = next;
  }
}

function storedToGalleryInfo(item: StoredGalleryInfo): GalleryInfo {
  const urlParts = parseStoredGalleryUrl(item.galleryUrl);
  const token = typeof item.token === 'string' && item.token.length > 0 ? item.token : urlParts.token;
  return {
    gid: typeof item.gid === 'number' && item.gid > 0 ? item.gid : urlParts.gid,
    token: token,
    title: typeof item.title === 'string' ? item.title : '',
    titleJpn: item.titleJpn,
    thumb: item.thumb,
    category: typeof item.category === 'number' ? item.category : GalleryCategory.Unknown,
    posted: item.posted,
    uploader: item.uploader,
    rating: typeof item.rating === 'number' ? item.rating : -1,
    rated: typeof item.rated === 'boolean' ? item.rated : false,
    simpleLanguage: item.simpleLanguage,
    simpleTags: item.simpleTags,
    pages: typeof item.pages === 'number' ? item.pages : 0,
    thumbWidth: typeof item.thumbWidth === 'number' ? item.thumbWidth : 0,
    thumbHeight: typeof item.thumbHeight === 'number' ? item.thumbHeight : 0,
    favoriteSlot: typeof item.favoriteSlot === 'number' ? item.favoriteSlot : -2,
    favoriteName: item.favoriteName,
    tagList: item.tagList,
    detailTags: storedToGalleryTagGroups(item.detailTags),
    detailLanguage: item.detailLanguage
  };
}

function parseStoredGalleryUrl(url: string | undefined): StoredGalleryUrlParts {
  if (url === undefined || url.length === 0) {
    return { gid: 0, token: '' };
  }
  const marker = '/g/';
  const markerIndex = url.indexOf(marker);
  if (markerIndex < 0) {
    return { gid: 0, token: '' };
  }
  const rest = url.substring(markerIndex + marker.length);
  const parts = rest.split('/');
  if (parts.length < 2) {
    return { gid: 0, token: '' };
  }
  const gid = Number.parseInt(parts[0]);
  if (Number.isNaN(gid) || gid <= 0) {
    return { gid: 0, token: '' };
  }
  return { gid: gid, token: parts[1] };
}

function galleryInfoToStored(item: GalleryInfo): StoredGalleryInfo {
  const tags = galleryDetailTags(item);
  const language = galleryDetailLanguage(item);
  return {
    galleryUrl: EhUrl.getGalleryDetailUrl(item.gid, item.token),
    gid: item.gid,
    token: item.token,
    title: item.title,
    titleJpn: item.titleJpn,
    thumb: item.thumb,
    category: item.category,
    posted: item.posted,
    uploader: item.uploader,
    rating: item.rating,
    rated: item.rated,
    simpleLanguage: item.simpleLanguage,
    simpleTags: item.simpleTags,
    pages: item.pages,
    thumbWidth: item.thumbWidth,
    thumbHeight: item.thumbHeight,
    favoriteSlot: item.favoriteSlot,
    favoriteName: item.favoriteName,
    tagList: item.tagList,
    detailTags: galleryTagGroupsToStored(tags),
    detailLanguage: language
  };
}

function storedToReadPosition(item: StoredReadPosition): ReadPosition {
  return {
    gid: typeof item.gid === 'number' ? item.gid : 0,
    pageIndex: typeof item.pageIndex === 'number' ? item.pageIndex : -1,
    updatedAt: typeof item.updatedAt === 'number' ? item.updatedAt : 0,
    readerTranslations: cloneReaderPageTranslations(item.readerTranslations)
  };
}

function cloneGalleryInfos(items: GalleryInfo[]): GalleryInfo[] {
  const cloned: GalleryInfo[] = [];
  for (let i = 0; i < items.length; i++) {
    cloned.push(cloneGalleryInfo(items[i]));
  }
  return cloned;
}

function cloneGalleryInfo(item: GalleryInfo): GalleryInfo {
  const tags = galleryDetailTags(item);
  const language = galleryDetailLanguage(item);
  return {
    gid: item.gid,
    token: item.token,
    title: item.title,
    titleJpn: item.titleJpn,
    thumb: item.thumb,
    category: item.category,
    posted: item.posted,
    uploader: item.uploader,
    rating: item.rating,
    rated: item.rated,
    simpleLanguage: item.simpleLanguage,
    simpleTags: item.simpleTags,
    pages: item.pages,
    thumbWidth: item.thumbWidth,
    thumbHeight: item.thumbHeight,
    favoriteSlot: item.favoriteSlot,
    favoriteName: item.favoriteName,
    tagList: item.tagList,
    detailTags: cloneGalleryTagGroups(tags),
    detailLanguage: language
  };
}

function galleryDetailTags(item: GalleryInfo): GalleryTagGroup[] | undefined {
  const detail = item as GalleryDetail;
  if (detail.tags !== undefined && detail.tags.length > 0) {
    return detail.tags;
  }
  return item.detailTags;
}

function galleryDetailLanguage(item: GalleryInfo): string | undefined {
  const detail = item as GalleryDetail;
  if (detail.language !== undefined && detail.language.length > 0) {
    return detail.language;
  }
  return item.detailLanguage;
}

function storedToGalleryTagGroups(groups: StoredGalleryTagGroup[] | undefined): GalleryTagGroup[] | undefined {
  if (groups === undefined || !Array.isArray(groups)) {
    return undefined;
  }
  const next: GalleryTagGroup[] = [];
  for (let i = 0; i < groups.length; i++) {
    const group = groups[i];
    const namespace: string = typeof group.namespace === 'string' ? group.namespace : '';
    const tags: string[] = Array.isArray(group.tags) ? group.tags as string[] : [];
    if (namespace.length > 0 && tags.length > 0) {
      next.push({ namespace: namespace, tags: cloneStringArray(tags) });
    }
  }
  return next.length > 0 ? next : undefined;
}

function galleryTagGroupsToStored(groups: GalleryTagGroup[] | undefined): StoredGalleryTagGroup[] | undefined {
  if (groups === undefined) {
    return undefined;
  }
  const next: StoredGalleryTagGroup[] = [];
  for (let i = 0; i < groups.length; i++) {
    next.push({
      namespace: groups[i].namespace,
      tags: cloneStringArray(groups[i].tags)
    });
  }
  return next;
}

function cloneGalleryTagGroups(groups: GalleryTagGroup[] | undefined): GalleryTagGroup[] | undefined {
  if (groups === undefined) {
    return undefined;
  }
  const next: GalleryTagGroup[] = [];
  for (let i = 0; i < groups.length; i++) {
    next.push({
      namespace: groups[i].namespace,
      tags: cloneStringArray(groups[i].tags)
    });
  }
  return next;
}

function cloneStringArray(values: string[]): string[] {
  const next: string[] = [];
  for (let i = 0; i < values.length; i++) {
    next.push(values[i]);
  }
  return next;
}

async function writeTextFileQuietly(path: string, value: string): Promise<void> {
  let file: fs.File | null = null;
  try {
    file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    await fs.write(file.fd, value);
  } catch (error) {
  } finally {
    if (file !== null) {
      try {
        await fs.close(file);
      } catch (error) {
      }
    }
  }
}

export const ehHistoryStore: EhHistoryStore = new EhHistoryStore();
